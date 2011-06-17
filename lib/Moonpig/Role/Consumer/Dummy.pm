package Moonpig::Role::Consumer::Dummy;
# ABSTRACT: a minimal consumer for testing

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Events::Handler::Method;
use Moonpig::Util qw(days event);
use Moose::Role;
use MooseX::Types::Moose qw(Num);

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

use Moonpig::Behavior::EventHandlers;

use namespace::autoclean;

implicit_event_handlers {
  return {
    heartbeat => { },
  };
};

sub template_like_this {
  my ($self) = @_;

  return {
    class => $self->meta->name,
    arg   => {
      charge_tags        => $self->charge_tags,
      ledger             => $self->ledger(),
      old_age            => $self->old_age(),
      replacement_mri    => $self->replacement_mri(),
    },
  };
}

1;
