package Moonpig::Role::Coupon::RequiredTags;
# ABSTRACT: a coupon that applies only to charges that have particular tags
use Moose::Role;
use Moonpig::Types qw(Tag);
use MooseX::Types::Moose qw(ArrayRef);

with(
  'Moonpig::Role::Coupon',
);

has target_tags => (
  is => 'ro',
  isa => ArrayRef [ Tag ],
  required => 1,
);

sub taglist { @{$_[0]->target_tags} }

sub applies_to {
  my ($self, $charge) = @_;
  for my $tag ( $self->taglist ) {
    return unless $charge->has_tag($tag);
  }
  return 1;
}

1;

