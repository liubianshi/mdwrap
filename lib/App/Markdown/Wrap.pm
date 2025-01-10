package App::Markdown::Wrap;

use v5.30;
use strict;
use warnings;
use Data::Dump qw(dump);
use utf8;
use open ':std', ':encoding(UTF-8)';
use List::Util           qw(any none);
use App::Markdown::Text  qw(set_environemnt_variable);
use App::Markdown::Block qw(
  upload_block_to_contents
  block_extend
);
use App::Markdown::Handler;

sub run {
  my $class   = shift;
  my %opt     = %{ shift() };
  my $handler = App::Markdown::Handler->new( \%opt );
  dump %opt;
  local @ARGV = @_;

  set_environemnt_variable( \%opt );

  while (<>) {
    chomp;
    $_ .= "\n";

    # YAML
    next if $handler->yaml_header($_);

    # Div
    next if $handler->pandoc_div($_);

    # math
    next if $handler->math($_);

    # 代码块中的内容不折叠
    if ( $opt->{tonewsboat} ) {
      s{^[ ]*\[/?code\][ ]*$}{```};
      s/^[ ]*([|]|[-]+[|][-]+)[ ]*$//;
      s/^[ ]+$//;
      next if m/\[\d+]\:\s*data\:image/;
    }

    # 代码块中的内容不折叠
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

    # newsboat
    if ( $opt->{tonewsboat} ) {
      next if $handler->tonewsboat_fetch_meta_info($_);
      next if $handler->tonewsboat_separator($_);
      next if $handler->tonewsboat_links_list($_);
      $_ = $handler->adjust_tonewsboat_image($_);
    }

    # Listings and quoted text are seListings and quoted text are segmented by special logicgmented by special logic
    next if $handler->quote($_);
    next if $handler->line_can_sep_paragraph($_);

    next if handle_normal_line($_);
  }

  $handler->upload() unless $handler->block_is_empty();

  my @contents = map { $_->tostring() } %{ $handler->get_content() };

  if ( $opt{tonewsboat} ) {
    unshift @contents, "\n"                   if any { defined $_ } $DATE, $URL, $TITLE, $SOURCE;
    unshift @contents, "Last Access: $DATE\n" if defined $DATE;
    unshift @contents, "Link: $URL\n"         if defined $URL;
    unshift @contents, "Title: $TITLE\n"      if defined $TITLE;
    unshift @contents, "Source: $SOURCE\n"    if defined $SOURCE;
  }

  print join "", @contents;
}

1;    # End of App::Markdown::Wrap
