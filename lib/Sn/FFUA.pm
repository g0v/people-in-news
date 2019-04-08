use v5.18;

package Sn::FFUA {
    use strict;
    use warnings;

    use Firefox::Marionette;
    use Encode qw< encode_utf8 >;
    use Mojo::Message::Request;
    use Mojo::Message::Response;
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

        my $req = Mojo::Message::Request->new;
        $req->url->parse($url);
        $req->method('GET');

        my $res = Mojo::Message::Response->new;
        $res->headers->content_type('text/html');
        $res->body( encode_utf8 $html );

        return Sn::TX->new(
            req => $req,
            res => $res,
        )
    }
};

1;
