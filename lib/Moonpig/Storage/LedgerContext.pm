package Moonpig::Storage::LedgerContext;
use Moose;

use Carp qw(confess croak);
use namespace::autoclean;

# Map names to actual ledger objects
has _ledgers => (
  is => 'ro',
  isa => 'HashRef',
  traits => [ 'Hash' ],
  handles => {
    get => 'get',
    has => 'exists',
  },
);

sub put {
  my ($self, $name, $ledger) = @_;
  if ($self->has($name)) {
    return if $ledger == $self->get($name);
    croak "Ledger context already has a ledger named '$name'";
  }
  $self->_ledgers->{$name} = $ledger;
}

1;

