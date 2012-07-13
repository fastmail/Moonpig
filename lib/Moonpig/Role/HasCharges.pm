package Moonpig::Role::HasCharges;
# ABSTRACT: something that has a set of charges associated with it
use MooseX::Role::Parameterized;

use namespace::autoclean;

use Moonpig;

use Moonpig::Types;
use Moonpig::Util qw(class sumof);
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef);
use Moonpig::Types qw(LineItem Time);

parameter charge_role => (
  isa      => enum([qw(InvoiceCharge JournalCharge)]),
  required => 1,
);

role {
  my $p = shift;

  requires 'accepts_charge';

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
      all_items => 'elements',
      has_items => 'count',
      _add_item => 'push',
      _add_item => 'push',
    },
  );

  method all_charges => sub {
    return $_[0]->all_items; # any reason at all to make this filter?
  };

  method has_charges => sub {
    return scalar($_[0]->all_charges);
  };

  method total_amount => sub {
    sumof { $_->amount } $_[0]->unabandoned_items;
  };

  method unabandoned_items => sub {
    my @items = grep {
      !    $_->does('Moonpig::Role::LineItem::Abandonable')
      || ! $_->is_abandoned
    } $_[0]->all_items;

    return @items;
  };

  method _objectify_charge => sub {
    my ($self, $input) = @_;
    return $input if blessed $input;

    my $class = class( $p->charge_role );

    $class->new($input);
  };

  method add_charge => sub {
    my ($self, $charge_input) = @_;

    my $charge = $self->_objectify_charge( $charge_input );

    Moonpig::X->throw("bad charge type")
      unless $self->accepts_charge($charge);

    $self->_add_item($charge);

    return $charge;
  };

  has closed_at => (
    isa => Time,
    init_arg  => undef,
    reader    => 'closed_at',
    predicate => 'is_closed',
    writer    => '__set_closed_at',
  );

  method mark_closed => sub { $_[0]->__set_closed_at( Moonpig->env->now ) };
  method is_open => sub { ! $_[0]->is_closed };

  has date => (
    is  => 'ro',
    default => sub { Moonpig->env->now() },
    init_arg => undef,
    isa => 'DateTime',
  );
};

1;
