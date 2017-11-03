#!/usr/bin/env perl
use Test::Routine;
use Test::Routine::Util -all;
use Test::Fatal qw(success);
use Test::More;

use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::UsesStorage',
);

use Moonpig::Test::Factory qw(do_with_fresh_ledger);
use t::lib::Logger '$Logger';

use Data::Dumper qw(Dumper);
use Data::GUID qw(guid_string);
use Path::Class;
use Try::Tiny;

use t::lib::ConsumerTemplateSet::Demo;

use namespace::autoclean;

test "xact death" => sub {
  my ($self) = @_;

  my $guid;
  my $failed = try {
    Moonpig->env->storage->_fail_next_save(1);
    do_with_fresh_ledger(
      {
        consumer => {
          template => 'demo-service',
          xid       => "some:xid:" . guid_string,
        }
      },
      sub {
        my ($ledger) = @_;
        $guid = $ledger->guid;
        $ledger->save;
      }
    );
    return 0;
  } catch {
    return 1;
  };

  ok($failed, "we failed the save as requested!");

  my @deliveries = Moonpig->env->email_sender->deliveries;
  is(@deliveries, 1, "...which got us an exception report");
};

test "store and retrieve" => sub {
  my ($self) = @_;

  my $xid = 'yoyodyne:account:' . guid_string;

  my $pid = fork;
  Carp::croak("error forking") unless defined $pid;

  if ($pid) {
    wait;
    if ($?) {
      my %waitpid = (
        status => $?,
        exit   => $? >> 8,
        signal => $? & 127,
        core   => $? & 128,
      );
      die("error with child: " . Dumper(\%waitpid));
    }
  } else {
    do_with_fresh_ledger(
      {
        consumer => {
          template => 'demo-service',
          xid       => $xid,
        }
      },
      sub {
        my ($ledger) = @_;
        $ledger->save;
      }
    );
    exit(0);
  }

  my @guids = Moonpig->env->storage->ledger_guids;

  is(@guids, 1, "we have stored one guid");

  my $ident;
  Moonpig->env->storage->do_with_ledger(
    { ro => 1 },
    $guids[0],
    sub {
      my $consumer = $_[0]->active_consumer_for_xid($xid);
      ok($consumer, "our consumer is there");
      $ident = $_[0]->short_ident;
    }
  );

  Moonpig->env->storage->do_ro(sub {
    my $ledger = Moonpig->env->storage->retrieve_ledger_for_ident($ident);
    is($ledger->guid, $guids[0], "we can get the ledger by ident");
  });

  Moonpig->env->storage->do_rw_with_ledger(
    $guids[0],
    sub {
      my $consumer = $_[0]->active_consumer_for_xid($xid);
      $consumer->_terminate;
    },
  );

  pass('we lived');
};

test "job queue" => sub {
  my ($self) = @_;

  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;

    $ledger->queue_job('test.job.a' => {
      foo => $^T,
      bar => 'serious business',
    });

    $ledger->queue_job('test.job.b' => {
      proc => $$,
      bar  => "..!",
    });
  });

  my @jobs_done;
  Moonpig->env->storage->iterate_jobs('test.job.a' => sub {
    my ($job) = @_;
    isa_ok($job, 'Moonpig::Job');
    is($job->job_id, 1, "cheating: we know we number jobs from 1");
    is_deeply(
      $job->payloads,
      {
        foo => $^T,
        bar => 'serious business',
      },
      "payloads as expected (test.job.a)",
    );
    push @jobs_done, $job->job_id;

    $job->mark_complete;
  });

  Moonpig->env->storage->iterate_jobs('test.job.b' => sub {
    my ($job) = @_;
    isa_ok($job, 'Moonpig::Job');
    is($job->job_id, 2, "cheating: we know we number jobs from 1");
    is_deeply(
      $job->payloads,
      {
        proc => $$,
        bar  => '..!',
      },
      "payloads as expected (test.job.b)",
    );
    push @jobs_done, $job->job_id;

    $job->mark_complete;
  });

  Moonpig->env->storage->iterate_jobs('test.job.b' => sub {
    my ($job) = @_;
    push @jobs_done, $job->job_id;
    fail("should never reach this!");
    $job->mark_complete;
  });

  is_deeply(\@jobs_done, [ 1, 2 ], "completed jobs are completed");
};

test "multiple completion" => sub {
  my ($self) = @_;

  my $guid;

  # Make the ledger exist.
  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;
  });

  Moonpig->env->storage->do_with_ledger(
    $guid,
    sub {
      my ($ledger) = @_;
      $ledger->queue_job('test.job' => { foo => 1, bar => 'not saved' });
    },
  );

  try {
    Moonpig->env->storage->do_rw(sub {
      Moonpig->env->storage->iterate_jobs('test.job' => sub {
        my ($job) = @_;
        $job->mark_complete;
        $job->mark_complete;
      });
    });
  } catch {
    ok($_, "can't mark a job complete twice");
  } success {
    fail("we marked a job done twice");
  };
};

test "jobs and xacts" => sub {
  plan tests => 2;
  my ($self) = @_;

  my $guid;

  # Make the ledger exist.
  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;
    $guid = $ledger->guid;
  });

  try {
    Moonpig->env->storage->do_with_ledger(
      $guid,
      sub {
        my ($ledger) = @_;

        $ledger->queue_job('test.job.a' => { foo => 1, bar => 'not saved' });

        $ledger->queue_job('test.job.a' => { foo => 3, bar => 'not saved' });

        die "failsauce\n";
      },
    );
  } catch {
    if (@_) { is($_[0], "failsauce\n", "fated-to-die block died"); }
    else    { fail("fated-to-die block died"); }
  };

  Moonpig->env->storage->do_with_ledger(
    { ro => 1 },
    $guid,
    sub {
      my ($ledger) = @_;

      is_deeply($ledger->job_array, [], "no jobs actually queued");
    },
  );
};

test "jobs left unfinished" => sub {
  my ($self) = @_;

  do_with_fresh_ledger({}, sub {
    my ($ledger) = @_;

    $ledger->queue_job('test.job' => {
      foo => $^T,
      bar => 'serious business',
    });
  });

  my $message = "I got handled by a stupid no-op handler.";

  Moonpig->env->storage->do_rw(sub {
    Moonpig->env->storage->iterate_jobs('test.job' => sub {
      my ($job) = @_;
      $job->log($message);
    });
  });

  my $ran = 0;
  Moonpig->env->storage->do_rw(sub {
    Moonpig->env->storage->iterate_jobs('test.job' => sub {
      my ($job) = @_;
      $ran = 1;

      my $logs = $job->get_logs;

      is(@$logs, 1, "we have a log for this job");
      is($logs->[0]{message}, $message, "it's the right message");
    });
  });

  ok($ran, "the job was unlocked after the previous work");
};

test "cache clearing" => sub {
  my ($self) = @_;

  {
    my @cache = Moonpig->env->storage->_ledger_cache_contents;
    is(@cache, 0, "the cache is empty!");
  }

  my $guid;
  do_with_fresh_ledger(
    {
      consumer => {
        template => 'demo-service',
        xid       => guid_string,
      }
    },
    sub {
      my ($ledger) = @_;
      $guid = $ledger->guid;

      {
        my %cache = Moonpig->env->storage->_ledger_cache_contents;
        is(keys %cache, 1, "we are alone in the cache");
      }

      $ledger->save;
    }
  );

  Moonpig->env->storage->do_rw_with_ledger(
    $guid,
    sub {
      my ($ledger) = @_;

      {
        my %cache = Moonpig->env->storage->_ledger_cache_contents;
        is(keys %cache, 1, "we have cached exactly one ledger");
      }

      Moonpig->env->storage->do_rw_with_ledger(
        $guid,
        sub {
          my %cache = Moonpig->env->storage->_ledger_cache_contents;
          is(keys %cache, 1, "we have cached exactly one ledger");
        },
      );

      {
        my %cache = Moonpig->env->storage->_ledger_cache_contents;
        is(keys %cache, 1, "we have cached exactly one ledger");
      }
    }
  );
};

test "crash saving ledger doesn't leave it lying around" => sub {
  my ($self) = @_;

  my $xid = 'yoyodyne:account:' . guid_string;
  my $xid2 = 'yoyodyne:account:' . guid_string;

  my $pid = fork;
  Carp::croak("error forking") unless defined $pid;

  if ($pid) {
    wait;
    if ($?) {
      my %waitpid = (
        status => $?,
        exit   => $? >> 8,
        signal => $? & 127,
        core   => $? & 128,
      );
      die("error with child: " . Dumper(\%waitpid));
    }
  } else {
    do_with_fresh_ledger(
      {
        consumer => {
          template => 'demo-service',
          xid       => $xid,
        }
      },
      sub {
        my ($ledger) = @_;
        $ledger->save;
      }
    );
    do_with_fresh_ledger(
      {
        consumer => {
          template => 'demo-service',
          xid       => $xid2,
        }
      },
      sub {
        my ($ledger) = @_;
        $ledger->save;
      }
    );
    exit(0);
  }

  my @guids = Moonpig->env->storage->ledger_guids;

  is(@guids, 2, "we have stored two guids");

  # Fun time, let's break first guid
  {
    local $ENV{MOONPIG_CRASH_SAVING_LEDGER} = 1;

    eval {
      Moonpig->env->storage->do_rw_with_ledger(
        $guids[0],
        sub {},
      );
    };
  }

  is(
    @{ Moonpig->env->storage->_ledger_queue },
    0,
    'no items in ledger queue'
  );

  # Now save it in another process so if we try to
  # save it we get a conflict
  my $pid2 = fork;
  Carp::croak("error forking") unless defined $pid2;

  if ($pid2) {
    wait;
    if ($?) {
      my %waitpid = (
        status => $?,
        exit   => $? >> 8,
        signal => $? & 127,
        core   => $? & 128,
      );
      die("error with child: " . Dumper(\%waitpid));
    }
  } else {
      Moonpig->env->storage->do_rw_with_ledger(
        $guids[0],
        sub {},
      );
    exit(0);
  }

  # Now lets save second ledger. Should not retry
  # first
  Moonpig->env->storage->do_rw_with_ledger(
    $guids[1],
    sub {},
  );

  pass('we lived');
};

run_me;
done_testing;
