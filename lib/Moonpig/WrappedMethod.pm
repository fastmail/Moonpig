package Moonpig::WrappedMethod;
use Moose;

with(
  'Stick::Role::PublicResource',
);

use namespace::autoclean;

has invocant => (
  is  => 'ro',
  isa => 'Defined',
  required => 1,
);

my @methods = qw(get put post delete);

has [ map {; "$_\_method" } @methods ] => (
  is  => 'ro',
  isa => 'Str|CodeRef',
);

for my $method (@methods) {
  Sub::Install::install_sub({
    as   => "resource_$method",
    code => sub {
      my ($self, $arg) = @_;
      my $proxy_name   = "$method\_method";
      Moonpig::X->throw("bad method")
        unless my $proxy_method = $self->$proxy_name;
      return $self->invocant->$proxy_method($arg);
    },
  });
}

1;
