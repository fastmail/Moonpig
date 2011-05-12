package Fauxbox::Moonpig::Consumer::Account;
use Moose::Role;
with(
  'Moonpig::Role::Consumer',
);

use namespace::autoclean;

use Fauxbox::Schema;

sub account {
  my ($self) = @_;

  my $xid = $self->xid;
  my ($account_id) = $xid =~ /\A fauxbox:account: ( [0-9]+ ) \z/x;

  my $account = Fauxbox::Schema
              ->shared_connection
              ->resultset('Account')->find( $account_id );

  return $account;
}

1;
