#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'TrustlinkClient' );
}

diag( "Testing TrustlinkClient $TrustlinkClient::VERSION, Perl $], $^X" );
