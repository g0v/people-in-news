package Sn::KnownNames {
    use Moo;
    use Encode qw(decode);
    use Types::Standard qw(ArrayRef Str);

    has input => (
        is => 'ro',
        isa => ArrayRef[Str],
        required => 1,
    );

    has known_names => (
        is => 'lazy',
        isa => ArrayRef[Str],
        required => 1,
    );

    sub _build_known_names {
        my ($self) = @_;
        my @ret;
        for my $fn (@{$self->input}) {
            open my $fh, '<', $fn;
            push @ret, map { chomp; decode('utf-8-strict', $_) } <$fh>;        
        }
        return \@ret;
    }
};

1;
