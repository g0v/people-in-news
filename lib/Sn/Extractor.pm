package Sn::Extractor {
    use Moo;
    use Types::Standard qw(ArrayRef Str);

    has name => (
        is => 'ro',
        isa => Str,
        required => 1,
    );

    has substrings => (
        is => 'ro',
        isa => ArrayRef[Str],
        required => 1,
    );

    sub extract {
        my ($self, $texts) = @_;

        my @extracted;
        for my $s (@{$self->substrings}) {
            for my $txt (@$texts) {
                if (index($txt, $s) >= 0) {
                    push @extracted, $s;
                    last;
                }
            }
        }

        return \@extracted;
    }
};

1;
