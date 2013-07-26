#
# Tests for the HitAdjuster module
use Kruser::MLB::HitAdjuster;

use Test::More tests => 4;

my $hitAdjuster = new Kruser::MLB::HitAdjuster();

diamond_cutter_test();
left_field_line_test();
left_field_gap_test();
right_field_line_test();

sub diamond_cutter_test
{
	my $hit = {
		des     => 'single',
		x       => 125.1,
		y       => 99.40,
		batter  => 448674,
		pitcher => 424144,
		type    => 'H',
		team    => 'A',
		inning  => 9,
	};

	my $angle = $hitAdjuster->get_hit_angle($hit);
	my $expected = 90;
	ok( $angle == $expected, "expecting $expected, got $angle" );
}

sub left_field_line_test
{
	my $leftFieldHit = {
		des     => 'Double',
		x       => 43.17,
		y       => 99.40,
		batter  => 448674,
		pitcher => 424144,
		type    => 'H',
		team    => 'A',
		inning  => 9,
	};

	my $angle = $hitAdjuster->get_hit_angle($leftFieldHit);
	my $expected = 52.06;
	ok( $angle == $expected, "expecting $expected, got $angle" );
}

sub left_field_gap_test
{
	my $hit = {
		des     => 'Double',
		x       => 72.29,
		y       => 66.27,
		batter  => 543302,
		pitcher => 424144,
		type    => 'H',
		team    => 'A',
		inning  => 9,
	};

	my $angle = $hitAdjuster->get_hit_angle($hit);
	my $expected = 69.09;
	ok( $angle == $expected, "expecting $expected, got $angle" );
}

sub right_field_line_test
{
	my $hit = {
		des     => 'Double',
		x       => 172,
		y       => 158,
		batter  => 448674,
		pitcher => 424144,
		type    => 'H',
		team    => 'A',
		inning  => 9,
	};

	my $angle = $hitAdjuster->get_hit_angle($hit);
	my $expected = 135.25;
	ok( $angle == $expected, "expecting $expected, got $angle" );
}

