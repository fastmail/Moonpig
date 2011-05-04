package Moonpig::Role::Collection::ConsumerExtras;
use Moose::Role;
use MooseX::Types::Moose qw(Str HashRef);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

publish add_from_template => { -http_method => 'post',
                               -path => 'add_from_template',
                               template => Str,
                               template_args => HashRef,
                             } => sub {
  my ($self, $arg) = @_;
  my $new_consumer =
    $self->ledger->add_consumer_from_template(
      $arg->{template},
      $arg->{template_args},
   );
  return $new_consumer;
};

1;

