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
        roles => [ '=t::lib::Role::Consumer::ByTime::NFixedCosts' ],
        arg   => {
          cost_amounts       => [ dollars(40), dollars(10) ],
          cost_period        => days(365),
          charge_frequency   => days(7), # less frequent to make logs simpler
          charge_description => 'yoyodyne service',
          old_age            => days(30),
          extra_journal_charge_tags  => [ 'yoyodyne.basic' ],
          grace_until        => Moonpig->env->now + days(3),

          # XXX: I have NFI what to do here, yet. -- rjbs, 2011-01-12
          replacement_XXX    => [ get => 'template-like-this' ],
        },
      };
    }
  }
}

1;
