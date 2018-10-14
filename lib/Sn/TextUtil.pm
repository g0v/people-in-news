package Sn::TextUtil {
    use strict;
    use warnings;

    use Unicode::UCD qw(charscript);

    use Exporter 'import';
    use Module::Functions;
    our @EXPORT = get_public_functions();
    
    sub normalize_whitespace {
        local $_ = $_[0];
        s/[\t ]+/ /g;
        s/\A\s+//;
        s/\s+\z//;
        return $_;
    }

    sub remove_spaces {
        return grep { ! /\A\s*\z/u } @_;
    }
    
    sub segmentation_by_script($) {
        my $str = normalize_whitespace($_[0]);
        my @tokens;
        my @chars = grep { defined($_) } split "", $str;
        return () unless @chars;

        my $t = shift(@chars);
        my $s = charscript(ord($t));
        while (my $char = shift @chars) {
            my $_s = charscript(ord($char));
            if ($_s eq $s) {
                $t .= $char;
            } else {
                push @tokens, $t;
                $s = $_s;
                $t = $char;
            }
        }
        push @tokens, $t;
        return remove_spaces map { $_ = normalize_whitespace($_) } @tokens;
    }
}
1;