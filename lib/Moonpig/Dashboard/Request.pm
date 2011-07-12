use strict;
use warnings;
package Moonpig::Dashboard::Request;
BEGIN { our @ISA = qw(HTML::Mason::Request::PSGI) }

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

1;
