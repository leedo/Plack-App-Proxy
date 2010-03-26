package Plack::Middleware::Proxy::LoadBalancer;
use strict;
use warnings;
use parent 'Plack::Middleware';

use Plack::Util::Accessor qw/backends/;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my %param = ref $_[0] ? %{ $_[0] } : @_;

    my $backends = delete $param{backends};

    my $self = $class->SUPER::new( \%param );
    $self->_set_backends( $backends );

    $self;
}

sub _set_backends{
    my $self = shift;
    my ( $backends ) = @_;

    # A total of 'weight' should be 1.0
    if( ref $backends eq 'ARRAY'){
        my $weight = 1 / @$backends;
        $self->backends([
            map { {remote => $_, weight => $weight} } @$backends
        ]);
    }elsif( ref $backends eq 'HASH'){
        my $total = 0;
        $total += $_ for values %$backends;
        $self->backends([ map { 
            {remote => $_, weight => $backends->{$_} / $total}
        } keys %$backends ]);
    }else{
        $self->backends([ { remote => $backends, weight => 1 } ]);
    }
}

sub select_backend {
    my $self = shift;
    my $rand = rand;

    my $choice = undef;
    for( @{ $self->backends } ){
        $choice = $_->{remote};
        ($rand -= $_->{weight}) <= 0 and last;
    }

    return $choice;
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


