
package Moonpig::Ledger::Accountant;
use Moose;

with 'Role::Subsystem' => {
  ident  => 'ledger-accountant',
  type   => 'Moonpig::Role::Ledger',
  what   => 'ledger',
  weak_ref => 0,
};

# Each transfer has a source, destination, and guid.
# Each transfer is listed exactly once in each of the three following hashes:
# By source in %by_from, by destination in %by_to, and by GUID in %by_id.


# This is a hash whose keys are GUIDs of objects such as banks or
# consumers, and whose values are arrays of transfers.  For object X,
# all transfers from X are listed in $by_from{$X->guid}.
has by_from => (
  is => 'ro',
  isa => 'HashRef',
  default => sub { {} },
);

# Like %by_from, but backwards
has by_to => (
  is => 'ro',
  isa => 'HashRef',
  default => sub { {} },
);

# Keys here are transfer GUIDs and values are transfer objects
has by_id => (
  is => 'ro',
  isa => 'HashRef',
  default => sub { {} },
);

no Moose;
1;

