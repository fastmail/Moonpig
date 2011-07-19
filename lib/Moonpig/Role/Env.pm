package Moonpig::Role::Env;
# ABSTRACT: an environment of globally-available behavior for all of Moonpig
use Moose::Role;

use Moonpig;

with(
  'Moonpig::Role::HandlesEvents',
  'Stick::Role::Routable::ClassAndInstance',
);

use Moonpig::Consumer::TemplateRegistry;
use Moonpig::Events::Handler::Method;
use Moonpig::Ledger::PostTarget;
use Moonpig::Util qw(class);

use Moonpig::Behavior::EventHandlers;

use Moonpig::Context -all, '$Context';

use namespace::autoclean;

requires 'register_object';
requires 'now';

sub format_guid { return $_[1] }

has storage => (
  is   => 'ro',
  does => 'Moonpig::Role::Storage',
  lazy => 1,
  init_arg => undef,
  default  => sub { $_[0]->storage_class->new },
  clearer  => 'clear_storage',
  handles  => [ qw(save_ledger) ],
);

requires 'storage_class';

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

  if ($path->[0] eq 'ledgers') {
    shift @$path;
    return 'Moonpig::Ledger::PostTarget';
  }

  return;
}

my %MP_ENV;
sub import {
  my ($class) = @_;
  my $THIS = $MP_ENV{ $class } ||= $class->new;
  Moonpig->set_env($THIS)
};

1;
