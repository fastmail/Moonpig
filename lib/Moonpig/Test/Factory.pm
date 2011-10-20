package Moonpig::Test::Factory;
use strict;

use Moonpig::Test::Factory::Templates; # default testing template set

use Carp qw(confess croak);
use Class::MOP ();
use Data::GUID qw(guid_string);

use Moonpig::Env::Test;
use Moonpig::Util -all;

use Sub::Exporter -setup => {
  exports => [ qw(build build_consumers build_ledger) ], # The other stuff is really not suitable for exportation
};

=head1 NAME

C<Moonpig::Test::Factory> - construct test examples

=head1 SYNOPSIS

       use Moonpig::Test::Factory qw(build);

       my $stuff = build( fred => { template => "consumer template name",
                                    bank     => dollars(100) });
       my $ledger = $stuff->{ledger};
       my $consumer = $stuff->{fred};

=head1 C<build>

The C<build> function gets a list of key-value pairs.  Each pair
specifies a component to be constructed, such as a ledger or a
consumer.  The returned value is a reference to a hash with the same
keys; the corresponding values are the components that were
constructed.

=head2 C<ledger>

The C<build> function always builds a ledger, even if there is no
C<ledger> key in the argument list; if the ledger value is omitted,
the builder will build a default ledger with a randomly-generated
contact.

If a C<ledger> value is supplied, it should be a hash of the following
form:

          { class => CLASSNAME, contact => $contact }

The classname defaults to C< class('Ledger') >.  If omitted, a contact
will be generated at random using the C<build_contact> method.

=head2 Consumer keys

All other keys are taken to be names of consumers.  You may include as
many consumers as you want.  The consumers are created as specified
and added to the ledger.

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

The value of C<bank> may either be a bank object to use, or a simple
money amount.  In the latter case, a bank is manufactured with the
indicated amount of money and is used.  For example:

    use Moonpig::Util qw(dollars);
    build(fred => { template => 'test', bank => dollars(15) });

If the money amount is zero, no bank will be created.

If a consumer's key in the returned hash is I<X>, then the bank will
be returned under the key I<X>C<.bank>.

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
            cost_per_unit    => cents(5),
            old_age          => days(30),
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
  my $class = delete $args{class} || class('Ledger');
  $args{contact} ||= build_contact();
  return $class->new(\%args);
}

sub build_consumers {
  my ($ledger, $args) = @_;
  my $stuff = { ledger => $ledger };
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
  my $replacement_name = $c_args{replacement};
  if (defined($replacement_name) && ! exists $stuff->{$replacement_name}) {
    $stuff->{$replacement_name} = $c_args{replacement} =
      build_consumer($replacement_name, $args, $stuff);
  }

  my $bank;
  if (exists $c_args{bank} && ! ref($c_args{bank}) && $c_args{bank} > 0) {
    $stuff->{"$name.bank"} =
      $c_args{bank} = build_bank({ amount => $c_args{bank} }, $stuff);
  }

  my $class = delete $c_args{class};
  my $template = delete $c_args{template};

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

  return $consumer;
}

sub build_bank {
  my ($args, $stuff) = @_;

  return $stuff->{ledger}->add_bank(
    class("Bank"),
    { amount => $args->{amount} });
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

  return class('Contact')->new({
    name => join(" ", @names),
    email_addresses => [ "\L$inits\E\@example.com" ],
    address_lines   => [ '123 Street Rd.' ],
    city            => 'Townville',
    country         => 'USA',
  });
}

1;
