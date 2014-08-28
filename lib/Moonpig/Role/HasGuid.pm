package Moonpig::Role::HasGuid;
# ABSTRACT: something with a GUID (nearly everything)

use Moose::Role;

use Data::GUID qw(guid_string);
use Moose::Util::TypeConstraints;

use Moonpig::Logger '$Logger';
use Moonpig::Types qw(GUID);

use Moonpig::Behavior::Packable;

use Stick::Publisher 0.301; # to make publish_is work in a role

use namespace::autoclean;

with 'Moonpig::Role::StubBuild';

has guid => (
  is  => 'ro',
  isa => GUID,
  init_arg => undef,
  default  => sub { guid_string },
  publish_is => 'ro',
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
  $Logger->log_debug([ 'created %s', $self->ident ]);
  Moonpig->env->register_object($self);
};

PARTIAL_PACK {
  return { guid => $_[0]->guid };
};


1;
