package Moonpig::UserAgent;
use Moose;
use URI;
our $VERSION = 0.20110525;

has agent_string => (
  is => 'ro',
  isa => 'Str',
  default => sub { join "/", __PACKAGE__, $VERSION },
);

has UA => (
  is => 'ro',
  lazy => 1,
  default => sub {
    require 'LWP::UserAgent';
    LWP::UserAgent->new($_[0]->agent_string);
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
  my ($self, $path) = @_;
  $self->mp_request('get', $path);
}

sub mp_post {
  my ($self, $path, $arg) = @_;
  $self->mp_request('post', $path, $arg);
}

sub mp_request {
  my ($self, $method, $path, $arg) = @_;

  my $target = $self->qualify_path($path);
  $method = lc $method;

  my $res;

  if ($method eq 'get') {
    $res = $self->get($target);
  } elsif ($method eq'post') {
    my $payload = $self->encode($arg);

    $res = $self->post(
      $target,
      'Content-Type' => 'application/json',
      Content => $payload,
    );
  }

  return undef if $res->code == 404;

  unless ($res->code == 200) {
    die "unexpected response from moonpig:\n" . $res->as_string;
  }

  return $self->decode($res->content);
}

sub qualify_path {
  my ($self, $path) = @_;

  # If the path is actually a complete URL, use it verbatim;
  # otherwise qualify it with base_uri.
  return defined URI->new($path)->scheme ? URI->new($path)
    : URI->new($self->base_uri . $path);
}

1;
