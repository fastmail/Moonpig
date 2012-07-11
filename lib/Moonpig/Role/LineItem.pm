package Moonpig::Role::LineItem;
# ABSTRACT: a non-charge line item on an invoice
use Moose::Role;
use Moonpig::Behavior::Packable;
with ('Moonpig::Role::Charge',
      'Moonpig::Role::ConsumerComponent',
      'Moonpig::Role::HandlesEvents',
     );

requires 'line_item_type';

sub check_amount { 1 }

sub counts_toward_total { 0 }
sub is_charge { 0 }

PARTIAL_PACK {
  my ($self) = @_;
  return { line_item_type => $self->line_item_type };
};

1;
