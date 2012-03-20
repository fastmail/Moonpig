package Moonpig::Test::Factory::Templates;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig;
use Moonpig::Util qw(class days dollars years);

use Data::GUID qw(guid_string);

use namespace::autoclean;

sub templates {
  my $dummy_xid = "consumer:test:dummy";
  my $b5g1_xid = "consumer:5y:test";

  return {
    dummy => sub {
      my ($name) = @_;
      return {
        roles => [ 'Consumer::Dummy' ],
        arg => {
          replacement_plan => [ get => '/nothing' ],
          xid              => $dummy_xid,
         },
       }
    },
    quick => sub {
      my ($name) = @_;
      return {
        roles => [ 'Consumer::ByTime::FixedAmountCharge' ],
        arg => {
          replacement_lead_time     => years(1000),
          charge_amount => dollars(100),
          cost_period => days(2),
          charge_description => 'quick consumer',
          replacement_plan   => [ get => '/consumer-template/quick' ],
        }};
    },

    b5g1_paid => sub {
      my ($name) = @_;

      return {
        roles => [
          'Consumer::ByTime::FixedAmountCharge',
          't::Consumer::FreeEveryFive',
        ],
        arg   => {
          xid           => $b5g1_xid,
          charge_amount => dollars(100),
          cost_period   => years(1),
          charge_description => 'b5g1 (paid)',
          replacement_plan   => [ get => "/consumer-template/b5g1_paid" ],
        },
      }
    },
    b5g1_free => sub {
      my ($name) = @_;

      return {
        roles => [
          'Consumer::ByTime::FixedAmountCharge',
          'Consumer::SelfFunding',
        ],
        arg   => {
          xid         => $b5g1_xid,
          charge_amount => dollars(100),
          cost_period   => years(1),
          charge_description => 'b5g1 (free)',
          replacement_plan   => [ get => "/consumer-template/b5g1_paid" ],
        },
      },
    },
  };
}

1;
