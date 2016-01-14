package t::lib::Factory::EventHandler;
use Moose::Role;

use String::RewritePrefix;

use namespace::autoclean;

sub make_event_handler {
  my ($self, $moniker, $arg) = @_;
  my $class = String::RewritePrefix->rewrite(
    {
      ''    => 'Moonpig::Events::Handler::',
      '='   => '',
      't::' => 't::lib::Class::EventHandler::',
    },
    $moniker,
  );
  Class::Load::load_class($class);

  return $class->new(defined $arg ? $arg : ());
}

1;
