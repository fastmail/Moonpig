use strict;
use warnings;

use Test::More;

use Moonpig::Ledger::Basic;
use Moonpig::Contact::Basic;
use Moonpig::Bank::Basic;
use Moonpig::Consumer::Basic;

use Moonpig::Util -all;

my $contact = Moonpig::Contact::Basic->new({
  name => 'J. Fred Bloggs',
  email_addresses => [ 'jfred@example.com' ],
});

my $ledger = Moonpig::Ledger::Basic->new({
  contact => $contact,
});

my $bank = Moonpig::Bank::Basic->new({
  amount => dollars(100),
});

my $consumer = Moonpig::Consumer::Basic->new({
  amount => dollars(100),
});

$ledger->add_bank($bank);
$ledger->add_consumer($consumer);

$consumer->bank($bank);

pass('hey, we lived!');

done_testing;
