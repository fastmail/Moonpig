package Moonpig::Router;
use Moose;
use MooseX::ClassAttribute;

require Moonpig::X;

require Moonpig::Role::Ledger;

use namespace::autoclean;

has owner => (
  isa    => 'Defined',
  reader => '_owner',
);

has routes => (
  reader   => '_routes',
  isa      => 'HashRef',
  required => 1,
);

# GET /ledger/guid/ABC-DEF-GHI/invoice/INVID/method
# GET /                  - start at root
#   ledger/              - "ledger" leads to Moonpig::Role::Ledger->resolver
#     guid/              - Ledger->resolver has guid(1); returns obj resolver
#       ABC-DEF-GHI/
#         invoice/       - obj->resolver has invoice(1); returns obj resolver
#           INVID/
#             method     - inv->resolver has method; returns method

sub route {
  my ($self, $invocant, $orig_path) = @_;

  Moonpig::X::NoRoute->throw unless my (@path) = @$orig_path;
  
  my $c_router   = $self;
  my $c_invocant = $invocant;
  my $endpoint;

  PATH_PART: while (my $next = shift @path) {
    Moonpig::X::NoRoute->throw unless my $step = $c_router->_routes->{ $next };

    my $next = (! blessed $step and ref $step eq 'CODE')
             ? $step->(\@path)
             : $step;

    if ($next->does('Moonpig::Role::Routable')) {
      $c_router = $next->_router;
      $c_invocant = $next;
    } elsif ($next->isa('Moonpig::WrappedMethod')) {
      Moonpig::X->throw("bogus route: method at non-endpoint") if @path;
      return ($next, $c_invocant);
    }
  }

  Moonpig::X->throw("non-method endpoint not yet implemented");
}

1;
