package App::Markdown::Text::State;

use strict;
use warnings;
use List::Util           qw(any none);
use App::Markdown::Utils qw(_char_attr);
use Text::CharWidth      qw(mbswidth mblen mbwidth);

sub new {
  my $class = shift;
  my ( $text, $prefix_first, $prefix_other ) = @_;
  $text         //= '';
  $prefix_first //= '';
  $prefix_other //= '';

  my $self = {
    lines             => [],
    original_text     => \$text,
    text_length       => length($text),
    pos               => 0,
    current_line      => _string_init(),
    current_word      => _string_init(),
    current_char      => _char_init(),
    inline_syntax_end => {},                                                   # 新增语法结束标记栈
    prefix            => { first => $prefix_first, other => $prefix_other },
  };

  bless $self, $class;
  return $self;
}

sub extract_next_char_info {
  my ( $self, $shift ) = @_;
  $shift //= 0;

  my $string  = ${ $self->{original_text} };
  my $pos     = $self->{pos} + $shift;
  my $str_len = $self->{text_length};

  my $char_info = _char_init();

  return $char_info if ( $pos > $str_len || $pos < 0 );

  my $char_len   = mblen( substr( $string, $pos ) );
  my $char       = substr( $string, $pos, 1 );
  my $char_width = mbswidth($char);

  if ( $char_len <= 0 ) {
    $char_info->{char} = '';
  }
  else {
    $char_info->{char}  = $char;
    $char_info->{width} = $char_width;
  }

  if ( $char_len > 1 ) {
    $char_info->{type} = _char_attr( ord $char );
  }

  return $char_info;
}

sub init {
  my $self = shift;
  my $key  = shift;
  if    ( $key eq "current_line" ) { $self->{$key} = _string_init( $self->{prefix}{other} ) }
  elsif ( $key eq "current_word" ) { $self->{$key} = _string_init() }
}

sub update {
  my $self = shift;
  my ( $key, $value ) = @_;
  if ( $key eq "pos" ) {
    $self->{pos} += $value if $self->{pos} >= 0 and $self->{pos} < $self->{text_length};
  }

}

sub at_end_of_text {
  my $self = shift;
  return $self->{pos} >= $self->{text_length}
    || substr( ${ $self->{original_text} }, $self->{pos} ) =~ m/\A\s*\z/mxs;
}

sub is_valid_char {
  my $self      = shift;
  my $char_info = $self->{current_char};
  return ( $char_info->{width} != -1 || $char_info->{char} eq "\n" );
}

sub shift_char {
  my $self = shift;
  $self->{current_char} = $self->extract_next_char_info();
  $self->{pos} += 1;
  return $self->{current_char};
}

sub push_line {
  my $self = shift;
  push @{ $self->{lines} }, $self->{current_line}{str} if $self->{current_line} > 0;
  $self->init("current_line");
  return $self;
}

sub word_extend {
  my $self = shift;
  return $self if $self->{current_char}{char} eq "";
  $self->{current_word}{str} .= $self->{current_char}{char};
  $self->{current_word}{len} += $self->{current_char}{width};
  return $self;
}

sub line_extend {
  my $self      = shift;
  my $opt       = shift || {};
  my $line      = $self->{current_line};
  my $word      = $self->{current_word};
  my $no_update = ( defined $opt->{update} && $opt->{update} == 0 );
  if ($no_update) {
    $line = $opt->{line} if defined $opt->{line};
    $word = $opt->{word} if defined $opt->{word};
    $line = { str => $line->{str}, len => $line->{len} };
    $word = { str => $word->{str}, len => $word->{len} };
  }

  return ( $no_update ? $line : $self ) if $word->{len} == 0 and $word->{str} eq "";

  if ( $line->{len} == 0 and $line->{str} eq "" ) {
    return $word if $no_update;
    $self->{current_line} = $word;
    $self->init("current_word");
    return $self;
  }

  # No additional processing is done when splicing characters
  if ( defined $opt and defined $opt->{noprocess} ) {
    $line->{str} .= $word->{str};
    $line->{len} += $word->{len};
    return $line if $no_update;
    $self->init("current_word");
    return $self;
  }

  my @no_extra_space_after  = ( q( ), qw( $ * _ =   [ / ~) );
  my @no_extra_space_before = ( q(,), qw( $ * _ = . ] / ~) );
  my $char_last             = substr( $line->{str}, -1, 1 );
  my $char_first            = substr( $word->{str},  0, 1 );
  my $attr_last             = _char_attr( ord $char_last );
  my $attr_first            = _char_attr( ord $char_first );

  # Insert spaces when splicing text when certain conditions are met
  if (
        $word->{len} > 0
    and ( none { $char_last eq $_ } @no_extra_space_after )
    and ( none { $char_first eq $_ } @no_extra_space_before )

    # When the sentence ends with a space, or the character begins with
    # a space, no additional spaces need to be inserted.
    and not( $char_first =~ m/\s/ or $char_last =~ m/\s/ )

    # There is no need for spaces between the bibliographic citation prefixes
    # after Chinese punctuation marks.
    and not( $char_first eq '@' and $attr_last =~ /PUN/ )

    # Insert spaces between Chinese and English
    and ( ( $attr_last eq "OTHER" and $attr_first eq "CJK" ) or ( $attr_last eq "CJK" and $attr_first eq "OTHER" ) )
    )
  {
    $line->{str} .= " " . $word->{str};
    $line->{len} += 1 + $word->{len};
  }

  # 应对 rime_ls bug 的临时解决方案 ----------------------------------- {{{
  elsif ( $line->{str} =~ m/\[\s\z/ and $attr_first eq "CJK" ) {
    $line->{str} = substr( $line->{str}, 0, -1 ) . $word->{str};
    $line->{len} += $word->{len} - 1;
  }
  elsif ( ( $attr_first eq "CJK" and $line->{str} =~ m/[A-z0-9.)][*_]+\z/xms )
    or ( $attr_last eq "CJK" and $word->{str} =~ m/[*_]+[A-z0-9.(]/ ) )
  {
    $line->{str} .= " " . $word->{str};
    $line->{len} += 1 + $word->{len};
  }
  elsif ( any { $char_first eq $_ } ("]")
    and $char_last eq " "
    and defined substr( $line->{str}, -2, 1 )
    and _char_attr( ord substr( $line->{str}, -2, 1 ) ) eq "CJK" )
  {
    $line->{str} = substr( $line->{str}, 0, -1 ) . $word->{str};
    $line->{len} += $word->{len} - 1;
  }

  # ------------------------------------------------------------------- }}}
  else {
    $line->{str} .= $word->{str};
    $line->{len} += $word->{len};
  }

  return $line if $no_update;
  $self->init("current_word");
  return $self;
}

sub _char_init {
  return { char => "", width => 0, type => "OTHER" };
}

sub _string_init {
  my $str = shift // "";
  my $len = shift // mbswidth($str);
  return { str => $str, len => $len };
}

1;
