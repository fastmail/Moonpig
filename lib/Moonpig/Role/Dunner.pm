package Moonpig::Role::Dunner;
# ABSTRACT: something that performs dunning of invoices

use Moose::Role;

use Data::GUID qw(guid_string);
use List::AllUtils 'any';
use Moonpig;
use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class event);
use Moonpig::Types qw(TimeInterval);
use Moonpig::Util qw(days sumof);
use Moose::Util::TypeConstraints qw(role_type);
use MooseX::Types::Moose qw(Str HashRef);
use Stick::Publisher 0.307;
use Stick::Publisher::Publish 0.307;
use Try::Tiny;

use namespace::autoclean;

has _dunning_history => (
  is  => 'ro',
  isa => 'ArrayRef[HashRef]',
  lazy     => 1,
  init_arg => undef,
  traits   => [ 'Array' ],
  default  => sub {  []  },
  handles  => {
    _last_dunning        => [ get => -1 ],
    _record_last_dunning => 'push',
    has_ever_dunned      => 'count',
  },
);

sub _last_dunning_time {
  return unless $_[0]->has_ever_dunned;
  $_[0]->_last_dunning->{dunned_at};
}

sub _last_dunned_invoice_guids {
  my ($self) = @_;
  return unless $self->has_ever_dunned;
  return @{ $self->_last_dunning->{invoice_guids} };
}

has custom_dunning_frequency => (
  is => 'rw',
  isa => TimeInterval,
  predicate => 'has_custom_dunning_frequency',
  clearer   => 'clear_custom_dunning_frequency',
);

publish _published_dunning_history => { -path => 'dunning-history' } => sub {
  my ($self) = @_;
  my $history = $self->_dunning_history;
  return {
    items => $history,
  };
};

sub dunning_frequency {
  my ($self) = @_;

  return $self->custom_dunning_frequency
    if $self->has_custom_dunning_frequency;

  return Moonpig->env->default_dunning_frequency;
}

sub _should_dunn_again {
  my ($self, $invoices) = @_;

  my $overearmarked = $self->amount_overearmarked;

  # If there's nothing to pay, why would we dunn?? -- rjbs, 2012-03-26
  return unless @$invoices or $overearmarked;

  # If we never dunned before, let's! -- rjbs, 2012-03-26
  return 1 unless $self->has_ever_dunned;

  # Now things get more complicated.  We dunned once.  Do we want to dunn
  # again?  Only if (a) it's been a while or (b) the situation has changed.
  # -- rjbs, 2012-03-26
  my $since = Moonpig->env->now - $self->_last_dunning_time;

  # (a) it's been a while!
  return 1 if $since > $self->dunning_frequency;

  # (b) something changed!
  return 1 if $self->_last_dunning->{amount_overearmarked} != $overearmarked;

  my @last_invoice_guids = $self->_last_dunned_invoice_guids;
  return 1 unless @$invoices &&  @last_invoice_guids == @$invoices;
  return 1 if $invoices->[0]->guid ne $last_invoice_guids[0];

  # Nope, nothing new.
  return;
}

sub perform_dunning {
  my ($self) = @_;

  my @invoices =
    sort { $b->created_at <=> $a->created_at
        || $b->guid       cmp $a->guid # incredibly unlikely, but let's plan
         }
    grep { any { ! $_->is_abandoned } $_->all_charges }
    grep { ! $_->is_abandoned && $_->is_unpaid && $_->has_charges }
    $self->invoices_without_quotes;

  return unless $self->_should_dunn_again(\@invoices);

  $_->mark_closed for grep { $_->is_open } @invoices;

  # Now we have an array of closed, unpaid invoices.  Before we send anything
  # to the poor guy who is on the hook for these, let's see if we can pay any
  # with existing credits, or charge him whatever we need to, to pay this.
  $self->_autopay_invoices(\@invoices);

  $self->_send_invoice_email(\@invoices);
}

sub _autopay_invoices {
  my ($self, $invoices) = @_;

  # First, just in case we have any credits on hand, let's see if we can pay
  # them off with existing credits.
  $self->process_credits;

  # If that worked, we're done!
  return unless $self->payable_invoices;

  # We can't autopay, so don't bother trying.
  return unless my $autocharger = $self->autocharger;

  my @unpaid_invoices = grep { ! $_->is_paid } @$invoices;

  # Oh no, there are invoices left to pay!  How much will it take to pay it all
  # off?
  my $credit_on_hand = sumof { $_->unapplied_amount } $self->credits;
  my $invoice_total  = sumof { $_->total_amount } @unpaid_invoices;
  my $balance_needed = $invoice_total - $credit_on_hand;

  my $credit = $autocharger->charge_into_credit({ amount => $balance_needed });

  if ($credit) {
    $self->process_credits;
  }

  return $credit;
}

# This is basically exactly the code of Ledger->add_consumer_from_template
sub setup_autocharger_from_template {
  my ($self, $template, $arg) = @_;
  $arg ||= {};

  $template = Moonpig->env->autocharger_template($template)
    unless ref $template;

  Moonpig::X->throw("unknown autocharger template") unless $template;

  my $template_roles = $template->{roles} || [];
  my $template_class = $template->{class};
  my $template_arg   = $template->{arg}   || {};

  Moonpig::X->throw("autocharger template supplied class and roles")
    if @$template_roles and $template_class;

  my $obj = ($template_class || class(qw(Autocharger), @$template_roles))->new({
    ledger => $self,
    %$template_arg,
    %$arg,
  });

  $self->_set_autocharger($obj);
  return $obj;
}

publish _setup_autocharger => {
  -http_method => 'post', -path => 'setup-autocharger',
  template      => Str,
  template_args => HashRef,
} => sub {
  my ($self) = @_;
  $self->handle_event( event('heartbeat') );
};

has autocharger => (
  is  => 'ro',
  isa => role_type('Moonpig::Role::Autocharger'),
  writer  => '_set_autocharger',
  clearer => '_delete_autocharger',
);

publish _get_autocharger => { -path => 'autocharger', -http_method => 'get' } => sub {
  $_[0]->autocharger;
};

sub _invoice_xid_summary {
  my ($self, $invoices) = @_;
  return unless @$invoices;

  my %xid_info;
  my %seen_guid;

  for my $charge (map {; $_->all_charges } @$invoices) {
    next if $seen_guid{ $charge->owner_guid };
    my $xid = $self->consumer_collection->find_by_guid({
      guid => $charge->owner_guid,
    })->xid;

    my $active = $self->active_consumer_for_xid($xid);

    $xid_info{ $xid } = {
      expiration_date => (
        $active && $active->can('replacement_chain_expiration_date')
        ? $active->replacement_chain_expiration_date
        : undef
      ),
    };
  }

  return \%xid_info;
}

sub _send_invoice_email {
  my ($self, $invoices_ref) = @_;

  # invoices has arrived here pre-sorted by ->perform_dunning
  my @invoices = grep { ! $_->is_internal } @$invoices_ref;

  unless (@invoices) {
    $Logger->log([
      "dunning ledger %s but not sending invoices; they're all internal",
      $self->ident,
    ]);
    return;
  }

  $Logger->log([
    "sending invoices %s to contacts of %s",
    [ map {; $_->ident } @invoices ],
    $self->ident,
  ]);

  my $xid_info = $self->_invoice_xid_summary(\@invoices);

  my $dunning_guid = guid_string;

  $self->_record_last_dunning({
    dunned_at     => Moonpig->env->now,
    dunning_guid  => $dunning_guid,
    invoice_guids => [ map {; $_->guid } @invoices ],
    xid_info      => $xid_info,
    amount_overearmarked => $self->amount_overearmarked,
    amount_due           => $self->amount_due,
  });

  $self->handle_event(event('send-mkit', {
    kit => 'invoice',
    arg => {
      subject => "Payment is due",

      # This should get names with addresses, unlike the contact-humans
      # handler, which wants envelope recipients.
      to_addresses => [ $self->contact->email_addresses ],

      dunning_guid => $dunning_guid,
      invoices     => \@invoices,
      ledger       => $self,
      xid_info     => $xid_info,
    },
  }));
}

sub _minimum_psync_amount {
  # This should really be a publicly defined env method.
  # The package variable is here, for now, to support a hack in
  # t/invoice/psync/chain.t -- rjbs, 2013-02-18
  our $_minimum_psync_amount //= Moonpig::Util::dollars(1);
}

# If there's a quote, it's for the amount of money the consumers need
# to advance their expire date back to where it was.  If not, then the
# expire date advanced and we're just sending a notification of that
# fact.
sub _send_psync_email {
  my ($self, $consumer, $info) = @_;

  my $quote = $info->{quote};
  my $what = $quote ? "psync quote" : "psync reverse notice";

  $Logger->log([
    "sending $what for %s to contacts of %s",
    $consumer->xid,
    $self->ident,
  ]);

  # use Moonpig::Util qw(to_dollars);
  # warn sprintf "\n# <%s> <expected: %s> <predicting: %s> <%s>\n",
  #   $what,
  #   $info->{old_expiration_date},
  #   $info->{new_expiration_date},
  #   to_dollars($quote ? $quote->total_amount : 0),
  # ;

  if ($quote and $quote->total_amount < $self->_minimum_psync_amount) {
    $Logger->log("declining to send mail; amount too small");
    return;
  }

  $self->handle_event(event('send-mkit', {
    kit => $quote ? 'psync' : 'psync-notice',
    arg => {
      subject => "Your expiration date has changed",

      # This should get names with addresses, unlike the contact-humans
      # handler, which wants envelope recipients.
      to_addresses => [ $self->contact->email_addresses ],
      old_expiration_date => $info->{old_expiration_date},
      new_expiration_date => $info->{new_expiration_date},
      $quote ? (charge_amount => $quote->total_amount) : (),
      $quote ? (quote_guid => $quote->guid)            : (),
      ledger       => $self,
      consumer     => $consumer,
    },
  }));
}

1;
