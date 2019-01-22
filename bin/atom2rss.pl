#!/usr/bin/env perl
use strict;
use warnings;
use autodie;
use XML::FeedPP;

my ($file_atom, $file_rss) = @ARGV;

my $feed = XML::FeedPP::RSS->new();
$feed->merge($file_atom);

open my $fh, '>', $file_rss;
print $fh $feed->to_string;
