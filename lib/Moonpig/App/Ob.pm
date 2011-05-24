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
#  isa => 'FileHandle',
  default => sub { $_[0]->term_readline->OUT || \*STDOUT },
  lazy => 1,
);

has last_result => (
  is => 'rw',
  isa => 'ArrayRef',
  init_arg => undef,
  traits => [ 'Array' ],
  handles => {
    result_count => 'count',
  },
);

sub BUILD {
  my ($self) = @_;
  my $st = $self->storage;
  my @guids = $st->ledger_guids();
  my @ledgers = map $st->retrieve_ledger_for_guid($_), @guids;
  $self->last_result( [ @ledgers ] );
  $st->_reinstate_stored_time();

  $self->_initial_display(\@guids);
}

sub _initial_display {
  my ($self, $ledger_guids) = @_;

  {
    my $mp_time = Moonpig->env->now;
    my $offset = $mp_time->epoch - time();
    my $d = int($offset / 86_400);
    my $s = $offset - $d * 86_400;
    if ($offset) {
      $self->output(join " ",
                    "Moonpig time : $mp_time",
                    $d ? "$d days" : (),
                    $s ? "$s seconds" : (),
                    "ahead.");
    } else {
      $self->output("Moonpig time == real time");
    }
  }


  if (@$ledger_guids == 0) {
    $self->obwarn("No ledgers in storage\n");
  } elsif (@$ledger_guids == 1) {
    $self->output("\$it = ledger $$->ledger_guids[0]");
  } else {
    for my $i (0 .. $#$ledger_guids) {
      $self->output(sprintf "\$it[%d] = ledger %s", $i, $ledger_guids->[$i]);
    }
  }
}

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
    $_[0]->_gen_command_table(qw(exit,quit,q
                                 eval,dump,x,d,ddump,dd,_internal_eval
                                 reload
                                 shell,sh,!
                                 store,st
                                 wait,z resume
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
  handles => [ qw(env storage dump_options set get maxlines) ],
);

has suppress_next_output => (
  is => 'rw',
  isa => 'Num',
  init_arg => undef,
  default => 0,
);

sub readline {
  my ($self) = @_;
  my $prompt = $self->app_id . "> ";
  my $rl = $self->term_readline;
  return my $in = $rl->readline($prompt);
}

sub replace_output {
  my ($self, @str) = @_;
  my $res = $self->output(@str);
  $self->suppress_next_output(1);
  return $res;
}

sub output {
  my ($self, @str) = @_;

  if ($self->suppress_next_output) {
    $self->suppress_next_output(0);
    return;
  }

  my $fh = $self->output_fh;
  if (@str < 2) {
    print $fh map _flatten($_), @str;
  } else {
    for my $i (0 .. $#str) {
      printf $fh "%2d %s\n", $i, _flatten($str[$i]);
    }
  }
  print $fh "\n";
}

sub _flatten { defined($_[0]) ? $_[0] : "<undef>" }

sub obwarn {
  my ($self, @str) = @_;
  print { $self->output_fh } @str;
}

sub find_command {
  my ($self, $input) = @_;
  $input =~ s/^\s+//;
  my ($command_name, @args) = split /\s+/, $input;
  $command_name = '_internal_eval' unless $self->known_command($command_name);
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

sub eval {
  my ($self, $expr) = @_;
  package Ob;

  our ($env, $it, @it, $ob, $st);
  local $ob = $self;
  local $it = $ob->it;
  local @it = @{$ob->last_result};
  local $st = $ob->storage;
  local $env = Moonpig->env;

  no strict;
  eval $expr;
}


no Moose;

1;
