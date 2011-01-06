package Moonpig::Role::Ledger;
use Moose::Role;
with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

use Moose::Util::TypeConstraints;
use MooseX::SetOnce;
use MooseX::Types::Moose qw(ArrayRef HashRef);

use Moonpig;
use Moonpig::Events::Handler::Method;
use Moonpig::Events::Handler::Missing;
use Moonpig::Types qw(Credit);

use Moonpig::Logger '$Logger';
use Moonpig::MKits;
use Moonpig::Util qw(event);

use Moonpig::Behavior::EventHandlers;
use Sub::Install ();

use namespace::autoclean;

# Should this be plural?  Or what?  Maybe it's a ContactManager subsystem...
# https://trac.pobox.com/wiki/Billing/DB says that there is *one* contact which
# has *one* address and *one* name but possibly many email addresses.
# -- rjbs, 2010-10-12
has contact => (
  is   => 'ro',
  does => 'Moonpig::Role::Contact',
  required => 1,
);

has banks => (
  reader  => '_banks',
  isa     => HashRef[ role_type('Moonpig::Role::Bank') ],
  default => sub { {} },
  traits  => [ qw(Hash) ],
  handles => {
    banks     => 'values',
    _has_bank => 'exists',
    _set_bank => 'set',
  },
);

has consumers => (
  reader  => '_consumers',
  isa     => HashRef[ role_type('Moonpig::Role::Consumer') ],
  default => sub { {} },
  traits  => [ qw(Hash) ],
  handles => {
    consumers     => 'values',
    _has_consumer => 'exists',
    _set_consumer => 'set',
  },
);

has credits => (
  isa     => ArrayRef[ Credit ],
  default => sub { [] },
  traits  => [ qw(Array) ],
  handles => {
    credits    => 'elements',
    _add_credit => 'push',
  },
);

sub add_credit {
  my ($self, $class, $arg) = @_;
  $arg ||= {};

  local $arg->{ledger} = $self;
  my $credit = $class->new($arg);
  $self->_add_credit($credit);

  return $credit;
}

for my $thing (qw(bank consumer)) {
  my $predicate = "_has_$thing";
  my $setter = "_set_$thing";

  Sub::Install::install_sub({
    as   => "add_$thing",
    code => sub {
      my ($self, $class, $arg) = @_;
      $arg ||= {};

      local $arg->{ledger} = $self;

      my $value = $class->new($arg);

      confess sprintf "%s with guid %s already present", $thing, $value->guid
        if $self->$predicate($value->guid);

      $self->$setter($value->guid, $value);
    },
  });
}

for my $thing (qw(journal invoice)) {
  my $role   = sprintf "Moonpig::Role::%s", ucfirst $thing;
  my $class  = sprintf "Moonpig::%s::Basic", ucfirst $thing;
  my $plural = "${thing}s";
  my $reader = "_$plural";

  has $plural => (
    reader  => $reader,
    isa     => ArrayRef[ role_type($role) ],
    default => sub { [] },
    traits  => [ qw(Array) ],
    handles => {
      $plural        => 'elements',
      "_push_$thing" => 'push',
    },
  );

  my $_ensure_one_thing = sub {
    my ($self) = @_;

    my $things = $self->$reader;
    return if @$things and $things->[-1]->is_open;

    Class::MOP::load_class($class);
    require Moonpig::CostTree::Basic;

    my $thing = $class->new({
      cost_tree => Moonpig::CostTree::Basic->new(),
      ledger    => $self,
    });

    push @$things, $thing;
    return;
  };

  has "current_$thing" => (
    is   => 'ro',
    does => role_type($role),
    lazy => 1,
    default => sub {
      my ($self) = @_;
      $self->$_ensure_one_thing;
      $self->$reader->[-1];
    }
  );
}

sub process_credits {
  my ($self) = @_;

  my @credits = $self->credits;

  # XXX: These need to be processed in order. -- rjbs, 2010-12-02
  for my $invoice (@{ $self->_invoices }) {
    next if $invoice->is_paid;

    @credits = grep { $_->unapplied_amount } @credits;

    my $to_pay = $invoice->total_amount;

    my @to_apply;

    # XXX: These need to be processed in order, too. -- rjbs, 2010-12-02
    CREDIT: for my $credit (@credits) {
      my $credit_amount = $credit->unapplied_amount;
      my $apply_amt = $credit_amount >= $to_pay ? $to_pay : $credit_amount;

      push @to_apply, {
        credit => $credit,
        amount => $apply_amt,
      };

      $to_pay -= $apply_amt;

      $Logger->log([
        "will apply %s from credit %s; %s left to pay",
        $apply_amt,
        $credit->guid,
        $to_pay,
      ]);

      last CREDIT if $to_pay == 0;
    }

    if ($to_pay == 0) {
      for my $to_apply (@to_apply) {
        Moonpig::CreditApplication->new({
          credit  => $to_apply->{credit},
          payable => $invoice,
          amount  => $to_apply->{amount},
        });
      }

      $Logger->log([ "marking invoice %s paid", $invoice->guid ]);
      $invoice->handle_event(event('paid'));
      $invoice->mark_paid;
    } else {
      # We can't successfully pay this invoice, so stop processing.
      return;
    }
  }
}

implicit_event_handlers {
  return {
    'heartbeat' => {
      redistribute => Moonpig::Events::Handler::Method->new('_reheartbeat'),
    },

    'send-invoice' => {
      default => Moonpig::Events::Handler::Method->new('_send_invoice'),
    },

    'send-mkit' => {
      default => Moonpig::Events::Handler::Method->new('_send_mkit'),
    },

    'contact-humans' => {
      default => Moonpig::Events::Handler::Missing->new,
    },
  };
};

sub _send_invoice {
  my ($self, $event) = @_;

  my $invoice = $event->payload->{invoice};

  $Logger->log([
    "sending invoice %s to contacts of ledger %s",
    $invoice->guid,
    $self->guid,
  ]);

  $self->handle_event(event('send-mkit', {
    kit => 'generic',
    arg => {
      subject => sprintf("INVOICE %s IS DUE", $invoice->guid),
      body    => sprintf("YOU OWE US %s\n", $invoice->total_amount),

      # This should get names with addresses, unlike the contact-humans
      # handler, which wants envelope recipients.
      to_addresses => [ $self->contact->email_addresses ],
    },
  }));
}

sub _reheartbeat {
  my ($self, $event) = @_;

  for my $target (
    # $self->contact,
    $self->banks,
    $self->consumers,
    $self->invoices,
    $self->journals,
  ) {
    $target->handle_event($event);
  }
}

sub _send_mkit {
  my ($self, $event, $arg) = @_;

  my $to   = [ $self->contact->email_addresses ];
  my $from = 'devnull@example.com';

  my $email = Moonpig::MKits->kit($event->payload->{kit})->assemble(
    $event->payload->{arg},
  );

  Moonpig->env->handle_event(event('send-email' => {
    email => $email,
    env   => { to => $to, from => $from },
  }));
}

after BUILD => sub {
  my ($self) = @_;
  $Logger->log([
    'created new ledger %s (%s)',
    $self->guid,
    $self->meta->name,
  ]);
};

1;
