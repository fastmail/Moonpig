package Moonpig::Role::Env;
# ABSTRACT: an environment of globally-available behavior for all of Moonpig
use Moose::Role;

use Moonpig;

with(
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::TracksTime',
);

use Moonpig::Consumer::TemplateRegistry;
use Moonpig::Events::Handler::Method;

use Moonpig::Behavior::EventHandlers;

requires 'handle_send_email';

sub format_guid { return $_[1] }

implicit_event_handlers {
  return {
    'send-email' => {
      default => Moonpig::Events::Handler::Method->new('handle_send_email'),
    }
  };
};

has _consumer_templates => (
  is  => 'ro',
  isa => 'Moonpig::Consumer::TemplateRegistry',
  init_arg => undef,
  default  => sub { Moonpig::Consumer::TemplateRegistry->new },
);

1;
