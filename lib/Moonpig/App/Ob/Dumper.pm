package Moonpig::App::Ob::Dumper;
use strict;
use warnings;
use Scalar::Util qw(blessed reftype);

use Sub::Exporter -setup => {
  exports => [ 'Dump' ],
  groups => { default => [ 'Dump' ] },
};

use Moose;

has undef => (
  is => 'rw',
  isa => 'Str',
  default => '<undef>',
);

has maxdepth => (
  is => 'rw',
  isa => 'Num',
  default => -1,
  predicate => 'has_maxdepth',
);

has depth => (
  is => 'rw',
  isa => 'Num',
  default => 0,
  init_arg => undef,
);

has indent => (
  is => 'rw',
  isa => 'Str',
  default => "| ",
);

has cur_indent => (
  is => 'rw',
  isa => 'Str',
  default => "",
  init_arg => undef,
);

# extra prefix to add to next output line
has next_prefix => (
  is => 'rw',
  isa => 'Str',
  init_arg => undef,
  predicate => 'has_next_prefix',
  clearer => 'clear_next_prefix',
);

sub get_next_prefix {
  my ($self) = @_;
  my $in;
  if ($self->has_next_prefix) {
    $in = $self->next_prefix;
    $self->clear_next_prefix;
  } else {
    $in = "";
  }
  return $in;
}

has result => (
  is => 'rw',
  isa => 'Str',
  default => "",
  init_arg => undef,
  clearer => 'clear_result',
);

has seen => (
  is => 'ro',
  isa => 'HashRef',
  default => sub { {} },
  init_arg => undef,
);

sub has_seen {
  my ($self, $what) = @_;
  exists $self->seen->{$what};
}

has path => (
  is => 'ro',
  isa => 'ArrayRef',
  default => sub { [] },
  init_arg => undef,
);

has prune_criteria => (
  is => 'ro',
  isa => 'ArrayRef',
  default => sub { [ qr/^DateTime/,
                     qr/^Moonpig::DateTime$/,
                     qr/^Moonpig::Events::EventHandlerRegistry/
                    ] },
);

sub prune_this {
  my ($self, $this) = @_;
  for my $prune_criterion (@{$self->prune_criteria}) {
    if (ref($prune_criterion) eq "Regexp") {
      return 1 if blessed($this) =~ $prune_criterion;
    } else {
      my $ref = ref($prune_criterion);
      die "Unknown prune_criterion type '$ref' for '$prune_criterion'";
    }
  }
  return 0;
}

sub ap {
  my ($self, @strs) = @_;
  $self->result(join "", $self->result, @strs);
  return $self;
}

sub aplines {
  my ($self, @lines) = @_;
  return unless @lines;
  $lines[0] = $self->get_next_prefix . $lines[0];
  $self->ap(map $self->cur_indent . "$_\n", @lines);
}

sub at_maxdepth {
  my ($self) = @_;
  $self->depth == $self->maxdepth;
}

sub Dump {
  my $self = __PACKAGE__->new();
  return $self->dump_value(@_)->result;
}

sub dump_values {
  my $self = shift;
  if (@_ == 0) { $self }
  elsif (@_ == 1) { $self->dump_value($_[0]) }
  else { $self->dump_array([ @_ ]) }
}

sub dump_value {
  my ($self, $val) = @_;
  my $rt = reftype $val;
  if (! defined $rt) { $self->dump_scalar($val) }
  elsif ($rt eq "ARRAY") { $self->dump_array($val) }
  elsif ($rt eq "HASH") { $self->dump_hash($val) }
  elsif ($rt eq "SCALAR" || $rt eq "REF") { $self->dump_scalar_ref($val) }
  else { $self->dump_scalar($val) }
}

sub recurse {
  my ($self, $into, $code) = @_;
  $self->aplines($into);
  return if $self->at_maxdepth;

  if ($self->depth > 0 && not $self->recurse_into($into)) {
    return $self;
  }

  if ($self->has_seen($into)) {
    $self->aplines("  ...");
    return $self;
  }

  my $old_depth = $self->depth;
  my $old_indent = $self->cur_indent;
  push @{$self->path}, $into;
  $self->seen->{$into} = 1;
  $self->depth($old_depth + 1);
  $self->cur_indent($old_indent . $self->indent);

  $code->();

  pop @{$self->path};
  $self->cur_indent($old_indent);
  $self->depth($old_depth);
  return $self;
}

sub recurse_into {
  my ($self, $what) = @_;
  return 0 if blessed($what) && $self->prune_this($what);
  return 1;
}

sub dump_array {
  my ($self, $ar) = @_;
  $self->recurse($ar,
    sub {
      for my $i (0 .. $#$ar) {
        $self->next_prefix("$i ");
        $self->dump_value($ar->[$i]);
      }
    });
  return $self;
}

sub dump_hash {
  my ($self, $ha) = @_;
  $self->recurse($ha,
    sub {
      for my $k (sort keys %$ha) {
        $self->next_prefix("'$k' => ");
        $self->dump_value($ha->{$k});
      }
    });
  return $self;
}

sub dump_scalar {
  my ($self, $sc) = @_;
  if (not defined $sc) {
    $self->aplines($self->undef);
  } else {
    $self->aplines($sc);
  }
  return $self;
}

sub dump_scalar_ref {
  my ($self, $sr) = @_;
  $self->recurse($sr,
                 sub { $self->dump_value($$sr) });
}

1;
