package App::Markdown::Utils;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(
  get_indent_prefix
  is_table_line
  is_header_line
  is_list_first_line
  is_link_list
  is_definition_header
  indent
);

sub get_indent_prefix {
  my $str    = shift;
  my $prefix = "";

  my $todo_regex  = qr/\[\w?\]\s+/xms;
  my $list_regex  = qr/(?:[-•*+]|\d+\.) \s+ (?:\s$todo_regex)?/xms;
  my $def_regex   = qr/(?:\: \s+)/xms;
  my $quote_regex = qr/\>+\s+/;

  # Quatation may contain list structures
  if ( $str =~ m{\A  (\s*) ($quote_regex?) ((?:$list_regex|$def_regex)?) }mxs ) {
    $prefix = $1 . $2 . ( "" x length($3) );
  }
  return $prefix;
}

sub is_table_line {
  my $str = shift;
  return 1 if $str =~ m{^\s*(\||\+[-=])}xms;
  return 0;
}

sub is_header_line {
  return "Setext" if m/^ \s* (?:\={3,}|\-{3,}) \s* $/mxs;
  return "Atx"    if m/^ \s* [#]+ \s+/mxs;
  return;
}

sub is_list_first_line {
  my $str = shift;
  return scalar( $str =~ m/^ \s* (?:[-•*+]|\d+\.) \s/mxs );
}

sub is_link_list {
  my $str = shift;
  return scalar( $str =~ m/^ \s* \[ [^[\]]+ \] \: \s/mxs );
}

sub is_definition_header {
  my $str = shift;
  return scalar m/^ \s* [~:] \s \s* /mxs;
}

sub indent {
  my $str         = shift;
  my $prefix      = "";
  my $todo_regex  = qr/\[\w?\]\s+/xms;
  my $list_regex  = qr/(?:[-•*+]|\d+\.) \s+ (?:\s$todo_regex)?/xms;
  my $def_regex   = qr/(?:\: \s+)/xms;
  my $quote_regex = qr/\>+\s+/;
  if ( $str =~ m{\A  (\s*) ($quote_regex?) ((?:$list_regex|$def_regex)?) }mxs ) {
    $prefix = $1 . $2 . ( " " x length($3) );
  }
  return $prefix;
}

1;
