package App::Markdown::Wrap;

use v5.30;
use strict;
use POSIX;
use warnings;
use Data::Dump qw(dump);
use utf8;
use open ':std', ':encoding(UTF-8)';
use List::Util          qw(any none);
use App::Markdown::Text qw(set_environemnt_variable);
use App::Markdown::Handler;
use App::Markdown::Utils qw(format_quote_line);

sub run {
  my $class             = shift;
  my %opt               = %{ shift() };
  my $handler           = App::Markdown::Handler->new( \%opt );
  my $ideographic_space = qr/　/;
  my $no_break_space    = qr/ /;
  local @ARGV = @_;

  set_environemnt_variable( \%opt );
  my @block_pids;
  my @contents;

  while (<>) {
    chomp;
    $_ =~ s/^(?:$ideographic_space|$no_break_space\s)+//;
    $_ .= "\n";

    my $current_prefix     = $handler->get("prefix");
    my $current_block_type = $handler->get("block")->get("type");

    # 嵌入结构
    if ( $current_prefix =~ m/\A[>]/ ) {
      my ( $q, $l ) = format_quote_line($_);
      my $prefix = substr( $q, 0, length($current_prefix) );
      if ( $prefix ne $current_prefix ) {
        if ( $_ !~ m/\S/ ) {
          $handler->update_prefix("");
          $handler->upload( { add_empty_line => 0 } );
        }
        elsif ( $q ne "" ) {
          $handler->update_prefix($q);
          $handler->upload();
          $_ = $l;
        }
      }
      else {
        $_ = substr( $q, length($current_prefix) ) . $l;
      }
    }

    # prefix 不同的行不能放在同一个 block, 以保证每个 block 有唯一的 prefix
    my $current_block = $handler->get("block");
    if ( $current_block->get("prefix") ne $handler->get("prefix") ) {
      if ( $handler->block_is_empty() ) {
        my $last_block = $handler->get("last_block");
        if ( defined $last_block and not $last_block->get("add_empty_line") ) {
          $current_block->extend("\n");
          $handler->upload();
        }
      }
      else {
        $handler->upload( { add_empty_line => 1 } );
      }
    }

    # YAML, 必须在文件开头
    next if $handler->yaml_header($_);

    # Quote, 引用可能包含其他结构，
    next if $handler->quote($_);

    # Div
    next if $handler->pandoc_div($_);

    # math
    next if $handler->math($_);

    # 代码块中的内容不折叠
    if ( $opt{tonewsboat} ) {
      s{^[ ]*\[/?code\][ ]*$}{```};
      s/^[ ]*([|]|[-]+[|][-]+)[ ]*$//;
      s/^[ ]+$//;
      next if m/\[\d+]\:\s*data\:image/;
    }

    # 代码块中的内容不折叠
    next if $handler->line_code_block($_);
    next if $handler->code_block($_);

    # table
    next if $handler->simple_table_line($_);
    next if $handler->pandoc_table_simple($_);
    next if $handler->pandoc_table_other($_);

    # header
    next if $handler->header_setext($_);
    next if $handler->header_atx($_);

    # Table rows and comment lines are output as is
    next if $handler->comment_line_as_sep($_);

    # Link ref line are output as is
    next if $handler->linkref_line_as_sep($_);

    # newsboat
    if ( $opt{tonewsboat} ) {
      next if $handler->tonewsboat_fetch_meta_info($_);
      next if $handler->tonewsboat_separator($_);
      next if $handler->tonewsboat_links_list($_);
      $_ = $handler->adjust_tonewsboat_image($_);
    }

    # Listings and quoted text are seListings and quoted text are segmented by special logicgmented by special logic
    #next if $handler->quote($_);
    next if $handler->line_can_sep_paragraph($_);

    next if $handler->normal_line($_);
  }

  $handler->upload() unless $handler->block_is_empty();

  @contents = map { $_->tostring() } @{ $handler->get("blocks") };

  if ( $opt{tonewsboat} ) {
    my $DATE   = $handler->{date};
    my $URL    = $handler->{url};
    my $TITLE  = $handler->{title};
    my $SOURCE = $handler->{source};
    unshift @contents, "\n"                   if any { defined $_ } $DATE, $URL, $TITLE, $SOURCE;
    unshift @contents, "Last Access: $DATE\n" if defined $DATE;
    unshift @contents, "Link: $URL\n"         if defined $URL;
    unshift @contents, "Title: $TITLE\n"      if defined $TITLE;
    unshift @contents, "Source: $SOURCE\n"    if defined $SOURCE;
  }

  print join "", @contents;
}

1;    # End of App::Markdown::Wrap
