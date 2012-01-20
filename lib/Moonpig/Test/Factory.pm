package Moonpig::Test::Factory;
use strict;

use Moonpig::Test::Factory::Templates; # default testing template set

use Carp qw(confess croak);
use Class::MOP ();
use Data::GUID qw(guid_string);
use Scalar::Util qw(blessed);

use Moonpig::Util -all;

use Sub::Exporter -setup => {
  exports => [ qw(build build_consumers build_ledger do_with_fresh_ledger do_ro_with_fresh_ledger) ],
};

=head1 NAME

C<Moonpig::Test::Factory> - construct test examples

=head1 SYNOPSIS

   use Moonpig::Test::Factory qw(do_with_fresh_ledger);

   do_with_fresh_ledger({ fred => { template => "consumer template name",
                                   bank     => dollars(100) } }, sub {
     my ($ledger) = @_;
     my $consumer = $ledger->get_component("fred");
     ...
   });


=head2 C<do_with_fresh_ledger>

	do_with_fresh_ledger($args, $code);

This builds a new ledger and associated components with C<<
build(%$args) >> (see below) and tells Moonpig to propagate it into a
new read-write transaction that executes the action in C<$code>.  The
ledger is passed to C<$code> as an argument.

The ledger supports a special method, C<get_component>, which can be
used to access the ledger's components by names given to them in the
C<$args> hash; see below for details.

The new ledger's GUID may be safely captured and re-used in a later
call to C<Moonpig::Storage::do_with_ledger>.

If C<$args> contains a C<do_opts> element, it should be hashref of
options to be supplied to the lower-level C<do_with_ledgers> function;
it is not passed to C<<build>>. You may use C<< ro => 1 >> to run
C<$code> in a read-only transaction. See
C<Moonpig::Role::Storage::do_with_ledgers> for further details.

=head2 C<do_ro_with_fresh_ledger>

The same as C<do_with_fresh_ledger>, but forces a read-only
transaction.

=head1 C<build>

The C<build> function gets a list of key-value pairs.  Each pair
specifies a component to be constructed, such as a ledger or a
consumer.  The returned value is a reference to a hash with the same
keys; the corresponding values are the components that were
constructed.

=head2 WARNING

If you construct a ledger object with C<build> and then perform
Moonpig operations on it, you run a risk that the object will become
invalid relative to the state of the Moonpig persistent database.
Calls to Moonpig to retrieve the ledger may return a different ledger
object representing the same ledger. Moonpig methods may create and
modify such objects internally, without propagating the appropriate
changes out to your ledger object.  To avoid this problem, you should
not usually called C<build> directly, but always implicitly via
C<do_with_fresh_ledger>.

=head2 C<ledger>

The C<build> function always builds a ledger, even if there is no
C<ledger> key in the argument list; if the ledger value is omitted,
the builder will build a default ledger with a randomly-generated
contact.

If a C<ledger> value is supplied, it should be a hash of the following
form:

          { class => CLASSNAME, contact => $contact }

The classname defaults to:

    Moonpig::Util::class('Ledger', 'Moonpig::Test::Role::Ledger')

If you supply your own classname, it must compose the simple role
C<Moonpig::Test::Role::Ledger> or implement equivalent functionality.

If a contact is omitted, one will be generated at random using the
C<build_contact> method.

=head2 Component keys

All other keys are taken to be names of consumers.  You may include as
many consumers as you want.  The consumers are created as specified
and added to the ledger.  You can retrieve the consumers later by using
C<< $ledger->get_component( $name ) >>.

The corresponding values are hashes.   Each hash must contain either a
C<template> key which specifies a template name, or a C<class> key
which specifies a class role name.

If C<template>, the consumer is
constructed and added to the ledger with
C<Ledger::add_consumer_from_template>.

If C<class> is specified, it should be the name of the class for the
consumer; it is given to C<Ledger::add_consumer>.  You may use
C<Moonpig::Util::class> to construct this name.

Most hash elements are passed to the consumer constructor
(C<Ledger::add_consumer_from_template> or C<Ledger::add_consumer>) as
normal constructor arguments.  There are a few exceptions:

=over

=item *

As described above, C<class> and C<template> are special, and are not
passed.

=item *

The value of C<replacement> may either be a consumer object to use as
the replacement, or a string which identifies the consumer to use as
the one manufactured by the C<build> method itself.  For example,

    build(fred => { template => 'test', replacement => 'steve' },
          steve => { template => 'test' });

builds a ledger with two consumers; the replacement for consumer
C<fred> will be consumer C<steve>.

=item *

The value of C<bank> is a money amount.  For example:

    use Moonpig::Util qw(dollars);
    build(fred => { template => 'test', bank => dollars(15) });

=item *

If no C<xid> argument is passed, C<test:consumer:NAME> will be used,
where I<NAME> is the key by which the consumer is known in the
arguments to C<build>.  For example, in this call:

    build(fred => { template => 'test' });

the consumer C<fred> receives the xid C<test:consumer:fred>.

Note that if consumer I<B> is the replacement for consumer I<A>, they
will still not be assigned the same xid by default; this is probably
not what you want.

=item *

If a C<make_active> argument is passed, the consumer will be made the
active consumer for its xid if the associated value is true.  If no
C<make_active> argument is passed, the consumer will be activated if
and only if it is I<not> the replacement for any other consumer.  For
example:

    # fred is activated, steve is not
    build(fred => { template => 'test', replacement => 'steve' },
          steve => { template => 'test' });


    # neither is activated
    build(fred => { template => 'test', replacement => 'steve', make_active => 0 },
          steve => { template => 'test' });

    # both are activated
    build(fred => { template => 'test', replacement => 'steve' },
          steve => { template => 'test', make_active => 1 });


=back

=head2 Examples

        my $stuff = build(
          consumer => {
            class            => class('Consumer::ByUsage'),
            bank             => dollars(1),
            charge_amount_per_unit    => cents(5),
            replacement_lead_time          => days(30),
            replacement_plan => [ get => '/nothing' ],
            make_active      => 1,
          },
        );

The C<$stuff> hash contains two elements.  C<< $stuff->{ledger} >> is a
regular ledger with a randomly-generated contact.  C<< $stuff->{consumer} >>
is a consumer of class C<class("Moonpig::Role::Consumer::ByUsage")>
with a bank that contains $1 and other properties as specified.  The
C<< make_active => 1 >> specification is redundant.

  my $xid = "...";
  my $stuff = build(b5 => { template => 'fiveyear', replacement => 'g1', xid => $xid },
                    g1 => { template => 'free_sixthyear',                xid => $xid });

Here the C<$stuff> hash contains three elements: C<ledger>, C<b5>, and
C<g1>.  Elements C<b5> and C<g1> are consumers built from the
indicated templates; consumer C<g1> is the replacement for C<b5>.
Note the use of an explicit C<xid> argument to ensure that both
consumers handle the same XID.  Consumer C<b5> is the active consumer
for this XID, because it is the consumer which is not a replacement.

=head1 C<build_ledger>

This builds and returns a single ledger.  Arguments are the same as
for the C<ledger> element of the arguments to the C<build> function,
described above.  That is, these two calls are in all cases identical:

	build_ledger($args)

	build(ledger => $args)

except that the first returns the ledger and the second returns a hash
with the ledger stored under the key C<ledger>.

=head1 C<build_consumers>

Use this if you need to build the ledger and consumers separately.

        my $ledger = build_ledger();
	my $stuff = build_consumers($ledger, $args);

Here C<$args> is an argument hash suitable for passing to C<build>.
C<build_consumers> works the same way but inserts the consumers into
the specified ledger instead of building a new one.  It returns the
same C<$stuff> array as C<build>, including the C<ledger> element.

=cut

sub build {
  my (%args) = @_;

  my $ledger = build_ledger($args{ledger});
  delete $args{ledger};

  my $stuff = build_consumers($ledger, \%args);

  return $stuff;
}

sub build_ledger {
  my ($args) = @_;
  my %args = %{$args || {}};
  my $class = delete $args{class} || class('Ledger', '=Moonpig::Test::Role::Ledger');
  $args{contact} ||= build_contact();
  return $class->new(\%args);
}

sub build_consumers {
  my ($ledger, $args) = @_;
  my $stuff = $ledger->_component_name_map;
  $stuff->{ledger} = $ledger;
  _build_consumers($args, $stuff);
}

sub _build_consumers {
  my ($args, $stuff) = @_;

  my %name_by_guid; # backwards mapping from guid of created consumer to name
  # create all required consumers
  for my $c_name (keys %$args) {
    next if exists $stuff->{$c_name};
    my %c_args = %{$args->{$c_name}};
    $stuff->{$c_name} = build_consumer($c_name, $args, $stuff);
    $name_by_guid{$stuff->{$c_name}->guid} = $c_name;
  }

  # find the ones that are *not* replacements and activate them unless
  # otherwise specified
  { my %consumer = map { $stuff->{$_}->guid => $stuff->{$_} } keys %$args;
    # delete all the consumers that are replacements
    my @consumers = values %consumer;
    for my $consumer (@consumers) {
      $consumer->replacement && delete $consumer{$consumer->replacement->guid};
    }
    # iterate over non-replacements, activating each
    for my $consumer (values %consumer) {
      my $name = $name_by_guid{$consumer->guid};
      # activate by default, or if the arg value is true
      if (! exists $args->{$name}{make_active} || $args->{$name}{make_active}) {
        $consumer->become_active;
      }
    }
  }

  return $stuff;
}

sub build_consumer {
  my ($name, $args, $stuff) = @_;
  my %c_args = %{$args->{$name}};
  my $become_active = delete $c_args{make_active};

  # If this consumer will have a replacement, build that first
  if (exists($c_args{replacement}) && ! blessed($c_args{replacement})) {
    my $replacement_name = $c_args{replacement};
    if (! exists $stuff->{$replacement_name}) {
      # replacement not yet built; build it before proceeding
      $stuff->{$replacement_name} = build_consumer($replacement_name, $args, $stuff);
    }
    $c_args{replacement} = $stuff->{$replacement_name};
  }

  my $class = delete $c_args{class};
  my $template = delete $c_args{template};
  my $amount   = delete $c_args{bank};

  my $consumer;
  if ($class) {
    croak "Arguments for consumer '$name' have both 'class' and 'template'\n"
      if $template;

    Class::MOP::load_class($class);
    $consumer = $stuff->{ledger}->add_consumer(
      $class,
      { xid => "test:consumer:$name",
        %c_args,
      });
  } elsif ($template) {
    $consumer = $stuff->{ledger}->add_consumer_from_template(
      $template,
      { xid => "test:consumer:$name",
        %c_args,
      });
  } else {
    croak "Arguments for consumer '$name' have neither 'class' nor 'template'\n";
  }

  $consumer->become_active if $become_active;

  if (defined $amount && $amount > 0) {
    my $credit = $stuff->{ledger}->add_credit(
      class(qw(Credit::Simulated)),
      { amount => $amount },
    );

    $stuff->{ledger}->create_transfer({
      type   => 'test_consumer_funding',
      from   => $credit,
      to     => $consumer,
      amount => $amount,
    });
  }

  return $consumer;
}

sub rnd {
  my (@items) = @_;
  return $items[int(rand(1000)) % @items];
}

sub build_contact {
  my ($self) = @_;
  my @first = qw(John Mary William Anna James Margaret George Helen Charles Elizabeth);
  my @last = qw(Smith Johnson Williams Jones Brown Davis Miller Wilson Moore Taylor);
  my @names = (rnd(@first), rnd('A' .. 'Z') . ".", rnd(@last));
  my $inits = join "", map substr($_, 0, 1), @names;

  my $phone = join "", map { int rand 10 } (1 .. 10);

  return class('Contact')->new({
    first_name      => $names[0],
    last_name       => $names[2],
    phone_number    => $phone,
    email_addresses => [ "\L$inits\E\@example.com" ],
    address_lines   => [ '123 Street Rd.' ],
    city            => 'Townville',
    country         => 'USA',
  });
}

sub do_with_fresh_ledger {
  my ($args, $code) = @_;
  my $opts = delete($args->{do_opts}) || {};
  my $stuff = build(%$args);
  my $ledger = delete $stuff->{ledger};
  return Moonpig->env->storage->do_with_this_ledger($opts, $ledger, $code);
}

sub do_ro_with_fresh_ledger {
  my ($args, $code) = @_;
  $args->{do_opts}{ro} = 1;
  do_with_fresh_ledger($args, $code);
}

1;
