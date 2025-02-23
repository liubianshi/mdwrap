package App::Markdown::Block;
use strict;
use warnings;
use Data::Dump qw/dump/;

use List::Util           qw(none);
use App::Markdown::Text  qw(wrap);
use App::Markdown::Utils qw( get_indent_prefix indent);

sub new {
  my $class = shift;
  my $args  = shift;
  my $self  = {
    text => "",
    type => "normal",
    attr => {
      prefix         => "",
      wrap           => 1,
      add_empty_line => 0,
      marker         => "",
      empty          => 1,
    },
    %{ $args // {} }
  };
  bless $self, $class;
  return $self;
}

sub extend {
  my $self = shift;
  $self->{'text'} .= join "", @_;
  $self->{attr}{empty} = 0 if $self->{attr}{empty} == 1;
}

sub get {
  my $self = shift;
  my $key  = shift or return;
  if ( $key eq "text" or $key eq "type" or $key eq "attr" ) {
    return $self->{$key};
  }
  else {
    return $self->{attr}{$key};
  }
}

sub update {
  my ( $self, $args ) = @_;
  if ( defined $args->{text} ) {
    $self->{text} = $args->{text};
  }
  if ( defined $args->{type} ) {
    $self->{type} = $args->{type};
  }
  if ( defined $args->{attr} ) {
    $self->{attr} = { %{ $self->{attr} }, %{ $args->{attr} } };
  }
}

sub tostring {
  my $self = shift;
  return "" if $self->get("empty");
  my $prefix = $self->get("prefix") // "";

  my $re = $self->get("text");
  if ( $self->get("wrap") ) {
    my $indent = $prefix . indent($re);
    $re = wrap( $prefix, $indent, $re );
  }
  else {
    $re = join "\n", map { $prefix . $_ } ( split /\n/, $re );
    $re .= "\n";
  }

  $re .= $self->get("prefix") . "\n" if $self->get("add_empty_line") == 1;

  return $re;
}

1;
