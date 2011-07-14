use strict;
use warnings;
package Moonpig::Dashboard::Request;
use base 'HTML::Mason::Request';

# use HTML::Widget::Factory;
use JSON;
use Moonpig::UserAgent;

my $JSON = JSON->new;

# my $WIDGET_FACTORY = HTML::Widget::Factory->new;
# sub widget { $WIDGET_FACTORY; }

my $BASE_URI = $ENV{MOONPIG_URI} || die "no MOONPIG_URI";

my $ua = Moonpig::UserAgent->new({ base_uri => $BASE_URI });

sub mp_request {
  my $self = shift;

  $ua->mp_request(@_);
}

sub dump {
  my ($self, $arg) = @_;

  warn Data::Dumper->Dump([ $arg ]);
}

sub redirect {
  Moonpig::Dashboard::Redirect->throw($_[1]);
}

package Moonpig::Dashboard::Redirect {
  sub throw {
    my $guts = { uri => $_[1] };
    die(bless $guts => $_[0]);
  };

  sub uri { $_[0]->{uri} }
}

1;
