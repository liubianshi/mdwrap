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
    my $state = shift || return;
    my ( $str_ref, $pos, $char, $left_char ) = _format_arg($state);
    return if $left_char eq "`" or $left_char eq "\\";
    return if substr( ${$str_ref}, $pos - 1 ) !~ m{
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
        my $state = shift;
        return if $state->{pos} != $end_pos;
        return { conceal => 1 };
      }
    };
  },
  '*' => sub {
    my $state = shift || return;
    my ( $str_ref, $pos, $char, $left_char ) = _format_arg($state);
    return if $left_char eq "\\" or $left_char eq '*';
    return if substr( ${$str_ref}, $pos - 1 ) !~ m{
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
        my $state = shift;
        return if $state->{pos} != $end_pos - ( length($symbol) - 1 );
        return {
          end_len => length($symbol),
          conceal => length($symbol)
        };
      }
    };
  },
  '$' => sub {
    my $state = shift || return;
    my ( $str_ref, $pos, $char, $left_char ) = _format_arg($state);
    return if $left_char eq "\\" and $left_char ne '$';
    return if substr( ${$str_ref}, $pos - 1 ) !~ m{
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
        my $state = shift;
        return if $state->{pos} != $end_pos;
        return { conceal => 0 };
      }
    };
  },
  '@' => sub {
    my $state = shift || return;
    my ( $str_ref, $pos, $char, $left_char, $left_char_attr ) = _format_arg($state);
    my $right_char = $state->extract_next_char_info()->{char};
    return if $left_char eq "\\" or ( $left_char =~ /\S/ and $left_char_attr eq "OTHER" );
    return if $right_char = m/[@\s\n]/;
    return {
      conceal  => 0,
      wrap     => 0,
      endprobe => sub {
        my $state = shift;
        my $str   = ${ $state->{original_text} };
        my $pos   = $state->{pos};
        my $right = $state->extract_next_char_info();
        if (  any { $right->{char} eq $_ } ( "", " ", "\n", split( //, '],:;' ) )
          and any { $right->{type} eq $_ } qw(CJK_PUN PUN_FORBIT_BREAK_BEFORE PUN_FORBIT_BREAK_AFTER) )
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
    sub {    # extneal link
      my $state = shift || return;
      my ( $str_ref, $pos, $char, $left_char ) = _format_arg($state);
      return if $left_char eq "\\";
      return if not substr( ${$str_ref}, $pos - 1 ) =~ m{ \A (
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
          my $state = shift;
          return if $state->{pos} != $end_pos;
          return { conceal => $concealed_char_number };
        }
      };
    },

    # wiki link
    sub {
      my $state = shift || return;
      my ( $str_ref, $pos, $char, $left_char ) = _format_arg($state);
      return if $left_char eq "\\";
      return if not substr( ${$str_ref}, $pos - 1 ) =~ m{
        \A (
          \[\[ ($RE{not_right_bracket}*) (?<!\])\]\]
        )
      }mxs;
      my ( $matched, $display ) = ( $1, $2 );
      if ( $display =~ m/(?<!\\)\|\s*(.+)/ ) {
        $display = $1;
      }
      my $concealed_char_number = mbswidth($matched) - ( mbswidth($display) + 2 );
      my $end_pos               = $pos + length($matched) - 1;
      return {
        conceal  => 0,
        wrap     => 0,
        endprobe => sub {
          my $state = shift;
          return if $state->{pos} != $end_pos;
          return { conceal => $concealed_char_number };
        }
      };
    },

    # ref link
    sub {
      my $state = shift || return;
      my ( $str_ref, $pos, $char, $left_char ) = _format_arg($state);
      return if $left_char eq "\\";
      return if not substr( ${$str_ref}, $pos - 1 ) =~ m{
        \A (
          \[ ($RE{not_right_bracket}*) (?!\\)\]
          \s*
          \[ $RE{not_right_bracket}+ (?!\\)\]
        )
      }xms;
      my ( $matched, $display ) = ( $1, $2 );
      my $concealed_char_number = mbswidth($matched) - ( mbswidth($display) + 2 );
      my $end_pos               = $pos + length($matched) - 1;
      return {
        conceal  => 0,
        wrap     => 0,
        endprobe => sub {
          my $state = shift;
          return if $state->{pos} != $end_pos;
          return { conceal => $concealed_char_number };
        }
      };
    }
  ],
};

sub get_syntax_meta {
  return $syntax;
}

sub _format_arg {
  my $state   = shift || return;
  my $str_ref = $state->{original_text};
  my $pos     = $state->{pos};
  my $char    = $state->{current_char}{char};
  my $left    = $state->extract_next_char_info(-2);
  return ( $str_ref, $pos, $char, $left->{char}, $left->{type} );
}

return 1;
