package Moonpig::Role::Env;
# ABSTRACT: an environment of globally-available behavior for all of Moonpig
use Moose::Role;

use Moonpig;

with(
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::TracksTime',
  'Stick::Role::Routable::Disjunct',
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

sub _class_subroute {
  Moonpig::X->throw("cannot route through Moonpig environment class");
}

sub _instance_subroute {
  my ($class, $path) = @_;

  if ($path->[0] eq 'ledger') {
    shift @$path;
    return scalar class('Ledger');
  }

  return;
}

1;
