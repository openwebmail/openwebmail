#!/usr/local/bin/perl
# this is used for debuging maildb routines only...

use strict;
no strict 'vars';
push (@INC, ".");
use Fcntl qw(:DEFAULT :flock);

require "maildb.pl";

sub dump_headerdb {
   my ($headerdb, $spoolfile) = @_;
   my (@messageids, @attr, $r_buff);
   my $spoolhandle=FileHandle->new();
   my $error=0;
   my $i=0;

   @messageids=get_messageids_sorted_by_offset($headerdb);
   open($spoolhandle, $spoolfile);

   dbmopen (%HDB, $headerdb, undef);
   $metainfo=$HDB{'METAINFO'};
   dbmclose(%HDB);

   if (  $metainfo eq metainfo($spoolfile) ) {
      printf ("+++ METAINFO db:[%s] folder:[%s]\n", $metainfo, metainfo($spoolfile));
   } else {
      $error++;
      printf ("--- METAINFO db:[%s] folder:[%s]\n", $metainfo, metainfo($spoolfile));
   }

   foreach $id (@messageids) {
      $i++;
      @attr=get_message_attributes($id, $headerdb);
      $r_buff=get_message_block($id, $headerdb, $spoolhandle);

      $id=substr($id,0,50);
      if ( ${$r_buff}!~/^From / ) {
         $error++;
         printf ("!!! %3d offset:%8d size:%8d date:%s msgid:$id\n",
		$i, $attr[$_OFFSET], $attr[$_SIZE], $attr[$_DATE]);
      } else {
         printf ("+++ %3d offset:%8d size:%8d date:%s msgid:$id\n",
		$i, $attr[$_OFFSET], $attr[$_SIZE], $attr[$_DATE]);
      }
   }

   close($spoolhandle);
   print "$error errors\n";
}
      
if ( $#ARGV ==1 ) {
  dump_headerdb($ARGV[0], $ARGV[1]);
} else {
  print "dumpdb [headerdb] [spoolfile]\n";
}
