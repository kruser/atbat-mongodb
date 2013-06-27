package Kruser::MLB::Storage::Mongo;

##
# Provides storage to a MongoDB database where the source files are
# standard Perl data structures
#
# All structures will be convert to BSON/JSON before persisting
#
# @author kruser
##
use strict;
use Log::Log4perl;
use MongoDB;
use Data::Dumper;

$MongoDB::BSON::looks_like_number = 1;

my $logger = Log::Log4perl->get_logger("Kruser::MLB::AtBat");
my $mongoClient;
my $mongoDB;

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

	$mongoClient = MongoDB::MongoClient->new;
	$mongoClient->dt_type('DateTime::Tiny');
	$mongoDB = $mongoClient->get_database( $this->{dbName} );

	bless( $this, $package );
	return $this;
}

##
# Save a game and its rosters
#
# @param game - the game object
##
sub save_game
{
	my $this           = shift;
	my $game           = shift;
	my $collectionName = 'games';

	my $gamesCollection = $mongoDB->get_collection($collectionName);
	$gamesCollection->insert($game);
}

##
# Saves an array of at-bats
#
# @param {Object[]} atbats
##
sub save_at_bats
{
	my $this   = shift;
	my $atbats = shift;
	
	my $collectionName = 'atbats';

	my $collection = $mongoDB->get_collection($collectionName);
	my @ids = $collection->batch_insert(\@{$atbats});	
	
	my $length = @ids;
	$logger->debug("Saved $length at bats to the '$collectionName' collection");
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
