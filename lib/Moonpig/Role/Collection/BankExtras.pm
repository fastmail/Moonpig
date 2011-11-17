package Moonpig::Role::Collection::BankExtras;
use Moose::Role;
use MooseX::Types::Moose qw(Str HashRef);
use Moonpig::Types qw(NonNegativeMillicents);
use Moonpig::Util qw(class);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

publish add => { -http_method => 'post',
                 -path => 'add',
                 amount => NonNegativeMillicents,
               } => sub {
  my ($self, $arg) = @_;
  my $bank = $self->owner->add_bank(class('Bank'), $arg);
  $self->owner->save;
  return $bank;
};

1;

