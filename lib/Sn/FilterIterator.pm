package Sn::FilterIterator;
use v5.18;
use Moo;
with 'Sn::Iterator';

has iterator => (
    is => "ro",
    required => 1,
);

has reject_if => (
    is => "ro",
    required => 1,
);

sub reify {
    my ($self) = @_;

    my $iter = $self->iterator;
    my $reject = $self->reject_if;

    my @chunk;
    my $o = $iter->next;
    while (@chunk < 10 and defined($o)) {
        push(@chunk, $o) unless $reject->($o);
        $o = $iter->next;
    }

    return \@chunk;
}

1;
