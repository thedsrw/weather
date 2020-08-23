#!/usr/bin/perl -T

package Weather_osm;
use Exporter;
@ISA = ('Exporter');
@EXPORT = qw/fail geocode alerts f_to_c c_to_f humidity
             dewpoint heat_index wind_chill direction
             pressure speed temperature
             get_mesonet_data check_mesonet_station get_zone/;

use LWP::UserAgent;
use DBI;
use Data::Dumper;
use JSON;
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::ISO8601;
use List::MoreUtils qw/ uniq /;


sub fail;
sub geocode;
sub get_mesonet_data;
sub check_mesonet_station;
sub get_zone;
sub alerts;
sub f_to_c;
sub c_to_f;
sub humidity;
sub dew_point;
sub heat_index;
sub wind_chill;
sub direction;
sub pressure;
sub speed;
sub temperature;
sub esubx;


my $ua = new LWP::UserAgent;
push @{ $ua->requests_redirectable }, 'POST';
$ua->default_header("Accept" => "application/geo+json");

sub fail (@_)
{
  print "wx: " . (@_ ? "@_" : "invalid location") . "\n";
  die;
}

sub f_to_c($)
{
  my $f = shift;
  return ($f - 32) * 5 / 9;
}
 
sub c_to_f ($)
{
  my $c = shift;
  return 32 + ($c * 1.8);
}

# format a digit as F temp
sub temperature($)
{
  my $t = shift;
  return sprintf ("%d F (%d C)",$t,f_to_c($t));
}

# format a digit as MPH speed
sub speed ($)
{
  my $s = shift;
  return undef unless $s;
  return sprintf ("%d MPH", $s);
}

# format a digit as millibars of pressure
sub pressure($)
{
  my $p = shift;
  return undef unless $p;
  return sprintf ("%d mb",$p);
}

# print a digit of degrees as a direction
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

# given temp in F and windspeed in MPH, return windchill in F
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

# given temp in F and humidity in %, return heat index in F
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

# given temp in F, humidity in % and pressure in mb, return dew_point in f
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

# magic for humidity().
sub esubx ($)
{
  my $x = shift;
  return 6.112 * exp((17.67 * $x) / ($x + 243.5));
}

# given temp in F and dewpoint in F, return humidity in pct
sub humidity ($$)
{
  # https://www.weather.gov/epz/wxcalc_dewpoint
  # https://www.weather.gov/media/epz/wxcalc/rhWetBulbFromTd.pdf
  my $t = f_to_c(shift);
  my $dwp = f_to_c(shift);
  return 100 * esubx($dwp)/esubx($t);
}

sub check_mesonet_station($$)
{
  my $station = shift;
  $station_og = $station;
  my $state = shift;
  my $dbh = DBI->connect("dbi:SQLite:/afs/dsrw.org/public/databases/wx.db");
  my $row = $dbh->selectrow_hashref("select * from stations where station=?",{},$station_og);
  if ($row and $row->{mesonet})
  {
    print Dumper $row;
    $dbh->disconnect;
    return $row->{mesonet};
  }
  else
  {
    $station =~ s/^K?//;
    $station = "\U$station";
    $state = "\U$state";
    my $url = sprintf "http://mesonet.agron.iastate.edu/json/current.py?station=%s&network=%s_ASOS", $station, $state;
    my $ua = new LWP::UserAgent;
    my $station_ok = -1;
    my $resp = $ua->get($url);
    if ($resp->is_success)
    {
      my $x = decode_json($resp->content);
      if ($x->{last_ob})
       { $station_ok = 1; }
    }
    $dbh->do("update stations set mesonet=? where station=?",{},$station_ok,$station_og);
    $dbh->disconnect;
    return $station_ok;
  }  
}

  
sub get_mesonet_data($$)
{
  my $station = shift;
  my $state = shift;
  my $ua = new LWP::UserAgent;
  $station =~ s/^K?//;
  $station = "\U$station";
  $state = "\U$state";
  my $url = sprintf "http://mesonet.agron.iastate.edu/json/current.py?station=%s&network=%s_ASOS", $station, $state;
  my $resp = $ua->get($url);
  if ($resp->is_success)
  {   
    my $wx_data = decode_json($resp->content);
    if ($wx_data->{last_ob})
     { return $wx_data->{last_ob}; }
  }
  return 0;
}

  

sub get_station_local($$)
{
  my $lat = shift;
  my $long = shift;
  my $dbh = DBI->connect("dbi:SQLite:/afs/dsrw.org/public/databases/wx.db");
  my $i=1;
  my @res;
  my $found = 0;
  my @discards;
  do {
    my $q = "select * from stations where (mesonet is null or mesonet == 1) and lat < ? and lat > ? and long < ? and long > ?";
    if (@discards)
    {
      $q .= " and station not in (" . ("?," x scalar @discards);
      $q =~ s/,$/)/;
    }
    @res = $dbh->selectrow_array($q,
           {},$lat + ($i*.01), $lat - ($i*.01), $long + ($i*.01), $long - ($i*.01),@discards);
    if ($res[0])
    {
      if ($res[6] == 1 or check_mesonet_station($res[0],$res[2]) == 1)
       { $found++; }
      else 
       { push @discards,  $res[0]; }
    }
    $i++;
  }
  while (!$found and $i < 100);
  $dbh->disconnect;

  if ($found)
   { return (@res[0..2]); }
  fail("can't find a station nearby\n");
}

sub get_zone ($$)
{
  my $lat = shift;
  my $lng = shift;
  my $resp = $ua->get("https://api.weather.gov/points/$lat,$lng");
  fail ("can't decode point\n") unless $resp->is_success;
  my $data = decode_json($resp->content);
  my ($zone) = $data->{properties}->{forecastZone} =~ m|/([A-Z]{2}Z\d+)|;
  die "can't get a valid zone" unless $zone;
  return ($zone, $data->{properties}->{timeZone});
}

sub get_station ($$)
{
  my $lat = shift;
  my $lng = shift;
  my $resp = $ua->get("https://api.weather.gov/points/$lat,$lng");
  fail ("can't decode point\n") unless $resp->is_success;
  my $data = decode_json($resp->content);
  $resp = $ua->get($data->{properties}->{forecastZone} . "/stations");
  fail ("can't get stations\n") unless $resp->is_success;
  my $data = decode_json($resp->content);
  for my $station (@{$data->{features}})
  {
    $resp = $ua->get($station->{id});
    ($station_name) = $station->{id} =~ /(...)$/;
    fail ("can't get station " . $station->{id}) unless $resp->is_success;
    $stationdata = decode_json($resp->content);
    my ($state) = $stationdata->{properties}->{forecast} =~ m|/([A-Z]{2})Z\d+|;

    if (get_mesonet_data($stationdata->{properties}->{stationIdentifier}, $state))
    {
      my @city_parts = split /,/, $stationdata->{properties}->{name};
      return ($stationdata->{properties}->{stationIdentifier},
	      $city_parts[0],
	      $state);
    }
  }
  fail("cannot match a station with data");
}



sub geocode ($)
{
  my $location = shift;

  my $gdbh = DBI->connect("dbi:SQLite:/afs/dsrw.org/public/databases/wx.db")
            or print "wx: can't cache\n"; #return; #die "Cannot connect: $DBI::errstr";
  my @res = $gdbh->selectrow_array("select zone,lat,long,station,station_name,state,timezone from geocode where location like '$location'");
  if (@res)
   { return @res; }
  else
  {
  # look up, cache location
    my ($gcresp,$zone,$stationdata,$lat,$lng);
    if ($location =~ m/^([a-z0-9]{3,4})$/i)
    {
      my $station = length $1 == 3 ? "K$1" : $1;
      my $gcresp = $ua->get("https://api.weather.gov/stations/\U$station");
      fail "not a valid station" unless $gcresp->is_success;
      $stationdata = decode_json($gcresp->content);
      print Dumper $stationdata if $debug;
      ($lng,$lat) = @{$stationdata->{geometry}->{coordinates}};
      $lat = sprintf("%.4f", $lat);
      $lng = sprintf("%.4f", $lng);
    }
    else
    {
      # my $gcresp = $ua->get("https://nominatim.openstreetmap.org/search?format=json&q=$location");
      # fail "bad geocode" unless $gcresp->is_success;
      # my $result = decode_json($gcresp->content);
      # $lat = sprintf ("%.4f",$result->[0]->{lat});
      # $lng = sprintf ("%.4f",$result->[0]->{lon});
      # fail "invalid location (could not geocode)" unless $lat != 0 and $lng != 0;

      my $mapquest_key = 'ZZlkNJlXCoBU4gZdnla5oikZKYxAYcqK';
      my $gcresp = $ua->get("https://www.mapquestapi.com/geocoding/v1/address?key=$mapquest_key&informat=kvp&outFormat=json&location=$location");
      fail "bad geocode" unless $gcresp->is_success;
      my $result = decode_json($gcresp->content);
      $lat = sprintf ("%.4f",$result->{results}->[0]->{locations}->[0]->{latLng}->{lat});
      $lng = sprintf ("%.4f",$result->{results}->[0]->{locations}->[0]->{latLng}->{lng});
      fail "invalid location (could not geocode)" unless $lat != 0 and $lng != 0;
    }

    my @station_data = get_station_local($lat,$lng);
    my @zone_data = get_zone($lat,$lng);

    $gdbh->do("insert into geocode
        (location,lat,long,station,station_name,state,zone, timezone)
        values (?,?,?,?,?,?,?,?)",{},$location, $lat, $lng, @station_data, @zone_data);
    # my ($zone,$lat,$long,$code,$place,$state,$tz) = geocode($loc);
    $gdbh->disconnect;
    return ($zone_data[0], $lat, $lng, @station_data, $zone_data[1]);
  } 
}

sub alerts($)
{
  my ($zone,$lat,$long,$code,$location,$state,$tz) = geocode(shift);
  my @alerts;
  my $resp = $ua->get("https://api.weather.gov/alerts/active?point=$lat,$long");
  fail "couldn't get alerts" unless $resp->is_success;
  my $x = decode_json($resp->content);
  my $now = DateTime->now(time_zone => $tz);

  for (@{$x->{features}})
  {
    my $string = $_->{properties}->{event};
    if ($_->{properties}->{ends})
    {
      my $et = DateTime::Format::ISO8601->parse_datetime($_->{properties}->{ends});
      $et->set_time_zone('UTC');
      $et->set_time_zone($tz);
      $string .= " until ";
      if ($now->ymd() eq $et->ymd())
       { $string .= $et->format_cldr("HH:mm"); }
      else
       { $string .= $et->format_cldr("MMM d HH:mm") }
    }
    push @alerts,$string;
  }
  return uniq @alerts;
}

1;
