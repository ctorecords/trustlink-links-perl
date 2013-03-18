use strict;
use warnings;
use Test::More tests => 1;

use lib::abs '../lib';
use TrustlinkClient;
use Encode qw(decode encode);
use File::Slurp 'read_file';

my $tlc = TrustlinkClient->new(
    {
        charset        => 'utf-8',
        TRUSTLINK_USER => 'a742bfd5f4b9f240095910e0983d714d4b08efbc',
        host           => 'kirovka.ru',
        host           => 'youdesigner.kz',
    }
);
is(
    $tlc->fetch_remote_file(
        'db.trustlink.ru' => '/a742bfd5f4b9f240095910e0983d714d4b08efbc/youdesigner.kz/UTF-8.text'
    ),
    read_file( lib::abs::path('./test_fetch.txt') ),
    'Fetch content from TrustLink.Ru'
);

