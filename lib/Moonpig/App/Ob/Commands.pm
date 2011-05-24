package Moonpig::App::Ob::Commands;
use strict;
use warnings;
use Moonpig::Util qw(class);
use Moonpig::App::Ob::Dumper;

sub eval {
  my ($args) = @_;
  my $expr = $args->orig_args;

  my $maxdepth = $args->hub->config->get('maxdepth') || -1;
  if ($args->primary =~ /\A(x|dump|d)\z/) {
    if ($expr =~ s/\A\s*([0-9]+)\s+//) {
      $maxdepth = $1;
    }
  }

  my @res = $args->hub->eval($expr);
  my $fh = $args->hub->output_fh;

  if ($@) {
    $args->hub->obwarn($@);
    return;
  } elsif ($args->primary =~ /^dd/) { # use data::dumper
    print $fh Data::Dumper::Dumper(@res);
    $args->hub->suppress_next_output(1);
    return @res;
  } {
    my $output = Moonpig::App::Ob::Dumper
      ->new({ $args->hub->dump_options, maxdepth => $maxdepth })
        ->dump_values(@res)
          ->result;
    my $len = $output =~ tr/\n//;
    if ($args->primary eq '_internal_eval' && $len > $args->hub->maxlines ) {
      my @lines = split /\n/, $output;
      $output = join "\n", @lines[0.. $args->hub->maxlines - 1], "";
      $args->hub->output($output);
      $args->hub->output("  WARNING: $len-line output truncated; use 'x \$it' to see all");
    } else {
      $args->hub->output($output);
    }
    $args->hub->suppress_next_output(1);
    return @res;
  }
}

sub exit { warn "bye\n"; exit 0 }

sub help {
  my ($args) = @_;
  my $rtab = {};

  my $tab = $args->hub->command_table;
  while (my ($cname, $code) = each %$tab) {
    next if $cname =~ /^_/;
    push @{$rtab->{$code}}, $cname;
  }

  while (my $name = each %Ob::) {
    next unless defined &{"Ob::$name"};
    next if $name =~ /^_/;
    my $code = \&{"Ob::$name"};
    push @{$rtab->{$code}}, $name;
  }

  my @res;
  for my $aliases (values %$rtab) {
    my @words = sort @$aliases;
    if (@words> 1) {
      push @res, $words[0] . " (" . join(", ", @words[1..$#words]) . ")";
    } else {
      push @res, $words[0];
    }
  }
  return join "\n", sort(@res), "";
}

sub reload {
  warn "reloading $0...\n";
  exec $0, @ARGV;
  die "exec $0: $!";
}

sub wait {
  my ($args) = @_;
  die "Unimplemented\n";
}

sub shell {
  my ($args) = @_;
  my @cmd = @{$args->arg_list};

  if (! @cmd) {
    my $shell = $ENV{SHELL} || (-x '/bin/bash' ? '/bin/bash' : '/bin/sh');
    warn "Use 'exit' to return from shell\n";
    my $rc = system $shell;
    $rc == 0 or warn "shell failed\n";
    return;
  }

  my $res = readpipe (join " ", @cmd);
  my $status = $? >> 8;
  my $sig = $? & 255;
  if ($sig) {
    warn "command died with signal $sig\n";
  } elsif ($status) {
    warn "command exited with non-zero status $status\n";
  }
  return $res;
}

1;
