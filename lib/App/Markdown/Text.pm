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
  DEFAULT_LINE_WIDTH   => 80,      # 默认行宽
  SPACE                => " ",     # 空格字符
  NEW_LINE             => "\n",    # 换行符
  ZERO_WIDTH_SPACE     => '​',     # 零宽空格
  SEPARATOR_SYMBOL     => "┄",     # 分隔线符号
  SUPPORT_SHORTER_LINE => 10,      # 偏好短行
  MAX_CONSECUTIVE_NL   => 1,       # 允许的最大连续换行数
};

my $REG_SENTENCE_END = qr/[,.:;?!]["')]?$/;
my $WRAP_SENTENCE    = 1;
my $LINE_WIDTH       = DEFAULT_LINE_WIDTH;    # 当前行宽配置
my $INLINE_SYNTAX    = get_syntax_meta();
my $KEEP_ORIGIN_WRAP = 0;

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

  $WRAP_SENTENCE    = $opt->{"wrap-sentence"}    if defined $opt->{"wrap-sentence"};
  $KEEP_ORIGIN_WRAP = $opt->{"keep-origin-wrap"} if defined $opt->{"keep-origin-wrap"};
}

sub wrap {
  my $args = shift // {};
  $args = {
    prefix_first     => "",
    prefix_other     => "",
    content          => \(""),
    wrap_sentence    => $WRAP_SENTENCE,
    keep_origin_wrap => $KEEP_ORIGIN_WRAP,
    %{$args}
  };

  # 段落处理优化：使用更明确的变量名和正则表达式
  my @paragraphs = grep { $_ =~ /\S/ } split /^\h*$/mxs, ${ $args->{content} };    # 使用\h匹配水平空白符
  if ( @paragraphs > 1 ) {
    my @outputs = map { wrap( { %{$args}, content => \$_ } ) } @paragraphs;
    my $output  = join "\n", map { ${$_} } @outputs;
    return \$output;
  }

  # 文本预处理管道
  my $processed_text = _clean_input_text( shift @paragraphs );
  return \("") if $processed_text eq q();

  # 初始化状态机
  my $state = App::Markdown::Text::State->new( { %{$args}, content => \$processed_text } );

  # 主处理循环
  _process_characters($state);

  # 后处理并生成最终输出
  return _post_processing($state);
}

# 主字符处理逻辑
sub _process_characters {
  my $state = shift;

  # 处理优先级队列（顺序敏感）
  my @handlers = (
    \&_handle_zero_width_space,         # 处理零宽空格
    \&_handle_final_newline,            # 最终换行符处理
    \&_handle_inline_syntax,            # 行内语法标记
    \&_handle_other_newline,            # 换行符转换
    \&_handle_wrap_forbidden_after,     # 禁止在当前字符之后换行
    \&_handle_wrap_forbidden_before,    # 禁止在当前字符之前换行
    \&_handle_with_remaining_room,      # 存在剩余空间的情况
    \&_handle_line_end_with_space,      # 空格结尾时的断行处理
    \&_handle_character_space,          # 末尾的空格处理
    \&_handle_character_cjk,            # CJK特殊处理
    \&_handle_default_case              # 默认处理
  );

  while ( $state->{pos} < $state->{text_length} ) {
    $state->next();
    next unless $state->is_valid_char();

    # 按优先级执行处理程序
    for my $handler (@handlers) {
      last if $handler->($state);
    }
  }
}

# 处理零宽空格
sub _handle_zero_width_space {
  my $state = shift;
  return 0 unless $state->{current_char}{char} eq ZERO_WIDTH_SPACE;
  $state->word_extend();
  $state->upload_word();
  return 1;
}

# 处理最终换行符
sub _handle_final_newline {
  my $state = shift;
  return 0 unless $state->{current_char}{char} eq NEW_LINE && $state->at_end_of_text();

  _finalize_processing($state);
  return 1;
}

# 独立语法处理函数
sub _handle_inline_syntax {
  my $state = shift;
  my $char  = $state->{current_char}{char};

  # 处理语法结束标记
  my $syn_end = $state->{inline_syntax_end}{$char};
  if ( defined $syn_end ) {
    for my $i ( 0 .. $#{$syn_end} ) {
      my $endprobe          = $syn_end->[$i];
      my $end_handle_result = _handle_inline_syntax_end( $endprobe, $state );
      if ($end_handle_result) {
        splice( @{ $state->{inline_syntax_end}{$char} }, $i, 1 );
        return 1;
      }
    }
  }

  # 处理语法开始标记
  if ( my $syn_start = $INLINE_SYNTAX->{$char} ) {
    $syn_start = [$syn_start] if ref($syn_start) ne ref( [] );
    for my $syn ( @{$syn_start} ) {
      my $start_handle_result = _handle_inline_syntax_start( $syn, $state );
      return 1 if $start_handle_result;
    }
  }

  return;
}

sub _handle_inline_syntax_end {
  my ( $endprobe, $state ) = @_;

  my $m = $endprobe->($state);
  return unless defined $m;

  my $mark_only = ( $state->{current_word}{len} == 0 );

  $state->word_extend();
  my $end_len = $m->{end_len} // 1;
  for ( 1 .. ( $end_len - 1 ) ) {
    $state->next();
    $state->word_extend();
  }

  $state->{current_word}{len} -= $m->{conceal} // 0;

  if ( $state->{wrap_sentence} ) {

    # 除非语法结束是当前单词只剩语法标记符，那么
    # 当插入捕获的语法单元后，该行会超长，那么需要先断行，将语法单元放入行首
    # $char 已经合入 $word, 因此判断是否折行时，无须考虑 $char
    wrap_line($state) unless $mark_only;

    $state->line_extend();
  }
  else {
    $state->sentence_extend();
  }

  return 1;
}

sub _handle_inline_syntax_start {
  my ( $syntax, $state ) = @_;
  my $m = $syntax->($state);
  return unless defined $m;

  # 先将单词的内容清空，因为没有引入新字符，所以不用考虑折行的问题
  $state->upload_word();

  # 处理行内语法的起始标记
  $state->word_extend();

  my $start_len = $m->{start_len} // 1;
  for ( 1 .. ( $start_len - 1 ) ) {
    $state->next();
    $state->word_extend();
  }
  $state->{current_word}{len} -= ( $m->{conceal} // 0 );

  # 对于那些允许跨行的行内语法，像普通字符那样处理即可
  # 但需要记录结束条件，后进先出
  if ( $m->{wrap} ) {
    unshift @{ $state->{inline_syntax_end}{ $m->{endchar} } }, $m->{endprobe};
    return 1;
  }

  while ( $state->{pos} < $state->{text_length} ) {
    $state->next();
    my $char_info = $state->{current_char};

    if ( $char_info->{char} eq NEW_LINE ) {
      update_when_new_line($state);
    }

    my $end_handle_result = _handle_inline_syntax_end( $m->{endprobe}, $state );

    last if defined $end_handle_result;
    $state->word_extend();
  }

  if ( $state->{pos} >= $state->{text_length} ) {
    $state->word_upload() if $state->{current_word}->{str} ne "";
    $state->line_extend() if not $state->{wrap_sentence} and $state->{current_sentence}->{str} ne "";
    $state->push_line();
  }

  # 一个字符可能时多个语法结构的起始字符，只要满足一个，就消耗掉该字符，不再考虑后续的语法
  # 只要满足特殊语法，那么该字符就会以特殊语法处理
  return 1;
}

# 处理换行符转换
sub _handle_other_newline {
  my $state = shift;
  return 0 unless $state->{current_char}{char} eq NEW_LINE;
  if ( $state->{keep_origin_wrap} ) {
    $state->upload_word();
    $state->line_extend() unless $state->{wrap_sentence};
    $state->push_line();
    return 1;
  }
  elsif ( $state->{previous_char}{char} eq ZERO_WIDTH_SPACE ) {
    $state->line_extend();
    $state->push_line();
    return 1;
  }

  my $sub_char = update_when_new_line($state);
  return ( $sub_char eq "" );
}

# line wrap are not allowed before the current letter
sub _handle_wrap_forbidden_before {
  my ($state) = @_;

  # Early return if sentence wrapping is disabled
  return unless $state->{wrap_sentence};

  my $char_info      = $state->{current_char};
  my $next_char_info = $state->extract_next_char_info();
  my $char           = $char_info->{char};
  my $char_attr      = $char_info->{type};

  # Define forbidden wrap characters for efficient lookup
  my $forbidden_chars = '\'",.!;:?])}';
  my %forbidden_chars = map { $_ => 1 } split //, $forbidden_chars;

  # Check if character is forbidden to start a line
  return
    unless $char_attr eq "PUN_FORBIT_BREAK_BEFORE"
    || exists $forbidden_chars{$char};

  # Build string before current character efficiently
  my $string_before_char = join( '',
    $state->{current_line}{str}     // '',
    $state->{current_sentence}{str} // '',
    $state->{current_word}{str}     // '' );

  # Remove prefix if string is long enough
  my $prefix_length = length( $state->{prefix}{other} // '' );
  if ( length($string_before_char) >= $prefix_length ) {
    $string_before_char = substr( $string_before_char, $prefix_length );
  }

  # Handle character placement based on preceding content
  if ( $string_before_char =~ /^\s*$/ && @{ $state->{lines} } > 0 ) {

    # Append to previous line if current content is only whitespace
    $state->{lines}[-1] .= $char;
  }
  else {
    # Extend current word and upload it
    $state->word_extend();
    $state->upload_word() if $char_info->{type} ne "OTHER" || $next_char_info->{type} ne "OTHER";
  }

  return 1;
}

# line wrap are not allowed after the current letter
sub _handle_wrap_forbidden_after {
  my ($state) = @_;

  # Early return if sentence wrapping is disabled
  return unless $state->{wrap_sentence};

  my $char_info      = $state->{current_char};
  my $next_char_info = $state->extract_next_char_info();
  my $char           = $char_info->{char};
  my $char_attr      = $char_info->{type};
  my $next_char      = $next_char_info->{char};
  my $next_char_attr = $next_char_info->{type};

  # Define forbidden wrap characters for efficient lookup
  my $forbidden_chars       = ',.!;:?])}';
  my $forbidden_chars_after = '\'"(';
  my %forbidden_chars       = map { $_ => 1 } split //, $forbidden_chars;
  my %forbidden_chars_after = map { $_ => 1 } split //, $forbidden_chars_after;

  # Check if next character is forbidden to start a line or current character is forbidden to wrap after
  return
    unless ( $char_attr eq "PUN_FORBIT_BREAK_AFTER" || exists $forbidden_chars_after{$char} )
    || ( $next_char_attr eq "PUN_FORBIT_BREAK_BEFORE" || exists $forbidden_chars{$next_char} );

  if ( $char_info->{width} == 0 || $char eq SPACE ) {
    $state->upload_word();
  }
  elsif ( $char_info->{type} ne "OTHER" ) {
    $state->upload_non_word_character();
  }
  else {
    $state->word_extend();
  }

  return 1;
}

# 存在足够空间的情况
# whether the current line have enough room for the curren character
sub _handle_with_remaining_room {
  my ($state) = @_;
  my $char_info = $state->{current_char};
  my ( $remaining_space, $exceed_when_not_wrap ) = remaining_space($state);
  return if $remaining_space <= 0;

  my $wrap_sentence = $state->{wrap_sentence};

  if ( $char_info->{width} == 0 ) {
    $state->upload_word();
    $state->push_line() if $wrap_sentence and $exceed_when_not_wrap >= 0;
    return 1;
  }

  if ( $char_info->{char} eq SPACE ) {
    $state->upload_word();
    my $sentence_end = ( not $wrap_sentence and $state->{current_sentence}{str} =~ m/$REG_SENTENCE_END/ );
    $state->line_extend() if $sentence_end;
    if ( ( $exceed_when_not_wrap >= 0 and ( $wrap_sentence or $sentence_end ) )
      or ( not $wrap_sentence and _sentence_end( $state->{current_line}{str} ) ) )
    {
      $state->push_line();
      return 1;
    }
    $state->upload_non_word_character();
    return 1;
  }

  if ( $char_info->{type} ne "OTHER" ) {
    my $char = $char_info->{char};
    $state->upload_non_word_character();
    if ( $state->{wrap_sentence} ) {
      $state->push_line() if $exceed_when_not_wrap >= 0;
    }
    elsif ( grep { $char eq $_ } qw{、 。 ） ， ． ： ； ？ } ) {
      $state->line_extend();
      $state->push_line() if $exceed_when_not_wrap >= 0 or _sentence_end($char);
    }
    return 1;
  }

  $state->word_extend();
  return 1;
}

# the line ends by space
sub _handle_line_end_with_space {
  my ($state) = @_;
  my $line    = $state->{current_line};
  my $word    = $state->{current_word};

  $state->upload_word() if $word->{str} =~ m/^\s+$/;
  return                if $word->{str} ne "";
  return                if substr( $line->{str}, length( $state->{prefix}{other} ) ) !~ m/(\s+)$/;
  my $trail_space_number = length($1);

  if ( $trail_space_number == 1 ) {
    $line->{str} = substr( $line->{str}, 0, -1 );
    $line->{len} -= 1;
    $state->push_line();
  }
  else {
    $line->{str} = substr( $line->{str}, 0, -$trail_space_number + 1 );
    $line->{len} -= ( $trail_space_number - 1 );
  }

  $state->word_extend();
  return 1;
}

# 没有空间的情况下处理空格符
#
# handle space
sub _handle_character_space {
  my ($state) = @_;
  my $char_info = $state->{current_char};

  my $char = $char_info->{char};
  return unless $char eq "" or $char =~ m/\A \s+ \z/mxs;

  my $line = $state->{current_line};

  # 可以在句子内部折行时，在空格处断行
  if ( $state->{wrap_sentence} ) {
    if ( $line->{str} eq "" ) {
      $state->line_extend();
      $state->push_line();
      return 1;
    }
    $state->push_line();
    $state->word_extend();
    if ( $state->{current_word}{str} =~ s/^(\s+)// ) {
      $state->{current_word}{len} -= length($1);
    }
    $state->upload_word() if $state->{current_word}{str} ne "";
    return 1;
  }

  # 否则，只能在句子末尾断行，或到
  $state->upload_word();
  if ( $state->{current_sentence}{str} =~ m/$REG_SENTENCE_END/ or $char eq "" ) {
    if ( $line->{str} eq "" ) {
      $state->line_extend();
      $state->push_line();
      return 1;
    }

    $state->push_line();
    if ( $state->{current_sentence}{str} =~ s/^(\s+)// ) {
      $state->{current_sentence}{len} -= length($1);
    }
    $state->line_extend() if $state->{current_sentence}{str} ne "";
    if ( not $state->{wrap_sentence} and _sentence_end( $state->{current_line}{str} ) ) {
      $state->push_line();
      return 1;
    }
  }
  $state->upload_non_word_character();

  return 1;
}

# 处理中日韩字符
sub _handle_character_cjk {
  my ($state) = @_;

  # 获取当前字符、行和词状态
  my $char_info = $state->{current_char};
  my $char      = $char_info->{char};
  my $line      = $state->{current_line};
  my $word      = $state->{current_word};

  # 仅处理CJK字符和中文标点
  return if $char_info->{type} ne "CJK" and $char_info->{type} !~ 'PUN';

  if ( not $state->{wrap_sentence} and none { $char eq $_ } qw{、 。 ） ， ． ： ； ？ } ) {
    $state->upload_non_word_character();
    return 1;
  }

  if ( $state->{current_line}{str} eq "" ) {
    $state->upload_non_word_character();
    $state->line_extend() unless $state->{wrap_sentence};
    $state->push_line();
    return 1;
  }

  $state->push_line();    # 创建新行并应用other前缀
  if ( $state->{wrap_sentence} ) {
    if ( $state->{current_word}{str} =~ s/^(\s+)// ) {
      $state->{current_word}{len} -= length($1);
    }
  }
  else {
    if ( $state->{current_sentence}{str} =~ s/^(\s+)// ) {
      $state->{current_sentence}{len} -= length($1);
    }
  }
  $state->upload_non_word_character();
  $state->line_extend() unless $state->{wrap_sentence};
  $state->push_line() if _sentence_end($char);

  return 1;    # 已处理CJK字符
}

# 默认处理程序
# 只在非单词字符（空格或 CJK 字符）处断行
# 其他字符会先存在 current word 中，直到遇到非单词字符，再进行换行处理
sub _handle_default_case {
  my $state = shift;
  $state->push_line();    # 创建新行并应用other前缀
  if ( $state->{wrap_sentence} ) {
    if ( $state->{current_word}{str} =~ s/^(\s+)// ) {
      $state->{current_word}{len} -= length($1);
    }
  }
  else {
    if ( $state->{current_sentence}{str} =~ s/^(\s+)// ) {
      $state->{current_sentence}{len} -= length($1);
    }
  }
  $state->word_extend();
  return 1;
}

# 辅助函数

# 后处理管道
sub _post_processing {
  my ($state) = @_;

  # 清理行尾空格
  my $result = join( "\n", grep { length } map { s/\s+$//r } @{ $state->{lines} } );

  # 保留原始换行特征
  $result .= "\n" if substr( ${ $state->{original_text} }, -1 ) eq "\n";

  # 优化连续空行
  $result =~ s/\n{3,}/\n\n/g;

  return \$result;
}

sub wrap_line {
  my $state      = shift;
  my $free_space = remaining_space($state);
  return if $free_space > 0;
  $state->push_line();
  return 1;
}

sub cal_remaining_space {
  my ( $origin, $new, $line_width ) = @_;
  $line_width //= $LINE_WIDTH;
  my $exceed_space      = $new - $line_width;
  my $origin_remainning = $line_width - $origin - SUPPORT_SHORTER_LINE;
  my $remaining_space   = ( $origin_remainning > 0 ? $origin_remainning : 0 ) - $exceed_space;
  return $remaining_space, $exceed_space;
}

sub remaining_space {
  my ($state)  = @_;
  my $line     = $state->{current_line};
  my $sentence = $state->{current_sentence};
  my $word     = $state->{current_word};
  my $char     = $state->{current_char};

  # 计算总显示长度（当前行 + 当前词 + 下个字符）
  my $total_visible_length = $line->{len} + $sentence->{len} + $word->{len} + $char->{width};

  # 基础剩余空间计算
  my ( $remaining, $exceed ) = cal_remaining_space( $line->{len}, $total_visible_length );

  # 处理长单词溢出情况
  if ( $remaining <= 10 ) {
    my $newline = { str => $line->{str}, len => $line->{len} };

    my $string_extend = App::Markdown::Text::State->can("_string_extend");
    $string_extend->( $newline, $sentence );
    $string_extend->( $newline, $word );
    $string_extend->( $newline, { str => $char->{char}, len => $char->{width} } );

    $total_visible_length = $newline->{len};
    ( $remaining, $exceed ) = cal_remaining_space( $line->{len}, $total_visible_length );
  }

  if (wantarray) {
    return $remaining, $exceed;
  }
  else {
    return $remaining;
  }
}

# 换行符的处理：是当成空格处理，还是直接忽略
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
    return "";    # 直接忽略这个换行符
  }
  else {
    $char_info->{char}  = SPACE;
    $char_info->{width} = 1;
    return SPACE;    # 让后续 handler 继续处理
  }
}

# 文本预处理函数
sub _clean_input_text {
  my ($text) = @_;
  return "" unless defined $text and $text =~ m/\S/;

  # 标准化换行符
  $text =~ s/\r\n?/\n/g;

  # 移除首尾空白和多余空行
  $text =~ s/^\s+//mg;
  $text =~ s/\h+$//mg;
  $text =~ s/\n{3,}/\n\n/g;

  return $text;
}

# 最终处理逻辑
sub _finalize_processing {
  my ($state) = @_;
  $state->upload_word();
  $state->line_extend() unless $state->{wrap_sentence};
  $state->push_line();
  $state->{pos} = $state->{text_length};
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

sub _sentence_end {
  my $str = shift or return;
  return ( any { $str eq $_ } qw{ 。 ． ； ？ } or $str =~ m/[.;?!]["')]?$/ );
}

# 当前是否允许折行

1;
