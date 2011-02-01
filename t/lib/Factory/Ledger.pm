package t::lib::Factory::Ledger;
use Moose::Role;

use Data::GUID qw(guid_string);

use Moonpig::Env::Test;
use Moonpig::URI;
use Moonpig::Util -all;

use namespace::autoclean;

sub test_ledger {
  my ($self, $class) = @_;
  $class ||= class('Ledger');

  my $contact = class('Contact')->new({
    name => 'J. Fred Bloggs',
    email_addresses => [ 'jfred@example.com' ],
  });

  my $ledger = $class->new({
    contact => $contact,
  });

  return $ledger;
}

sub add_bank_to {
  my ($self, $ledger, $args) = @_;

  my $bank = $ledger->add_bank(
    class(qw(Bank)),
    {
      amount => $args->{amount} || dollars(100),
    }
  );

  return $bank;
}

sub add_consumer_to {
  my ($self, $ledger, $args) = @_;

  my $consumer = $ledger->add_consumer(
    class(qw(Consumer::Dummy)),
    {
      xid             => 'urn:uuid:' . guid_string,
      make_active     => 1,
      replacement_mri => Moonpig::URI->nothing(),
      charge_path_prefix => [ "dummy-consumer" ],
      old_age => 30,
    },
  );

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
