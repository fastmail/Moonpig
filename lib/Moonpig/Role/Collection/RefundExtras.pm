package Moonpig::Role::Collection::RefundExtras;
use Class::MOP;
use Moose::Role;
use MooseX::Types::Moose qw(Int Str HashRef);
use Moonpig::Util qw(cents class);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

publish add => { -http_method => 'post',
                 attributes => HashRef,
               } => sub {
  my ($self, $arg) = @_;

  return Moonpig->env->storage->do_rw(sub {
    my $refund = $self->owner->add_refund(
      class("Refund"),
      $arg->{attributes},
     );
    return $refund;
  });
};

1;

