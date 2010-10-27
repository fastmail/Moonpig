package t::lib::Factory::Ledger;
use Moose::Role;

use Moonpig::Ledger::Basic;
use Moonpig::Contact::Basic;
use Moonpig::Bank::Basic;
use Moonpig::Consumer::Basic;

use Moonpig::Util -all;

sub test_ledger {
  my $contact = Moonpig::Contact::Basic->new({
    name => 'J. Fred Bloggs',
    email_addresses => [ 'jfred@example.com' ],
  });

  my $ledger = Moonpig::Ledger::Basic->new({
    contact => $contact,
  });

  return $ledger;
}

sub add_bank_and_consumer_to {
  my ($self, $ledger, $args) = @_;

  my $bank = Moonpig::Bank::Basic->new({
    amount => $args->{amount} || dollars(100),
    ledger => $ledger,
  });

  my $consumer = Moonpig::Consumer::Basic->new({
    ledger => $ledger,
  });

  $ledger->add_bank($bank);
  $ledger->add_consumer($consumer);

  $consumer->_set_bank($bank);

  return ($bank, $consumer);
}

1;
