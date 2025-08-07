package App::Markdown::Block;
use strict;
use warnings;
use Data::Dump qw/dump/;

use List::Util           qw(none);
use App::Markdown::Text  qw(wrap);
use App::Markdown::Utils qw( get_indent_prefix indent);

#############################################################################
# 构造函数：创建新的 Markdown 块对象
# 参数：
#   $class - 类名
#   $args  - 可选参数哈希引用，可包含：
#     text - 初始文本内容
#     type - 块类型（默认 normal）
#     attr - 属性哈希引用，可包含：
#       prefix         - 行前缀字符串
#       wrap           - 是否自动换行（默认 1）
#       add_empty_line - 是否添加空行（默认 0）
#       marker         - 块标记符号
#       empty          - 是否是空块（默认 1）
# 返回：App::Markdown::Block 对象
#############################################################################
sub new {
  my $class = shift;
  my $args  = shift || {};    # 确保总是有哈希引用

  # 初始化对象属性，合并用户自定义参数
  my $self = {
    text => "",
    type => "normal",
    attr => {
      prefix         => "",
      wrap           => 1,
      add_empty_line => 0,
      marker         => "",
      empty          => 1,
    },
    %$args    # 合并用户参数
  };

  # 深度合并 attr 属性
  if ( $args->{attr} ) {
    $self->{attr} = { %{ $self->{attr} }, %{ $args->{attr} } };
  }

  bless $self, $class;
  return $self;
}

#############################################################################
# 扩展块内容：追加文本并更新块状态
# 参数：
#   @_ - 要追加的文本内容（多个标量值）
# 注意：
#   追加内容后会自动将 empty 状态设为 0
#############################################################################
sub extend {
  my $self = shift;

  # 拼接所有参数作为新内容
  my $new_content = join( "", @_ );

  # 追加内容并更新状态
  $self->{text} .= $new_content;

  # 如果有实际内容，标记为非空块
  if ( $self->{attr}{empty} && length($new_content) > 0 ) {
    $self->{attr}{empty} = 0;
  }
}

#############################################################################
# 获取属性值：统一访问对象属性
# 参数：
#   $key - 属性名称，支持：
#           text/type/attr 直接访问顶层属性
#           其他属性访问 attr 哈希中的值
# 返回：对应的属性值，不存在时返回 undef
#############################################################################
sub get {
  my $self = shift;
  my $key  = shift or return undef;

  # 优先检查顶层属性
  if ( $key eq "text" || $key eq "type" || $key eq "attr" ) {
    return $self->{$key};
  }

  # 检查属性哈希
  return exists $self->{attr}{$key} ? $self->{attr}{$key} : undef;
}

#############################################################################
# 更新块属性：合并新的属性值
# 参数：
#   $args - 包含更新属性的哈希引用，可以是：
#           text - 更新文本内容
#           type - 更新块类型
#           attr - 合并属性哈希
# 注意：
#   使用浅合并策略更新属性，原有未指定的属性保持不变
#############################################################################
sub update {
  my ( $self, $args ) = @_;

  # 参数有效性检查
  return unless ref($args) eq 'HASH';

  # 更新顶层属性
  $self->{text} = $args->{text} if exists $args->{text};
  $self->{type} = $args->{type} if exists $args->{type};

  # 合并属性哈希
  if ( $args->{attr} && ref( $args->{attr} ) eq 'HASH' ) {
    $self->{attr} = { %{ $self->{attr} }, %{ $args->{attr} } };
  }
}

#############################################################################
# 生成格式化字符串：根据块属性生成最终 Markdown 内容
# 返回：
#   格式化后的字符串，包含适当的前缀、换行和空行
# 处理逻辑：
#   1. 空块直接返回空字符串
#   2. 自动换行模式使用 Text::wrap 进行格式化
#   3. 非换行模式直接添加前缀
#   4. 根据需要添加结尾空行
#############################################################################
sub tostring {
  my $self = shift;

  # 处理空块
  return "" if $self->get("empty");

  my $prefix  = $self->get("prefix") || "";
  my $content = $self->get("text");

  # 处理不同换行模式
  my $formatted;
  if ( $self->get("wrap") ) {

    # 自动换行模式
    my $indent       = indent($content);
    my $prefix_first = $prefix . $indent->[0];
    my $prefix_other = $prefix_first . $indent->[1];
    my $args         = { prefix_first => $prefix_first, prefix_other => $prefix_other, content => \$content };
    $formatted = ${ wrap($args) };
  }
  else {
    # 直接添加前缀模式
    my @contents = split /\n/, $content;
    push @contents, "" if scalar @contents == 0;
    $formatted = join( "\n", map { $prefix . $_ } @contents );
    $formatted .= "\n";    # 确保块结尾换行
  }

  # 添加结尾空行
  if ( $self->get("add_empty_line") ) {
    $formatted .= $prefix . "\n";
  }

  return $formatted;
}

1;
