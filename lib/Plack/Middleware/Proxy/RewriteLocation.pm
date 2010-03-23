package Plack::Middleware::Proxy::RewriteLocation;
use strict;
use parent 'Plack::Middleware';

use Plack::Util;

sub call {
    my($self, $env) = @_;

    return sub {
        my $respond = shift;

        my $cb = $self->app->($env);
        $cb->(sub {
            my $res = shift;
            if ( my $location = Plack::Util::header_get($res->[1], 'Location') ) {
                my $remote = ($env->{'plack.proxy.last_url'} =~ m!^(https?://[^/]*/)!)[0];
                if ($remote && $env->{HTTP_HOST}) {
                    $location =~ s!^$remote!$env->{'psgi.url_scheme'}://$env->{HTTP_HOST}/!;
                }
                Plack::Util::header_set($res->[1], 'Location' => $location);
            }
            return $respond->($res);
        });
    };
}

1;

__END__

=head1 NAME

Plack::Middleware::Proxy::RewriteLocation - Rewrites redirect headers

=head1 SYNOPSIS

  use Plack::Builder;
  use Plack::App::Proxy;

  builder {
      enable "Proxy::RewriteLocation";
      Plack::App::Proxy->new(remote => "http://10.0.1.2:8080/")->to_app;
  };

=head1 DESCRIPTION

Plack::Middleware::Proxy::RewriteLocation rewrites the C<Location>
header in the response when the remote host redirects using its own
headers, like mod_proxy's C<ProxyPassReverse> option.

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Plack::App::Proxy>

=cut
