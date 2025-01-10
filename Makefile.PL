use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
  NAME               => 'App::Markdown::Wrap',
  AUTHOR             => q{Liu.Bian.Shi <liu.bian.shi@gmail.com>},
  VERSION_FROM       => 'lib/App/Markdown/Wrap.pm',
  ABSTRACT_FROM      => 'lib/App/Markdown/Wrap.pm',
  LICENSE            => 'artistic_2',
  MIN_PERL_VERSION   => '5.006',
  EXE_FILES          => [qw( script/mdwrap )],
  CONFIGURE_REQUIRES => {
    'ExtUtils::MakeMaker' => '0',
  },
  TEST_REQUIRES => {
    'Test::More' => '0',
  },
  PREREQ_PM => {
    'App::url' => '0',

    #'ABC'              => '1.6',
    #'Foo::Bar::Module' => '5.0401',
  },
  dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
  clean => { FILES    => 'App-Markdown-Wrap-*' },
);

# Compatibility with old versions of ExtUtils::MakeMaker
unless ( eval { ExtUtils::MakeMaker->VERSION('6.64'); 1 } ) {
  my $test_requires = delete $WriteMakefileArgs{TEST_REQUIRES} || {};
  @{ $WriteMakefileArgs{PREREQ_PM} }{ keys %$test_requires } = values %$test_requires;
}

unless ( eval { ExtUtils::MakeMaker->VERSION('6.55_03'); 1 } ) {
  my $build_requires = delete $WriteMakefileArgs{BUILD_REQUIRES} || {};
  @{ $WriteMakefileArgs{PREREQ_PM} }{ keys %$build_requires } = values %$build_requires;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION('6.52'); 1 };
delete $WriteMakefileArgs{MIN_PERL_VERSION}
  unless eval { ExtUtils::MakeMaker->VERSION('6.48'); 1 };
delete $WriteMakefileArgs{LICENSE}
  unless eval { ExtUtils::MakeMaker->VERSION('6.31'); 1 };

WriteMakefile(%WriteMakefileArgs);
