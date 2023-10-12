package OpenXPKI::Client::Config;
use Moose;

use File::Spec;
use Cache::LRU;
use Config::Std;
use Data::Dumper;
use Log::Log4perl::MDC;
use OpenXPKI::Client;
use OpenXPKI::Log4perl;
use OpenXPKI::i18n qw( set_language set_locale_prefix);

=head1 OpenXPKI::Client::Config

This is a helper package for all cgi based client interfaces to read a
client config file base on the name of the script called. It was designed
to work inside an apache server but should do in other environments as
long as the environment variables are available or adjusted.

=head2 Environment variables

=over

=item OPENXPKI_CLIENT_CONF_DIR

The path of the OpenXPKI base config directory, default I</etc/openxpki>

=item OPENXPKI_I<SERVICE>_CLIENT_CONF_DIR

I<SERVICE> is the name of the service as given to the constructor.
The default value is the basedir plus the name of the service, e.g.
I</etc/openxpki/scep>. This is the base directory where the service
config is initialized from the file I<default.conf>. If you use
the config autodiscovery feature (config name from script name), those
files need to be here, too.

Note: Dashes in the servicename are replaced by underscores, e.g. the
name for I<scep-test> is I<OPENXPKI_SCEP_TEST_CLIENT_CONF_DIR>.

It is B<not> used if an expicit config file is set with
OPENXPKI_I<SERVICE>_CLIENT_CONF_FILE!

=item OPENXPKI_I<SERVICE>_CLIENT_CONF_FILE

The full path of the config file to use.

=item OPENXPKI_CLIENT_SERVICE_NAME

The name of the service.
B<Note> This overrides the service name passed to the constructor!

=back

=head2 Default Configuration

Mostly logger config, used before FCGI is spawned and if no special
config is found.

=head2 Entity Configuration / Autodiscovery

Most cgi wrappers offer autodiscovery of config files based on the
scripts filename, which is espacially handy with rewrite or alias rules.
E.g. with the default scep configuration you can use
http://servername/scep/my-endpoint in your scep client which will load
the entity configuration from the file I<my-endpoint.conf> in the scep
config directory (by default /etc/openxpki/scep, see also notes above).

If no such file is found, the default configuration is used.

=head2 Isntance Variables / Accessor Methods

=head3 service

Name of the service as passed during construction, read-only

=cut

has 'service' => (
    required => 1,
    is => 'ro',
    isa => 'Str',
);

=head3 basepath

The filesystem path holding the config directories, can be set during
construction, defaults to I</etc/openxpki> when not read from ENV
(see above).

=cut

# the service specific path
has 'basepath' => (
    required => 0,
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    builder => '__init_basepath'
);

=head3 logger

The Log4perl instance. Will be created from the global section of the
config file read but can also be set.

=cut

has 'logger' => (
    required => 0,
    lazy => 1,
    is => 'rw',
    isa => 'Object',
    builder => '__init_logger',
);

=head3 logconf

The default configuration for the logger when created from the I<logger>
section of the global config file. This contains the details for a file
appender, minimum configuration is to set the loglevel, it might also be
useful to set a custom filename, the filename is used as pattern and
expanded with the value of I<service>.

    [logger]
    log_level = WARN
    filename  = /var/log/openxpki/%s.log

=cut

has 'logconf' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { return {
        recreate    => 1,
        recreate_check_interval => 120,
        filename    => '/var/log/openxpki/%s.log',
        layout      => 'Log::Log4perl::Layout::PatternLayout',
        'layout.ConversionPattern' => '%d %p{3} %m []%n',
        syswrite    => 1,
        utf8        => 1
    }}
);

=head3 default

Accessor to the default configuration, usually read from I<default.conf>.

=cut

has 'default' => (
    required => 0,
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    builder => '__init_default',
);

=head3 endpoint

Name of the endpoint that is used for config discovery, set from the
script name when C<parse_uri> is called. Can also be set explicit.

=cut

has 'endpoint' => (
    required => 0,
    is => 'rw',
    isa => 'Str|Undef',
    lazy => 1,
    default => '',
);

=head3 route

The name of the route extracted from the script name by C<parse_uri>.

=cut

has 'route' => (
    required => 0,
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    default => '',
);

=head3 language

The name of the current language, set whenever a config is loaded that has
the language propery set. Sets the gettext path when changed.

=cut

has language => (
    required => 0,
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    default => '',
    trigger => sub {
        my $self = shift;
        set_language($self->language());
    },
);

=head3 client

Instance of OpenXPKI::Client, autogenerated with the default socket
path if not set.

=cut

has 'client' => (
    required => 0,
    is => 'rw',
    isa => 'OpenXPKI::Client',
    lazy => 1,
    predicate => "has_client",
    default => sub {
        return OpenXPKI::Client->new( socketfile => '/var/openxpki/openxpki.socket' );
    }
);

has '_cache' => (
    required => 0,
    is => 'ro',
    isa => 'Cache::LRU',
    lazy => 1,
    default => sub {
        return Cache::LRU->new( size => 16 );
    }
);

# this allows a constructor with the service as scalar
around BUILDARGS => sub {

    my $orig = shift;
    my $class = shift;

    my $args = shift;
    if (!ref $args) {
        $args = { service => $args };
    }

    # try to read service name from ENV
    if ($ENV{OPENXPKI_CLIENT_SERVICE_NAME}) {
        $args->{service} = $ENV{OPENXPKI_CLIENT_SERVICE_NAME};
    }

    return $class->$orig( $args );

};

sub BUILD {

    my $self = shift;

    if ($self->service() !~ /\A[a-zA-Z0-9\-]+\z/) {
        die "Invalid service name: " . $self->service();
    }

    my $config = $self->default();

    if ($config->{global}->{locale_directory}) {
        set_locale_prefix($config->{global}->{locale_directory});
    }
    if ($config->{global}->{default_language}) {
        $self->language($config->{global}->{default_language});
    }

    $self->logger()->debug(sprintf('Config for service %s loaded', $self->service()));
    $self->logger()->trace('Global config: ' . Dumper $config ) if $self->logger->is_trace;

}

sub __init_basepath {

    my $self = shift;

    # generate name of the environemnt values from the service name
    my $env_dir = 'OPENXPKI_'.uc($self->service).'_CLIENT_CONF_DIR';
    $env_dir =~ s{-}{_}g;

    # check for service specific basedir in env
    if ( $ENV{$env_dir} ) {
        -d $ENV{$env_dir}
            || die sprintf "Explicit config directory not found (%s from env %s)", $ENV{$env_dir}, $env_dir;

        return File::Spec->canonpath( $ENV{$env_dir} );
    }

    my $path;
    # check for a customized global base dir
    if ($ENV{OPENXPKI_CLIENT_CONF_DIR}) {
        $path = $ENV{OPENXPKI_CLIENT_CONF_DIR};
        -d $path
            || die "Explicit client config directory not found ($path from env OPENXPKI_CLIENT_CONF_DIR)";
        $path = File::Spec->canonpath( $path );
    } else {
        $path = '/etc/openxpki';
    }

    # default basedir is global path + servicename
    return File::Spec->catdir($path, $self->service);

}

sub __init_default {

    my $self = shift;
    # in case an explicit script name is set, we do NOT use the default.conf
    my $service = $self->service();
    my $env_file = 'OPENXPKI_'.uc($service).'_CLIENT_CONF_FILE';

    my $configfile;
    if ($ENV{$env_file}) {
        -f $ENV{$env_file}
            || die sprintf "Explicit config file not found (%s, from env %s)", $ENV{$env_file}, $env_file;

        $configfile = $ENV{$env_file};

    } else {
        $configfile = File::Spec->catfile( ( ($self->basepath), 'default.conf' ) );
    }

    my $config;
    if (!read_config $configfile => $config) {
        die "Could not read client config file " . $configfile;
    }

    # cast to an unblessed hash
    my %config = %{$config};
    return \%config;

}

=head2 Methods

=head3 parse_uri

Try to parse endpoint and route based on the script url in the
environment. Always returns $self, endpoint is set to the empty
string if parsing fails.

=cut

sub parse_uri {

    my $self = shift;

    # generate name of the environemnt values from the service name
    my $service = $self->service();

    $self->endpoint('');
    $self->route('');

    # Test for specific config file based on script name
    # SCRIPT_URL is only available with mod_rewrite
    # expected pattern is servicename/endpoint/route,
    # route can contain a suffix like .exe which is used by some scep clients
    my ($ep, $rt);
    if (defined $ENV{SCRIPT_URL}) {
        ($ep, $rt) = $ENV{SCRIPT_URL} =~ qr@ ${service} / ([^/]+) (?: / ([\w\-\/]+ (?:\.\w{3})? )? )?\z@x;
    } elsif (defined $ENV{REQUEST_URI}) {
        ($ep,$rt) = $ENV{REQUEST_URI} =~ qr@ ${service} / ([^/\?]+) (?: / ([\w\-\/]+ (?:\.\w{3})? )? )? (\?.*)? \z@x;
    }

    if (!$ep) {
        $self->logger()->warn("Unable to detect script name - please check the docs");
        $self->logger()->trace(Dumper \%ENV) if $self->logger->is_debug;
    } elsif (($service =~ m{(est|cmc)}) && !$rt) {
        $self->logger()->debug("URI without endpoint, setting route: $ep");
        $self->endpoint('default');
        $self->route($ep);
    } else {
        $self->endpoint($ep);
        $self->route($rt) if ($rt);
        $self->logger()->debug("Parsed URI: $ep => ".($rt||''));
    }

    # Populate the endpoint to the MDC
    Log::Log4perl::MDC->put('endpoint', $self->endpoint());

    return $self;

}

=head3 config

Returns the config hashref for the current endpoint.

=cut

sub config {

    my $self = shift;
    my $config;
    my $cacheid = $self->endpoint() || 'default';
    if (!($config = $self->_cache()->get( $cacheid ))) {
        # non existing files and other errors are handled inside loader
        $config = $self->__load_config();
        $self->_cache()->set( $cacheid  => $config );
        $self->logger()->debug('added config to cache ' . $cacheid);
    }

    $self->language($config->{global}->{default_language} || $self->default()->{global}->{default_language} || '');

    return $config;

}

sub __load_config {

    my $self = shift;

    my $file;
    my $config;
    if ($self->endpoint()) {
        # config via socket
        if ($self->has_client()) {
            $self->logger()->debug('Autodetect config for service ' . $self->service() . ' via socket ');
            my $reply = $self->client()->send_receive_service_msg('GET_ENDPOINT_CONFIG',
                { 'interface' => $self->service(), endpoint => $self->endpoint() });
            die "Unable to fetch endpoint default configuration from backend" unless (ref $reply->{PARAMS});
            return $reply->{PARAMS}->{CONFIG};
        }
        $file = $self->endpoint().'.conf';
    }

    if ($file) {
        $self->logger()->debug('Autodetect config file for service ' . $self->service() . ': ' . $file );
        $file = File::Spec->catfile( ($self->basepath() ), $file );
        if (! -f $file ) {
            $self->logger()->debug('No config file found, falling back to default');
            $file = undef;
        }
    }

    # if no config file is given, use the default
    return $self->default() unless($file);

    if (!read_config $file => $config) {
        $self->logger()->error('Unable to read config from file ' . $file);
        die "Could not read client config file $file ";
    }

    # cast to an unblessed hash
    my %config = %{$config};

    $self->logger()->trace('Script config: ' . Dumper \%config ) if $self->logger->is_trace;

    return \%config;
}

sub __init_logger {
    my $self = shift;
    my $config = $self->default();

    # if no logger section was found we use the log settings from global
    # if those are also missing this falls back to a SCREEN appender
    if (!$config->{logger}) {
        OpenXPKI::Log4perl->init_or_fallback( $config->{global}->{log_config} );
        return Log::Log4perl->get_logger($config->{global}->{log_facility} || '');
    }

    # logger section is merged with the default config from the class
    my $conf = {
        %{$self->logconf()},
        %{$config->{logger}}
    };

    # extract the loglevel from the config hash
    my $loglevel = uc($conf->{log_level}) || 'WARN';
    delete $conf->{log_level};

    # facility is constructed from service
    my $log_facility = 'client.'.$self->service();

    # fill in the service name into the filename pattern
    $conf->{filename} = sprintf($conf->{filename}, $self->service());

    # add the MDC part to the conversion pattern in case it is not set (empty [] in string)
    if ($conf->{'layout.ConversionPattern'} && $conf->{'layout.ConversionPattern'} =~ m{\[\]}) {
        if ($self->service() eq 'webui') {
            $conf->{'layout.ConversionPattern'} =~ s{\[\]}{[pid=%P|sid=%X{sid}]};
        } else {
            $conf->{'layout.ConversionPattern'} =~ s{\[\]}{[pid=%P|ep=%X{endpoint}]};
        }
    }

    # assemble the final hash
    my $log_config = {
        "log4perl.category.$log_facility" => "$loglevel, Logfile",
        'log4perl.appender.Logfile'       => 'Log::Log4perl::Appender::File',
    };
    map {
        $log_config->{'log4perl.appender.Logfile.'.$_} = $conf->{$_};
    } keys %{$conf};

    OpenXPKI::Log4perl->init_or_fallback( $log_config );
    return Log::Log4perl->get_logger( $log_facility );

}

__PACKAGE__->meta->make_immutable;

__END__;
