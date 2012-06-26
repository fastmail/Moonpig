package Moonpig::Role::Coupon::RequiredTags;
# ABSTRACT: a coupon that applies only to charges that have particular tags
use Moose::Role;

with(
  'Moonpig::Role::Coupon',
  'Moonpig::Role::HasTagset' => {
    attr      => 'target_tags',
    predicate => 'has_target_tag',
    taglist_method => 'target_taglist',
  },
);

sub applies_to_charge {
  my ($self, $struct) = @_;
  for my $tag ( $self->target_taglist ) {
    return unless grep { $tag eq $_ } @{ $struct->{tags} };
  }
  return 1;
}

1;

