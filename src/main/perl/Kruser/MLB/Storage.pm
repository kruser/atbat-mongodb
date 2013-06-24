package Kruser::MLB::Storage;

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
	$mongoDB     = $mongoClient->get_database( $this->{dbName} );

	bless( $this, $package );
	return $this;
}

##
# Save game rosters
#
# @param games array
##
sub save_games
{
	my $this           = shift;
	my $games          = shift;
	my $collectionName = 'games';

	my $gamesCollection = $mongoDB->get_collection($collectionName);
	my @ids = $gamesCollection->batch_insert(\@$games);

	my $originalGamesLength = @$games;
	my $idLength            = @ids;
	if ( $idLength == $originalGamesLength )
	{
		$logger->info("Saved $idLength games to the '$collectionName' table");
	}
	else
	{
		$logger->error("Failed saving '$originalGamesLength' games to the database. Only $idLength succeeded");
	}
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
