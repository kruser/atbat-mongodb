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

		my $shallowGameInfo = {
			id        => $gameId,
			time      => $game->{time},
			away_team => $game->{'away_code'},
			home_team => $game->{'home_code'},
		};

		my $url = $this->{apibase} . "/year_$year/month_$month/day_$day/epg.xml";

		my $inningsUrl = "$dayUrl/gid_$gameId/inning/inning_all.xml";
		$logger->debug("Getting at-bat details from $inningsUrl");
		my $inningsObj = $this->_get_xml_page_as_obj($inningsUrl);

		$this->_save_at_bats( $inningsObj, $shallowGameInfo );
		$this->_save_pitches( $inningsObj, $shallowGameInfo );

		my $gameRosterUrl = "$dayUrl/gid_$gameId/players.xml";
		$logger->debug("Getting game roster details from $gameRosterUrl");
		my $gameRosterObj = $this->_get_xml_page_as_obj($gameRosterUrl);
		if ($gameRosterObj)
		{
			$game->{team} = $gameRosterObj->{team};
		}

		$this->{storage}->save_game($game);
	}
}

##
# Runs through all innings and at-bats of a game and persists each
# pitch as their own object in the database, embedding game and inning info
# along the way
#
# @param innings - the object representing all innings
# @param shallowGame - the shallow game data that we'll embed in each pitch
## 
sub _save_pitches
{
	my $this            = shift;
	my $inningsObj      = shift;
	my $shallowGameInfo = shift;
}

##
# Run through a list of innings and save the at-bat
# data only. We're purposefully stripping out the pitches
# as those will be saved in another space
#
# @param innings - the object representing all innings
# @param shallowGame - the shallow game data that we'll embed in each at-bat
##
sub _save_at_bats
{
	my $this            = shift;
	my $inningsObj      = shift;
	my $shallowGameInfo = shift;

	if ($inningsObj)
	{
		foreach my $inning ( @{ $inningsObj->{inning} } )
		{
			if ( $inning->{top} )
			{
				my @atbats = @{ $inning->{top}->{atbat} };
				foreach my $atbat (@atbats)
				{
					undef $atbat->{'pitch'};
					$atbat->{'batter_team'}  = $inning->{'away_team'};
					$atbat->{'pitcher_team'} = $inning->{'home_team'};
					$atbat->{'inning'}       = {
						type   => 'top',
						number => $inning->{num},
					};
					$atbat->{'game'}           = $shallowGameInfo,;
					$atbat->{'start_tfs_zulu'} =
					  DateTime->from_epoch( epoch => str2time( $atbat->{'start_tfs_zulu'} ) );
				}
				$this->{storage}->save_at_bats( \@atbats );
			}
			if ( $inning->{bottom} )
			{
				my @atbats = @{ $inning->{bottom}->{atbat} };
				foreach my $atbat (@atbats)
				{
					undef $atbat->{'pitch'};
					$atbat->{'batter_team'}  = $inning->{'home_team'};
					$atbat->{'pitcher_team'} = $inning->{'away_team'};
					$atbat->{'inning'}       = {
						type   => 'bottom',
						number => $inning->{num},
					};
					$atbat->{'game'}           = $shallowGameInfo,;
					$atbat->{'start_tfs_zulu'} =
					  DateTime->from_epoch( epoch => str2time( $atbat->{'start_tfs_zulu'} ) );
				}
				$this->{storage}->save_at_bats( \@atbats );
			}
		}
	}
}

##
# Get a list of the game folders for a day
# @private
##
sub _get_games_for_day
{
	my $this   = shift;
	my $dayUrl = shift;

	my $url = "$dayUrl/epg.xml";
	$logger->debug("Getting gameday lists from $url");
	my $gamesObj = $this->_get_xml_page_as_obj($url);
	if ($gamesObj)
	{
		$this->_cleanup_games( \@{ $gamesObj->{game} } );
		return @{ $gamesObj->{game} };
	}
	else
	{
		return [];
	}
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
}

##
# Gets the XML file from the given URL and returns the content
# string or undefined if the retrieval failed
#
# @param {string} url
##
sub _get_xml_page
{
	my $this = shift;
	my $url  = shift;

	my $response = $browser->get($url);
	if ( $response->is_success )
	{
		my $xml = $response->content();
		return $xml;
	}
	else
	{
		$logger->warn("No content found at $url");
		return undef;
	}
}

##
# Gets a page of XML from an absolute URL and returns a Perl data structure representing
# those objects
#
# @returns the decoded object, or 0 if the URL was bad
##
sub _get_xml_page_as_obj
{
	my $this = shift;
	my $url  = shift;
	
	my $xml = $this->_get_xml_page($url);
	if ($xml)
	{
		return XMLin( $xml, KeyAttr => {} );
	}
	else
	{
		return undef;
	}
}

1;
