package t::lib::ConsumerTemplateSet::Demo;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(days dollars);
use Moonpig::URI;

use namespace::autoclean;

sub templates {
  return {
    'demo-service' => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByTime::FixedCost' ],
        arg   => {
          cost_amount        => dollars(50),
          cost_period        => days(365),
          charge_frequency   => days(7), # less frequent to make logs simpler
          charge_description => 'yoyodyne service',
          old_age            => days(30),
          charge_tags        => [ 'yoyodyne.basic' ],
          grace_until        => Moonpig->env->now + days(3),

          # XXX: I have NFI what to do here, yet. -- rjbs, 2011-01-12
          replacement_mri    => Moonpig::URI->new(
            "moonpig://consumer-template/$name",
          ),
        },
      };
    }
  }
}

1;
