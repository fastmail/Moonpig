package Fauxbox::Moonpig::Consumer::BasicAccount;
use Moose::Role;
with(
  'Fauxbox::Moonpig::Consumer::HasAccount',
);

use Moonpig::Util qw(dollars);

use namespace::autoclean;

sub charge_pairs_on {
  my ($self, $date) = @_;

  my $account = $self->account;

  my @charge_pairs = ('Fauxbox Basic Account' => dollars(20));
  push @charge_pairs, ('Premium Services' => dollars(30))
    if $account->was_premium_at($date);

  return @charge_pairs;
}

1;
