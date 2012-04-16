package Moonpig::Role::Consumer;
# ABSTRACT: something that uses up money
use Moose::Role;

use Carp qw(confess croak);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110324;
use Stick::Util qw(true false);
use Moonpig::Trait::Copy;

with(
  'Moonpig::Role::CanCancel',
  'Moonpig::Role::CanExpire',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasCreatedAt',
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::CanTransfer' => { transferer_type => "consumer" },
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
);

sub _class_subroute { return }

use List::AllUtils qw(any max);
use Moose::Util::TypeConstraints qw(role_type);
use MooseX::SetOnce;
use MooseX::Types::Moose qw(ArrayRef);
use Moonpig::Types qw(Ledger Millicents Time TimeInterval XID ReplacementPlan);
use Moonpig::Util qw(class event);

use Moonpig::Logger '$Logger';
use namespace::autoclean;

use Moonpig::Behavior::Packable;

use Moonpig::Behavior::EventHandlers;
implicit_event_handlers {
  return {
    'activated' => {
      get_funding => Moonpig::Events::Handler::Method->new(
        method_name => 'acquire_funds',
      ),
    },
    'consumer-create-replacement' => {
      create_replacement => Moonpig::Events::Handler::Method->new(
        method_name => 'build_and_install_replacement',
      ),
    },
    'fail-over' => {
      default => Moonpig::Events::Handler::Method->new(
        method_name => 'failover',
      ),
    },
    'terminate' => {
      default => Moonpig::Events::Handler::Method->new(
        method_name => 'handle_terminate',
      ),
    },
  };
};

has _superseded_at => (
  is => 'rw',
  isa => Time,
  predicate => 'is_superseded',
  init_arg => undef,
  traits => [ qw(Copy SetOnce) ],
);

sub mark_superseded {
  my ($self) = @_;
  return if $self->is_superseded;

  if ($self->is_active) {
    confess sprintf "Can't supersede active consumer for %s (%s)\n",
      $self->xid, $self->guid;
  } elsif ($self->is_expired) {
    confess sprintf "Can't supersede expired consumer for %s (%s)\n",
      $self->xid, $self->guid;
  }

  $self->_superseded_at(Moonpig->env->now);
  $self->abandon_all_unpaid_charges;
  for my $repl (@{$self->_replacement_history}) {
    $repl->mark_superseded if $repl;
  }
}

has _replacement_history => (
  is   => 'ro',
  isa => ArrayRef [ role_type('Moonpig::Role::Consumer') ],
  default => sub { [] },
);

# Convert (replacement => $foo) to (replacement_history => [$foo])
around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;
  my $args = @_ == 1 ? $_[0] : { @_ };
  if (my $replacement = delete $args->{replacement}) {
    $args->{_replacement_history} = [ $replacement ];
  }
  return $class->$orig($args);
};

# List of this consumer's replacement, replacement's replacement, etc.
sub replacement_chain {
  my ($self) = @_;
  return $self->has_replacement
    ? ($self->replacement, $self->replacement->replacement_chain) : ();
}

# The chain length here is a TimeInterval that says how long the chain
# should last for. The created chain will be at least that long.
# It returns the head of the new chain.
publish adjust_replacement_chain => {
   '-http_method' => 'post',
   '-path'        => 'create-replacements',
   chain_duration   => TimeInterval,
} => sub {
  my ($self, $arg) = @_;
  my $chain_duration = $arg->{chain_duration};
  return [ $self->_adjust_replacement_chain($chain_duration)->replacement_chain ];
};

sub _adjust_replacement_chain {
  my ($self, $chain_duration, $depth) = @_;
  $depth //= 0;

  if ($chain_duration <= 0) {
    $self->replacement(undef) if $self->has_replacement;
    return;
  }

  my $replacement = $self->replacement;
  unless ($replacement) {
    $replacement = $self->build_and_install_replacement()
      # The consumer specifies no replacement, so we can't continue the chain
      or confess(sprintf "replacement chain ended with %d days to go",
                 $chain_duration / 86400);
  }

  $replacement = $replacement->_joined_chain_at_depth($depth+1)
    if $replacement->can('_joined_chain_at_depth');

  $replacement->_adjust_replacement_chain(
    $chain_duration - $replacement->estimated_lifetime,
    $depth + 1,
  );

  return $replacement;
}

# Does this consumer, or any consumer in its replacement chain,
# have funds?  If so, the funds will be lost if the consumer is superseded
sub is_funded {
  my ($self) = @_;
  return $self->unapplied_amount > 0
    || ($self->has_replacement && $self->replacement->is_funded);
}

sub replacement {
  my ($self, $new_replacement) = @_;

  if (@_ > 1) {
    croak "Too late to set replacement of expired consumer $self" if $self->is_expired;
    croak "Can't set replacement on superseded consumer $self" if $self->is_superseded;
    if ($self->has_replacement) {
      croak "Can't replace funded consumer chain" if $self->replacement->is_funded;
      $self->replacement->mark_superseded;
    }

    push @{$self->_replacement_history}, $new_replacement;
    return $new_replacement;
  } else {
    return $self->_replacement_history->[-1];
  }
}

sub has_replacement {
  my ($self) = @_;
  defined($self->replacement);
}

has replacement_plan => (
  is  => 'rw',
  isa => ReplacementPlan,
  required => 1,
  traits   => [ qw(Array Copy) ],
  handles  => {
    replacement_plan_parts => 'elements',
  },
);

sub build_replacement {
  my ($self) = @_;

  Moonpig::X->throw("can't build replacement: one exists")
    if $self->has_replacement;

  $Logger->log([ "trying to set up replacement for %s", $self->TO_JSON ]);

  my $replacement_template = $self->_replacement_template;

  # i.e., it's okay if we return undef from _replacement_template; that's how
  # "nothing" will work
  return unless $replacement_template;

  my $replacement = $self->ledger->add_consumer_from_template(
    $replacement_template,
    { xid => $self->xid, $self->_replacement_extra_args },
  );

  return $replacement;
}

sub build_and_install_replacement {
  my ($self) = @_;
  my $replacement = $self->build_replacement();
  $self->replacement($replacement);
  return $replacement;
}

sub _replacement_extra_args { return () }

sub _replacement_template {
  my ($self) = @_;

  my ($method, $uri, $arg) = $self->replacement_plan_parts;

  my @parts = split m{/}, $uri;

  my $wrapped_method;

  if ($parts[0] eq '') {
    # /foo/bar -> [ '', 'foo', 'bar' ]
    shift @parts;
    $wrapped_method = Moonpig->env->route(\@parts);
  } else {
    $wrapped_method = $self->route(\@parts);
  }

  my $result;

  if ($method eq 'get') {
    $result = $wrapped_method->resource_get;
  } elsif ($method eq 'post' or $method eq 'put') {
    my $call = "resource_$method";
    $result = $wrapped_method->$call($arg);
  } else {
    Moonpig::X->throw("illegal replacement plan method");
  }

  return $result;
}

sub handle_cancel {
  my ($self, $event) = @_;
  return if $self->is_canceled;
  $self->mark_canceled;
  if ($self->has_replacement) {
    $self->replacement->expire;
  } else {
    # XXX Now that replacements can be superseded, shouldn't this occur
    # even if there is a replacement already? 2012-01-23 mjd
    $self->replacement_plan([ get => '/nothing' ]);
  }
  return;
}

has xid => (
  is  => 'ro',
  isa => XID,
  required => 1,
  traits => [ qw(Copy) ],
);

before expire => sub {
  my ($self) = @_;

  $self->handle_event(
    $self->has_replacement
    ? event('fail-over')
    : event('terminate')
  );
};

after BUILD => sub {
  my ($self, $arg) = @_;

  if ( exists $arg->{minimum_chain_duration}
    && exists $arg->{replacement_chain_duration}
  ) {
    Moonpig::X->throw(
      "supply only one of minimum_chain_duration and replacement_chain_duration"
    );
  }

  if (exists $arg->{replacement_chain_duration}) {
    $self->_adjust_replacement_chain(delete $arg->{replacement_chain_duration});
  }

  if (exists $arg->{minimum_chain_duration}) {
    my $wanted    = delete $arg->{minimum_chain_duration};
    my $extend_by = max(0, $wanted - $self->estimated_lifetime);
    $self->_adjust_replacement_chain($extend_by, 1);
  }

  $self->become_active if delete $arg->{make_active};
};

sub is_active {
  my ($self) = @_;

  $self->ledger->_is_consumer_active($self) ? true : false;
}

has activated_at => (
  is   => 'ro',
  isa  => Time,
  init_arg => undef,
  traits => [ qw(SetOnce) ],
  writer => '__set_activated_at'
);

# note that this might be called before the consumer is added to the ledger.
# So don't expect that $self->ledger->active_consumer_for_xid($self->xid)
# will return $self here. 20110610 MJD
sub become_active {
  my ($self) = @_;

  $self->ledger->mark_consumer_active__($self);
  $self->__set_activated_at( Moonpig->env->now );
  $self->handle_event( event('activated') );
}

sub failover {
  my ($self) = @_;

  $self->ledger->failover_active_consumer__($self);
}

publish _terminate => { -http_method => 'post', -path => 'terminate' } => sub {
  my ($self) = @_;
  $self->handle_event(event('terminate'));
  return;
};

sub handle_terminate {
  my ($self, $event) = @_;

  $Logger->log([
    'terminating service: %s',
    $self->ident,
  ]);

  $self->handle_event(event('cancel'));
  $self->ledger->mark_consumer_inactive__($self);
}

# Create a copy of myself in the specified ledger; commit suicide,
# and return the copy.
# This method is called "copy_to" and not "move_to" by analogy with
# Unix "cp" (which it is like) and not "mv" (which it is not).  The
# original consumer object is not merely relinked into the new ledger;
# it is copied there.
sub copy_to {
  my ($self, $target) = @_;
  my $copy;
  Moonpig->env->storage->do_rw(
    sub {
      $copy = $target->add_consumer(
        $self->meta->name,
        $self->copy_attr_hash__
      );
      $target->save;
      $self->copy_balance_to__($copy);
      $self->copy_subcomponents_to__($target, $copy);
      { # We have to terminate service before activating service, or else the
        # same xid would be active in both ledgers at once, which is forbidden
        my $was_active = $self->is_active;
        $self->handle_event(event('terminate'));
        $copy->become_active if $was_active;
      }
    });
  return $copy;
}

# "Move" my balance to a different consumer.  This will work even if
# the consumer is in a different ledger.  It works by entering a
# charge to the source consumer for its entire remaining funds, then
# creating a credit in the recipient consumer's ledger and
# transferring the credit to the recipient.
sub copy_balance_to__ {
  my ($self, $new_consumer) = @_;
  my $amount = $self->unapplied_amount;
  return if $amount == 0;

  Moonpig->env->storage->do_rw(
    sub {
      my ($ledger, $new_ledger) = ($self->ledger, $new_consumer->ledger);
      $self->charge_current_journal({
        desc        => sprintf("Transfer management of '%s' to ledger %s",
                               $self->xid, $new_ledger->guid),
        amount      => $amount,
        extra_tags  => [ "transient" ],
      });

      my $credit = $new_ledger->add_credit(
        class('Credit::Transient'),
        {
          amount               => $amount,
          source_guid          => $self->guid,
          source_ledger_guid   => $ledger->guid,
        },
      );

      $new_ledger->accountant->create_transfer({
        type => 'consumer_funding',
        from => $credit,
        to   => $new_consumer,
        amount => $amount,
      });

      $new_consumer->abandon_all_unpaid_charges;

      $new_ledger->save;
    }
  );
}

# roles will decorate this method with code to move subcomponents to the copy
sub copy_subcomponents_to__ {
  my ($self, $target, $copy) = @_;
  $copy->replacement($self->replacement->copy_to($target))
    if $self->replacement;
}

sub copy_attr_hash__ {
  my ($self) = @_;
  my %hash;
  for my $attr ($self->meta->get_all_attributes) {
    if ($attr->does("Moose::Meta::Attribute::Custom::Trait::Copy")
          && $attr->has_value($self)) {
      my $name = $attr->name;
      my $read_method = $attr->get_read_method;
      $hash{$name} = $self->$read_method();
    }
  }
  return \%hash;
}

publish template_like_this => {
  '-http_method' => 'get',
  '-path'        => 'template-like-this',
} => sub {
  my ($self) = @_;

  return {
    class => $self->meta->name,
    arg   => $self->copy_attr_hash__,
  };
};

sub charge_current_journal {
  my ($self, $args) = @_;

  my @extra_tags = @{delete $args->{extra_tags} || [] };
  $args->{from}       ||= $self;
  $args->{to}         ||= $self->ledger->current_journal;
  $args->{extra_tags} ||= [];
  $args->{tags}       ||= [ @{$self->journal_charge_tags}, @extra_tags ];
  $args->{date}       ||= Moonpig->env->now;

  return $self->ledger->current_journal->charge($args);
}

has extra_journal_charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
  traits => [ qw(Copy) ],
);

sub journal_charge_tags {
  my ($self) = @_;
  return [ $self->xid, @{$self->extra_journal_charge_tags} ]
}

sub charge_current_invoice {
  my ($self, $args) = @_;
  $self->charge_invoice($self->ledger->current_invoice, $args);
}

sub charge_invoice {
  my ($self, $invoice, $args) = @_;

  my @extra_tags = @{delete $args->{extra_tags} || [] };
  $args->{consumer}   ||= $self;
  $args->{tags}       ||= [ @{$self->invoice_charge_tags}, @extra_tags ];

  # If there's no ->build_invoice_charge method, let the Invoice
  # object build the charge from the arguments.
  $args = $self->build_invoice_charge($args) if $self->can("build_invoice_charge");

  $invoice->add_charge($args);
}

has extra_invoice_charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
  traits => [ qw(Copy) ],
);

sub invoice_charge_tags {
  my ($self) = @_;
  return [ $self->xid, @{$self->extra_invoice_charge_tags} ]
}

# and return a list (or count) of the abandoned charges
sub abandon_charges_on_invoice {
  my ($self, $invoice) = @_;
  my @charges = grep ! $_->is_abandoned,
    grep $self->guid eq $_->owner_guid,
      $invoice->all_charges;
  $_->mark_abandoned for @charges;
  return @charges;
}

sub abandon_all_unpaid_charges {
  my ($self) = @_;
  grep $self->abandon_charges_on_invoice($_) > 0,
    grep { ! $_->is_paid && ! $_->is_abandoned } $self->ledger->invoices;
}

sub all_charges {
  my ($self) = @_;

  # If the invoice was closed before we were created, we can't be on it!
  # -- rjbs, 2012-03-06
  my $guid = $self->guid;
  my @charges = grep { $_->owner_guid eq $guid }
                map  { $_->all_charges }
                grep { ! $_->is_closed || $_->closed_at >= $self->created_at }
                $self->ledger->invoices;

  return @charges;
}

sub relevant_invoices {
  my ($self) = @_;

  # If the invoice was closed before we were created, we can't be on it!
  # -- rjbs, 2012-03-06
  my $guid = $self->guid;
  my @invoices = grep { (! $_->is_closed || $_->closed_at >= $self->created_at)
                        && any { $_->owner_guid eq $guid } $_->all_charges
                      } $self->ledger->invoices;

  return @invoices;
}

sub acquire_funds {
  my ($self) = @_;
  return unless $self->is_active or $self->is_expired;

  $_->__execute_charges_for($self)
    for grep { $_->is_paid } $self->relevant_invoices;

  return;
}

sub effective_funding_pairs {
  my ($self) = @_;

  return $self->ledger->accountant->__compute_effective_transferrer_pairs({
    thing => $self,
    to_thing   => [ qw(consumer_funding) ],
    from_thing => [ qw(cashout) ],
    negative   => [ qw(cashout) ],
  });
}

sub cashout_unapplied_amount {
  my ($self) = @_;
  my $balance = $self->unapplied_amount;

  return unless $balance > 0;

  my @source_pairs = $self->effective_funding_pairs;
  my @credits = map { $source_pairs[$_] } grep { ! $_ % 2 } keys @source_pairs;

  # This is the order in which we will refund:  first, to non-refundable
  # credits (because we use up "real money" first); within those, to the
  # largest credit first, to minimize the number of credits to which we might
  # have to cashout money. -- rjbs, 2012-03-06
  @credits = sort { $a->is_refundable  <=> $b->is_refundable
                 || $b->applied_amount <=> $a->applied_amount } @credits;

  while ($balance and @credits) {
    my $next_credit = shift @credits;

    my $to_xfer = $balance <= $next_credit->applied_amount
                ? $balance
                : $next_credit->applied_amount;

    $self->ledger->accountant->create_transfer({
      type   => 'cashout',
      to     => $next_credit,
      from   => $self,
      amount => $to_xfer,
    });

    $balance -= $to_xfer;
  }

  Moonpig::X->throw("could not refund all remaining balance") if $balance != 0;

  return;
}

publish quote_for_extended_service => {
  -http_method   => 'post',
  chain_duration => TimeInterval,
} => sub {
  my ($self, $arg) = @_;
  Moonpig::X->throw("consumer not active") unless $self->is_active;

  my $ledger = $self->ledger;

  my $quote = $ledger->quote_for_extended_service(
    $self->xid,
    $arg->{chain_duration}
  );

  return $quote;
};

PARTIAL_PACK {
  return {
    xid       => $_[0]->xid,
    is_active => $_[0]->is_active,
    unapplied_amount => $_[0]->unapplied_amount,
  };
};

1;
