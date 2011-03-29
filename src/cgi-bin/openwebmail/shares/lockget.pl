
#                              The BSD License
#
#  Copyright (c) 2009-2011, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# lockget.pl - lock and get message ids, header, block
#
# routines in this file will do lock and db sync
# before making access to folderfile/folderdb
#
# lockget_message_header/block are wrappers for get_message_header/block in maildb.pl
# the two routines returns size, size < 0 means error

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);

sub lockget_messageids {
   my ($folderfile, $folderdb, $r_messageids, $has_globallock) = @_;

   if (!$has_globallock) {
      if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB)) {
         return(-1, "$folderfile read lock error");
      }

      if (!update_folderindex($folderfile, $folderdb) < 0) {
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
         return(-1, "Could not update index db $folderdb");
      }
   }

   # populate the array ref with the messageids
   @{$r_messageids} = get_messageids_sorted_by_offset($folderdb);

   if (!$has_globallock) {
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
   }

   return (0, '');
}

sub lockget_message_header {
   my ($messageid, $folderfile, $folderdb, $r_header, $has_globallock) = @_;

   my $folderhandle = do { no warnings 'once'; local *FH };

   # -1: lock/open error
   if (!$has_globallock) {
      if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB)) {
         writelog("cannot lock file $folderfile");
         return -1;
      }

      if (!update_folderindex($folderfile, $folderdb) < 0) {
         writelog("cannot update index db $folderdb");
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
         return -1;
      }
   }

   if (!sysopen($folderhandle, $folderfile, O_RDONLY)) {
      writelog("cannot open file $folderfile ($!)");

      if (!$has_globallock) {
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
      }

      return -1;
   }

   # note: get_message_header error codes are later decremented by 1.
   # -1: message id not in database
   # -2: invalid header size in database
   # -3: header size mismatch read error
   # -4: header start and end does not match index
   my $size = get_message_header($messageid, $folderdb, $folderhandle, $r_header);

   close($folderhandle) or writelog("cannot close file $folderfile ($!)");

   if (!$has_globallock) {
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
   }

   # on error, decrement $size return value so -1 can still be lock/open error
   return $size - 1 if $size < 0;

   # or just return the valid header size
   return $size;
}

sub lockget_message_block {
   # -1: lock/open error
   # -2: message id not in database
   # -3: invalid message size in database
   # -4: message size mismatch read error
   # -5: message start and end does not match index
   my ($messageid, $folderfile, $folderdb, $r_block, $has_globallock) = @_;

   my $folderhandle = do { no warnings 'once'; local *FH };

   if (!$has_globallock) {
      if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB)) {
         writelog("cannot lock file $folderfile");
         return -1;
      }

      if (!update_folderindex($folderfile, $folderdb) < 0) {
         writelog("cannot update index db $folderdb");
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
         return -1;
      }
   }

   if (!sysopen($folderhandle, $folderfile, O_RDONLY)) {
      writelog("cannot open file $folderfile ($!)");

      if (!$has_globallock) {
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
      }

      return -1;
   }

   # note: get_message_header error codes are later decremented by 1.
   # -1: message id not in database
   # -2: invalid message size in database
   # -3: message size mismatch read error
   # -4: message start and end does not match index
   my $size = get_message_block($messageid, $folderdb, $folderhandle, $r_block);

   close($folderhandle) or writelog("cannot close file $folderfile ($!)");

   if (!$has_globallock) {
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile ($!)");
   }

   # on error, decrement $size return value so -1 can still be lock/open error
   return $size - 1 if $size < 0;

   # or just return the valid message size
   return $size;
}

1;
