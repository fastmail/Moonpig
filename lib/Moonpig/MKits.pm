use strict;
use warnings;
package Moonpig::MKits;
# ABSTRACT: the access point for Moonpig's message kits

use Carp ();
use File::ShareDir;
use File::Spec;
use Email::MIME::Kit 2;

sub kit {
  my ($self, $kitname) = @_;

  $kitname .= '.mkit';

  my @path = map {; File::Spec->catdir($_, 'kit' ) } Moonpig->env->share_roots;

  for my $root (@path) {
    my $kit = File::Spec->catdir($root, $kitname);
    next unless -d $kit;
    return Email::MIME::Kit->new({ source => $kit });
  }

  Carp::confess "unknown mkit <$kitname>";
}

1;
