package Plack::Middleware::Proxy::LoadBalancer;
use strict;
use warnings;
use parent 'Plack::Middleware';

use Plack::Util::Accessor qw/backends/;

our $VERSION = '0.01';

sub select_backend {
    my $self = shift;

    if ( ref $self->backends eq 'ARRAY' ) {
        return $self->backends->[ int( rand( @{ $self->backends } ) ) ];
    }
    elsif ( ref $self->backends eq 'HASH' ) {
        return (
            sort { $b->{value} <=> $a->{value} }
                map { { value => rand() * $self->backends->{$_}, host => $_ }; }
                keys %{ $self->backends }
        )[0]->{host};
    }
    else {
        return $self->backends;
    }
}

sub call {
    my ( $self, $env ) = @_;
    $env->{'plack.proxy.remote'} = $self->select_backend;
    $self->app->($env);
}

1;

__END__

=head1 NAME

Plack::Middleware::Proxy::LoadBalancer - Simple load balancer

=head1 SYNOPSIS

  use Plack::Builder;
  use Plack::App::Proxy;

  builder {
    enable "Proxy::LoadBalancer", backends => ['http://10.0.0.1:8080', 'http://10.0.0.1:8081'];
    Plack::App::Proxy->new()->to_app;
  };

=head1 DESCRIPTION

Plack::Middleware::Proxy::LoadBalancer allow you to define several backends.

=head1 OPTIONS

=over 4

=item backends

  enable "Proxy::LoadBalancer", backends => 'http://10.0.0.1:8080';

Or

  enable "Proxy::LoadBalancer", backends => ['http://10.0.0.1:8080', 'http://10.0.0.1:8081'];

Or

  enable "Proxy::LoadBalancer", backends => {'http://10.0.0.1:8080' => 0.4, 'http://10.0.0.1:8081' => 0.5, 'http://10.0.0.1:8002' => 0.3};

More than one backend can be defined. Weight can be given to backends.

=back

=head1 AUTHOR

Franck Cuny

=head1 SEE ALSO

L<Plack::App::Proxy>

=cut


