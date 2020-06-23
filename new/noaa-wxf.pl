#!/usr/bin/perl -T

use strict;
use warnings;
use lib '.';
use Weather;
use CGI ':standard';
use LWP::UserAgent;
use JSON;

print header('text/plain');

my $loc = param('location');
$loc = shift unless $loc;
die "invalid location\n" unless $loc;
my $debug = shift;
my ($zone,$lat,$long,$code,$place,$state,$tz) = geocode($loc);

my $location = "$place, $state";
print "Forecast for $place, $state\n";

for (alerts($loc))
 { print "4** $_\n"; }

my $i = 0;
my $ua = LWP::UserAgent->new;
$ua->default_header("Accept" => "application/geo+json");
my $r = $ua->get("https://api.weather.gov/points/$lat,$long/forecast");
fail "couldn't get forecast" unless $r->is_success;
my $x = decode_json($r->content);
for (@{$x->{properties}->{periods}})
{
  print "\U$_->{name}\E: $_->{detailedForecast}\n";
  last if (++$i > 3);
}
