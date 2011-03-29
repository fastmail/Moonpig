use strict;
use warnings;
package Fauxbox::Mason::Commands;

use Sub::Exporter -setup => {
  groups  => [ default => [ '-all' ] ],
  exports => [ qw(username_xid) ],
};

sub username_xid { "fauxbox:username:$_[0]" }

1;
