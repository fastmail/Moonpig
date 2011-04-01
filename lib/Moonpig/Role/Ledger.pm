package Moonpig::Role::Ledger;
# ABSTRACT: the fundamental hub of a billable account

use Moose::Role;
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110324;

_generate_subcomponent_methods(qw(bank consumer refund));

with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
  'Moonpig::Role::Dunner',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
  'Moonpig::Role::HasCollections' => {
    item => 'refund',
    item_roles => [ 'Moonpig::Role::Refund' ],
   },
  'Moonpig::Role::HasCollections' => {
    item => 'consumer',
    item_roles => [ 'Moonpig::Role::Consumer' ],
   },
  'Moonpig::Role::HasCollections' => {
    item => 'bank',
    item_roles => [ 'Moonpig::Role::Bank' ],
   },
  'Stick::Role::PublicResource::GetSelf',
);

use Moose::Util::TypeConstraints;
use MooseX::SetOnce;
use MooseX::Types::Moose qw(ArrayRef HashRef);

use Moonpig;
use Moonpig::Ledger::Accountant;
use Moonpig::Events::Handler::Method;
use Moonpig::Events::Handler::Missing;
use Moonpig::Storage;
use Moonpig::Types qw(Credit Consumer);

use Moonpig::Logger '$Logger';
use Moonpig::MKits;
use Moonpig::Util qw(class event);

use Data::GUID qw(guid_string);
use List::Util qw(reduce);
use Scalar::Util qw(weaken);

use Moonpig::Behavior::EventHandlers;
use Sub::Install ();

use namespace::autoclean;

# Should this be plural?  Or what?  Maybe it's a ContactManager subsystem...
# https://trac.pobox.com/wiki/Billing/DB says that there is *one* contact which
# has *one* address and *one* name but possibly many email addresses.
# -- rjbs, 2010-10-12
has contact => (
  is   => 'ro',
  does => 'Moonpig::Role::Contact',
  required => 1,
);

has credits => (
  isa     => ArrayRef[ Credit ],
  default => sub { [] },
  traits  => [ qw(Array) ],
  handles => {
    credits    => 'elements',
    _add_credit => 'push',
  },
);

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

sub add_credit {
  my ($self, $class, $arg) = @_;
  $arg ||= {};

  local $arg->{ledger} = $self;
  my $credit = $class->new($arg);
  $self->_add_credit($credit);

  return $credit;
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
      charge_tree => class('ChargeTree')->new,
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

sub process_credits {
  my ($self) = @_;

  $self->_collect_spare_change;

  my @credits = $self->credits;

  # XXX: These need to be processed in order. -- rjbs, 2010-12-02
  for my $invoice (@{ $self->_invoices }) {
    next if $invoice->is_paid;

    @credits = grep { $_->unapplied_amount } @credits;

    my $to_pay = $invoice->total_amount;

    my @to_apply;

    # XXX: These need to be processed in order, too. -- rjbs, 2010-12-02
    CREDIT: for my $credit (@credits) {
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
      for my $to_apply (@to_apply) {
        $self->create_transfer({
          type   => 'credit_application',
          from   => $to_apply->{credit},
          to     => $invoice,
          amount => $to_apply->{amount},
        });
      }

      $Logger->log([ "marking %s paid", $invoice->ident ]);
      $invoice->handle_event(event('paid'));
      $invoice->mark_paid;
    } else {
      # We can't successfully pay this invoice, so stop processing.
      return;
    }
  }
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
  my $from = 'devnull@example.com';

  my $email = Moonpig::MKits->kit($event->payload->{kit})->assemble(
    $event->payload->{arg},
  );

  Moonpig->env->handle_event(event('send-email' => {
    email => $email,
    env   => { to => $to, from => $from },
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

  my @consumers = grep {; $_->has_bank && ! $_->is_expired } $self->consumers;
  my %consider  = map  {; $_->[0]->guid => $_ }
                  grep {; $_->[1] }
                  map  {; [ $_, $_->unapplied_amount ] }
                  $self->banks;

  delete $consider{ $_->bank->guid } for @consumers;

  my $total = reduce { $a + $b } 0, map { $_->[1] } values %consider;

  return unless $total > 0;

  my $credit = $self->add_credit(
    class('Credit::Courtesy'),
    {
      amount => $total,
      reason => "collecting spare change", # XXX ? -- rjbs, 2011-01-28
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

  if ($path->[0] eq 'xid') {
    my (undef, $xid) = splice @$path, 0, 2;
    confess "unimplemented";
    return $class->for_xid($xid);
  }

  if ($path->[0] eq 'guid') {
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

# This allows us to call ->ledger on the ledger itself, as we would on
# any of its contents. 20110217 MJD
sub ledger { return $_[0] }

sub STICK_PACK {
  my ($self) = @_;

  return {
    guid => $self->guid,
  };
}

1;
