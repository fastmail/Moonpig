package Moonpig::Role::ConsumerTemplateSet;
use Moose::Role;

use Moonpig;

use namespace::autoclean;

requires 'templates';

sub import {
  my ($class, $name) = @_;
  return unless defined $name;

  Moonpig->env->consumer_template_registry
              ->register_templates_with_prefix($name => $class->templates);

  return;
}


1;
