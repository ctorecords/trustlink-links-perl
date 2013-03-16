use strict;
use warnings;

use lib::abs '../lib';
use TrustlinkClient;
use Encode qw(decode encode);

print encode(utf8=>TrustlinkClient->new({
    charset        => 'utf-8',
    TRUSTLINK_USER => 'a742bfd5f4b9f240095910e0983d714d4b08efbc',
    request_uri    => '/brushes/kollekciya-kistei-dlya-fotoshop-collection-brushes-for-photoshop.html',
    host           => 'kirovka.ru',
    host           => 'youdesigner.kz',
    tl_multi_site  => 1,
    tpath          => lib::abs::path('.'),
})->build_links());
