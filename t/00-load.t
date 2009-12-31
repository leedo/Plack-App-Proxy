
use Test::More tests => 1;

BEGIN {
    use_ok( 'Plack::App::Proxy' ) || print "Bail out!
";
}

diag( "Testing Plack::App::Proxy $Plack::App::Proxy::VERSION, Perl $], $^X" );
