
package Moonpig::Ledger::Accountant;
use Moose;

with 'Role::Subsystem' => {
  ident  => 'ledger-accountant',
  type   => 'Moonpig::Role::Ledger',
  what   => 'ledger',
  weak_ref => 0,
};

# Given source and destination types, and transfer type,
# $type_map{source type}{destination type}{transfer type} is true iff
# the specified transfer type is permitted between the specified source
# and destination.
has type_map => (
  is => 'ro',
  isa => 'HashRef',
  default => sub { $_[0]->_load_type_map(*DATA) },
);

sub type_is_ok {
  my ($self, $fm, $to, $tp) = @_;
  my $tm = $self->type_map;
  exists $tm->{$fm} and exists $tm->{$fm}{$to} and $tm->{$fm}{$to}{$tp};
}

sub _load_type_map {
  my ($self, $fh) = @_;
  my %tm;
  while (my $line = <$fh>) {
    $line =~ s/#.*//;
    next unless $line =~ /\S/;
    chomp $line;
    my ($from, $type, $to, $rest) = split /\s+/, $line;
      die "Malformed typemap line '$line'" if $rest || ! defined($to);
    for ($from, $type, $to) {
      die "Malformed typemap line '$line'" if /\W/;
    }
    $tm{$from}{$to}{$type} = 1;
  }
  return \%tm;
}

1;

__DATA__
# FROM TYPE               TO
bank   transfer           consumer
bank   hold               consumer
credit credit_application payable
bank   bank_credit        credit
