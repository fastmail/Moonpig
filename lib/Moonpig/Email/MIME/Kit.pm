package Moonpig::Email::MIME::Kit;

use Moose;
extends 'Email::MIME::Kit';

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

__PACKAGE__->meta->make_immutable;
