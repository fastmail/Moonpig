package Moonpig::Role::Routable;
use Moose::Role;

require Moonpig::X;

use namespace::autoclean;

# GET /ledger/guid/ABC-DEF-GHI/invoice/INVID/method
# GET /                  - start at root
#   ledger/              - "ledger" leads to Moonpig::Role::Ledger->resolver
#     guid/              - Ledger->resolver has guid(1); returns obj resolver
#       ABC-DEF-GHI/
#         invoice/       - obj->resolver has invoice(1); returns obj resolver
#           INVID/
#             method     - inv->resolver has method; returns method

requires '_subroute';

sub route {
  my ($self, $orig_path) = @_;

  Moonpig::X::NoRoute->throw unless my (@remaining_path) = @$orig_path;

  my $next_step = $self;

  PATH_PART: while (1) {
    if (! @remaining_path) {
      # we're at the end!  make sure it's a PublicResource and return it
      Moonpig::X->throw("non-PublicResource endpoint reached")
        unless $next_step->does('Moonpig::Role::PublicResource');

      return $next_step;
    };

    my $part_count = @remaining_path;

    $next_step = $next_step->_subroute( \@remaining_path );

    Moonpig::X::NoRoute->throw unless $next_step;

    Moonpig::X->throw("non-destructive routing not allowed")
      unless @remaining_path < $part_count;
  }
}

1;
