package App::Markdown::Text;

use strict;
use warnings;
use Data::Dump qw(dump);
use Exporter 'import';
use utf8;
use Text::CharWidth qw(mbswidth mblen mbwidth);
use List::Util      qw(any none);
use open ':std', ':encoding(UTF-8)';
use App::Markdown::Inline qw(get_syntax_meta);
use App::Markdown::Utils  qw(_char_attr);
use App::Markdown::Text::State;

our @EXPORT_OK = qw(wrap set_environemnt_variable);

# 配置常量
use constant {
  DEFAULT_LINE_WIDTH  => 80,      # 默认行宽
  SPACE               => " ",     # 空格字符
  NEW_LINE            => "\n",    # 换行符
  SEPARATOR_SYMBOL    => "┄",     # 分隔线符号
  MIN_REMAINING_SPACE => 4,       # 触发换行的最小剩余空间
  MAX_CONSECUTIVE_NL  => 1,       # 允许的最大连续换行数
};

my $LINE_WIDTH    = DEFAULT_LINE_WIDTH;    # 当前行宽配置
my $INLINE_SYNTAX = get_syntax_meta();

sub set_environemnt_variable {
  my $opt = shift;
  return unless $opt;

  # 参数有效性检查
  if ( defined $opt->{"line-width"}
    && $opt->{"line-width"} =~ /^\d+$/
    && $opt->{"line-width"} >= 20
    && $opt->{"line-width"} <= 200 )
  {
    $LINE_WIDTH = $opt->{"line-width"};
  }
  else {
    warn "Invalid line-width value, using default: " . DEFAULT_LINE_WIDTH;
    $LINE_WIDTH = DEFAULT_LINE_WIDTH;
  }
}

sub wrap {
  my ( $prefix_first, $prefix_other, $original_text, $opts ) = @_;

  # 输入验证
  $prefix_first  //= '';
  $prefix_other  //= '';
  $original_text //= '';

  # Segmented processing, can consider using multi-threading in the future
  my @paragrphs = split /^\s*$/mxs, $original_text;
  if ( scalar @paragrphs > 1 ) {
    return join "\n", map { wrap( $prefix_first, $prefix_other, $_, $opts ) } @paragrphs;
  }

  # 清理输入文本
  my $cleaned_text = _clean_input_text($original_text);
  return "\n" if $cleaned_text eq '';

  # 添加首行前缀
  $cleaned_text = $prefix_first . $cleaned_text;

  # 初始化处理状态
  my $state = App::Markdown::Text::State->new( $cleaned_text, $prefix_first, $prefix_other );

  while ( $state->{pos} < $state->{text_length} ) {
    $state->shift_char();

    # 跳过无效字符（错误处理）
    next unless $state->is_valid_char();

    # 处理最后的换行符
    _finalize_processing($state)
      if $state->{current_char}{char} eq NEW_LINE
      and $state->at_end_of_text();

    # 优先处理行内语法标记
    next if _handle_inline_syntax($state);

    # 换行符号的特殊处理
    update_when_new_line($state) if $state->{current_char}{char} eq NEW_LINE;

    # 不能折行的情况
    next if _handle_wrap_forbidden($state);

    # 当前行还有插入一个字符的空间
    next if _handle_with_remaining_room($state);

    # 在行空间已满的情况下处理空格
    next if _handle_space($state);

    # 以空格结尾的行
    next if _handle_line_end_with_space($state);

    # CJK
    next if _handle_cjk($state);

    # 普通字符
    $state->push_line();
    $state->word_extend();
  }

  # 返回格式化后的文本
  return _generate_output($state);
}

sub wrap_line {
  my $state      = shift;
  my $char       = $state->{current_char};
  my $free_space = remaining_space($state);
  if ( $free_space <= 0 ) {
    $state->push_line();
    return 1;
  }

  return;
}

sub _handle_cjk {
  my ($state)   = @_;
  my $char_info = $state->{current_char};
  my $line      = $state->{current_line};
  my $word      = $state->{current_word};
  return if none { $char_info->{type} eq $_ } qw(CJK CJK_PUN);

  $state->word_extend();
  $state->line_extend();
  $state->push_line();

  # Spaces between CJK and English should be removed after a line break
  $state->{pos} += 1
    if $state->extract_next_char_info()->{char}   =~ m/\s/
    and $state->extract_next_char_info(1)->{char} !~ m/\s/;

  return 1;
}

# the line ends by space
sub _handle_line_end_with_space {
  my ($state)   = @_;
  my $char_info = $state->{current_char};
  my $line      = $state->{current_line};
  my $word      = $state->{current_word};

  return unless $line->{str} =~ m/\s$/ and $word->{str} eq "";

  $line->{str} =~ s/\s+$//;
  $state->push_line();
  $state->word_extend();

  return 1;
}

# handle space
sub _handle_space {
  my ($state) = @_;
  my $char_info = $state->{current_char};

  my $char = $char_info->{char};
  return unless $char eq "" or $char =~ m/\A \s* \z/mxs;

  if ( $state->{current_word}{str} ne SPACE ) {
    $state->line_extend();
  }
  $state->push_line();
  return 1;
}

# whether the current line have enough room for the curren character
sub _handle_with_remaining_room {
  my ($state)         = @_;
  my $char_info       = $state->{current_char};
  my $remaining_space = remaining_space($state);
  return if $remaining_space <= 0;

  if ( $char_info->{width} == 0 ) {
    $state->line_extend();
  }
  elsif ( $char_info->{char} eq SPACE || $char_info->{type} ne "OTHER" ) {
    $state->word_extend();
    $state->line_extend();
  }
  else {
    $state->word_extend();
  }

  return 1;
}

# line wrap are not allowed after the current letter
# or the next character cannot be the start of a new line.
sub _handle_wrap_forbidden {
  my ($state)        = @_;
  my $char_info      = $state->{current_char};
  my $next_char_info = $state->extract_next_char_info();

  my $char      = $char_info->{char};
  my $char_attr = $char_info->{type};
  return unless $char_attr eq "PUN_FORBIT_BREAK_BEFORE" || grep { $_ eq $char } split( //, ",.!" );

  my $string_before_char = $state->{current_line}{str} . $state->{current_word}{str};
  $string_before_char = substr( $string_before_char, length( $state->{prefix}{other} ) );
  if ( $string_before_char =~ m/^\s*$/ and scalar @{ $state->{lines} } > 0 ) {
    $state->{lines}[-1] .= $char;
  }
  else {
    $state->word_extend();
    $state->line_extend();
  }

  return 1;
}

sub cal_remaining_space {
  my ( $origin, $new, $line_width ) = @_;
  $line_width //= $LINE_WIDTH;
  return ( $line_width - $origin ) - ( $new - $line_width );
}

sub remaining_space {
  my ($state) = @_;
  my $line    = $state->{current_line};
  my $word    = $state->{current_word};
  my $char    = $state->{current_char};

  # 计算总显示长度（当前行 + 当前词 + 下个字符）
  my $total_visible_length = $line->{len} + $word->{len} + $char->{width};

  # 基础剩余空间计算
  my $remaining = cal_remaining_space( $line->{len}, $total_visible_length );

  # 处理长单词溢出情况
  if ( $remaining <= 4 ) {
    my $newline = $state->line_extend(
      {
        line   => $state->line_extend( { update => 0 } ),
        word   => { str => $char->{char}, len => $char->{width} },
        update => 0
      }
    );

    $total_visible_length = $newline->{len};
    $remaining            = cal_remaining_space( $line->{len}, $total_visible_length );
  }

  return $remaining;
}

# 判断如果处理改换行符，是当成空格处理，还是直接忽略
sub update_when_new_line {
  my ($state)   = @_;
  my $char_info = $state->{current_char};
  my $string    = ${ $state->{original_text} };
  my $last_char = substr( $state->{current_line}{str} . $state->{current_word}{str}, -1 );

  # 换行符后面的字符串以空格开头，可以直接删除
  if ( substr( $string, $state->{pos} ) =~ m/\A(\s+)/ ) {
    $state->{pos} += length($1);
  }

  # 换行符后面的第一个非空字符
  my $next_char_info = $state->extract_next_char_info();

  # When the first character of the next line is CJK,
  # there is no need to add an extra space when merging lines.
  if (  $next_char_info->{width} > 1
    and $next_char_info->{type} ne "OTHER"
    and $last_char eq "" || $last_char eq SPACE || _char_attr( ord $last_char ) ne "OTHER" )
  {
    $char_info->{char}  = "";
    $char_info->{width} = 0;
  }
  else {
    $char_info->{char}  = SPACE;
    $char_info->{width} = 1;
  }
}

# 文本预处理函数
sub _clean_input_text {
  my ($text) = @_;

  # 标准化换行符
  $text =~ s/\r\n?/\n/g;

  # 移除首尾空白和多余空行
  $text =~ s/^\s+//mg;
  $text =~ s/\h+$//mg;
  $text =~ s/\n{3,}/\n\n/g;

  return $text;
}

# 独立语法处理函数
sub _handle_inline_syntax {
  my $state = shift;
  my $char  = $state->{current_char}{char};

  # 处理语法结束标记
  my $syn_end = $state->{inline_syntax_end}{$char};
  if ( defined $syn_end ) {
    for my $i ( 0 .. $#{$syn_end} ) {
      my $handler           = $syn_end->[$i];
      my $end_handle_result = _handle_inline_syntax_end( $handler, $state );
      if ($end_handle_result) {
        splice( @{ $state->{inline_syntax_end}{$char} }, $i, 1 );
        return 1;
      }
    }
  }

  if ( my $syn_start = $INLINE_SYNTAX->{$char} ) {
    $syn_start = [$syn_start] if ref($syn_start) ne ref( [] );
    for my $handler ( @{$syn_start} ) {
      my $start_handle_result = _handle_inline_syntax_start( $handler, $state );
      return 1 if $start_handle_result;
    }
  }

  return;
}

sub _handle_inline_syntax_end {
  my ( $handler, $state ) = @_;

  my $m = $handler->($state);
  return unless defined $m;

  $state->word_extend();

  my $end_len = $m->{end_len} // 1;
  for ( 1 .. ( $end_len - 1 ) ) {
    $state->shift_char();
    $state->word_extend();
  }

  $state->{current_word}{len} -= $m->{conceal} // 0;

  # 如果插入捕获的语法单元后，该行会超长，那么需要先断行，将语法单元放入行首
  # $char 已经合入 $word, 因此判断是否折行时，无须考虑 $char
  wrap_line($state);

  $state->line_extend();

  return 1;
}

sub _handle_inline_syntax_start {
  my ( $handler, $state ) = @_;
  my $m = $handler->($state);
  return unless defined $m;

  # 先将单词的内容清空，因为没有引入新字符，所以不用考虑折行的问题
  $state->line_extend();

  # 处理行内语法的起始标记
  $state->word_extend();

  my $start_len = $m->{start_len} // 1;
  for ( 1 .. ( $start_len - 1 ) ) {
    $state->shift_char();
    $state->word_extend();
  }
  $state->{current_word}{len} -= $m->{conceal} // 0;

  # 对于那些允许跨行的行内语法，像普通字符那样处理即可
  # 但需要记录结束条件，后进先出
  if ( $m->{wrap} ) {
    $state->{inline_syntax_end}{ $m->{endchar} } //= [];
    unshift @{ $state->{inline_syntax_end}{ $m->{endchar} } }, $m->{endprobe};
    return 1;
  }

  while ( $state->{pos} < $state->{text_length} ) {
    $state->shift_char();
    my $char_info = $state->{current_char};

    if ( $char_info->{char} eq NEW_LINE ) {
      update_when_new_line($state);
    }

    my $end_handle_result = _handle_inline_syntax_end( $m->{endprobe}, $state );

    last if defined $end_handle_result;
    $state->word_extend();
  }

  $state->push_line() if $state->{pos} >= $state->{text_length};

  # 一个字符可能时多个语法结构的起始字符，只要满足一个，就消耗掉该字符，不再考虑后续的语法
  # 只要满足特殊语法，那么该字符就会以特殊语法处理
  return 1;
}

# 最终处理逻辑
sub _finalize_processing {
  my ($state) = @_;

  $state->line_extend();
  $state->push_line();
}

# 生成最终输出
sub _generate_output {
  my ($state) = @_;

  # 清理行尾空白并连接结果
  my $result = join( "\n", map { s/\s+$//r } grep { length } @{ $state->{lines} } );

  # 保留原始段落结尾的换行
  $result .= "\n" if ${ $state->{original_text} } =~ /\n$/;

  return $result;
}

1;
