# Moonpig Billing

The Moonpig billing system is a highly modular, configurable, and extensible
system for tracking customer accounts, credit, charges, and all that sort of
stuff.  It was designed for the needs of Pobox and Listbox, but should be
capable of handling many other billing scenarios.

# How to Use Moonpig Billing

**First off**: decide whether you really think this is a good idea.  Moonpig is
a really nice piece of software, but it's still sort of laboratory quality.  It
works very well for the needs of its original designers, who know it inside and
out.  If you don't know it that well, you're going to have to learn the Moonpig
way of thinking about billing.  This is a cool thing to learn, but it means
that using Moonpig isn't just a matter of "install, configure, profit."

Further, there is no stability guarantee.  If a backward-incompatible change is
needed to improve the system, *it will be made, possibly without advance
warning.*

If you decide you really want to use Moonpig, and are willing to swallow these
conditions, look at `doc/INSTALL` for basic installation instructions.  That
will install the code on your system.  The installation instructions don't
cover configuring Moonpig or getting it running as a service yet.  See what I
mean about laboratory quality?

# How to Contribute to Moonpig Billing

The Moonpig billing system is licensed under the three-clause BSD license.
This basically means that you can do whatever you want as long as you credit
IC Group, Inc. as the source of the Moonpig billing system and don't use our
name for anything other than giving us credit.  That means you can hack on it
for your own purposes, and you can certainly send in patches to us.

We haven't gotten any patches yet, but we will require contributor licensing
agreements from contributors.
