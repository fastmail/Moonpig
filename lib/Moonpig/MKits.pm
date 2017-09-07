package Moonpig::MKits;
# ABSTRACT: the access point for Moonpig's message kits

use Moose;

use Carp ();
use File::ShareDir;
use File::Spec;
use Moonpig::Email::MIME::Kit;

use namespace::autoclean;

has _global_mkit_overrides => (
  is   => 'ro',
  default => sub { [] },
);

has _per_mkit_overrides => (
  is      => 'ro',
  default => sub { {} },
);

sub _overrides_for_kitname {
  my ($self, $kitname) = @_;

  my $for_kit   = $self->_per_mkit_overrides->{ $kitname };
  my @overrides = $for_kit ? @$for_kit : ();

  push @overrides, @{ $self->_global_mkit_overrides };

  return @overrides;
}

sub add_override {
  my ($self, $kitname, $sub) = @_;

  if ($kitname eq '*') {
    push @{ $self->_global_mkit_overrides }, $sub;
  } else {
    push @{ $self->_per_mkit_overrides->{ $kitname } }, $sub;
  }
}

sub _kitname_for {
  my ($self, $kitname, $arg) = @_;

  for my $override ($self->_overrides_for_kitname($kitname)) {
    my $result = $override->( $kitname, $arg );
    next unless defined $result;
    return $result;
  }

  return $kitname;
}

sub _kit_for {
  my ($self, $kitname, $arg) = @_;

  $kitname = $self->_kitname_for($kitname, $arg);
  my $kitdir = "$kitname.mkit";

  my @path = map {; File::Spec->catdir($_, 'kit' ) } Moonpig->env->share_roots;

  for my $root (@path) {
    my $kit = File::Spec->catdir($root, $kitdir);
    next unless -d $kit;
    return Moonpig::Email::MIME::Kit->new({
      kitname => $kitname,
      source  => $kit,
    });
  }

  Carp::confess "unknown mkit <$kitname>";
}

sub assemble_kit {
  my ($self, $kitname, $arg) = @_;

  my $kit = $self->_kit_for($kitname, $arg);
  return $kit->assemble($arg);
}

1;
