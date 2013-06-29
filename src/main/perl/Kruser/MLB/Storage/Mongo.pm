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

my $logger = Log::Log4perl->get_logger("Kruser::MLB::Storage::Mongo");
my $mongoClient;
my $mongoDB;

##
# construct an instance
# TODO: use the dbHost property
##
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

	my $length = @{$atbats};
	if ($length)
	{
		my $collection = $mongoDB->get_collection($collectionName);
		my @ids        = $collection->batch_insert( \@{$atbats} );

		my $length = @ids;
		$logger->debug("Saved $length at bats to the '$collectionName' collection");
	}
}
##
# Saves an array of pitches
#
# @param {Object[]} pitches
##
sub save_pitches
{
	my $this    = shift;
	my $pitches = shift;

	my $collectionName = 'pitches';

	my $length = @{$pitches};
	if ($length)
	{
		my $collection = $mongoDB->get_collection($collectionName);
		my @ids        = $collection->batch_insert( \@{$pitches} );

		my $length = @ids;
		$logger->debug("Saved $length pitches to the '$collectionName' collection");
	}
}

##
# This method will be called to save or update any players. Each object will have an
# 'id' property. If one entry already exists in the database for this ID, the new record
# should simply overwrite or ignore that entry
#
# @param {Object%} players - key is the MLB ID of the player
##
sub save_players
{
	my $this           = shift;
	my $players        = shift;
	my $collectionName = 'players';

	my $collection    = $mongoDB->get_collection($collectionName);
	my @playersToSave = ();

	foreach my $playerId ( keys %$players )
	{
		my $result = $collection->find_one( { id => $playerId } );
		if ( !$result )
		{
			push( @playersToSave, $players->{$playerId} );
		}
	}

	my $length = @playersToSave;
	if ($length)
	{
		my @ids = $collection->batch_insert( \@playersToSave );

		my $length = @ids;
		$logger->debug("Saved $length players to the '$collectionName' collection");
	}
}

##
# Get the date when the database was last sync'd to
# MLB data
#
# A cli query for this might look like...
# db.games.find().sort({'source_day':-1}).limit(1).pretty();
#
# @returns {long} epoch timestamp of the last sync
##
sub get_last_sync_date
{
	my $this = shift;
}

##
# Checks if we already have games for that day.
#
# A cli query for this might look like...
# db.games.find({'source_day':'2013-06-01'}).limit(1).pretty();
#
# @param {string} day in YYYY-MM-DD format
# @returns {boolean} true if we already have persisted data for this day
##
sub already_have_day
{
	my $this      = shift;
	my $dayString = shift;

	my $gamesCollection = $mongoDB->get_collection('games');
	my $gamesForDay     = $gamesCollection->find( { 'source_day' => $dayString } );
	my $count = $gamesForDay->count();
	return $count;
}
1;
