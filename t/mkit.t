use Test::Routine;
use Test::More;
use Test::Routine::Util;

use Moonpig::Logger::Test;
use t::lib::TestEnv;

with(
  'Moonpig::Test::Role::LedgerTester',
);

### THIS TEST VIOLATES ENCAPSULATION
### BECAUSE DOING THAT IS A LOT EASIER
### THAN BUILDING TEST KITS AND ALLTHAT
### KIND OF STUFF JUST TO TEST THE GUTS
###                  -- rjbs, 2011-12-07
use Moonpig::MKits;

test "basic mkit overrides" => sub {
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
      $mkits->add_override('*' => sub { return 'generic' });
      my $kitname = $mkits->_kitname_for(invoice => {});
      is($kitname, 'generic', "global return(q{generic}) override");

      my $email = $mkits->assemble_kit(invoice => {
        subject       => "Test",
        to_addresses  => [ q{example@example.com} ],
        body          => "This should be generic.\n",
      });

      is(
        $email->header('Moonpig-MKit'),
        Digest::MD5::md5_hex('generic'),
        "we respect override in setting Moonpig-MKit",
      );
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
};

run_me;
done_testing;
