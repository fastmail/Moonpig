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
        roles => [ 'Consumer::ByTime' ],
        arg   => {
          cost_amount        => dollars(20),
          cost_period        => days(365),
          old_age            => days(30),
          make_active        => 1,
          charge_description => 'Fauxbox Basic Service',
          charge_path_prefix => 'fauxbox.basic',
          replacement_mri    => "moonpig://consumer-template/$name",
        },
      }
    },
  };
}

1;
