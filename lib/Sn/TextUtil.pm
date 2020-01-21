package Sn::TextUtil {
    use strict;
    use warnings;

    our @EXPORT = ('looks_like_similar_host', 'looks_like_sns_url');
    
    sub looks_like_similar_host {
        my @host = map {
            s/.+\.([^\.]+)$/$1/r
        } map {
            s/\.((com|org|net)(\.tw)?|(co|ne|or)\.(jp|uk))$//r
        } @_;
        return $host[0] eq $host[1]
    }

    sub looks_like_sns_url {
        my ($url) = @_;
        my $prefix = join(
            '|',
            map { qr(\Q$_\E) }
            'accounts.google.com/ServiceLogin',
            'www.linkedin.com/uas',
            'twitter.com/intent/tweet',
        );

        return $url =~ m{ \A https:// (?: $prefix ) }xo;
    }
}
1;
