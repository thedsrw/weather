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
use Data::Dumper;
use Math::BigFloat;


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
print join (" // ",geocode($loc)), "\nhttps://api.weather.gov/stations/\U$code\L/observations/current\n" if $debug;


my $w = get_mesonet_data($code, $state);
die "can't get data!" unless $w;
#print Dumper $w;
my @ot;
if ($w->{local_valid})
 { @ot = split /\s+/, $w->{local_valid}; }
else 
 { @ot = ("unknown", "unknown" ); }


print "wx: $place, $state at ", $ot[1], " L\n";
for my $a (alerts($loc))
 { print "4 ** $a\n"; }

sub conditions ($$)
{
  my $pwx = shift;
  my $cover = shift;
  my $descr = {MI => "Shallow",
               PR => "Partial",
               BC => "Patches",
               DR => "Low Drifting",
               BL => "Blowing",
               SH => "Shower(s)",
               TS => "Thunderstorm",
               FZ => "Freezing"};
  my $pcp = {  DZ => "Drizzle",
               RA => "Rain",
               SN => "Snow",
               SG => "Snow Grains",
               IC => "Ice Crystals",
               PL => "Ice Pellets",
               GR => "Hail",
               GS => "Small Hail and/or Snow Pellets",
               UP => "Unknown Precipitation"};
  my $obsc = { BR => "Mist",
               FG => "Fog",
               FU => "Smoke",
               VA => "Volcanic Ash",
               DU => "Widespread Dust",
               SA => "Sand",
               HZ => "Haze",
               PY => "Spray"};
  my $after = ["BC", "SH", "TS"];

  if (scalar(@$pwx))
  {
    my $out = "";
    for my $wx (@$pwx)
    {
      my $i;
      my $d;
      my $p;
      my $o;
      my $extra;
      if ($wx =~ /^-/)
      {
        $i = "Light";
	$wx =~ s/^.//;
      }
      elsif ($wx =~ /^\+/)
      {
	$i = "Heavy";
	$wx =~ s/^.//;
      }
      my $unpack = "A2" x (length($wx)/2);
      for my $code (unpack $unpack, $wx)
      {
	if ($descr->{$code})
	 { $d = $code; }
	elsif ($pcp->{$code})
	 { $p = $code; }
	elsif ($obsc->{$code})
	 { $o = $code; }
	else
	 { $extra .= $code; }


      }
      if ($i)
       { $out .= "$i "; }
      if ($d and !grep( /^$d$/,@$after))
       { $out .= $descr->{$d}. " "; }
      if ($p)
       { $out .= $pcp->{$p}. " "; }
      if ($d and grep( /^$d$/,@$after))
       { $out .= $descr->{$d}. " "; }
      if ($o)
       { $out .= $obsc->{$o}. " "; }
      if ($extra)
       { $out .= "($extra)"; }
      $out =~ s/\s+$/, /; 
    }
    $out =~ s/,\s+$//;
    return "\L$out";
  }
  elsif ($cover)
  {
    if ($cover eq "CLR")
     { return "clear skies"; }
    elsif ($cover eq "FEW")
     { return "a few clouds"; }
    elsif ($cover eq "SCT")
     { return "scattered clouds"; }
    elsif ($cover eq "BKN")
     { return "a broken sky"; }
    elsif ($cover eq "OVC")
     { return "overcast"; }
  }
  return "WEATHER HAPPEN"
}
print Dumper $w if $debug;
my $temp = $w->{'airtemp[F]'};
print "TEMP: $temp\n" if $debug;
print "temp(): " . temperature($temp) . "\n" if $debug;
my $windspeed = $w->{'windspeed[kt]'} * 1.15 if $w->{'windspeed[kt]'};
my $humidity = humidity($temp,$w->{'dewpointtemp[F]'});
print " - Currently ", conditions($w->{presentwx}, $w->{'skycover[code]'}->[0]), " and ", temperature($temp), "\n";
my $wchill = wind_chill($temp, $windspeed);
my $hindex = heat_index($temp, $humidity);
if ($wchill < $temp - 1)
 { print " - Feels like: ", temperature($wchill), "\n" }
elsif ($hindex > $temp + 1)
 { print " - Feels like: ", temperature($hindex), "\n" }
printf(" - Humidity: %d%%\n",$humidity) 
  if $humidity;
print " - Dewpoint: ", temperature($w->{'dewpointtemp[F]'}), "\n";
if ($w->{'winddirection[deg]'})
{
  print " - Wind: from the ", direction($w->{'winddirection[deg]'});
  print " at ", speed($windspeed);
  if ($w->{raw} =~ m/\d+G(\d+)KT\b/)
   { print " gusting to ", speed($1 * 1.15); }
  print "\n";
}
print " - Pressure: ", pressure($w->{'mslp[mb]'}), "\n"
  if $w->{'mslp[mb]'};

