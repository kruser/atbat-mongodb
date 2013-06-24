#!/usr/bin/perl
#
# ETL script for taking MLB AtBat data and moving it into a set of different MongoDB collections
#
# @author: kruser
#
use strict;
use Kruser::MLB::AtBat;
use Kruser::MLB::Storage;
use Config::Properties;
use Log::Log4perl;
use Data::Dumper;
use File::Basename;
use Getopt::Long;

my $properties;
my $year;
my $month;
my $day;
my $path = dirname(__FILE__);    # where the script lives
Log::Log4perl->init( $path . '/log4perl.conf' );
my $logger = Log::Log4perl->get_logger("atbatETL");

##
# Main
##
load_options();
load_properties();
my $storage = Kruser::MLB::Storage->new(
	dbName => $properties->getProperty('db.name'),
	dbHost => $properties->getProperty('db.host'),
);
my $atbat = Kruser::MLB::AtBat->new(
	storage => $storage,
	apibase => $properties->getProperty('apibase'),
	year    => $year,
);

if ( $year && $month && $day )
{
	$atbat->retrieve_day( $year, $month, $day );
}
elsif ( $year && $month )
{
	$atbat->retrieve_month( $year, $month );
}
elsif ($year)
{
	$atbat->retrieve_year($year);
}
else
{
	$atbat->retrieve_since_last();
}

##
# loads the properties from the script configuration file
##
sub load_properties()
{
	my $configFile = $path . '/atbatETL.properties';
	if ( !-e $configFile )
	{
		$logger->error("The config file '$configFile' does not exist");
	}

	open PROPS, "< $configFile"
	  or die "Unable to open configuration file $configFile";
	$properties = new Config::Properties();
	$properties->load(*PROPS);
}

##
# load all of the startup options
##
sub load_options()
{
	my $help;
	GetOptions(
		"h"       => \$help,
		"help"    => \$help,
		"year=i"  => \$year,
		"month=i" => \$month,
		"day=i"   => \$day,
	);

	if ($help)
	{
		usage();
	}
}

##
# Prints out some help
##
sub usage
{

	# not sure if we need this yet
}

