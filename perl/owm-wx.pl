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
use Data::Dumper;
use Math::BigFloat;


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



$resp = $ua->get("https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$long&units=imperial&appid=740f1a126e1ea0ef4f2b54afacfbd2cf");
fail "can't pull weather" unless $resp->is_success;

#print $resp->content;
my $w = decode_json($resp->content);
#print Dumper $w;
my $ot = DateTime->from_epoch( epoch => $w->{dt});
#my $ot = DateTime::Format::ISO8601->parse_datetime($w->{dt});
$ot->set_time_zone('UTC');
$ot->set_time_zone($tz);

print "wx: $place, $state ($w->{name}) at ", $ot->format_cldr("HH:mm"), " L\n";

sub temperature($)
{
  my $t = shift;
  return undef unless $t;
  return sprintf ("%d F (%d C)",$t,f_to_c($t));
}

sub speed ($)
{
  my $s = shift;
  return undef unless $s;
  return sprintf ("%d MPH", $s);
}

sub pressure($)
{
  my $p = shift;
  return undef unless $p;
  return sprintf ("%d mb",$p);
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

sub wind_chill ($$)
{
  # https://www.weather.gov/epz/wxcalc_windchill
  # https://www.weather.gov/media/epz/wxcalc/windChill.pdf
  my $temp = shift;
  my $windspeed = shift;
  if ($temp > 50 or $windspeed < 3)
   { return $temp; }
  return 35.74 + (0.6215 * $temp) - (35.75 * $windspeed ** 0.16) + (0.4275 * $temp * $windspeed ** 0.16)
}

sub heat_index ($$)
{
  # https://www.weather.gov/epz/wxcalc_heatindex
  # https://www.weather.gov/media/epz/wxcalc/heatIndex.pdf
  my $t = shift;
  my $h = shift;
  if ($t < 80)
   { return $t; }
  return -42.379 + (2.04901523 * $t) + (10.14333127 * $h)
         - (0.22475541 * $t * $h) - (6.83783 * 10**-3 * $t**2)
	 - (5.481717 * 10**-2 * $h**2) + (1.22874 * 10**-3 * $t**2 * $h)
	 + (8.5282 * 10**-4 * $t * $h**2) - (1.99 * 10**-6 * $t**2 * $h**2)
}

sub dew_point ($$$)
{
  # https://www.weather.gov/epz/wxcalc_rh
  # https://www.weather.gov/media/epz/wxcalc/wetBulbTdFromRh.pdf
  my $c = f_to_c(shift);
  my $h = shift;
  my $p = shift;
  my $es = 6.112 * exp(17.67 * $c / ($c + 243.5));
  my $e = $es * ($h/100);
  return c_to_f((243.5 * log($e/6.112))/(17.67 - log($e/6.112)))
}


my $temp = $w->{main}->{temp};
print " - Currently \L$w->{weather}->[0]->{description} and ", temperature($temp), "\n";
my $wchill = wind_chill($temp, $w->{wind}->{speed});
my $hindex = heat_index($temp, $w->{main}->{humidity});
if ($wchill < $temp - 1)
 { print " - Feels like: ", temperature($wchill), "\n" }
elsif ($hindex > $temp + 1)
 { print " - Feels like: ", temperature($hindex), "\n" }
printf(" - Humidity: %d%%\n",$w->{main}->{humidity}) 
  if $w->{main}->{humidity};
print " - Dewpoint: ", temperature(dew_point($temp,$w->{main}->{humidity},$w->{main}->{pressure})), "\n";
if ($w->{wind}->{deg})
{
  print " - Wind: from the ", direction($w->{wind}->{deg});
  print " at ", speed($w->{wind}->{speed});
#  if ($w->{windGust}->{value})
#   { print " gusting to ", speed($w->{windGust}); }
  print "\n";
}
print " - Pressure: ", pressure($w->{main}->{pressure}), "\n"
  if $w->{main}->{pressure};

