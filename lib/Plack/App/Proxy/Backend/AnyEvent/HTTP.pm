package Plack::App::Proxy::Backend::AnyEvent::HTTP;

use strict;
use parent 'Plack::App::Proxy::Backend';
use AnyEvent::HTTP;

sub call {
    my $self = shift;
    my ($env) = @_;

    return sub {
        my $respond = shift;
        my $cv = AE::cv;
        my $writer;
        AnyEvent::HTTP::http_request(
            $self->method => $self->url,
            headers => $self->headers,
            body => $self->content,
            recurse => 0,  # want not to treat any redirections
            persistent => 0,
            on_header => sub {
                my $headers = shift;

                if ($headers->{Status} !~ /^59\d+/) {
                    $env->{'plack.proxy.last_protocol'} = $headers->{HTTPVersion};
                    $env->{'plack.proxy.last_status'}   = $headers->{Status};
                    $env->{'plack.proxy.last_reason'}   = $headers->{Reason};
                    $env->{'plack.proxy.last_url'}      = $headers->{URL};

                    $writer = $respond->([
                        $headers->{Status},
                        [$self->response_headers->($headers)],
                    ]);
                }
                return 1;
            },
            on_body => sub {
              $writer->write($_[0]);
              return 1;
            },
            sub {
                my (undef, $headers) = @_;

                if (!$writer and $headers->{Status} =~ /^59\d/) {
                    $respond->([502, ["Content-Type","text/html"], ["Gateway error: $headers->{Reason}"]]);
                }

                $writer->close if $writer;
                $cv->send;

                # http_request may not release $cb with perl 5.8.8
                # and AE::HTTP 1.44. So free $env manually.
                undef $env;

                # Free the reference manually for perl 5.8.x
                # to avoid nested closure memory leaks.
                undef $respond;
            }
        );
        $cv->recv unless $env->{"psgi.nonblocking"};
    }
}

1;

__END__

=head1 NAME

Plack::App::Proxy::Backend::AnyEvent::HTTP - backend which uses AnyEvent::HTTP

=head1 SYNOPSIS

  my $app = Plack::App::Proxy->new(backend => 'AnyEvent::HTTP')->to_app;

=head1 DESCRIPTION

This backend uses L<AnyEvent::HTTP> to make HTTP requests. This is the default
backend used when no backend is specified in the constructor.

=head1 AUTHOR
 
Lee Aylward

Masahiro Honma

Tatsuhiko Miyagawa

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
