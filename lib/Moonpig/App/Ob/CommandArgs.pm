package Moonpig::App::Ob::CommandArgs;

use Moose;
use Carp qw(confess croak);

has code => (
  is => 'ro',
  isa => 'CodeRef',
  required => 1,
);

has primary => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has arg_list => (
  is => 'ro',
  isa => 'ArrayRef',
  default => sub { [] },
);

has orig => (
  is => 'ro',
  isa => 'Str',
  default => "",
);

sub orig_args {
  my ($self) = @_;
  my $args = $self->orig;
  my $prim = quotemeta($self->primary);
  $args =~ s/^\s*$prim//;
  return $args;
}

has _eval_res => (
  is => 'ro',
  lazy => 1,
  init_arg => undef,
  default => sub {
    my ($self) = @_;
    my $val = $self->eval($_[0]->orig_args, context => 'scalar',);
    [ $@, $val ];
  },
);

sub value {
  $_[0]->_eval_res->[1];
}

sub eval_ok {
  defined $_[0]->exception;
}

sub exception {
  $_[0]->_eval_res->[0];
}

has hub => (
  is => 'ro',
  weak_ref => 1,
  required => 1,
);

sub eval {
  my ($self, $str, %opts) = @_;
  our ($it, $ob);
  local $ob = $self->hub;
  local $it = $ob->last_result;
  if ($opts{context} eq 'scalar') {
    my $res = eval($str);
    return $res;
  } else {
    croak "Unknown or missing 'context' option";
  }
};

sub run {
  my ($self) = @_;
  return $self->code->($self);
}

no Moose;
1;
