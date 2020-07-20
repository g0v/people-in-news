#!/usr/bin/env perl
use Sn;
use Sn::WaybackMachinePoster;

use XML::FeedPP;
use Getopt::Long qw(GetOptions);

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
