package Sn::Seen {
    use Moo;
    use Algorithm::BloomFilter;
    use Types::Standard qw(Str Bool InstanceOf);

    has store => ( is => 'ro', isa => Str, required => 1 );

    has bloomfilter => (
        is => 'lazy',
        isa => InstanceOf['Algorithm::BloomFilter'],
        required => 1,
    );

    sub _build_bloomfilter {
        my ($self) = @_;
        my $o;

        my $f = $self->store;
        if (-f $f) {
            open my $fh, '<', $f;
            my $x = do { local $/; <$fh> };
            close($fh);
            $o = Algorithm::BloomFilter->deserialize($x);
        } else {
            $o = Algorithm::BloomFilter->new(50000000, 10);
        }

        return $o;
    }

    sub test {
        my ($self, $thing) = @_;
        return $self->bloomfilter->test($thing);
    }

    sub add {
        my ($self, @stuff) = @_;
        $self->bloomfilter->add(@stuff);
        return $self;
    }

    sub save {
        my ($self) = @_;

        my $x = $self->bloomfilter->serialize;
        open my $fh, '>', $self->store;
        print $fh $x;
        close($fh);

        return $self;
    }
};

1;
