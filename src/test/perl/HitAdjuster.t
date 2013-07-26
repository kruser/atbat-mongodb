#
# Tests for the HitAdjuster module
use Kruser::MLB::HitAdjuster;

use Test::More tests => 8;

my $hitAdjuster = new Kruser::MLB::HitAdjuster();

diamond_cutter_test();
left_field_line_test();
left_field_gap_test();
right_field_line_test();
distance_test();

sub diamond_cutter_test
{
	my $hit = {
		des => 'single',
		x   => 125.1,
		y   => 99.40,
	};

	my $angle    = $hitAdjuster->get_hit_angle($hit);
	my $expected = 90;
	ok( $angle == $expected, "expecting $expected, got $angle" );
}

sub left_field_line_test
{
	my $leftFieldHit = {
		des => 'Double',
		x   => 43.17,
		y   => 99.40,
	};

	my $angle    = $hitAdjuster->get_hit_angle($leftFieldHit);
	my $expected = 52.06;
	ok( $angle == $expected, "expecting $expected, got $angle" );
}

sub left_field_gap_test
{
	my $hit = {
		des => 'Double',
		x   => 72.29,
		y   => 66.27,
	};

	my $angle    = $hitAdjuster->get_hit_angle($hit);
	my $expected = 69.09;
	ok( $angle == $expected, "expecting $expected, got $angle" );
}

sub right_field_line_test
{
	my $hit = {
		des => 'Double',
		x   => 172,
		y   => 158,
	};

	my $angle    = $hitAdjuster->get_hit_angle($hit);
	my $expected = 135.25;
	ok( $angle == $expected, "expecting $expected, got $angle" );
}

sub distance_test
{
	my $distance = $hitAdjuster->estimate_hit_distance({ x => 136, y => 32, });
	my $expected = 400;
	ok( $distance == $expected, "expecting $expected, got $distance" );
	
	$distance = $hitAdjuster->estimate_hit_distance({ x => 225.50, y => 102.50, });
	$expected = 331.21;
	ok( $distance == $expected, "expecting $expected, got $distance" );
	
	$distance = $hitAdjuster->estimate_hit_distance({ x => 27.30, y => 104.50, });
	$expected = 323.70;
	ok( $distance == $expected, "expecting $expected, got $distance" );
	
	$distance = $hitAdjuster->estimate_hit_distance({ x => 66, y => 62, });
	$expected = 357.01;
	ok( $distance == $expected, "expecting $expected, got $distance" );
}

