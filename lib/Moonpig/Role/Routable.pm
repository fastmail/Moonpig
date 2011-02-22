package Moonpig::Role::Routable;
use Moose::Role;

use Moonpig::X;
use Moonpig::X::HTTP::Factory;

use namespace::autoclean;

requires '_subroute';

sub route {
  my ($self, $orig_path) = @_;

  Moonpig::X::HTTP::Factory->throw('NotFound')
    unless my (@remaining_path) = @$orig_path;

  my $next_step = $self;

  PATH_PART: while (1) {
    if (! @remaining_path) {
      # we're at the end!  make sure it's a PublicResource and return it

      # This should probably be a 404, but we want to know if people are
      # hitting it a lot, because ... why are they building some bogus URL like
      # this? -- rjbs, 2011-02-22
      Moonpig::X->throw("non-PublicResource endpoint reached")
        unless $next_step->does('Moonpig::Role::PublicResource');

      return $next_step;
    };

    my $part_count = @remaining_path;

    $next_step = $next_step->_subroute( \@remaining_path );

    Moonpig::X::HTTP::Factory->throw('NotFound') unless $next_step;

    Moonpig::X->throw("non-destructive routing not allowed")
      unless @remaining_path < $part_count;
  }
}

1;
