package Moonpig::Role::Collection::CreditExtras;
use Class::MOP;
use Moose::Role;
use MooseX::Types::Moose qw(Int Str HashRef);
use Moonpig::Util qw(cents class);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

sub add {
  my ($self, $arg) = @_;
  my $type = $arg->{type};

  return Moonpig->env->storage->do_rw(sub {
    my $credit = $self->owner->add_credit(
      class("Credit::$type"),
      $arg->{attributes},
    );

    $self->owner->save;
    $self->owner->process_credits;
    $self->owner->save;
    return $credit;
  });
};

1;

