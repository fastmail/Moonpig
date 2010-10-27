package Moonpig::X;
use Moose;

# We do not use Throwable::X, because we want a way to provide manual payload
# content for one-off exceptions without subclassing.  I will add that to
# Throwable::X's composition. -- rjbs, 2010-10-27
# with 'Throwable::X';

has payload => (
  is  => 'ro',
  isa => 'HashRef',
  default => sub {  {}  },
);

with(
  'Throwable',
  'Throwable::X::WithIdent',
  'Throwable::X::WithTags',

  'Throwable::X::WithMessage::Errf' => {
    default  => sub { $_[0]->ident },
    lazy     => 1,
  },

  'MooseX::OneArgNew' => {
    type     => 'Throwable::X::_VisibleStr',
    init_arg => 'ident',
  },
);

has is_public => (
  is  => 'ro',
  isa => 'Bool',
  init_arg => 'public',
  default  => 0,
);

use namespace::autoclean;


1;
