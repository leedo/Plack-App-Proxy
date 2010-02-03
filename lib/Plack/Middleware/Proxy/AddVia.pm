package Plack::Middleware::Proxy::AddVia;
use strict;
use parent 'Plack::Middleware';

use Plack::Util;

our $VERSION = '0.01';

sub add_via {
    my ( $self, $via, $protocol, $recieved_by ) = @_;

    $protocol =~ s|^HTTP/||;
    return join ', ', $via || (), "$protocol $recieved_by";
}

sub make_recieved_by_from_env {
    my ( $self, $env ) = @_;
    my $host = $env->{SERVER_NAME} . (
        $env->{SERVER_PORT} == 80 ? '' : ":$env->{SERVER_PORT}"
    ) ;
    return  $host . " (" . __PACKAGE__ . "/$VERSION)";
}

sub call {
    my($self, $env) = @_;

    my $recieved_by = $self->make_recieved_by_from_env( $env );

    $env->{HTTP_VIA} = $self->add_via( 
        $env->{HTTP_VIA}, $env->{SERVER_PROTOCOL}, $recieved_by
    );

    return sub {
        my $orig_respond = shift;

        my $respond = sub {
            my $res = shift;
            my $via = Plack::Util::header_get($res->[1], 'Via');
            Plack::Util::header_set(
                $res->[1], 'Via' => $self->add_via(
                    $via, $env->{'plack.proxy.last_protocol'}, $recieved_by
                )
            );
            return $orig_respond->( $res );
        };

        my $res = $self->app->($env);
        ref $res eq 'CODE' ? $res->( $respond ) : $respond->( $res );
    };
}

1;

__END__

=head1 NAME

Plack::Middleware::Proxy::AddVia - Adds the Via header for the current host.

=head1 SYNOPSIS

  use Plack::Builder;
  use Plack::App::Proxy;

  builder {
      enable "Proxy::AddVia";
      Plack::App::Proxy->new(host => "http://10.0.1.2:8080/")->to_app;
  };

=head1 DESCRIPTION

Plack::Middleware::Proxy::AddVia adds the C<Via> header to the request and 
response, like mod_proxy's C<ProxyVia> option.

=head1 AUTHOR

Masahiro Honma E<lt>hiratara@cpan.orgE<gt>

=head1 SEE ALSO

L<Plack::App::Proxy>

=cut
