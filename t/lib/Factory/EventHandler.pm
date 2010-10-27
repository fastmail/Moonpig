package t::lib::Factory::EventHandler;
use Moose::Role;

use namespace::autoclean;

sub make_event_handler {
  my ($self, $moniker, $arg) = @_;
  my $class = "Moonpig::Events::Handler::$moniker";
  Class::MOP::load_class($class);

  return $class->new($arg);
}

1;
