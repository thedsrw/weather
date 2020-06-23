#!/usr/bin/perl -T

use strict;
use warnings;
use lib '.';
use Weather_osm;
use CGI ':standard';
use LWP::UserAgent;
use JSON;
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::ISO8601;

print header('text/plain');

my $ua = new LWP::UserAgent;
my $resp;
push @{ $ua->requests_redirectable }, 'POST';
$ua->default_header("Accept" => "application/geo+json");

my $loc = param("location");
$loc = shift unless $loc;
my $debug = shift;
fail if ($loc eq "");
my ($zone,$lat,$long,$code,$place,$state,$tz) = geocode($loc);
#print join (" // ",geocode($loc)), "\nhttps://api.weather.gov/stations/\U$code\L/observations/current\n" if $debug;


my $url = "https://api.weather.gov/stations/\U$code\L/observations/latest";
print "$url\n" if $debug;

$resp = $ua->get($url);
fail "can't pull weather" unless $resp->is_success;

my $x = decode_json($resp->content);
my $w = $x->{properties};

my $ot = DateTime::Format::ISO8601->parse_datetime($w->{timestamp});
$ot->set_time_zone('UTC');
$ot->set_time_zone($tz);

print "wx: $place, $state at ", $ot->format_cldr("HH:mm"), " L\n";

for (alerts($loc))
 { print "4** $_\n"; }
  
sub temperature_noaa($)
{
  my $t = shift;
  my ($c, $f);
  if ($t->{unitCode} eq "unit:degC")
  {
    $c = $t->{value};
    $f = ($t->{value} * 1.8) + 32;
  }
  elsif ($t->{unitCode} eq "unit:degF")
  {
    $c = ($t->{value} - 32) * 5 / 9;
    $f = $t->{value};
  }
  else
   { return undef; }
  return sprintf ("%d F (%d C)",$f,$c);
}
sub speed_noaa ($)
{
  my $s = shift;
  return undef unless $s->{value};
  return sprintf ("%d MPH", ($s->{unitCode} eq "unit:m_s-1" ? ($s->{value} * 2.237) : $s->{value}));
}
sub pressure_noaa ($)
{
  my $p = shift;
  return undef unless $p->{value};
  return sprintf ("%d mb",($p->{unitCode} eq "unit:Pa" ? $p->{value} / 100 : $p->{value}));
}

print " - Currently \L$w->{textDescription} and ", temperature_noaa($w->{temperature}), "\n";
print " - Feels like: ", temperature_noaa($w->{heatIndex}), "\n"
  if $w->{heatIndex}->{value};
print " - Feels like: ", temperature_noaa($w->{windChill}), "\n"
  if $w->{windChill}->{value};
printf(" - Humidity: %d%%\n",$w->{relativeHumidity}->{value}) 
  if $w->{relativeHumidity}->{value};
print " - Dewpoint: ", temperature_noaa($w->{dewpoint}), "\n"
  if $w->{dewpoint}->{value};
if ($w->{windDirection}->{value})
{
  print " - Wind: from the ", direction($w->{windDirection}->{value});
  print " at ", speed_noaa($w->{windSpeed});
  if ($w->{windGust}->{value})
   { print " gusting to ", speed_noaa($w->{windGust}); }
  print "\n";
}
print " - Pressure: ", pressure_noaa($w->{barometricPressure}), "\n"
  if $w->{barometricPressure}->{value};
