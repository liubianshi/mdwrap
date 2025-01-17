package App::Markdown::Utils;
use strict;
use warnings;
use Exporter 'import';
use List::Util qw(any none);
our @EXPORT_OK = qw(
  get_indent_prefix
  is_table_line
  is_header_line
  is_list_first_line
  is_link_list
  is_definition_header
  format_quote_line
  _char_attr
  indent
);

sub is_table_line {
  my $str = shift;
  return 1 if $str =~ m{^\s*(\||\+[-=])}xms;
  return 0;
}

sub is_header_line {
  return "Setext" if m/^ \s* (?:\={3,}|\-{3,}) \s* $/mxs;
  return "Atx"    if m/^ \s* [#]+ \s+/mxs;
  return;
}

sub is_list_first_line {
  my $str = shift;
  return scalar( $str =~ m/^ \s* (?:[-•*+]|\d+\.) \s/mxs );
}

sub is_link_list {
  my $str = shift;
  return scalar( $str =~ m/^ \s* \[ [^[\]]+ \] \: \s/mxs );
}

sub is_definition_header {
  my $str = shift;
  return scalar m/^ \s* [~:] \s \s* /mxs;
}

sub is_code_block {
  my $str = shift;
  return $str =~ m/\A\h{4}/;
}

sub indent {
  my $str         = shift;
  my $prefix      = "";
  my $todo_regex  = qr/\[\w?\]\s+/xms;
  my $list_regex  = qr/(?:[-•*+]|\d+\.) \s+ (?:$todo_regex\s)?/xms;
  my $def_regex   = qr/(?:\: \s+)/xms;
  my $quote_regex = qr/(?:\>\s)+/;
  if ( $str =~ m{\A  (\s*) ($quote_regex?) ((?:$list_regex|$def_regex)?) }mxs ) {
    $prefix = $1 . $2 . ( " " x length($3) );
  }
  return $prefix;
}

sub format_quote_line {
  my $line               = shift;
  my $prefix             = "";
  my $continue_space_num = 0;

  for my $i ( 0 .. length($line) ) {
    my $char = substr( $line, $i, 1 );
    if ( $char eq ">" ) {
      $prefix .= "> ";
      $continue_space_num = 0;
    }
    elsif ( $char =~ m/\h/ ) {
      $continue_space_num++;
    }
    else {
      $line = substr( $line, $continue_space_num >= 4 ? $i - 4 : $i );
      last;
    }
  }

  return ( $prefix, $line );
}

sub _char_attr {
  my $u                               = shift;
  my @punctuations_forbit_break_after = (
    0x2014,    # —  Em dash
    0x2018,    # ‘ Left single quotation mark
    0x201c,    # “ Left double quotation mark
    0x3008,    # 〈 Left angle bracket
    0x300a,    # 《 Left double angle bracket
    0x300c,    # 「 Left corner bracket
    0x300e,    # 『 Left white corner bracket
    0x3010,    # 【 Left black lenticular bracket
    0x3014,    # 〔 Left tortoise shell bracket
    0x3016,    # 〖 Left white lenticular bracket
    0x301d,    # 〝 Reversed double prime quotation mark
    0xfe59,    # ﹙ Small left parenthesis
    0xfe5b,    # ﹛ Small left curly bracket
    0xfe5d,    # ﹝ Small left tortoise shell bracket
    0xff04,    # ＄ Fullwidth dollar sign
    0xff08,    # （ Fullwidth left parenthesis
    0xff0e,    # ． Fullwidth full stop
    0xff3b,    # ［ Fullwidth left square bracket
    0xff5b,    # ｛ Fullwidth left curly bracket
    0xffe1,    # ￡ Fullwidth pound sign
    0xffe5,    # ￥ Fullwidth yen sign
  );
  my @punctuations_forbit_break_before = (
    0x2014,    # —  Em dash
    0x2019,    # ’  Right single quotation mark
    0x201d,    # ”  Right double quotation mark
    0x2026,    # …  Horizontal ellipsis
    0x2030,    # ‰  Per mille sign
    0x2032,    # ′  Prime
    0x2033,    # ″  Double prime
    0x203a,    # ›  Single right-pointing angle quotation mark
    0x2103,    # ℃  Degree celsius
    0x2236,    # ∶  Ratio
    0x3001,    # 、 Ideographic comma
    0xff0c,    # ， Fullwidth comma
    0x3002,    # 。 Ideographic full stop
    0x3003,    # 〃 Ditto mark
    0x3009,    # 〉 Right angle bracket
    0x300b,    # 》 Right double angle bracket
    0x300d,    # 」 Right corner bracket
    0x300f,    # 』 Right white corner bracket
    0x3011,    # 】 Right black lenticular bracket
    0x3015,    # 〕 Right tortoise shell bracket
  );
  return "PUN_FORBIT_BREAK_AFTER"
    if any { $u == $_ } @punctuations_forbit_break_after;
  return "PUN_FORBIT_BREAK_BEFORE"
    if any { $u == $_ } @punctuations_forbit_break_before;
  return "CJK_PUN"
    if (
      ( $u >= 0x3000 and $u <= 0x303F ) or    # CJK Symbols and Punctuation
      ( $u >= 0xFF00 and $u <= 0xFFEF ) or    # Halfwidth and Fullwidth Forms
      ( $u >= 0xFE50 and $u <= 0xFE6F )       # Small Form Variants
    );
  return "CJK"
    if (
      ( $u >= 0x4E00 and $u <= 0x9FFF ) or    # CJK Unified Ideographs
      ( $u >= 0x3400 and $u <= 0x4DBF )
      or                                      # CJK Unified Ideographs Extension A
      ( $u >= 0x20000 and $u <= 0x2A6DF )
      or                                      # CJK Unified Ideographs Extension B
      ( $u >= 0x2A700 and $u <= 0x2B73F )
      or                                      # CJK Unified Ideographs Extension C
      ( $u >= 0x2B740 and $u <= 0x2B81F )
      or                                      # CJK Unified Ideographs Extension D
      ( $u >= 0x2B820 and $u <= 0x2CEAF )
      or                                      # CJK Unified Ideographs Extension E
      ( $u >= 0x2CEB0 and $u <= 0x2EBEF )
      or                                      # CJK Unified Ideographs Extension F
      ( $u >= 0x30000 and $u <= 0x3134F )
      or                                      # CJK Unified Ideographs Extension G
      ( $u >= 0x31350 and $u <= 0x323AF )
      or                                      # CJK Unified Ideographs Extension H
      ( $u >= 0xF900 and $u <= 0xFAFF ) or    # CJK Compatibility Ideographs
      ( $u >= 0x3100 and $u <= 0x312f ) or    # Bopomofo
      ( $u >= 0x31a0 and $u <= 0x31bf ) or    # Bopomofo Extended
      (     $u >= 0x2F800
        and $u <= 0x2FA1F )                   # CJK Compatibility Ideographs Supplement
       );
  return "OTHER";
}

1;
