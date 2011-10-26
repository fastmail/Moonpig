package Moonpig::Storage::Spike::SQLite;
use Moose;
with 'Moonpig::Storage::Spike';

use namespace::autoclean;

has _root => (
  is  => 'ro',
  isa => 'Str',
  init_arg => undef,
  default  => sub { $ENV{MOONPIG_STORAGE_ROOT} || die('no storage root') },
);

sub _sqlite_filename {
  my ($self) = @_;

  my $db_file = File::Spec->catfile(
    $self->_root,
    "moonpig.sqlite",
  );
}

sub _dbi_connect_args {
  my ($self) = @_;
  my $db_file = $self->_sqlite_filename;

  return (
    "dbi:SQLite:dbname=$db_file", undef, undef,
    {
      RaiseError => 1,
      PrintError => 0,
    },
  );
}

sub _sql_producer { 'SQLite' }

1;
