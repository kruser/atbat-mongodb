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
use Kruser::MLB::HitAdjuster;

my $browser = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 } );
my $logger  = Log::Log4perl->get_logger("Kruser::MLB::AtBat");

##
# Construct an instance
##
sub new {
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

	foreach my $key ( keys %params ) {
		$this->{$key} = $params{$key};
	}

	bless( $this, $package );
	return $this;
}

##
# retreives data since the last sync point
##
sub initiate_sync {
	my $this = shift;
	if ( $this->{year} && $this->{month} && $this->{day} ) {
		$this->_retrieve_day( $this->{year}, $this->{month}, $this->{day} );
	}
	elsif ( $this->{year} && $this->{month} ) {
		$this->_retrieve_month( $this->{year}, $this->{month} );
	}
	elsif ( $this->{year} ) {
		$this->_retrieve_year( $this->{year} );
	}
	else {
		my $lastDate = $this->{storage}->get_last_sync_date();
		if ($lastDate) {
			$this->_retrieve_since($lastDate);
		}
		else {
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
sub _retrieve_since {
	my $this     = shift;
	my $lastDate = shift;

	my $lastDateTime = _convert_to_datetime($lastDate)->epoch() + 86400;
	my $today        = DateTime->now()->epoch();
	while ( $lastDateTime < $today ) {
		my $dt = DateTime->from_epoch( epoch => $lastDateTime );
		$this->_retrieve_day( $dt->year(), $dt->month(), $dt->day() );
		$lastDateTime += 86400;
	}
}

##
# retrieves a full year
# @param year in YYYY format
##
sub _retrieve_year {
	my $this = shift;
	my $year = shift;
	$logger->info(
"Retrieving a full year for $year. Sit tight, this could take a few minutes."
	);

	for ( my $month = 3 ; $month <= 11 && $this->{'beforetoday'} ; $month++ ) {
		$this->_retrieve_month( $year, $month );
	}
}

##
# retrieves an entire month's worth of data
##
sub _retrieve_month {
	my $this  = shift;
	my $year  = shift;
	my $month = shift;
	$logger->info("Retrieving data for the month $year-$month.");
	if ( $month > 1 && $month < 12 ) {
		for ( my $day = 1 ; $day <= 31 && $this->{'beforetoday'} ; $day++ ) {
			$this->_retrieve_day( $year, $month, $day );
		}
	}
	else {
		$logger->info(
			"skipping analyzing $year-$month since there aren't MLB games");
	}
}

##
# retrieves a full day
# @param year in YYYY format
# @param day in DD format
##
sub _retrieve_day {
	my $this  = shift;
	my $year  = shift;
	my $month = shift;
	my $day   = shift;

	my $targetDay;

	eval {
		$targetDay = DateTime->new(
			year   => $year,
			month  => $month,
			day    => $day,
			hour   => 23,
			minute => 59,
			second => 59
		);
	} or do { return; };

	my $fallbackDate = DateTime->new(
		year   => $year,
		month  => $month,
		day    => $day,
		hour   => 20,
		minute => 0,
		second => 0
	);

	# format the short strings for the URL
	$month = '0' . $month if $month < 10;
	$day   = '0' . $day   if $day < 10;
	my $dayString = "$year-$month-$day";

	my $now              = DateTime->now();
	my $millisDifference = $now->epoch() - $targetDay->epoch();
	if ( $millisDifference < 60 * 60 * 8 ) {
		$logger->info(
"The target date for $dayString is today, in the future, or late last night. Exiting soon...."
		);
		$this->{beforetoday} = 0;
		return;
	}
	elsif ( $this->{storage}->already_have_day($dayString) ) {
		$logger->info(
			"We already have some game data for $dayString. Skipping this day."
		);
		return;
	}

	my $dayUrl = $this->{apibase} . "/year_$year/month_$month/day_$day";
	$logger->info("Starting retrieving data for $dayString.");

	my @threads;
	my @games = $this->_get_games_for_day($dayUrl);
	foreach my $game (@games) {
		$game->{'source_day'} = $dayString;
		$game->{'start'}      =
		  _convert_to_datetime( $game->{'start'}, $fallbackDate );
		$this->_save_game_data( $dayUrl, $game, $fallbackDate );
	}
	$logger->info("Finished retrieving data for $dayString.");
}

##
# Gets the inning data for the game passed in and persists all at-bats
# and pitches.
#
# @param {string} dayUrl - the URL for all games that day
# @param {Object} game - the top level game data
# @param {Object} fallbackDate - on MLB gameday servers some games and at-bats don't have a good timestamp. When that's the case this will be used.
##
sub _save_game_data {
	my $this         = shift;
	my $dayUrl       = shift;
	my $game         = shift;
	my $fallbackDate = shift;

	$game->{start} = _convert_to_datetime( $game->{start}, $fallbackDate );

	my $gameId = $game->{gameday};

	my $shallowGameInfo = {
		id        => $gameId,
		time      => $game->{time},
		away_team => $game->{'away_code'},
		home_team => $game->{'home_code'},
		venue_id  => $game->{'venue_id'},
		game_type => $game->{'game_type'},
	};

	my $gameRosterUrl = "$dayUrl/gid_$gameId/players.xml";
	$logger->debug("Getting game roster details from $gameRosterUrl");

	my $gameRosterXml = $this->_get_xml_page($gameRosterUrl);
	if ($gameRosterXml) {
		my $gameRosterObj = XMLin(
			$gameRosterXml,
			KeyAttr    => {},
			ForceArray => [ 'team', 'player', 'coach' ]
		);
		if ( $gameRosterObj && $gameRosterObj->{team} ) {
			$game->{team} = $gameRosterObj->{team};

			foreach my $team ( @{ $gameRosterObj->{team} } ) {
				if ( $team->{'player'} ) {
					foreach my $player ( @{ $team->{'player'} } ) {
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

	my $inningsUrl = "$dayUrl/gid_$gameId/inning/inning_all.xml";
	$logger->debug("Getting at-bat details from $inningsUrl");
	my $inningsXml = $this->_get_xml_page($inningsUrl);

	my $hitsUrl = "$dayUrl/gid_$gameId/inning/inning_hit.xml";
	$logger->debug("Getting hit details from $hitsUrl");
	my $hitsXml = $this->_get_xml_page($hitsUrl);

	if ( $inningsXml && $hitsXml ) {

		my $hitsForAtBats =
		  $this->_add_hit_angles(
			XMLin( $hitsXml, KeyAttr => {}, ForceArray => ['hip'] ) );

		$this->_save_at_bats(
			XMLin(
				$inningsXml,
				KeyAttr    => {},
				ForceArray =>
				  [ 'inning', 'atbat', 'runner', 'action', 'pitch', 'po' ]
			),
			$hitsForAtBats,
			$shallowGameInfo,
			$fallbackDate
		);

		my $hitsForPitches =
		  $this->_add_hit_angles(
			XMLin( $hitsXml, KeyAttr => {}, ForceArray => ['hip'] ) );

		$this->_save_pitches(
			XMLin(
				$inningsXml,
				KeyAttr    => {},
				ForceArray => [ 'inning', 'atbat', 'runner', 'pitch' ]
			),
			$hitsForPitches,
			$shallowGameInfo,
			$fallbackDate
		);
	}

}

##
# Cycles through a list of hit balls and use the X/Y coordinates to formulate an angle
# of the hit. 0 degrees will be straight up the middle of the field. -45 degrees is the left
# foul pole and 45 degress is the right foul pole.
##
sub _add_hit_angles {
	my $this    = shift;
	my $hipList = shift;

	my $hitAdjuster = new Kruser::MLB::HitAdjuster();

	if ( $hipList->{hip} ) {
		for my $hip ( @{ $hipList->{hip} } ) {
			$hip->{angle} = $hitAdjuster->get_hit_angle($hip);

		 # don't insert distance as they aren't reliable just yet
		 #$hip->{estimatedDistance} = $hitAdjuster->estimate_hit_distance($hip);
		}
	}
	return $hipList;
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
# @param hitBalls - the object representing all hit balls
# @param shallowGame - the shallow game data that we'll embed in each pitch
# @param fallbackDate - the day to use if we don't have one per pitch
# @private
##
sub _save_pitches {
	my $this            = shift;
	my $inningsObj      = shift;
	my $hitBalls        = shift;
	my $shallowGameInfo = shift;
	my $fallbackDate    = shift;

	my @allPitches = ();

	if ($inningsObj) {
		foreach my $inning ( @{ $inningsObj->{inning} } ) {
			$this->_save_pitches_from_half_inning( $inning, 'top', $hitBalls,
				$shallowGameInfo, $fallbackDate, \@allPitches );
			$this->_save_pitches_from_half_inning( $inning, 'bottom', $hitBalls,
				$shallowGameInfo, $fallbackDate, \@allPitches );
		}
	}
	$this->{storage}->save_pitches( \@allPitches );
}

##
# Saves all pitches from a 1/2 inning's at-bats
#
sub _save_pitches_from_half_inning {
	my $this             = shift;
	my $inning           = shift;
	my $inningSide       = shift;
	my $hitBalls         = shift;
	my $shallowGameInfo  = shift;
	my $fallbackDate     = shift;
	my $aggregatePitches = shift;

	if ( $inning->{$inningSide} && $inning->{$inningSide}->{atbat} ) {
		my $startingOuts = 0;
		my @atbats = @{ $inning->{$inningSide}->{atbat} };
		foreach my $atbat (@atbats) {
			$atbat->{'batter_team'} =
			  ( $inningSide eq 'top' )
			  ? $inning->{'away_team'}
			  : $inning->{'home_team'};
			$atbat->{'pitcher_team'} =
			  ( $inningSide eq 'top' )
			  ? $inning->{'home_team'}
			  : $inning->{'away_team'};
			$atbat->{'start_tfs_zulu'} =
			  _convert_to_datetime( $atbat->{'start_tfs_zulu'}, $fallbackDate );
			$atbat->{'o_start'} = $startingOuts;
			$startingOuts = $atbat->{'o'};

			my $shallowAtBat = dclone($atbat);
			undef $shallowAtBat->{'pitch'};

			if ( $atbat->{pitch} ) {
				my @pitches = @{ $atbat->{pitch} };

				my $hip =
				  $this->_get_hip_for_atbat( $hitBalls, $inning->{num},
					$atbat->{batter} );
				if ($hip) {

					# inject the hit ball on the last pitch of the at-bat
					$pitches[-1]->{'hip'} = $hip;
				}

				foreach my $pitch (@pitches) {
					$pitch->{'tfs_zulu'} =
					  _convert_to_datetime( $pitch->{'tfs_zulu'},
						$fallbackDate );
					$pitch->{'game'}   = $shallowGameInfo;
					$pitch->{'inning'} = {
						type   => $inningSide,
						number => $inning->{num},
					};
					$pitch->{'atbat'} = $shallowAtBat;
					push( @{$aggregatePitches}, $pitch );
				}
			}
		}
	}

}

##
# Run through a list of innings and save the at-bat
# data only. We're purposefully stripping out the pitches
# as those will be saved in another space
#
# @param inningsObj - the object representing all innings
# @param hitsObj - the object representing all hit balls
# @param shallowGame - the shallow game data that we'll embed in each at-bat
# @param fallbackDate - the date to use on the atbats if we don't have one from MLB
# @private
##
sub _save_at_bats {
	my $this            = shift;
	my $inningsObj      = shift;
	my $hitsObj         = shift;
	my $shallowGameInfo = shift;
	my $fallbackDate    = shift;

	my @allAtBats = ();
	if ( $inningsObj && $inningsObj->{'inning'} ) {
		foreach my $inning ( @{ $inningsObj->{inning} } ) {
			if ( $inning->{top} && $inning->{top}->{atbat} ) {
				$this->_save_at_bats_for_inning( $inning, $hitsObj, 'top',
					$shallowGameInfo, \@allAtBats, $fallbackDate );

			}
			if ( $inning->{bottom} && $inning->{bottom}->{atbat} ) {
				$this->_save_at_bats_for_inning( $inning, $hitsObj, 'bottom',
					$shallowGameInfo, \@allAtBats, $fallbackDate );
			}
		}
	}
	$this->{storage}->save_at_bats( \@allAtBats );
}

##
# Finds players that have been accumulated via the games retrieved.
#
# Note this doesn't go against the database, so it only will find players listed
# on the scorecards on the days selected.
##
sub _find_player {
	my $this      = shift;
	my $firstName = shift;
	my $lastName  = shift;

	for my $player ( values %{ $this->{players} } ) {
		if ( $player->{last} eq $lastName && $player->{first} eq $firstName ) {
			return $player->{id};
		}
	}
	return undef;
}

##
# Handles persisting all at bats in an array that represents
# the top or bottom half of an inning.
#
# The processed results are pushed on the $aggregateAtBats array
# and are assumed to be persisted by the calling method
#
# Note that we're not persisting at-bats and runners like a game log. Instead, we're storing the
# at-bat sa the first class citizen and retrofitting 'runners' to be exactly what the batter
# had on base at the time of their event. This takes out stolen bases that happened during the at-bat.
#
# @param atBats - the array of bats
# @param inning - the inning details
# @param hitBalls - the hit balls for the game so we can pull each hit an inject it as needed
# @param inningSide - (top|bottom), the side of the inning
# @param shallowGameInfo - an arbitrary game object that we'll stick in each at-bat
# @param aggregateAtBats - an array for all of the at-bats that the caller will be aggregating, presumedly for storage
# @param fallbackDate
##
sub _save_at_bats_for_inning {
	my $this            = shift;
	my $inning          = shift;
	my $hitBalls        = shift;
	my $inningSide      = shift;
	my $shallowGameInfo = shift;
	my $aggregateAtBats = shift;
	my $fallbackDate    = shift;

	my $startingOuts = 0;
	my @atbats       = @{ $inning->{$inningSide}->{'atbat'} };
	foreach my $atbat (@atbats) {
		my $atBatEvent = $atbat->{'event'};

		$atbat->{'batter_team'} =
		    $inningSide eq 'top'
		  ? $inning->{'away_team'}
		  : $inning->{'home_team'};
		$atbat->{'pitcher_team'} =
		    $inningSide eq 'top'
		  ? $inning->{'home_team'}
		  : $inning->{'away_team'};
		$atbat->{'inning'} = {
			type   => $inningSide,
			number => $inning->{num},
		};
		$atbat->{'o_start'}        = $startingOuts;
		$atbat->{'game'}           = $shallowGameInfo,;
		$atbat->{'start_tfs_zulu'} =
		  _convert_to_datetime( $atbat->{'start_tfs_zulu'}, $fallbackDate );

		my $hip =
		  $this->_get_hip_for_atbat( $hitBalls, $inning->{num},
			$atbat->{batter} );
		if ($hip) {
			$atbat->{'hip'} = $hip;

			my $trajectory = 'grounder';
			if ( $atbat->{'des'} =~ /pop up|pops out/i ) {
				$trajectory = 'popup';
			}
			elsif ( $atbat->{'des'} =~ /line drive|lines out/i ) {
				$trajectory = 'liner';
			}
			elsif ( $atbat->{'des'} =~ /fly ball|flies out/i ) {
				$trajectory = 'flyball';
			}
			$atbat->{'hip'}->{'trajectory'} = $trajectory;
		}

		my $runnersPotentialBases = 0;
		if ( $atbat->{'pitch'} ) {
			my @pitches   = @{ $atbat->{'pitch'} };
			my $lastPitch = $pitches[-1];
			if ($lastPitch) {
				if ( $lastPitch->{'on_1b'} ) {
					$runnersPotentialBases += 3;
				}
				if ( $lastPitch->{'on_2b'} ) {
					$runnersPotentialBases += 2;
				}
				if ( $lastPitch->{'on_3b'} ) {
					$runnersPotentialBases += 1;
				}
			}
		}
		$atbat->{'runnersPotentialBases'} = $runnersPotentialBases;

		my $runnersMovedBases = 0;
		if ( $atbat->{'runner'} ) {
			my @runners = @{ $atbat->{'runner'} };
			foreach my $runner (@runners) {
				$runnersMovedBases += _get_runners_moved($runner);
			}
		}
		$atbat->{'runnersMovedBases'} = $runnersMovedBases;
		push( @{$aggregateAtBats}, $atbat );
		$startingOuts = $atbat->{'o'};
	}
}

##
# Hand me a list of hit balls and we'll pick the one for your batter/inning (the first one for that inning)
#
# Note that the inbound list will be altered, in that we'll remove the match to make this method a little
# faster on the next go-round. The method isn't that performant, but it's good enough.
#
# @param hitBalls - a hash containing an array of hits at $hitBalls->{'hip'}
# @param inning - the inning number
# @param batterId - the ID of the batter
# @returns a hip instance or undefined if it there wasn't a match.
# @private
##
sub _get_hip_for_atbat {
	my $this     = shift;
	my $hitBalls = shift;
	my $inning   = shift;
	my $batterId = shift;

	my @hips     = @{ $hitBalls->{'hip'} };
	my $hipCount = @hips;

	my $hipMatch      = undef;
	my $hipMatchIndex = undef;

	for ( my $i = 0 ; $i < $hipCount ; $i++ ) {
		my $hip = @hips[$i];
		if (   $hip->{'inning'} == $inning
			&& $hip->{'batter'} == $batterId
			&& $hip->{'des'} ne 'Error' )
		{
			$hipMatch      = $hip;
			$hipMatchIndex = $i;
			last;
		}
	}
	if ( $hipMatch && $hipMatchIndex >= 0 ) {
		splice( @{ $hitBalls->{'hip'} }, $hipMatchIndex, 1 );
	}
	return $hipMatch;
}

##
# Get a list of the game folders for a day
# @private
##
sub _get_games_for_day {
	my $this   = shift;
	my $dayUrl = shift;

	my $url = "$dayUrl/epg.xml";
	$logger->debug("Getting gameday lists from $url");
	my $gamesXml = $this->_get_xml_page($url);
	my $gamesObj = XMLin( $gamesXml, KeyAttr => {}, ForceArray => ['game'] );
	if ( $gamesObj && $gamesObj->{game} ) {
		$this->_cleanup_games( \@{ $gamesObj->{game} } );
		return @{ $gamesObj->{game} };
	}
	else {
		return ();
	}
}

##
# cleanup the data within the games
#
# @param {Object[]} games - the array of games
# @private
##
sub _cleanup_games {
	my $this  = shift;
	my $games = shift;

	foreach my $game ( @{$games} ) {
		if ( $game->{game_media} ) {
			undef( $game->{game_media} );
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
sub _get_xml_page {
	my $this = shift;
	my $url  = shift;

	my $response = $browser->get($url);
	if ( $response->is_success ) {
		my $xml = $response->content();
		return $xml;
	}
	else {
		$logger->warn("No content found at $url");
		return undef;
	}
}

##
# Get the number of bases that a runner moved in the at-bat
#
# @param {runner} - the runner as it comes from the atbat schema
# @returns the number of bases moved by a runner that isn't the batter
# @static
# @private
##
sub _get_runners_moved {
	my $runner = shift;

	my $endInt  = 0;
	my $endBase = $runner->{'end'};

	my $startInt  = 0;
	my $startBase = $runner->{'start'};

	if ($startBase) {
		if ( $startBase eq '1B' ) {
			$startInt = 1;
		}
		elsif ( $startBase eq '2B' ) {
			$startInt = 2;
		}
		elsif ( $startBase eq '3B' ) {
			$startInt = 3;
		}

		if ( $endBase eq '' && $runner->{'score'} eq 'T' ) {
			$endInt = 4;
		}
		elsif ( $endBase eq '' ) {
			$endInt = $startInt;
		}
		elsif ( $endBase eq '3B' ) {
			$endInt = 3;
		}
		elsif ( $endBase eq '2B' ) {
			$endInt = 2;
		}
		elsif ( $endBase eq '1B' ) {
			$endInt = 1;
		}
	}
	return $endInt - $startInt;
}

##
# Converts a date string to a DateTime object
#
# @param {string} datetimeString
# @static
# @private
##
sub _convert_to_datetime {
	my $datetimeString = shift;
	my $fallbackDate   = shift;
	eval {
		my $conversion =
		  DateTime->from_epoch( epoch => str2time($datetimeString) );
		return $conversion;
	  }
	  or do {
		$logger->error(
"The string '$datetimeString' can't be converted to a DateTime object. Using $fallbackDate"
		);
		return $fallbackDate;
	  };
}

1;
