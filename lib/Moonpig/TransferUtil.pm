
package Moonpig::TransferUtil;

my %TYPE; # Maps valid type names to 1, others to false
my %TYPEMAP; # Maps valid from-to-type triples to 1, others to false

CHECK {
  while (my $line = <DATA>) {
    $line =~ s/#.*//;
    next unless $line =~ /\S/;
    chomp $line;
    my ($from, $type, $to, $rest) = split /\s+/, $line;
      die "Malformed typemap line '$line'" if $rest || ! defined($to);
    for ($from, $type, $to) {
      die "Malformed typemap line '$line'" if /\W/;
    }
    $TYPEMAP{$from}{$to}{$type} = 1;
    $TYPE{$type} = 1;
  }
}

sub transfer_type_ok {
  my ($class, $fm, $to, $tp) = @_;
  exists $TYPEMAP{$fm} and
  exists $TYPEMAP{$fm}{$to} and
         $TYPEMAP{$fm}{$to}{$tp};
}

sub valid_type {
  my ($class, $type) = @_;
  return $TYPE{$type};
}

sub deletable {
  my ($class, $type) = @_;
  return $type eq 'hold';
}

1;

__DATA__
# FROM TYPE               TO
bank   transfer           consumer
bank   hold               consumer
credit credit_application payable
bank   bank_credit        credit
