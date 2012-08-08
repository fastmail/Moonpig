package Moonpig::Role::HasLineItems;
# ABSTRACT: something that has a set of line items associated with it
use Moose::Role;

use namespace::autoclean;

use Moonpig;

use Moonpig::Types;
use Moonpig::Util qw(class sumof);
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef);
use Moonpig::Types qw(LineItem Time);

with 'Moonpig::Role::HasCreatedAt';

requires 'charge_role';

requires 'accepts_line_item';

# This is a misnomer, since it might not yield only charges, but any line
# item.
# We did not want to have to modify the existing database. mjd 2012-07-12
has charges => (
  is  => 'ro',
  isa => ArrayRef[ LineItem ],
  init_arg => undef,
  default  => sub {  []  },
  traits   => [ 'Array' ],
  handles  => {
    all_items   => 'elements',
    all_charges => 'elements',
    has_items   => 'count',
    has_charges => 'count',
    _add_item   => 'push',
  },
);

sub total_amount {
  sumof { $_->amount } $_[0]->unabandoned_items;
}

sub abandoned_items {
  my @items = grep {
    ($_->does('Moonpig::Role::LineItem::Abandonable') and $_->is_abandoned)
  } $_[0]->all_items;

  return @items;
}

sub unabandoned_items {
  my @items = grep {
    ! ($_->does('Moonpig::Role::LineItem::Abandonable') and $_->is_abandoned)
  } $_[0]->all_items;

  return @items;
}

sub _objectify_charge {
  my ($self, $input) = @_;
  return $input if blessed $input;

  my $class = class( $self->charge_role );

  $class->new($input);
}

sub add_charge {
  my ($self, $charge_input) = @_;

  my $charge = $self->_objectify_charge( $charge_input );

  Moonpig::X->throw("bad charge type")
    unless $self->accepts_line_item($charge);

  $self->_add_item($charge);

  return $charge;
}

has closed_at => (
  isa => Time,
  init_arg  => undef,
  reader    => 'closed_at',
  predicate => 'is_closed',
  writer    => '__set_closed_at',
);

sub mark_closed { $_[0]->__set_closed_at( Moonpig->env->now ) };
sub is_open { ! $_[0]->is_closed };

sub date { $_[0]->created_at }

1;
