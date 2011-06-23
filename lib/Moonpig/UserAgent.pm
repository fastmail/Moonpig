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
    require LWP::UserAgent;
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
    return undef if $res->code == 404;
  } elsif ($method eq'post') {
    my $payload = $self->encode($arg);

    $res = $self->post(
      $target,
      'Content-Type' => 'application/json',
      Content => $payload,
    );
  }

  # eventually there should be exceptions here for all 2xx codes
  unless ($res->code == 200) {
    my $error = sprintf "unexpected response from Moonpig:\n"
                      . "request : %s %s\n"
                      . "response: \n%s", uc $method, $target, $res->as_string;
    die $error;
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

sub set_test_callback {
  my ($self, $cb) = @_;
  $self->UA->add_handler(request_send => $cb);
}

sub clear_test_callback {
  my ($self) = @_;
  $self->UA->remove_handler('request_send');
}

1;
