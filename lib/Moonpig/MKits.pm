use strict;
use warnings;
package Moonpig::MKits;
# ABSTRACT: the access point for Moonpig's message kits

use File::ShareDir;
use File::Spec;
use Email::MIME::Kit 2;

sub kit {
  my ($self, $kitname) = @_;

  $kitname .= '.mkit' unless $kitname =~ /\.mkit$/;

  my $root = defined $ENV{MOONPIG_MKITS_DIR}
           ? $ENV{MOONPIG_MKITS_DIR}
           : File::Spec->catdir( File::ShareDir::dist_dir('Moonpig'), 'kit' );

  my $kit = File::Spec->catdir($root, $kitname);

  return Email::MIME::Kit->new({ source => $kit });
}

1;
