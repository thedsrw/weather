#!/usr/bin/perl -T

use strict;
use warnings;
use lib '.';
use Weather_osm;
use CGI ':standard';
use LWP::UserAgent;
use JSON;
use Data::Dumper;

print header('text/plain');

my $loc = param('location');
$loc = shift unless $loc;
die "invalid location\n" unless $loc;
my $debug = shift;
my ($zone,$lat,$long,$code,$place,$state,$tz) = geocode($loc);
print "$zone $lat $long\n" if $debug;

my $location = "$place, $state";
print "Forecast for $place, $state\n";

for my $a (alerts($loc))
 { print "4 ** $a\n"; }

my $i = 0;
my $ua = LWP::UserAgent->new;
$ua->default_header("Accept" => "application/geo+json");
my $r = $ua->get("https://api.weather.gov/zones/forecast/$zone/forecast");
print "URL: https://api.weather.gov/zones/forecast/$zone/forecast\n" if $debug;
print Dumper $r->content if $debug;
fail "couldn't get forecast" unless $r->is_success;
my $x = decode_json($r->content);
for (@{$x->{periods}})
{
  my $fcst = $_->{detailedForecast};
  $fcst =~ s/\n/ /g;
  print "\U$_->{name}\E: $fcst\n";
  last if (++$i > 3);
}
