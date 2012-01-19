package Moonpig::Role::CanCancel;
# ABSTRACT: something that can be canceled
use Moose::Role;

use Moonpig::Trait::Copy;
use Stick::Publisher;
use Stick::Publisher::Publish;
use Moonpig::Types qw(Time);
use Moonpig::Util qw(event);

use namespace::autoclean;

use Moonpig::Behavior::EventHandlers;
implicit_event_handlers {
  return {
    'cancel' => {
      cancel_service => Moonpig::Events::Handler::Method->new(
        method_name => 'handle_cancel',
      ),
    },
  };
};

use Moonpig::Behavior::Packable;
PARTIAL_PACK {
  my ($self) = @_;
  return { $_[0]->canceled_at ? (canceled_at => $_[0]->canceled_at) : () };
};

requires 'handle_cancel';

publish cancel => { -http_method => 'post', -path => 'cancel' } => sub {
  my ($self) = @_;
  $self->handle_event(event('cancel'));
  return;
};

has canceled_at => (
  isa => Time,
  reader    => 'canceled_at',
  predicate => 'is_canceled',
  writer    => '__set_canceled_at',
  traits    => [ qw(Copy) ],
);

sub mark_canceled { $_[0]->__set_canceled_at( Moonpig->env->now ) }

1;
