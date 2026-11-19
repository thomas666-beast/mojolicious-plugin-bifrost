use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME => 'Mojolicious::Plugin::Bifrost',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Bifrost.pm',
  ABSTRACT_FROM => 'lib/Mojolicious/Plugin/Bifrost.pm',
  AUTHOR => 'Bifrost contributors',
  LICENSE => 'artistic_2',
  MIN_PERL_VERSION => '5.026',
  PREREQ_PM => {Mojolicious => '9.48'},
  TEST_REQUIRES => {'Test::More' => 0},
);
