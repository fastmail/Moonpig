package Moonpig::Role::ConsumerTemplateSet;
# ABSTRACT: a loadable set of consumer templates

use Moose::Role;
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
