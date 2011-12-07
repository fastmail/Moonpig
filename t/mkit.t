use strict;
use warnings;
use Test::More;

### THIS TEST VIOLATES ENCAPSULATION
### BECAUSE DOING THAT IS A LOT EASIER
### THAN BUILDING TEST KITS AND ALLTHAT
### KIND OF STUFF JUST TO TEST THE GUTS
###                  -- rjbs, 2011-12-07
use Moonpig::MKits;

{
  my $mkits = Moonpig::MKits->new;
  my $kitname = $mkits->_kitname_for(invoice => {});
  is($kitname, 'invoice', "no overrides");
}

{
  my $mkits = Moonpig::MKits->new;
  {
    $mkits->add_override('*' => sub { return });
    my $kitname = $mkits->_kitname_for(invoice => {});
    is($kitname, 'invoice', "global return() override");
  }

  {
    $mkits->add_override('*' => sub { return 'zooch' });
    my $kitname = $mkits->_kitname_for(invoice => {});
    is($kitname, 'zooch', "global return(q{zooch}) override");
  }
}

{
  my $mkits = Moonpig::MKits->new;
  {
    $mkits->add_override('glort' => sub { return 'zooch' });
    my $kitname = $mkits->_kitname_for(invoice => {});
    is($kitname, 'invoice', "override for other name ignored");
  }

  {
    $mkits->add_override('invoice' => sub { return 'bling' });
    my $kitname = $mkits->_kitname_for(invoice => {});
    is($kitname, 'bling', "override for this name matched");
  }
}

done_testing;
