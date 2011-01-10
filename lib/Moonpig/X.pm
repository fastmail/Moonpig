package Moonpig::X;
# ABSTRACT: an exception thrown in Moonpig
use Moose;

with(
  'Throwable',
  'Moonpig::Role::Happening',
  'StackTrace::Auto',
);

has is_public => (
  is  => 'ro',
  isa => 'Bool',
  init_arg => 'public',
  default  => 0,
);

use Data::Dumper ();

use namespace::clean -except => 'meta';

use overload
  '""' => sub {
    my ($self) = @_;
    my %dump = %$self;
    delete $dump{stack_trace};
    Data::Dumper->Dump([ \%dump ], [ 'Exception' ]) . "\n-------\n" .
    $_[0]->stack_trace->as_string
  },
  fallback => 1;

1;
