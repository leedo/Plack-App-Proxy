use strict;
use warnings;
use Test::Requires 'Plack::Server::AnyEvent';
use Test::More;
use t::Runner;

run_tests( 'AnyEvent' );

done_testing;
