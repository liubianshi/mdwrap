package App::Markdown::Inline;

use strict;
use warnings;
use utf8;
use Data::Dump      qw(dump);
use Text::CharWidth qw(mbswidth mblen mbwidth);
use Exporter 'import';
our @EXPORT_OK = qw(get_syntax_meta);

my $syntax = {
  '`' => sub {
    my $arg       = shift;
    my $char      = $arg->{char};
    my $left_char = $arg->{left};
    return if $char ne "`" or $left_char eq "\\";
    return {
      wrap     => 1,
      conceal  => 1,
      endchar  => "`",
      endprobe => sub {
        my $arg       = shift;
        my $char      = $arg->{char};
        my $left_char = $arg->{left};
        my $cap       = $arg->{cap};
        return if $char ne "`" or $left_char eq "\\";
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
    return if $left_char eq "\\";
    if ( substr( $str, $pos - 1 ) =~ m/^([*]{1,3})[^*]+\1/ ) {
      my $match = $1;
      return {
        wrap      => 1,
        start_len => length($match),
        conceal   => length($match),
        endchar   => "*",
        endprobe  => sub {
          my $arg       = shift;
          my $left_char = $arg->{left};
          my $str       = ${ $arg->{str_ref} };
          my $pos       = $arg->{pos};
          return if $left_char eq "\\";
          return if substr( $str, $pos - 1, length($match) ) ne $match;
          return { end_len => length($match), conceal => length($match) };
        }
      };
    }
  },
  '$' => sub {
    my $arg       = shift;
    my $char      = $arg->{char};
    my $left_char = $arg->{left};
    return if $char ne "`" or $left_char eq "\\";
    return {
      wrap     => 1,
      conceal  => 1,
      endchar  => '$',
      endprobe => sub {
        my $arg       = shift;
        my $char      = $arg->{char};
        my $left_char = $arg->{left};
        my $cap       = $arg->{cap};
        return if $char ne '$' or $left_char eq "\\";
        return { conceal => 1 };
      }
    };
  },
  '@' => sub {
    my $arg       = shift;
    my $char      = $arg->{char};
    my $left_char = $arg->{left};
    return if $char ne "@" or ( $left_char !~ /^\s*$/ and _char_attr( ord $left_char ) eq "OTHER" );
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
      my $arg   = shift;
      my $str   = ${ $arg->{str_ref} };
      my $pos   = $arg->{pos};
      my $no_rB = qr/(?:[^\]]|\\\])/;
      my $no_rb = qr/(?:[^)]|\\\))/;
      return if not substr( $str, $pos - 1 ) =~ m/^\[$no_rB*\]\($no_rb*\)/;
      return {
        conceal  => 0,
        wrap     => 0,
        endprobe => sub {
          my $arg       = shift;
          my $char      = $arg->{char};
          my $left_char = $arg->{left};
          my $cap       = $arg->{cap};
          my $no_rB     = qr/(?:[^\]]|\\\])/;
          my $no_rb     = qr/(?:[^)]|\\\))/;
          return if $char ne ')' or $left_char eq '\\';

          if ( $cap =~ m/^\[(${no_rB}*)\]\(${no_rb}*\)$/ ) {
            return { conceal => mbswidth($cap) - ( mbswidth($1) + 2 ) };
          }
          return;
        }
      };
    },

    # winki link
    sub {
      my $arg   = shift;
      my $str   = ${ $arg->{str_ref} };
      my $pos   = $arg->{pos};
      my $no_rB = qr/(?:[^\]]|\\\])/;
      return if not substr( $str, $pos - 1 ) =~ m/^\[\[$no_rB*\]\]/;
      return {
        conceal  => 0,
        wrap     => 0,
        endprobe => sub {
          my $arg       = shift;
          my $char      = $arg->{char};
          my $left_char = $arg->{left};
          my $next_char = $arg->{right};
          my $cap       = $arg->{cap};
          my $no_rB     = qr/(?:[^\]]|\\\])/;
          return if $char ne ']' or $left_char eq '\\';

          if ( $cap =~ m/^\[{2}(${no_rB}*)\]{2}$/ ) {
            return { conceal => mbswidth($cap) - ( mbswidth($1) + 2 ) };
          }
          return;
        }
      };
    },

    # ref link
    sub {
      my $arg   = shift;
      my $str   = ${ $arg->{str_ref} };
      my $pos   = $arg->{pos};
      my $no_rB = qr/(?:[^\]]|\\\])/;
      return if not substr( $str, $pos - 1 ) =~ m/^\[$no_rB*\]\[$no_rB+\]/;
      return {
        conceal  => 0,
        wrap     => 0,
        endprobe => sub {
          my $arg       = shift;
          my $char      = $arg->{char};
          my $left_char = $arg->{left};
          my $next_char = $arg->{right};
          my $cap       = $arg->{cap};
          my $no_rB     = qr/(?:[^\]]|\\\])/;
          return if $char ne ']' or $left_char eq '\\';

          if ( $cap =~ m/^\[($no_rB*)\]\[$no_rB+\]$/ ) {
            return { conceal => mbswidth($cap) - ( mbswidth($1) + 2 ) };
          }
          return;
        }
      };
    }
  ],
};

sub get_syntax_meta {
  return $syntax;
}

return 1;
