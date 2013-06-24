#!/usr/bin/perl
#
# ETL script for taking MLB AtBat data and moving it into a set of different MongoDB collections
#
# @author: kruser
#
use strict;
use Kruser::MLB::AtBat;
use Config::Properties;
use Log::Log4perl;
use Data::Dumper;
use File::Basename;
use Getopt::Long;

my $properties;
my $path = dirname(__FILE__);    # where the script lives
Log::Log4perl->init( $path . '/log4perl.conf' );
my $logger = Log::Log4perl->get_logger("atbatETL");

##
# Main
##
load_options();
load_properties();
$logger->info("Starting MLB ETL");
print Dumper($properties);

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
		"h"    => \$help,
		"help" => \$help,
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

}

