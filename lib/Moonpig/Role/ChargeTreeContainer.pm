package Moonpig::Role::ChargeTreeContainer;
# ABSTRACT: something that acts as the head of a cost tree
use MooseX::Role::Parameterized;

use namespace::autoclean;

use Moonpig;

use Moonpig::Util qw(class);
use Stick::Types qw(StickBool);
use Stick::Util qw(true false);

parameter charges_handle_events => (
  isa      => 'Bool',
  required => 1,
);

role {
  my $p = shift;

  has charge_tree => (
    is   => 'ro',
    does => 'Moonpig::Role::ChargeTree',
    default  => sub { class('ChargeTree')->new },
    handles  => [ qw(add_charge_at total_amount) ],
  );

  method _objectify_charge => sub {
    my ($self, $input) = @_;
    return $input if blessed $input;

    my $class = $p->charges_handle_events
              ? class('Charge::HandlesEvents')
              : class('Charge');
    $class->new($input);
  };

  around add_charge_at => sub {
    my ($orig, $self, $charge_input, $path) = @_;

    my $charge = $self->_objectify_charge( $charge_input );

    my $handles = $charge->does('Moonpig::Role::HandlesEvents');

    Moonpig::X->throw("bad charge type")
      if $handles xor $p->charges_handle_events;

    $self->$orig($charge, $path);

    return $charge;
  };

  has closed => (
    isa     => StickBool,
    coerce  => 1,
    default => 0,
    reader  => 'is_closed',
    writer  => '__set_closed',
  );

  method close   => sub { $_[0]->__set_closed( true ) };
  method is_open => sub { ! $_[0]->is_closed };

  # TODO: make sure that charges added to this container have dates that
  # precede this date. 2010-10-17 mjd@icgroup.com
  has date => (
    is  => 'ro',
    required => 1,
    default => sub { Moonpig->env->now() },
    isa => 'DateTime',
  );
};

1;
