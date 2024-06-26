requires 'Algorithm::BloomFilter' => '0.02';
requires 'Chart::Plotly';
requires 'Elastijk';
requires 'File::Next';
requires 'File::Slurp';
requires 'HTML::ExtractContent';
requires 'HTTP::Date';
requires 'IO::Socket::SSL'        => '2.060';
requires 'JSON' => 4;
requires 'JSON::Feed';
requires 'MCE::Loop';
requires 'Module::Functions';
requires 'Mojo::UserAgent';
requires 'Moo';
requires 'Net::Graphite';
requires 'NewsExtractor', 'v0.41.0';
requires 'PerlIO::via::gzip';
requires 'Regexp::Trie';
requires 'String::Trim';
requires 'Text::Markdown';
requires 'Text::Util::Chinese', '0.07';
requires 'Time::Moment';
requires 'Try::Tiny';
requires 'Type::Tiny';
requires 'Types::URI';
requires 'URI';
requires 'WWW::Mechanize::Chrome';
requires 'WWW::Mechanize::PhantomJS';
requires 'XML::FeedPP';
requires 'Importer';

on test => sub {
   requires 'Test2::Harness';
};

on development => sub {
    requires 'Firefox::Marionette'    => '0.66';
};
