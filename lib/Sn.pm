package Sn;
use v5.18;

use strict;
use strict;
use warnings;
use Firefox::Marionette;
use Mojo::DOM;

use Sn::TX;

sub ts_now {
    my @t = localtime();
    return sprintf('%04d%02d%02d%02d%02d%02d', $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

sub fetch {
    my ($url) = @_;
    state $firefox = Firefox::Marionette->new();
    $firefox->go($url);
    my $sleeps = 0;
    sleep 1 while ($sleeps++ < 10 && (! $firefox->interactive()));
    return unless $firefox->interactive();

    my $html = $firefox->html();
    return Sn::TX->new(
        uri => $firefox->uri(),
        title => $firefox->title(),
        dom => Mojo::DOM->new($html),
    )
}


1;

