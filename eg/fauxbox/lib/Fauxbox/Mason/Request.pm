use strict;
use warnings;
package Fauxbox::Mason::Request;

BEGIN { our @ISA = qw(HTML::Mason::Request::PSGI) }

use Data::Dumper ();
use HTML::Widget::Factory;
use JSON;
use Moonpig::UserAgent;
use Fauxbox::Schema;
use DateTime;

my $JSON = JSON->new;

my $WIDGET_FACTORY = HTML::Widget::Factory->new;
sub widget { $WIDGET_FACTORY; }

my $BASE_URI = $ENV{FAUXBOX_MOONPIG_URI} || die "no FAUXBOX_MOONPIG_URI";

my $ua = Moonpig::UserAgent->new({ base_uri => $BASE_URI });

sub mp_time {
  my ($self) = @_;
  my $time = $self->mp_request(GET => '/time')->{now};
  return $time;
}

sub real_time {
  return time();
}

sub mp_request {
  my $self = shift;

  $ua->mp_request(@_);
}

sub dump {
  my ($self, $arg) = @_;

  warn Data::Dumper->Dump([ $arg ]);
}

sub schema {
  Fauxbox::Schema->shared_connection;
}

1;
