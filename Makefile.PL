use inc::Module::Install;
name 'Plack-App-Proxy';
all_from 'lib/Plack/App/Proxy.pm';
readme_from 'lib/Plack/App/Proxy.pm';
test_requires 'Test::More' => '0.88';  # for done_testing()
requires 'Plack' => 0.9021; # for Plack::Component
requires 'Plack::Request';
requires 'AnyEvent::HTTP' => 1.44; # for Host header
requires 'LWP';
auto_set_repository;
WriteAll;
