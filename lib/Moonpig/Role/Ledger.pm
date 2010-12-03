package Moonpig::Role::Ledger;
use Moose::Role;
with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::HandlesEvents',
);

use Moose::Util::TypeConstraints;
use MooseX::SetOnce;
use MooseX::Types::Moose qw(ArrayRef HashRef);

use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(Credit);

use Moonpig::Logger '$Logger';
use Moonpig::Util qw(event);

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
    _has_bank => 'exists',
    _set_bank    => 'set',
  },
);

has consumers => (
  reader  => '_consumers',
  isa     => HashRef[ role_type('Moonpig::Role::Consumer') ],
  default => sub { {} },
  traits  => [ qw(Hash) ],
  handles => {
    _has_consumer => 'exists',
    _set_consumer    => 'set',
  },
);

has credits => (
  isa     => ArrayRef[ Credit ],
  default => sub { [] },
  traits  => [ qw(Array) ],
  handles => {
    credits    => 'elements',
    add_credit => 'push',
  },
);

for my $thing (qw(bank consumer)) {
  Sub::Install::install_sub({
    as   => "add_$thing",
    code => sub {
      my ($self, $value) = @_;

      my $predicate = "_has_$thing";
      confess sprintf "%s with guid %s already present", $thing, $value->guid
        if $self->$predicate($value->guid);

      if ($value->ledger->guid ne $self->guid) {
        confess(sprintf "can't add $thing for ledger %s to ledger %s",
          $value->ledger->guid,
          $self->guid
        );
      }

      my $setter = "_set_$thing";
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
      $invoice->handle_event(event('invoice-paid'));
      $invoice->mark_paid;
    } else {
      # We can't successfully pay this invoice, so stop processing.
      return;
    }
  }
}

1;
