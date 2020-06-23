#!/usr/bin/perl

use strict;
use warnings;
use lib '.';
use Weather_osm;
use Data::Dumper;

my $station = shift;
my $state = shift;

print get_mesonet_data($station, $state);
