package Moonpig::App::Ob;
use Moonpig::App::Ob::Config;
use Moonpig::App::Ob::Commands;
use Moonpig::App::Ob::CommandArgs;
use Moonpig::App::Ob::Functions;
use Moonpig::Types qw(Factory);

use Moose;
use Moose::Util::TypeConstraints qw(duck_type class_type);
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
  isa => 'ArrayRef',
  init_arg => undef,
  default => sub { [] },
  traits => [ 'Array' ],
  handles => {
    result_count => 'count',
  },
);

sub it {
  my ($self) = @_;
  if ($self->result_count == 0) { return }
  elsif ($self->result_count == 1) { return $self->last_result->[0] }
  else { return $self->last_result }
}

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
               get_implementation => 'get',
               known_command => 'exists',
             },
  default => sub {
    no warnings 'qw';
    $_[0]->_gen_command_table(qw(exit,quit,q eval reload shell,sh,!
                                 help,?,h
                               ))
  },
);

has command_arg_factory => (
  is => 'ro',
  isa => Factory,
  default => "Moonpig::App::Ob::CommandArgs",
);

has config => (
  is => 'ro',
  isa => class_type('Moonpig::App::Ob::Config'),
  lazy => 1,
  default => sub { Moonpig::App::Ob::Config->new() },
  handles => [ qw(env storage) ],
);

sub readline {
  my ($self) = @_;
  my $prompt = $self->app_id . "> ";
  my $rl = $self->term_readline;
  return my $in = $rl->readline($prompt);
}

sub output {
  my ($self, @str) = @_;
  if (@str < 2) {
    print { $self->output_fh } map _flatten($_), @str;
  } else {
    for my $i (0 .. $#str) {
      printf "%2d %s\n", $i, _flatten($str[$i]);
    }
  }
}

sub _flatten { defined($_[0]) ? $_[0] : "<undef>" }

sub obwarn {
  my ($self, @str) = @_;
  print { $self->output_fh } @str;
}

sub find_command {
  my ($self, $input) = @_;
  my ($command_name, @args) = split /\s+/, $input;
  $command_name = 'eval' unless $self->known_command($command_name);
  return $self->command_arg_factory->new({
    code => $self->get_implementation($command_name),
    primary => $command_name,
    arg_list => [ @args ],
    orig => $input,
    hub => $self,
  });
}

sub run {
  my ($self) = @_;
  while (defined ($_ = $self->readline)) {
    next unless /\S/;
    $self->do_input($_);
  }
}

sub do_input {
  my ($self, $input, $output_rt) = @_;
  $output_rt ||= sub { $self->output(@_) };
  my (@res) = $self->find_command($_)->run();
  if ($@) { warn $@ }
  else {
    $self->last_result([@res]);
    $output_rt->(@res);
  }
}

sub _gen_command_table {
  my ($self, @items) = @_;
  my $BAD = 0;
  my %tab;
  for my $item (@items) {
    my ($cmd) = my @aliases = split /,/, $item;
    unless (defined &{"Moonpig::App::Ob::Commands::$cmd"}) {
      warn "Command '$cmd' not defined in Moonpig::App::Ob::Commands";
      $BAD++;
    }

    for my $alias (@aliases) {
      $tab{$alias} = \&{"Moonpig::App::Ob::Commands::$cmd"};
    }
  }
  exit 1 if $BAD;
  return \%tab;
}

no Moose;

1;
