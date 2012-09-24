use strict;
use warnings;
package Moonpig::Dashboard::Request;
use base 'HTML::MasonX::Free::Request';
# ABSTRACT: the Mason request subclass for the Moonpig dashboard

# use HTML::Widget::Factory;
use CGI::Expand ();
use JSON;
use Moonpig::UserAgent;

my $JSON = JSON->new;

# my $WIDGET_FACTORY = HTML::Widget::Factory->new;
# sub widget { $WIDGET_FACTORY; }

my $BASE_URI = $ENV{MOONPIG_URI} || die "no MOONPIG_URI";

my $ua = Moonpig::UserAgent->new({ base_uri => $BASE_URI });

sub mp_last_response {
  my ($self) = @_;
  return $self->{__last_mp_response};
}

sub mp_request {
  my ($self, $method, $path, $arg, $extra_arg) = @_;
  $extra_arg //= {};

  undef $self->{__last_mp_response};
  $extra_arg->{response} = \ $self->{__last_mp_response};

  $ua->mp_request($method, $path, $arg, $extra_arg);
}

sub mp_ledger_path {
  my ($self, $id) = @_;
  my $type = ($id =~ /:/) ? 'xid' : 'guid';
  return(sprintf '/ledger/by-%s/%s', $type, $id);
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
