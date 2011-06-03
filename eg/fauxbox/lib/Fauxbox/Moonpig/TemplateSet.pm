package Fauxbox::Moonpig::TemplateSet;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(days dollars);
use Moonpig::URI;

use namespace::autoclean;

sub templates {
  return {
    username => sub {
      my ($name) = @_;

      return {
        arg   => {
          make_active     => 1,
          replacement_mri => "moonpig://consumer-template/$name",
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
          cost_period        => days(365),
          old_age            => days(30),
          charge_path_prefix => 'fauxbox.basic',
          replacement_mri    => "moonpig://consumer-template/$name",
        },
      }
    },

    fauxboxtrivial => sub {
      my ($name) = @_;

      return {
        roles => [
          qw(Consumer::ByTime Consumer::ByTime::FixedCost)
        ],
        arg   => {
          cost_period        => days(365),
          old_age            => days(30),
          charge_path_prefix => 'fauxbox.basic',
          replacement_mri    => "moonpig://consumer-template/$name",
          charge_description => "test charge",
        },
      }
    },
  };
}

1;
