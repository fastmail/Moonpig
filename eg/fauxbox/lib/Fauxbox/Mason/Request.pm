use strict;
use warnings;
package Fauxbox::Mason::Request;

BEGIN { our @ISA = qw(HTML::Mason::Request::PSGI) }

use Data::Dumper ();
use HTML::Widget::Factory;
use JSON;
use LWP::UserAgent;
use Fauxbox::Schema;
use DateTime;

my $JSON = JSON->new;

my $WIDGET_FACTORY = HTML::Widget::Factory->new;
sub widget { $WIDGET_FACTORY; }

my $BASE_URI = $ENV{FAUXBOX_MOONPIG_URI} || die "no FAUXBOX_MOONPIG_URI";

my $UA = LWP::UserAgent->new;

$BASE_URI =~ s{/$}{};

sub mp_time {
  my ($self) = @_;
  my $time = $self->mp_request(GET => '/time')->{now};
  return DateTime->from_epoch(epoch => $time, time_zone => 'America/New_York');
}

sub real_time {
  return DateTime->now(time_zone => 'America/New_York');
}

sub mp_request {
  my ($self, $method, $path, $arg) = @_;

  my $target = $BASE_URI . $path;
  $method = lc $method;

  my $res;

  if ($method eq 'get') {
    $res = $UA->get($target);
  } elsif ($method eq'post') {
    my $payload = $JSON->encode($arg);

    $res = $UA->post(
      $target,
      'Content-Type' => 'application/json',
      Content => $payload,
    );
  }

  return undef if $res->code == 404;

  unless ($res->code == 200) {
    die "unexpected response from moonpig:\n" . $res->as_string;
  }

  return $JSON->decode($res->content);
}

sub dump {
  my ($self, $arg) = @_;

  warn Data::Dumper->Dump([ $arg ]);
}

sub schema {
  Fauxbox::Schema->shared_connection;
}

1;
