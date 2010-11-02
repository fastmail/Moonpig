package Moonpig::URI;

use base 'URI';

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);
  bless $self => $class;
}

sub nothing { $_[0]->new("moonpig:/nothing") }

1;
