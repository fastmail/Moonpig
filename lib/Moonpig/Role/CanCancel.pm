package Moonpig::Role::CanCancel;
# ABSTRACT: something that can be canceled
use Moose::Role;

use Moonpig::Trait::Copy;
use Stick::Publisher;
use Stick::Publisher::Publish;
use Stick::Types qw(StickBool);
use Stick::Util qw(true false);
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

requires 'handle_cancel';

publish cancel => { -http_method => 'post', -path => 'cancel' } => sub {
  my ($self) = @_;
  $self->handle_event(event('cancel'));
  return;
};

has canceled => (
  is  => 'ro',
  isa => StickBool,
  coerce  => 1,
  default => 0,
  reader  => 'is_canceled',
  writer  => '__set_canceled',
  traits  => [ qw(Copy) ],
);

sub mark_canceled { $_[0]->__set_canceled( true ) }

1;
