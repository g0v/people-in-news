#!/usr/bin/env perl
use v5.26;
use strict;
use warnings;
use XML::FeedPP;
use Getopt::Long qw(GetOptions);

use Sn::WaybackMachinePoster;

## main
my %opts;
GetOptions(
    \%opts,
    "atom=s",
);
die "--atom <PATH> is needed" unless  $opts{atom} && -f $opts{atom};

my $feed = XML::FeedPP::Atom->new( $opts{atom} );
my @items = $feed->get_item();
for my $item ( @items ) {
    my $url = $item->link;
    Sn::WaybackMachinePoster->post($url);
    say "POSTED: $url";
}
