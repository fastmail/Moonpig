package Moonpig::Role::Collection::InvoiceExtras;
use Moose::Role;
use MooseX::Types::Moose qw(Str HashRef);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

publish unpaid => {} => sub {
  my ($self) = @_;
  return [ grep {; $_->is_unpaid } @{ $self->items } ];
};

1;
