package App::Markdown::Inline;

use strict;
use warnings;
use utf8;
use Data::Dump      qw(dump);
use Text::CharWidth qw(mbswidth mblen mbwidth);

use App::Markdown::Utils qw(_char_attr);

use Exporter 'import';
our @EXPORT_OK = qw(get_syntax_meta);

my %RE = (
  not_right_bracket => qr/(?: [^\]] | \\\] )/x,
  not_right_par     => qr/(?: [^)]  | \\\) )/x,
  balance_star      => qr/
    (?<SYN>[*]{1,3}) (?!\s)
    (?: [^*] | \\[*] )+
    (?<!\s)\g{SYN}
  /xms,
);

my $syntax = {
  '`' => sub {
    my $arg       = shift;
    my $str       = ${ $arg->{str_ref} };
    my $pos       = $arg->{pos};
    my $left_char = $arg->{left};
    return if $left_char eq "`" or $left_char eq "\\";
    return if substr( $str, $pos - 1 ) !~ m{
      \A (
        [`]
        (?: [^`] | \\[`])+
        (?<!\\)[`](?![`])
      )
    }xms;
    my $matched = $1;
    my $end_pos = $pos + length($matched) - 1;
    return {
      wrap     => 1,
      conceal  => 1,
      endchar  => "`",
      endprobe => sub {
        my $arg = shift;
        return if $arg->{pos} != $end_pos;
        return { conceal => 1 };
      }
    };
  },
  '*' => sub {
    my $arg       = shift;
    my $str       = ${ $arg->{str_ref} };
    my $pos       = $arg->{pos};
    my $char      = $arg->{char};
    my $left_char = $arg->{left} // "";
    return if $left_char eq "\\" or $left_char eq '*';
    return if substr( $str, $pos - 1 ) !~ m{
      \A (
        ([*]{1,3}) (?![\s*])
        (?: [^*] | \\[*] | $RE{balance_star} )+?
        (?<!\s)\2
      )
    }xms;
    my ( $matched, $symbol ) = ( $1, $2 );
    my $end_pos = $pos + length($matched) - 1;
    return {
      wrap      => 1,
      start_len => length($symbol),
      conceal   => length($symbol),
      endchar   => "*",
      endprobe  => sub {
        my $arg = shift;
        return if $arg->{pos} != $end_pos - ( length($symbol) - 1 );
        return {
          end_len => length($symbol),
          conceal => length($symbol)
        };
      }
    };
  },
  '$' => sub {
    my $arg       = shift;
    my $str       = ${ $arg->{str_ref} };
    my $pos       = $arg->{pos};
    my $left_char = $arg->{left};
    return if $left_char eq "\\" and $left_char ne '$';
    return if substr( $str, $pos - 1 ) !~ m{
      \A (
        \$
        (?: [^\$] | \\\$)+
        (?<!\\)\$(?!\$)
      )
    }xms;
    my $matched = $1;
    my $end_pos = $pos + length($matched) - 1;
    return {
      wrap     => 1,
      conceal  => 0,
      endchar  => '$',
      endprobe => sub {
        my $arg = shift;
        return if $arg->{pos} != $end_pos;
        return { conceal => 0 };
      }
    };
  },
  '@' => sub {
    my $arg        = shift;
    my $pos        = $arg->{pos};
    my $left_char  = $arg->{left};
    my $right_char = $arg->{right};
    return if $left_char eq "\\" or ( $left_char =~ /\S/ and _char_attr( ord $left_char ) eq "OTHER" );
    return if $right_char = m/[@\s\n]/;
    return {
      conceal  => 0,
      wrap     => 0,
      endprobe => sub {
        my $arg    = shift;
        my $str    = ${ $arg->{str_ref} };
        my $pos    = $arg->{pos};
        my $char_r = substr( $str, $pos, 1 );
        if (  any { $char_r eq $_ } ( "", " ", "\n", split( //, '],:;' ) )
          and any { _char_attr( ord $char_r ) eq $_ } qw(CJK_PUN PUN_FORBIT_BREAK_BEFORE PUN_FORBIT_BREAK_AFTER) )
        {
          return { conceal => 0 };
        }
        else {
          return;
        }
      },
    };
  },
  '[' => [

    # extneal link
    sub {
      my $arg = shift;
      my $str = ${ $arg->{str_ref} };
      my $pos = $arg->{pos};
      return if $arg->{left} eq "\\";
      return if not substr( $str, $pos - 1 ) =~ m{ \A (
        \[ ($RE{not_right_bracket}*) (?<!\])\]
        \s*
        \( $RE{not_right_par}* (?<!\\) \)
      )}xms;
      my ( $matched, $display ) = ( $1, $2 );
      my $concealed_char_number = mbswidth($matched) - ( mbswidth($display) + 2 );
      my $end_pos               = $pos + length($matched) - 1;
      return {
        conceal  => 0,
        wrap     => 0,
        endprobe => sub {
          my $arg = shift;
          return if $arg->{pos} != $end_pos;
          return { conceal => $concealed_char_number };
        }
      };
    },

    # winki link
    sub {
      my $arg = shift;
      my $str = ${ $arg->{str_ref} };
      my $pos = $arg->{pos};
      return if $arg->{left} eq "\\";
      return if not substr( $str, $pos - 1 ) =~ m{
        \A (
          \[\[ ($RE{not_right_bracket}*) (?<!\])\]\]
        )
      }mxs;
      my ( $matched, $display ) = ( $1, $2 );
      my $concealed_char_number = mbswidth($matched) - ( mbswidth($display) + 2 );
      my $end_pos               = $pos + length($matched) - 1;
      return {
        conceal  => 0,
        wrap     => 0,
        endprobe => sub {
          my $arg = shift;
          return if $arg->{pos} != $end_pos;
          return { conceal => $concealed_char_number };
        }
      };
    },

    # ref link
    sub {
      my $arg   = shift;
      my $str   = ${ $arg->{str_ref} };
      my $pos   = $arg->{pos};
      my $no_rB = qr/(?:[^\]]|\\\])/;
      return if $arg->{left} eq "\\";
      return if not substr( $str, $pos - 1 ) =~ m{
        \A (
          \[ $RE{not_right_bracket}* (?!\\)\]
          \s*
          \[ $RE{not_right_bracket}+ (?!\\)\]
        )
      };
      my ( $matched, $display ) = ( $1, $2 );
      my $concealed_char_number = mbswidth($matched) - ( mbswidth($display) + 2 );
      my $end_pos               = $pos + length($matched) - 1;
      return {
        conceal  => 0,
        wrap     => 0,
        endprobe => sub {
          my $arg = shift;
          return if $arg->{pos} != $end_pos;
          return { conceal => $concealed_char_number };
        }
      };
    }
  ],
};

sub get_syntax_meta {
  return $syntax;
}

return 1;
