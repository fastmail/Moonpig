package Moonpig::Role::Credit;
use Moose::Role;

with 'Moonpig::Role::HasGuid';

use List::Util qw(reduce);

use Moonpig::Types qw(Millicents);

use namespace::autoclean;

requires 'as_string'; # to be used on line items

has amount => (
  is  => 'ro',
  isa => Millicents,
  coerce => 1,
);

sub unapplied_amount {
  my ($self) = @_;
  my $xfers = Moonpig::CreditApplication->all_for_credit($self);

  my $xfer_total = reduce { $a + $b } 0, (map {; $_->amount } @$xfers);

  return $self->amount - $xfer_total;
}

has created_at => (
  is   => 'ro',
  isa  => 'Moonpig::DateTime',
  default  => sub { Moonpig->env->now },
  required => 1,
);

1;
