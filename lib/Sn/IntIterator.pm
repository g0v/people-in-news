package Sn::IntIterator;
use Moo;
with 'Sn::Iterator';

has from => (
    is => 'ro',
    required => 1,
);

has 'until' => (
    is => 'ro',
    required => 1
);

has _current => (
    is => 'rw',
);

sub reify {
    my ($self) = @_;

    my @chunk;
    my $x = $self->_current() // int( $self->from() );
    while (@chunk < 100 and $x < $self->until) {
        push @chunk, $x;
        $x++;
    }
    $self->_current($x);
    return \@chunk;
}

1;
