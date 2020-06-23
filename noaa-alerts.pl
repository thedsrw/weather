#!/usr/bin/perl -T

use strict;
use warnings;
use lib '.';
use Weather;
use CGI ':standard';
use LWP::UserAgent;
use JSON;
use DateTime;
use DateTime::TimeZone;

print header('text/plain');

my $ua = new LWP::UserAgent;
my $resp;
push @{ $ua->requests_redirectable }, 'POST';
$ua->default_header("Accept" => "application/geo+json");

my $loc = param("location");
$loc = shift unless $loc;
#my $debug = shift;
fail if ($loc eq "");
my ($zone,$lat,$long,$code,$place,$state,$tz) = geocode($loc);
#print join (" // ",geocode($loc)), "\nhttps://api.weather.gov/stations/\U$code\L/observations/current\n" if $debug;

for (alerts($loc))
 { print "4** $_\n"; }
  
