package Moonpig::EMKit::KitReader::SWAK;
# ABSTRACT: the SWAK kit-reader, but checks Moonpig share_roots

use Moose;
extends 'Email::MIME::Kit::KitReader::SWAK';

use Moonpig;

use Path::Resolver::Resolver::Mux::Ordered;
use Path::Resolver::Resolver::DistDir;

use namespace::autoclean;

sub BUILD {
  my ($self) = @_;

  $self->resolver->add_resolver_for(
    Moonpig => Path::Resolver::Resolver::Mux::Ordered->new({
      resolvers => [
        (map {; Path::Resolver::Resolver::FileSystem->new({ root => $_ }), }
          Moonpig->env->share_roots),
      ],
    })
  );
}

use namespace::autoclean;

1;
