
use strict;
use Data::GUID qw(guid_string);
use Moonpig::Util qw(class dollars years);
use Test::Deep qw(cmp_deeply bag);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

with qw(t::lib::Factory::Ledger);

my @basic = qw(expired replacement_mri is_replaceable xid);
my @charges_bank = qw(extra_journal_charge_tags old_age);
my @invoices = qw(extra_invoice_charge_tags);

test dummy => sub {
  my ($self) = @_;
  my $ledger = $self->test_ledger();
  my $consumer = $self->add_consumer_to($ledger);
  my $h = $consumer->copy_attr_hash__();
  cmp_deeply([keys %$h], bag(@basic));
};

test by_time => sub {
  my ($self) = @_;
  my $ledger = $self->test_ledger();

  for my $make_active (0, 1) {
    my $test_name = $make_active ? "active consumer" : "inactive consumer";

    my $consumer = $ledger->add_consumer(
      class("Consumer::ByTime::FixedCost"),
      {
        xid             => 'urn:uuid:' . guid_string,
        replacement_mri => Moonpig::URI->nothing(),
        charge_description => "dummy",
        cost_amount => dollars(1),
        cost_period => years(1),
        old_age => years(1),
        make_active => $make_active,
      });

    my $h = $consumer->copy_attr_hash__();
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
  my $ledger = $self->test_ledger();
  my $consumer = $ledger->add_consumer(
    class("Consumer::ByUsage"),
    {
      xid             => 'urn:uuid:' . guid_string,
      replacement_mri => Moonpig::URI->nothing(),
      cost_per_unit   => dollars(2),
      low_water_mark  => 3,
      old_age => years(1),
    });
  my $h = $consumer->copy_attr_hash__();
  cmp_deeply([keys %$h], bag(@basic, @charges_bank,
                             qw(cost_per_unit low_water_mark)));
};

run_me;
done_testing;
