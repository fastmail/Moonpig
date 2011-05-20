
package Ob;  # note weird package declaration
# This is the package in which unrecognized commands are evaluated as Perl
# expressions.
use strict;
use warnings;
use Moonpig::Util '-all';
use Carp 'croak';

# These variables will be set up in package Ob when these functions
# are invoked via Moonpig::App::Ob::Commands::eval
our ($ob, $st);

sub generate {
  my ($subcommand, @args) = @_;
  $subcommand ||= 'help';
  if ($subcommand eq 'ledger') {
    return class('Ledger')->new({ contact => _gen_contact() });
  } elsif ($subcommand eq 'contact') {
    return _gen_contact();
  } else {
    warn "Usage: generate [ledger|contact]\n";
    return "";
  }
}
*gen =\&generate;

{
  my $N = 'a';
  sub _gen_contact {
    my $name = "\U$N\E Jones";
    my $email = qq{$N\@example.com};
    $N++;
    return class('Contact')->new({ name => $name,
                                   email_addresses => [ $email ],
                                 });
  }
}

sub store {
  my (@argl) = @_;
  unless (@argl) {
    warn "Usage: store ledger...\n";
    return "";
  }
  $ob->storage->_store_ledger($_) for @argl;
}
*st =\&store;

sub xid {
  my (@args) = @_;
  my @ledgers = map $st->retrieve_ledger_for_xid($_), @args;
  return wantarray ? @ledgers : $ledgers[0];
}

sub guid {
  my (@args) = @_;
  my @ledgers = map $st->retrieve_ledger_for_guid($_), @args;
  return wantarray ? @ledgers : $ledgers[0];
}

sub guid_or_xid {
  my ($id) = @_;
  return guid($id) || xid($id) || do {
    warn "Can't find ledger for '$id'\n";
    return;
  };
}

sub ledger {
  my (@args) = @_;
  my @L = grep defined, map guid_or_xid($_), @args;

  return @L if wantarray;

  warn "Found more than one ledger, but called in scalar context." if @L > 1;
  return $L[0];
}

sub guids {
  $st->ledger_guids;
}

1;
