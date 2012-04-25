
use strict;
use Data::GUID qw(guid_string);
use Moonpig::Util qw(class dollars years);
use Test::Deep qw(cmp_deeply bag);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(build);

my @basic = qw(
  replacement_plan xid
  extra_charge_tags
);
my @makes_replacement = qw(replacement_lead_time);

test dummy => sub {
  my ($self) = @_;
  my $stuff = build(consumer => { template => "dummy" });
  {
    my $h = $stuff->{consumer}->copy_attr_hash__();
    cmp_deeply([keys %$h], bag(@basic));
  }

  {
    $stuff->{consumer}->expire;
    my $h = $stuff->{consumer}->copy_attr_hash__();
    cmp_deeply([keys %$h], bag(qw(canceled_at expired_at), @basic));
  }
};

test by_time => sub {
  my ($self) = @_;

  for my $make_active (0, 1) {
    my $test_name = $make_active ? "active consumer" : "inactive consumer";

    my $stuff = build(
      consumer =>
        { class => class("Consumer::ByTime::FixedAmountCharge"),
          xid             => 'urn:uuid:' . guid_string,
          replacement_plan => [ get => '/nothing' ],
          charge_description => "dummy",
          charge_amount => dollars(1),
          cost_period => years(1),
          replacement_lead_time => years(1),
          make_active => $make_active,
        });

    my $h = $stuff->{consumer}->copy_attr_hash__();
    cmp_deeply([keys %$h],
               bag(grep { 'last_charge_date' ne $_ } @basic, @makes_replacement,
                   qw(charge_description charge_frequency
                      charge_amount cost_period grace_period_duration
                      proration_period
                    ),
                   $make_active ? qw(grace_until last_charge_date)
                     : (),
                  ),
               $test_name,
              );
  }
};

test byusage => sub {
  my ($self) = @_;
  my $stuff = build(
    consumer => {
      class            => class("Consumer::ByUsage"),
      xid              => 'urn:uuid:' . guid_string,
      replacement_plan => [ get => '/nothing' ],
      charge_amount_per_unit    => dollars(2),
      low_water_mark   => 3,
      replacement_lead_time          => years(1),
    }
  );
  my $h = $stuff->{consumer}->copy_attr_hash__();
  cmp_deeply([keys %$h], bag(@basic, @makes_replacement,
                             qw(charge_amount_per_unit low_water_mark)));
};

run_me;
done_testing;
