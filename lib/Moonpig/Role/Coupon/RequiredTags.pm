package Moonpig::Role::Coupon::RequiredTags;
# ABSTRACT: a coupon that applies only to charges that have particular tags
use Moose::Role;

with(
  'Moonpig::Role::Coupon',
  'Moonpig::Role::HasTagset' => { attr => 'target_tags', predicate => 'has_target_tag' },
);

sub applies_to_charge {
  my ($self, $charge) = @_;
  for my $tag ( $self->taglist ) {
    return unless $charge->has_tag($tag);
  }
  return 1;
}

1;

