package Fauxbox::Moonpig::Consumer::BasicAccount;
use Moose::Role;
with(
  'Fauxbox::Moonpig::Consumer::HasAccount',
);

use Moonpig::Util qw(dollars);

use namespace::autoclean;

sub cost_amount_on {
  my ($self, $date) = @_;

  my $account = $self->account;

  return dollars(50) if $account->was_premium_at($date);
  return dollars(20);
}

1;
