#!/usr/bin/perl
#
# simplely dump out content of a dbm
#
dbmopen (%DB, $ARGV[0], undef);
foreach (sort keys %DB) {
   print "key=$_, value=$DB{$_}\n";
}
dbmclose(%DB);
