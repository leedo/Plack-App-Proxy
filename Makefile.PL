use inc::Module::Install;
name 'Plack-App-Proxy';
all_from 'lib/Plack/App/Proxy.pm';
readme_from 'lib/Plack/App/Proxy.pm';
test_requires 'Test::More' => '0.88';  # for done_testing()
test_requires 'Test::Requires';
test_requires 'Test::TCP';
test_requires 'IO::Socket::INET';
requires 'Plack' => '0.9913'; # for psgix.io supports.
requires 'Plack::Request';
requires 'HTTP::Headers';
requires 'AnyEvent::HTTP' => 1.44; # for Host header
tests 't/*.t t/*/*.t';
auto_set_repository;
WriteAll;
