package Moonpig::Ledger::PostTarget;
use Moose;

with(
  'Stick::Role::PublicResource',
);

use Moonpig::Util qw(class);

use namespace::autoclean;

sub resource_post {
  my ($self, $arg) = @_;

  my $class ||= class('Ledger');

  my $contact = class('Contact')->new({
    name            => $arg->{name},
    email_addresses => $arg->{email_addresses},
  });

  my $ledger = $class->new({
    contact => $contact,
  });

  return $ledger;
}

1;
