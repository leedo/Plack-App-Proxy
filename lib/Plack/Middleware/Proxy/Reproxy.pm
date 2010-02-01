package Plack::Middleware::Proxy::Reproxy;
use strict;
use parent 'Plack::Middleware';

use Plack::Util;
use Try::Tiny;

sub call {
    my($self, $env) = @_;

    $env->{HTTP_X_PROXY_CAPABILITIES} = 'reproxy-file';

    return sub {
        my $respond = shift;

        my $cb = $self->app->($env);
        $cb->(sub {
            my $res = shift;
            if (my $url = Plack::Util::header_get($res->[1], 'X-Reproxy-URL')) {
                $env->{'plack.proxy.url'} = $url;
                $env->{REQUEST_METHOD} = 'GET';
                die "Recurse";
            }
            return $respond->($res);
        });
    };
}

1;

__END__

=head1 NAME

Plack::Middleware::Proxy::Reproxy - Adds reproxy behavior to Plack::App::Proxy

=head1 SYNOPSIS

  use Plack::Builder;
  use Plack::App::Proxy;

  builder {
      enable "Proxy::Reproxy";
      Plack::App::Proxy->new(host => "http://10.0.1.2:8080/")->to_app;
  };

=head1 DESCRIPTION

Plack::Middleware::Proxy::Reproxy adds reproxy capability to Plack::App::Proxy.

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Plack::App::Proxy>

=cut
