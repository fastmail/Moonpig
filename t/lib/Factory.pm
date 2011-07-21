package t::lib::Factory;
use strict;

use Carp qw(confess croak);
use Data::GUID qw(guid_string);

use Moonpig::Env::Test;
use Moonpig::URI;
use Moonpig::Util -all;

use Sub::Exporter -setup => {
  exports => [ qw(build) ], # The other stuff is really not suitable for exportation
};

sub build {
  my (%args) = @_;
  my %stuff;

  $stuff{ledger} = build_ledger($args{ledger});
  delete $args{ledger};

  build_consumers(\%args, \%stuff);

  return \%stuff;
}

sub build_ledger {
  my ($args) = @_;
  my %args = %{$args || {}};
  my $class = delete $args{class} || class('Ledger');
  $args{contact} ||= build_contact();
  return $class->new(\%args);
}

sub build_consumers {
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
    for my $consumer (values %consumer) {
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
  if (exists $c_args{bank} && $c_args{bank} > 0) {
    $c_args{bank} = build_bank({ amount => $c_args{bank} }, $stuff);
  }

  my $class = delete $c_args{class};
  my $template = delete $c_args{template};

  my $consumer;
  if ($class) {
    croak "Arguments for consumer '$name' have both 'class' and 'template'\n"
      if $template;

    $class = "Consumer::$class" unless $class =~ /^Consumer::/;
    $consumer = $stuff->{ledger}->add_consumer(
      class($class),
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
  });
}

1;
