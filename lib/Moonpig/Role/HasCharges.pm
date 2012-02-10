package Moonpig::Role::HasCharges;
# ABSTRACT: something that has a set of charges associated with it
use MooseX::Role::Parameterized;

use namespace::autoclean;

use Moonpig;

use Moonpig::Types;
use Moonpig::Util qw(class sumof);
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef);
use Moonpig::Types qw(Time);

parameter charge_role => (
  isa      => enum([qw(InvoiceCharge JournalCharge)]),
  required => 1,
);

role {
  my $p = shift;

  has charges => (
    is  => 'ro',
    isa => ArrayRef[ "Moonpig::Types::" . $p->charge_role ],
    init_arg => undef,
    default  => sub {  []  },
    traits   => [ 'Array' ],
    handles  => {
      all_charges => 'elements',
      has_charges => 'count',
      _add_charge => 'push',
    },
  );

  method total_amount => sub {
    sumof { $_->amount } $_[0]->all_charges;
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
      unless $charge->does( 'Moonpig::Role::' . $p->charge_role );

    $self->_add_charge($charge);

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
