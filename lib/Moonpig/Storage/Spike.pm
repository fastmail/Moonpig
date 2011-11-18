package Moonpig::Storage::Spike;
# ABSTRACT: Basic implementation of Moonpig persistent storage
use Moose;
with 'Moonpig::Role::Storage';

use MooseX::StrictConstructor;

use Carp qw(carp confess croak);
use Class::Rebless 0.009;
use Digest::MD5 qw(md5_hex);
use DBI;
use DBIx::Connector;
use File::Spec;

use Moonpig::Job;
use Moonpig::Logger '$Logger';
use Moonpig::Storage::UpdateModeStack;
use Moonpig::Types qw(Ledger Factory);
use Moonpig::Util qw(class class_roles);
use Scalar::Util qw(blessed);
use SQL::Translator;
use Storable qw(nfreeze thaw);

use namespace::autoclean;

has sql_translator_producer => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

has sql_translator_producer_args => (
  isa => 'HashRef',
  default => sub {  {}  },
  traits  => [ qw(Hash) ],
  handles => { sql_translator_producer_args => 'elements' },
);

has dbi_connect_args => (
  isa => 'ArrayRef',
  required => 1,
  traits   => [ 'Array' ],
  handles  => { dbi_connect_args => 'elements' },
);

has _conn => (
  is   => 'ro',
  isa  => 'DBIx::Connector',
  lazy => 1,
  init_arg => undef,
  handles  => [ qw(txn) ],
  default  => sub {
    my ($self) = @_;

    return DBIx::Connector->new( $self->dbi_connect_args );
  },
);

my $schema_yaml = <<'...';
---
schema:
  tables:
    ledgers:
      name: ledgers
      fields:
        guid: { name: guid, data_type: varchar, size: 36, is_primary_key: 1 }
        frozen_ledger: { name: frozen_ledger, data_type: blob, is_nullable: 0 }
        frozen_classes: { name: frozen_classes, data_type: blob, is_nullable: 0 }

    xid_ledgers:
      name: xid_ledgers
      fields:
        xid: { name: xid, data_type: varchar, size: 256, is_primary_key: 1 }
        ledger_guid: { name: ledger_guid, data_type: varchar, size: 36, is_nullable: 0 }
      constraints:
        - type: FOREIGN KEY
          fields: [ ledger_guid ]
          reference_table: ledgers
          reference_fields: [ guid ]

    metadata:
      name: metadata
      fields:
        one: { name: one, data_type: int unsigned, is_primary_key: 1 }
        schema_md5: { name: schema_md5, data_type: varchar, size: 32, is_nullable: 0 }
        last_realtime: { name: last_realtime, data_type: integer, is_nullable: 0 }
        last_moontime: { name: last_moontime, data_type: integer, is_nullable: 0 }

    jobs:
      name: jobs
      fields:
        id: { name: id, data_type: integer, is_auto_increment: 1, is_primary_key: 1 }
        ledger_guid: { name: ledger_guid, data_type: varchar, size: 36, is_nullable: 0 }
        type: { name: type, data_type: text, is_nullable: 0 }
        created_at: { name: created_at, data_type: integer, is_nullable: 0 }
        locked_at: { name: locked_at, data_type: integer, is_nullable: 1 }
        termination_state: { name: termination_state, data_type: varchar, size: 32, is_nullable: 1 }
      constraints:
        - type: FOREIGN KEY
          fields: [ ledger_guid ]
          reference_table: ledgers
          reference_fields: [ guid ]

    job_documents:
      name: job_documents
      fields:
        job_id: { name: job_id, data_type: integer, is_nullable: 0 }
        ident: { name: ident, data_type: varchar, size: 64, is_nullable: 0 }
        payload: { name: payload, data_type: text, is_nullable: 0 }
      constraints:
        - type:   PRIMARY KEY
          fields: [ job_id, ident ]
        - type: FOREIGN KEY
          fields: [ job_id ]
          reference_table: jobs
          reference_fields: [ id ]

    job_logs:
      name: job_logs
      fields:
        id: { name: id, data_type: integer, is_auto_increment: 1, is_primary_key: 1 }
        job_id: { name: job_id, data_type: integer, is_nullable: 0 }
        logged_at: { name: logged_at, data_type: integer, is_nullable: 0 }
        message: { name: message, data_type: text, is_nullable: 0 }
...

my $SCHEMA_MD5 = md5_hex($schema_yaml);

sub _ensure_tables_exist {
  my ($self) = @_;

  my $conn = $self->_conn;

  $conn->txn(sub {
    my ($dbh) = $_;

    my ($schema_md5) = eval {
      $dbh->selectrow_array("SELECT schema_md5 FROM metadata");
    };

    return if defined $schema_md5 and $schema_md5 eq $SCHEMA_MD5;
    Carp::croak("database is of an incompatible schema") if defined $schema_md5;

    my $translator = SQL::Translator->new(
      parser   => "YAML",
      data     => \$schema_yaml,
      producer      => $self->sql_translator_producer,
      producer_args => {
        no_transaction => 1,
        $self->sql_translator_producer_args,
      },
    );

    my $sql = $translator->translate;
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

has _update_mode_stack => (
  is  => 'ro',
  isa => 'Moonpig::Storage::UpdateModeStack',
  default => sub { Moonpig::Storage::UpdateModeStack->new() },
  handles => {
    _has_update_mode => 'is_nonempty',
    _in_transaction => 'is_nonempty',
    _push_update_mode => 'push',
    _set_noupdate_mode => 'push_false',
    _set_update_mode => 'push_true',
  },
);

sub _in_update_mode {
  my ($self) = @_;
  $self->_has_update_mode &&
    $self->_update_mode_stack->get_top;
}

sub _in_nested_transaction {
  $_[0]->_update_mode_stack->depth > 1;
}

sub do_rw {
  my ($self, $code) = @_;
  my $popper = $self->_set_update_mode;
  my $rv = $self->txn(sub {
    my $rv = $code->();
    $self->_execute_saves unless $self->_in_nested_transaction;
    return $rv;
  });
  return $rv;
}

sub do_ro {
  my ($self, $code) = @_;
  my $popper = $self->_set_noupdate_mode;
  my $rv = $self->txn(sub {
    $code->();
  });
  return $rv;
}

sub do_with_ledgers {
  if (@_ == 3) {
    splice @_, 1, 0, {}; # $opts was omitted, so splice it in
  }
  my ($self, $opts, $guids, $code) = @_;
  $guids ||= [];
  my %opts = %$opts;
  my $ro = delete($opts{ro}) || 0;

  if (%opts) {
    my $keys = join " ", sort keys %opts;
    croak "Unknown options '%keys' to do_with_ledgers";
  }

  my @ledgers = ();
  for my $i (0 .. $#$guids) {
    defined($guids->[$i])
      or croak "Guid element $i was undefined";
    my $ledger = $self->retrieve_ledger_for_guid($guids->[$i])
      or croak "Couldn't find ledger for guid '$guids->[$i]'";
    push @ledgers, $ledger;
  }

  my $rv;
  {
    my $popper = $self->_push_update_mode(! $ro);

    $rv = $self->txn(sub {
      my $rv = $code->(@ledgers);
      unless ($ro) {
        $_->save for @ledgers;
        $self->_execute_saves;
      }
      return $rv;
    });
  }

  # Properly, we should track which ledgers are used in each nested
  # transaction, and whenver a transaction ends, flush the ones that
  # were used by only that transaction, but eh, that's too much
  # trouble. So instead, we just hold them all until the final
  # transaction ends and flush them all then. mjd 2011-11-14

  $self->_flush_ledger_cache unless $self->_in_transaction;

  return $rv;
}

sub do_rw_with_ledgers {
  if (@_ == 3) {
    splice @_, 1, 0, {}; # $opts was omitted, so splice it in
  }
  my ($self, $opts, $guids, $code) = @_;
  croak "ro option forbidden in do_rw_with_ledgers" if exists $opts->{ro};
  $self->do_with_ledgers({ %$opts, ro => 0 }, $guids, $code);
}

sub do_ro_with_ledgers {
  if (@_ == 3) {
    splice @_, 1, 0, {}; # $opts was omitted, so splice it in
  }
  my ($self, $opts, $guids, $code) = @_;
  croak "ro option forbidden in do_rw_with_ledgers" if exists $opts->{ro};
  $self->do_with_ledgers({ %$opts, ro => 1 }, $guids, $code);
}

has _ledger_cache => (
  is => 'ro',
  isa => 'HashRef',
  init_arg => undef,
  traits => [ 'Hash' ],
  default => sub { {} },
  handles => {
    _has_cached_ledger => 'exists',
    _cached_ledger => 'get',
    _flush_ledger_cache => 'clear',
  },
);

sub _cache_ledger {
  my ($self, $ledger) = @_;
  $self->_ledger_cache->{$ledger->guid} = $ledger;
}

has _ledger_queue => (
  is  => 'ro',
  isa => 'ArrayRef',
  init_arg => undef,
  default  => sub {  []  },
);

sub queue_job__ {
  my ($self, $arg) = @_;
  $arg->{payloads} ||= {};

  if ($self->_has_update_mode and $self->_in_update_mode) {
    $self->txn(sub {
      my $dbh = $_;
      $dbh->do(
        q{INSERT INTO jobs (type, ledger_guid, created_at) VALUES (?, ?, ?)},
        undef,
        $arg->{type},
        $arg->{ledger}->guid,
        Moonpig->env->now->epoch,
      );

      my $job_id = $dbh->last_insert_id(q{}, q{}, 'jobs', 'id');

      for my $ident (keys %{ $arg->{payloads} }) {
        # XXX: barf on reference payloads? -- rjbs, 2011-04-13
        $dbh->do(
          q{
            INSERT INTO job_documents (job_id, ident, payload)
            VALUES (?, ?, ?)
          },
          undef,
          $job_id,
          $ident,
          $arg->{payloads}->{ $ident },
        );
      }
    });
  } else {
    Moonpig::X->throw("queue_job outside of read-write transaction");
  }
}

sub __job_callbacks {
  my ($self, $conn, $job_row) = @_;

  return (
    log_callback  => sub {
      my ($self, $message) = @_;
      $conn->run(sub { $_->do(
        "INSERT INTO job_logs (job_id, logged_at, message)
        VALUES (?, ?, ?)",
        undef, $job_row->{id}, Moonpig->env->now->epoch, $message,
      )});
    },
    get_logs_callback => sub {
      my ($self) = @_;

      my $logs = $conn->run(sub { $_->selectall_arrayref(
        "SELECT * FROM job_logs WHERE job_id = ? ORDER BY logged_at",
        { Slice => {} },
        $job_row->{id},
      )});

      $_->{logged_at} = Moonpig::DateTime->new($_->{logged_at})
        for @$logs;

      return $logs;
    },
    unlock_callback => sub {
      my ($self) = @_;
      $conn->run(sub { $_->do(
        "UPDATE jobs SET locked_at = NULL WHERE id = ?",
        undef, $job_row->{id},
      )});
    },
    lock_callback => sub {
      my ($self) = @_;
      $conn->run(sub { $_->do(
        "UPDATE jobs SET locked_at = ? WHERE id = ?",
        undef, Moonpig->env->now->epoch, $job_row->{id},
      )});
    },
    cancel_callback => sub {
      my ($self) = @_;
      $conn->run(sub {
        my $dbh = $_;
        $_->do(
          "INSERT INTO job_logs (job_id, logged_at, message)
          VALUES (?, ?, ?)",
          undef, $job_row->{id}, Moonpig->env->now->epoch, 'job complete',
        );
        $_->do(
          "UPDATE jobs SET termination_state = 'cancel' WHERE id = ?",
          undef, $job_row->{id},
        );
      });
    },
    done_callback => sub {
      my ($self) = @_;
      $conn->run(sub {
        my $dbh = $_;
        $_->do(
          "INSERT INTO job_logs (job_id, logged_at, message)
          VALUES (?, ?, ?)",
          undef, $job_row->{id}, Moonpig->env->now->epoch, 'job complete',
        );
        $_->do(
          "UPDATE jobs SET termination_state = 'done' WHERE id = ?",
          undef, $job_row->{id},
        );
      });
    },
  );
}

sub __payloads_for_job_row {
  my ($self, $job_row, $dbh) = @_;

  my $payloads = $dbh->selectall_hashref(
    q{SELECT ident, payload FROM job_documents WHERE job_id = ?},
    'ident',
    undef,
    $job_row->{id},
  );

  $_ = $_->{payload} for values %$payloads;

  return $payloads;
}

sub iterate_jobs {
  my ($self, $type, $code) = @_;
  my $conn = $self->_conn;

  # NOTE: not ->txn, because we want each job to be updateable ASAP, rather
  # than waiting for every job to work ! -- rjbs, 2011-04-13
  $conn->run(sub {
    my $dbh = $_;

    my $job_sth = $dbh->prepare(
      q{
        SELECT *
        FROM jobs
        WHERE type = ? AND termination_state IS NULL AND locked_at IS NULL
        ORDER BY created_at
      },
    );

    $job_sth->execute($type);

    while (my $job_row = $job_sth->fetchrow_hashref) {
      my $payloads = $self->__payloads_for_job_row($job_row, $dbh);

      # We don't wrap each job in a transaction, because we want to let calls
      # to "done" or "lock" happen immediately.  Otherwise, a very slow job
      # that calls "extend_lock" will be calling it inside a transaction, and
      # it won't be updated in other job iterators!  I general, jobs should not
      # need to do much work inside larger transaction -- that's the point!
      # They will do outside work and mark the job done. -- rjbs, 2011-04-14

      my $ledger = $self->retrieve_ledger_for_guid($job_row->{ledger_guid});
      unless ($ledger) {
        Moonpig::X->throw({
          ident   => "no ledger found for job",
          payload => { ledger_guid => $job_row->{ledger_guid} },
        });
      }

      my $job = Moonpig::Job->new({
        ledger     => $ledger,
        job_id     => $job_row->{id},
        job_type   => $job_row->{type},
        created_at => $job_row->{created_at},
        payloads   => $payloads,
        status     => $job_row->{termination_state} || 'incomplete',

        $self->__job_callbacks($conn, $job_row),
      });
      $job->lock;
      $code->($job);
      $job->unlock;
    }
  });
}

sub undone_jobs_for_ledger {
  my ($self, $ledger) = @_;

  my $conn = $self->_conn;

  my @jobs;

  $conn->run(sub {
    my $dbh = $_;

    my $job_sth = $dbh->prepare(
      q{
        SELECT *
        FROM jobs
        WHERE ledger_guid = ? AND termination_state IS NULL
        ORDER BY created_at
      },
    );

    $job_sth->execute($ledger->guid);
    my $job_rows = $job_sth->fetchall_arrayref({}, );

    @jobs = map {
      Moonpig::Job->new({
        ledger     => $ledger,
        job_id     => $_->{id},
        job_type   => $_->{type},
        created_at => $_->{created_at},
        payloads   => $self->__payloads_for_job_row($_, $dbh),
        status     => $_->{termination_state} || 'incomplete',

        $self->__job_callbacks($conn, $_),
      });
    } @$job_rows;
  });

  return \@jobs;
}

sub save_ledger {
  my ($self, $ledger) = @_;

  # EITHER:
  # 1. we are in a do_rw transaction -- save this ledger to write later
  # 2. we are in a do_ro transaction -- die
  # 3. we are not in a transaction -- die (mjd, 2011-11-02)
  # -- rjbs, 2011-04-11
  if ($self->_in_transaction) {
    if ($self->_in_update_mode) {
      $self->_queue_changed_ledger($ledger);
    } else {
      Moonpig::X->throw("save ledger inside read-only transaction");
    }
  } else {
    Moonpig::X->throw("save ledger outside transaction");
  }
}

sub _queue_changed_ledger {
  my ($self, $ledger) = @_;
  my $q = $self->_ledger_queue;

  # Put it in the ledger cache
  $self->_cache_ledger($ledger);

  {
    my ($x) = $self->_search_queue_for_ledger($ledger);
    if ($x && $x != $ledger) {
      confess("Saved two different ledger objects for guid " . $x->guid . "!\n");
    }
  }
  # put the new ledger at the end
  # if it was in there already, remove it and put it at the end
  @$q = grep { $_->guid ne $ledger->guid } @$q;
  push @$q, $ledger;
}

sub _search_queue_for_ledger {
  my ($self, $guid) = @_;
  my $q = $self->_ledger_queue;
  my ($ledger) = grep { $_->guid eq $guid } @$q;
  return $ledger;
}

sub _execute_saves {
  my ($self) = @_;

  return unless @{ $self->_ledger_queue };
  $self->txn(sub {
    for my $ledger (@{ $self->_ledger_queue }) {
      $self->_store_ledger($ledger);
    }
  });
  @{ $self->_ledger_queue } = ();
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

    my ($count) = $dbh->selectrow_array(
      q{SELECT COUNT(guid) FROM ledgers WHERE guid = ?},
      undef,
      $ledger->guid,
    );

    my $rv = $dbh->do(
      q{
        UPDATE ledgers SET frozen_ledger = ?, frozen_classes = ?
        WHERE guid = ?
      },
      undef,
      nfreeze( $ledger ),
      nfreeze( class_roles ),
      $ledger->guid,
    );

    if ($rv and $rv == 0) {
      # 0E0: no rows affected; we will have to insert -- rjbs, 2011-11-09
      $dbh->do(
        q{
          INSERT INTO ledgers
          (guid, frozen_ledger, frozen_classes)
          VALUES (?, ?, ?)
        },
        undef,
        $ledger->guid,
        nfreeze( $ledger ),
        nfreeze( class_roles ),
      );
    }

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

sub ledger_guids {
  my ($self) = @_;
  my $dbh = $self->_conn->dbh;

  my $guids = $dbh->selectcol_arrayref(q{SELECT DISTINCT guid FROM ledgers});
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

  return $self->_cached_ledger($guid) if $self->_has_cached_ledger($guid);

  my $dbh = $self->_conn->dbh;
  my ($ledger_blob, $class_blob) = $dbh->selectrow_array(
    q{SELECT frozen_ledger, frozen_classes FROM ledgers WHERE guid = ?},
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

  if ($self->_in_update_mode) {
    $self->save_ledger($ledger); # also put it in the cache
  } else {
    $self->_cache_ledger($ledger);
  }

  return $ledger;
}

sub BUILD {
  my ($self) = @_;
  $self->_ensure_tables_exist;
}

1;
