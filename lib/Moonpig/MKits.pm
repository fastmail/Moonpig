package Moonpig::MKits;
use Moose;
# ABSTRACT: the access point for Moonpig's message kits

use Carp ();
use Email::Date::Format qw(email_gmdate);
use File::ShareDir;
use File::Spec;
use Email::MIME::Kit 2;

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
  my $email = $kit->assemble($arg);

  if ( Moonpig->env->does('Moonpig::Role::Env::WithMockedTime') ) {
    $email->header_set(Date => email_gmdate( Moonpig->env->now->epoch ) );
  }

  return $email;
}

1;
