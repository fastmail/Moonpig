package t::lib::Factory::Templates;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig;
use Moonpig::Env::Test;
use Moonpig::Util qw(class days dollars years);
use Moonpig::URI;

use Data::GUID qw(guid_string);

use namespace::autoclean;

sub templates {
  my $b5g1_xid = "consumer:5y:test";
  return {
    dummy => sub {
      my ($name) = @_;
      return {
        roles => [ 'Consumer::Dummy' ],
        arg => {
          replacement_mri => Moonpig::URI->nothing(),
         },
       }
    },
    dummy_with_bank => sub {
      my ($name) = @_;
      return {
        roles => [ 'Consumer::DummyWithBank' ],
        arg => {
          replacement_mri => Moonpig::URI->nothing(),
          old_age => years(1000),
        },
      }
    },
    fiveyear => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByTime::FixedCost', 't::Consumer::CouponCreator' ],
        arg   => {
          xid         => $b5g1_xid,
          old_age     => days(30),
          cost_amount => dollars(500),
          cost_period => days(365 * 5 + 1),
          charge_description => 'long-term consumer',
          replacement_mri    => "moonpig://consumer-template/free_sixthyear",

          coupon_class => class(qw(Coupon::Simple Coupon::RequiredTags)),
          coupon_args => {
            discount_rate => 1.00,
            target_tags   => [ $b5g1_xid, "coupon.b5g1" ],
            description   => "Buy five, get one free",
          },
        },
      }
    },
    free_sixthyear => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByTime::FixedCost' ],
        arg   => {
          xid         => $b5g1_xid,
          old_age     => days(30),
          cost_amount => dollars(100),
          cost_period => days(365),
          charge_description => 'free sixth-year consumer',
          extra_invoice_charge_tags  => [ "coupon.b5g1" ],
          replacement_mri    => "moonpig://consumer-template/$name",
        },
      },
    },
  };
}

1;
