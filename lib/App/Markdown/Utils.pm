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

# 判断是否为Markdown表格行
# 匹配以竖线(|)或表格分隔线(+---)开头的行
sub is_table_line {
  my $str = shift;
  return $str =~ m{^\s*(\||\+[-=])}xms;
}

# 判断是否为Markdown标题行
# 返回类型："Setext"（下划线式标题）、"Atx"（井号式标题）或undef
sub is_header_line {
  my $str = shift;
  return "Setext" if $str =~ m/^ \s* (?:\={3,}|\-{3,}) \s* $/mxs;    # 匹配 === 或 ---
  return "Atx"    if $str =~ m/^ \s* [#]+ \s+/mxs;                   # 匹配 # 标题
  return;
}

sub is_list_first_line {
  my $str = shift;
  return 1 if $str =~ m/^ \s* (?:[-•*+]|\d+\.) \s/mxs;
  return 0;
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

# 计算字符串的缩进前缀
# 处理以下情况：
# 1. 普通缩进空格
# 2. 引用块前缀（>）
# 3. 列表项前缀（*, - 等）
# 4. 定义列表前缀（:）
sub indent {
  my $str = shift;

  # 定义各类前缀的正则表达式
  my $todo_regex  = qr/\[\w?\]\s+/xms;                                 # 匹配待办项如 [x]
  my $list_regex  = qr/(?:[-•*+]|\d+\.) \s+ (?:$todo_regex\s)?/xms;    # 列表项
  my $def_regex   = qr/(?:\: \s+)/xms;                                 # 定义列表
  my $quote_regex = qr/(?:\>\s)+/xms;                                  # 引用块

  # 组合匹配模式
  my $prefix = "";
  if (
    $str =~ m{\A
    (\s*)                     # 基础缩进空格
    ($quote_regex?)           # 引用标记
    ((?:$list_regex|$def_regex)?)  # 列表或定义标记
  }xms
    )
  {
    # 组合前缀：缩进 + 引用标记 + 列表/定义标记的等效空格
    $prefix = $1 . $2 . ( " " x length($3) );
  }
  return $prefix;
}

# 格式化引用块行
# 返回值：(前缀, 内容)
# 处理规则：
# 1. 连续的 > 转换为带空格的引用前缀
# 2. 引用符号后的4个空格转换为引用层级的缩进
sub format_quote_line {
  my ($input_line) = @_;
  my $quote_prefix = "";
  my $space_count  = 0;
  my $cursor_pos   = 0;

  # 遍历行首的引用标记和空格
  for ( ; $cursor_pos < length($input_line); $cursor_pos++ ) {
    my $current_char = substr( $input_line, $cursor_pos, 1 );

    # 处理引用标记
    if ( $current_char eq '>' ) {
      $quote_prefix .= "> ";    # 标准化引用前缀格式
      $space_count = 0;         # 重置空格计数器
      next;
    }

    # 统计连续空格（仅处理水平空白符）
    if ( $current_char =~ /\h/ ) {
      $space_count++;
      next;
    }

    # 遇到非空白字符时结束解析
    last;
  }

  # 处理Markdown的4空格缩进规则
  if ( $space_count >= 4 ) {
    $quote_prefix .= " " x 4;    # 将4空格转换为缩进
    $cursor_pos -= 4;            # 调整光标位置
  }

  # 截取剩余内容（排除已处理的前缀部分）
  my $content = substr( $input_line, $cursor_pos );

  return ( $quote_prefix, $content );
}

# 判断字符的排版属性（内部使用）
# 参数：字符的Unicode码点
# 返回值：
#   PUN_FORBIT_BREAK_AFTER - 禁止在此符号后换行
#   PUN_FORBIT_BREAK_BEFORE - 禁止在此符号前换行
#   CJK_PUN - 中日韩标点符号
#   CJK - 中日韩统一表意文字
#   OTHER - 其他字符
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
    0xff09,    # ） Fullwidth right parenthesis
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

  # 中日韩标点符号范围
  return "CJK_PUN"
    if (
      ( $u >= 0x3000 && $u <= 0x303F ) ||    # CJK符号和标点
      ( $u >= 0xFF00 && $u <= 0xFFEF ) ||    # 半角/全角形式
      ( $u >= 0xFE50 && $u <= 0xFE6F )       # 小写变体
    );

  # 中日韩统一表意文字范围
  return "CJK"
    if (
      ( $u >= 0x4E00  and $u <= 0x9FFF )  or    # CJK Unified Ideographs
      ( $u >= 0x3400  and $u <= 0x4DBF )  or    # CJK Unified Ideographs Extension A
      ( $u >= 0x20000 and $u <= 0x2A6DF ) or    # CJK Unified Ideographs Extension B
      ( $u >= 0x2A700 and $u <= 0x2B73F ) or    # CJK Unified Ideographs Extension C
      ( $u >= 0x2B740 and $u <= 0x2B81F ) or    # CJK Unified Ideographs Extension D
      ( $u >= 0x2B820 and $u <= 0x2CEAF ) or    # CJK Unified Ideographs Extension E
      ( $u >= 0x2CEB0 and $u <= 0x2EBEF ) or    # CJK Unified Ideographs Extension F
      ( $u >= 0x30000 and $u <= 0x3134F ) or    # CJK Unified Ideographs Extension G
      ( $u >= 0x31350 and $u <= 0x323AF ) or    # CJK Unified Ideographs Extension H
      ( $u >= 0xF900  and $u <= 0xFAFF )  or    # CJK Compatibility Ideographs
      ( $u >= 0x3100  and $u <= 0x312f )  or    # Bopomofo
      ( $u >= 0x31a0  and $u <= 0x31bf )  or    # Bopomofo Extended
      ( $u >= 0x2F800 and $u <= 0x2FA1F )       # CJK Compatibility Ideographs Supplement
    );
  return "OTHER";
}

1;
