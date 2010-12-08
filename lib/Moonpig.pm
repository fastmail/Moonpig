package Moonpig;

my $env;

sub set_env {
  my ($self, $new_env) = @_;
  Carp::croak("environment is already configured") if $env;
  $env = $new_env;
}

sub env {
  Carp::croak("environment not yet configured") if ! $env;
  $env
}

1;
