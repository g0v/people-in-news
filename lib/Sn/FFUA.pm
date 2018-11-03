use v5.18;

package Sn::FFUA {
    use strict;
    use warnings;

    use Firefox::Marionette;
    use Mojo::DOM;

    use Moo;

    has firefox => (
        is => 'lazy',
    );

    no Moo;

    sub _build_firefox {
        return Firefox::Marionette->new( visible => 1 );
    }

    sub fetch {
        my ($self, $url) = @_;

        my $firefox = $self->firefox;

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
