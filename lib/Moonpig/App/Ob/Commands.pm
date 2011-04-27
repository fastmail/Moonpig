package Moonpig::App::Ob::Commands;

sub exit { warn "bye\n"; exit 0 }

sub dump {
  my ($args) = @_;
  my @extra;
  if ($args->eval_ok) {
    my $val = my $s = $args->value;
    if ($args->primary =~ /^(dump|x)$/) {
      require Data::Dumper;
      # callback to use actual value, not string, as $it
      @extra = (sub { $args->hub->last_result($val) });
      $s = Data::Dumper::Dumper($val);
    }
    return ($s, @extra);
  } else {
    warn $args->exception;
    return;
  }
}

sub reload {
  warn "reloading $0...\n";
  exec $0, @ARGV;
  die "exec $0: $!";
}

1;
