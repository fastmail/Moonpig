package Moonpig::Email::MIME::Kit;

use Moose;
extends 'Email::MIME::Kit';

use Email::MIME::Kit 2 ();

use namespace::autoclean;

package Moonpig::Util::Text::Template {

  use parent 'Text::Template';

  use Encode ();

  sub append_text_to_output {
    my ($self, %arg) = @_;
    my $encoded = Encode::encode('utf-8', $arg{text});
    return $self->SUPER::append_text_to_output(
      %arg,
      text => $encoded,
    );
  }

  $INC{'Moonpig/Util/Text/Template.pm'} = 1;
}

around read_manifest => sub {
  my ($orig, $self, @rest) = @_;
  my $manifest = $self->$orig(@rest);

  unless (exists $manifest->{renderer}) {
    $manifest->{renderer} = [
      "Text::Template" => {
        template_class => 'Moonpig::Util::Text::Template',
        template_args  => { DELIMITERS => [ "{{", "}}" ] }
      }
    ];
  }

  return $manifest;
};

__PACKAGE__->meta->make_immutable;
