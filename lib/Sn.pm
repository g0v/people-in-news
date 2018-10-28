package Sn;
use v5.18;

use strict;
use warnings;
use Encode qw(decode_utf8);
use List::Util qw(uniqstr);

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

sub read_string_list {
    my ($fn) = @_;
    my @lines = grep {
        s/\A#.+\z//;
        s/\A\s+//;
        s/\s+\z//;

        $_ ne ''
    } @{ readlines_utf8($fn) };

    return \@lines;
}

sub extract_substrings {
    my ($texts) = @_;

    state @extractors;
    unless (@extractors) {
        @extractors = map {
            my $fn = $_;
            my $name = substr($fn, 11) =~ s/\.txt$//r;
            Sn::Extractor->new(
                name => $name,
                substrings => [ uniqstr map { split /\t+/ } @{ read_string_list($fn) } ],
            );
        } glob('etc/substr-*.txt');
    }

    my %extracts = map { $_->name => $_->extract($texts) } @extractors;
    return \%extracts;
}

1;
