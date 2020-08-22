package Sn::Iterator;
use v5.18;
use Moo::Role;

requires 'reify';

has _cursor => (
    is => "rw",
    predicate => 1,
);

has reified => (
    is => "rw",
    default => sub { [ ] }
);

has mapper => (
    is => "rw",
    predicate => 1,
);

use overload '&{}' => sub {
    my $self = $_[0];
    return sub { $self->next() }
};

sub next {
    my ($self) = @_;

    if ( !$self->_has_cursor || $self->_cursor == @{$self->reified}) {
        my $items = $self->reify;

        if ($self->has_mapper) {
            my $code = $self->mapper;
            @$items = map { $code->($_) } @$items;
        }

        $self->reified($items);
        $self->_cursor(0);
    }

    my $i = $self->_cursor;
    $self->_cursor($i+1);
    return $self->reified->[$i];
}

sub exhaust {
    my ($self) = @_;
    my ($o, @ret);
    while(defined($o = $self->next())) {
        push @ret, $o;
    }
    return \@ret;
}

sub map {
    my ($self, $mapper) = @_;
    my $class = ref($self);
    my $new_iter = bless +{ %$self }, $class;
    $new_iter->mapper($mapper);
    return $new_iter;
}

1;
