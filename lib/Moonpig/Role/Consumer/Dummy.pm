package Moonpig::Role::Consumer::Dummy;
# ABSTRACT: a minimal consumer for testing

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(CostPath);
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
use Moonpig::Types qw(Millicents Time TimeInterval);

use namespace::autoclean;

implicit_event_handlers {
  return {
    heartbeat => { },
  };
};

sub construct_replacement {
  my ($self, $param) = @_;

  my $repl = $self->ledger->add_consumer(
    $self->meta->name,
    {
      cost_path_prefix   => $self->cost_path_prefix(),
      ledger             => $self->ledger(),
      old_age            => $self->old_age(),
      replacement_mri    => $self->replacement_mri(),
      %$param,
  });
}

1;
