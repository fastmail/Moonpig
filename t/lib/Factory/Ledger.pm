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

sub add_bank_to {
  my ($self, $ledger, $args) = @_;

  my $bank = Moonpig::Bank::Basic->new({
    amount => $args->{amount} || dollars(100),
    ledger => $ledger,
  });

  $ledger->add_bank($bank);
  return $bank;
}

sub add_consumer_to {
  my ($self, $ledger, $args) = @_;

  my $consumer = Moonpig::Consumer::Basic->new({
    ledger => $ledger,
  });

  $ledger->add_consumer($consumer);
  $consumer->_set_bank($args->{bank})
    if $args->{bank};

  return $consumer;
}

sub add_bank_and_consumer_to {
  my ($self, $ledger, $args) = @_;
  $args ||= {};

  my $bank = $self->add_bank_to($ledger, $args);
  my $consumer = $self->add_consumer_to($ledger, {%$args, bank => $bank});

  return ($bank, $consumer);
}

1;
