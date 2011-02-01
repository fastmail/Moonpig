package Moonpig::Ledger::Accountant::Iterator;
use Moonpig::TransferUtil;

sub new {
  my ($class, $array) = @_;
  my $i = 0;
  bless sub {
    return if $i > $#$array;
    return $array->[$i++];
  } => $class;
}

sub next {
  my ($self) = @_;
  return $self->();
}

sub filter {
  my ($self, $pred) = @_;
  bless sub {
    my $c;
    1 while defined($c = $self->next) && ! $pred->($c);
    return $c;
  } => ref($self);
}

# return transfers newer than $max_age (which is in seconds)
sub newer_than {
  my ($self, $max_age) = @_;
  my $now = Moonpig->env->now();
  $self->filter(sub { $now - $_[0]->date < $max_age });
}

# return transfers older than $min_age (which is in seconds)
sub older_than {
  my ($self, $min_age) = @_;
  my $now = Moonpig->env->now();
  $self->filter(sub { $now - $_[0]->date > $min_age });
}

sub with_type {
  my ($self, $type) = @_;
  $self->filter(sub { $_[0]->type eq $type });
}

sub with_source {
  my ($self, $source) = @_;
  $self->filter(sub { $_[0]->source->guid eq $source->guid });
}

sub with_target {
  my ($self, $target) = @_;
  $self->filter(sub { $_[0]->target->guid eq $target->guid });
}

sub all {
  my ($self) = @_;
  my (@all, $t);
  push @all, $t while $t = $self->next;
  return @all;
}

sub union {
  my ($class, @its) = @_;
  bless sub {
    my $c;
    shift @its until @its == 0 || defined($c = $its[0]->next);
    return unless @its;
    return $c;
  } => $class;
}

sub _make_filter {
  my ($pred) = @_;
  sub { $_[0]->filter($pred) };
}

BEGIN {
  for my $type (Moonpig::TransferUtil->transfer_types) {
    *{"$type\_only"} = _make_filter(sub { $_[0]->type eq $type });
  }
}

1;
