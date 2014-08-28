package Moonpig::Ledger::Accountant;
# ABSTRACT: a ledger's transfer-tracking subsystem

use Moose;

use Carp qw(confess croak);
use Moonpig::TransferUtil ();
use Moonpig::Ledger::Accountant::TransferSet;
use Moonpig::Ledger::Accountant::Transfer;
use MooseX::StrictConstructor;
use Scalar::Util qw(blessed);
use Moonpig::Util qw(pair_rights sum);

use namespace::autoclean;

with 'Role::Subsystem' => {
  ident  => 'ledger-accountant',
  type   => 'Moonpig::Role::Ledger',
  what   => 'ledger',
  id_method => 'guid',

  # This getter should not be needed.  Nothing should be trying to talk to the
  # accountant after its ledger has been garbage collected, but we need to
  # supply a getter if we want to hold a weak ref -- which we do, because we
  # want the entire object graph of a ledger to be garbage collectable.  So,
  # either we put in this bogus getter, or we add a DEMOLISH to Ledger and mark
  # this (weak_ref => 0).  For now, this is the one I picked. -- rjbs,
  # 2011-03-22
  getter    => sub { confess("can't retrieve garbage collected ledger") },
};

################################################################
#
# Each transfer has a source, destination, and guid.
# Each transfer is listed exactly once in each of the three following hashes:
# By source in %by_src, by destination in %by_dst, and by GUID in %by_id.

# This is a hash whose keys are GUIDs of objects such as invoices or
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

has last_serial_number => (
  is  => 'ro',
  isa => 'Int',
  init_arg => undef,
  default  => 0,
  traits   => [ 'Counter' ],
  handles  => { next_serial_number => 'inc' },
);

sub create_transfer {
  my ($self, $arg) = @_;
  $arg or croak "Missing arguments to create_transfer";

  my ($from, $to, $type) = @{$arg}{qw(from to type)};

  croak "missing 'from'" unless defined $from;
  croak "missing 'to'" unless defined $to;
  croak "missing transfer type" unless defined $type;
  croak "missing amount" unless defined $arg->{amount};

  if ($ENV{MOONPIG_TRACE_TRANSFERS}) {
    warn "# transfer $arg->{amount} from " . $from->ident . " to " .
      $to->ident . " ($type)\n";
  }

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
    serial_number => $self->next_serial_number,
  });
  return unless $t;

  push @{$self->by_src->{$from->guid}}, $t;
  push @{$self->by_dst->{$to->guid}}, $t;
  $self->by_id->{$t->guid} = $t;

  return $t;
}

sub _force_delete_transfer {
  my ($self, $transfer) = @_;
  my $src = $self->by_src->{$transfer->source->guid} ||= [];
  my $dst = $self->by_dst->{$transfer->target->guid} ||= [];

  @$src = grep $_->guid ne $transfer->guid, @$src;
  @$dst = grep $_->guid ne $transfer->guid, @$dst;
  delete $self->by_id->{$transfer->guid};
}

sub delete_transfer {
  my ($self, $transfer) = @_;
  my $type = $transfer->type;
  croak "Can't delete transfer of immortal type '$type'"
    unless $transfer->is_deletable;
  $self->_force_delete_transfer($transfer);
}

BEGIN {
  for my $type (Moonpig::TransferUtil::transfer_types) {
    my $check = sub {
      croak "$_[0] is not something that participates in transfers"
        unless blessed $_[0] && $_[0]->does('Moonpig::Role::CanTransfer');
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

# args: source, target, type, newer_than, newer_than
sub select {
  my ($self, $args) = @_;
  my $SS = exists($args->{source});
  my $TT = exists($args->{target});
  my $s = $SS ? $self->by_src->{$args->{source}->guid} : [];
  my $t = $TT ? $self->by_dst->{$args->{target}->guid} : [];

  my $res;
  if ($SS && $TT) {
    if (@$s < @$t) {
      $res = $self->transfer_set_factory->new($s)->with_target($args->{target});
    } else {
      $res = $self->transfer_set_factory->new($t)->with_target($args->{source});
    }
  } elsif ($SS) {
    $res = $self->transfer_set_factory->new($s);
  } elsif ($TT) {
    $res = $self->transfer_set_factory->new($t);
  } else {
    croak "source or target specifier required in transfer selection";
  }

  $res = $res->older_than($args->{older_than}) if exists $args->{older_than};
  $res = $res->newer_than($args->{newer_than}) if exists $args->{newer_than};
  $res = $res->with_type ($args->{type}      ) if exists $args->{type}      ;

  return $res;
}

has transfer_set_factory => (
  is => 'ro',
  isa => 'Str|Object',
  default => sub { 'Moonpig::Ledger::Accountant::TransferSet' },
);

sub _convert_transfer_type {
  my ($self, $transfer, $from_type, $to_type) = @_;
  croak "Transfer is not a $from_type" unless $transfer->type eq $from_type;
  croak "Transfer is not deletable"
    unless $transfer->is_deletable($from_type);

  my $new = $self->create_transfer({
    from   => $transfer->source,
    to     => $transfer->target,
    type   => $to_type,
    amount => $transfer->amount,
    skip_funds_check => 1, # do not check for overdraft...
  });
  # ... because we are about to do this:
  $self->_force_delete_transfer($transfer) if $new;
  return $new;
}

sub commit_hold {
  my ($self, $hold) = @_;
  return $self->_convert_transfer_type($hold, 'hold' => 'transfer');
}

sub __compute_effective_transferrer_pairs {
  my ($self, $arg) = @_;
  my $thing = $arg->{thing};
  my $to    = $arg->{to_thing};
  my $from  = $arg->{from_thing};
  my $neg   = $arg->{negative};
  my $cap   = $arg->{upper_bound};

  # positive_types
  # negative_types

  # return (xfer_source => $amount, ... );

  my @transfers = sort { $a->serial_number <=> $b->serial_number } (
    (map {; $self->select({ target => $thing, type => $_ })->all } @$to),
    (map {; $self->select({ source => $thing, type => $_ })->all } @$from),
  );

  my %is_neg  = map {; $_ => 1 } @$neg;
  my %is_from = map {; $_ => 1 } @$from;

  my %credit_for;
  my %funds_from;
  for my $transfer (@transfers) {
    my ($amount, $credit) = $is_from{ $transfer->type }
                          ? ($transfer->amount, $transfer->target)
                          : ($transfer->amount, $transfer->source);

    $amount *= -1 if $is_neg{ $transfer->type };

    my $guid = $credit->guid;
    $credit_for{ $guid } //= $credit;
    $funds_from{ $guid } += $amount;

    Moonpig::X->throw("drawn below zero") if $funds_from{ $guid } < 0;

    Moonpig::X->throw("funded above maximum")
      if defined $cap and sum pair_rights(%funds_from) > $cap;
  }

  return(
    map  {; $credit_for{$_}, $funds_from{$_} }
    grep {; $funds_from{$_} }
    keys %funds_from
  );
}

no Moose;
1;
