package Moonpig::App::Ob;

use Moose;
use Moose::Util::TypeConstraints qw(duck_type);
use Term::ReadLine;

has app_id => (
  is => 'ro',
  isa => 'Str',
  default => "ob",
);

has output_fh => (
  is => 'rw',
  isa => 'FileHandle',
  default => sub { $_[0]->term_readline->OUT || \*STDOUT },
  lazy => 1,
);

has last_result => (
  is => 'rw',
  isa => 'Any',
  init_arg => undef,
);

has term_readline => (
  is => 'ro',
  isa => duck_type([qw(addhistory readline OUT)]),
  lazy => 1,
  default => sub { Term::ReadLine->new($_[0]->app_id) },
);

has command_table => (
  is => 'ro',
  isa => 'HashRef[CodeRef]',
  traits => [ qw(Hash) ],
  handles => { install_command => 'set',
               get_command => 'get',
               known_command => 'exists',
             },
  default => sub { {} },
);

sub readline {
  my ($self) = @_;
  my $prompt = $self->app_id . "> ";
  my $rl = $self->term_readline;
  return my $in = $rl->readline($prompt);
}

sub output {
  my ($self, @str) = @_;
  print { $self->output_fh } map defined() ? $_ : "<undef>", @str;
}

sub find_command {
  my ($self, $input) = @_;
  my ($command, @args) = split /\s+/, $input;
  if ($self->known_command($command)) {
    return sub { $self->get_command($command)->(@args) };
  } else {
    return;
  }
}

sub run {
  my ($self) = @_;
  while (defined ($_ = $self->readline)) {
    if (my $cmd = $self->find_command($_)) {
      $cmd->();
    } else {
      our $it;
      local $it = $self->last_result;
      my $res = eval($_);
      if ($@) { warn $@ }
      else {
        $self->last_result($res);
        $self->output($res, "\n")
      }
    }
  }
}

no Moose;

1;
