#!/usr/bin/perl
if ( -f "$ARGV[0].db" || -f "$ARGV[0].dir" ) {
   dbmopen (%DB, $ARGV[0], undef);
   foreach (keys %DB) {
      print "key=$_, value=$DB{$_}\n";
   }
   dbmclose(%DB);
}
