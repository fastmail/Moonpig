use strict;
use warnings;

use Carp qw(confess croak);
use Moonpig::DateTime;
use Moonpig::Util -all;
use Test::Routine;
use Test::More;
use Test::Routine::Util;

use t::lib::Factory qw(build);
use t::lib::Logger;

my ($Ledger, $Consumer);
has hold => (
  is   => 'rw',
  isa => 'Moonpig::Ledger::Accountant::Transfer',
  clearer => 'discard_hold',
);

before run_test => sub {
  my ($self) = @_;
  $self->discard_ledger();
  $self->discard_hold();
  Moonpig->env->email_sender->clear_deliveries;
  $self->create_consumer();
};

sub discard_ledger {
  undef $Ledger;
  undef $Consumer;
}

sub create_consumer {
  my ($self, $args) = @_;
  $args ||= {};

  my $stuff = build(
    consumer => { class => 'ByUsage',
                  bank => dollars(1),
                  cost_per_unit => cents(5),
                  old_age => days(30),
                  replacement_mri => Moonpig::URI->nothing(),
                  make_active => 1,
                  %$args,
                },
  );

  $Consumer = $stuff->{consumer};
  $Ledger   = $stuff->{ledger};

  ok($Consumer, "set up consumer");
  ok($Consumer->does('Moonpig::Role::Consumer::ByUsage'),
     "consumer is correct type");
  is($Consumer->unapplied_amount, dollars(1), "its bank contains \$1");
}

test "consumer creation" => sub {
  my ($self) = @_;
  $self->create_consumer;
};

sub successful_hold {
  my ($self, $n_units) = @_;
  $n_units ||= 7;
  $self->create_consumer;
  is($Consumer->units_remaining, 20, "initially funds for 20 units");
  my $h = $Consumer->create_hold_for_units($n_units);
  my $amt = $n_units * cents(5);
  ok($h, "made hold");
  $self->hold($h);
  is($h->target, $Consumer, "hold has correct consumer");
  is($h->source, $Consumer->bank, "hold has correct bank");
  is($h->amount, $amt, "hold is for $amt mc");
  my $x_remaining = 20 - $n_units;
  is($Consumer->units_remaining, $x_remaining,
     "after holding $n_units, there are $x_remaining left");
}

test "successful hold" => sub {
  my ($self) = @_;

  $self->successful_hold;
};

test release_hold => sub {
  my ($self) = @_;
  $self->successful_hold;
  is($Consumer->units_remaining, 13, "still 13 left in bank");
  $self->hold->delete;
  is($Consumer->units_remaining, 20, "20 left after releasing hold");
};

test commit_hold => sub {
  my ($self) = @_;
  my @journals;
  $self->successful_hold;
  @journals = $Ledger->journals;
  is(@journals, 0, "no journal yet");
  note("creating charge for hold");
  $Consumer->create_charge_for_hold($self->hold, "test charge");
  is($Consumer->units_remaining, 13, "still 13 left in bank");
  @journals = $Ledger->journals;
  is(@journals, 1, "now one journal");
  is($journals[0]->total_amount, cents(35),
     "total charges now \$.35");
};

test failed_hold => sub {
  my ($self) = @_;
  $self->successful_hold;
  is($Consumer->units_remaining, 13, "still 13 left in bank");
  my $hold = $Consumer->create_hold_for_units(14);
  is(undef(), $hold, "cannot create hold for 14 units");
  is($Consumer->units_remaining, 13, "still 13 left in bank");
};

test low_water_replacement => sub {
  my ($self) = @_;
  my $MRI =
    Moonpig::URI->new("moonpig://method?method=template_like_this");
  my $lwm = 7;
  $self->create_consumer({
    low_water_mark => $lwm,
    replacement_mri => $MRI,
    old_age => 0,
  });
  my $q = 2;
  my $held = 0;
  until ($Consumer->has_replacement) {
    $Consumer->create_hold_for_units($q) or last;
    $held += $q;
  }
  ok($Consumer->has_replacement, "replacement consumer created");
  cmp_ok($Consumer->units_remaining, '<=', $lwm,
         "replacement created at or below LW mark");
  cmp_ok($Consumer->units_remaining + $q, '>', $lwm,
         "replacement created just below LW mark");

  # Make sure hold creation works even after the replacement exists
  # (This caused a failure until commit 918a10cce.)
  $Consumer->create_hold_for_units(1);
};

sub jan {
  my ($day) = @_;
  my $month = 1;
  ($day, $month) = ($day-31, 2) if $day > 31;
  Moonpig::DateTime->new( year => 2000, month => $month, day => $day );
}

test est_lifetime => sub {
  my ($self) = @_;
  Moonpig->env->stop_clock_at(jan(1));

  $self->create_consumer();
  is($Consumer->units_remaining, 20, "initially 20 units");
  is($Consumer->unapplied_amount, dollars(1), "initially \$1.00");
  is($Consumer->estimated_lifetime, days(365),
     "inestimable lifetime -> 365d");

  Moonpig->env->stop_clock_at(jan(15));
  $Consumer->create_hold_for_units(1);
  is($Consumer->units_remaining, 19, "now 19 units");
  is($Consumer->unapplied_amount, dollars(0.95), "now \$0.95");
  Moonpig->env->stop_clock_at(jan(30));
  is($Consumer->estimated_lifetime, days(30 * 19),
     "1 charge/30d -> lifetime 600d");

  Moonpig->env->stop_clock_at(jan(24));
  $Consumer->create_hold_for_units(2);
  is($Consumer->units_remaining, 17, "now 17 units");
  is($Consumer->unapplied_amount, dollars(0.85), "now \$0.85");
  Moonpig->env->stop_clock_at(jan(30));
  is($Consumer->estimated_lifetime, days(30 * 17/3),
     "3 charges/30d -> lifetime 200d");

  Moonpig->env->stop_clock_at(jan(50));
  is($Consumer->estimated_lifetime, days(30 * 17/2),
     "old charges don't count");

  Moonpig->env->stop_clock_at(jan(58));
  is($Consumer->estimated_lifetime, days(365),
     "no recent charges -> guess 365d");
};

test "test lifetime replacement" => sub {
  my ($self) = @_;
  my $MRI =
    Moonpig::URI->new("moonpig://method?method=template_like_this");
  my $old_age = days(10);

  for my $q (1 .. 3) { # number of units to reserve each time
    for my $t (1 .. 3) { # number of days between holds
      my ($prev_est_life, $cur_est_life);
      my $day = 0;

      note "Testing with q=$q, t=$t\n";
      $self->discard_ledger;
      $self->create_consumer({
        low_water_mark => 0,
        replacement_mri => $MRI,
        old_age => $old_age,
      });

      until ($Consumer->has_replacement) {
        $day += $t;
        Moonpig->env->stop_clock_at(jan($day));
        $prev_est_life = $Consumer->estimated_lifetime;
        $Consumer->create_hold_for_units($q) or last;
        $cur_est_life = $Consumer->estimated_lifetime;
      }
      ok($Consumer->has_replacement, "replacement consumer created");
      cmp_ok($cur_est_life, '<=', $old_age,
             "replacement created not created too soon");
      cmp_ok($prev_est_life, '>', $old_age,
             "replacement created as soon as appropriate");
      note "This test finished on Jan $day.\n";
    }
  }
};

test default_low_water_check => sub {
  my ($self) = @_;
  my $MRI =
    Moonpig::URI->new("moonpig://method?method=template_like_this");
  $self->create_consumer({
    replacement_mri => $MRI,
    old_age => 0,
  });
  my $q = 0;
  my $held = 0;
  until ($Consumer->has_replacement) {
    $q++;
    $Consumer->create_hold_for_units($q) or last;
    $held += $q;
  }
  ok($Consumer->has_replacement, "replacement consumer created");
  # If no low-water mark specified, create replacement when next request of
  # same size would cause exhaustion
  cmp_ok($Consumer->units_remaining, '<=', $q,
         "replacement created at or below LW mark");
  cmp_ok($Consumer->units_remaining, '>', 0,
         "replacement created before exhaustion");
};

# Postpone testing this until we figure out whether these consumers
# will actually expire.
test expiration => sub {
  ok(1);
};

# Postpone testing this until we figure out whether these consumers
# will actually have replacements.
test subsidiary_hold => sub {
  ok(1);
};

run_me;
done_testing;
