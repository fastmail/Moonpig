package Moonpig::Role::Ledger;
# ABSTRACT: the fundamental hub of a billable account

use Carp qw(confess croak);
use Moose::Role;

use Stick::Publisher 0.307;
use Stick::Publisher::Publish 0.307;
use Moose::Util::TypeConstraints qw(role_type);
require Stick::Role::Routable::AutoInstance;
Stick::Role::Routable::AutoInstance->VERSION(0.307);
require Stick::Role::HasCollection;
Stick::Role::HasCollection->VERSION(0.307);

_generate_subcomponent_methods(qw(consumer debit credit coupon));

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
    item => 'journal',
    is => 'ro',
  },
  'Stick::Role::HasCollection' => {
    item => 'coupon',
    collection_roles => [ ],
  },
  'Stick::Role::HasCollection' => {
    item => 'job',
    is => 'ro',
   },
  'Stick::Role::PublicResource::GetSelf',
);

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(ArrayRef HashRef Str);

use Moonpig;
use Moonpig::Ledger::Accountant;
use Moonpig::Events::Handler::Method;
use Moonpig::Events::Handler::Missing;
use Moonpig::Types qw(Credit Consumer EmailAddresses GUID XID NonBlankLine);

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
    coupons   => $self->coupon_collection,
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

sub add_consumer_chain {
  my ($self, $class, $arg, $chain_length) = @_;
  my $consumer = $self->add_consumer($class, $arg);
  $consumer->_adjust_replacement_chain($chain_length - $consumer->estimated_lifetime);
  return ($consumer, $consumer->replacement_chain);
}

sub add_consumer_chain_from_template {
  my ($self, $template, $arg, $chain_length) = @_;
  my $consumer = $self->add_consumer_from_template($template, $arg);
  $consumer->_adjust_replacement_chain($chain_length - $consumer->estimated_lifetime);
  return ($consumer, $consumer->replacement_chain);
}

for my $thing (qw(journal invoice)) {
  my $role   = sprintf "Moonpig::Role::%s", ucfirst $thing;
  my $class  = class(ucfirst $thing);
  my $things = "${thing}s";
  my $reader = "_$things";
  my $push   = "_push_$thing";

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

  my $_ensure_one_thing = sub {
    my ($self) = @_;

    my $things = $self->$reader;
    return if @$things and $things->[-1]->is_open;

    Class::MOP::load_class($class);

    my $thing = $class->new({
      ledger => $self,
    });

    $self->$push($thing);
    return;
  };

  Sub::Install::install_sub({
    as   => "current_$thing",
    code => sub {
      my ($self) = @_;
      $self->$_ensure_one_thing;
      $self->$reader->[-1];
    }
  });
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
         } $self->invoices
  )[0];

  return $latest;
}

sub invoice_array {
  [ $_[0]->invoices ]
}

sub journal_array {
  [ $_[0]->invoices ]
}

sub payable_invoices {
  my ($self) = @_;
  grep {; $_->is_payable } $self->invoices;
}

sub abandon_invoice {
  my ($self, $invoice) = @_;

  return $invoice->abandon_with_replacement($self->current_invoice);
}

sub amount_earmarked {
  my ($self) = @_;
  my @invoices = grep { $_->is_paid } $self->invoices;
  my @charges  = grep { ! $_->is_executed }
                 map  { $_->all_charges } @invoices;

  return sumof { $_->amount } @charges;
}

sub amount_available {
  my ($self) = @_;
  my $total = sumof { $_->unapplied_amount } $self->credits;
  my $earmarked_amount = $self->amount_earmarked;

  return max(0, $total - $earmarked_amount);
}

sub amount_due {
  my ($self) = @_;

  my $due   = sumof { $_->total_amount } $self->payable_invoices;
  my $avail = $self->amount_available;

  return 0 if $avail >= $due;
  return abs($due - $avail);
}

sub process_credits {
  my ($self) = @_;

  $self->_collect_spare_change;

  my @credits = $self->credits;

  my $available = $self->amount_available;

  for my $invoice (
    sort { $a->created_at <=> $b->created_at } $self->payable_invoices
  ) {
    {
      # XXX: We broke coupons and have yet to repair them.
      my @coupon_apps = $self->find_coupon_applications__($invoice);
      my @coupon_credits = map $_->{coupon}->create_discount_for($_->{charge}),
        @coupon_apps;
      Moonpig::X->throw("coupon support is broken") if @coupon_apps;
    }

    last if $invoice->total_amount > $available;

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

# Given an invoice, find all outstanding coupons that apply to its charges
# return a list of { coupon => $coupon, charge => $charge } items indicating
# which coupons apply to which charges
sub find_coupon_applications__ {
  my ($self, $invoice) = @_;
  my @coupons = $self->coupons;
  my @res;
  for my $coupon ($self->coupons) {
    push @res, map { coupon => $coupon, charge => $_ }, $coupon->applies_to_invoice($invoice);
  }
  return @res;
}

implicit_event_handlers {
  return {
    'heartbeat' => {
      redistribute => Moonpig::Events::Handler::Method->new('_reheartbeat'),
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

sub _send_mkit {
  my ($self, $event, $arg) = @_;

  my $to   = [ $self->contact->email_addresses ];
  my $from = Moonpig->env->from_email_address_mailbox;

  my $email = Moonpig->env->mkits->assemble_kit(
    $event->payload->{kit},
    $event->payload->{arg},
  );

  $self->queue_email($email, { to => $to, from => $from });
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
    xids_handled     => 'keys',
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

  my @consumers =
    grep {; $_->does('Moonpig::Role::Consumer') && ! $_->is_expired }
    $self->consumers;

  my %consider  = map  {; $_->[0]->guid => $_ }
                  grep {; $_->[1] }
                  map  {; [ $_, $_->unapplied_amount ] }
                  $self->consumers;

  delete $consider{ $_->guid } for @consumers;

  $_->cashout_unapplied_amount for map { $_->[0] } values %consider;
}

sub _class_subroute {
  my ($class, $path) = @_;

  if ($path->[0] eq 'by-xid') {
    my (undef, $xid) = splice @$path, 0, 2;
    return Moonpig->env->storage->retrieve_ledger_for_xid($xid);
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
    env   => JSON->new->ascii->encode($env),
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

sub save {
  my ($self) = @_;
  Moonpig->env->storage->save_ledger($self);
  return $self;
}

sub estimate_cost_for_interval {
  my ($self, $period) = @_;

  # XXX this function should fail when it sees a consumer without its
  # own cost estimation method, rather than ignoring it.
  # It's this way as a temporary fallback so that ledgers can give a
  # cost estimate during the transition period from pybill to moonpig.
  # 2012-02-21 mjd
  return sumof {$_->estimate_cost_for_interval($period)}
    grep $_->can("estimate_cost_for_interval"), # XXX
      grep $_->is_active, $self->consumer_collection->all;
}

PARTIAL_PACK {
  my ($self) = @_;

  return {
    ident   => $self->ident,
    contact => ppack($self->contact),
    credits => ppack($self->credit_collection),
    jobs    => ppack($self->job_collection),

    unpaid_invoices => {
      items => [
        map { ppack($_) } grep { $_->is_unpaid && ! $_->is_abandoned } $self->invoices
      ],
    },
    active_xids => {
      map {; $_ => ppack($self->active_consumer_for_xid($_)) }
        $self->xids_handled
    },
    yearly_cost_estimate => $self->estimate_cost_for_interval(years(1)),
  };
};

1;
