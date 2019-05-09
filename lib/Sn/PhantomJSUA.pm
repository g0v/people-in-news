use v5.18;

package Sn::PhantomJSUA {
    use strict;
    use warnings;

    use WWW::Mechanize::PhantomJS;

    use Encode qw< encode_utf8 >;
    use Mojo::Message::Request;
    use Mojo::Message::Response;
    use Mojo::DOM;
    use Moo;

    has ua => (
        is => 'lazy',
    );

    no Moo;

    sub _build_ua {
        return WWW::Mechanize::PhantomJS->new;
    }

    sub fetch {
        my ($self, $url) = @_;

        my $ua = $self->ua;

        $ua->get($url);
        sleep(10);

        my $req = Mojo::Message::Request->new;
        $req->url->parse($url);
        $req->method('GET');

        my $html = $ua->content();

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
