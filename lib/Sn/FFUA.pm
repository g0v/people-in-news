package Sn::FFUA {
    use strict;
    use warning;

    use Firefox::Marionette;
    use Mojo::DOM;

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
};

1;
