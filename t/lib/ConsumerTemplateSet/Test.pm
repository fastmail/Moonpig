package t::lib::ConsumerTemplateSet::Test;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(days dollars);
use Moonpig::URI;

use namespace::autoclean;

sub templates {
  return {
    boring => {
      roles => [ 'Consumer::ByTime' ],
      arg   => {
        old_age     => days(30),
        cost_amount => dollars(100),
        cost_period => days(365),
        charge_description => 'boring test charge',
        charge_path_prefix => 'a.b.c',

        replacement_mri    => Moonpig::URI->nothing,
      },
    },
  };
}

1;
