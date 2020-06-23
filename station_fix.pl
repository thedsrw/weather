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
my $stmt = $dbh->prepare("select station, station_name from stations where station_name like '%,%' order by station") or die $dbh->errstr;
my $update = $dbh->prepare("update stations set station_name=? where station=?");
$stmt->execute;
while (my $row = $stmt->fetchrow_hashref)
{
  print $row->{station} . " : " . $row->{station_name};
  my @sn = split(/,\s*/,$row->{station_name});

  $update->execute($sn[0], $row->{station}) or die $update->errstr;
  print " -> $sn[0]\n";
}
