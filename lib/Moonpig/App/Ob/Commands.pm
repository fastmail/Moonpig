package Moonpig::App::Ob::Commands;
use strict;
use warnings;
use Moonpig::Util qw(class);

sub eval {
  my ($args) = @_;
  my $expr = $args->orig_args;

  my @res = do {
    package Ob;

    our ($it, @it, $ob, $st);
    local $ob = $args->hub;
    local $it = $ob->it;
    local @it = @{$ob->last_result};
    local $st = $ob->storage;

    no strict;
    eval $expr;
  };

  if ($@) {
    $args->hub->obwarn($@);
    return;
  } else {
    if ($args->primary eq "dump") {
      local $Ob::ob = $args->hub; # Awful hack
      Ob::d(@res);
    }
    return @res;
  }
}

sub exit { warn "bye\n"; exit 0 }

sub help {
  my ($args) = @_;
  my $tab = $args->hub->command_table;
  my $rtab = {};
  while (my ($cname, $code) = each %$tab) {
    push @{$rtab->{$code}}, $cname;
  }
  my @res;
  for my $aliases (values %$rtab) {
    warn " > $aliases = (@$aliases)\n";
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
