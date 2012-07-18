use strict;
use warnings;
package Moonpig::Behavior::Packable;
# ABSTRACT: MooseX::ComposedBehavior for STICK_PACK methods

use Moonpig::X;

use MooseX::ComposedBehavior -compose => {
  method_name  => 'STICK_PACK',
  sugar_name   => 'PARTIAL_PACK',
  context      => 'scalar',
  compositor   => sub {
    my ($self, $results) = @_;
    my %composed;

    for my $result (@$results) {
      for my $key (keys %$result) {
        if (exists $composed{ $key }) {
          Moonpig::X->throw({
            ident => "multiple contributors to one STICK_PACK entry",
            payload => { key => $key },
          });
        }

        $composed{ $key } = $result->{ $key };
      }
    }

    return \%composed;
  },
};

1;
