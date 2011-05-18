package Fauxbox::Moonpig::Consumer::BasicAccount;
use Moose::Role;
with(
  'Fauxbox::Moonpig::Consumer::HasAccount',
);

use Moonpig::Util qw(dollars);

use namespace::autoclean;

sub costs_on {
  my ($self, $date) = @_;

  my $account = $self->account;

  my @costs = ('Fauxbox Basic Account' => dollars(20));
  push @costs, ('Premium Services' => dollars(30))
    if $account->was_premium_at($date);

  return @costs;
}

1;
