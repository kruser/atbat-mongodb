#!/usr/bin/perl
#
# ETL script for taking MLB AtBat data and moving it into a set of different MongoDB collections
#
# @author: kruser
#
use strict;
use Kruser::MLB::AtBat;
use Kruser::MLB::Storage::Mongo;
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
my $storage = Kruser::MLB::Storage::Mongo->new(
	dbName => $properties->getProperty('db.name'),
	dbHost => $properties->getProperty('db.host'),
);
my $atbat = Kruser::MLB::AtBat->new(
	storage => $storage,
	apibase => $properties->getProperty('apibase'),
	year    => $year,
	month   => $month,
	day     => $day,
);
$atbat->initiate_sync();

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
	print "With no args, this program will sync from the last date the program was run\n";
	print "When you initially run it, you should sync an entire month or year to seed your database.\n\n";
	print "Optional args\n";
	print " --year=YYYY (the year to sync with)\n";
	print " --month=MM (the month to sync with, must be used with --year)\n";
	print " --day=DD (the day to sync with, must be used with --year and --month)\n";
	print "\nFor example, this will sync June 2013\n";
	print "\tperl atbatETL.pl --year=2013 --month=06\n";
	exit;
}

