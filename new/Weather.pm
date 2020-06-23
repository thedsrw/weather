#!/usr/bin/perl -T

package Weather;
use Exporter;
@ISA = ('Exporter');
@EXPORT = qw/fail geocode alerts/;

use LWP::UserAgent;
use DBI;
use Data::Dumper;
use XML::Simple;
use JSON;
use DateTime;
use DateTime::TimeZone;
use DateTime::Format::ISO8601;


sub fail;
sub geocode;
sub alerts;


my $ua = new LWP::UserAgent;
push @{ $ua->requests_redirectable }, 'POST';
$ua->default_header("Accept" => "application/geo+json");

sub fail (@_)
{
  print "wx: " . (@_ ? "@_" : "invalid location") . "\n";
  die;
}

sub geocode ($)
{
  my $apikey = "AIzaSyCwuy6PAnS6DBz_8NcUKww3A641G-WAMg4";
  my $location = shift;



  my $gdbh = DBI->connect("dbi:SQLite:/afs/dsrw.org/public/databases/wx.db")
            or return; #die "Cannot connect: $DBI::errstr";
  my @res = $gdbh->selectrow_array("select zone,lat,long,code,name,state,timezone from geocode2 left join stations on geocode2.station_code == stations.code where location like '$location'");
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
      
      ($zone) = $stationdata->{properties}->{forecast} =~ m|/([A-Z]{2}Z(\d+))|;
    }
    else
    {
      my $gcresp = $ua->get("https://maps.googleapis.com/maps/api/geocode/xml?address=$location&key=$apikey");
      fail "bad geocode" unless $gcresp->is_success;
      my $result = XMLin($gcresp->content, ForceArray => 1);
      $lat = sprintf ("%.4f",$result->{result}->[0]->{geometry}->[0]->{location}->[0]->{lat}->[0]);
      $lng = sprintf ("%.4f",$result->{result}->[0]->{geometry}->[0]->{location}->[0]->{lng}->[0]);
      fail "invalid location (could not geocode)" unless $lat != 0 and $lng != 0;

      $gcresp = $ua->get("https://api.weather.gov/points/$lat,$lng");
      fail "bad points lookup" unless $gcresp->is_success;
      my $points = decode_json($gcresp->content);
      ($zone) = $points->{properties}->{forecastZone} =~ m|/([A-Z]{2}Z(\d+))|;

      $gcresp = $ua->get("https://api.weather.gov/points/$lat,$lng/stations");
      fail "couldn't pull observation station data" unless $gcresp->is_success;
      my $stationlist  = decode_json($gcresp->content);
      $gcresp = $ua->get($stationlist->{features}->[0]->{id});
      fail "can't pull station data" unless $gcresp->is_success;
      $stationdata = decode_json($gcresp->content);
    }
    my ($state) = $stationdata->{properties}->{forecast} =~ m|/([A-Z]{2})Z\d+$|;


    my @return = ($zone,$lat,$lng,
	      $stationdata->{properties}->{stationIdentifier},
	      $stationdata->{properties}->{name},
	      $state,$stationdata->{properties}->{timeZone});
    $gdbh->do("insert into geocode
	      (location,zone,lat,long,station,station_name,state,timezone)
	      values (?,?,?,?,?,?,?,?)",{},$location,@return);
    return @return;
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
  return @alerts;
}


    



1;
