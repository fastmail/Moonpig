package Moonpig::Role::Consumer;
use Moose::Role;
with(
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HasGuid',
);

use MooseX::SetOnce;
use Moonpig::Types qw(Ledger Millicents);

use namespace::autoclean;

has bank => (
  reader => 'bank',
  writer => '_set_bank',
  does   => 'Moonpig::Role::Bank',
  traits => [ qw(SetOnce) ],
  predicate => 'has_bank',
);

before _set_bank => sub {
  my ($self, $bank) = @_;

  unless ($self->ledger->guid eq $bank->ledger->guid) {
    confess sprintf(
      "cannot associate consumer from ledger %s with bank from ledger %s",
      $self->ledger->guid,
      $bank->ledger->guid,
    );
  }
};

has replacement => (
  is   => 'rw',
  does => 'Moonpig::Role::Consumer',
  traits    => [ qw(SetOnce) ],
  predicate => 'has_replacement',
);

# mechanism to get xfers

1;
