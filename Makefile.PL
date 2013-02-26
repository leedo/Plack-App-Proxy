use inc::Module::Install;
name 'Plack-App-Proxy';
all_from 'lib/Plack/App/Proxy.pm';
readme_from 'lib/Plack/App/Proxy.pm';
test_requires 'Test::More' => '0.88';  # for done_testing()
test_requires 'Test::Requires';
test_requires 'Test::TCP';
test_requires 'IO::Socket::INET';
requires 'Plack' => '1.0013'; # for seek(0,0) on psgi.input
                              # for psgix.io support in 0.9913
requires 'HTTP::Headers';
requires 'AnyEvent::HTTP' => 1.44; # for Host header
requires 'LWP::UserAgent';
requires 'parent';
tests 't/*.t t/*/*.t';
auto_set_repository;
WriteAll;
