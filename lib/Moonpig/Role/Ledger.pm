package Moonpig::Role::Ledger;
# ABSTRACT: the fundamental hub of a billable account

use Carp qw(confess croak);
use Moose::Role;
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110324;
use Moose::Util::TypeConstraints qw(role_type);
require Stick::Role::Routable::AutoInstance;
Stick::Role::Routable::AutoInstance->VERSION(0.20110401);
require Stick::Role::HasCollection;
Stick::Role::HasCollection->VERSION(0.20110802);

_generate_subcomponent_methods(qw(bank consumer refund credit coupon));

with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::Dunner',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::HasCollection' => {
    item => 'refund',
    # These are only because we use the refund collection for collection tests
    collection_roles => [ [ 'Stick::Role::Collection::Sortable' => "Sortable" =>
                              { default_sort_key => 'guid' } ],
                          'Stick::Role::Collection::Pageable',
                          'Moonpig::Role::Collection::RefundExtras',
                          'Stick::Role::Collection::Mutable',
                         ],
  },
  'Stick::Role::HasCollection' => {
    item => 'consumer',
    collection_roles => [ 'Moonpig::Role::Collection::ConsumerExtras',
                          [ 'Stick::Role::Collection::Mutable' => "Mutable" =>
                              { add_this_item => 'add_from_template',
                              } ] ],
  },
  'Stick::Role::HasCollection' => {
    item => 'bank',
  # These are only because we use the refund collection for collection tests
    collection__roles => [ 'Stick::Role::Collection::Pageable' ],
  },
  'Stick::Role::HasCollection' => {
    item => 'credit',
    collection_roles => [ 'Moonpig::Role::Collection::CreditExtras' ],
    post_action => 'add_credit',
  },
  'Stick::Role::HasCollection' => {
    item => 'invoice',
    collection_roles => [ 'Moonpig::Role::Collection::InvoiceExtras' ],
    default_sort_key => 'created_at',
    is => 'ro',
  },
  'Stick::Role::HasCollection' => {
    item => 'journal',
    default_sort_key => 'created_at',
    is => 'ro',
  },
  'Stick::Role::HasCollection' => {
    item => 'coupon',
    collection_roles => [ ],
    default_sort_key => 'created_at',
  },
  'Stick::Role::HasCollection' => {
    item => 'job',
    is => 'ro',
   },
  'Stick::Role::PublicResource::GetSelf',
);

use Moose::Util::TypeConstraints;
use MooseX::SetOnce;
use MooseX::Types::Moose qw(ArrayRef HashRef Str);

use Moonpig;
use Moonpig::Ledger::Accountant;
use Moonpig::Events::Handler::Method;
use Moonpig::Events::Handler::Missing;
use Moonpig::Types qw(Credit Consumer EmailAddresses GUID XID);

use Moonpig::Logger '$Logger';
use Moonpig::MKits;
use Moonpig::Util qw(class event sum);
use Stick::Util qw(ppack);

use Data::GUID qw(guid_string);
use Scalar::Util qw(weaken);

use Moonpig::Behavior::EventHandlers;
use Moonpig::Behavior::Packable;
use Sub::Install ();

use Moonpig::Context -all, '$Context';

use namespace::autoclean;

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

# XXX: This should be a submethod.  And not totally bogus.  -- rjbs, 2011-08-15
sub BUILDARGS {
  my ($self, $hashref) = @_;

  if ($hashref->{contact} and not $hashref->{contact_history}) {
    $hashref->{contact_history} = [ delete $hashref->{contact} ];
  }

  return $hashref;
}

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
    banks     => $self->bank_collection,
    consumers => $self->consumer_collection,
    coupons   => $self->coupon_collection,
    credits   => $self->credit_collection,
    invoices  => $self->invoice_collection,
    jobs      => $self->job_collection,
    journals  => $self->journal_collection,
    refunds   => $self->refund_collection,
  );
  if (exists $x_rt{$first}) {
    shift @$path;
    return $x_rt{$first};
  }
  return;
}

# Compile-time generation of accessors for subcomponents such as
# banks and refunds
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
        warn "# thing = $thing\n";
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

  # XXX: sloppy; we should make a template class and a coercion
  # -- rjbs, 2011-02-09
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

for my $thing (qw(journal invoice)) {
  my $role   = sprintf "Moonpig::Role::%s", ucfirst $thing;
  my $class  = class(ucfirst $thing);
  my $things = "${thing}s";
  my $reader = "_$things";

  has $things => (
    reader  => $reader,
    isa     => ArrayRef[ role_type($role) ],
    default => sub { [] },
    traits  => [ qw(Array) ],
    handles => {
      $things        => 'elements',
      "_push_$thing" => 'push',
    },
  );

  my $_ensure_one_thing = sub {
    my ($self) = @_;

    my $things = $self->$reader;
    return if @$things and $things->[-1]->is_open;

    Class::MOP::load_class($class);

    my $thing = $class->new({
      ledger      => $self,
    });

    push @$things, $thing;
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
  grep $_->is_unpaid && $_->is_closed, $self->invoices;
}

sub process_credits {
  my ($self) = @_;

  $self->_collect_spare_change;

  my @credits = $self->credits;

  # XXX: These need to be processed in order. -- rjbs, 2010-12-02
  for my $invoice ( $self->payable_invoices ) {

    @credits = grep { $_->unapplied_amount > 0 } @credits;

    my @coupon_apps = $self->find_coupon_applications__($invoice);
    my @coupon_credits = map $_->{coupon}->create_discount_for($_->{charge}), @coupon_apps;

    my $to_pay = $invoice->total_amount;

    my @to_apply;

    # XXX: These need to be processed in order, too. -- rjbs, 2010-12-02
    CREDIT: for my $credit (@coupon_credits, @credits) {
      my $credit_amount = $credit->unapplied_amount;
      my $apply_amt = $credit_amount >= $to_pay ? $to_pay : $credit_amount;

      push @to_apply, {
        credit => $credit,
        amount => $apply_amt,
      };

      $to_pay -= $apply_amt;

      $Logger->log([
        "will apply %s from %s; %s left to pay",
        $apply_amt,
        $credit->ident,
        $to_pay,
      ]);

      last CREDIT if $to_pay == 0;
    }

    if ($to_pay == 0) {
      $self->apply_credits_to_invoice__( \@to_apply, $invoice );
      $_->{coupon}->applied for @coupon_apps;
    } else {
      # We can't successfully pay this invoice, so stop processing.
      $self->destroy_credits__(@coupon_credits);
      return;
    }
  }
}

sub destroy_credits__ {
  my ($self, @credits) = @_;
  for my $c (@credits) {
    delete $self->_credits->{$c->guid};
  }
}

# Given an invoice, find all outstanding coupons that apply to its charges
# return a list of { coupon => $coupon, charge => $charge } items indicating which coupons
# apply to which charges
sub find_coupon_applications__ {
  my ($self, $invoice) = @_;
  my @coupons = $self->coupons;
  my @res;
  for my $coupon ($self->coupons) {
    push @res, map { coupon => $coupon, charge => $_ }, $coupon->applies_to_invoice($invoice);
  }
  return @res;
}

# Only call this if you are paying off the complete invoice!
# $to_apply is an array of { credit => $credit_object, amount => $amount }
# hashes.
sub apply_credits_to_invoice__ {
  my ($self, $to_apply, $invoice) = @_;

  {
    my $total = sum(map $_->{amount}, @$to_apply);
    croak "credit application of $total did not mach invoiced amount of " .
      $invoice->total_amount
        unless $invoice->total_amount == $total;
  }

  for my $application (@$to_apply) {
    $self->create_transfer({
      type   => 'credit_application',
      from   => $application->{credit},
      to     => $invoice,
      amount => $application->{amount},
    });
  }

  $Logger->log([ "marking %s paid", $invoice->ident ]);
  $invoice->handle_event(event('paid'));
  $invoice->mark_paid;
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
    $self->banks,
    $self->consumers,
    $self->invoices,
    $self->journals,
  ) {
    $target->handle_event($event);
  }

  $self->perform_dunning;
}

sub _send_mkit {
  my ($self, $event, $arg) = @_;

  my $to   = [ $self->contact->email_addresses ];
  my $from = Moonpig->env->from_email_address_mailbox;

  my $email = Moonpig::MKits->kit($event->payload->{kit})->assemble(
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
    xids_handled => 'keys',
  },
);

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

  my @consumers = grep {; $_->does('Consumer::ChargesBank') &&
                          $_->has_bank && ! $_->is_expired } $self->consumers;
  my %consider  = map  {; $_->[0]->guid => $_ }
                  grep {; $_->[1] }
                  map  {; [ $_, $_->unapplied_amount ] }
                  $self->banks;

  delete $consider{ $_->bank->guid } for @consumers;

  my $total = sum(map { $_->[1] } values %consider);

  return unless $total > 0;

  my $credit = $self->add_credit(
    class('Credit::SpareChange'),
    {
      amount => $total,
    },
  );

  for my $bank_pair (values %consider) {
    my ($bank, $amount) = @$bank_pair;

    $self->create_transfer({
      type    => 'bank_credit',
      from    => $bank,
      to      => $credit,
      amount  => $amount,
    });
  }
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
  return $cons->copy_to($target);
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
      my $target = class('Ledger')->new({ contact => $contact });

      Moonpig->env->storage->save_ledger($target);
      return $cons->copy_to($target);
    });
};

# XXX: Bogus, we should make this queue like everything else.
sub queue_email {
  my ($self, $email, $env) = @_;

  # XXX: validate email -- rjbs, 2010-12-08
  $self->queue_job('send-email', {
    email => $email->as_string,
    env   => JSON->new->ascii->encode($env),
  });
}

sub queue_job {
  my ($self, $type, $payloads) = @_;

  Moonpig->env->storage->queue_job__({
    ledger   => $self,
    type     => $type,
    payloads => $payloads,
  });
}

sub job_array {
  Moonpig->env->storage->undone_jobs_for_ledger($_[0]);
}

PARTIAL_PACK {
  my ($self) = @_;

  return {
    contact => ppack($self->contact),
    credits => ppack($self->credit_collection),
    jobs    => ppack($self->job_collection),

    open_invoices => {
      items => [
        map { ppack($_) } grep { $_->is_unpaid } $self->invoices
      ],
    },
    active_xids => {
      map {; $_ => ppack($self->active_consumer_for_xid($_)) }
        $self->xids_handled
    },
  };
};

after BUILD => sub {
  $Context->stack->current_frame->add_memorandum($_[0]);
};

1;
