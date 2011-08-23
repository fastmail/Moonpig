package t::lib::ConsumerTemplateSet::Test;
use Moose;
with 'Moonpig::Role::ConsumerTemplateSet';

use Moonpig::Util qw(days dollars);

use Data::GUID qw(guid_string);

use namespace::autoclean;

sub templates {
  return {


    # Used entirely to test that the template system works at all.  It's a bare
    # set of things needed to create a consumer.
    boring => sub {
      my ($name) = @_;

      return {
        roles => [ 'Consumer::ByTime::FixedCost' ],
        arg   => {
          xid         => 'urn:uuid:' . guid_string,
          old_age     => days(30),
          cost_amount => dollars(100),
          cost_period => days(365),
          charge_description => 'boring test charge',
          extra_journal_charge_tags  => [ 'a.b.c' ],

          # build the uri based on the $name -- rjbs, 2011-02-09
          replacement_XXX    => [ get => 'template-like-this' ],
        },
      }
    },
  };
}

1;
