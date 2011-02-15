package Moonpig::Role::Env;
# ABSTRACT: an environment of globally-available behavior for all of Moonpig
use Moose::Role;

use Moonpig;
use Moonpig::Router;

with(
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::TracksTime',
);

use Moonpig::Consumer::TemplateRegistry;
use Moonpig::Events::Handler::Method;
use Moonpig::Util qw(class);

use Moonpig::Behavior::EventHandlers;

use namespace::autoclean;

requires 'handle_send_email';

sub format_guid { return $_[1] }

implicit_event_handlers {
  return {
    'send-email' => {
      default => Moonpig::Events::Handler::Method->new('handle_send_email'),
    }
  };
};

has consumer_template_registry => (
  is  => 'ro',
  isa => 'Moonpig::Consumer::TemplateRegistry',
  init_arg => undef,
  default  => sub { Moonpig::Consumer::TemplateRegistry->new },
  handles  => {
    consumer_template => 'template',
  },
);

sub _router {
  my ($class) = @_;

  Moonpig::Router->new({
    routes => {
      ledger => scalar class('Ledger'),
    },
  });
}

sub route {
  my ($self, @rest) = @_;

  $self->_router->route(undef, @rest);
}

1;
