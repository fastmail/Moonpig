package Moonpig::Env::Test;
# ABSTRACT: a testing environment for Moonpig

use Moose;
with(
  'Moonpig::Role::Env::WithMockedTime',
  'Moonpig::Role::Env::EmailSender',
);

use MooseX::StrictConstructor;

use namespace::autoclean;

use Carp qw(croak confess);
use Email::Address;
use Email::Sender::Transport::Test;
use File::ShareDir ();
use Moonpig::X;
use Moonpig::DateTime;
use Moonpig::Types qw(Time);
use Moonpig::Util qw(class);

use Moose::Util::TypeConstraints;

sub extra_share_roots { }

sub default_from_email_address {
  Email::Address->new(
    'Moonpig',
    'moonpig@example.com',
  );
}

has object_registry => (
  is   => 'ro',
  isa  => 'HashRef',
  init_arg => undef,
  default  => sub {  {}  },
);

sub register_object {
  my ($self, $obj) = @_;

  $self->object_registry->{ $obj->guid } = {
    weak_ref   => $obj,
    string     => "$obj",
    ident      => $obj->ident,
    guid       => $obj->guid,
    class      => ref($obj),
    created_at => Moonpig->env->now,
  };

  Scalar::Util::weaken( $self->object_registry->{ $obj->guid }->{weak_ref} );

  return;
}

sub storage_class {
  require Moonpig::Storage::Spike;
  'Moonpig::Storage::Spike';
}

sub storage_init_args {
  my ($self) = @_;

  my $root = $ENV{MOONPIG_STORAGE_ROOT} || die('no storage root');
  my $db_file = File::Spec->catfile($root, "moonpig.sqlite");

  return (
    sql_translator_producer => 'SQLite',
    dbi_connect_args        => [
      "dbi:SQLite:dbname=$db_file", undef, undef,
      {
        RaiseError => 1,
        PrintError => 0,
      },
    ],
  );
}

has _guid_serial_number_registry => (
  is  => 'ro',
  init_arg => undef,
  default  => sub {  {}  },
);

my $i = 1;

sub format_guid {
  my ($self, $guid) = @_;
  my $reg = $self->_guid_serial_number_registry;
  return ($reg->{ $guid } ||= $i++)
}

1;
