package Plack::Middleware::Proxy::Connect;
use strict;
use warnings;
use parent 'Plack::Middleware';

use AnyEvent::Socket;
use AnyEvent::Handle;

our $VERSION = '0.01';

sub call {
    my($self, $env) = @_;
    return $self->app->( $env ) unless $env->{ REQUEST_METHOD } eq 'CONNECT';

    my $client_fh = $env->{'psgix.io'}
                      or return [ 501, [], ['Not implemented CONNECT method']];
    my ( $host, $port ) =
                     ( $env->{REQUEST_URI} =~ m{^(?:.+\@)?(.+?)(?::(\d+))?$} );

    sub {
        my $respond = shift;

        # Run the loop by myself when psgi.nonblocking is turend off.
        my $cv = $env->{'psgi.nonblocking'} ? undef : AE::cv;

        tcp_connect $host, $port, sub {
            my ( $origin_fh ) = @_;
            unless( $origin_fh ){
                $respond->( [ 502, [], ['Bad Gateway'] ] );
                $cv->send if $cv;
                return;
            }

            my $writer = $respond->( [ 200, [] ] );

            my $client_hdl = AnyEvent::Handle->new( fh => $client_fh );
            my $origin_hdl = AnyEvent::Handle->new( fh => $origin_fh );

            # Join 2 handles by a tunnel
            $client_hdl->on_read(sub {
                my $hdl = shift;
                my $rbuf = delete $hdl->{rbuf};
                $origin_hdl->push_write( $rbuf );
            } );
            $client_hdl->on_error( sub {
                my ( $hdl, $fatal, $message ) = @_;
                $! and warn "error($fatal): $message\n";
                $origin_hdl->push_shutdown;
                # Finish this request.
                $writer->close;
                $cv->send if $cv;
                # Use $client_hdl to keep the handle by a cyclical reference.
                $client_hdl->destroy;
            } );

            $origin_hdl->on_read(sub {
                my $hdl = shift;
                my $rbuf = delete $hdl->{rbuf};
                $client_hdl->push_write( $rbuf );
            } );
            $origin_hdl->on_error( sub {
                my ( $hdl, $fatal, $message ) = @_;
                $! and warn "error($fatal): $message\n";
                $client_hdl->push_shutdown;
                # Use $origin_hdl to keep the handle by a cyclical reference.
                $origin_hdl->destroy;
            } );
        };

        $cv->recv if $cv;
    };
}

1;

__END__

=head1 NAME

Plack::Middleware::Proxy::Connect - Handles the CONNECT method.

=head1 SYNOPSIS

  use Plack::Builder;
  use Plack::App::Proxy;

  builder {
      enable "Proxy::Connect";
      enable sub {
          my $app = shift;
          return sub {
              my $env = shift;
              ($env->{'plack.proxy.url'} = $env->{REQUEST_URI}) =~ s|^/||;
              $app->( $env );
          };
      };
      Plack::App::Proxy->new->to_app;
  };

=head1 DESCRIPTION

Plack::Middleware::Proxy::Connect handles the C<CONNECT> method,
like mod_proxy's C<AllowCONNECT> option.

Plack::Middleware::Proxy::Connect runs on servers supporting I<psgix.io>;
Twiggy, Plack::Server::Coro, and so on.

=head1 AUTHOR

Masahiro Honma E<lt>hiratara@cpan.orgE<gt>

=head1 SEE ALSO

L<Plack::App::Proxy>

=cut

