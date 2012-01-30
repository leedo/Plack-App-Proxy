package Plack::Middleware::Proxy::RewriteLocation;
use strict;
use parent 'Plack::Middleware';

use Plack::Util;
use Plack::Util::Accessor 'url_map';
use URI;

sub _different_part($$) {
    my ($from, $to) = @_;

    while ($from =~ m{[^/]+(?:\://$|/$|$)}g) {
        my $last_part = $&;
        last unless $to =~ /\Q$last_part\E$/;

        $from =~ s!\Q$last_part\E$!!;
        $to   =~ s!\Q$last_part\E$!!;
    }

    $from => $to;
}

sub new {
    my $self = shift->SUPER::new( @_ );

    # regularize the remote URLs in the URL map
    if( my $m = $self->url_map ) {
        for( my $i = 1; $i < @$m; $i += 2 ) {
            $m->[$i] = $self->_regularize_url( $m->[$i] );
        }
    }

    return $self;
}

sub call {
    my($self, $env) = @_;

    return sub {
        my $respond = shift;

        my $cb = $self->app->($env);
        return $respond->( $cb ) unless ref $cb eq 'CODE';

        $cb->(sub {
            my $res = shift;

            if ( $env->{HTTP_HOST} and my $location = Plack::Util::header_get($res->[1], 'Location') ) {

                my @map;
                if ($self->url_map) {
                    # regularize the format of the location so we can
                    # compare it correctly (some apps print this
                    # non-canonically)
                    $location = $self->_regularize_url( $location );

                    my $proxy = "$env->{'psgi.url_scheme'}://$env->{HTTP_HOST}";
                    my @url_map = @{$self->url_map};

                    while(my ($proxy_path, $remote) = splice @url_map, 0, 2) {
                        push @map, "$proxy$proxy_path" => $remote;
                    }
                } else {
                    # Auto-guessing url_map
                    my $original_url = "$env->{'psgi.url_scheme'}://" . 
                                       $env->{HTTP_HOST} .
                                       $env->{SCRIPT_NAME} .
                                       $env->{PATH_INFO};
                    $original_url .= '?' . $env->{QUERY_STRING}
                        if defined $env->{QUERY_STRING} && $env->{QUERY_STRING};
                    @map = _different_part(
                        $original_url => $env->{'plack.proxy.last_url'}
                    );
                }

                while(my ($proxy_url, $remote) = splice @map, 0, 2) {
                    last if $location =~ s!^$remote!$proxy_url!;
                }

                $location =~ s!//$!/!; #< avoid double slashes

                Plack::Util::header_set( $res->[1], 'Location' => $location );
            }

            return $respond->( $res );
        });
    };
}

sub _regularize_url {
    '' . URI->new( $_[1] )->canonical
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

  ### or, if mounting (i.e. URLMap) the proxied site at /foo

  builder {
      enable "Proxy::RewriteLocation", url_map => [ '/foo' => http://10.0.1.2:8080' ];
      mount '/foo' => Plack::App::Proxy->new(remote => "http://10.0.1.2:8080/")->to_app;
  };

=head1 DESCRIPTION

Plack::Middleware::Proxy::RewriteLocation rewrites the C<Location>
header in the response when the remote host redirects using its own
headers, like mod_proxy's C<ProxyPassReverse> option.

=head1 OPTIONS

=over 4

=item url_map (arrayref)

If given, will account for mounted (URLMapped) Proxy apps when
rewriting C<Location> headers.  Will be applied in order, stopping at the
first successful match with the remote C<Location>.

=back

=head1 AUTHOR

Tatsuhiko Miyagawa
Robert Buels

=head1 SEE ALSO

L<Plack::App::Proxy>

=cut
