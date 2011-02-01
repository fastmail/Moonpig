
package Moonpig::Ledger::Accountant;
use Carp qw(confess croak);
use Moonpig::TransferUtil;
use Moonpig::Ledger::Accountant::Iterator;
use Moonpig::Ledger::Accountant::Transfer;
use Moose;

with 'Role::Subsystem' => {
  ident  => 'ledger-accountant',
  type   => 'Moonpig::Role::Ledger',
  what   => 'ledger',
  weak_ref => 0,
};

################################################################
#
# Each transfer has a source, destination, and guid.
# Each transfer is listed exactly once in each of the three following hashes:
# By source in %by_src, by destination in %by_dst, and by GUID in %by_id.

# This is a hash whose keys are GUIDs of objects such as banks or
# consumers, and whose values are arrays of transfers.  For object X,
# all transfers from X are listed in $by_src{$X->guid}.
has by_src => (
  is => 'ro',
  isa => 'HashRef',
  default => sub { {} },
);

# Like %by_src, but backwards
has by_dst => (
  is => 'ro',
  isa => 'HashRef',
  default => sub { {} },
);

# Keys here are transfer GUIDs and values are transfer objects
has by_id => (
  is => 'ro',
  isa => 'HashRef',
  default => sub { {} },
);

has transfer_factory => (
  is => 'ro',
  isa => 'Str|Object',
  default => sub { 'Moonpig::Ledger::Accountant::Transfer' },
);

sub create_transfer {
  my ($self, $arg) = @_;
  $arg or croak "Missing arguments to create_transfer";

  my ($from, $to, $type) = @{$arg}{qw(from to type)};

  croak "missing 'from'" unless defined $from;
  croak "missing 'to'" unless defined $to;
  croak "missing transfer type" unless defined $type;
  croak "missing amount" unless defined $arg->{amount};

  my $skip_funds_check = delete $arg->{skip_funds_check};
  if (! $skip_funds_check && $from->unapplied_amount < $arg->{amount}) {
    croak "Refusing overdraft transfer of $arg->{amount} from " .
      $from->TO_JSON . "; it has only " . $from->unapplied_amount;
  }
  my $t = $self->transfer_factory->new({
    source => $from,
    target => $to,
    type   => $type,
    amount => $arg->{amount},
    exists $arg->{date} ? (date => $arg->{date}) : (),
    ledger => $self->ledger,
  });
  return unless $t;

  push @{$self->by_src->{$from->guid}}, $t;
  push @{$self->by_dst->{$to->guid}}, $t;
  $self->by_id->{$t->guid} = $t;

  return $t;
}

sub delete_transfer {
  my ($self, $transfer) = @_;
  my $src = $self->by_src->{$transfer->source->guid};
  my $dst = $self->by_dst->{$transfer->target->guid};

  @$src = grep $_->guid ne $transfer->guid, @$src;
  @$dst = grep $_->guid ne $transfer->guid, @$dst;
  delete $self->by_id->{$transfer->guid};
}

BEGIN {
  for my $type (Moonpig::TransferUtil->transfer_types) {
    my $check = sub {
      my $a_type = $_[0]->transferer_type;
      croak "Expected object of type '$type', got '$a_type' instead"
        unless $a_type eq $type;
    };
    my $from = sub {
      my ($self, $source) = @_;
      $check->($source);
      $self->select({source => $source});
    };
    my $to = sub {
      my ($self, $target) = @_;
      $check->($target);
      $self->select({target => $target});
    };
    my $all_for = sub {
      my ($self, $who) = @_;
      $check->($who);
      my $f = $self->select({source => $who});
      my $t = $self->select({target => $who});
      return (ref $f)->union($f, $t);
    };
    {
      no strict 'refs';
      *{"from_$type"} = $from;
      *{"to_$type"} = $to;
      *{"all_for_$type"} = $all_for;
    }
  }
}

# args: source, target, type, before, after
sub select {
  my ($self, $args) = @_;
  my $SS = exists($args->{source});
  my $TT = exists($args->{target});
  my $s = $SS ? $self->by_src->{$args->{source}->guid} : [];
  my $t = $TT ? $self->by_dst->{$args->{target}->guid} : [];

  my $res;
  if ($SS && $TT) {
    if (@$s < @$t) {
      $res = $self->iterator_factory->new($s)->with_target($args->{target});
    } else {
      $res = $self->iterator_factory->new($t)->with_target($args->{source});
    }
  } elsif ($SS) {
    $res = $self->iterator_factory->new($s);
  } elsif ($TT) {
    $res = $self->iterator_factory->new($t);
  } else {
    croak "source or target specifier required in transfer selection";
  }

  $res = $res->before   ($args->{before}) if exists $args->{before};
  $res = $res->after    ($args->{after} ) if exists $args->{after} ;
  $res = $res->with_type($args->{type}  ) if exists $args->{type}  ;

  return $res;
}

has iterator_factory => (
  is => 'ro',
  isa => 'Str|Object',
  default => sub { 'Moonpig::Ledger::Accountant::Iterator' },
);

sub _convert_transfer_type {
  my ($self, $transfer, $from_type, $to_type) = @_;
  croak "Transfer is not a $from_type" unless $transfer->type eq $from_type;
  my $new = $self->create_transfer({
    source => $transfer->source,
    target => $transfer->target,
    type => $to_type,
    amount => $transfer->amount,
    skip_funds_check => 1,
  });
  $self->delete_transfer($transfer) if $new;
  return $new;
}

sub commit_hold {
  my ($self, $hold) = @_;
  return $self->_convert_transfer_type($hold, 'hold' => 'transfer');
}


no Moose;
1;

