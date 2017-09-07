package Moonpig::Email::MIME::Kit;

use Moose;
extends 'Email::MIME::Kit';

use Digest::MD5 ();
use Email::Date::Format qw(email_gmdate);
use Email::MIME::Kit 2 ();

use namespace::autoclean;

around read_manifest => sub {
  my ($orig, $self, @rest) = @_;
  my $manifest = $self->$orig(@rest);

  unless (exists $manifest->{renderer}) {
    $manifest->{renderer} = [
      "Text::Template" => {
        template_args  => { DELIMITERS => [ "{{", "}}" ] }
      }
    ];
  }

  return $manifest;
};

has kitname => (
  is       => 'ro',
  required => 1,
);

around assemble => sub {
  my ($orig, $self, @rest) = @_;
  my $email = $self->$orig(@rest);

  if ( Moonpig->env->does('Moonpig::Role::Env::WithMockedTime') ) {
    $email->header_set(Date => email_gmdate( Moonpig->env->now->epoch ) );
  }

  $email->header_set('Moonpig-MKit' => Digest::MD5::md5_hex($self->kitname));

  return $email;
};

__PACKAGE__->meta->make_immutable;
