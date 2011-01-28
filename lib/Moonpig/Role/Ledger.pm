package Moonpig::Role::Ledger;
# ABSTRACT: the fundamental hub of a billable account

use Moose::Role;
with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::Dunner',
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
use Moonpig::Util qw(class event);

use Data::GUID qw(guid_string);
use List::Util qw(reduce);

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

for my $thing (qw(bank consumer refund)) {
  my $predicate = "_has_$thing";
  my $setter = "_set_$thing";

  has $thing => (
    reader  => "_${thing}s",
    isa     => HashRef[ role_type('Moonpig::Role::' . ucfirst $thing) ],
    default => sub { {} },
    traits  => [ qw(Hash) ],
    handles => {
      "${thing}s"   => 'values',
      "_has_$thing" => 'exists',
      "_set_$thing" => 'set',
      "_get_$thing" => 'get',
    },
  );
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

      $value->handle_event(event('created'));

      return $value;
    },
  });
}

for my $thing (qw(journal invoice)) {
  my $role   = sprintf "Moonpig::Role::%s", ucfirst $thing;
  my $class  = class(ucfirst $thing);
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

    my $thing = $class->new({
      charge_tree => class('ChargeTree')->new,
      ledger      => $self,
    });

    push @$things, $thing;
    return;
  };

  Sub::Install::install_sub({
    as   => "current_$thing",
    code => sub {
      my ($self) = @_;
      $self->$_ensure_one_thing;
      $self->$reader->[-1];
    }
  });
}

sub latest_invoice {
  my ($self) = @_;
  my $latest = (
    sort { $b->created_at <=> $a->created_at
        || $b->guid       cmp $a->guid # incredibly unlikely, but let's plan
         } $self->invoices
  )[0];

  return $latest;
}

sub process_credits {
  my ($self) = @_;

  # $self->_collect_spare_change;

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
        "will apply %s from %s; %s left to pay",
        $apply_amt,
        $credit->ident,
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

      $Logger->log([ "marking %s paid", $invoice->ident ]);
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

    'send-mkit' => {
      default => Moonpig::Events::Handler::Method->new('_send_mkit'),
    },

    'contact-humans' => {
      default => Moonpig::Events::Handler::Missing->new,
    },
  };
};

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

  $self->perform_dunning;
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

# {
#   service_uri => [ consumer_guid, ... ],
#   ...
# }
has _active_service_consumers => (
  is  => 'ro',
  isa => HashRef,
  init_arg => undef,
  default  => sub {  {}  },
);

sub active_consumers_for_service {
  my ($self, $service_uri) = @_;

  my $reg = $self->_active_service_consumers;
  return unless my $svc = $reg->{ $service_uri };

  my @consumers = map {; $self->_get_consumer($_) } keys %$svc;

  return @consumers;
}

sub _is_consumer_active {
  my ($self, $consumer) = @_;

  my $reg = $self->_active_service_consumers;
  return unless my $svc = $reg->{ $consumer->service_uri };

  return $svc->{ $consumer->guid };
}

sub mark_consumer_active__ {
  my ($self, $consumer) = @_;

  my $reg = $self->_active_service_consumers;

  $reg->{ $consumer->service_uri } ||= {};

  $reg->{ $consumer->service_uri }{ $consumer->guid } = 1;

  return;
}

sub mark_consumer_inactive__ {
  my ($self, $consumer) = @_;

  my $reg = $self->_active_service_consumers;

  return unless $reg->{ $consumer->service_uri };

  delete $reg->{ $consumer->service_uri }{ $consumer->guid };

  return;
}

sub failover_active_consumer__ {
  my ($self, $consumer) = @_;

  my $reg = $self->_active_service_consumers;

  $reg->{ $consumer->service_uri } ||= {};

  Moonpig::X->throw("can't failover inactive service")
    unless delete $reg->{ $consumer->service_uri }{ $consumer->guid };

  $consumer->replacement->become_active;

  return;
}

sub _collect_spare_change {
  my ($self) = @_;

  my @consumers = grep {; $_->has_bank && ! $_->is_expired } $self->consumers;
  my %consider  = map  {; $_->[0]->guid => $_ }
                  grep {; $_->[1] }
                  map  {; [ $_, $_->unapplied_amount ] }
                  $self->banks;

  delete $consider{ $_->bank->guid } for @consumers;

  my $total = reduce { $a + $b } 0, map { $_->[1] } values %consider;

  my $credit = $self->add_credit(
    class('Credit::Courtesy'),
    {
      amount => $total,
      reason => "collecting spare change", # XXX ? -- rjbs, 2011-01-28
    },
  );

  for my $bank_pair (values %consider) {
    my ($bank, $amount) = @$bank_pair;

    Moonpig::Transfer::BankCredit->new({
      bank    => $bank,
      credit  => $credit,
      amount  => $amount,
    });
  }

  warn "$total\n";
}

1;
