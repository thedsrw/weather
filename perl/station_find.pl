#!/usr/bin/perl

use strict;
use warnings;
use lib '.';
use Weather_osm;
use DBI;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use Math::Trig;

my $ua = new LWP::UserAgent;
my $location = shift;
my $gcresp = $ua->get("https://nominatim.openstreetmap.org/search?format=json&q=$location");
die "bad geocode" unless $gcresp->is_success;
my $result = decode_json($gcresp->content);
die "can't geocode!\n" unless $result->[0]->{lat};
my $lat = sprintf ("%.4f",$result->[0]->{lat});
my $long = sprintf ("%.4f",$result->[0]->{lon});
print "$lat, $long\n";

#print get_zone($lat, $long) . "\n";

my $dbh = DBI->connect("dbi:SQLite:/afs/dsrw.org/public/databases/wx.db");
my $i=1;
my @res;
my $found = 0;
my @seen;
my @keeps;
while (scalar @keeps < 4)
{
  my $q =  "select * from stations where (mesonet is null or mesonet == 1) and lat < ? and lat > ? and long < ? and long > ?";
  if (@seen)
  {
    $q .= " and station not in (" . ("?," x scalar @seen);
    $q =~ s/,$/)/;
  }
  print "$q\n";
  my $stmt = $dbh->prepare($q);
                     
  $stmt->execute($lat + ($i*.25), $lat - ($i*.25), $long + ($i*.25), $long - ($i*.25),@seen);
  while (my $row = $stmt->fetchrow_hashref())
  {
    print Dumper $row;
    if (($row->{mesonet}  and $row->{mesonet} == 1) or check_mesonet_station($row->{station},$row->{state}) == 1)
     { push @keeps, $row; }
    push @seen,  $row->{station};
  }
  $i++;
}

print "factor: $i\ncount: $res[0]\n";
my $found_station;
my $distance = 100;
my $cos = cos($lat * pi / 180);
my $cos2 = 2 * $cos * $cos - 1;
my $cos3 = 2 * $cos * $cos2 - $cos;
my $cos4 = 2 * $cos * $cos3 - $cos2;
my $cos5 = 2 * $cos * $cos4 - $cos3;
my $kx = (111.41513 * $cos - 0.09455 * $cos3 + 0.00012 * $cos5);
my $ky = (111.13209 - 0.56605 * $cos2 + 0.0012 * $cos4);
for my $station (@keeps)
{
    my $dy = ($long - $station->{long}) *  $kx;
    my $dx = ($lat - $station->{lat}) * $ky;
    my $d = sqrt($dx * $dx + $dy * $dy);
    if ($d < $distance)
    {
      $distance = $d;
      $found_station = $station;
    }
    printf ("%s: %.4f\n",  $station->{station}, $d);
}

print Dumper $found_station;

