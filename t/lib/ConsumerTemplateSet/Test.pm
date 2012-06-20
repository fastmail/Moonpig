package t::lib::ConsumerTemplateSet::Test;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(cents days dollars);

use Data::GUID qw(guid_string);

use namespace::autoclean;

sub templates {
  return {


    # Used entirely to test that the template system works at all.  It's a bare
    # set of things needed to create a consumer.
    boring => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByTime::FixedAmountCharge' ],
        arg   => {
          xid         => 'urn:uuid:' . guid_string,
          replacement_lead_time     => days(30),
          charge_amount => dollars(100),
          cost_period => days(365),
          charge_description => 'boring test charge',
          extra_charge_tags  => [ 'a.b.c' ],

          replacement_plan   => [ get => '/consumer-template/boring' ],
        },
      }
    },

    boring2 => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByTime::FixedAmountCharge' ],
        arg   => {
          charge_description    => "test charge",
          replacement_lead_time => days(20),
          replacement_plan      => [ get => '/consumer-template/boring2' ],
          charge_amount         => dollars(1),
          cost_period      => days(1),
        },
      }
    },

    byu_test => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByUsage' ],
        arg   => {
          charge_amount_per_unit    => cents(5),
          replacement_lead_time          => days(30),
          replacement_plan => [ get => '/consumer-template/byu_test' ],
          replacement_lead_time => days(20),
          replacement_plan      => [ get => '/consumer-template/boring2' ],
        },
      }
    },

    psync => sub {
      my ($name) = @_;
      return {
        roles => [ 't::Consumer::VaryingCharge' ],
        arg => {
          total_charge_amount => dollars(14),
          cost_period => days(14),
          replacement_plan => [ get => '/consumer-template/psync' ],
        },
      },
    },


  };
}

1;
