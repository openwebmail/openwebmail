#!/usr/local/bin/perl
# this is used for debuging maildb routines only...

use strict;
no strict 'vars';
push (@INC, ".");
use Fcntl qw(:DEFAULT :flock);

require "maildb.pl";
require "filelock.pl";
require "openwebmail-shared.pl";

sub dump_headerdb {
   my ($headerdb, $folderfile) = @_;
   my (@messageids, @attr, $r_buff);
   my $spoolhandle=FileHandle->new();
   my $error=0;
   my $i=0;

   @messageids=get_messageids_sorted_by_offset($headerdb);
   open($spoolhandle, $folderfile);

   dbmopen (%HDB, $headerdb, undef);
   $metainfo=$HDB{'METAINFO'};
   dbmclose(%HDB);

   if (  $metainfo eq metainfo($folderfile) ) {
      printf ("+++ METAINFO db:[%s] folder:[%s]\n", $metainfo, metainfo($folderfile));
   } else {
      $error++;
      printf ("--- METAINFO db:[%s] folder:[%s]\n", $metainfo, metainfo($folderfile));
   }

   foreach $id (@messageids) {
      $i++;
      @attr=get_message_attributes($id, $headerdb);
      $r_buff=get_message_block($id, $headerdb, $spoolhandle);

      $id=substr($id,0,50);
      if ( ${$r_buff}!~/^From / ) {
         $error++;
#         printf ("buf=${$r_buff}\n");
         printf ("!!! %3d offset:%8d size:%8d date:%s msgid:$id stat:%s\n",
		$i, $attr[$_OFFSET], $attr[$_SIZE], $attr[$_DATE], $attr[$_STATUS]);
      } else {
#         printf ("buf=${$r_buff}\n");
         printf ("+++ %3d offset:%8d size:%8d date:%s msgid:$id stat:%s\n",
		$i, $attr[$_OFFSET], $attr[$_SIZE], $attr[$_DATE], $attr[$_STATUS]);
      }
   }

   close($spoolhandle);
   print "$error errors\n";
}
      
if ( $#ARGV ==1 ) {
  dump_headerdb($ARGV[1], $ARGV[0]);
} elsif ( $#ARGV ==0 ) {
  my @a=split(/\//, $ARGV[0]);
  $a[$#a]=".$a[$#a]";
  my $db=join('/', @a);
  dump_headerdb($db, $ARGV[0]);
} else {
  print "dumpdb folderfile [headerdb_without_extension]\n";
}
