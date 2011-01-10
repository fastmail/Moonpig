use strict;
use warnings;
package Moonpig::Behavior::EventHandlers;
# ABSTRACT: MooseX::ComposedBehavior for implicit_event_handlers

use Moonpig::X;

use MooseX::ComposedBehavior -compose => {
  method_name  => 'composed_implicit_event_handlers',
  sugar_name   => 'implicit_event_handlers',
  context      => 'scalar',
  compositor   => sub {
    my ($self, $results) = @_;
    my %composed;

    # Each result is a HOH; first keys, event names; second keys, handler names
    for my $result (@$results) {
      for my $event_name (keys %$result) {
        my $this_event = ($composed{ $event_name } ||= {});

        for my $handler_name (keys %{ $result->{$event_name} }) {
          if (exists $this_event->{$handler_name}) {
            Moonpig::X->throw({
              ident   => "implicit handler composition conflict",
              payload => {
                handler_name => $handler_name,
                event_name   => $event_name,
              },
            });
          }

          $this_event->{$handler_name} = $result->{$event_name}{$handler_name};
        }
      }
    }

    return \%composed;
  },
};

1;
