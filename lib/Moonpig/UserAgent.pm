package Moonpig::UserAgent;
use Moose;

our $VERSION = 0.20110525;

use HTTP::Request;
use LWP::UserAgent;
use URI;


has agent_string => (
  is => 'ro',
  isa => 'Str',
  default => sub { join "/", __PACKAGE__, $VERSION },
);

has UA => (
  is => 'ro',
  lazy => 1,
  default => sub {
    LWP::UserAgent->new(
      agent      => $_[0]->agent_string,
      keep_alive => 1,
    );
  },
  handles => [ qw(get post) ],
);

has base_uri => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has JSON => (
  is => 'ro',
  default => sub {
    require JSON;
    JSON->new;
  },
  handles => [ qw(encode decode) ],
);

sub mp_time {
  my ($self) = @_;
  my $time = $self->mp_request(GET => '/time')->{now};
  return $time;
}

sub mp_get {
  my $self = shift;
  $self->mp_request('get', @_);
}

sub mp_post {
  my $self = shift;
  $self->mp_request('post', @_);
}

sub mp_request {
  my ($self, $method, $path, $arg, $extra_arg) = @_;
  $extra_arg //= {};

  my $target = $self->qualify_path($path);
  $method = lc $method;

  my $res;

  if ($method eq 'get') {
    $res = $self->get($target);
    return undef if $res->code == 404;
  } elsif ($method eq 'post' or $method eq 'put') {
    my $payload = $self->encode($arg);

    my $req = HTTP::Request->new(
      uc $method,
      $target,
      [ 'Content-Type' => 'application/json' ],
      $payload,
    );

    $res = $self->UA->request($req);
  } else {
    confess "do not know how to make $method-method request";
  }

  # eventually there should be exceptions here for all 2xx codes
  unless ($res->code == 200) {
    my $error = sprintf "unexpected response from Moonpig:\n"
                      . "request : %s %s\n"
                      . "response: \n%s", uc $method, $target, $res->as_string;
    die $error;
  }

  ${ $extra_arg->{response} } = $res if $extra_arg->{response};

  return $self->decode($res->content)->{value};
}

sub qualify_path {
  my ($self, $path) = @_;

  # If the path is actually a complete URL, use it verbatim;
  # otherwise qualify it with base_uri.
  return defined URI->new($path)->scheme ? URI->new($path)
    : URI->new($self->base_uri . $path);
}

sub set_test_callback {
  my ($self, $cb) = @_;
  $self->UA->add_handler(request_send => $cb);
}

sub clear_test_callback {
  my ($self) = @_;
  $self->UA->remove_handler('request_send');
}

1;
