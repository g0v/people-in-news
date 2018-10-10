package Sn::TX {
    use Moo;
    use Types::Standard qw(Str Bool InstanceOf);
    use Types::URI -all;

    use Mojo::DOM;

    has uri => (
        is => 'ro',
        isa => Uri,
        required => 1
    );

    has title => (
        is => 'ro',
        isa => Str,
        required => 1,
    );

    has dom => (
        is => 'ro',
        isa => InstanceOf['Mojo::DOM'],
        required => 1
    );

    sub no_content {
        my ($self) = @_;
        return $self->dom->find('html')->first->text eq "";
    }
};

1;
