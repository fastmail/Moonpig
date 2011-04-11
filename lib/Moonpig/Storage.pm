package Moonpig::Storage;
use Moose;

use Class::Rebless 0.009;
use Digest::MD5 qw(md5_hex);
use DBI;
use DBIx::Connector;
use File::Spec;

use Moonpig::Logger '$Logger';

use Moonpig::Types qw(Ledger);
use Moonpig::Util qw(class class_roles);
use Scalar::Util qw(blessed);
use Storable qw(nfreeze thaw);

use namespace::autoclean;

has _root => (
  is  => 'ro',
  isa => 'Str',
  init_arg => undef,
  default  => sub { $ENV{MOONPIG_STORAGE_ROOT} || die('no storage root') },
);

sub sqlite_filename {
  my ($self) = @_;

  my $db_file = File::Spec->catfile(
    $self->_root,
    "moonpig.sqlite",
  );
}

has _conn => (
  is   => 'ro',
  isa  => 'DBIx::Connector',
  lazy => 1,
  init_arg => undef,
  handles  => [ qw(txn) ],
  default  => sub {
    my ($self) = @_;

    my $db_file = $self->sqlite_filename;

    return DBIx::Connector->new(
      "dbi:SQLite:dbname=$db_file", undef, undef,
      {
        RaiseError => 1,
        PrintError => 0,
      },
    );
  },
);

my $sql = <<'END_SQL';
    CREATE TABLE stuff (
      guid TEXT NOT NULL,
      name TEXT NOT NULL,
      blob BLOB NOT NULL,
      PRIMARY KEY (guid, name)
    );

    CREATE TABLE xid_ledgers (
      xid TEXT PRIMARY KEY,
      ledger_guid TEXT NOT NULL
    );

    CREATE TABLE metadata (
      one PRIMARY KEY,
      schema_md5 TEXT NOT NULL,
      last_realtime INTEGER NOT NULL,
      last_moontime INTEGER NOT NULL
    );
END_SQL

my $SCHEMA_MD5 = md5_hex($sql);

sub _ensure_tables_exist {
  my ($self) = @_;

  my $conn = $self->_conn;

  $conn->txn(sub {
    my ($dbh) = $_;

    my ($schema_md5) = eval {
      $dbh->selectrow_array("SELECT schema_md5 FROM metadata");
    };

    return if defined $schema_md5 and $schema_md5 eq $SCHEMA_MD5;
    confess "database is of an incompatible schema" if defined $schema_md5;

    my @hunks = split /\n{2,}/, $sql;

    $dbh->do($_) for @hunks;

    $dbh->do(
      q{
        INSERT INTO metadata (one, schema_md5, last_realtime, last_moontime)
        VALUES (1, ?, ?, ?)
      },
      undef,
      $SCHEMA_MD5,
      (time) x 2,
    );
  });
}

has _in_update_mode => (
  is  => 'ro',
  isa => 'Bool',
  traits  => [ 'Bool' ],
  handles => {
    _set_update_mode   => 'set',
    _set_noupdate_mode => 'unset',
  },
  predicate => '_has_update_mode',
  clearer   => '_clear_update_mode',
);

sub do_rw {
  my ($self, $code) = @_;
  $self->_set_update_mode;
  my $rv = $self->txn(sub {
    my $rv = $code->();
    $self->execute_saves;
    return $rv;
  });
  $self->_clear_update_mode;
  return $rv;
}

sub do_ro {
  my ($self, $code) = @_;
  $self->_set_noupdate_mode;
  my $rv = $self->txn(sub {
    $code->();
  });
  $self->_clear_update_mode;
  return $rv;
}

has _ledger_queue => (
  is  => 'ro',
  isa => 'HashRef',
  init_arg => undef,
  default  => sub {  {}  },
);

sub save_ledger {
  my ($self, $ledger) = @_;

  # EITHER:
  # 1. we are in a do_rw transaction -- save this ledger to write later
  # 2. we are in a do_ro transaction -- die
  # 3. we are not in a transaction -- do one right now to save immediately
  # -- rjbs, 2011-04-11
  if ($self->_has_update_mode) {
    if ($self->_in_update_mode) {
      $self->_ledger_queue->{ $ledger->guid } = $ledger;
    } else {
      Moonpig::X->throw("save ledger inside read-only transaction");
    }
  } else {
    $self->_store_ledger($ledger);
  }
}

sub execute_saves {
  my ($self) = @_;

  $self->txn(sub {
    for my $guid (keys %{ $self->_ledger_queue }) {
      my $ledger = delete $self->_ledger_queue->{ $guid };
      $self->_store_ledger($ledger);
    }
  });
}

sub _store_ledger {
  my ($self, $ledger) = @_;

  Ledger->assert_valid($ledger);

  $Logger->log_debug([
    'storing %s under guid %s',
    $ledger->ident,
    $ledger->guid,
  ]);

  my $conn = $self->_conn;
  $conn->txn(sub {
    my ($dbh) = $_;

    $self->_ensure_tables_exist;

    $dbh->do(
      q{
        INSERT OR REPLACE INTO stuff
        (guid, name, blob)
        VALUES (?, 'class_roles', ?)
      },
      undef,
      $ledger->guid,
      nfreeze( class_roles ),
    );

    $dbh->do(
      q{
        INSERT OR REPLACE INTO stuff
        (guid, name, blob)
        VALUES (?, 'ledger', ?)
      },
      undef,
      $ledger->guid,
      nfreeze( $ledger ),
    );

    $dbh->do(
      q{DELETE FROM xid_ledgers WHERE ledger_guid = ?},
      undef,
      $ledger->guid,
    );

    my $xid_sth = $dbh->prepare(
      q{INSERT INTO xid_ledgers (xid, ledger_guid) VALUES (?,?)},
    );

    for my $xid ($ledger->xids_handled) {
      $Logger->log_debug([
        'registering ledger %s for xid %s',
        $ledger->ident,
        $xid,
      ]);
      $xid_sth->execute($xid, $ledger->guid);
    }
  });

  return $ledger;
}

sub _reinstate_stored_time {
  my ($self) = @_;

  my ($real, $moon) = $self->_conn->dbh->selectrow_array(
    "SELECT last_realtime, last_moontime FROM metadata",
  );

  my $diff = time - $real;
  confess("last realtime from storage is in the future") if $diff < 0;

  my $should_be = $moon + $diff;

  Moonpig->env->stop_clock_at( Moonpig::DateTime->new($should_be) );
  Moonpig->env->restart_clock;
}

sub _store_time {
  my ($self) = @_;

  my $now_s = Moonpig->env->now->epoch;

  $self->txn(sub {
    $_->do(
      "UPDATE metadata SET last_realtime = ?, last_moontime = ?",
      undef,
      time,
      $now_s,
    );
  });
}

sub known_guids {
  my ($self) = @_;
  my $dbh = $self->_conn->dbh;

  my $guids = $dbh->selectcol_arrayref(q{SELECT DISTINCT guid FROM stuff});
  return @$guids;
}

sub retrieve_ledger_for_xid {
  my ($self, $xid) = @_;

  my $dbh = $self->_conn->dbh;

  my ($ledger_guid) = $dbh->selectrow_array(
    q{SELECT ledger_guid FROM xid_ledgers WHERE xid = ?},
    undef,
    $xid,
  );

  return unless defined $ledger_guid;

  $Logger->log_debug([ 'retrieved guid %s for xid %s', $ledger_guid, $xid ]);

  return $self->retrieve_ledger_for_guid($ledger_guid);
}

sub retrieve_ledger_for_guid {
  my ($self, $guid) = @_;

  $Logger->log_debug([ 'retrieving ledger under guid %s', $guid ]);

  my $dbh = $self->_conn->dbh;
  my ($class_blob) = $dbh->selectrow_array(
    q{SELECT blob FROM stuff WHERE guid = ? AND name = 'class_roles'},
    undef,
    $guid,
  );

  my ($ledger_blob) = $dbh->selectrow_array(
    q{SELECT blob FROM stuff WHERE guid = ? AND name = 'ledger'},
    undef,
    $guid,
  );

  return unless defined $class_blob or defined $ledger_blob;

  Carp::confess("incomplete storage data found for $guid")
    unless defined $class_blob and defined $ledger_blob;

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

  $self->save_ledger($ledger) if $self->_in_update_mode;

  return $ledger;
}

1;
