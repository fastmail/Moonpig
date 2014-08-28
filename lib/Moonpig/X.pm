package Moonpig::X;
# ABSTRACT: an exception thrown in Moonpig

use Moose;

extends 'Stick::Error';

with(
  'Throwable',
  'Moonpig::Role::Notification',
  'StackTrace::Auto',
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

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
