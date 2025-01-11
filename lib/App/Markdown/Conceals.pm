package App::Markdown::Conceals;
use strict;
use warnings;
use Data::Dump      qw(dump);
use Text::CharWidth qw(mbswidth mblen mbwidth);
use Exporter 'import';
our @EXPORT_OK = qw(
  get_conceals
  concealed_chars
);

my $rB = qr/(?:[^\]]|\\\])/;
my $rb = qr/(?:[^)]|\\\))/;

my @CONCEALS = (
  {
    name  => "Bold",
    regex => qr/(?:(?<!\\)\*){2,} (?!\s) | (?<![\s]) (?:(?<!\\)\*){2,}/mxs,
  },
  {
    name  => "Highlight",
    regex => qr/(?:(?<!\\)\=){2} (?!\s) | (?<![\s]) (?:(?<!\\)\=){2}/mxs,
  },
  {
    name  => "wiki",
    regex => qr/(?:(?<!\\)\[){2} (?!\[) | (?<!\]) (?:(?<!\\)\]){2}/mxs,
  },
  {
    name  => "inline_code",
    regex => qr/(?<!\\)\`/mxs,
  },
  {
    name  => "inline_math",
    regex => qr/(?<!\\)\$/mxs,
  },
  {
    name    => "extenal_link",
    regex   => qr/\[($rB*)\]\($rb*\)/,
    display => sub {
      my $cap = shift or return "";
      $cap =~ s/\[(${rB}*)\]\(${rb}*\)/$1/;
      return $cap;
    },
  },
  {
    name    => "wiki_link",
    regex   => qr/\[{2}(${rB}*)\]{2}/,
    display => sub {
      my $cap = shift or return "";
      $cap =~ s/\[{2}(${rB}*)\]{2}/[$1]/;
      return $cap;
    },
  },
  {
    name    => "link_ref",
    regex   => qr/\[($rB*)\]\[$rB*\]/,
    display => sub {
      my $cap = shift or return "";
      $cap =~ s/\[($rB*)\]\[$rB*\]/$1/;
      return $cap;
    },
  },
);

sub get_conceals {
  my $opts = shift;
  if ( $opts->{tonewsboart} ) {
    return [
      @CONCEALS,
      {
        name    => "newsboat_image",
        regex   => qr/\[image \d+ \(link \#\)\]/xms,
        display => sub { shift() =~ s/\A\[|\]\z//mxsr },
      },
      {
        name  => "newsboat_highlight",
        regex => qr/〚|〛/,
      }
    ];
  }
  return \@CONCEALS;
}

sub concealed_chars {
  my $text     = shift;
  my @conceals = @{ get_conceals() };
  return 0 if scalar @conceals == 0;

  my $text_temp = $text;
  for (@conceals) {
    my $regex   = $_->{regex};
    my $display = $_->{display} // sub { "" };
    $text_temp =~ s/($regex)/$display->($1)/emxgs;
  }

  return mbswidth($text) - mbswidth($text_temp);
}

1;
