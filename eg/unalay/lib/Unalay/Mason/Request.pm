use strict;
use warnings;
package Unalay::Mason::Request;

BEGIN { our @ISA = qw(HTML::Mason::Request::PSGI) }

use HTML::Widget::Factory;

my $WIDGET_FACTORY = HTML::Widget::Factory->new;
sub widget { $WIDGET_FACTORY; }

1;
