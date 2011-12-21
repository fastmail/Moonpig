package t::lib::ConsumerTemplateSet::Test;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(days dollars);

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
          extra_journal_charge_tags  => [ 'a.b.c' ],

          replacement_plan   => [ get => '/consumer-template/boring' ],
        },
      }
    },
  };
}

1;
