package Moonpig::Role::Ledger;
# ABSTRACT: the fundamental hub of a billable account

use 5.12.0;

use Carp qw(confess croak);
use Moose::Role;

use Email::MessageID;
use Sort::ByExample ();
use Sys::Hostname::Long;

use Stick::Publisher 0.307;
use Stick::Publisher::Publish 0.307;
use Moose::Util::TypeConstraints qw(role_type);
require Stick::Role::Routable::AutoInstance;
Stick::Role::Routable::AutoInstance->VERSION(0.307);
require Stick::Role::HasCollection;
Stick::Role::HasCollection->VERSION(0.308); # ppack + subcol

_generate_subcomponent_methods(qw(consumer discount credit debit));
_generate_chargecollection_methods(qw(invoice journal));

with(
  'Moonpig::Role::HasGuid' => { -excludes => 'ident' },
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::Dunner',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::HasCollection' => {
    item => 'debit',
    # These are only here because we use the debit collection for collection
    # tests
    collection_roles => [ 'Stick::Role::Collection::Pageable',
                          'Moonpig::Role::Collection::DebitExtras',
                          'Stick::Role::Collection::Mutable',
                         ],
  },
  'Stick::Role::HasCollection' => {
    item => 'consumer',
    collection_roles => [ 'Moonpig::Role::Collection::ConsumerExtras',
                          'Stick::Role::Collection::Mutable',
                          'Stick::Role::Collection::CanFilter',
                        ]
  },
  'Stick::Role::HasCollection' => {
    item => 'credit',
    collection_roles => [ 'Moonpig::Role::Collection::CreditExtras',
                          'Stick::Role::Collection::Mutable',
                          'Stick::Role::Collection::CanFilter',
                         ],
  },
  'Stick::Role::HasCollection' => {
    item => 'invoice',
    collection_roles => [ 'Moonpig::Role::Collection::InvoiceExtras',
                          'Stick::Role::Collection::CanFilter',
                          ],
    is => 'ro',
  },
  'Stick::Role::HasCollection' => {
    item => 'discount',
    collection_roles => [
      'Moonpig::Role::Collection::DiscountExtras',
      'Stick::Role::Collection::Mutable',
    ],
  },
  'Stick::Role::HasCollection' => {
    item => 'journal',
    is => 'ro',
    collection_roles => [
      'Stick::Role::Collection::Sortable',
    ],
  },
  'Stick::Role::HasCollection' => {
    item => 'job',
    is => 'ro',
   },
  'Stick::Role::PublicResource::GetSelf',
);

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef HashRef Str Int);

use Moonpig;
use Moonpig::Ledger::Accountant;
use Moonpig::Events::Handler::Method;
use Moonpig::Events::Handler::Missing;
use Moonpig::Types qw(
  Credit Consumer EmailAddresses GUID XID NonBlankLine
  TimeInterval
);

use Moonpig::Logger '$Logger';
use Moonpig::MKits;
use Moonpig::Util qw(class event random_short_ident sumof years);
use Stick::Util qw(ppack);

use Data::GUID qw(guid_string);
use List::AllUtils qw(part max);
use Scalar::Util qw(weaken);

use Moonpig::Behavior::EventHandlers;
use Moonpig::Behavior::Packable;
use Sub::Install ();

use namespace::autoclean;

has entity_id => (
  is      => 'rw',
  isa     => Str,
  default => 0,
);

has short_ident => (
  isa    => NonBlankLine,
  reader => 'short_ident',
  writer => 'set_short_ident',
  predicate => 'has_short_ident',
);

sub ident {
  return $_[0]->short_ident if $_[0]->has_short_ident;
  return $_[0]->Moonpig::Role::HasGuid::ident;
}

# Should this be plural?  Or what?  Maybe it's a ContactManager subsystem...
# https://trac.pobox.com/wiki/Billing/DB says that there is *one* contact which
# has *one* address and *one* name but possibly many email addresses.
# -- rjbs, 2010-10-12
has contact_history => (
  is   => 'ro',
  isa  => ArrayRef[ role_type( 'Moonpig::Role::Contact' ) ],
  required => 1,
  traits   => [ 'Array' ],
  handles  => {
    contact         => [ get => -1 ],
    replace_contact => 'push',
  },
);

publish _replace_contact => {
  -path        => 'contact',
  -http_method => 'put',
  attributes   => HashRef,
} => sub {
  my ($self, $arg) = @_;
  my $contact = class('Contact')->new($arg->{attributes});
  $self->replace_contact($contact);

  return $contact;
};

# We can't just use "publish_is" on the contact_history attr, because it's an
# array. -- rjbs, 2011-11-18
publish _get_contact => {
  -path        => 'contact',
  -http_method => 'get',
} => sub {
  my ($self) = @_;
  return $self->contact;
};

around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;
  my $args = @_ == 1 ? $_[0] : { @_ };
  if ($args->{contact} and not $args->{contact_history}) {
    $args->{contact_history} = [ delete $args->{contact} ];
  }
  return $class->$orig($args);
};

has accountant => (
  isa => 'Moonpig::Ledger::Accountant',
  is => 'ro',
  handles => [ qw(create_transfer delete_transfer) ],
  lazy => 1, # avoid initializing this before $self->guid is set 20110202 MJD
  default => sub { Moonpig::Ledger::Accountant->for_ledger($_[0]) },
);

# Convenience method for generating standard transfers
sub transfer {
  my ($self, $args) = @_;
  ($args->{type} ||= 'transfer') eq 'transfer'
    or croak(ref($self) . "::transfer only makes standard-type transfers");
  return $self->accountant->create_transfer($args);
}

sub _extra_instance_subroute {
  my ($self, $path, $npr) = @_;
  my ($first) = @$path;
  my %x_rt = (
    consumers => $self->consumer_collection,
    credits   => $self->credit_collection,
    invoices  => $self->invoice_collection,
    jobs      => $self->job_collection,
    journals  => $self->journal_collection,
    debits    => $self->debit_collection,
  );
  if (exists $x_rt{$first}) {
    shift @$path;
    return $x_rt{$first};
  }
  return;
}

# Compile-time generation of accessors for subcomponents such as debits
sub _generate_subcomponent_methods {
  for my $thing (@_) {
    my $predicate = "_has_$thing";
    my $setter = "_set_$thing";
    my $things = $thing . "s";

    has $thing => (
      reader   => "_${thing}s",
      isa      => HashRef[ role_type('Moonpig::Role::' . ucfirst $thing) ],
      default  => sub { {} },
      traits   => [ qw(Hash) ],
      init_arg => undef,
      handles  => {
        $things       => 'values',
        "_has_$thing" => 'exists',
        "_set_$thing" => 'set',
        "_get_$thing" => 'get',
      },
     );

    Sub::Install::install_sub({
      as   => "$thing\_array",
      code => sub {
        my ($self) = @_;
        return [ $self->$things() ];
      },
    });

    my $add_thing = "add_$thing";
    my $add_this_thing = "add_this_$thing";

    Sub::Install::install_sub({
      as   => $add_thing,
      code => sub {
        my ($self, $class, $arg) = @_;
        $arg ||= {};

        local $arg->{ledger} = $self;

        my $value = $class->new($arg);

        $self->$add_this_thing($value);

        $Logger->log([ 'added %s to %s', $value->ident, $self->ident ]);

        $value->handle_event(event('created'));

        return $value;
      },
    });

    Sub::Install::install_sub({
      as   => $add_this_thing,
      code => sub {
        my ($self, $thing) = @_;
        confess "Can only add this $thing to its own ledger"
          unless $thing->ledger->guid eq $self->guid;

        confess sprintf "%s with guid %s already present", $thing, $thing->guid
          if $self->$predicate($thing->guid);

        $self->$setter($thing->guid, $thing);

        return $thing;
      },
    });
  }
}

sub add_consumer_from_template {
  my ($self, $template, $arg) = @_;
  $arg ||= {};

  $template = Moonpig->env->consumer_template($template)
    unless ref $template;

  Moonpig::X->throw("unknown consumer template") unless $template;

  my $template_roles = $template->{roles} || [];
  my $template_class = $template->{class};
  my $template_arg   = $template->{arg}   || {};

  Moonpig::X->throw("consumer template supplied class and roles")
    if @$template_roles and $template_class;

  $self->add_consumer(
    ($template_class || class(qw(Consumer), @$template_roles)),
    {
      %$template_arg,
      %$arg,
    },
  );
}

# normally used only as part of ->quote_for_.*_service
# $kind is either { template => $template_name } or { class => $class_name }
sub _add_consumer_chain {
  my ($self, $kind, $arg, $chain_duration) = @_;
  my $consumer;
  if (exists $kind->{template}) {
    $consumer = $self->add_consumer_from_template($kind->{template}, $arg);
  } elsif (exists $kind->{class}) {
    $consumer = $self->add_consumer($kind->{class}, $arg);
  } else {
    confess "Unexpected 'kind' argument '$kind' to Ledger::_add_consumer_chain";
  }

  $consumer->_adjust_replacement_chain(
    $chain_duration - $consumer->estimated_lifetime, 1
  );

  return ($consumer, $consumer->replacement_chain);
}

# $kind is either { template => $template_name } or { class => $class_name }
sub quote_for_new_service {
  my ($self, $kind, $arg, $chain_duration) = @_;
  $self->start_quote;
  # XXX What if an exception is thrown before the quote is ended?
  # Couldn't that leave the ledger with an open quote?
  my @chain = $self->_add_consumer_chain($kind, $arg, $chain_duration);
  my $quote = $self->end_quote($chain[0]);
  return $quote;
}

sub quote_for_extended_service {
  my ($self, $xid, $chain_duration) = @_;
  my $active_consumer = $self->active_consumer_for_xid($xid)
    or confess "No active service for '$xid' to extend";
  $self->start_quote;

  my $end_consumer = $active_consumer->replacement_chain_end;

  my $chain_head;

  if ($end_consumer->can('_custom_quote_for_extended_service')) {
    $chain_head = $end_consumer->_custom_quote_for_extended_service(
      $chain_duration
    );
  } else {
    # If the endpoint has not been paid-for yet, then it's part of the 5 you
    # have to buy start counting with it.  -- rjbs, 2012-06-20
    my $start_depth = 0;
    $start_depth++ if ! grep {; $_->is_paid } $end_consumer->relevant_invoices;

    Moonpig::X->throw("consumer for '$xid' could not build a replacement")
      unless $chain_head = $end_consumer->build_replacement();

    $chain_duration -= $chain_head->estimated_lifetime;
    my @chain = $chain_head->_adjust_replacement_chain(
      $chain_duration,
      $start_depth + 1, # +1 because we made the $chain_head by hand; count it!
    );
  }

  my $quote = $self->end_quote($chain_head);
  return $quote;
}

sub start_quote {
  my ($self, $quote_args) = @_;
  $quote_args //= {};
  if ($self->has_current_invoice) {
    my $invoice = $self->current_invoice;
    $invoice->mark_closed; # XXX someone should garbage-collect chargeless invoices
  }
  return $self->current_invoice(class("Invoice::Quote"), $quote_args);
}

sub end_quote {
  my ($self, $first_consumer) = @_;
  my $quote = $self->current_invoice; # XXX someone should garbage-collect chargeless quotes
  $quote->record_first_consumer($first_consumer);
  $quote->mark_closed;
  return $quote;
}

sub find_old_psync_quotes {
  my ($self, $xid) = @_;
  my @q = grep { ! $_->is_abandoned && ! $_->is_executed &&
                   $_->is_psync_quote && $_->psync_for_xid eq $xid }
    $self->quotes;
  return @q;
}

# Compile-time generation of accessors for invoice and journal subcomponents
sub _generate_chargecollection_methods {
  for my $thing (qw(journal invoice)) {
    my $role          = sprintf "Moonpig::Role::%s", ucfirst $thing;
    my $default_class = class(ucfirst $thing);
    my $things        = "${thing}s";
    my $reader        = "_$things";
    my $push          = "_push_$thing";

    has $things => (
      reader  => $reader,
      isa     => ArrayRef[ role_type($role) ],
      default => sub { [] },
      traits  => [ qw(Array) ],
      handles => {
        $things => 'elements',
        $push   => 'push',
      },
    );

    my $_has_current_thing = sub {
      my ($self) = @_;
      my $things = $self->$reader;
      @$things and $things->[-1]->is_open;
    };

    my $has_current_thing = "has_current_$thing";
    Sub::Install::install_sub({
      as   => $has_current_thing,
      code => $_has_current_thing,
    });

    my $_ensure_one_thing = sub {
      my ($self, $class, $args) = @_;
      $args //= {};

      $class ||= $default_class;
      my $things = $self->$reader;
      return if $self->$has_current_thing;

      Class::Load::load_class($class);

      my $thing = $class->new({
        ledger => $self,
        %$args,
      });

      $self->$push($thing);
      return;
    };

    Sub::Install::install_sub({
      as   => "current_$thing",
      code => sub {
        my ($self, $class, $args) = @_;
        $self->$_ensure_one_thing($class, $args);
        $self->$reader->[-1];
      }
    });

    Sub::Install::install_sub({
      as   => "$thing\_array",
      code => sub { [ $_[0]->$things ] },
    });
  }
}

has _invoice_ident_registry => (
  is       => 'ro',
  isa      => HashRef,
  default  => sub {  {}  },
  init_arg => undef,
);

before _push_invoice => sub {
  my ($self, $invoice) = @_;
  my $guid = $invoice->guid;
  my $reg  = $self->_invoice_ident_registry;

  Moonpig::X->throw("invoice ident already registered")
    if exists $self->_invoice_ident_registry->{ $guid };

  my %in_use = map {; $_ => 1 } values %$reg;
  my $ident  = 'I-' . random_short_ident(1e6);
  $ident = 'I-' . random_short_ident(1e6) until ! $in_use{ $ident };

  $reg->{ $guid } = $ident;
};

sub latest_invoice {
  my ($self) = @_;
  my $latest = (
    sort { $b->created_at <=> $a->created_at
        || $b->guid       cmp $a->guid # incredibly unlikely, but let's plan
         } $self->invoices_without_quotes
  )[0];

  return $latest;
}

sub payable_invoices {
  my ($self) = @_;
  grep {; $_->is_payable } $self->invoices;
}

sub invoices_without_quotes {
  my ($self) = @_;
  grep {; ! $_->is_quote } $self->invoices;
}

sub quotes {
  my ($self) = @_;
  grep {; $_->is_quote } $self->invoices;
}

sub amount_earmarked {
  my ($self) = @_;
  my @invoices = grep { $_->is_paid } $self->invoices_without_quotes;
  my @charges  = grep {
                    ! ($_->does('Moonpig::Role::LineItem::Abandonable')
                       && $_->is_abandoned)
                   && ($_->can('is_executed') && ! $_->is_executed)
                 }
                 map  { $_->all_charges } @invoices;

  return sumof { $_->amount } @charges;
}

sub amount_available {
  my ($self) = @_;
  my $total = $self->amount_unapplied;
  my $earmarked_amount = $self->amount_earmarked;

  return max(0, $total - $earmarked_amount);
}

publish amount_due => { } => sub {
  my ($self) = @_;

  my $due   = (sumof { $_->total_amount } $self->payable_invoices)
            + $self->amount_overearmarked;
  my $avail = $self->amount_available;

  return 0 if $avail >= $due;
  return abs($due - $avail);
};

sub amount_unapplied {
  my ($self) = @_;
  return sumof { $_->unapplied_amount } $self->credits;
}

sub process_credits {
  my ($self) = @_;

  $self->_collect_spare_change;

  my @credits = $self->credits;

  for my $invoice (
    sort { $a->created_at <=> $b->created_at } $self->payable_invoices
  ) {
    last if $invoice->total_amount > $self->amount_available;

    $invoice->mark_paid;
    $invoice->handle_event(event('paid'));
  }
}

sub destroy_credits__ {
  my ($self, @credits) = @_;
  for my $c (@credits) {
    delete $self->_credits->{$c->guid};
  }
}

implicit_event_handlers {
  return {
    'heartbeat' => {
      redistribute => Moonpig::Events::Handler::Method->new('_reheartbeat'),
      spare_change => Moonpig::Events::Handler::Method->new('_collect_spare_change'),
    },

    'send-mkit' => {
      default => Moonpig::Events::Handler::Method->new('_send_mkit'),
    },

    'contact-humans' => {
      default => Moonpig::Events::Handler::Missing->new,
    },
  };
};

sub _reheartbeat {
  my ($self, $event) = @_;

  for my $target (
    # $self->contact,
    $self->consumers,
    $self->invoices,
    $self->journals,
  ) {
    next if $target->does('Moonpig::Role::CanExpire') and $target->is_expired;
    $target->handle_event($event);
  }

  $self->perform_dunning;
}

sub amount_overearmarked {
  my ($self) = @_;
  my $earmarked = $self->amount_earmarked;
  my $unapplied = $self->amount_unapplied;
  return 0 if $unapplied >= $earmarked;
  return $earmarked - $unapplied;
}

sub _send_mkit {
  my ($self, $event, $arg) = @_;

  my $to   = $event->payload->{envelope_recipients} // [ $self->contact->email_addresses ];
  my $from = $event->payload->{envelope_sender} // Moonpig->env->from_email_address_mailbox;

  my $email = Moonpig->env->mkits->assemble_kit(
    $event->payload->{kit},
    $event->payload->{arg},
  );

  {
    state $counter = 0;
    # Do not get the Foo<1>-form ident during testing!  It isn't valid.
    # -- rjbs, 2012-05-02
    my $ident = $self->has_short_ident ? $self->short_ident : $self->guid;
    $email->header_set('Message-ID' =>
      Email::MessageID->new(
        user => join(q{.}, $ident, $$, time, $counter++),
        host => hostname_long(),
      )->in_brackets,
    );
  }

  $self->queue_email($email, { to => $to, from => $from });
}

sub send_receipt {
  my ($self, $arg) = @_;
  my $credit   = $arg->{credit};
  my $invoices = $arg->{invoices};

  $self->handle_event(event('send-mkit', {
    kit => 'receipt',
    arg => {
      subject => "Payment received",

      to_addresses => [ $self->contact->email_addresses ],
      credit       => $credit,
      ledger       => $self,
      invoices     => [
        sort { $a->created_at <=> $b->created_at } @$invoices
      ],
    },
  }));
}

# {
#   xid => [ consumer_guid, ... ],
#   ...
# }
has _active_xid_consumers => (
  is  => 'ro',
  isa => HashRef,
  init_arg => undef,
  default  => sub {  {}  },
  traits   => [ 'Hash' ],
  handles  => {
    active_xids => 'keys',
    _active_consumer_guids => 'values',
  },
);

sub active_consumers {
  my ($self) = @_;
  return map { $self->_get_consumer($_) } $self->_active_consumer_guids;
}

sub active_consumer_for_xid {
  my ($self, $xid) = @_;

  my $reg = $self->_active_xid_consumers;
  return unless my $guid = $reg->{ $xid };

  my $consumer = $self->_get_consumer($guid);

  Consumer->assert_valid($consumer);

  return $consumer;
}

sub _is_consumer_active {
  my ($self, $consumer) = @_;

  my $reg = $self->_active_xid_consumers;
  return unless my $guid = $reg->{ $consumer->xid };
  return $guid eq $consumer->guid;
}

sub mark_consumer_active__ {
  my ($self, $consumer) = @_;

  my $reg = $self->_active_xid_consumers;
  my $xid = $consumer->xid;

  if (my $guid = $reg->{ $consumer->xid }) {
    return if $guid eq $consumer->guid;
    Moonpig::X->throw("cannot activate for already-handled xid");
  }

  $reg->{ $xid } = $consumer->guid;

  return;
}

sub mark_consumer_inactive__ {
  my ($self, $consumer) = @_;

  my $reg = $self->_active_xid_consumers;
  my $xid = $consumer->xid;

  return unless $reg->{ $xid } and $reg->{ $xid } eq $consumer->guid;

  my $rv = delete($reg->{ $xid }) ? 1 : 0;

  return $rv;
}

sub failover_active_consumer__ {
  my ($self, $consumer) = @_;

  my $reg = $self->_active_xid_consumers;

  $reg->{ $consumer->xid } ||= {};

  Moonpig::X->throw("can't failover inactive service")
    unless $self->mark_consumer_inactive__($consumer);

  $consumer->replacement->become_active;

  return;
}

sub _collect_spare_change {
  my ($self) = @_;

  my @unexpired_consumers =
    grep {; ! $_->is_expired && ! $_->is_canceled }
    $self->consumers;

  my %consider  = map  {; $_->[0]->guid => $_ }
                  grep {; $_->[1] > 0 }
                  map  {; [ $_, $_->unapplied_amount ] }
                  $self->consumers;

  delete $consider{ $_->guid } for @unexpired_consumers;

  my $min_to_collect = Moonpig->env->minimum_spare_change_amount;
  for my $pair (values %consider) {
    my ($consumer, $unapplied_amount) = @$pair;

    my $min = $consumer->can('minimum_spare_change_amount')
            ? $consumer->minimum_spare_change_amount
            : $min_to_collect;

    if ($unapplied_amount >= $min) {
      $consumer->cashout_unapplied_amount;
    } else {
      $self->create_transfer({
        type => 'transfer',
        from   => $consumer,
        to     => $self->current_journal,
        amount => $unapplied_amount,
      });
    }
  }
}

sub _class_subroute {
  my ($class, $path) = @_;

  if ($path->[0] eq 'by-xid') {
    my (undef, $xid) = splice @$path, 0, 2;
    return Moonpig->env->storage->retrieve_ledger_unambiguous_for_xid($xid);
  }

  if ($path->[0] eq 'by-guid') {
    my (undef, $guid) = splice @$path, 0, 2;
    return Moonpig->env->storage->retrieve_ledger_for_guid($guid);
  }

  if ($path->[0] eq 'by-ident') {
    my (undef, $ident) = splice @$path, 0, 2;
    return Moonpig->env->storage->retrieve_ledger_for_ident($ident);
  }

  return;
}

# This method is here only as a favor to the router test, which can be adapted
# to query other published methods once we *have some*. -- rjbs, 2011-02-23
publish published_guid => { -path => 'gguid' } => sub {
  my ($self) = @_;
  return $self->guid;
};

publish heartbeat => { -http_method => 'post', -path => 'heartbeat' } => sub {
  my ($self) = @_;
  $self->handle_event( event('heartbeat') );
};

# hand off responsibility for this xid to the target ledger
publish move_xid_to => { -http_method => 'post', -path => 'handoff',
                         target_ledger => GUID, xid => XID } => sub {
  my ($self, $args) = @_;
  my ($xid, $guid) = @{$args}{qw(xid target_ledger)};
  my $target = Moonpig->env->storage->retrieve_ledger_for_guid($guid)
    or croak "Can't find any ledger for guid $guid";
  my $cons = $self->active_consumer_for_xid($xid)
    or croak sprintf "Ledger %s has no active consumer for xid '%s'",
      $self->guid, $xid;
  my $new_consumer = $cons->copy_to($target);
  $_->save for $self, $target;
  return $new_consumer;
};

# hand off responsibility for this xid to a fresh ledger
publish split_xid => { -http_method => 'post', -path => 'split',
                       xid => XID,
                       contact => HashRef,
                     } => sub {
  my ($self, $arg) = @_;

  my ($xid) = $arg->{xid};
  my $cons = $self->active_consumer_for_xid($xid)
    or croak sprintf "Ledger %s has no active consumer for xid '%s'",
      $self->guid, $xid;

  return Moonpig->env->storage->do_rw(
    sub {
      my $contact = class('Contact')->new($arg->{contact});
      my $target = class('Ledger')->new({ contact => $contact })->save;

      my $new_cons = $cons->copy_to($target);
      $_->save for $self, $target;
      return $new_cons;
    });
};

sub queue_email {
  my ($self, $email, $env) = @_;

  Moonpig::X->throw("can't queue non-Email::Simple object")
    unless $email->isa('Email::Simple');

  $self->queue_job('send-email', {
    email => $email->as_string,
    env   => Moonpig::Util::json()->encode($env),
  });
}

sub queue_job {
  my ($self, $type, $payloads) = @_;

  Moonpig->env->storage->queue_job(
    $self,
    {
      type        => $type,
      payloads    => $payloads,
    },
  );
}

sub job_array {
  Moonpig->env->storage->undone_jobs_for_ledger($_[0]);
}

sub prepare_to_be_saved {
  my ($self) = @_;

  Moonpig::X->throw("can't save a ledger with open quote as current invoice")
    if $self->has_current_invoice and $self->current_invoice->is_quote;

  $_->_clear_event_handler_registry for ($self, $self->consumers);
}

sub save {
  my ($self) = @_;
  Moonpig->env->storage->save_ledger($self);
  return $self;
}

publish estimate_cost_for_interval => { interval => TimeInterval } => sub {
  my ($self, $arg) = @_;
  my $interval = $arg->{interval};

  # XXX this function should fail when it sees a consumer without its
  # own cost estimation method, rather than ignoring it.
  # It's this way as a temporary fallback so that ledgers can give a
  # cost estimate during the transition period from pybill to moonpig.
  # 2012-02-21 mjd
  return sumof { $_->estimate_cost_for_interval({ interval => $interval }) }
    grep $_->can("estimate_cost_for_interval"), # XXX
      grep $_->is_active, $self->consumer_collection->all;
};

publish invoice_history_events => {
  -path => 'invoice-history-events',
} => sub {
  my ($self) = @_;

  my @events;
  for my $invoice (
    grep {; $_->is_closed && ! $_->is_abandoned } $self->invoices
  ) {
    push @events, {
      event  => 'invoice.invoiced',
      date   => $invoice->closed_at,
      guid   => $invoice->guid,
      ident  => $invoice->ident,
      amount => $invoice->total_amount,
    };

    if ($invoice->is_paid) {
      push @events, {
        event => 'invoice.paid',
        date  => $invoice->paid_at,
        guid  => $invoice->guid,
        ident => $invoice->ident,
      };
    }
  }

  for my $credit ($self->credits) {
    push @events, {
      event  => 'credit.paid',
      date   => $credit->created_at,
      guid   => $credit->guid,
      amount => $credit->amount,
      credit_type => $credit->type,
    };
  }

  # XXX: A bit gross: -- rjbs, 2012-10-16
  for my $dunning (@{ $self->_dunning_history }) {
    push @events, {
      event  => 'dunning',
      date   => $dunning->{dunned_at},
      guid   => $dunning->{dunning_guid},
      amount => $dunning->{amount_due},
      xid_info => $dunning->{xid_info},
      invoice_guids => $dunning->{invoice_guids},
    };
  }

  # the cmp fallback gets credits before invoice payment, which will make
  # better display sense, even if the two things are within 1 second and 1
  # transaction -- rjbs, 2012-10-08
  state $cmp = Sort::ByExample->cmp([
    qw(invoice.invoiced dunning credit.paid invoice.paid)
  ]);
  @events = sort { $a->{date} <=> $b->{date}
                || $cmp->($a->{event}, $b->{event}) } @events;

  return {
    items => \@events
  };
};

PARTIAL_PACK {
  my ($self) = @_;

  return {
    ident   => $self->ident,
    contact => ppack($self->contact),
    credits => ppack($self->credit_collection),
    jobs    => ppack($self->job_collection),

    amount_due       => $self->amount_due,
    amount_available => $self->amount_available,
    unpaid_invoices  => ppack($self->invoice_collection->payable),
    discounts        => ppack($self->discount_collection),

    active_xids => {
      map {;
        my $xid = $_; # somewhere downstream of here is a topicalization bug
        $xid => ppack($self->active_consumer_for_xid($xid))
      } $self->active_xids
    },
    yearly_cost_estimate => $self->estimate_cost_for_interval({
      interval => years(1),
    }),
  };
};

1;
