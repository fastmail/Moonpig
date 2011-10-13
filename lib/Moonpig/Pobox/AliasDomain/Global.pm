package Moonpig::Pobox::AliasDomain::Global;
# ABSTRACT: Stand-in for when Pobox::AliasDomain::Global is missing

my $padg_available = eval { require Pobox::AliasDomain::Global };

sub get {
  my ($class) = @_;
  if ($padg_available) {
    return Pobox::AliasDomain::Global->get();
  } else {
    # fake it
    # This was the contents of icg_main.alias_domains as of 2011-10-12
    map Moonpig::Pobox::AliasDomain::Global::Name->new($_),
      qw(foobox.com foobox.net immerbox.com immermail.com
         lifetimeaddress.com mailzone.com onepost.net penguinmail.com
         permanentmail.com pobox.com rightbox.com siemprebox.com
         siempremail.com topicbox.com veribox.net );
  }
}

{
  package Moonpig::Pobox::AliasDomain::Global::Name;

  sub new {
    my ($class, $name) = @_;
    bless \$name => $class;
  }

  sub name {
    my ($self) = @_;
    return $$self;
  }
}

1;
