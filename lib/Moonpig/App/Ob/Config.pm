package Moonpig::App::Ob::Config;
use Moose;
use Moonpig::Env::Test;
use Moose::Util::TypeConstraints qw(role_type);

sub env {
  Moonpig::Env->new;
}

sub storage {
  $_[0]->env->storage
}

1;
