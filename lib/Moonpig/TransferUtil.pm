
package Moonpig::TransferUtil;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw(
  is_transfer_capable
  transfer_types
  transfer_type_ok
  valid_type
  deletable
);
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

my %TYPE; # Maps valid transfer type names to 1, others to false
my %CANTRANSFER; # Maps valid transferer names ("payable") to 1, others to false
my %TYPEMAP; # Maps valid (from, to, type) triples to 1, others to false
my $INITIALIZED;

sub import {
  my ($class) = @_;
  $class->export_to_level(1, @_); # Call Exporter::import as usual
  return if $INITIALIZED;
  while (my $line = <DATA>) {
    $line =~ s/#.*//;
    next unless $line =~ /\S/;
    chomp $line;
    my ($from, $to, $type, $rest) = split /\s+/, $line;
    die "Malformed typemap line '$line'" if $rest || ! defined($to);
    for ($from, $type, $to) {
      die "Malformed typemap line '$line'" if /\W/;
    }
    $TYPEMAP{$from}{$to}{$type} = 1;
    $CANTRANSFER{$from} = 1;
    $CANTRANSFER{$to} = 1;
    $TYPE{$type} = 1;
  }
  close DATA;
  $INITIALIZED = 1;
}

sub is_transfer_capable {
  my ($what) = @_;
  return $CANTRANSFER{$what};
}

sub transfer_types {
  return keys %CANTRANSFER;
}

sub transfer_type_ok {
  my ($fm, $to, $tp) = @_;
  exists $TYPEMAP{$fm} and
  exists $TYPEMAP{$fm}{$to} and
         $TYPEMAP{$fm}{$to}{$tp};
}

sub valid_type {
  my ($type) = @_;
  return $TYPE{$type};
}

sub deletable {
  my ($type) = @_;
  return $type eq 'hold';
}

1;

__DATA__
# FROM     TO        TYPE
consumer   journal   hold
consumer   journal   transfer
credit     refund    refund
credit     invoice   credit_application
consumer   credit    cashout
invoice    consumer  consumer_funding
credit     consumer  test_consumer_funding
