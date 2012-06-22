package Fauxbox::Moonpig::Consumer::BasicAccount;
use Moose::Role;
with(
  'Fauxbox::Moonpig::Consumer::HasAccount',
);

use Moonpig::Util qw(dollars);

use namespace::autoclean;

sub charge_structs_on {
  my ($self, $date) = @_;

  my $account = $self->account;

  my @charge_structs = ({
    description => 'Fauxbox Basic Account',
    amount      => dollars(20),
  });

  if ($account->was_premium_at($date)) {
    push @charge_structs, ({
      description => 'Premium Services',
      amount      => dollars(30),
    });
  }

  return @charge_structs;
}

1;
