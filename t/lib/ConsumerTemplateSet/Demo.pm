package t::lib::ConsumerTemplateSet::Demo;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(days dollars);

use namespace::autoclean;

sub templates {
  return {
    'demo-service' => sub {
      my ($name) = @_;

      return {
        roles => [ '=t::lib::Role::Consumer::ByTime::NFixedCosts' ],
        arg   => {
          cost_amounts       => [ dollars(40), dollars(10) ],
          cost_period        => days(365),
          charge_frequency   => days(7), # less frequent to make logs simpler
          charge_description => 'yoyodyne service',
          replacement_lead_time            => days(30),
          extra_journal_charge_tags  => [ 'yoyodyne.basic' ],
          grace_until        => Moonpig->env->now + days(3),

          replacement_plan   => [ get => '/consumer-template/demo-service' ],
        },
      };
    }
  }
}

1;
