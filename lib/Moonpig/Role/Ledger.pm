package Moonpig::Role::Ledger;
use Moose::Role;
use MooseX::SetOnce;

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef);

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
  is   => 'ro',
  isa  => ArrayRef[ role_type('Moonpig::Role::Bank') ],
  default => sub { [] },
  # traits  => [ qw(Array) ],
  # handles => {
  #   'add_bank' => 'push',
  # }
);

has consumers => (
  is   => 'ro',
  isa  => ArrayRef[ role_type('Moonpig::Role::Consumer') ],
  default => sub { [] },
  # traits  => [ qw(Array) ],
  # handles => {
  #   'add_bank' => 'push',
  # }
);

1;

