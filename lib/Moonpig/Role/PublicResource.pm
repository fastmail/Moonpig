package Moonpig::Role::PublicResource;
use Moose::Role;
use namespace::autoclean;

# might provide:
#   resource_get
#   resource_post
#   resource_put
#   resouce_delete

sub resource_request {
  my ($self, $method, $arg) = @_;

  my $method_name = "resource_$method";

  unless ($self->can($method_name)) {
    Moonpig::X->throw("bad method");
    # return [
    #   405,
    #   [ 'Content-type' => 'application/json' ],
    #   [ q<{ "error": "method not supported" }> ],
    # ];
  }

  return scalar $self->$method_name($arg);
}

1;
