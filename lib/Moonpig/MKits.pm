package Moonpig::MKits;
use Moose;
# ABSTRACT: the access point for Moonpig's message kits

use Carp ();
use File::ShareDir;
use File::Spec;
use Email::MIME::Kit 2;

use namespace::autoclean;

sub _kit_for {
  my ($self, $kitname, $arg) = @_;

  $kitname .= '.mkit';

  my @path = map {; File::Spec->catdir($_, 'kit' ) } Moonpig->env->share_roots;

  for my $root (@path) {
    my $kit = File::Spec->catdir($root, $kitname);
    next unless -d $kit;
    return Email::MIME::Kit->new({ source => $kit });
  }

  Carp::confess "unknown mkit <$kitname>";
}

sub assemble_kit {
  my ($self, $kitname, $arg) = @_;

  my $kit = $self->_kit_for($kitname, $arg);
  return $kit->assemble($arg);
}

1;
