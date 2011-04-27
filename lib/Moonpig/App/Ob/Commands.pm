package Moonpig::App::Ob::Commands;

sub exit { warn "bye\n"; exit 0 }

sub dump {
  my ($args) = @_;
  require Data::Dumper;
  if ($args->eval_ok) {
    my $s = $args->value;
    $s = Data::Dumper::Dumper($s) if $args->primary =~ /^(dump|x)$/;
    return $s;
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
