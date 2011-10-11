
use strict;
use Data::GUID qw(guid_string);
use Moonpig::Util qw(class dollars years);
use Test::Deep qw(cmp_deeply bag);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use Moonpig::Test::Factory qw(build);

use Moonpig::Context::Test -all, '$Context';

my @basic = qw(canceled expired replacement_plan xid);
my @charges_bank = qw(extra_journal_charge_tags old_age);
my @invoices = qw(extra_invoice_charge_tags);

test dummy => sub {
  my ($self) = @_;
  my $stuff = build(consumer => { template => "dummy" });
  my $h = $stuff->{consumer}->copy_attr_hash__();
  cmp_deeply([keys %$h], bag(@basic));
};

test by_time => sub {
  my ($self) = @_;

  for my $make_active (0, 1) {
    my $test_name = $make_active ? "active consumer" : "inactive consumer";

    my $stuff = build(
      consumer =>
        { class => class("Consumer::ByTime::FixedCost"),
          xid             => 'urn:uuid:' . guid_string,
          replacement_plan => [ get => '/nothing' ],
          charge_description => "dummy",
          cost_amount => dollars(1),
          cost_period => years(1),
          old_age => years(1),
          make_active => $make_active,
        });

    my $h = $stuff->{consumer}->copy_attr_hash__();
    cmp_deeply([keys %$h],
               bag(@basic, @charges_bank, @invoices,
                   qw(charge_description charge_frequency
                      cost_amount cost_period grace_period_duration
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
      cost_per_unit    => dollars(2),
      low_water_mark   => 3,
      old_age          => years(1),
    }
  );
  my $h = $stuff->{consumer}->copy_attr_hash__();
  cmp_deeply([keys %$h], bag(@basic, @charges_bank,
                             qw(cost_per_unit low_water_mark)));
};

run_me;
done_testing;
