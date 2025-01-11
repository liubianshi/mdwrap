package App::Markdown::Text;
use strict;
use warnings;
use Data::Dump qw(dump);
use Exporter 'import';
use Text::CharWidth         qw(mbswidth mblen mbwidth);
use List::Util              qw(any none);
use App::Markdown::Conceals qw(concealed_chars);

our @EXPORT_OK = qw(wrap set_environemnt_variable);

my $LINE_WIDTH       = 80;
my $SPACE            = " ";
my $NEW_LINE         = "\n";
my $SEPERATOR_SYMBOL = "┄";

sub set_environemnt_variable {
  my $opt = shift;
  if ( defined $opt->{"line-width"} ) {
    $LINE_WIDTH = $opt->{"line-width"};
  }
}

sub wrap {
  my $prefix_first = shift;    # First line indent
  my $prefix_other = shift;    # Indent other lines
  my $oritext      = shift;
  my $opts         = shift;

  # Segmented processing, can consider using multi-threading in the future
  my @paragrphs = split /^\s*$/mxs, $oritext;
  if ( scalar @paragrphs > 1 ) {
    return join "\n", map { wrap( $prefix_first, $prefix_other, $_ ) } @paragrphs;
  }

  # Remove consecutive blank lines and ensure the text ends with a single newline character
  $oritext =~ s/\A\n+//;
  $oritext =~ s/[\h\n]*\z/\n/m;

  $oritext = $prefix_first . $oritext;
  my $oritext_len = length($oritext);
  return $oritext if $oritext_len <= 1;

  # Wrap extra long lines to avoid copying large strings
  my @oritexts;
  while ( scalar(@oritexts) * 80 <= $oritext_len ) {
    push @oritexts, substr( $oritext, 80 * scalar(@oritexts), 80 );
  }

  # Process character by character, first aggregate into words, then aggregate
  # into lines, and consider line breaks at appropriate locations
  my @lines = ();
  my $line  = _string_init();
  my $word  = _string_init();

  my ( $char, $char_width, $char_attr, $next_char, $next_char_attr );
  my $i       = 0;     # Used to determine whether all rows have been exhausted
  my $sub_env = "";    #  Literals for handling special syntax

OUTER:
  for my $text (@oritexts) {
    $i++;
    my $text_len = length($text);
  INNER:
    while ( $text_len > 0 ) {
      ( $char, $text, $char_width, $char_attr ) = _extract($text);
      $text_len = length($text);
      next INNER if $char_width == -1 and $char ne $NEW_LINE;

      # end of line terminator
      if ( $char eq $NEW_LINE and $text =~ m/\A\s*\z/mxs ) {
        _line_extend( $line, $word->{str}, $word->{len} ) if $sub_env eq "";
        if ( $i == scalar @oritexts ) {
          push @lines, $line->{str} if $line->{len} > 0;
          last OUTER;
        }
      }

      # No wrap between ` and `
      if ( $sub_env eq "code"
        or ( $sub_env eq "" and $char eq "`" and $word->{str} !~ m/\\$/ ) )
      {
        if ( $sub_env ne "code" ) {
          _line_extend( $line, $word->{str}, $word->{len} );
          $word = _string_init( $char, $char_width );
          if ( $text_len == 0 ) {
            $sub_env = "code";
            next OUTER;
          }
          ( $char, $text, $char_width, $char_attr ) = _extract($text);
          $text_len = length($text);
        }

        while ( defined $char
          and ( $char ne '`' or $word->{str} =~ m/[\\]$/ ) )
        {
          $char = $SPACE if $char eq $NEW_LINE;    # `` 内不应该有断行
          _word_extend( $word, $char, $char_width );
          if ( $text_len == 0 ) {
            $sub_env = "code";
            next OUTER;
          }
          ( $char, $text, $char_width, $char_attr ) = _extract($text);
          $text_len = length($text);
        }
        _word_extend( $word, $char, $char_width );
        $sub_env = "";

        wrap_line( \@lines, $line, $word )
          and $line = _string_init($prefix_other);
        _line_extend( $line, $word->{str}, $word->{len}, { noprocess => 1 } );
        $word = _string_init();
        next INNER;
      }

      # No wrap between $ and $
      if ( $sub_env eq "inline_eq"
        or ( $sub_env eq "" and $char eq "\$" and $word->{str} !~ m/\\$/ ) )
      {
        if ( $sub_env ne "inline_eq" ) {
          _line_extend( $line, $word->{str}, $word->{len} );
          $word = _string_init( $char, $char_width );
          if ( $text_len == 0 ) {
            $sub_env = "inline_eq";
            next OUTER;
          }
          ( $char, $text, $char_width, $char_attr ) = _extract($text);
          $text_len = length($text);
        }

        while ( defined $char
          and ( $char ne "\$" or $word->{str} =~ m/[\\]$/ ) )
        {
          $char = $SPACE if $char eq $NEW_LINE;    # `` 内不应该有断行
          _word_extend( $word, $char, $char_width );
          if ( $text_len == 0 ) {
            $sub_env = "inline_eq";
            next OUTER;
          }
          ( $char, $text, $char_width, $char_attr ) = _extract($text);
          $text_len = length($text);
        }
        _word_extend( $word, $char, $char_width );
        $sub_env = "";

        wrap_line( \@lines, $line, $word )
          and $line = _string_init($prefix_other);
        _line_extend( $line, $word->{str}, $word->{len}, { noprocess => 1 } );
        $word = _string_init();
        next INNER;
      }

      # No spaces should be inserted between bibliographic citations
      # 如 `@罗EtAl2024`
      if (
        $sub_env eq "cite"
        or (  $sub_env eq ""
          and $char eq "@"
          and $word->{str} !~ m/[-A-Za-z0-9_]$/ )
         )
      {
        if ( $sub_env ne "cite" ) {
          _line_extend( $line, $word->{str}, $word->{len} );
          $word = _string_init( $char, $char_width );
          if ( $text_len == 0 ) {
            $sub_env = "cite";
            next OUTER;
          }
          ( $char, $text, $char_width, $char_attr ) = _extract($text);
          $text_len = length($text);
        }
        else {
          $sub_env = "";
        }

        while ( defined $char
          and none { $char eq $_ } ( "", $SPACE, $NEW_LINE, split( //, '],:;' ) )
          and none { $char_attr eq $_ } qw(CJK_PUN PUN_FORBIT_BREAK_BEFORE PUN_FORBIT_BREAK_AFTER) )
        {
          _word_extend( $word, $char, $char_width );
          if ( $text_len == 0 ) {
            $sub_env = "cite";
            next OUTER;
          }
          ( $char, $text, $char_width, $char_attr ) = _extract($text);
          $text_len = length($text);
        }
        $sub_env = "";

        # 当加入文献引用后句子超长时，就应该先断行
        wrap_line( \@lines, $line, $word )
          and $line = _string_init($prefix_other);
        _line_extend( $line, $word->{str}, $word->{len} );
        $word = _string_init();
      }

      # 换行符号的特殊处理
      if ( $char eq $NEW_LINE ) {
        $text =~ s/\A\s+//;    # Remove the original indentation of a paragraph
        $text_len = length($text);

        # When the first character of the next line is CJK,
        # there is no need to add an extra space when merging lines.
        $next_char_attr = _char_attr( ord substr( $text, 0, 1 ) );
        if ( mbwidth($text) > 1 and $next_char_attr ne "OTHER" ) {
          my $last_char = substr( $word->{str} eq "" ? $line->{str} : $word->{str}, -1 );
          $char = ( $last_char eq $SPACE || _char_attr( ord $last_char ) ne "OTHER" ) ? "" : $SPACE;
        }
        else {
          $char = $SPACE;
        }
        $char_width = $char eq "" ? 0 : 1;
        $char_attr  = "";
      }

      $next_char      = substr( $text, 0, 1 );
      $next_char_attr = _char_attr( ord $next_char );

      # line wrap are not allowed after the current letter
      # or the next character cannot be the start of a new line.
      if ( $char_attr eq "PUN_FORBIT_BREAK_AFTER"
        || $next_char_attr eq "PUN_FORBIT_BREAK_BEFORE" )
      {
        _line_extend( $line, $word->{str}, $word->{len} );
        _line_extend( $line, $char,        $char_width );
        $word = _string_init();
        next INNER;
      }

      # whether the current line have enough room for the curren character
      my $with_enough_room = remaining_space( $line, $word, { str => $char, len => $char_width } );

      # 下一个字符为英文字符时，需要引入额外的空格，导致前面的计算不准
      # if (  $with_enough_room == 1
      #   and $line->{str} !~ m/\s$/
      #   and $word->{str} eq ""
      #   and $char_width > 0
      #   and $char_attr eq "OTHER" )
      # {
      #   push @lines, $line->{str};
      #   $line = _string_init($prefix_other);
      #   _word_extend( $word, $char, $char_width );
      #   next INNER;
      # }

      if ( $with_enough_room > 0 ) {
        if ( $char_width == 0 ) {
          _line_extend( $line, $word->{str}, $word->{len} );
          $word = _string_init();
        }
        elsif ( $char eq $SPACE || $char_attr ne "OTHER" ) {
          _line_extend( $line, $word->{str}, $word->{len} );
          _line_extend( $line, $char,        $char_width );
          $word = _string_init();
        }
        else {
          _word_extend( $word, $char, $char_width );
        }
        next INNER;
      }

      # 新字符为空字符
      if ( $char eq "" or $char =~ m/\A \s* \z/mxs ) {

        # 当行长已经足够时，可以省略空格
        _line_extend( $line, $word->{str}, $word->{len} ) unless $word->{str} eq $SPACE;
        push @lines, $line->{str};
        $line = _string_init($prefix_other);
        $word = _string_init();
        next INNER;
      }

      # the line ends by space
      if ( $line->{str} =~ m/\s$/ and $word->{str} eq "" ) {
        push @lines, $line->{str} =~ s/\s$//r;
        $line = _string_init($prefix_other);
        _word_extend( $word, $char, $char_width );
        next INNER;
      }

      if ( any { $char_attr eq $_ } qw(CJK CJK_PUN PUN_FORBIT_BREAK_BEFORE) ) {
        _line_extend( $line, $word->{str}, $word->{len} );
        _line_extend( $line, $char,        $char_width );
        push @lines, $line->{str};

        # Spaces between CJK and English should be removed after a line break
        $text =~ s/\A\s(?!\s)//;

        $line = _string_init($prefix_other);
        $word = _string_init();
        next INNER;
      }

      _word_extend( $word, $char, $char_width );
      push @lines, $line->{str};
      $line = _string_init($prefix_other);
    }
  }

  return join( "\n", map { s/\s+$//rmxs } @lines ) . "\n";
}

sub _string_init {
  my $str = shift // "";
  my $len = shift // mbswidth($str);
  return { str => $str, len => $len };
}

sub _line_extend {
  my ( $str_ref, $char, $width, $opt_ref ) = @_;
  $width //= mbswidth($char);
  return $str_ref if $width == 0;

  # No additional processing is done when splicing characters
  if ( defined $opt_ref and defined $opt_ref->{noprocess} ) {
    $str_ref->{str} .= $char;
    $str_ref->{len} += $width;
    return $str_ref;
  }

  my @no_extra_space_after  = ( q( ), qw( $ * _ =   [ / ~) );
  my @no_extra_space_before = ( q(,), qw( $ * _ = . ] / ~) );
  my $char_last             = substr( $str_ref->{str}, -1, 1 );
  my $char_first            = substr( $char,            0, 1 );
  my $str_attr              = _char_attr( ord $char_last );
  my $char_attr             = _char_attr( ord $char_first );

  # Insert spaces when splicing text when certain conditions are met
  if (
        $str_ref->{len} > 0
    and ( none { $char_last eq $_ } @no_extra_space_after )
    and ( none { $char_first eq $_ } @no_extra_space_before )

    # When the sentence ends with a space, or the character begins with
    # a space, no additional spaces need to be inserted.
    and not( $char =~ /\A\s/m or $str_ref->{str} =~ /\s\z/m )

    # There is no need for spaces between the bibliographic citation prefixes
    # after Chinese punctuation marks.
    and not( $char_first eq '@' and $str_attr =~ /PUN/ )

    # Insert spaces between Chinese and English
    and ( ( $str_attr eq "OTHER" and $char_attr eq "CJK" ) or ( $str_attr eq "CJK" and $char_attr eq "OTHER" ) )
    )
  {
    $str_ref->{str} .= " $char";
    $str_ref->{len} += ( $width + 1 );
  }

  # 应对 rime_ls bug 的临时解决方案 ----------------------------------- {{{
  elsif ( $str_ref->{str} =~ m/\[\s\z/ and $char_attr eq "CJK" ) {
    $str_ref->{str} = substr( $str_ref->{str}, 0, -1 ) . $char;
    $str_ref->{len} += ( $width - 1 );
  }
  elsif ( $char_attr eq "CJK"
    and $str_ref->{str} =~ m/(?<![A-z0-9.)]) [*_][*_]* \s \z/xms )
  {
    $str_ref->{str} = substr( $str_ref->{str}, 0, -1 ) . $char;
    $str_ref->{len} += ( $width - 1 );
  }
  elsif ( any { $char_first eq $_ } ("]")
    and $char_last eq " "
    and defined substr( $str_ref->{str}, -2, 1 )
    and _char_attr( ord substr( $str_ref->{str}, -2, 1 ) ) eq "CJK" )
  {
    $str_ref->{str} = substr( $str_ref->{str}, 0, -1 ) . $char;
    $str_ref->{len} += ( $width - 1 );
  }

  # ------------------------------------------------------------------- }}}
  else {
    $str_ref->{str} .= $char;
    $str_ref->{len} += $width;
  }

  return $str_ref;
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
    0x002c,    # ,  Comma
    0x002e,    # .  Full stop
    0x003b,    # ;  Semicolon
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

sub _extract {
  my $string    = shift;
  my $char_attr = "OTHER";
  my ( $char_len, $char, $rest, $char_width, $unicode );

  return ( '', '', 0, "OTHER" ) if length($string) == 0;

  $char_len = mblen($string);
  return ( '?', substr( $string, 1 ), -1, "OTHER" )
    if $char_len == 0 || $char_len == -1;

  $char       = substr( $string, 0, 1 );
  $rest       = length($string) >= 1 ? substr( $string, 1 ) : "";
  $char_width = mbswidth($char);
  return ( $char, $rest, $char_width, "OTHER" ) if $char_len == 1;

  return ( $char, $rest, $char_width, _char_attr( ord($char) ) );
}

sub _word_extend {
  my ( $str_ref, $char, $width ) = @_;
  $str_ref->{str} .= $char;
  $str_ref->{len} += $width;
  return $str_ref;
}

sub wrap_line {
  my ( $lines_ref, $line, $word, $char, $char_width ) = @_;
  $char       //= "";
  $char_width //= mbswidth($char);
  if ( remaining_space( $line, $word, { str => $char, len => $char_width } ) <= 0 ) {
    push @$lines_ref, $line->{str};
    return 1;
  }

  return undef;
}

sub cal_remaining_space {
  my ( $origin, $new, $limit ) = @_;
  $limit //= $LINE_WIDTH;
  return ( $limit - $origin ) - ( $new - $limit );
}

sub remaining_space {
  my ( $l, $w, $c ) = @_;
  $c //= { str => "", len => 0 };

  my $lw = $l->{len} + $w->{len} + $c->{len};

  # 当单词过长时，需要在过长和过短之间权衡
  my $rm = cal_remaining_space( $l->{len}, $lw );

  # 当接近行长时，比较合并前后行长的情况
  if ( $rm <= 4 ) {
    my $nl = _line_extend( { str => $l->{str}, len => $l->{len} }, $w->{str}, $w->{len} );
    $nl = _line_extend( $nl, $c->{str}, $c->{len} );
    $lw = $nl->{len};
    $rm = cal_remaining_space( $l->{len}, $lw );

    # 当行长不够时，考虑 conceal 后再进行比较
    if ( $rm <= 0 ) {
      $lw = $lw - concealed_chars( $nl->{str} );
      $rm = cal_remaining_space( $l->{len} - concealed_chars( $l->{str} ), $lw );
    }
  }

  return $rm;
}

1;
