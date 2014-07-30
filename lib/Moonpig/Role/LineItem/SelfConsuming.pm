package Moonpig::Role::LineItem::SelfConsuming;
# ABSTRACT: a magic line item that consumes its funds immediately on payment
use Moonpig;
use Moonpig::Types qw(NonNegativeMillicents);

use Moose::Role;

with ('Moonpig::Role::LineItem',
      'Moonpig::Role::LineItem::Active',
      'Moonpig::Role::LineItem::Abandonable',
     );

sub when_paid {
  my ($self) = @_;

  my $owner = $self->owner;
  $owner->charge_current_journal({
    description => $self->description,
    amount      => $self->amount,
    skip_funds_check => (
      $owner->can('allows_overdrafts') ? $owner->allows_overdrafts : 0
    ),
  });
}

1;
