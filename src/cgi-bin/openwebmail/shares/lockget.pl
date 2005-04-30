#
# lockget.pl - lock and get message ids, header, block
#
# routines in this file will do lock and db sync
# before making access to folderfile/folderdb
#

use strict;
use Fcntl qw(:DEFAULT :flock);

# lockget_message_header/block are wrappers for get_message_header/block in maildb.pl
# the two routines returns (size, errmsg), size<0 means error
#
# -1 folder/dbm lock/open error
# -2 msg not found in db
# -3 size in db invalid
# -4 size mismatched with read
# -5 folder index inconsistence
#
# ps: in case size=-3/-4/-5, db reindex is required.
#

sub lockget_messageids {
   my ($folderfile, $folderdb, $r_messageids, $has_globallock)=@_;

   if (!$has_globallock) {
      if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB)) {
         return(-1, "$folderfile read lock error");
      }
      if (!update_folderindex($folderfile, $folderdb)<0) {
         ow::filelock::lock($folderfile, LOCK_UN);
         return(-1, "Couldn't update index db $folderdb");
      }
   }
   @{$r_messageids}=get_messageids_sorted_by_offset($folderdb);
   ow::filelock::lock($folderfile, LOCK_UN) if (!$has_globallock);

   return(0, '');
}

sub lockget_message_header {
   my ($messageid, $folderfile, $folderdb, $r_header, $has_globallock)=@_;
   my $folderhandle=do { local *FH };

   if (!$has_globallock) {
      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         return(-1, "$folderfile read lock error");
      if (!update_folderindex($folderfile, $folderdb)<0) {
         ow::filelock::lock($folderfile, LOCK_UN);
         return(-1, "Couldn't update index db $folderdb");
      }
   }
   if (!sysopen($folderhandle, $folderfile, O_RDONLY)) {
      ow::filelock::lock($folderfile, LOCK_UN) if (!$has_globallock);
      return(-1, "$folderfile read open error");
   }
   my ($size, $errmsg)=get_message_header($messageid, $folderdb, $folderhandle, $r_header);
   close($folderhandle);
   ow::filelock::lock($folderfile, LOCK_UN) if (!$has_globallock);

   # -1 lock/open err, -2 msg not found in db, -3 size in db invalid, -4 read size mismatched
   return($size-1, $errmsg) if ($size<0);

   if (substr(${$r_header}, 0, 5) ne 'From ' ||
      substr(${$r_header}, $size-1, 1) ne "\n") {	# msg header should end with \n
      return(-5, "msg $messageid in $folderfile index inconsistence");
   }
   return($size, '');
}

sub lockget_message_block {
   my ($messageid, $folderfile, $folderdb, $r_block, $has_globallock)=@_;
   my $folderhandle=do { local *FH };

   if (!$has_globallock) {
      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         return(-1, "$folderfile read lock error");
      if (!update_folderindex($folderfile, $folderdb)<0) {
         ow::filelock::lock($folderfile, LOCK_UN);
         return(-1, "Couldn't update index db $folderdb");
      }
   }
   if (!sysopen($folderhandle, $folderfile, O_RDONLY)) {
      ow::filelock::lock($folderfile, LOCK_UN) if (!$has_globallock);
      return(-1, "$folderfile read open error");
   }
   my ($size, $errmsg)=get_message_block($messageid, $folderdb, $folderhandle, $r_block);
   close($folderhandle);
   ow::filelock::lock($folderfile, LOCK_UN) if (!$has_globallock);

   # -1 lock/open err, -2 msg not found in db, -3 size in db invalid, -4 read size mismatched
   return($size-1, $errmsg) if ($size<0);

   if (substr(${$r_block}, 0, 5) ne 'From ' ||
      substr(${$r_block}, $size-1, 1) ne "\n") {	# msg should end with \n
      return(-5, "msg $messageid in $folderfile index inconsistence");
   }
   return($size, '');
}

1;
