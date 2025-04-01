package App::Markdown::Handler;

use strict;
use warnings;
use utf8;
use Data::Dump           qw(dump);
use List::Util           qw(any);
use App::Markdown::Utils qw(
  is_header_line
  is_table_line
  is_list_first_line
  is_link_list
  is_definition_header
  format_quote_line
);
use App::Markdown::Block;

sub new {
  my $class = shift;
  my $args  = shift;
  my $self  = {
    blocks       => [],
    block        => App::Markdown::Block->new(),
    last_block   => undef,
    prefix       => "",
    title        => undef,
    url          => undef,
    date         => undef,
    source       => undef,
    tonewsboat   => 0,
    seperator    => "┄",
    'line-width' => 80,
    images       => [],
  };
  for ( keys %$self ) {
    if ( defined $args->{$_} ) {
      $self->{$_} = $args->{$_};
    }
  }
  bless $self, $class;
  return $self;
}

sub upload {
  my ( $self, $attr ) = @_;
  my $block = $self->{block};
  $block->update( { attr => { %{ $attr // {} } } } );
  $self->{last_block} = $self->{block};
  push @{ $self->{blocks} }, $self->{block};
  $self->{block} = App::Markdown::Block->new();
  $self->{block}->update( { attr => { prefix => $self->get("prefix") } } );
}

sub get_contents {
  my $self = shift;
  return $self->{contents};
}

sub get {
  my ( $self, $key ) = @_;
  return $self->{$key};
}

sub block_is_empty {
  my $self  = shift;
  my $block = $self->{block};
  $block->get("text") eq "";
}

# YAML header
sub yaml_header {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  my $btype = $block->get("type");
  return if $self->get("prefix") ne "";
  if (  ( $btype ne "yaml" )
    and ( defined $self->{last_block} or $block->get('text') ne "" ) )
  {
    return;
  }

  my $match_yaml_symbol = $line =~ m/^\s*\-{3,}\s*$/;
  return if $btype ne "yaml" and not $match_yaml_symbol;

  $block->extend($line);
  if ($match_yaml_symbol) {
    if ( $btype eq "yaml" ) {
      $self->upload( { add_empty_line => 1 } );
    }
    else {
      $block->update( { type => "yaml", attr => { wrap => 0 } } );
    }
  }

  return 1;
}

# Ordinary row processing
sub normal_line {
  my ( $self, $line ) = @_;

  my $block = $self->{block};
  my $btype = $block->get("type");

  # 保留特意插入的空行
  if ( $line !~ m/\S/ ) {
    if ( $self->block_is_empty() ) {
      my $last_block = $self->{last_block};
      if ( defined $last_block and not $last_block->get("add_empty_line") ) {
        $self->{block}->extend("\n");
        $block->update( { attr => { wrap => 0 } } );
        $self->upload();
      }
    }
    else {
      $self->upload( { add_empty_line => 1 } );
    }
    return 1;
  }

  $self->{block}->extend($line);
  return 1;
}

# Pandoc div: :::
sub pandoc_div {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  return if $block->get("type") ne "normal";

  if ( $line =~ m/^[:]{3, }/ ) {
    $self->upload() unless $self->block_is_empty();
    $self->{block}->extend($line);
    $self->upload();
    return 1;
  }
  return;
}

## math
sub math {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  my $btype = $block->get("type");
  my $mtype = $block->get("marker");

  # end
  if (
    $btype eq "math"
    and (( $mtype eq "markdown" and $line =~ m/\s*\$\$/ )
      or ( $mtype eq "latex" and $line =~ m/\s*\\\]/ ) )
     )
  {
    $block->extend($line);
    $self->upload();
    return 1;
  }

  # continue
  if ( $btype eq "math" ) {
    $block->extend($line);
    return 1;
  }

  # start
  if ( $btype eq "normal" and $line =~ m/\s*(\$\$|\\\[)\s*$/ ) {
    $self->upload() unless $self->block_is_empty();
    $block->update(
      {
        text => $line,
        type => "math",
        attr => {
          prefix         => $self->get("prefix"),
          wrap           => 0,
          add_empty_line => 0,
          marker         => $1 eq '$$' ? "markdown" : "latex",
        }
      }
    );
    return 1;
  }

  return;
}

## code block
sub code_block {
  my ( $self, $line ) = @_;
  my $block   = $self->{block};
  my $btype   = $block->get("type");
  my $bmarker = $block->get("marker");

  # end
  if (  $btype eq "code"
    and $line =~ m/^ (\s* [`~]{3,})/mxs
    and $1 eq $bmarker )
  {
    if ( $block->get("empty") ) {
      return 1;
    }

    $block->extend($line);
    my $block_text = $block->get("text");
    $block_text =~ s/\h+\n/\n/g;
    $block_text =~ s/\A(\s*[`~]{3,}[^\n]*\n)(?:\s*\n)+/$1/;
    $block_text =~ s/(?:\n\s*)+(\n[`~]{3,}\s*\n+)\z/$1/;
    $block->update( { text => $block_text } );
    $self->upload( { add_empty_line => 0 } );

    return 1;
  }

  # continue
  if ( $btype eq "code" ) {
    if ( $line =~ m/^ (\s* [`~]{3,})/mxs and length($1) > length($bmarker) ) {
      $block->update(
        {
          attr => {
            marker => $1,
            empty  => $block->get("empty"),
          }
        }
      );
    }
    $block->extend($line);

    return 1;
  }

  # start
  if ( ( $btype eq "normal" or $btype eq "list" ) and $line =~ m/^ (\s* [`~]{3,})/mxs ) {
    $self->upload( { add_empty_line => 1 } ) unless $self->block_is_empty();
    $self->{block}->update(
      {
        text => $line,
        type => "code",
        attr => {
          prefix         => $self->get("prefix"),
          marker         => $1,
          wrap           => 0,
          empty          => 1,
          add_empty_line => 0,
        }
      }
    );
    return 1;
  }

  return;
}

# pandoc table: simple_table_line
#  abc abc
#  --- ---
#  1   2
sub pandoc_table_simple {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  return if $block->get("type") ne "normal";

  my $empty_line = ( $line !~ m/\S/ );
  my $tblock     = $block->get("type");
  my $mblock     = $block->get("marker");

  # end: empty line
  if ( $tblock eq "table" and $mblock eq "oneline" and $empty_line ) {
    $self->upload( { add_empty_line => 1 } );
    return 1;
  }

  # continue
  if ( $tblock eq "table" and $mblock eq "oneline" ) {
    $block->extend($line);
    return 1;
  }

  # start
  if (
    $line =~ m/^\s* [|]? \s* [:]? \s* [-]{3,} [:|\s-]* $/mxs
    and not $self->block_is_empty()    # 和 headless table 的区别所在
    and $tblock eq "normal"
    )
  {
    $block->update(
      {
        type => "table",
        attr => {
          prefix         => $self->get("prefix"),
          marker         => "oneline",
          wrap           => 0,
          add_empty_line => 0,
        }
      }
    );
    $block->extend($line);
    return 1;
  }

  return;
}

# pandoc table: multi and headless
sub pandoc_table_other {
  my ( $self, $line ) = @_;
  my $empty_line = ( $line !~ m/\S/ );
  my $block      = $self->{block};
  my $tblock     = $block->get("type");
  my $mblock     = $block->get("marker");

  # start: special seperator line after empty line
  if (  $self->block_is_empty()
    and $tblock eq "normal"
    and $line =~ m/^\s* [|]? \s* [:]? \s* [-]{3,} [:|\s-]* $/mxs )
  {
    $block->update(
      {
        text => $line,
        type => "table",
        attr => {
          prefix         => $self->get("prefix"),
          marker         => "pandoc-start",
          wrap           => 0,
          add_empty_line => 1,
          empty          => 0,
        }
      }
    );
    return 1;
  }

  # end: empty line after special seperator line
  if (  $tblock eq "table"
    and $mblock eq "pandoc-start"
    and $empty_line )
  {
    $block->update(
      {
        type => 'sepline',
        attr => {
          marker         => "",
          wraop          => 0,
          add_empty_line => 1,
          empty          => 0
        }
      }
    );
    $self->upload();
    return 1;
  }

  if (  $tblock eq "table"
    and $mblock eq "pandoc-sep"
    and $empty_line )
  {
    $self->upload( { add_empty_line => 1 } );
    return 1;
  }

  # continue
  if ( $tblock eq "table" and $mblock =~ m/^pandoc/ ) {
    if (m/^\s* [-]{3,} (?:\s+|[-]{3,})* $/mxs) {
      $block->update( { attr => { marker => "pandoc-sep" } } );
    }
    else {
      $block->update( { attr => { marker => "pandoc-norm" } } );
    }
    $block->extend($line);
    return 1;
  }

  return;
}

## table simple
#  | abc | cde |
#  | --- | --- |
#  | cde | dafe |
sub simple_table_line {
  my ( $self, $line ) = @_;

  if ( is_table_line($line) ) {
    $self->upload() unless $self->block_is_empty();
    $self->{block}->extend($line);
    $self->upload( { wrap => 0, add_empty_line => 0 } );
    return 1;
  }
  return;
}

## header setext
sub header_setext {
  my ( $self, $line ) = @_;
  my $block  = $self->{block};
  my $tblock = $block->get("type");
  my $mblock = $block->get("marker");

  # continue and end
  if ( $tblock eq "header" and $mblock eq "setext" ) {
    if ( $line =~ m/\S/ ) {    # correct to pandoc simple table
      $block->update(
        {
          type => 'table',
          attr => {
            marker => "oneline",
            wrap   => 0,
          }
        }
      );
      $block->extend($line);
    }
    else {
      $self->upload( { add_empty_line => 1, wrap => 0 } );
    }
    return 1;
  }

  # start
  if (  ( is_header_line($line) // "" ) eq "Setext"
    and not $self->block_is_empty()
    and $tblock eq "normal" )
  {
    $block->update(
      {
        type => 'header',
        attr => { marker => "setext", wrap => 0, add_empty_line => 1 },
      }
    );
    $block->extend($line);
    return 1;
  }

  return;
}

## header atx
sub header_atx {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  return if $block->get("type") ne "normal";

  if ( ( is_header_line($line) // "" ) eq "Atx"
    and $self->block_is_empty() )
  {
    $block->update(
      {
        type => "header",
        attr => {
          marker         => "atx",
          wrap           => 0,
          add_empty_line => 1,
        }
      }
    );
    $block->extend($line);
    $self->upload();
    return 1;
  }

  return;
}

# Table rows and comment lines are output as is
sub comment_line_as_sep {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  return if $block->get("type") ne "normal";

  if ( $line =~ m/^\s* (?:\<!\-\-.*\-\-\>) \s*$/mxs ) {
    $self->upload() unless $self->block_is_empty();
    $self->{block}->extend("$line");
    $self->upload( { wrap => 0, add_empty_line => 0 } );
    return 1;
  }
  return;
}

# Link ref line are output as is
sub linkref_line_as_sep {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  return if $block->get("type") ne "normal";
  if ($line =~ m/^ \s* \[\d+\]: \s+ http/imxs) {
    $self->upload() unless $self->block_is_empty();
    $self->{block}->extend("$line");
    $self->upload( { wrap => 0, add_empty_line => 0 } );
    return 1;
  }
  return;
}

# newsboat
sub tonewsboat_fetch_meta_info {
  my ( $self, $line ) = @_;

  # Find Title
  if ( not defined $self->{title} and m/^TITI?LE:$/mxs ) {
    $self->{title} = "";
    return 1;
  }
  if ( defined $self->{title} and $self->{title} eq "" ) {
    return 1 unless m/\S/;
    if   (m/^ \s* \* \s+ ([^\n]*) $/mxs) { $self->{title} = $1 }
    else                                 { $self->{title} = undef }
    return 1;
  }

  # Find URL
  if ( not defined $self->{url} and m/^URL$/mxs ) {
    $self->{url} = "";
    return 1;
  }
  if ( defined $self->{url} and $self->{url} eq "" ) {
    return 1 unless m/\S/;
    if    (m/^ \s* \* \s+ \< ([^\n]*) \> $/mxs)            { $self->{url} = $1 }
    elsif (m/^ \s* \* \s+ \[ ([^\]]+) \]\[\d+\] \s* $/xms) { $self->{url} = $1 }
    else                                                   { $self->{url} = undef }
    return 1;
  }

  # Find Date
  if ( not defined $self->{date} and m/^DOWNLOAD_DATE$/mxs ) {
    $self->{date} = "";
    return 1;
  }
  if ( defined $self->{date} and $self->{date} eq "" ) {
    return 1 unless m/\S/;
    if   (m/^ \s* \* \s+  ([^\n]*)  $/mxs) { $self->{date} = $1 }
    else                                   { $self->{date} = undef }
    return 1;
  }

  # Source
  if ( not defined $self->{source} and m/^\[([^\]]+)\]\[1\]\s*$/xms ) {
    $self->{source} = $1;
    return 1;
  }
  return;
}

sub tonewsboat_separator {
  my ( $self, $line ) = @_;
  if ( $self->block_is_empty()
    and m{ ^ (\s*) \* (?:\s\*){2,} \s* $}xms )
  {
    $self->{block}->update(
      {
        text => "\n" . ( $self->{seperator} x $self->{"line-width"} ) . "\n"
      }
    );
    $self->upload();
    return 1;
  }
  return;
}

sub tonewsboat_links_list {
  my ( $self, $line ) = @_;
  return unless m/^ \s* \[(\d+)\]\: \s+ http/mxs;
  my $link_id = $1;
  if ( any { $link_id == $_ } @{ $self->{images} } ) {
    $line =~ s/\n*\z/ (image)\n/;
  }
  else {
    $line =~ s/\n*\z/ (link)\n/;
  }
  $line =~ s/^\s*//mxs;
  $line = "Links:\n$line" if $link_id == 1;
  $self->{block}->update(
    type => "image",
    attr => {
      wrap           => 0,
      add_empty_line => 0,
    }
  );
  $self->{block}->extend($line);
  $self->upload();
  return 1;
}

sub adjust_tonewsboat_image {
  my ( $self, $line ) = @_;
  if (
    $line =~ s{
            \! \[ ([^]]*) \]\[ (\d+) \]
        }{
           "[image $2 (link #$2)]" . ($1 eq "" ? "" : " $1")
        }egxms
    )
  {
    push @{ $self->{images} }, $2;
  }
  return $line;
}

sub quote {
  my ( $self, $line ) = @_;
  return if $line !~ m/\A\s*[>]/;
  return if $line =~ m/\A\s{4,}/;    ## 如缩进 4 个空格，那么应当成代码块处理
  return if $self->{block}->get("type") ne "normal";
  $self->upload();

  $line =~ s/\A\s+//;
  my $prefix;
  ( $prefix, $line ) = format_quote_line($line);

  $self->update_prefix( $self->get("prefix") . $prefix );
  my $block = $self->{block};
  $block->update( { attr => { prefix => $self->get("prefix") } } );
  $block->extend($line) if $line ne "";

  # callout title need in seperate line
  if ( $line =~ m/\A \s* \[ \! [^\]\s]+ \] /xms ) {
    $self->upload( { wrap => 0, add_empty_line => 0 } );
  }

  return 1;
}

sub line_can_sep_paragraph {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  return if $block->get("type") ne "normal" and $block->get("type") ne "list";

  if ( is_list_first_line($line)
    || is_link_list($line)
    || is_definition_header($line) )
  {
    $line =~ s{ ^ (\s*) [-*+] \s}{$1 • }xms if $self->{tonewsboat};
    $self->upload() unless $self->block_is_empty();
    $self->{block}->update( { type => "list" } );
    $self->{block}->extend($line);
    return 1;
  }

  return;
}

sub line_code_block {
  my ( $self, $line ) = @_;
  my $block = $self->{block};
  return if $block->get("type") ne "normal";
  return if $line !~ m/\A\h{4,}/;

  $self->upload() unless $self->block_is_empty();
  $self->{block}->extend($line);
  $self->upload( { wrap => 0, add_empty_line => 0 } );
  return 1;
}

sub update_prefix {
  my ( $self, $value ) = @_;
  $self->{prefix} = $value // "";
}

1;
