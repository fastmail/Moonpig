use strict;
use warnings;
package Moonpig::Storage;

use Class::Rebless;
use DBI;
use File::Spec;

use Moonpig::Types qw(Ledger);
use Moonpig::Util qw(class class_roles);
use Scalar::Util qw(blessed);
use Storable qw(nfreeze thaw);

use namespace::autoclean;

sub _root {
  return($ENV{MOONPIG_STORAGE_ROOT} || die('no storage root'));
}

sub _dbh_for_guid {
  my ($self, $guid) = @_;

  my $db_file = File::Spec->catfile(
    $self->_root,
    $guid . q{.sqlite}
  );

  my $dbh = DBI->connect(
    "dbi:SQLite:dbname=$db_file", undef, undef,
    { RaiseError => 1 },
  );

  return $dbh;
}

sub store_ledger {
  my ($self, $ledger) = @_;

  Ledger->assert_valid($ledger);

  my $dbh = $self->_dbh_for_guid($ledger->guid);

  $dbh->begin_work;

  $dbh->do("CREATE TABLE stuff (name TEXT PRIMARY KEY, blob BLOB NOT NULL)");

  $dbh->do(q{DELETE FROM stuff});

  $dbh->do(
    q{INSERT INTO stuff (name, blob) VALUES ('class_roles', ?)},
    undef,
    nfreeze( class_roles ),
  );

  $dbh->do(
    q{INSERT INTO stuff (name, blob) VALUES ('ledger', ?)},
    undef,
    nfreeze( $ledger ),
  );

  $dbh->commit;
}

sub retrieve_ledger {
  my ($self, $guid) = @_;

  my $dbh = $self->_dbh_for_guid($guid);
  my ($class_blob) = $dbh->selectrow_array(
    q{SELECT blob FROM stuff WHERE name = 'class_roles'}
  );

  my ($ledger_blob) = $dbh->selectrow_array(
    q{SELECT blob FROM stuff WHERE name = 'ledger'}
  );

  require Moonpig::DateTime; # has a STORABLE_freeze -- rjbs, 2011-03-18

  my $class_map = thaw($class_blob);
  my $ledger    = thaw($ledger_blob);

  my %class_for;
  for my $old_class (keys %$class_map) {
    my $new_class = class(@{ $class_map->{ $old_class } });
    next if $new_class eq $old_class;

    $class_for{ $old_class } = $new_class;
  }

  Class::Rebless->custom($ledger, '...', {
    editor => sub {
      my ($obj) = @_;
      my $class = blessed $obj;
      return unless exists $class_for{ $class };
      bless $obj, $class_for{ $class };
    },
  });

  return $ledger;
}

1;
