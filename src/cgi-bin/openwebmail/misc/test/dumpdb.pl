#!/usr/bin/perl
#
# simply dump out content of a dbm
# the first argument should be the full path to the db WITHOUT THE EXTENSION
# dumpdb.pl /path/to/db/file
# would dump file.db
#
use strict;
use warnings;
use Data::Dumper;
$Data::Dumper::Sortkeys++;

my $dbfile = $ARGV[0];

my %DB = ();

dbmopen (%DB, $dbfile, 0700) or die "cannot open db $dbfile\: $!";

print Dumper(\%DB);

dbmclose(%DB);


