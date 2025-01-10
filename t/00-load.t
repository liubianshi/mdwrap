#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'App::Markdown::Wrap' ) || print "Bail out!\n";
}

diag( "Testing App::Markdown::Wrap $App::Markdown::Wrap::VERSION, Perl $], $^X" );
