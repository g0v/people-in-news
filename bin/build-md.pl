#!/usr/bin/env perl
use Sn;
use Importer 'Sn::Util' => qw( nsort_by sort_by uniq_by );

use File::Basename qw(basename);
use Encode qw(encode_utf8);
use Getopt::Long qw(GetOptions);
use JSON qw(decode_json);

sub build_md {
    my ($page, $output) = @_;

    my $next_link_id = 1;
    my %link_id;
    my @link_url;

    my $md = "";
    for my $obj (nsort_by { -1 * (keys %{$page->{$_}} ) } keys %$page) {
        my %articles;

        for my $name (nsort_by { -1 * @{$page->{$obj}{$_}} } keys %{$page->{$obj}}) {
            @{$articles{$name}} = sort_by { $_->{title} } map {
                $_->{title} =~ s/\A\s+//;
                $_->{title} =~ s/\s+\z//;
                $_;
            } uniq_by { $_->{content_text} } grep { not exists $link_id{$_->{url}} } @{ $page->{$obj}{$name} };

            for my $d (@{$articles{$name}}) {
                my $link_id = $link_id{ $d->{url} } //= $next_link_id++;
                $link_url[$link_id] //= $d->{url};
            }
        }

        next if 0 == keys %articles;

        for my $name (nsort_by { -1 * @{$articles{$_}}} keys %articles) {
            next unless @{$articles{$name}} > 0;

            $md .= "### $obj :: $name\n\n";
            for my $d (@{$articles{$name}}) {
                my $link_id = $link_id{ $d->{url} };
                $md .= "- [$d->{title}][$link_id]\n";
            }
            $md .= "\n";
        }
        $md .= "\n";
    }

    $md .= "\n";
    for my $id (1..$next_link_id-1) {
        $md .= "[$id]: " . $link_url[$id] . "\n";
    };
    $md .= "\n";

    open my $fh, '>', $output;
    say $fh encode_utf8($md);
    close($fh);
}

## main
my %opts;
GetOptions(
    \%opts,
    "o=s",
    "i=s",
);
die "-i <DIR> is needed" unless -d $opts{i};
die "-o <DIR> is needed" unless -d $opts{o};

my @input = glob "$opts{i}/*.jsonl";
for my $file (@input) {
    my $output = $opts{o} . '/' . ( basename($file) =~ s/\.jsonl$/.md/r );
    next if -f $output;

    my %page;

    open my $fh, '<', $file;
    while (<$fh>) {
        chomp;
        my $d = decode_json($_);
        for my $obj (@{$d->{substrings}{events} //[]}, @{$d->{substrings}{things} //[]}) {
            for my $name (@{$d->{substrings}{people} //[]}) {
                push @{$page{$obj}{$name}}, $d;
            }
        }
    }
    close($fh);

    build_md(\%page, $output);
}
