package t::lib::Factory::Ledger;
use Moose::Role;

use Data::GUID qw(guid_string);

use Moonpig::Env::Test;
use Moonpig::URI;
use Moonpig::Util -all;

use namespace::autoclean;

sub test_ledger {
  my ($self, $class, $args) = @_;
  $class ||= class('Ledger');
  $args ||= {};

  my $contact = class('Contact')->new({
    name => 'J. Fred Bloggs',
    email_addresses => [ 'jfred@example.com' ],
  });

  my $ledger = $class->new({
    contact => $contact,
    %$args,
  });

  return $ledger;
}

sub rnd {
  my (@items) = @_;
  return $items[int(rand(1000)) % @items];
}

sub random_contact {
  my ($self) = @_;
  my @first = qw(John Mary William Anna James Margaret George Helen Charles Elizabeth);
  my @last = qw(Smith Johnson Williams Jones Brown Davis Miller Wilson Moore Taylor);
  my @names = (rnd(@first), rnd('A' .. 'Z') . ".", rnd(@last));
  my $inits = join "", map substr($_, 0, 1), @names;
  return class('Contact')->new({
    name => join(" ", @names),
    email_addresses => [ "\L$inits\@example.com" ],
  });
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
  my $class = delete $args->{class} || class("Consumer::Dummy");

  my $consumer = $ledger->add_consumer(
    $class,
    {
      xid             => 'urn:uuid:' . guid_string,
      make_active     => 1,
      replacement_mri => Moonpig::URI->nothing(),
      %$args,
    },
  );

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
