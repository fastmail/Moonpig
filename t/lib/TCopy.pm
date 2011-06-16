package t::lib::TCopy;
use Moose;
use Moonpig::Trait::Copy;

has yes => (
  is => 'ro',
  traits => [ 'Copy' ],
  default => "yes",
);

has no => (
  is => 'ro',
  traits => [ ],
  default => "no",
);

1;
