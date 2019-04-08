package Sn::TX {
    use Moo;
    use Types::Standard qw(InstanceOf);

    has req => (
        is => 'ro',
        isa => InstanceOf['Mojo::Message::Request'],
        required => 1
    );

    has res => (
        is => 'ro',
        isa => InstanceOf['Mojo::Message::Response'],
        required => 1
    );
};

1;
