#!/usr/bin/perl

use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use DBI;
use Data::Dumper;

my $base_url = "https://dev.virtualearth.net/REST/v1/TimeZone/%.4f,%.4f?key=AoeBJeVqPEofLsPhnctocT-WKxcfK-gj-v6Vxx3QSDdtJwHimCiYRhji-XKpXi_w";

my $ua = new LWP::UserAgent;

my $dbh = DBI->connect("dbi:SQLite:/afs/dsrw.org/public/databases/wx.db");
my $stmt = $dbh->prepare("select * from stations where timezone is null  order by station") or die $dbh->errstr;
my $update = $dbh->prepare("update stations set timezone=? where station=?");
$stmt->execute;
while (my $row = $stmt->fetchrow_hashref)
{
  print $row->{station};
  my $resp = $ua->get(sprintf $base_url,$row->{lat},$row->{long});
  if ($resp->is_success)
  {
    my $j = decode_json($resp->content);
    
    my $tz = $j->{resourceSets}->[0]->{resources}->[0]->{timeZone}->{ianaTimeZoneId};
    if ($tz)
    {
      print " -> $tz";
      $update->execute($tz, $row->{station}) or die $update->errstr;
    }
    else
    {
      #print Dumper $j;
    }
    print "\n";
    sleep 1;
  }
}
