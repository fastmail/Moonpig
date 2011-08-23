package Fauxbox::Moonpig::TemplateSet;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(days dollars);

use namespace::autoclean;

sub templates {
  return {
    username => sub {
      my ($name) = @_;

      return {
        arg   => {
          make_active     => 1,
          replacement_XXX => [ get => "/consumer-template/$name" ],
        },
      }
    },

    fauxboxbasic => sub {
      my ($name) = @_;

      return {
        roles => [
          qw(Consumer::ByTime =Fauxbox::Moonpig::Consumer::BasicAccount)
        ],
        arg   => {
          cost_period     => days(365),
          old_age         => days(30),
          extra_journal_charge_tags     => [ 'fauxbox.basic' ],
          replacement_XXX => [ get => "/consumer-template/$name" ],
        },
      }
    },

    fauxboxtest => sub {
      my ($name) = @_;

      return {
        roles => [
          qw(Consumer::ByTime Consumer::ByTime::FixedCost)
        ],
        arg   => {
          cost_amount => dollars(20),
          cost_period => days(5),
          old_age     => days(2),
          extra_journal_charge_tags => [ 'fauxbox.speedy' ],
          charge_frequency => days(1),
          grace_period_duration => days(1),
          replacement_XXX => [ get => "/consumer-template/$name" ],
          charge_description => "test charge",
        },
      }
    },
  };
}

1;
