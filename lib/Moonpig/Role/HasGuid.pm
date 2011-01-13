package Moonpig::Role::HasGuid;
# ABSTRACT: something with a GUID (nearly everything)
use Moose::Role;

use Data::GUID qw(guid_string);
use Moose::Util::TypeConstraints;

use Moonpig::Logger '$Logger';

use namespace::autoclean;

with 'Moonpig::Role::StubBuild';

has guid => (
  is  => 'ro',
  isa => 'Str', # refine this -- rjbs, 2010-12-02
  init_arg => undef,
  default  => sub { guid_string },
);

sub ident {
  my ($self) = @_;

  return sprintf '%s<%s>',
    $self->meta->name,
    Moonpig->env->format_guid( $self->guid );
}

sub TO_JSON { $_[0]->ident }

after BUILD => sub {
  my ($self) = @_;
  $Logger->log([ 'created %s', $self->ident ]);
};

1;
