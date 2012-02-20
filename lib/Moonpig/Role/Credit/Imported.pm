package Moonpig::Role::Credit::Imported;
# ABSTRACT: a credit imported from the old billing system
use Moose::Role;

with('Moonpig::Role::Credit::Refundable');

use namespace::autoclean;

sub issue_refund {
  Moonpig::X->throw("Imported credit refund unimplemented");
}

1;
