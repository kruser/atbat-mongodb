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
use Storable 'dclone';

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
		apibase     => undef,
		storage     => undef,
		beforetoday => 1,
		year        => undef,
		month       => undef,
		day         => undef,
		players     => {},
	};

	foreach my $key ( keys %params )
	{
		$this->{$key} = $params{$key};
	}

	bless( $this, $package );
	return $this;
}

##
# retreives data since the last sync point
##
sub initiate_sync
{
	my $this = shift;
	if ( $this->{year} && $this->{month} && $this->{day} )
	{
		$this->_retrieve_day( $this->{year}, $this->{month}, $this->{day} );
	}
	elsif ( $this->{year} && $this->{month} )
	{
		$this->_retrieve_month( $this->{year}, $this->{month} );
	}
	elsif ( $this->{year} )
	{
		$this->_retrieve_year( $this->{year} );
	}
	else
	{
		my $lastDate = $this->{storage}->get_last_sync_date();
		if ($lastDate)
		{
			$this->_retrieve_since($lastDate);
		}
		else
		{
			$logger->info(
"Your database doesn't have any data so we're not sure when to sync to. Try seeding it with a year or month."
			);
		}
	}
	$this->{storage}->save_players( $this->{players} );
}

##
# Retrieves all data since the given date
#
##
sub _retrieve_since
{
	my $this     = shift;
	my $lastDate = shift;

	my $lastDateTime = _convert_to_datetime($lastDate)->epoch() + 86400;
	my $today        = DateTime->now()->epoch();
	while ( $lastDateTime < $today )
	{
		my $dt = DateTime->from_epoch( epoch => $lastDateTime );
		$this->_retrieve_day( $dt->year(), $dt->month(), $dt->day() );
		$lastDateTime += 86400;
	}
}

##
# retrieves a full year
# @param year in YYYY format
##
sub _retrieve_year
{
	my $this = shift;
	my $year = shift;
	$logger->info("Retrieving a full year for $year. Sit tight, this could take a few minutes.");

	for ( my $month = 3 ; $month <= 11 && $this->{'beforetoday'} ; $month++ )
	{
		$this->_retrieve_month( $year, $month );
	}
}

##
# retrieves an entire month's worth of data
##
sub _retrieve_month
{
	my $this  = shift;
	my $year  = shift;
	my $month = shift;
	$logger->info("Retrieving data for the month $year-$month.");
	if ( $month > 2 && $month < 12 )
	{
		for ( my $day = 1 ; $day <= 31 && $this->{'beforetoday'} ; $day++ )
		{
			$this->_retrieve_day( $year, $month, $day );
		}
	}
	else
	{
		$logger->info("skipping analyzing $year-$month since there aren't MLB games");
	}
}

##
# retrieves a full day
# @param year in YYYY format
# @param day in DD format
##
sub _retrieve_day
{
	my $this  = shift;
	my $year  = shift;
	my $month = shift;
	my $day   = shift;

	my $targetDay;

	eval {
		$targetDay =
		  DateTime->new( year => $year, month => $month, day => $day, hour => 23, minute => 59, second => 59 );
	} or do { return; };

	# format the short strings for the URL
	$month = '0' . $month if $month < 10;
	$day   = '0' . $day   if $day < 10;
	my $dayString = "$year-$month-$day";

	my $now              = DateTime->now();
	my $millisDifference = $now->epoch() - $targetDay->epoch();
	if ( $millisDifference < 60 * 60 * 8 )
	{
		$logger->info("The target date for $dayString is today, in the future, or late last night. Exiting soon....");
		$this->{beforetoday} = 0;
		return;
	}
	elsif ( $this->{storage}->already_have_day($dayString) )
	{
		$logger->info("We already have some game data for $dayString. Skipping this day.");
		return;
	}

	my $dayUrl = $this->{apibase} . "/year_$year/month_$month/day_$day";
	$logger->info("Starting retrieving data for $dayString.");

	my @threads;
	my @games = $this->_get_games_for_day($dayUrl);
	foreach my $game (@games)
	{
		$game->{'source_day'} = $dayString;
		$this->_save_game_data( $dayUrl, $game );
	}
	$logger->info("Finished retrieving data for $dayString.");
}

##
# Gets the inning data for the game passed in and persists all at-bats
# and pitches.
#
# @param {string} dayUrl - the URL for all games that day
# @param {Object} game - the top level game data
##
sub _save_game_data
{
	my $this   = shift;
	my $dayUrl = shift;
	my $game   = shift;

	my $gameType = $game->{'game_type'};
	if ( $gameType eq 'R' )
	{
		my $gameId = $game->{gameday};

		my $shallowGameInfo = {
			id        => $gameId,
			time      => $game->{time},
			away_team => $game->{'away_code'},
			home_team => $game->{'home_code'},
		};

		my $inningsUrl = "$dayUrl/gid_$gameId/inning/inning_all.xml";
		$logger->debug("Getting at-bat details from $inningsUrl");
		my $inningsXml = $this->_get_xml_page($inningsUrl);
		if ($inningsXml)
		{
			my $eventsUrl = "$dayUrl/gid_$gameId/game_events.xml";
			$logger->debug("Getting game events from $eventsUrl");
			my $eventsXml = $this->_get_xml_page($eventsUrl);
			my $eventsObj;
			if ($eventsXml)
			{
				$eventsObj = XMLin(
					$eventsXml,
					KeyAttr    => { atbat     => 'num', inning => 'num' },
					ForceArray => [ 'inning', 'atbat',  'pitch' ]
				  ),
				  ;
			}

			$this->_save_at_bats(
				XMLin( $inningsXml, KeyAttr => {}, ForceArray => [ 'inning', 'atbat', 'runner', 'action', 'po' ] ),
				$shallowGameInfo, $eventsObj );
			$this->_save_pitches(
				XMLin( $inningsXml, KeyAttr => {}, ForceArray => [ 'inning', 'atbat', 'runner', 'pitch' ] ),
				$shallowGameInfo );
		}

		my $gameRosterUrl = "$dayUrl/gid_$gameId/players.xml";
		$logger->debug("Getting game roster details from $gameRosterUrl");

		my $gameRosterXml = $this->_get_xml_page($gameRosterUrl);
		if ($gameRosterXml)
		{
			my $gameRosterObj = XMLin( $gameRosterXml, KeyAttr => {}, ForceArray => [ 'team', 'player', 'coach' ] );
			if ( $gameRosterObj && $gameRosterObj->{team} )
			{
				$game->{team} = $gameRosterObj->{team};

				foreach my $team ( @{ $gameRosterObj->{team} } )
				{
					if ( $team->{'player'} )
					{
						foreach my $player ( @{ $team->{'player'} } )
						{
							$this->{players}->{ $player->{id} } = {
								id    => $player->{id},
								first => $player->{first},
								last  => $player->{last},
							};
						}
					}
				}
			}
		}
		$this->{storage}->save_game($game);
	}

}

##
# Runs through all innings and at-bats of a game and persists each
# pitch as their own object in the database, embedding game and inning info
# along the way
#
# TODO: I'm sure this could be refactored with <code>_save_at_bats</code> to reduce
# a little code redundancy.
#
# @param innings - the object representing all innings
# @param shallowGame - the shallow game data that we'll embed in each pitch
# @private
##
sub _save_pitches
{
	my $this            = shift;
	my $inningsObj      = shift;
	my $shallowGameInfo = shift;

	my @allPitches = ();

	if ($inningsObj)
	{
		foreach my $inning ( @{ $inningsObj->{inning} } )
		{
			if ( $inning->{top} && $inning->{top}->{atbat} )
			{
				my @atbats = @{ $inning->{top}->{atbat} };
				foreach my $atbat (@atbats)
				{
					$atbat->{'batter_team'}    = $inning->{'away_team'};
					$atbat->{'pitcher_team'}   = $inning->{'home_team'};
					$atbat->{'start_tfs_zulu'} = _convert_to_datetime( $atbat->{'start_tfs_zulu'} );

					my $shallowAtBat = dclone($atbat);
					undef $shallowAtBat->{'pitch'};

					if ( $atbat->{pitch} )
					{
						my @pitches = @{ $atbat->{pitch} };
						foreach my $pitch (@pitches)
						{
							$pitch->{'tfs_zulu'} = _convert_to_datetime( $pitch->{'tfs_zulu'} );
							$pitch->{'game'}     = $shallowGameInfo;
							$pitch->{'inning'}   = {
								type   => 'top',
								number => $inning->{num},
							};
							$pitch->{'atbat'} = $shallowAtBat;
							push( @allPitches, $pitch );
						}
					}
				}
			}
			if ( $inning->{bottom} && $inning->{bottom}->{atbat} )
			{
				my @atbats = @{ $inning->{bottom}->{atbat} };
				foreach my $atbat (@atbats)
				{
					$atbat->{'batter_team'}    = $inning->{'home_team'};
					$atbat->{'pitcher_team'}   = $inning->{'away_team'};
					$atbat->{'start_tfs_zulu'} = _convert_to_datetime( $atbat->{'start_tfs_zulu'} );

					my $shallowAtBat = dclone($atbat);
					undef $shallowAtBat->{'pitch'};

					if ( $atbat->{pitch} )
					{
						my @pitches = @{ $atbat->{pitch} };
						foreach my $pitch (@pitches)
						{
							$pitch->{'tfs_zulu'} = _convert_to_datetime( $pitch->{'tfs_zulu'} );
							$pitch->{'game'}     = $shallowGameInfo;
							$pitch->{'inning'}   = {
								type   => 'bottom',
								number => $inning->{num},
							};
							$pitch->{'atbat'} = $shallowAtBat;
							push( @allPitches, $pitch );
						}
					}
				}
			}
		}
	}
	$this->{storage}->save_pitches( \@allPitches );
}

##
# Run through a list of innings and save the at-bat
# data only. We're purposefully stripping out the pitches
# as those will be saved in another space
#
# @param innings - the object representing all innings
# @param shallowGame - the shallow game data that we'll embed in each at-bat
# @param events - contains higher level information about each at-bat, including the runner positions to start the at-bat
# @private
##
sub _save_at_bats
{
	my $this            = shift;
	my $inningsObj      = shift;
	my $shallowGameInfo = shift;
	my $events          = shift;

	my @allAtBats = ();
	if ( $inningsObj && $inningsObj->{'inning'} )
	{
		foreach my $inning ( @{ $inningsObj->{inning} } )
		{
			if ( $inning->{top} && $inning->{top}->{atbat} )
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
					$atbat->{'start_tfs_zulu'} = _convert_to_datetime( $atbat->{'start_tfs_zulu'} );

					#_inject_baserunners( $atbat, $events, 'top', $inning->{num} );
					push( @allAtBats, $atbat );
				}
			}
			if ( $inning->{bottom} && $inning->{bottom}->{atbat} )
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
					$atbat->{'start_tfs_zulu'} = _convert_to_datetime( $atbat->{'start_tfs_zulu'} );
					#_inject_baserunners( $atbat, $events, 'bottom', $inning->{num} );
					push( @allAtBats, $atbat );
				}
			}
		}
	}
	$this->{storage}->save_at_bats( \@allAtBats );
}

##
# Browse through the events list and get the baserunner positions for the given at-bat
##
sub _inject_baserunners
{
	my $atbat        = shift;
	my $events       = shift;
	my $topOrBottom  = shift;
	my $inningNumber = shift;

	if (   $events
		&& $events->{'inning'}
		&& $events->{'inning'}->{$inningNumber}
		&& $events->{'inning'}->{$inningNumber}->{$topOrBottom}
		&& $events->{'inning'}->{$inningNumber}->{$topOrBottom}->{'atbat'}
		&& $events->{'inning'}->{$inningNumber}->{$topOrBottom}->{'atbat'}->{ $atbat->{num} } )
	{
		my $eventAb = $events->{'inning'}->{$inningNumber}->{$topOrBottom}->{'atbat'}->{ $atbat->{num} };

		my $runnerPositions = {
			end => {
				b1 => $eventAb->{'b1'},
				b2 => $eventAb->{'b2'},
				b3 => $eventAb->{'b3'},
			}
		};

		my $previousAbNumber = int( $atbat->{num} ) - 1;
		my $previousAb       = $events->{'inning'}->{$inningNumber}->{$topOrBottom}->{'atbat'}->{$previousAbNumber};
		if ($previousAb)
		{

			# this will fail gracefully if the previous at-bat wasn't in the same inning
			$runnerPositions->{'start'} = {
				b1 => $previousAb->{'b1'},
				b2 => $previousAb->{'b2'},
				b3 => $previousAb->{'b3'},
			};
		}
		else
		{
			$runnerPositions->{'start'} = {
				b1 => '',
				b2 => '',
				b3 => '',
			};
		}

		$atbat->{'bases'} = $runnerPositions;
		$atbat->{'rbi'}   = $eventAb->{'rbi'};
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
	my $gamesXml = $this->_get_xml_page($url);
	my $gamesObj = XMLin( $gamesXml, KeyAttr => {}, ForceArray => ['game'] );
	if ( $gamesObj && $gamesObj->{game} )
	{
		$this->_cleanup_games( \@{ $gamesObj->{game} } );
		return @{ $gamesObj->{game} };
	}
	else
	{
		return ();
	}
}

##
# cleanup the data within the games
#
# @param {Object[]} games - the array of games
# @private
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
# @private
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
# Converts a date string to a DateTime object
#
# @param {string} datetimeString
# @static
# @private
##
sub _convert_to_datetime
{
	my $datetimeString = shift;
	eval {
		my $conversion = DateTime->from_epoch( epoch => str2time($datetimeString) );
		return $conversion;
	  }
	  or do
	{
		$logger->error("The string '$datetimeString' can't be converted to a DateTime object");
		return undef;
	};
}

1;
