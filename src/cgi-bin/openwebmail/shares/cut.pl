
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

# cut.pl - routines to cut size of webmail or webdisk for quota

use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);

require "shares/ow-shared.pl"; # openwebmailerror and gettext support
require "shares/maildb.pl";    # maildb support

use vars qw(%config);
use vars qw(
              $_OFFSET
              $_SIZE
              $_HEADERSIZE
              $_HEADERCHKSUM
              $_RECVDATE
              $_DATE
              $_FROM
              $_TO
              $_SUBJECT
              $_CONTENT_TYPE
              $_CHARSET
              $_STATUS
              $_REFERENCES
           );                  # defined in maildb.pl

sub cutfoldermails {
   my ($sizetocut, $user, @folders) = @_;

   my @userfolders      = ();
   my %folderfile       = ();
   my %folderdb         = ();
   my $inbox_foldersize = 0;
   my $user_foldersize  = 0;
   my $total_foldersize = 0;

   foreach my $folder (@folders) {
      ($folderfile{$folder}, $folderdb{$folder}) = get_folderpath_folderdb($user, $folder);

      my $foldersize = (-s $folderfile{$folder});

      if (!is_defaultfolder($folder)) {
         push(@userfolders, $folder);
         $user_foldersize += $foldersize;
      }

      if ($folder eq 'INBOX') {
         if ($config{use_homedirspools}) {
            $total_foldersize += $foldersize;
            $inbox_foldersize = $foldersize;
         }
      } else {
         $total_foldersize += $foldersize;
      }
   }

   my @folders_tocut = ();
   push(@folders_tocut, 'virus-mail') if $config{has_virusfolder_by_default};
   push(@folders_tocut, 'spam-mail') if $config{has_spamfolder_by_default};
   push(@folders_tocut, 'mail-trash');
   push(@folders_tocut, 'saved-drafts') if $config{enable_savedraft};

   foreach my $folder (@folders_tocut) {
      next if (-s $folderfile{$folder}) == 0;

      my $sizereduced = (-s $folderfile{$folder});

      ow::filelock::lock($folderfile{$folder}, LOCK_EX) or
         openwebmailerror(gettext('Cannot lock file:') . " $folderfile{$folder}");

      empty_folder($folderfile{$folder}, $folderdb{$folder});

      ow::filelock::lock($folderfile{$folder}, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . " $folderfile{$folder}");

      $sizereduced -= (-s $folderfile{$folder});

      $total_foldersize -= $sizereduced;
      $sizetocut -= $sizereduced;
      return ($_[0] - $sizetocut) if $sizetocut <= 0; # return if we have cut enough
   }

   # or else cut more
   @folders_tocut = ();
   push(@folders_tocut, 'sent-mail') if $config{enable_backupsent};
   push(@folders_tocut, 'saved-messages');

   # put @userfolders to cutlist if it occupies more than 33%
   if ($user_foldersize > $total_foldersize * 0.33) {
      push (@folders_tocut, sort(@userfolders));
   } else {
      $total_foldersize -= $user_foldersize;
   }

   # put INBOX to cutlist if it occupies more than 33%
   if ($config{use_homedirspools}) {
      if ($inbox_foldersize > $total_foldersize * 0.33) {
         push (@folders_tocut, 'INBOX');
      } else {
         $total_foldersize -= $inbox_foldersize;
      }
   }

   for (my $i = 0; $i < 3; $i++) {
      return ($_[0] - $sizetocut) if $total_foldersize == 0; # return if we have cut enough

      my $cutpercent = $sizetocut / $total_foldersize;
      $cutpercent = 0.1 if $cutpercent < 0.1;

      foreach my $folder (@folders_tocut) {
         next if (-s $folderfile{$folder}) == 0;

         my $sizereduced = (-s $folderfile{$folder});

         my $ret = _cutfoldermail($folderfile{$folder}, $folderdb{$folder}, $cutpercent + ($folder eq 'sent-mail' ? 0.1 : 0));

         if ($ret < 0) {
            writelog("cutfoldermails error - folder $folder ret=$ret");
            writehistory("cutfoldermails error - folder $folder ret=$ret");
            next;
         }

         $sizereduced -= (-s $folderfile{$folder});

         writelog("cutfoldermails - $folder, $ret messages removed, reduced size $sizereduced");
         writehistory("cutfoldermails - $folder, $ret messages removed, reduced size $sizereduced");

         $total_foldersize -= $sizereduced;
         $sizetocut -= $sizereduced;
         return ($_[0] - $sizetocut) if $sizetocut <=0; # return if we have cut enough
      }
   }

   writelog("cutfoldermails error - still $sizetocut bytes to cut");
   writehistory("cutfoldermails error - still $sizetocut bytes to cut");
   return ($_[0] - $sizetocut); # return cutsize
}

sub _cutfoldermail {
   # reduce folder size by $cutpercent
   my ($folderfile, $folderdb, $cutpercent) = @_;

   my @deleteids = ();
   my $cutsize   = 0;

   my %FDB = ();

   if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB)) {
      writelog("cannot lock file $folderfile");
      return -1;
   }

   if (update_folderindex($folderfile, $folderdb) < 0) {
      writelog("cannot update folder index for $folderfile");
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
      return -2;
   }

   my $r_messageids = get_messageids_sorted_by_recvdate($folderdb, 0);

   if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH)) {
      writelog("cannot open db $folderdb");
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
      return -3;
   }

   my $totalsize = (stat($folderfile))[7];

   foreach my $id (@{$r_messageids}) {
      push(@deleteids, $id);
      $cutsize += (string2msgattr($FDB{$id}))[$_SIZE];
      last if ($cutsize + $FDB{ZAPSIZE} > $totalsize * $cutpercent);
   }

   ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

   my $counted = operate_message_with_ids('delete', \@deleteids, $folderfile, $folderdb);
   $counted = folder_zapmessages($folderfile, $folderdb);

   ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");

   return $counted;
}

sub cutdirfiles {
   my ($sizetocut, $dir) = @_;

   return 0 if is_under_dotdir_or_folderdir($dir);

   if (!opendir(D, $dir)) {
      writelog("cannot open dir $dir");
      return -1;
   }

   my @files = readdir(D);

   closedir(D) or writelog("cannot close dir $dir");

   my %ftype = ();
   my %fdate = ();
   my %fsize = ();

   foreach my $fname (@files) {
      next if $fname =~ m/^\.\.?$/;

      my ($st_mode, $st_mtime, $st_blocks) = (lstat("$dir/$fname"))[2,9,12];
      if (($st_mode & 0170000) == 0040000) {      # directory
         $ftype{$fname} = 'd';
         $fdate{$fname} = $st_mtime;
         $fsize{$fname} = $st_blocks * 512;
      } elsif (
                 ($st_mode & 0170000) == 0100000  # regular file
                 ||
                 ($st_mode & 0170000) == 0120000  # symlink
              ) {
         $ftype{$fname} = 'f';
         $fdate{$fname} = $st_mtime;
         $fsize{$fname} = $st_blocks * 512;
      } else {                                    # unix specific filetype: fifo, socket, block dev, char dev..
         next;
      }
   }

   my $now = time();

   my @sortedlist = sort { $fdate{$a} <=> $fdate{$b} } keys %ftype;

   foreach my $fname (@sortedlist) {
      if (exists $ftype{$fname} && $ftype{$fname} eq 'f') {
         # file
         if (unlink ow::tool::untaint("$dir/$fname")) {
            $sizetocut -= $fsize{$fname};
            writelog("cutdirfiles - file $dir/$fname has been removed");
            writehistory("cutdirfiles - file $dir/$fname has been removed");
            return ($_[0] - $sizetocut) if $sizetocut <= 0; # return if we have cut enough
         }
      } else {
         # dir
         my $sizecut = cutdirfiles($sizetocut, "$dir/$fname");

         if ($sizecut > 0) {
            $sizetocut -= $sizecut;

            if (rmdir ow::tool::untaint("$dir/$fname")) {
               writelog("cutdir - dir $dir/$fname has been removed");
               writehistory("cutdir - dir $dir/$fname has been removed");
            } else {
               # restore dir modify time
               utime($now, ow::tool::untaint($fdate{$fname}), ow::tool::untaint("$dir/$fname"));
            }

            return ($_[0] - $sizetocut) if $sizetocut <= 0; # return if we have cut enough
         }
      }
   }

   return ($_[0] - $sizetocut); # return cutsize
}

1;
