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



$resp = $ua->get("https://api.weather.gov/stations/\U$code\L/observations/current");
fail "can't pull weather" unless $resp->is_success;

my $x = decode_json($resp->content);
my $w = $x->{properties};
my $ot = DateTime::Format::ISO8601->parse_datetime($w->{timestamp});
$ot->set_time_zone('UTC');
$ot->set_time_zone($tz);

print "wx: $place, $state at ", $ot->format_cldr("HH:mm"), " L\n";

for (alerts($loc))
 { print "4** $_\n"; }
  
sub temperature($)
{
  my $t = shift;
  return undef  unless $t->{value};
  return sprintf ("%d F",($t->{unitCode} eq "unit:degC" ? ($t->{value} * 1.8) + 32 : $t->{value}));
}
sub speed ($)
{
  my $s = shift;
  return undef unless $s->{value};
  return sprintf ("%d MPH", ($s->{unitCode} eq "unit:m_s-1" ? ($s->{value} * 2.237) : $s->{value}));
}
sub pressure($)
{
  my $p = shift;
  return undef unless $p->{value};
  return sprintf ("%d mb",($p->{unitCode} eq "unit:Pa" ? $p->{value} / 100 : $p->{value}));
}
sub direction ($)
{
  my $deg = shift;
  if ($deg !~ /^\d+$/)
   { return "unknown"; }
  elsif ($deg >= 338 or $deg < 23)
   { return "north"; }
  elsif ($deg < 68)
   { return "northeast"; }
  elsif ($deg < 113)
   { return "east"; }
  elsif ($deg < 158)
   { return "southeast"; }
  elsif ($deg < 203)
   { return "south"; }
  elsif ($deg < 248)
   { return "southwest"; }
  elsif ($deg < 293)
   { return "west"; }
  else
   { return "northwest"; }
}

print " - Currently \L$w->{textDescription} and ", temperature($w->{temperature}), "\n";
print " - Feels like: ", temperature($w->{heatIndex}), "\n"
  if $w->{heatIndex}->{value};
print " - Feels like: ", temperature($w->{windChill}), "\n"
  if $w->{windChill}->{value};
printf(" - Humidity: %d%%\n",$w->{relativeHumidity}->{value}) 
  if $w->{relativeHumidity}->{value};
print " - Dewpoint: ", temperature($w->{dewpoint}), "\n"
  if $w->{dewpoint}->{value};
if ($w->{windDirection}->{value})
{
  print " - Wind: from the ", direction($w->{windDirection}->{value});
  print " at ", speed($w->{windSpeed});
  if ($w->{windGust}->{value})
   { print " gusting to ", speed($w->{windGust}); }
  print "\n";
}
print " - Pressure: ", pressure($w->{barometricPressure}), "\n"
  if $w->{barometricPressure}->{value};
