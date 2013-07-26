package Kruser::MLB::HitAdjuster;

##
# A module that provides methods for converting
# the MLB X/Y hit coordinates into angles and distances
#
# @author kruser
##
use strict;

my $PI = atan2 0, -1;

##
# Construct an instance
##
sub new
{
	my ( $proto, %params ) = @_;
	my $package = ref($proto) || $proto;

	my $this = {
		homeX => 125.1,
		homeY => 204.5,
	};

	foreach my $key ( keys %params )
	{
		$this->{$key} = $params{$key};
	}

	bless( $this, $package );
	return $this;
}

##
# Given a hip instance, returns an angle of the hit from home plate, assuming home plate is at the center of a circle
# and zero degrees is due left of home plate.
#
# 45 degrees = left field foul line
# 90 degrees = up the middle
# 135 degrees = right field foul line
#
# @param hit - an instance of the hip - see here for an example: http://gd2.mlb.com/components/game/mlb/year_2013/month_07/day_25/gid_2013_07_25_minmlb_seamlb_1/inning/inning_hit.xml
# @returns angle
##
sub get_hit_angle
{
	my $this = shift;
	my $hit  = shift;

	my $x = $hit->{x};
	my $y = $hit->{y};
	
	my $deltaX = $this->{homeX} - $x;
	my $deltaY = $this->{homeY} - $y;

	my $degrees = atan2($deltaY, $deltaX) * 180 / $PI;
	my $rounded = sprintf("%.2f", $degrees);
	return $rounded;
}

##
# Given a hip instance, returns an estimation of the distance between home plate and the x,y coordinates of the hit.
#
# This method currently doesn't take the ballpark into consideration. It assumes all park images are nearly to scale.
#
# @param hit - an instance of the hip - see here for an example: http://gd2.mlb.com/components/game/mlb/year_2013/month_07/day_25/gid_2013_07_25_minmlb_seamlb_1/inning/inning_hit.xml
# @returns angle
##
sub estimate_hit_distance
{
	my $this = shift;
	my $hit  = shift;

	my $x = $hit->{x};
	my $y = $hit->{y};
	
	my $deltaX = $this->{homeX} - $x;
	my $deltaY = $this->{homeY} - $y;

	my $degrees = atan2($deltaY, $deltaX) * 180 / $PI;
	my $rounded = sprintf("%.2f", $degrees);
	return $rounded;
}

1;
