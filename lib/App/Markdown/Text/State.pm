package App::Markdown::Text::State;

use strict;
use warnings;
use List::Util           qw(any none);
use App::Markdown::Utils qw(_char_attr);
use Text::CharWidth      qw(mbswidth mblen mbwidth);

sub new {
  my $class = shift;
  my $args = shift;
  $args = {
    prefix_first => "",
    prefix_other => "",
    content => \(""),
    %{$args}
  };

  my $self = {
    lines             => [],
    original_text     => $args->{content},
    text_length       => length(${$args->{content}}),
    pos               => 0,
    current_line      => _string_init($args->{prefix_first}),
    current_word      => _string_init(),
    current_sentence  => _string_init(),
    current_char      => _char_init(),
    wrap_sentence     => $args->{wrap_sentence},
    inline_syntax_end => {},                 # 新增语法结束标记栈
    prefix            => { first => $args->{prefix_first}, other => $args->{prefix_other} },
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
  my $self  = shift;
  my $key   = shift;
  my $value = shift // ( $key eq "current_line" ? $self->{prefix}{other} : "" );
  $self->{$key} = _string_init($value)
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

sub next {
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

sub sentence_extend {
  my $self      = shift;
  my $opt       = shift || {};
  my $sentence  = $self->{current_sentence};
  my $word      = $self->{current_word};
  _string_extend($sentence, $word, $opt);
  $self->init("current_word");
  return $self;
}

sub line_extend {
  my $self      = shift;
  my $opt       = shift || {};
  my $line      = $self->{current_line};
  my $source    = $self->{wrap_sentence} ? "current_word" : "current_sentence";
  my $new       = $self->{$source};

  _string_extend($line, $new, $opt);
  $self->init($source);
  return $self;
}

sub upload_word {
  my $self = shift;
  if ($self->{wrap_sentence}) {
    $self->line_extend();
  }
  else {
    $self->sentence_extend();
  }
  return $self;
}

sub upload_non_word_character {
  my $self = shift;
  $self->upload_word();
  $self->word_extend();
  $self->upload_word();
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

sub _string_extend {
  my ($left, $right, $opt) = @_;
  return if
    not defined $left
    or not defined $right
    or not defined $left->{str}
    or not defined $left->{len}
    or not defined $right->{str}
    or not defined $right->{len};

  if ( defined $opt and defined $opt->{noprocess} ) {
    $left->{str} .= $right->{str};
    $left->{len} += $right->{len};
    return
  }

  my @no_extra_space_after  = ( q( ), qw( $ * _ =   [ / ~) );
  my @no_extra_space_before = ( q(,), qw( $ * _ = . ] / ~) );
  my $char_last             = substr( $left->{str},  -1, 1 );
  my $char_first            = substr( $right->{str},  0, 1 );
  my $attr_last             = _char_attr( ord $char_last );
  my $attr_first            = _char_attr( ord $char_first );

  # Insert spaces when splicing text when certain conditions are met
  if (
        $right->{len} > 0
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
    $left->{str} .= " " . $right->{str};
    $left->{len} += 1 + $right->{len};
  }

  # 应对 rime_ls bug 的临时解决方案 ----------------------------------- {{{
  elsif ( $left->{str} =~ m/\[\s\z/ and $attr_first eq "CJK" ) {
    $left->{str} = substr( $left->{str}, 0, -1 ) . $right->{str};
    $left->{len} += $right->{len} - 1;
  }
  elsif ( ( $attr_first eq "CJK" and $left->{str} =~ m/[A-z0-9.)][*_]+\z/xms )
    or ( $attr_last eq "CJK" and $right->{str} =~ m/[*_]+[A-z0-9.(]/ ) )
  {
    $left->{str} .= " " . $right->{str};
    $left->{len} += 1 + $right->{len};
  }
  elsif ( any { $char_first eq $_ } ("]")
    and $char_last eq " "
    and defined substr( $left->{str}, -2, 1 )
    and _char_attr( ord substr( $left->{str}, -2, 1 ) ) eq "CJK" )
  {
    $left->{str} = substr( $left->{str}, 0, -1 ) . $right->{str};
    $left->{len} += $right->{len} - 1;
  }

  # ------------------------------------------------------------------- }}}
  else {
    $left->{str} .= $right->{str};
    $left->{len} += $right->{len};
  }
}

1;
