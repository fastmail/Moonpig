package Moonpig::App::Ob::Config;
use Moose;
use Moonpig;
use Moonpig::Env::Test;
use Moose::Util::TypeConstraints qw(role_type);

sub env {
  Moonpig->env;
}

sub storage {
  $_[0]->env->storage
}

1;
