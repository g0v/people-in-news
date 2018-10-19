package Sn;
use v5.18;

use strict;
use warnings;

use Sn::TX;

sub ts_now {
    my @t = localtime();
    return sprintf('%04d%02d%02d%02d%02d%02d', $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

sub readlines {
    my ($fn) = @_;

    open my $fh, '<', $fn;
    my @lines = map { chomp; $_ } <$fh>;
    close($fh);

    return \@lines;
}

sub readlines_utf8 {
    my ($fn) = @_;

    open my $fh, '<', $fn;
    my @lines = map { chomp; decode_utf8($_); } <$fh>;
    close($fh);

    return \@lines;
}

1;

