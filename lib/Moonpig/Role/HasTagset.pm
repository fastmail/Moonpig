package Moonpig::Role::HasTagset;
# ABSTRACT: a charge in a charge tree

use Moonpig::Types qw(Tag);
use MooseX::Role::Parameterized;
use MooseX::Types::Moose qw(Str ArrayRef);

# Name of the attribute under which the tag set will be stored
parameter attr => (isa => Str, default => 'tags');

# Name of the method that asks if an object possesses a certain tag
parameter predicate => (isa => Str, default => 'has_tag');

parameter taglist_method => (isa => Str, default => 'taglist');

role {
  my ($p) = @_;
  my $attr = $p->attr;
  my $predicate = $p->predicate;
  my $taglist_method = $p->taglist_method;

  has $attr => (
    is => 'ro',
    isa => ArrayRef [ Tag ],
    default => sub { [] },
  );

  method $taglist_method => sub { @{$_[0]->$attr} };

  method $predicate => sub {
    my ($self, $tag) = @_;
    for my $_tag ($self->taglist) {
      return 1 if $_tag eq $tag;
    }
    return;
  };

};

1;
