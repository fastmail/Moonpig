package t::lib::Factory::Consumers;
use Moose::Role;

use Moonpig::Ledger::Basic;
use Moonpig::Contact::Basic;
use Moonpig::Bank::Basic;
use Moonpig::Consumer::ByTime;
use Moonpig::URI;

use Moonpig::Util -all;
requires 'ledger';

my %reasonable_defaults = (
    cost_amount => dollars(1),
    cost_period => DateTime::Duration->new( days => 1 ),
    old_age => DateTime::Duration->new( days => 0 ),
    replacement_mri => Moonpig::URI->nothing(),
);

sub test_consumer {
  my ($self, $class, $args) = @_;
  $args ||= {};
  $class ||= 'Moonpig::Consumer::Basic';
  $class = "Moonpig::Consumer" . $class if $class =~ /^::/;

  my $c = $class->new({
    %reasonable_defaults,
    ledger => $self->ledger,
    %$args,
  });

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
