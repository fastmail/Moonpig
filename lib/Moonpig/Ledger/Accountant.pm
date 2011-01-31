
package Moonpig::Ledger::Accountant;
use Moose;

with 'Role::Subsystem' => {
  ident  => 'ledger-accountant',
  type   => 'Moonpig::Role::Ledger',
  what   => 'ledger',
  weak_ref => 0,
};

1;

