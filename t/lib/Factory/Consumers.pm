package t::lib::Factory::Consumers;
use Moose::Role;

use Moonpig::Env::Test;
use Moonpig::URI;

use Data::GUID qw(guid_string);
use Moonpig::Util -all;
requires 'ledger';

my %reasonable_defaults = (
  'Moonpig::Class::Consumer::ByTime' => {
    charge_description => "test charge",
    charge_path_prefix => ["test"],
    description        => "test consumer",
    cost_amount        => dollars(1),
    cost_period        => days(1),
    old_age            => days(0),
    replacement_mri    => Moonpig::URI->nothing(),
    service_active     => 1,
  },
  'Moonpig::Class::Consumer::ByUsage' => {
    charge_path_prefix => ["test"],
    cost_per_unit      => cents(5),
    old_age            => days(30),
    replacement_mri    => Moonpig::URI->nothing(),
    service_active     => 1,
  },
);

sub test_consumer {
  my ($self, $class, $args) = @_;
  $args ||= {};
  $class ||= class(qw(Consumer::Dummy));
  unless ($class =~ /^Moonpig::/) {
    $class = "Consumer::$class" unless $class =~ /^Consumer::/;
    $class = class($class);
  }

  my %arg = (
    %{$reasonable_defaults{$class}},
    service_uri => 'urn:uuid:' . guid_string,
    ledger      => $self->ledger,
    %$args,
  );

  my $c = $arg{ledger}->add_consumer($class, \%arg);

  return $c;
}

sub test_consumer_pair {
  my ($self, $class, $args) = @_;
  $args ||= {};
  my %args = %$args;
  delete $args{bank};

  my $c1 = $self->test_consumer(
    $class,
    { %reasonable_defaults,
      ledger => $self->ledger,
      %args
    },
  );

  my $c0 = $self->test_consumer(
    $class,
    {
      %reasonable_defaults,
      ledger => $self->ledger,
      %$args,
      replacement => $c1
     },
  );

  return $c0;
}

1;
