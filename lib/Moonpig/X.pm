package Moonpig::X;
# ABSTRACT: an exception thrown in Moonpig
use Moose;

with(
  'Throwable',
  'Moonpig::Role::Notification',
  'StackTrace::Auto',
);

has is_public => (
  is  => 'ro',
  isa => 'Bool',
  init_arg => 'public',
  builder  => 'public_by_default',
);

use Data::Dumper ();

use namespace::clean -except => 'meta';

sub public_by_default { 0 }

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
