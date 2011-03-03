package Plack::App::Proxy::Test;
use strict;
use warnings;
use Carp;
use Plack::Loader;
use Plack::Test;
use Test::More;
use Test::TCP;
use LWP::UserAgent;
use base Exporter::;
our @EXPORT = qw(test_proxy);

BEGIN {
  # disable HTTP proxy when testing since we are connecting to localhost
  delete $ENV{http_proxy};
}

our @BACKENDS = qw/LWP AnyEvent::HTTP/;

sub test_proxy {
    my %args = @_;

    local $Plack::Test::Impl = 'Server';

    my $client = delete $args{client} or croak "client test code needed";
    my $app    = delete $args{app}    or croak "app needed";
    my $proxy  = delete $args{proxy}  or croak "proxy needed";
    my $host   = delete $args{host} || '127.0.0.1';

    for my $backend (@BACKENDS) {

        local $ENV{PLACK_PROXY_BACKEND} = $backend;

        test_tcp(
            client => sub {
                my $port = shift;
                test_psgi(
                    app => $proxy->( $host, $port ),
                    client => $client,
                    host => $host,
                    # disable the auto redirection of LWP::UA
                    ua => LWP::UserAgent->new( max_redirect => 0 ),
                );
            },
            server => sub {
                my $port = shift;

                # Use an ordinary server.
                local $ENV{PLACK_SERVER} = 'Standalone';

                my $server = Plack::Loader->auto(port => $port, host => $host);
                $server->run($app);
            },
        );
    }
}

1;

__END__

=head1 NAME

Plack::App::Proxy::Test - Is utilities to test Plack::App::Proxy.

=head1 SYNOPSIS

  test_proxy(
      app   => $backend_app,
      proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]") },
      client => sub {
          my $cb = shift;
          my $res = $cb->(GET '/');
          ok $res->is_success, "Check the status line.";
      },
  );

=head1 DESCRIPTION

Plack::App::Proxy::Test provids test_proxy function which wraps 
test_psgi of Plack::Test simply. 

=head1 FUNCTIONS

=over 4

=item test_proxy

  test_proxy app    => $app, 
             proxy  => $proxy_cb->($app_host, $app_port), 
             client => $client_cb->($cb);

=back

test_proxy runs two servers, 'C<app>' as an origin server and the proxy server.
In 'C<proxy>' callback, you should create the proxy server instance to send 
requests to 'C<app>' server. Then 'C<client>' callback is called to run your 
tests. In 'C<client>' callback, all HTTP requests are sent to 'C<proxy>' 
server. (And the proxy server will proxy your request to the app server.)

=head1 AUTHOR

Masahiro Honma E<lt>hiratara@cpan.orgE<gt>

=cut

=head1 SEE ALSO

L<Plack::App::Proxy> L<Plack::Test>

=cut

