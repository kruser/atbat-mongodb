package Kruser::MLB::AtBat;

##
# A module that provides a way to get Perl data structures
# from the MLB AtBat XML APIs
#
# @author kruser
##
use strict;
use LWP;
use Log::Log4perl;

my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 } );
my $logger = Log::Log4perl->get_logger("Kruser::MLB::AtBat");

##
# Construct an instance
##
sub new
{
	my ( $proto, %params ) = @_;
	my $package = ref($proto) || $proto;

	my $this = { 
		apibase => undef, 
		storage => undef, 
	};

	foreach my $key ( keys %params )
	{
		$this->{$key} = $params{$key};
	}

	bless( $this, $package );
	return $this;
}

##
# Initiate the sync between the local storage solution
# and MLB's AtBat XML files
##
sub initiate_sync
{
	my $this = shift;
	$logger->info("Starting MLB ETL");
}

1;
