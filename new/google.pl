#!/usr/bin/perl

use strict;
use warnings;
use lib '.';
use Weather;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use DBI;

#my ($zone,$lat,$long,$location,$airport,$state,$tz) = google_geocode(shift);
#print "$lat,$long\n";

print alerts(shift);

#my $gdbh = DBI->connect("dbi:SQLite:/afs/dsrw.org/public/databases/wx.db")
#	    or die "Cannot connect: $DBI::errstr";
#
#my $ua = new LWP::UserAgent;
#$ua->default_header("Accept" => "application/geo+json");
#
#my $resp = $ua->get("https://api.weather.gov/zones/forecast");
#my $j = decode_json($resp->content);
#for (@{$j->{features}})
#{
#  print $_->{properties}->{id}, "\t";
#  $gdbh->do("update zones set timezone=? where zone=?",{},$_->{properties}->{timeZone}->[0],$_->{properties}->{id});
#  print $_->{properties}->{timeZone}->[0],"\n";
#}
##
#fail "can't get alerts" unless $resp->is_success;
#
#my $alerts = decode_json($resp->content);
#for (@{$alerts->{features}})
#{
#
#  print "+",$_->{properties}->{event}, "\n";
#}

