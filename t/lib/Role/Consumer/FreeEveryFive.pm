package t::lib::Role::Consumer::FreeEveryFive;
use Moose::Role;

sub _joined_chain_at_depth {
  my ($self, $depth, $am_importing) = @_;

  return $self if $am_importing;
  return $self unless $depth % 5 == 0;

  $self->replacement_plan([ get => "/consumer-template/b5g1_free" ]);
  my $repl = $self->build_and_install_replacement;
  return $repl
}

1;
