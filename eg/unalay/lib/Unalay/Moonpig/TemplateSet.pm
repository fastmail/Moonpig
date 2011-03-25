package Unalay::Moonpig::TemplateSet;
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
          make_active => 1,

          old_age     => days(30),
          charge_path_prefix => 'SHOULD.NOT.BE.HERE',

          # build the uri based on the $name -- rjbs, 2011-02-09
          replacement_mri    => "moonpig://consumer-template/$name",
        },
      }
    },
  };
}

1;
