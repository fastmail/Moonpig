use 5.12.0;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class days dollars months sumof to_dollars years);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

with ('Moonpig::Test::Role::UsesStorage');

has xid => (
  isa => 'Str',
  is  => 'ro',
  default => sub { state $i = 0; $i++; "consumer:b5g1:$i"; },
);

package B5G1::Summary {
  sub new { bless $_[1] => $_[0] }
  sub consumers { @{ $_[0] } }

  sub head { $_[0]->[0] }

  sub free_consumers {
    grep { $_->does('Moonpig::Role::Consumer::SelfFunding') } @{ $_[0] };
  }

  sub paid_consumers {
    grep { ! $_->does('Moonpig::Role::Consumer::SelfFunding') } @{ $_[0] };
  }

  sub free_indexes {
    my ($self) = @_;
    grep { $self->[$_]->does('Moonpig::Role::Consumer::SelfFunding') }
      0 .. $#$self;
  }

  sub paid_indexes {
    my ($self) = @_;
    grep { ! $self->[$_]->does('Moonpig::Role::Consumer::SelfFunding') }
      0 .. $#$self;
  }
}

sub b5_summary {
  my ($self, $ledger) = @_;

  my $head = $ledger->active_consumer_for_xid( $self->xid );
  my @consumers = ($head, $head->replacement_chain);
  B5G1::Summary->new(\@consumers);
}

before run_test => sub {
  Moonpig->env->reset_clock;
};

sub pay_unpaid_invoices {
  my ($self, $ledger, $expect) = @_;

  my $total = sumof { $_->total_amount } $ledger->payable_invoices;
  if (defined $expect) {
    is(
      $total,
      $expect,
      sprintf("invoices should total \$%.2f", to_dollars($expect)),
    )
  } else {
    note sprintf("Total amount payable: \$%.2f", to_dollars($total));
  }
  $ledger->add_credit(class('Credit::Simulated'), { amount => $total });
  $ledger->process_credits;
}

test 'signup for five, get one free' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      b5 => {
        xid      => $self->xid,
        template => 'b5g1_paid',
        minimum_chain_duration => years(5),
      },
    },
    sub {
      my ($ledger) = @_;

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(500));

      my $summ = $self->b5_summary($ledger);

      is($summ->consumers, 6, "there are six consumers");

      is($summ->paid_consumers, 5, "five are paid");
      is($summ->free_consumers, 1, "one is free");
      is_deeply([$summ->free_indexes], [5], "...and the free one is last");
    },
  );
};

test 'signup for one, buy five more, have one' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      b5 => {
        xid      => $self->xid,
        template => 'b5g1_paid',
      },
    },
    sub {
      my ($ledger) = @_;

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(100));

      $ledger->active_consumer_for_xid($self->xid)
             ->adjust_replacement_chain({ chain_duration => years(5) });

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(500));

      my $summ = $self->b5_summary($ledger);

      is($summ->consumers, 7, "there are seven consumers");

      is($summ->paid_consumers, 6, "six are paid");
      is($summ->free_consumers, 1, "one is free");
      is_deeply([$summ->free_indexes], [6], "...and the free one is last");
    },
  );
};

test 'signup for one, buy six, get one free' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      b5 => {
        xid      => $self->xid,
        template => 'b5g1_paid',
      },
    },
    sub {
      my ($ledger) = @_;

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(100));

      $ledger->active_consumer_for_xid($self->xid)
             ->adjust_replacement_chain({ chain_duration => years(6) });

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(600));

      my $summary = $self->b5_summary($ledger);
      is($summary->consumers, 8, "there are eight consumers");

      is($summary->paid_consumers, 7, "seven are paid");
      is($summary->free_consumers, 1, "one is free");
      is_deeply([$summary->free_indexes], [6], "...and the free one is 7th");
    },
  );
};

test 'signup for one, buy eleven, get two free' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      b5 => {
        xid      => $self->xid,
        template => 'b5g1_paid',
      },
    },
    sub {
      my ($ledger) = @_;

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(100));

      $ledger->active_consumer_for_xid($self->xid)
             ->adjust_replacement_chain({ chain_duration => years(11) });

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(1100));

      my $summary = $self->b5_summary($ledger);
      is($summary->consumers, 14, "there are fourteen consumers");

      is($summary->paid_consumers, 12, "twelve are paid");
      is($summary->free_consumers, 2, "two are free");
      is_deeply(
        [$summary->free_indexes],
        [6, 12],
        "...and the free ones are 7th and 13th"
      );
    },
  );
};

test 'signup for eleven, get two free' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      b5 => {
        xid      => $self->xid,
        template => 'b5g1_paid',
        minimum_chain_duration => years(11),
      },
    },
    sub {
      my ($ledger) = @_;

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(1100));

      my $summary = $self->b5_summary($ledger);
      is($summary->consumers, 13, "there are fourteen consumers");

      is($summary->paid_consumers, 11, "twelve are paid");
      is($summary->free_consumers, 2, "two are free");
      is_deeply(
        [$summary->free_indexes],
        [5, 11],
        "...and the free ones are 6th and 12th"
      );
    },
  );
};

test 'signup for one, quote five more, have one' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      b5 => {
        xid      => $self->xid,
        template => 'b5g1_paid',
      },
    },
    sub {
      my ($ledger) = @_;

      $ledger->heartbeat;
      $self->pay_unpaid_invoices($ledger, dollars(100));

      my $quote = $ledger->quote_for_extended_service($self->xid, years(5));

      is(
        $ledger->active_consumer_for_xid($self->xid)->guid,
        $quote->attachment_point_guid,
        "quote attaches where we expected",
      );

      my $head  = $quote->first_consumer;
      my @chain = $head->replacement_chain;

      my $summ = B5G1::Summary->new([ $head, @chain ]);

      is($summ->consumers, 6, "there are six consumers");

      is($summ->paid_consumers, 5, "five are paid");
      is($summ->free_consumers, 1, "one is free");
      is_deeply([$summ->free_indexes], [5], "...and the free one is last");
    },
  );
};

test 'already invoiced for 1, get quote for 4, get one free' => sub {
  my ($self) = @_;
  do_with_fresh_ledger(
    {
      b5 => {
        xid      => $self->xid,
        template => 'b5g1_paid',
      },
    },
    sub {
      my ($ledger) = @_;

      $ledger->heartbeat;

      is($ledger->amount_due, dollars(100), 'we owe $100 already');

      my $quote = $ledger->quote_for_extended_service($self->xid, years(4));

      is(
        $ledger->active_consumer_for_xid($self->xid)->guid,
        $quote->attachment_point_guid,
        "quote attaches where we expected",
      );

      my $head  = $quote->first_consumer;
      my @chain = $head->replacement_chain;

      my $summ = B5G1::Summary->new([ $head, @chain ]);

      is($summ->consumers, 5, "there are five consumers on the quote");

      is($summ->paid_consumers, 4, "four are paid");
      is($summ->free_consumers, 1, "one is free");
      is_deeply([$summ->free_indexes], [4], "...and the free one is last");
    },
  );
};

run_me;
done_testing;
