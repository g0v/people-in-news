package Sn;
use v5.18;

use strict;
use strict;
use warnings;
use Firefox::Marionette;
use Mojo::DOM;

use Sn::TX;

sub fetch {
    my ($url) = @_;
    state %foxes;

    my $firefox =  $foxes{$$} //= Firefox::Marionette->new();
    $firefox->go($url);

    my $html = $firefox->html();
    return Sn::TX->new(
        uri => $firefox->uri(),
        title => $firefox->title(),
        dom => Mojo::DOM->new($html),
    )
}


1;

