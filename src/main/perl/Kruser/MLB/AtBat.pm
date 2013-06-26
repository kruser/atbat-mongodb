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
use XML::Simple;
use Data::Dumper;
use Date::Parse;
use DateTime;

my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 } );
my $logger  = Log::Log4perl->get_logger("Kruser::MLB::AtBat");

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
	if ( $this->{year} )
	{
		$this->_retrieve_year( $this->{year} );
	}
	else
	{
		$this->_retrieve_since_last();
	}
}

##
# retreives data since the last sync point
sub retrieve_since_last
{

}

##
# retrieves a full year
# @param year in YYYY format
##
sub retrieve_year
{
	my $this = shift;
	my $year = shift;
	$logger->info("Retrieving a full year for $year. Sit tight, this could take a few minutes.");
}

##
# retrieves an entire month's worth of data
##
sub retrieve_month
{
	my $this  = shift;
	my $year  = shift;
	my $month = shift;
	my $day   = shift;
	$logger->info("Retrieving data for the month $year-$month.");
}

##
# retrieves a full day
# @param year in YYYY format
# @param day in DD format
##
sub retrieve_day
{
	my $this  = shift;
	my $year  = shift;
	my $month = shift;
	my $day   = shift;

	# format the short strings for the URL
	$month = '0' . $month if $month < 10;
	$day   = '0' . $day   if $day < 10;

	my $dayUrl = $this->{apibase} . "/year_$year/month_$month/day_$day";

	$logger->info("Retrieving data for $year-$month-$day.");

	my @games = $this->_get_games_for_day($dayUrl);
	foreach my $game (@games)
	{
		my $gameId = $game->{gameday};
		my $url    = $this->{apibase} . "/year_$year/month_$month/day_$day/epg.xml";

		my $inningsUrl = "$dayUrl/gid_$gameId/inning/inning_all.xml";
		$logger->debug("Getting at-bat details from $inningsUrl");
		my $inngingsObj = _get_xml_page_as_obj($inningsUrl);

		my $gameRosterUrl = "$dayUrl/gid_$gameId/players.xml";
		$logger->debug("Getting game roster details from $gameRosterUrl");
		my $gameRosterObj = _get_xml_page_as_obj($gameRosterUrl);
	}
}

##
# Get a list of the game folders for a day
##
sub _get_games_for_day
{
	my $this   = shift;
	my $dayUrl = shift;

	my $url = "$dayUrl/epg.xml";
	$logger->debug("Getting gameday lists from $url");
	my $gamesObj = $this->_get_xml_page_as_obj($url);
	$this->_cleanup_games( \@{ $gamesObj->{game} } );
	if ( $gamesObj->{game} )
	{
		$this->{storage}->save_games( \@{ $gamesObj->{game} } );
	}
	else
	{
		$logger->error("Unable to find any games listed at $url");
	}
	return @{ $gamesObj->{game} };
}

##
# cleanup the data within the games
##
sub _cleanup_games
{
	my $this  = shift;
	my $games = shift;

	foreach my $game ( @{$games} )
	{
		if ( $game->{game_media} )
		{
			undef( $game->{game_media} );
		}
		if ( $game->{start} )
		{
			$game->{start} = DateTime->from_epoch( epoch => str2time( $game->{start} ) );
		}
	}

	print Dumper($games);
}

##
# Gets a page of XML from an absolute URL and returns a Perl data structure representing
# those objects
##
sub _get_xml_page_as_obj
{
	my $this = shift;
	my $url  = shift;

	my $response = $browser->get($url);
	my $content  = $response->content();
	my $objs     = XMLin( $content, KeyAttr => {} );
	return $objs;
}

1;
