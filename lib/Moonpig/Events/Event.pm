package Moonpig::Events::Event;
use Moose;

use Moonpig::Types qw(EventName);

use namespace::autoclean;

has payload => (
  is  => 'ro',
  isa => 'HashRef',
  default => sub {  {}  },
);

with(
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

has '+ident' => (
  isa => EventName,
);

1;
