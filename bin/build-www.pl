#!/usr/bin/env perl
use Sn;

use File::Basename qw(basename);
use Getopt::Long qw(GetOptions);
use Text::Markdown qw(markdown);
use Encode qw(decode_utf8 encode_utf8);
use File::Slurp qw(read_file write_file);
use MCE::Loop;

## main
my %opts;
GetOptions(
    \%opts,
    "force|f",
    "i=s",
    "o=s",
);
die "-i <DIR> is needed" unless -d $opts{i};
die "-o <DIR> is needed" unless -d $opts{o};

my @things = sort {
    $b->{mtime} <=> $a->{mtime}
} map {
    my $input = $_;
    my $output = $opts{o} . '/' . (basename($input) =~ s/\.md\z/.html/r);
    my $input_mtime = (stat($input))[7];
    ( (-f $output) && ($input_mtime <= (stat($output))[7]) ) ? () : (+{
        input => $input, output => $output, mtime => $input_mtime
    })
} glob("$opts{i}/*.md");

my $toc_js_script = <<'JS';
<script type="text/javascript">
(() => {
  const headers = document.querySelectorAll('h2');
  for (const el of headers) {
    el.id = el.textContent;
  }
  const links = Array.from(headers, el => el.textContent)
                     .map(t => `<li><a href="#${t}">${t}</a></li>`)
                     .join('');
  document.body.insertAdjacentHTML('afterbegin', `<ul>${links}</ul>`);
})();
</script>
JS

for (@things){
    my $input = $_->{input};
    my $output = $_->{output};

    say "$input => $output";
    my $text = decode_utf8( scalar read_file($input) );
    my $html = "<!doctype html>\n" .
        '<html><head><meta charset="utf-8" /></head><body>' .
        markdown($text) .
        $toc_js_script .
        '</body></html>';

    write_file($output, encode_utf8($html));
}
