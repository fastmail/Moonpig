package Moonpig::Storage::Spike;
# ABSTRACT: Basic implementation of Moonpig persistent storage
use Moose;
with 'Moonpig::Role::Storage';

use v5.12.0;

use MooseX::StrictConstructor;

use Carp qw(carp confess croak);
use Data::GUID qw(guid_string);
use Data::Visitor::Callback;
use Digest::MD5 qw(md5_hex);
use DBI;
use DBIx::Connector;
use File::Spec;
use IO::Compress::Gzip ();
use IO::Uncompress::Gunzip ();
use Moonpig::Job;
use Moonpig::Logger '$Logger';
use Moonpig::Storage::UpdateModeStack;
use Moonpig::Types qw(Factory GUID Ledger);
use Moonpig::Util qw(class class_roles random_short_ident);
use MooseX::Types::Moose qw(Str);
use Scalar::Util qw(blessed);
use Sereal::Decoder;
use Sereal::Encoder;
use SQL::Translator;
use Storable qw(nfreeze thaw);
use Try::Tiny;

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
  builder  => '_new_connection',
  clearer  => '_clear_connection',
);

sub reset_connection {
  my ($self) = @_;
  Moonpig::X->throw("can't reset connection during transaction")
    if $self->_in_transaction;
  $self->_clear_connection;
}

sub _new_connection {
  my ($self) = @_;
  return DBIx::Connector->new( $self->dbi_connect_args );
}

my $schema_yaml = <<'...';
---
schema:
  tables:
    ledgers:
      name: ledgers
      fields:
        guid: { name: guid, data_type: varchar, size: 36, is_primary_key: 1 }
        entity_id: { name: entity_id, data_type: varchar, size: 36, is_nullable: 0 }
        ident: { name: ident, data_type: varchar, size: 10, is_nullable: 0 }
        serialization_version: { name: serialization_version, data_type: int unsigned, is_nullable: 0 }
        frozen_ledger: { name: frozen_ledger, data_type: longblob, is_nullable: 0 }
        frozen_classes: { name: frozen_classes, data_type: longblob, is_nullable: 0 }
      constraints:
        - type: UNIQUE
          fields: [ ident ]
          name: ledger_ident_unique_constraint

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

    all_xid_ledgers:
      name: all_xid_ledgers
      fields:
        xid: { name: xid, data_type: varchar, size: 256, is_nullable: 0 }
        ledger_guid: { name: ledger_guid, data_type: varchar, size: 36, is_nullable: 0 }
      constraints:
        - type:   PRIMARY KEY
          fields: [ xid, ledger_guid ]
        - type: FOREIGN KEY
          fields: [ ledger_guid ]
          reference_table: ledgers
          reference_fields: [ guid ]

    ledger_search_fields:
      name: ledger_search_fields
      fields:
        ledger_guid: { name: ledger_guid, data_type: varchar, size: 36, is_nullable: 0 }
        field_name: { name: field_name, data_type: varchar, size: 36, is_nullable: 0 }
        field_value: { name: field_value, data_type: varchar, size: 128, is_nullable: 0 }
      constraints:
        - type: FOREIGN KEY
          fields: [ ledger_guid ]
          reference_table: ledgers
          reference_fields: [ guid ]
          on_delete: cascade

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
      constraints:
        - type: FOREIGN KEY
          fields: [ ledger_guid ]
          reference_table: ledgers
          reference_fields: [ guid ]

    job_receipts:
      name: job_receipts
      fields:
        job_id: { name: job_id, data_type: integer, is_primary_key: 1 }
        terminated_at: { name: terminated_at, data_type: integer, is_nullable: 0 }
        termination_state: { name: termination_state, data_type: varchar, size: 32, is_nullable: 1 }
      constraints:
        - type: FOREIGN KEY
          fields: [ job_id ]
          reference_table: jobs
          reference_fields: [ id ]
          on_delete: cascade
        - type: UNIQUE
          fields: [ job_id ]
          name: job_receipts_job_id_unique_constraint

    job_documents:
      name: job_documents
      fields:
        job_id: { name: job_id, data_type: integer, is_nullable: 0 }
        ident: { name: ident, data_type: varchar, size: 64, is_nullable: 0 }
        payload: { name: payload, data_type: longtext, is_nullable: 0 }
      constraints:
        - type:   PRIMARY KEY
          fields: [ job_id, ident ]
        - type: FOREIGN KEY
          fields: [ job_id ]
          reference_table: jobs
          reference_fields: [ id ]
          on_delete: cascade

    job_logs:
      name: job_logs
      fields:
        id: { name: id, data_type: integer, is_auto_increment: 1, is_primary_key: 1 }
        job_id: { name: job_id, data_type: integer, is_nullable: 0 }
        logged_at: { name: logged_at, data_type: integer, is_nullable: 0 }
        message: { name: message, data_type: text, is_nullable: 0 }
      constraints:
        - type: FOREIGN KEY
          fields: [ job_id ]
          reference_table: jobs
          reference_fields: [ id ]
          on_delete: cascade
...

my $SCHEMA_MD5 = md5_hex($schema_yaml);

sub _sql_hunks_to_deploy_schema {
  my ($self) = @_;

  my $translator = SQL::Translator->new(
    parser   => "YAML",
    data     => \$schema_yaml,
    producer      => $self->sql_translator_producer,
    producer_args => {
      no_transaction => 1,
      $self->sql_translator_producer_args,
    },
  );

  my $sql = $translator->translate or die $translator->error;
  my @hunks = split /\n{2,}/, $sql;
  return @hunks;
}

sub _ensure_tables_exist {
  my ($self) = @_;

  my $conn = $self->_conn;

  my $did_deploy = $conn->txn(sub {
    my ($dbh) = $_;

    my ($schema_md5) = eval {
      $dbh->selectrow_array("SELECT schema_md5 FROM metadata");
    };

    return 0 if defined $schema_md5 and $schema_md5 eq $SCHEMA_MD5;
    if (defined $schema_md5) {
      Carp::croak( <<END_ERR );
database is of an incompatible schema
want: $SCHEMA_MD5
have: $schema_md5
END_ERR
    }

    $Logger->log([
      "deploying %s v%s schema",
      __PACKAGE__,
      __PACKAGE__->VERSION // '(undef)',
    ]);

    my @hunks = $self->_sql_hunks_to_deploy_schema;

    $dbh->do($_) for @hunks;

    $dbh->do(
      q{
        INSERT INTO metadata (one, schema_md5, last_realtime, last_moontime)
        VALUES (1, ?, ?, ?)
      },
      undef,
      $SCHEMA_MD5,
      (0) x 2,
    );

    return 1;
  });

  $Logger->log("deployment complete") if $did_deploy;
}

has _update_mode_stack => (
  is  => 'ro',
  isa => 'Moonpig::Storage::UpdateModeStack',
  default => sub { Moonpig::Storage::UpdateModeStack->new() },
  handles => {
    _has_update_mode => 'is_nonempty',
    _in_transaction => 'is_nonempty',
    _push_update_mode => 'push',
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
  my $rv = $self->__with_update_mode(1, sub {
    return $self->txn(sub {
      my $rv = $code->();
      $self->_execute_saves unless $self->_in_nested_transaction;
      return $rv;
    });
  });
  return $rv;
}

sub do_ro {
  my ($self, $code) = @_;
  my $rv = $self->__with_update_mode(0, sub {
    return $self->txn(sub {
      $code->();
    });
  });
  return $rv;
}

sub __with_update_mode {
  my ($self, $mode, $code) = @_;

  my $at_top = ! $self->_has_update_mode;
  state $xact_pid_id = 1;

  my $xact_id = $at_top ? join(q{.}, $$, $xact_pid_id++) : undef;

  local $Logger = $Logger->proxy({ proxy_prefix => "xact<$xact_id>: " })
    if $at_top;

  if ($at_top and ! $self->_ledger_cache_is_empty) {
    my $error = "ledger cache not empty when beginning top-level xact";
    Moonpig->env->report_exception(
      [ [ exception => $error ] ]
    );
    Moonpig::X->throw($error);
  }

  $Logger->log("transaction begun") if $at_top;

  # The 'popper' here is an object which pops the mode stack when it
  # goes out of scope.  The sub argument is a callback that is invoked
  # if the stack becomes empty as a result.
  #
  # Properly, we should track which ledgers are used in each nested
  # transaction, and whenver a transaction ends, flush the ones that
  # were used by only that transaction, but eh, that's too much
  # trouble. So instead, we just hold them all until the final
  # transaction ends and flush them all then. mjd 2011-11-14
  my $popper = $self->_push_update_mode($mode, sub { $self->_flush_ledger_cache });

  my $rv = try {
    $code->();
  } catch {
    $Logger->log("transaction aborted by exception") if $at_top;
    die $_;
  };

  $Logger->log("transaction completed") if $at_top;

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

  my $rv;
  $self->__with_update_mode( ! $ro, sub {
    my @ledgers = ();
    for my $i (0 .. $#$guids) {
      defined($guids->[$i])
        or croak "Guid element $i was undefined";
      my $ledger = $self->retrieve_ledger_for_guid($guids->[$i])
        or croak "Couldn't find ledger for guid '$guids->[$i]'";
      push @ledgers, $ledger;
    }

    $rv = $self->txn(sub {
      my $rv = $code->(@ledgers);
      unless ($ro) {
        $_->save for @ledgers;
        $self->_execute_saves;
      }
      return $rv;
    });
  });

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
  croak "ro option forbidden in do_ro_with_ledgers" if exists $opts->{ro};
  $self->do_with_ledgers({ %$opts, ro => 1 }, $guids, $code);
}

sub do_with_each_ledger {
  if (@_ == 2) {
    splice @_, 1, 0, {}; # $opts was omitted, so splice it in
  }
  my ($self, $opts, $code) = @_;
  my @guids = $self->ledger_guids;
  for my $i (0 .. $#guids) {
    local ${^Progress} = [ $i, scalar(@guids) ]; # progress meter
    $self->do_with_ledgers($opts, [ $guids[$i] ], $code);
  }
}

# This cache is getting complicated. It should be turned into an object.
# 20120229 mjd
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
    _ledger_cache_contents => 'elements', # in case of emergency
    _ledger_cache_is_empty => 'is_empty',
  },
);

sub _cache_ledger {
  my ($self, $ledger) = @_;
  my $cache = $self->_ledger_cache;
  my $guid = $ledger->guid;

  if (exists $cache->{$guid} && $ledger != $cache->{$guid}) {
    confess sprintf "Tried to cache ledger %s = 0x%x, but ledger 0x%x was already cached there!",
      $guid, $ledger, $cache->{$guid};
  }

  $self->_ledger_cache->{$ledger->guid} = $ledger;
}

has _ledger_queue => (
  is  => 'ro',
  isa => 'ArrayRef',
  init_arg => undef,
  default  => sub {  []  },
);

sub queue_job {
  my ($self, $ledger, $arg) = @_;

  if ($self->_has_update_mode and $self->_in_update_mode) {
    $self->__queue_job($ledger, $arg);
  } else {
    Moonpig::X->throw("queue_job outside of read-write transaction");
  }
}

sub __queue_job {
  my ($self, $ledger, $arg) = @_;
  $arg->{payloads} //= {};

  # We know this won't be called outside a transaction, so it doesn't matter to
  # us whether or not we log the begin/end of this transaction. -- rjbs,
  # 2012-05-04
  $self->txn(sub {
    my $dbh = $_;
    $dbh->do(
      q{INSERT INTO jobs (type, ledger_guid, created_at) VALUES (?, ?, ?)},
      undef,
      $arg->{type},
      $ledger->guid,
      Moonpig->env->now->epoch,
    );

    my $job_id = $dbh->last_insert_id(q{}, q{}, 'jobs', 'id');

    for my $ident (keys %{ $arg->{payloads} }) {
      my $payload = $arg->{payloads}->{ $ident };
      Str->assert_valid($payload);

      $dbh->do(
        q{
          INSERT INTO job_documents (job_id, ident, payload)
          VALUES (?, ?, ?)
        },
        undef,
        $job_id,
        $ident,
        $payload,
      );
    }
  });
}

sub __job_callbacks {
  my ($spike, $conn, $job_row) = @_;

  return (
    log_callback  => sub {
      my ($self, $message) = @_;
      $spike->_conn->run(sub { $_->do(
        "INSERT INTO job_logs (job_id, logged_at, message)
        VALUES (?, ?, ?)",
        undef, $job_row->{id}, Moonpig->env->now->epoch, $message,
      )});
    },
    get_logs_callback => sub {
      my ($self) = @_;

      my $logs = $spike->_conn->run(sub { $_->selectall_arrayref(
        "SELECT * FROM job_logs WHERE job_id = ? ORDER BY logged_at",
        { Slice => {} },
        $job_row->{id},
      )});

      $_->{logged_at} = Moonpig::DateTime->new($_->{logged_at})
        for @$logs;

      return $logs;
    },

    cancel_callback => sub {
      my ($self) = @_;
      $spike->_conn->run(sub {
        my $dbh = $_;
        $dbh->do(
          "INSERT INTO job_logs (job_id, logged_at, message)
          VALUES (?, ?, ?)",
          undef, $job_row->{id}, Moonpig->env->now->epoch, 'job canceled',
        );
        $dbh->do(
          "INSERT INTO job_receipts (job_id, terminated_at, termination_state)
          VALUES (?, ?, ?)",
          undef, $job_row->{id}, Moonpig->env->now->epoch, 'canceled',
        );
      });
    },
    delete_callback => sub {
      my ($self) = @_;
      Moonpig::X->throw("can't delete an incomplete job")
        if $self->status eq 'incomplete';
      $spike->_conn->run(sub {
        my $dbh = $_;
        $dbh->do("DELETE FROM jobs WHERE id = ?", undef, $job_row->{id});
      });
    },
    mark_complete_callback => sub {
      my ($self) = @_;
      $spike->_conn->run(sub {
        my $dbh = $_;
        $dbh->do(
          "INSERT INTO job_logs (job_id, logged_at, message)
          VALUES (?, ?, ?)",
          undef, $job_row->{id}, Moonpig->env->now->epoch, 'job complete',
        );
        $dbh->do(
          "INSERT INTO job_receipts (job_id, terminated_at, termination_state)
          VALUES (?, ?, ?)",
          undef, $job_row->{id}, Moonpig->env->now->epoch, 'done',
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
  my $self = shift;
  my ($type, $arg, $code);

  if (@_ == 2) {
    ($type, $code) = @_;
  } elsif (@_ == 3) {
    ($type, $arg, $code) = @_;
  } else {
    Moonpig::X->throw("weird argc to iterate_jobs: " . 0+@_);
  }

  my $incomplete_sql = $arg->{completed_jobs} ? 'IS NOT NULL' : 'IS NULL';

  my $conn = $self->_conn;

  # NOTE: not ->txn, because we want each job to be updateable ASAP, rather
  # than waiting for every job to work ! -- rjbs, 2011-04-13
  $conn->run(sub {
    my $dbh = $_;

    my $job_sth;

    if (defined $type) {
      $job_sth = $dbh->prepare(
        qq{
          SELECT *
          FROM jobs
          LEFT JOIN job_receipts ON jobs.id = job_receipts.job_id
          WHERE type = ? AND termination_state $incomplete_sql
          ORDER BY created_at
        },
      );

      $job_sth->execute($type);
    } else {
      $job_sth = $dbh->prepare(
        qq{
          SELECT *
          FROM jobs
          LEFT JOIN job_receipts ON jobs.id = job_receipts.job_id
          WHERE termination_state $incomplete_sql
          ORDER BY created_at
        },
      );

      $job_sth->execute;
    }

    while (my $job_row = $job_sth->fetchrow_hashref) {
      my $payloads = $self->__payloads_for_job_row($job_row, $dbh);

      # We don't wrap each job in a transaction, because we want to let calls
      # to "done" or "lock" happen immediately.  Otherwise, a very slow job
      # that calls "extend_lock" will be calling it inside a transaction, and
      # it won't be updated in other job iterators!  I general, jobs should not
      # need to do much work inside larger transaction -- that's the point!
      # They will do outside work and mark the job done. -- rjbs, 2011-04-14

      my $job = Moonpig::Job->new({
        job_id      => $job_row->{id},
        job_type    => $job_row->{type},
        created_at  => $job_row->{created_at},
        payloads    => $payloads,
        status      => $job_row->{termination_state} || 'incomplete',
        ledger_guid => $job_row->{ledger_guid},

        $self->__job_callbacks($conn, $job_row),
      });

      $code->($job);
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
        LEFT JOIN job_receipts ON jobs.id = job_receipts.job_id
        WHERE ledger_guid = ? AND termination_state IS NULL
        ORDER BY created_at
      },
    );

    $job_sth->execute($ledger->guid);
    my $job_rows = $job_sth->fetchall_arrayref({}, );

    @jobs = map {
      Moonpig::Job->new({
        job_id      => $_->{id},
        job_type    => $_->{type},
        created_at  => $_->{created_at},
        payloads    => $self->__payloads_for_job_row($_, $dbh),
        status      => $_->{termination_state} || 'incomplete',
        ledger_guid => $ledger->guid,

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

  for my $ledger (@{ $self->_ledger_queue }) {
    $self->_store_ledger($ledger);
  }

  @{ $self->_ledger_queue } = ();
}

sub _restore_save_packet {
  my ($self, $packet) = @_;

  my $version = $packet->{version};

  Carp::confess("illegal save packet version: $version")
    unless defined $version and $version =~ /\A[0-9]+\z/;

  my $method = "__restore_v$version\_packet";

  Carp::confess("can't restore save packet of version $version")
    unless $self->can($method);

  return $self->$method($packet);
}

sub __restore_v1_packet {
  my ($self, $packet) = @_;

  my ($ledger_blob, $class_blob) = @$packet{qw(frozen_ledger frozen_classes)};

  require Moonpig::DateTime; # has a STORABLE_freeze -- rjbs, 2011-03-18

  if (substr($ledger_blob, 0, 2) eq "\x1F\x8B") {
    # The gzip marker!
    my $buffer;
    Carp::confess(
      "error gunzipping ledger: $IO::Uncompress::Gunzip::GunzipError"
    ) unless IO::Uncompress::Gunzip::gunzip(\$ledger_blob, \$buffer);

    $ledger_blob = $buffer;
  }

  my $class_map = thaw($class_blob);
  my $ledger    = thaw($ledger_blob);

  $self->_perform_reblessing($ledger, $class_map);

  return $ledger;
}

has _sereal_encoder => (
  is   => 'ro',
  lazy => 1,
  init_arg => undef,
  default  => sub { Sereal::Encoder->new },
);

has _sereal_decoder => (
  is   => 'ro',
  lazy => 1,
  init_arg => undef,
  default  => sub { Sereal::Decoder->new },
);

sub __restore_v2_packet {
  my ($self, $packet) = @_;

  my ($ledger_blob, $class_blob) = @$packet{qw(frozen_ledger frozen_classes)};

  require Moonpig::DateTime; # XXX does NOT provide Sereal hooks

  if (substr($ledger_blob, 0, 2) eq "\x1F\x8B") {
    # The gzip marker!
    my $buffer;
    Carp::confess(
      "error gunzipping ledger: $IO::Uncompress::Gunzip::GunzipError"
    ) unless IO::Uncompress::Gunzip::gunzip(\$ledger_blob, \$buffer);

    $ledger_blob = $buffer;
  }

  my $class_map = $self->_sereal_decoder->decode($class_blob);
  my $ledger    = $self->_sereal_decoder->decode($ledger_blob);

  $self->_perform_reblessing($ledger, $class_map);

  return $ledger;
}

sub _perform_reblessing {
  my ($self, $ledger, $class_map) = @_;

  my %class_for;
  for my $old_class (keys %$class_map) {
    my $new_class = class(@{ $class_map->{ $old_class } });
    next if $new_class eq $old_class;

    $class_for{ $old_class } = $new_class;
  }

  Data::Visitor::Callback->new({
    object => sub {
      my (undef, $obj) = @_;
      my $class = blessed $obj;
      return unless exists $class_for{ $class };
      bless $obj, $class_for{ $class };
    }
  })->visit($ledger);
}

sub _save_packet_for {
  my ($self, $ledger) = @_;

  my $guid = $ledger->guid;
  my $frozen_ledger = $self->_sereal_encoder->encode($ledger);

  my $gz_frozen_ledger;
  Carp::confess(
    "error gzipping ledger $guid: $IO::Compress::Gzip::GzipError"
  ) unless IO::Compress::Gzip::gzip(\$frozen_ledger, \$gz_frozen_ledger);

  return {
    version   => 2,
    ledger    => $gz_frozen_ledger,
    classes   => $self->_sereal_encoder->encode( class_roles ),
    entity_id => guid_string(),
  };
}

sub _store_ledger {
  my ($self, $ledger) = @_;

  unless ($self->_has_update_mode and $self->_in_update_mode) {
    Moonpig::X->throw("_store_ledger outside of read-write transaction");
  }

  Ledger->assert_valid($ledger);

  my $guid = $ledger->guid;

  $Logger->log_debug([
    'storing %s under guid %s',
    $ledger->ident,
    $guid,
  ]);

  my $ident;

  try {
    my $conn = $self->_conn;
    $conn->txn(sub {
      my ($dbh) = @_;

      my ($count) = $dbh->selectrow_array(
        q{SELECT COUNT(guid) FROM ledgers WHERE guid = ?},
        undef,
        $guid,
      );

      $ledger->prepare_to_be_saved;

      my $save_packet = $self->_save_packet_for($ledger);

      my $rv = $dbh->do(
        q{
          UPDATE ledgers SET
            frozen_ledger = ?,
            frozen_classes = ?,
            entity_id = ?,
            serialization_version = ?
          WHERE guid = ?
        },
        undef,
        $save_packet->{ledger},
        $save_packet->{classes},
        $save_packet->{entity_id},
        $save_packet->{version},
        $guid,
      );

      if ($rv and $rv == 0) {
        # 0E0: no rows affected; we will have to insert -- rjbs, 2011-11-09

        # This shouldn't really ever happen -- if it already has a short_ident,
        # that means you have saved it once, so the UPDATE above should have
        # been useful.  Still, there is no need to forbid this right now, so
        # let's just carry on as usual.  We won't keep trying to insert over
        # and over, though.  If we have an ident and can't insert, we give up.
        # -- rjbs, 2012-02-14
        my $existing_ident = $ledger->short_ident;

        my $saved = 0;

        until ($saved) {
          $saved = try {
            $conn->svp(sub {
              my ($dbh) = @_;
              my $ident = $existing_ident // 'L-' . random_short_ident(1e9);

              $ledger->set_short_ident($ident) unless $existing_ident;

              my $save_packet = $self->_save_packet_for($ledger);

              $dbh->do(
                q{
                  INSERT INTO ledgers
                  (guid, ident, serialization_version, frozen_ledger,
                  frozen_classes, entity_id)
                  VALUES (?, ?, ?, ?, ?, ?)
                },
                undef,
                $guid,
                $ident,
                $save_packet->{version},
                $save_packet->{ledger},
                $save_packet->{classes},
                $save_packet->{entity_id},
              );

              return 1;
            });
          };

          if ($existing_ident && ! $saved) {
            Moonpig::X->throw("conflict inserting ledger with preset ident");
          }
        }
      }

      $dbh->do(
        q{DELETE FROM xid_ledgers WHERE ledger_guid = ?},
        undef,
        $guid,
      );

      $dbh->do(
        q{DELETE FROM all_xid_ledgers WHERE ledger_guid = ?},
        undef,
        $guid,
      );

      my $xid_sth = $dbh->prepare(
        q{INSERT INTO xid_ledgers (xid, ledger_guid) VALUES (?,?)},
      );

      for my $xid ($ledger->active_xids) {
        $xid_sth->execute($xid, $guid);
      }

      my $all_xid_sth = $dbh->prepare(
        q{INSERT INTO all_xid_ledgers (xid, ledger_guid) VALUES (?,?)},
      );

      my %seen;
      for my $consumer ($ledger->consumers) {
        next if $seen{ $consumer->xid }++;
        $all_xid_sth->execute($consumer->xid, $guid);
      }

      if ($self->_fail_next_save) {
        $self->_fail_next_save(0);
        Moonpig::X->throw("fail_next_save was true");
      }
    });
  } catch {
    my $error = $_;

    Moonpig->env->report_exception(
      [
        [ exception => Carp::longmess("error while saving ledger") ],
        [ misc => {
          ledger_guid => $guid,
          error       => $error,
          cache_keys  => [ keys %{ {$self->_ledger_cache_contents} } ],
          xact_stack  => $self->_update_mode_stack,
          active_xids => [ $ledger->active_xids ],
        } ],
      ],
      { handled => 1 },
    );

    # In some cases, the cache or other memory state becomes corrupted.  We've
    # called the "The Bug" in the past.  We've never found the root cause, but
    # the symptom is that when trying to save ledger X, it seems to be trying
    # to save Y instead.  When this happens, all saves start failing.  This has
    # the incredibly nasty fallout that attempts to record received payments
    # fail and users retry them.  There are a number of things that must be
    # solved here, but the first one is: stop taking requests when the state is
    # corrupted.  -- rjbs, 2013-11-13
    $self->_is_corrupted(1);

    die $error;
  };

  return $ledger;
}

has _is_corrupted => (
  is  => 'rw',
  isa => 'Bool',
  init_arg => undef,
  default  => 0,
);

has _fail_next_save => (
  is  => 'rw',
  isa => 'Bool',
  default => 0,
);

sub _reinstate_stored_time {
  my ($self) = @_;

  my ($real, $moon) = $self->_conn->dbh->selectrow_array(
    "SELECT last_realtime, last_moontime FROM metadata",
  );

  # clock never stored
  return if $real == 0 && $moon == 0;

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

sub retrieve_ledger_unambiguous_for_xid {
  my ($self, $xid) = @_;

  my $active = $self->retrieve_ledger_active_for_xid($xid);
  return $active if $active;

  my @guids = $self->ledger_guids_for_xid($xid);

  if (@guids == 1) {
    $Logger->log_debug([ 'resolved xid %s to %s as inactive but unambigious',
      $xid,
      $guids[0],
    ]);

    return $self->retrieve_ledger_for_guid($guids[0]);
  }

  return;
}

sub retrieve_ledger_active_for_xid {
  my ($self, $xid) = @_;

  my $dbh = $self->_conn->dbh;

  my ($ledger_guid) = $dbh->selectrow_array(
    q{SELECT ledger_guid FROM xid_ledgers WHERE xid = ?},
    undef,
    $xid,
  );

  return unless $ledger_guid;

  $Logger->log_debug([ 'resolved xid %s to %s by active service',
    $xid,
    $ledger_guid,
  ]);
  return $self->retrieve_ledger_for_guid($ledger_guid);
}

sub ledger_guids_for_xid {
  my ($self, $xid) = @_;

  my $dbh = $self->_conn->dbh;

  my $guids = $dbh->selectcol_arrayref(
    q{SELECT ledger_guid FROM all_xid_ledgers WHERE xid = ?},
    undef,
    $xid,
  );

  return @$guids;
}

sub retrieve_ledger_for_ident {
  my ($self, $ident) = @_;

  return $self->retrieve_ledger_for_guid($ident) if GUID->check($ident);

  my $dbh = $self->_conn->dbh;

  my ($guid) = $dbh->selectrow_array(
    q{SELECT guid FROM ledgers WHERE ident = ?},
    undef,
    $ident,
  );

  return unless defined $guid;

  $Logger->log_debug([ 'retrieved guid %s for ident %s', $guid, $ident ]);

  return $self->retrieve_ledger_for_guid($guid);
}

sub retrieve_ledger_for_guid {
  my ($self, $guid) = @_;

  unless ($self->_in_transaction) {
    Moonpig::X->throw("retrieve_ledger outside of transaction");
  }

  $Logger->log_debug([ 'retrieving ledger under guid %s', $guid ]);

  my $ledger;
  $ledger = $self->_cached_ledger($guid) if $self->_has_cached_ledger($guid);

  $ledger ||= $self->_retrieve_ledger_from_db($guid);

  return unless $ledger;

  if ($self->_in_update_mode) {
    $self->save_ledger($ledger); # also put it in the cache
  } elsif ($self->_in_transaction) {
    $self->_cache_ledger($ledger);
  }

  return $ledger;
}

sub _retrieve_ledger_from_db {
  my ($self, $guid) = @_;

  my $dbh = $self->_conn->dbh;
  my $save_packet = $dbh->selectrow_hashref(
    q{SELECT
      frozen_ledger, frozen_classes, serialization_version, entity_id
    FROM ledgers WHERE guid = ?},
    undef,
    $guid,
  );

  # rather than use "serialization_version AS version" to avoid finding out
  # version is a keyword -- rjbs, 2012-12-13
  $save_packet->{version} = delete $save_packet->{serialization_version};

  Carp::confess("incomplete storage data found for $guid") unless $save_packet;

  return $self->_restore_save_packet($save_packet);
}

sub delete_ledger_by_guid {
  my ($self, $guid) = @_;

  $self->txn(sub {
    my $dbh = $_;
    # XXX: Assert that ledger cache is empty?  We don't want someone deleting a
    # ledger mid-transaction, only to have it saved at the transaction's end.
    # Then again, we might want to route to this with (DELETE /ledger/...)
    # which means we'll have retrieved the ledger, first.
    # This needs discussion once we're past the "this is here for use by rjbs
    # when testing crap by hand" phase. -- rjbs, 2012-01-25
    $dbh->do("DELETE FROM jobs WHERE ledger_guid = ?", undef, $guid);
    $dbh->do("DELETE FROM xid_ledgers WHERE ledger_guid = ?", undef, $guid);
    $dbh->do("DELETE FROM ledgers WHERE guid = ?", undef, $guid);
  });
}

sub BUILD {
  my ($self) = @_;
  $self->_ensure_tables_exist;
}

1;
