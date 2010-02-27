package t::Runner;
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

sub test_proxy {
  my %args = @_;

  local $Plack::Test::Impl = 'Server';

  my $client = delete $args{client} or croak "client test code needed";
  my $app    = delete $args{app}    or croak "app needed";
  my $proxy  = delete $args{proxy}  or croak "proxy needed";
  my $host   = delete $args{host} || '127.0.0.1';

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

1;
