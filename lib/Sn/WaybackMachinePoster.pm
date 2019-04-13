package Sn::WaybackMachinePoster;
use strict;
use warnings;

use Mojo::UserAgent;

sub post {
    my ($self, $url) = @_;
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->get('https://web.archive.org/save/' . $url)->result;
    return $res->is_success ? 1 : 0;
}

1;
