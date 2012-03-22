package Moonpig::Role::ConsumerTemplateSet;
use Moose::Role;
# ABSTRACT: a loadable set of consumer templates

use Moonpig;

use namespace::autoclean;

requires 'templates';

sub import {
  my ($class) = @_;

  Moonpig->env->consumer_template_registry
              ->register_templates($class->templates);

  return;
}

1;
