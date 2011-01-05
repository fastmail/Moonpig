package Moonpig::Role::Credit::Simulated;
use Moose::Role;

use namespace::autoclean;

use Moonpig::X;

with(
  'Moonpig::Role::Credit',
  'Moonpig::Role::StubBuild',
);

sub as_string { 'simulated payment' }

after BUILD => sub {
  Moonpig::X->throw("can't use simulated payment in non-Test environment")
    unless Moonpig->env->isa('Moonpig::Env::Test');
};

1;
