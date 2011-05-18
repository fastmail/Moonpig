package t::lib::Factory::Consumers;
use Moose::Role;

use Moonpig::Env::Test;
use Moonpig::URI;

use Data::GUID qw(guid_string);
use Moonpig::Util -all;
requires 'ledger';

my %reasonable_defaults = (
  'Moonpig::Class::Consumer::ByTime::FixedCost' => {
    charge_description => "test charge",
    charge_path_prefix => ["test"],
    # description        => "test consumer",
  },
  'Moonpig::Class::Consumer::ByUsage' => {
    charge_path_prefix => ["test"],
  },
  'Moonpig::Class::Consumer::Dummy' => {
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
    %{ $reasonable_defaults{$class} || {} },
    xid         => 'urn:uuid:' . guid_string,
    make_active => 1,
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
    { # %reasonable_defaults,
      ledger => $self->ledger,
      %args
    },
  );

  my $c0 = $self->test_consumer(
    $class,
    {
      #%reasonable_defaults,
      ledger => $self->ledger,
      %$args,
      replacement => $c1
     },
  );

  return $c0;
}

1;
