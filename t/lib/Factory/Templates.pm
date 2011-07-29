package t::lib::Factory::Templates;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(days dollars);
use Moonpig::URI;

use Data::GUID qw(guid_string);

use namespace::autoclean;

sub templates {
  return {
    fiveyear => sub {
      my ($name) = @_;
      my $xid = "consumer:5y:$name";

      return {
        roles => [ 'Consumer::ByTime::FixedCost' ],
        arg   => {
          xid         => $xid,
          old_age     => days(30),
          cost_amount => dollars(500),
          cost_period => days(365 * 5 + 1),
          charge_description => 'long-term consumer',
          replacement_mri    => "moonpig://consumer-template/$name",
        },
      }
    },
    free_sixthyear => sub {
      my ($name) = @_;
      my $xid = "consumer:5y:$name";

      return {
        roles => [ 'Consumer::ByTime::FixedCost' ],
        arg   => {
          xid         => $xid,
          old_age     => days(30),
          cost_amount => dollars(100),
          cost_period => days(365),
          charge_description => 'free sixth-year consumer',
          extra_invoice_charge_tags  => [ "coupon.b5g1" ],
          replacement_mri    => "moonpig://consumer-template/$name",
        },
      }
    },
  };
}

1;
