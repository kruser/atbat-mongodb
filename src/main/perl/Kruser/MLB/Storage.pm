package Kruser::MLB::Storage;

##
# Provides storage to a MongoDB database
#
# @author kruser
##
use strict;
use Log::Log4perl;
use MongoDB;

my $logger = Log::Log4perl->get_logger("Kruser::MLB::AtBat");

# construct an instance
sub new
{
	my ( $proto, %params ) = @_;
	my $package = ref($proto) || $proto;

	my $this = {
		dbName => undef,
		dbHost => 'localhost'
	};

	foreach my $key ( keys %params )
	{
		$this->{$key} = $params{$key};
	}

	bless( $this, $package );
	return $this;
}

##
# Saves an array of innings
#
# @param innings array
##
sub save_innings
{
	my $this = shift;
}

##
# Get the date when the database was last sync'd to
# MLB data
#
# @returns epoch timestamp of the last sync
##
sub get_last_sync_date
{
	my $this = shift;
}
1;
