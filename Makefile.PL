use inc::Module::Install;

name     'TrustlinkClient';
all_from 'lib/TrustlinkClient.pm';
author   q{Dmitriy V. Simonov <dsimonov@gmail.com>};
license  'perl';

build_requires 'Test::More';
build_requires 'lib::abs';
requires 'File::Basename';
requires 'File::stat';
requires 'URI';
requires 'IO::File';
requires 'Socket';
requires 'Data::Dumper';
requires 'List::MoreUtils';
requires 'Encode';

auto_install;

WriteAll;

