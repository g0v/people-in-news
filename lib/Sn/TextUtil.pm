package Sn::TextUtil {
    use strict;
    use warnings;
    our @EXPORT = ('looks_like_similar_host');
    
    sub looks_like_similar_host {
        my @host = map {
            s/.+\.([^\.]+)$/$1/r
        } map {
            s/\.((com|org|net)(\.tw)?|(co|ne|or)\.(jp|uk))$//r
        } @_;
        return $host[0] eq $host[1]
    }
}
1;
