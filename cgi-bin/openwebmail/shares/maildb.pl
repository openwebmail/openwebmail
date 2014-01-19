
#                              The BSD License
#
#  Copyright (c) 2009-2014, The OpenWebMail Project
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

# maildb.pl - mail indexing routines
#   - This module speeds up the message folder access by caching important information with perl dbm.
#   - Functions in this file do not do locks for folderfile/folderhandle. They rely on the caller to do that lock.
#   - Functions with folderfile/folderhandle in argument must be inside a folderfile lock session.
#   - Functions may change the current folderfile read position! Be careful!

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);

# extern vars
use vars qw(%config %prefs);

# define the version of the mail index database
use vars qw($_DBVERSION);
$_DBVERSION = 20110123;

# globals, message attribute number constant
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
           );

$_OFFSET       = 0;
$_SIZE         = 1;
$_HEADERSIZE   = 2;
$_HEADERCHKSUM = 3;
$_RECVDATE     = 4;
$_DATE         = 5;
$_FROM         = 6;
$_TO           = 7;
$_SUBJECT      = 8;
$_CONTENT_TYPE = 9;
$_CHARSET      = 10;
$_STATUS       = 11;
$_REFERENCES   = 12;

# we devide messages in a folder into the following 4 types exclusively
# ZAPPED:   message deleted by user but still not removed from folder, has Z flag in status in db
# INTERNAL: message with is_internal_subject ret=1
# NEW:      message has R flag in status
# OLD:      message not in the above 3 types
use vars qw(%is_internal_dbkey);
%is_internal_dbkey = (
                        DBVERSION        => 1, # for db format checking
                        METAINFO         => 1, # for db consistence check
                        LSTMTIME         => 1, # for message membership check, used by getmsgids.pl
                        ALLMESSAGES      => 1,
                        NEWMESSAGES      => 1,
                        INTERNALMESSAGES => 1,
                        INTERNALSIZE     => 1,
                        ZAPMESSAGES      => 1,
                        ZAPSIZE          => 1,
                        ''               => 1,
                     );

use vars qw($BUFF_filehandle $BUFF_filestart $BUFF_fileoffset $BUFF_start $BUFF_size $BUFF_buff $BUFF_EOF);

use vars qw($BUFF_blocksize $BUFF_blocksizemax $BUFF_regex);
$BUFF_blocksize    = 32768;
$BUFF_blocksizemax = $BUFF_blocksize + 512;
$BUFF_regex        = qr/^From .*(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+([A-Z]{3,4}\d?\s+)?(\d\d+)/;

sub update_folderindex {
   # this routine indexes the messages in a folder and
   # marks duplicated messages with a 'Z' (to be zapped)
   my ($folderfile, $folderdb) = @_;

   writelog("debug_mailprocess :: $folderfile :: updating folder index") if $config{debug_mailprocess};

   $folderdb = ow::tool::untaint($folderdb);

   my $is_db_reuseable = 0; # 0: not exist, 1: reuseable, -1: not reuseable
   my @oldmessageids   = ();
   my $folderhandle    = do { no warnings 'once'; local *FH };
   my $foldermeta      = ow::tool::metainfo($folderfile);

   my %FDB    = ();
   my %OLDFDB = ();

   if (ow::dbm::existdb($folderdb)) {
      ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(gettext('Cannot open db:') . " $folderdb ($!)");

      if (defined $FDB{DBVERSION} && $FDB{DBVERSION} eq $_DBVERSION) {
         # this db file is the current dbversion, so lets use its data
         my ($foldersize) = $foldermeta =~ m/^mtime=\d+ size=(\d+)$/;

         if (
               $FDB{NEWMESSAGES} >= 0
               && $FDB{INTERNALMESSAGES} >= 0
               && $FDB{INTERNALSIZE} >= 0
               && $FDB{ZAPMESSAGES} >= 0
               && $FDB{ZAPSIZE} >= 0
               && $FDB{ALLMESSAGES} >= $FDB{NEWMESSAGES} + $FDB{INTERNALMESSAGES} + $FDB{ZAPMESSAGES}
               && $foldersize >= $FDB{INTERNALSIZE} + $FDB{ZAPSIZE}
               && $FDB{METAINFO} eq $foldermeta
            ) {
            # database attributes match the folder metainfo - no update needed
            ow::dbm::closedb(\%FDB, $folderdb) or
               openwebmailerror(gettext('Cannot close db:') . " $folderdb ($!)");

            writelog("debug_mailprocess :: $folderfile :: db/folder metainfo matches - no update needed") if $config{debug_mailprocess};

            return 0; # all ok
         }

         writelog("debug_mailprocess :: $folderfile :: db/folder metainfo mismatch ::\nfolder  : $foldermeta\ndatabase: $FDB{METAINFO}") if $config{debug_mailprocess};

         $is_db_reuseable = -1;

         @oldmessageids = get_messageids_sorted_by_offset_db(\%FDB);

         # check if the db is reuseable or if it needs to be rebuilt
         if (
               $FDB{NEWMESSAGES} >= 0
               && $FDB{INTERNALMESSAGES} >= 0
               && $FDB{INTERNALSIZE} >= 0
               && $FDB{ZAPMESSAGES} >= 0
               && $FDB{ZAPSIZE} >= 0
               && $FDB{ALLMESSAGES} >= $FDB{NEWMESSAGES} + $FDB{INTERNALMESSAGES} + $FDB{ZAPMESSAGES}
               && $foldersize >= $FDB{INTERNALSIZE} + $FDB{ZAPSIZE}
               && $FDB{METAINFO} =~ m/^mtime=\d+ size=\d+$/  # not forced reindex (which sets RENEW or ERR as the metainfo)
               && $FDB{ALLMESSAGES} == ($#oldmessageids + 1) # message count is correct
            ) {
            $is_db_reuseable = 1;

            writelog("debug_mailprocess :: $folderfile :: db seems to be reusable - double check against the folder itself") if $config{debug_mailprocess};
            # seems to be reusable - double check against the folder itself
            # assume the db is reuseable if some records in the db
            # are consistent against the old messages in the folder
            my @oldmessageidindexes_to_check = ();

            if ($#oldmessageids >= 4) {
               # more than 3 messages, spot check some
               my $checkevery = int(($#oldmessageids - 1) / 3);

               writelog("debug_mailprocess :: $folderfile :: checking every $checkevery messages out of $#oldmessageids old message ids") if $config{debug_mailprocess};

               for (my $index = 0; $index < $#oldmessageids - 1; $index += $checkevery) {
                  push (@oldmessageidindexes_to_check, $index);
               }

               # and the second to last and last message too
               push(@oldmessageidindexes_to_check, $#oldmessageids - 1, $#oldmessageids);
            } else {
               # 3 or less messages, just check them all
               @oldmessageidindexes_to_check = (0..$#oldmessageids);
               writelog("debug_mailprocess :: $folderfile :: checking every message - $#oldmessageids old message ids") if $config{debug_mailprocess};
            }

            if ($#oldmessageidindexes_to_check >= 0) {
               sysopen($folderhandle, $folderfile, O_RDONLY) or
                  openwebmailerror(gettext('Cannot open file:') . " $folderfile ($!)");

               foreach my $index (@oldmessageidindexes_to_check) {
                  my $msgid = $oldmessageids[$index];
                  my @attr  = string2msgattr($FDB{$msgid});

                  if (!is_msgattr_consistent_with_folder(\@attr, $folderhandle)) {
                     writelog("debug_mailprocess :: $folderfile :: attributes from db do not match spool for messageid $msgid - db is not reuseable") if $config{debug_mailprocess};
                     $is_db_reuseable = -1;
                     last;
                  }
               }

               close($folderhandle) or
                  openwebmailerror(gettext('Cannot close file:') . " $folderfile ($!)");
            }
         }

         ow::dbm::closedb(\%FDB, $folderdb) or
            openwebmailerror(gettext('Cannot close db:') . " $folderdb ($!)");
      } else {
         # old db version - remove it so we can make a new one
         writelog("debug_mailprocess :: $folderfile :: old db version - removing old db") if $config{debug_mailprocess};

         ow::dbm::closedb(\%FDB, $folderdb) or
            openwebmailerror(gettext('Cannot close db:') . " $folderdb ($!)");

         ow::dbm::unlinkdb($folderdb) or
            openwebmailerror(gettext('Cannot delete db:') . " $folderdb ($!)");
      }
   }

   writelog("debug_mailprocess :: $folderfile :: is_db_reuseable = $is_db_reuseable") if $config{debug_mailprocess};

   my $totalmessages    = -1; # so first message is index 0
   my $totalsize        = 0;
   my $newmessages      = 0;
   my $internalmessages = 0;
   my $internalsize     = 0;
   my $zapmessages      = 0;
   my $zapsize          = 0;

   sysopen($folderhandle, $folderfile, O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:') . " $folderfile ($!)");

   my $foldersize = (stat($folderhandle))[7];

   if ($is_db_reuseable == 0) {
      # db does not exist for this folder - make a new db
      writelog("debug_mailprocess :: $folderfile :: making a new db") if $config{debug_mailprocess};
      ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or
         openwebmailerror(gettext('Cannot open db:') . " $folderdb ($!)");

      # ensure the folderdb is empty
      %FDB = ();
   } elsif ($is_db_reuseable > 0) {
      # the existing db is reuseable - we just need to append the new messages information to it
      writelog("debug_mailprocess :: $folderfile :: re-using the existing db") if $config{debug_mailprocess}; 
      ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or
         openwebmailerror(gettext('Cannot open db:') . " $folderdb ($!)");

      $totalmessages = $FDB{ALLMESSAGES} - 1;

      if ($totalmessages >= 0) {
         # refer to the db summary keys only if old records are found in the db
         $newmessages      = $FDB{NEWMESSAGES};
         $internalmessages = $FDB{INTERNALMESSAGES};
         $internalsize     = $FDB{INTERNALSIZE};
         $zapmessages      = $FDB{ZAPMESSAGES};
         $zapsize          = $FDB{ZAPSIZE};

         my $last_msgid = $oldmessageids[$#oldmessageids];
         my @attr = string2msgattr($FDB{$last_msgid});
         $totalsize = $attr[$_OFFSET] + $attr[$_SIZE];
      }
   } elsif ($is_db_reuseable < 0) {
      # db is inconsistent and cannot be used entirely
      # to save overhead, try to salvage as many records as possible from
      # the old database into our new updated database
      writelog("debug_mailprocess :: $folderfile :: db is inconsistent - salvage as many records as possible") if $config{debug_mailprocess};
      ow::dbm::renamedb($folderdb, "$folderdb.old") or
         openwebmailerror(gettext('Cannot rename db:') . " $folderdb -> $folderdb.old ($!)");

      ow::dbm::opendb(\%OLDFDB, "$folderdb.old", LOCK_SH) or
         openwebmailerror(gettext('Cannot open db:') . " $folderdb.old ($!)");

      ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or
         openwebmailerror(gettext('Cannot open db:') . " $folderdb ($!)");

      # ensure the new db is empty
      %FDB = ();

      # copy as many records as possible from the old db
      my $lastsize         = 0;
      my $lastid           = '';
      my $last_is_new      = 0;
      my $last_is_internal = 0;
      my $last_is_zap      = 0;

      foreach my $id (@oldmessageids) {
         my $size    = 0;
         my $offset  = -1;
         my $status  = '';
         my $subject = '';

         # capture the attributes for this message from the old db
         if (defined $OLDFDB{$id}) {
            # check if the message attributes in the db are valid against the folder file
            # assume that if the message header is valid (via checksum) than the body is valid
            my @attr = string2msgattr($OLDFDB{$id});

            if (
                  $attr[$_OFFSET] >= 0
                  && $attr[$_HEADERSIZE] > 0
                  && $attr[$_SIZE] > $attr[$_HEADERSIZE]
               ) {
               my $buff = '';
               seek($folderhandle, $attr[$_OFFSET], 0);

               # read this message header into buff
               my $readlen = read($folderhandle, $buff, $attr[$_HEADERSIZE]);

               if (
                     $readlen == $attr[$_HEADERSIZE]
                     && $buff =~ m/^From /
                     && $attr[$_HEADERCHKSUM] eq ow::tool::calc_checksum(\$buff)
                  ) {
                  # looks valid
                  $size    = $attr[$_SIZE];
                  $offset  = $attr[$_OFFSET];
                  $status  = $attr[$_STATUS];
                  $subject = $attr[$_SUBJECT];
               }
            }
         }

         last if !$size || $offset < 0 || $offset != $totalsize + $lastsize;

         if ($totalmessages >= 0) {
            $FDB{$lastid} = $OLDFDB{$lastid};

            $totalsize += $lastsize;

            if ($last_is_zap) {
               $zapmessages++;
               $zapsize += $lastsize;
            } elsif ($last_is_internal) {
               $internalmessages++;
               $internalsize += $lastsize;
            } elsif ($last_is_new) {
               $newmessages++;
            }
         }

         $totalmessages++;

         $lastsize = $size;
         $lastid   = $id;

         # message will be in one of the 4 types: zapped, internal, new, old
         $last_is_new      = 0;
         $last_is_internal = 0;
         $last_is_zap      = 0;

         if ($status =~ m/Z/i) {
            $last_is_zap = 1;
         } elsif (is_internal_subject($subject)) {
            $last_is_internal = 1;
         } elsif ($status !~ m/R/i) {
            $last_is_new = 1;
         }
      }

      if ($totalmessages >= 0) {
         # at least one message header matched
         my $is_last_ok = 0;

         # did the last successful match make it exactly to the end of the folder?
         if ($totalsize + $lastsize == $foldersize) {
            $is_last_ok = 1;
         } else {
            # did the last valid header match end at the start of a new message?
            seek($folderhandle, $totalsize + $lastsize - 1, 0);
            my $buff = '';
            read($folderhandle, $buff, 6);
            $is_last_ok = 1 if $buff eq "\nFrom ";
         }

         if ($is_last_ok) {
            $FDB{$lastid} = $OLDFDB{$lastid};

            $totalsize += $lastsize;

            if ($last_is_zap) {
               $zapmessages++;
               $zapsize += $lastsize;
            } elsif ($last_is_internal) {
               $internalmessages++;
               $internalsize += $lastsize;
            } elsif ($last_is_new) {
               $newmessages++;
            }
         } else {
            $totalmessages--;
         }
      }
   }

   writelog("debug_mailprocess :: $folderfile :: db is ready for updating") if $config{debug_mailprocess};

   # db is now ready for updating
   # set the point at which we will start reading from
   # the spool in order to update the database
   $BUFF_filehandle = $folderhandle;
   $BUFF_filestart  = $totalsize;
   $BUFF_fileoffset = $BUFF_filestart;
   $BUFF_start      = $BUFF_filestart;
   $BUFF_size       = 0;
   $BUFF_buff       = '';
   $BUFF_EOF        = 0;

   buffer_readblock();

   my ($header_offset, $r_header_content) = _get_next_msgheader_buffered(0);
   $totalsize = $header_offset;

   my %flag = (); # internal flag

   while ($header_offset >= 0) {
      $totalmessages++;

      $flag{$_} = 0 for qw(T V Z); # T(has att), V(verified), Z(to be zapped)

      # create a hash of attributes for this message,
      # extracting the information from the header lines
      my %message = (
                       from           => 'N/A',
                       to             => 'N/A',
                       date           => 'N/A',
                       subject        => 'N/A',
                       'content-type' => 'N/A',
                       'message-id'   => '',
                       status         => '',
                       references     => '',
                       charset        => '',
                       'in-reply-to'  => '',
                    );

      ow::mailparse::parse_header($r_header_content, \%message);

      if ($message{'content-type'} =~ m/^multipart/i) {
         $message{msg_type} = 'm';
      } elsif ($message{'content-type'} eq 'N/A' || $message{'content-type'} =~ m#^text/plain#i ) {
         $message{msg_type} = 'p';
      } else {
         $message{msg_type} = '';
      }

      writelog("debug_maildb - database mail header parsed:" . join("\n", map { "$_ => $message{$_}" } sort keys %message)) if $config{debug_maildb};

      $message{offset}       = $header_offset;
      $message{headersize}   = length ${$r_header_content};
      $message{headerchksum} = ow::tool::calc_checksum($r_header_content);

      # check if this message info was recorded into the old folderdb so we can seek to the
      # message end quickly and skip scanning all the content type parts
      my ($skip, $oldstatus, $oldcharset, $oldchksum) = (string2msgattr($OLDFDB{$message{'message-id'}}))[$_SIZE, $_STATUS, $_CHARSET, $_HEADERCHKSUM];

      $oldstatus  = '' unless defined $oldstatus;
      $oldcharset = '' unless defined $oldcharset;
      $oldchksum  = '' unless defined $oldchksum;

      $skip = 0 if $oldchksum ne $message{headerchksum};

      if ($skip) {
         # the old db has this message - copy the info from the old db
         writelog("debug_mailprocess :: copying attributes from old db for message $message{'message-id'}") if $config{debug_mailprocess};
         $flag{$1} = 1 if $oldstatus =~ m/(T|V|Z)/i;

         $message{charset} = $oldcharset;

         # skip past this message - we are already positioned at the end of the header
         $skip -= $message{headersize};
      } else {
         # the old db does not have this message - parse it to get its info
         writelog("debug_maildb - database parsing message header_offset=$header_offset") if $config{debug_maildb};

         if ($message{msg_type} eq 'm') {
            # multipart message
            my $block = _skip_to_next_text_block();

            while ($block ne '') {
               $message{charset} = $1 if (
                                            # is att header?
                                            $message{charset} eq ''
                                            && $block =~ m/^--/
                                            && $block =~ m/^content-type:.*;\s*charset="?([^\s"';]*)"?/ims # 'm' to check multiple lines
                                         );

               writelog("debug_maildb - detected message block charset='$message{charset}'") if $config{debug_maildb};

               $flag{T} = 1 if (  # has_att?
                                  !$flag{T}
                                  && (
                                        $block =~ m/^content-type:.*;\s*name\s*\*?=/ims
                                        ||
                                        $block =~ m/^content-disposition:.*;\s*filename\s*\*?=/ims
                                     )
                               );

               writelog("debug_maildb - multipart detected message block attachments flag T=$flag{T}") if $config{debug_maildb};

               $block = (!$flag{T} || $message{charset} eq '') ? _skip_to_next_text_block() : '';
            }
         } elsif ($message{msg_type} eq 'p') {
            # plain text message
            my $block = _skip_to_next_text_block();

            while ($block ne '') {
               if ($block =~ m/^begin [0-7][0-7][0-7][0-7]? [^\n\r]+/mi) {
                  $flag{T} = 1;
                  $block   = '';
               } else {
                  $block = _skip_to_next_text_block();
               }
            }
         } else {
            $flag{T} = 1 if (  # has_att?
                               !$flag{T}
                               && (
                                     (exists $message{'content-type'} && $message{'content-type'} =~ m/^.*;\s*name\s*\*?=/ims)
                                     ||
                                     (exists $message{'content-disposition'} && $message{'content-disposition'} =~ m/^.*;\s*filename\s*\*?=/ims)
                                  )
                            );

            writelog("debug_maildb - detected message block attachments flag T=$flag{T}") if $config{debug_maildb};
         }
      }

      ($header_offset, $r_header_content) = _get_next_msgheader_buffered($skip);

      if ($header_offset >= 0) {
         # next message start found
         $message{size} = $header_offset - $totalsize;
         $totalsize = $header_offset;
      } else {
         # folder end
         # compare metainfo since folder may have been changed by another processes that did not respect filelock
         my $foldermeta2 = ow::tool::metainfo($folderfile);

         if ($foldermeta2 ne $foldermeta) {
            # folder file was changed during indexing
            writelog("db warning - folder $folderfile changed during indexing - [$foldermeta] -> [$foldermeta2]");
            $foldermeta = $foldermeta2;
            $foldersize = (stat($folderhandle))[7];

            if ($foldersize == 0) {
               # folder file was cleaned during indexing
               %FDB              = ();
               $totalmessages    = -1;
               $newmessages      = 0;
               $internalmessages = 0;
               $internalsize     = 0;
               $zapmessages      = 0;
               $zapsize          = 0;
               last;
            }
         }

         $message{size} = $foldersize - $totalsize;
      }

      # perform additional processing on the message hash attributes for maildb:

      # message dateserial (Mon Aug 20 18:24 CST 2010 -> 20100820182400)
      $message{date}     = ow::datetime::datefield2dateserial($message{date}) if exists $message{date} && $message{date};
      $message{recvdate} = ow::datetime::delimiter2dateserial($message{delimiter}, $config{deliver_use_gmt}, $prefs{daylightsaving}, $prefs{timezone})
                               || ow::datetime::gmtime2dateserial();
      $message{date}     = $message{recvdate} unless exists $message{date} && $message{date};

      # try to get charset from contenttype header
      $message{charset} = $1 if $message{charset} eq '' && $message{'content-type'} =~ m/charset\s*=\s*"?([^\s"';]*)"?\s?/i;

      # decode mime and convert from/to/subject to message charset with iconv.
      # the intention here is to always store from, to, and subject as utf-8 strings
      # in the database, but if iconv cannot convert the string it ends up getting
      # stored as whatever charset it was... and then displayed incorrectly when
      # the user views the message in listview or read.
      # TODO figure out a fallback method when strings cannot be converted to utf-8
      # perhaps add a flag to the database
      $message{$_} = decode_mimewords_iconv($message{$_}, 'utf-8') for qw(from to subject);

      # in most cases, a message references field should already contain
      # ids in in-reply-to: field, but do check it again here
      if ($message{'in-reply-to'} =~ m/\S/) {
         # <someone@somehost> "desc..."
         my $string = $message{'in-reply-to'};
         $string =~ s/^.*?(\<\S+\>).*$/$1/;
         $message{references} .= " $string" if $message{references} !~ m/\Q$string\E/;
      }

      $message{references} =~ s/\s{2,}/ /g;

      if ($message{'message-id'} eq '') {
         # fake messageid with date and from
         $message{'message-id'} = "$message{date}." . (ow::tool::email2nameaddr($message{from}))[1];
         $message{'message-id'} =~ s![<>()\s/"':]!!g;
         $message{'message-id'} = "<$message{'message-id'}>";
      } elsif (length $message{'message-id'} >= 128) {
         $message{'message-id'} = '<' . substr($message{'message-id'}, 1, 125) . '>';
      }

      # message status
      $message{status} .= $message{'x-status'} if exists $message{'x-status'} && defined $message{'x-status'};
      $message{status} .= 'I' if exists $message{priority} && $message{priority} =~ m/urgent/i;

      # flags used by openwebmail internally
      $message{status} .= 'T' if exists $flag{T} && $flag{T}; # has attachment
      $message{status} .= 'V' if exists $flag{V} && $flag{V}; # verified
      $message{status} .= 'Z' if exists $flag{Z} && $flag{Z}; # to be zap

      $message{status} =~ s/\s//g;

      my $id = $message{'message-id'};

      if (defined $FDB{$id}) {
         # duplicated message found?
         if ($message{status} !~ m/Z/i) {
            # this is not zap, mark prev as zap
            my @attr0 = string2msgattr($FDB{$id});
            if ($attr0[$_STATUS] !~ m/Z/i) {
               # try to mark prev as zap
               $attr0[$_STATUS] .= 'Z';
               $zapmessages++;
               $zapsize += $attr0[$_SIZE];
               if (is_internal_subject($attr0[$_SUBJECT])) {
                  $internalmessages--;
                  $internalsize -= $attr0[$_SIZE];
               } elsif ($attr0[$_STATUS] !~ m/R/i) {
                  $newmessages--;
               }
            }
            $FDB{"DUP$attr0[$_OFFSET]-$id"} = msgattr2string(@attr0);
            delete $FDB{$id};
         } else {
            # this is zap, change messageid
            $id = "DUP$message{offset}-$id";
         }
      }

      if ($message{status} =~ m/Z/i) {
         $zapmessages++;
         $zapsize += $message{size};
      } elsif (is_internal_subject($message{subject})) {
         $internalmessages++;
         $internalsize += $message{size};
      } elsif($message{status} !~ m/R/i) {
         $newmessages++;
      }

      writelog("warning - writing message $id with size 0 to db $folderdb (status $message{status})")
         if $message{size} == 0;

      # write this message to the db (tied db)
      $FDB{$id} = msgattr2string(
                                   $message{offset},
                                   $message{size},
                                   $message{headersize},
                                   $message{headerchksum},
                                   $message{recvdate},
                                   $message{date},
                                   $message{from},
                                   $message{to},
                                   $message{subject},
                                   $message{'content-type'},
                                   $message{charset},
                                   $message{status},
                                   $message{references}
                                );
   }

   writelog("debug_mailprocess :: $folderfile :: db update complete") if $config{debug_mailprocess};

   close($folderhandle) or
      openwebmailerror(gettext('Cannot close file:') . " $folderfile ($!)");

   $FDB{ALLMESSAGES}      = $totalmessages + 1;
   $FDB{NEWMESSAGES}      = $newmessages;
   $FDB{INTERNALMESSAGES} = $internalmessages;
   $FDB{INTERNALSIZE}     = $internalsize;
   $FDB{ZAPMESSAGES}      = $zapmessages;
   $FDB{ZAPSIZE}          = $zapsize;
   $FDB{DBVERSION}        = $_DBVERSION;
   $FDB{METAINFO}         = $foldermeta;
   $FDB{LSTMTIME}         = time();

   ow::dbm::closedb(\%FDB, $folderdb) or
      openwebmailerror(gettext('Cannot close db:') . " $folderdb ($!)");

   # remove old folderdb
   if (ow::dbm::existdb("$folderdb.old")) {
      ow::dbm::closedb(\%OLDFDB, "$folderdb.old") or
         openwebmailerror(gettext('Cannot close db:') . " $folderdb.old ($!)");

      ow::dbm::unlinkdb("$folderdb.old") or
         openwebmailerror(gettext('Cannot delete db:') . " $folderdb.old ($!)");
   }

   return 1;
}

sub _get_next_msgheader_buffered {
   # returns: $offset, $r_header_content
   my $skip = shift; # number of bytes to skip in the buffer

   my $pos            = 0;
   my $offset         = -1;
   my $header_content = '';

   buffer_skipchars($skip) if $skip;

   # locate the start of the message
   while ($offset < 0 and $pos >= 0) {
      $pos    = (buffer_index(0, 'From '))[0];
      $offset = buffer_startmsgchk($pos) if $pos >= 0;
   }

   # get msgheader until the first \n\n (pos > 0) or EOF (pos = -1)
   # note: the first \n is counted as part of the msgheader
   if ($offset >= 0) {
      $pos = (buffer_index(1, "\n\n"))[0];
      $pos++ if $pos >= 0; # count first \n into msgheader
      $header_content = buffer_getchars($pos);
   }

   return ($offset, \$header_content);
}

sub _skip_to_next_text_block {
   # search the buffer for a block of text (delimited by '\n\n' or '\nFrom ')
   # we are only interested in returning the first 4096 or less bytes of the block
   my $block_content = '';

   writelog("debug_maildb_buffer - _skip_to_next_text_block start") if $config{debug_maildb_buffer};

   # skip past any leading new line characters
   buffer_skipleading("\n");

   # we are done if this is the next message block
   if (buffer_startmsgchk(0) < 0) {
      # find first occurance of "\n\n" or "\nFrom "
      my ($pos, $foundstring) = buffer_index(1, "\n\n", "\nFrom");

      # get max 4096 chars or to the end of the block
      # then skip to the next block start
      if ($pos > 4096) {
         $block_content = buffer_getchars(4096);
         buffer_skipchars($pos - 4096);
      } elsif ($pos >= 0) {
         $block_content = buffer_getchars($pos);
      } else {
         # pos == -1 means not found until EOF
         $block_content = buffer_getchars(4096);
      }
   }

   return $block_content;
}

sub get_messageids_sorted_by_offset {
   my $folderdb = shift;

   my %FDB = ();

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
      openwebmailerror(gettext('Cannot open db:') . " $folderdb ($!)");

   my @keys = get_messageids_sorted_by_offset_db(\%FDB);

   ow::dbm::closedb(\%FDB, $folderdb) or
      openwebmailerror(gettext('Cannot close db:') . " $folderdb ($!)");

   return @keys;
}

sub get_messageids_sorted_by_offset_db {
   # same as above, only no DBM open close
   my $r_FDB = shift;

   my %ids     = ();
   my %offsets = ();

   # %FDB is a hash of messageids pointing to multi-line strings like:
   # '<000e01c72c17$92dcc3c0$7d7b0b3e@venus>' => '283933767
   # 5175
   # 3272
   # <IO<CE><E9>ef=(<C0><91><D9>Y<EA>qE
   # 20061230133722
   # 20061201133654
   # "Sampei02" <sampei02@tiscali.it>
   # <sendmail-milter-users@lists.sourceforge.net>
   # [Sendmail-milter-users] two milter filters ?
   # text/plain; charset="us-ascii"
   # us-ascii
   # RO
   # ',
   while (my ($key,$data) = each(%{$r_FDB})) {
      unless (exists $is_internal_dbkey{$key} && $is_internal_dbkey{$key}) {
         my $offset = (string2msgattr($data))[$_OFFSET];

         openwebmailerror(gettext('Two messages have the same offset in the spool database:') . " $main::folder :: $key :: $offsets{$offset}")
            if exists $offsets{$offset} && $key !~ m/^DUP/ && $offsets{$offset} !~ m/^DUP/;

         $offsets{$offset} = $key;
         $ids{$key}        = $offset;
      }
   }

   my @ids_sorted = sort { $ids{$a} <=> $ids{$b} } keys %ids;

   return @ids_sorted;
}

sub get_msgid2attrs {
   my ($folderdb, $ignore_internal, @attrnums) = @_;

   my %msgid2attr = ();
   my %FDB        = ();
   my $total      = 0;

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
      openwebmailerror(gettext('Cannot open db:') . " $folderdb ($!)");

   while (my($key, $data) = each(%FDB)) {
      next if exists $is_internal_dbkey{$key} && $is_internal_dbkey{$key};
      my @attr = string2msgattr($data);
      next if defined $attr[$_STATUS] && $attr[$_STATUS] =~ m/Z/i;
      next if $ignore_internal && is_internal_subject($attr[$_SUBJECT]);
      $total++;
      my @attr2 = @attr[@attrnums];
      $msgid2attr{$key} = \@attr2;
   }

   ow::dbm::closedb(\%FDB, $folderdb) or
      openwebmailerror(gettext('Cannot close db:') . " $folderdb ($!)");

   return($total, \%msgid2attr);
}

sub get_message_attributes {
   # given a message id and database, open the database and convert
   # the stored message attributes into an array
   my ($messageid, $folderdb) = @_;

   my @attr = ();
   my %FDB  = ();

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
      openwebmailerror(gettext('Cannot open db:') . " $folderdb ($!)");

   @attr = string2msgattr($FDB{$messageid});

   ow::dbm::closedb(\%FDB, $folderdb) or
      openwebmailerror(gettext('Cannot close db:') . " $folderdb ($!)");

   return @attr;
}

sub get_message_header {
   # given a message id, database, and mail spool filehandle, read the header from
   # the mail spool using the byte range stored in the database and return its size
   # this can be used as a checkpoint to verify consistency between the db and mail spool
   # -1: message id not in database
   # -2: invalid header size in database
   # -3: header size mismatch read error
   # -4: header start and end does not match index
   my ($messageid, $folderdb, $folderhandle, $r_buff) = @_;

   my @attr = get_message_attributes($messageid, $folderdb);

   if (scalar @attr == 0) {
      writelog("message $messageid not found in db $folderdb");
      return -1;
   }

   if ($attr[$_HEADERSIZE] < 0 || $attr[$_SIZE] <= $attr[$_HEADERSIZE]) {
      writelog("header size $attr[$_HEADERSIZE] for message $messageid in db $folderdb is invalid");
      return -2;
   }

   seek($folderhandle, $attr[$_OFFSET], 0);

   my $size = read($folderhandle, ${$r_buff}, $attr[$_HEADERSIZE]);

   if ($size !=  $attr[$_HEADERSIZE]) {
      writelog("message $messageid in db $folderdb header read error, headersize=$attr[$_HEADERSIZE], read=$size");
      return -3;
   }

   if (substr(${$r_buff}, 0, 5) ne 'From ' || substr(${$r_buff}, $size - 1, 1) ne "\n") {
      # message header should end with a \n
      writelog("header start and end does not match db index for message $messageid in db $folderdb");
      return -4;
   }

   return $size;
}

sub get_message_block {
   # given a message id, database, and mail spool filehandle, read the message from
   # the mail spool using the byte range stored in the database and return its size
   # this can be used as a checkpoint to verify consistency between the db and mail spool
   # -1: message id not in database
   # -2: invalid message size in database
   # -3: message size mismatch read error
   # -4: message start and end does not match index
   my ($messageid, $folderdb, $folderhandle, $r_buff) = @_;

   my @attr = get_message_attributes($messageid, $folderdb);

   if (scalar @attr == 0) {
      writelog("message $messageid not found in db $folderdb");
      return -1;
   }

   if ($attr[$_SIZE] <= 0) {
      writelog(ow::tool::stacktrace("message size $attr[$_SIZE] for message $messageid in db $folderdb is invalid"));
      return -2;
   }

   seek($folderhandle, $attr[$_OFFSET], 0);

   my $size = read($folderhandle, ${$r_buff}, $attr[$_SIZE]);

   if ($size != $attr[$_SIZE]) {
      writelog("message $messageid in db $folderdb read error, messagesize=$attr[$_SIZE], read=$size");
      return -3;
   }

   if (substr(${$r_buff}, 0, 5) ne 'From ' || substr(${$r_buff}, $size - 1, 1) ne "\n") {
      # message should end with a \n
      writelog("message start and end does not match db index for message $messageid in db $folderdb");
      return -4;
   }

   return $size;
}

sub update_message_status {
   # -1: update index error
   # -2: cannot open database
   # -3: cannot open folderfile
   # -4: header start does not match index db header start
   # -5: io error
   my ($messageid, $status, $folderdb, $folderfile) = @_;

   $status = '' unless defined $status && $status;

   if (update_folderindex($folderfile, $folderdb) < 0) {
      writelog("db error - cannot update index db $folderdb");
      writehistory("db error - cannot update index db $folderdb");
      return -1;
   }

   my %FDB = ();

   if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX)) {
      writelog("cannot open db $folderdb");
      return -2;
   }

   my @messageids   = get_messageids_sorted_by_offset_db(\%FDB);
   my @attr         = ();
   my $movement     = 0;
   my $folderhandle = do { no warnings 'once'; local *FH };

   if (!sysopen($folderhandle, $folderfile, O_RDWR)) {
      writelog("cannot open file $folderfile");
      ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");
      return -3;
   }

   my $ioerr = 0;
   my $i     = 0;

   for ($i = 0; $i <= $#messageids; $i++) {
      if ($messageids[$i] eq $messageid) {
         @attr = string2msgattr($FDB{$messageid}) if defined $FDB{$messageid};

         my $messagestart = $attr[$_OFFSET];
         my $headerlen    = $attr[$_HEADERSIZE];
         my $headerend    = $messagestart + $headerlen;

         my $header = '';
         seek ($folderhandle, $messagestart, 0);
         read ($folderhandle, $header, $headerlen); # header ends with one \n

         if ($header !~ m/^From /) {
            # index not consistent with folder content
            close($folderhandle) or writelog("cannot close file $folderfile");

            writelog("db warning - msg $messageid in $folderfile header start does not match db header start - forcing reindex");
            writehistory("db warning - msg $messageid in $folderfile header start does not match db header start - forcing reindex");

            $FDB{METAINFO} = 'ERR';
            $FDB{LSTMTIME} = -1;

            ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

            # forced reindex since metainfo = ERR
            update_folderindex($folderfile, $folderdb);

            return -4;
         }

         last if $attr[$_STATUS] eq $status;

         # update status, flags from rfc2076
         my $status_update = '';

         if ($status =~ m/[RO]/i) {
            $status_update .= 'R' if $status =~ m/R/i; # Read
            $status_update .= 'O' if $status =~ m/O/i; # Old
         } else {
            $status_update .= 'N' if $status =~ m/N/i; # New
            $status_update .= 'U' if $status =~ m/U/i; # still Undownloaded & Undeleted
         }

         $status_update .= 'D' if $status =~ m/D/i;    # to be Deleted

         if ($status_update ne '') {
            if (!($header =~ s/^status:.*\n/Status: $status_update\n/im)) {
               $header .= "Status: $status_update\n";
            }
         } else {
            $header =~ s/^status:.*\n//im;
         }

	 # update x-status
         $status_update = '';
         $status_update .= 'A' if $status =~ m/A/i; # Answered
         $status_update .= 'I' if $status =~ m/I/i; # Important
         $status_update .= 'D' if $status =~ m/D/i; # to be Deleted

         if ($status_update ne '') {
            if (!($header =~ s/^x-status:.*\n/X-Status: $status_update\n/im)) {
               $header .= "X-Status: $status_update\n";
            }
         } else {
            $header =~ s/^x-status:.*\n//im;
         }

         my $newheaderlen = length($header);
         $movement = ow::tool::untaint($newheaderlen - $headerlen);

         my $foldersize = (stat($folderhandle))[7];
         if (shiftblock($folderhandle, $headerend, $foldersize - $headerend, $movement) < 0) {
            writelog("data error - message $messageids[$i] in $folderfile shiftblock failed");
            writehistory("data error - message $messageids[$i] in $folderfile shiftblock failed");
            $ioerr++;
         }

         if (!$ioerr) {
            seek($folderhandle, $messagestart, 0);
            print $folderhandle $header or $ioerr++;
         }

         if (!$ioerr) {
            truncate($folderhandle, ow::tool::untaint($foldersize + $movement)) or
               writelog("truncate failed on folder $folderfile");

            if ($status =~ m/Z/i) {
               $FDB{ZAPSIZE} += $movement;
            } elsif (is_internal_subject($attr[$_SUBJECT])) {
               $FDB{INTERNALSIZE} += $movement;
            } else {
               # okay, this is a nozapped, noninternal message
               # set attributes in folderdb for this status changed message
               if ($attr[$_STATUS] !~ m/R/i && $status =~ m/R/i) {
                  $FDB{NEWMESSAGES}--;
                  $FDB{NEWMESSAGES} = 0 if $FDB{NEWMESSAGES} < 0;
               } elsif ($attr[$_STATUS] =~ m/R/i && $status !~ m/R/i) {
                  $FDB{NEWMESSAGES}++;
               }
            }

            $attr[$_SIZE]        += $movement;
            $attr[$_STATUS]       = $status;
            $attr[$_HEADERCHKSUM] = ow::tool::calc_checksum(\$header);
            $attr[$_HEADERSIZE]   = $newheaderlen;
            $FDB{$messageid}      = msgattr2string(@attr);
         }

         last;
      }
   }

   close($folderhandle) or writelog("cannot close file $folderfile");

   writelog("db warning - message $messageid in $folderfile index missing") if $i > $#messageids;

   # if size of this message is changed
   if ($movement != 0 && !$ioerr) {
      # change offset attr for messages after the above one
      for ($i = $i + 1; $i <= $#messageids; $i++) {
         @attr = string2msgattr($FDB{$messageids[$i]});
         $attr[$_OFFSET] += $movement;
         $FDB{$messageids[$i]} = msgattr2string(@attr);
      }
   }

   # update folder metainfo
   $FDB{METAINFO} = ow::tool::metainfo($folderfile) unless $ioerr;

   ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

   return ($ioerr ? -5 : 0);
}

sub operate_message_with_ids {
   # operate messages with @messageids from src folderfile to dst folderfile
   # available $op: "move", "copy", "delete"

   #  0: no message ids to process
   # -1: cannot update db
   # -2: cannot open source file
   # -3: cannot open source db
   # -4: cannot update destination index db
   # -5: cannot open destination file
   # -6: cannot open destination db
   # -7: message $messageid in $srcfile index inconsistence
   # -8: cannot write to destination

   my ($op, $r_messageids, $srcfile, $srcdb, $dstfile, $dstdb) = @_;

   openwebmailerror(gettext('Invalid message operation:') . " ($op)")
     if $op ne 'move' && $op ne 'copy' && $op ne 'delete';

   return 0 if (defined $srcfile && defined $dstfile && $srcfile eq $dstfile) || scalar @{$r_messageids} == 0;

   my %SRCDB = ();
   my %DSTDB = ();

   if (update_folderindex($srcfile, $srcdb) < 0) {
      writelog("db error - cannot update index db $srcdb");
      return -1;
   }

   my $srchandle = do { no warnings 'once'; local *FH };

   if (!sysopen($srchandle, $srcfile, O_RDONLY)) {
      writelog("cannot open source file $srcfile ($!)");
      return -2;
   }

   if (!ow::dbm::opendb(\%SRCDB, $srcdb, LOCK_EX)) {
      writelog("cannot open source db $srcdb ($!)");
      return -3;
   }

   my $dsthandle = do { no warnings 'once'; local *FH };
   my $dstlength = 0;
   my $readlen   = 0;

   if ($op eq 'move' || $op eq 'copy') {
      if (update_folderindex($dstfile, $dstdb) < 0) {
         ow::dbm::closedb(\%SRCDB, $srcdb) or writelog("cannot close db $srcdb");

         close($srchandle) or writelog("cannot close file $srcfile");

         writelog("db error - cannot update index db $dstdb");

         return -4;
      }

      if (!sysopen($dsthandle, $dstfile, O_WRONLY|O_APPEND|O_CREAT)) {
         writelog("cannot open destination file $dstfile ($!)");

         ow::dbm::closedb(\%SRCDB, $srcdb) or writelog("cannot close db $srcdb");

         close($srchandle) or writelog("cannot close file $srcfile");

         return -5;
      }

      $dstlength = (stat($dsthandle))[7];

      if (!ow::dbm::opendb(\%DSTDB,$dstdb, LOCK_EX)) {
         writelog("db error - cannot open db $dstdb");

         close($dsthandle) or writelog("cannot close file $dstfile");

         ow::dbm::closedb(\%SRCDB, $srcdb) or writelog("cannot close db $srcdb");

         close($srchandle) or writelog("cannot close file $srcfile");

         return -6;
      }
   }

   my $counted = 0;

   foreach my $messageid (@{$r_messageids}) {
      next unless defined $SRCDB{$messageid};

      my @attr = string2msgattr($SRCDB{$messageid});

      if (!is_msgattr_consistent_with_folder(\@attr, $srchandle)) {
         # index is not consistent with folder content
         writelog("db warning - message $messageid in $srcfile index inconsistence");

         close($srchandle) or writelog("cannot close file $srcfile");

         $SRCDB{METAINFO} = 'ERR';
         $SRCDB{LSTMTIME} = -1;

         ow::dbm::closedb(\%SRCDB, $srcdb) or writelog("cannot close db $srcdb");

         # forced reindex since metainfo = ERR
         update_folderindex($srcfile, $srcdb);

         if ($op eq 'move' || $op eq 'copy') {
            close($dsthandle) or writelog("cannot close file $dstfile");

            $DSTDB{METAINFO} = 'ERR';
            $DSTDB{LSTMTIME} = -1;

            ow::dbm::closedb(\%DSTDB,$dstdb) or writelog("cannot close db $dstdb");

            # ensure other messages cp/mv to dst are correctly indexed
            update_folderindex($dsthandle, $dstdb) if $counted;
         }

         return -7;
      }

      $counted++;

      # append message to dst folder only if op=move/copy and message does not exist in dstfile
      if ($op eq 'move' || $op eq 'copy') {
         _mark_duplicated_messageid(\%DSTDB, $messageid, $attr[$_SIZE]) if defined $DSTDB{$messageid};

         if (!defined $DSTDB{$messageid}) {
            # cp message from $srchandle to $dsthandle
            # since @attr will be used for DSTDB temporarily and $attr[$_OFFSET] will be modified
            # we save it in $srcoffset and copy it back after write of dst folder
            my $srcoffset = $attr[$_OFFSET];

            seek($srchandle, $srcoffset, 0);

            my $buff = '';
            my $left = $attr[$_SIZE];

            while ($left > 0) {
               my $dstioerr = 0;

               if ($left > $BUFF_blocksize) {
                  read($srchandle, $buff,  $BUFF_blocksize);
               } else {
                  read($srchandle, $buff, $left);
               }

               print $dsthandle $buff or $dstioerr = 1;

               if ($dstioerr) {
                  writelog("data error - cannot write $dstfile ($!)");

                  close($srchandle) or writelog("cannot close file $srcfile");

                  ow::dbm::closedb(\%SRCDB, $srcdb) or writelog("cannot close db $srcdb");

                  # cut at last successful write
                  truncate($dsthandle, ow::tool::untaint($dstlength));

                  close($dsthandle) or writelog("cannot close file $dstfile");

                  $DSTDB{METAINFO} = 'ERR';
                  $DSTDB{LSTMTIME} = -1;

                  ow::dbm::closedb(\%DSTDB, $dstdb) or writelog("cannot close db $dstdb");

                  return -8;
               }

               $left -= $BUFF_blocksize;
            }

            $DSTDB{ALLMESSAGES}++;

            if ($attr[$_STATUS] =~ m/Z/i) {
               $DSTDB{ZAPMESSAGES}++;
               $DSTDB{ZAPSIZE} += $attr[$_SIZE];
            } elsif (is_internal_subject($attr[$_SUBJECT])) {
               $DSTDB{INTERNALMESSAGES}++;
               $DSTDB{INTERNALSIZE} += $attr[$_SIZE];
            } elsif ($attr[$_STATUS] !~ m/R/i) {
               $DSTDB{NEWMESSAGES}++;
            }

            $attr[$_OFFSET] = $dstlength;
            $dstlength += $attr[$_SIZE];
            $DSTDB{$messageid} = msgattr2string(@attr);
            $attr[$_OFFSET] = $srcoffset;
         }
      }

      if (($op eq 'move' || $op eq 'delete') && $attr[$_STATUS] !~ m/Z/i) {
         $attr[$_STATUS] .= 'Z'; # to be zapped in the future

         $SRCDB{ZAPMESSAGES}++;
         $SRCDB{ZAPSIZE} += $attr[$_SIZE];

         if (is_internal_subject($attr[$_SUBJECT])) {
            $SRCDB{INTERNALMESSAGES}--;
            $SRCDB{INTERNALSIZE} -= $attr[$_SIZE];
         } elsif ($attr[$_STATUS] !~ m/R/i) {
            $SRCDB{NEWMESSAGES}--;
         }

         $SRCDB{$messageid} = msgattr2string(@attr); # $attr[$_OFFSET] is used here
      }
   }

   if ($op eq 'move' || $op eq 'copy') {
      close($dsthandle) or writelog("cannot close file $dstfile");

      $DSTDB{METAINFO} = ow::tool::metainfo($dstfile);
      $DSTDB{LSTMTIME} = time();

      ow::dbm::closedb(\%DSTDB, $dstdb) or writelog("cannot close db $dstdb");
   }

   close($srchandle) or writelog("cannot close file $srcfile");

   ow::dbm::closedb(\%SRCDB, $srcdb) or writelog("cannot close db $srcdb");

   return $counted;
}

sub append_message_to_folder {
   #  0: no errors
   # -1: cannot update index db
   # -2: cannot open db
   # -3: cannot open dstfile
   # -4: cannot close db
   # -5: io error printing to dstfile
   my ($messageid, $r_attr, $r_message, $dstfile, $dstdb) = @_;

   writelog("debug_mailprocess :: $dstfile :: append_message_to_folder") if $config{debug_mailprocess};

   my %FDB   = ();
   my @attr  = @{$r_attr};
   my $ioerr = 0;

   if (update_folderindex($dstfile, $dstdb) < 0) {
      writelog("cannot update index db $dstdb");
      ow::filelock::lock($dstfile, LOCK_UN) or writelog("cannot unlock file $dstfile");
      return -1;
   }

   if (!ow::dbm::opendb(\%FDB, $dstdb, LOCK_EX)) {
      writelog("cannot open db $dstdb");
      return -2;
   }

   _mark_duplicated_messageid(\%FDB, $messageid, $attr[$_SIZE]) if defined $FDB{$messageid};

   if (!defined $FDB{$messageid}) {
      # append only if not found in dstfile
      if (!sysopen(DEST, $dstfile, O_RDWR)) {
         writelog("cannot open file $dstfile ($!)");
         ow::dbm::closedb(\%FDB, $dstdb) or writelog("cannot close db $dstdb");
         return -3;
      }

      $attr[$_OFFSET] = (stat(DEST))[7];

      if (!defined $attr[$_OFFSET]) {
         writelog("cannot stat DEST filehandle");
         openwebmail_exit(1);
      }

      seek(DEST, $attr[$_OFFSET], 0);

      $attr[$_SIZE] = length(${$r_message});

      if ($attr[$_SIZE] < 5) {
         writelog("illegal message size :: messageid $messageid size $attr[$_SIZE]");
         openwebmail_exit(1);
      }

      print DEST ${$r_message} or $ioerr++;

      close(DEST) or writelog("cannot close file $dstfile");

      if (!$ioerr) {
         $FDB{$messageid} = msgattr2string(@attr);

         if (is_internal_subject($attr[$_SUBJECT])) {
            $FDB{INTERNALMESSAGES}++;
            $FDB{INTERNALSIZE} += $attr[$_SIZE];
         } elsif ($attr[$_STATUS] !~ m/R/i) {
            $FDB{NEWMESSAGES}++;
         }

         $FDB{ALLMESSAGES}++;
         $FDB{METAINFO} = ow::tool::metainfo($dstfile);
         $FDB{LSTMTIME} = time();
      }
   }

   if (!ow::dbm::closedb(\%FDB, $dstdb)) {
      writelog("cannot close db $dstdb");
      return -4;
   }

   if ($ioerr) {
      writelog("io error printing to file $dstfile");
      return -5;
   }

   return 0;
}

sub _mark_duplicated_messageid {
   my ($r_FDB, $messageid, $newmsgsize) = @_;

   my @attr = string2msgattr($r_FDB->{$messageid});

   writelog("debug_mailprocess :: _mark_duplicated_messageid") if $config{debug_mailprocess};

   if ($attr[$_SIZE] eq $newmsgsize) {
      # skip because new message is same size as existing one
      if ($attr[$_STATUS] =~ s/Z//ig) {
         # undelete if the one in dest is zapped
         $r_FDB->{$messageid} = msgattr2string(@attr);
         $r_FDB->{ZAPMESSAGES}--;
         $r_FDB->{ZAPSIZE} -= $attr[$_SIZE];

         if (is_internal_subject($attr[$_SUBJECT])) {
            $r_FDB->{INTERNALMESSAGES}++;
            $r_FDB->{INTERNALSIZE} += $attr[$_SIZE];
         } elsif ($attr[$_STATUS] !~ m/R/i) {
            $r_FDB->{NEWMESSAGES}++;
         }
      }
   } else {
      if ($attr[$_STATUS] !~ m/Z/i) {
         # mark old duplicated one as zap
         $attr[$_STATUS] .= 'Z';
         $r_FDB->{ZAPMESSAGES}++;
         $r_FDB->{ZAPSIZE} += $attr[$_SIZE];

         if (is_internal_subject($attr[$_SUBJECT])) {
            $r_FDB->{INTERNALMESSAGES}--;
            $r_FDB->{INTERNALSIZE} -= $attr[$_SIZE];
         } elsif ($attr[$_STATUS] !~ m/R/i) {
            $r_FDB->{NEWMESSAGES}--;
         }
      }

      writelog("debug_mailprocess :: marking message as DUP - messageid $messageid") if $config{debug_mailprocess};

      # mark message as DUP
      $r_FDB->{"DUP$attr[$_OFFSET]-$messageid"} = msgattr2string(@attr); # NOT a subtraction, but a dash

      delete $r_FDB->{$messageid};
   }

   return;
}

sub folder_zapmessages {
   # returns number of zapped messages, or else error code
   # -1: cannot update index db srcdb
   # -2: cannot open db srcdb
   # -3: cannot close db srcdb
   # -4: cannot open file srcfile
   # -5: index inconsistence
   # -6: io error shiftblock failed
   my ($srcfile, $srcdb) = @_;

   my %FDB   = ();
   my $ioerr = 0;

   if (update_folderindex($srcfile, $srcdb) < 0) {
      writelog("db error - cannot update index db $srcdb");
      writehistory("db error - cannot update index db $srcdb");
      return -1;
   }

   if(!ow::dbm::opendb(\%FDB, $srcdb, LOCK_SH)) {
      writelog("cannot open db $srcdb");
      return -2;
   }

   if($FDB{ZAPSIZE} == 0) {
      # no messages to zap in folder
      if (!ow::dbm::closedb(\%FDB, $srcdb)) {
         writelog("cannot close db $srcdb");
         return -3;
      }

      return 0;
   }

   my $folderhandle = do { no warnings 'once'; local *FH };

   if (!sysopen($folderhandle, $srcfile, O_RDWR)) {
      writelog("cannot open file $srcfile");
      ow::dbm::closedb(\%FDB, $srcdb) or writelog("cannot close db $srcdb");
      return -4;
   }

   my @allmessageids = get_messageids_sorted_by_offset_db(\%FDB);

   my $blockstart   = 0;
   my $blockend     = 0;
   my $writepointer = 0;
   my $counted      = 0;

   for (my $i = 0; $i <= $#allmessageids; $i++) {
      my $messageid = $allmessageids[$i];

      my @attr = string2msgattr($FDB{$messageid});

      if (!is_msgattr_consistent_with_folder(\@attr, $folderhandle)) {
         # index not consistent with folder content
         writelog("db warning - message $messageid in $srcfile index inconsistence");
         writehistory("db warning - message $messageid in $srcfile index inconsistence");

         $FDB{METAINFO} = 'ERR';
         $FDB{LSTMTIME} = -1;

         ow::dbm::closedb(\%FDB, $srcdb) or writelog("cannot close db $srcdb");

         close($folderhandle) or writelog("cannot close file $srcfile");

         return -5;
      }

      my $nextstart = ow::tool::untaint($attr[$_OFFSET] + $attr[$_SIZE]);

      if ($attr[$_STATUS] =~ m/Z/i) {
         $counted++;

         if (shiftblock($folderhandle, $blockstart, $blockend - $blockstart, $writepointer - $blockstart) < 0) {
            writelog("data error - message $messageid in $srcfile shiftblock failed ($!)");
            writehistory("data error - message $messageid in $srcfile shiftblock failed ($!)");
            $ioerr++;
         } else {
            $writepointer = $writepointer + ($blockend - $blockstart);
            $blockstart = $blockend = $nextstart;
         }

         if (!$ioerr) {
            $FDB{ALLMESSAGES}--;
            $FDB{ZAPMESSAGES}--;
            $FDB{ZAPSIZE} -= $attr[$_SIZE];
            delete $FDB{$messageid};
         }
      } else {
         # message to be kept in same folder
         $blockend = $nextstart;
         my $movement = $writepointer - $blockstart;

         if ($movement < 0) {
            $attr[$_OFFSET] += $movement;
            $FDB{$messageid} = msgattr2string(@attr);
         }
      }

      last if $ioerr;
   }

   if ($counted > 0 && !$ioerr) {
      if (shiftblock($folderhandle, $blockstart, $blockend - $blockstart, $writepointer - $blockstart) < 0) {
         writelog("data error - messages in $srcfile shiftblock failed ($!)");
         writehistory("data error - messages in $srcfile shiftblock failed ($!)");
         $ioerr++;
      } else {
         truncate($folderhandle, ow::tool::untaint($writepointer+$blockend-$blockstart));
      }
   }

   close($folderhandle) or writelog("cannot close file $srcfile");

   if (!$ioerr) {
      foreach (qw(ALLMESSAGES NEWMESSAGES INTERNALMESSAGES INTERNALSIZE ZAPMESSAGES ZAPSIZE)) {
         $FDB{$_} = 0 if $FDB{$_} < 0; # should not happen
      }

      $FDB{METAINFO} = ow::tool::metainfo($srcfile);
      $FDB{LSTMTIME} = time();
   } else {
      $FDB{METAINFO} = 'ERR';
      $FDB{LSTMTIME} = -1;
   }

   ow::dbm::closedb(\%FDB, $srcdb) or writelog("cannot close db $srcdb");

   return -6 if $ioerr;

   return $counted;
}

sub delete_message_by_age {
   # use receiveddate instead of sentdate for age calculation
   # -1: cannot open db
   my ($dayage, $folderdb, $folderfile) = @_;
   return 0 unless -f $folderfile;

   my %FDB           = ();
   my @allmessageids = ();
   my @agedids       = ();

   if (update_folderindex($folderfile, $folderdb) < 0) {
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile ($!)");
      writelog("db error - cannot update index db $folderdb");
      writehistory("db error - cannot update index db $folderdb");
      return 0;
   }

   my $agestarttime = time() - $dayage * 86400;

   if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX)) {
      writelog("cannot open db $folderdb");
      return -1;
   }

   while (my ($key, $data) = each(%FDB)) {
      my @attr = string2msgattr($data);
      push(@agedids, $key) if ow::datetime::dateserial2gmtime($attr[$_RECVDATE]) <= $agestarttime; # too old
   }

   ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

   return 0 if scalar @agedids == 0;

   my $deleted = operate_message_with_ids('delete', \@agedids, $folderfile, $folderdb);
   my $zapped  = folder_zapmessages($folderfile, $folderdb);

   return $zapped if $deleted < 0;

   return $deleted;
}

sub move_oldmsg_from_folder {
   # -1: cannot open db
   my ($srcfile, $srcdb, $dstfile, $dstdb) = @_;

   my %FDB        = ();
   my @messageids = ();

   if (!ow::dbm::opendb(\%FDB, $srcdb, LOCK_SH)) {
      writelog("cannot open db $srcdb");
      return -1;
   }

   # if oldmsg == internal msg or 0, then do not read ids
   my $oldmessages = $FDB{ALLMESSAGES} - $FDB{NEWMESSAGES} - $FDB{INTERNALMESSAGES} - $FDB{ZAPMESSAGES};

   if ($oldmessages > 0) {
      while (my ($key, $data) = each(%FDB)) {
         next if $is_internal_dbkey{$key};

         my @attr = string2msgattr($data);

         push(@messageids, $key) if $attr[$_STATUS] =~ m/R/i && $attr[$_STATUS] !~ m/Z/i && !is_internal_subject($attr[$_SUBJECT]);
      }
   }

   ow::dbm::closedb(\%FDB, $srcdb) or writelog("cannot close db $srcdb");

   # no old msg found
   return 0 if scalar @messageids == 0;

   my $moved  = operate_message_with_ids('move', \@messageids, $srcfile, $srcdb, $dstfile, $dstdb);
   my $zapped = folder_zapmessages($srcfile, $srcdb);

   return $zapped if $moved < 0;

   return $moved;
}

sub rebuild_message_with_partialid {
   # rebuild original message with partial messages in the same folder
   #  -1: cannot update index db
   #  -2: cannot open db folderdb
   #  -3: rebuild partial message failed - last part not found
   #  -4: rebuild partial message part $i missing
   #  -5: cannot make tempdir $tmpdir
   #  -6: cannot lock tmpfile $tmpfile
   #  -7: cannot open file $tmpfile
   #  -8: cannot open file $foldefile
   #  -9: cannot update index db $tmpdb
   # -10: incorrect count of rebuild message ids
   # -11: rebuild message size does not equal written message size
   my ($folderfile, $folderdb, $partialid) = @_;

   my %FDB           = ();
   my $partialtotal  = 0;
   my @partialmsgids = ();
   my @offset        = 0;
   my @size          = 0;

   if (update_folderindex($folderfile, $folderdb) < 0) {
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot lock file $folderfile");
      writelog("db error - cannot update index db $folderdb");
      writehistory("db error - cannot update index db $folderdb");
      return -1;
   }

   # find all partial msgids
   if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH)) {
      writelog("cannot open db $folderdb");
      return -2;
   }

   while (my ($id,$data) = each(%FDB)) {
      next if exists $is_internal_dbkey{$id} && $is_internal_dbkey{$id};

      my @attr = string2msgattr($data);

      next if $attr[$_CONTENT_TYPE] !~ m/^message\/partial/i;

      $attr[$_CONTENT_TYPE] =~ m/;\s*id="(.+?)";?/i;

      next if $partialid ne $1;

      if ($attr[$_CONTENT_TYPE] =~ m/;\s*number="?(.+?)"?;?/i) {
         my $n = $1;
         $partialmsgids[$n] = $id;
         $offset[$n] = $attr[$_OFFSET];
         $size[$n] = $attr[$_SIZE];
         $partialtotal = $1 if $attr[$_CONTENT_TYPE] =~ m/;\s*total="?(.+?)"?;?/i;
      }
   }

   ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

   # check completeness
   if ($partialtotal < 1) {
      # last part not found
      writelog("rebuild partial message failed - last part not found");
      return -3;
   }

   for (my $i = 1; $i <= $partialtotal; $i++) {
      if ($partialmsgids[$i] eq '') {
         # some part missing
         writelog("rebuild partial message part $i missing");
         return -4;
      }
   }

   my $tmpdir = ow::tool::mktmpdir("rebuild.tmp");
   if ($tmpdir eq '') {
      writelog("cannot make tempdir $tmpdir");
      return -5;
   }

   my $tmpfile = ow::tool::untaint("$tmpdir/folder");

   my $tmpdb   = ow::tool::untaint("$tmpdir/db");

   if (!ow::filelock::lock($tmpfile, LOCK_EX)) {
      writelog("cannot lock tmpfile $tmpfile");
      rmdir($tmpdir);
      return -6;
   }

   if (!sysopen(TMP, $tmpfile, O_WRONLY|O_TRUNC|O_CREAT)) {
      writelog("cannot open file $tmpfile ($!)");
      ow::filelock::lock($tmpfile, LOCK_UN) or writelog("cannot unlock file $tmpfile");
      return -7;
   }

   if (!sysopen(FOLDER, $folderfile, O_RDONLY)) {
      writelog("cannot open file $folderfile ($!)");
      close(TMP) or writelog("cannot close file $tmpfile");
      ow::filelock::lock($tmpfile, LOCK_UN) or writelog("cannot unlock file $tmpfile");
      return -8;
   }

   seek(FOLDER, $offset[1], 0);

   my $line = <FOLDER>;
   my $writtensize = length($line);

   print TMP $line; # copy delimiter line from 1st partial message

   for (my $i = 1; $i <= $partialtotal; $i++) {
      my $currsize = 0;
      seek(FOLDER, $offset[$i], 0);

      # skip header of the partial message
      while (defined($line = <FOLDER>)) {
         $currsize += length($line);
         last if $line =~ m/^\r*$/;
      }

      # read body of the partial message and copy to tmpfile
      while (defined($line = <FOLDER>)) {
         $currsize += length($line);
         $writtensize += length($line);
         print TMP $line;
         last if $currsize >= $size[$i];
      }
   }

   close(TMP) or writelog("cannot close file $tmpfile ($!)");
   close(FOLDER) or writelog("cannot close file $folderfile ($!)");

   # index tmpfile, get the msgid
   if (update_folderindex($tmpfile, $tmpdb) < 0) {
      writelog("db error - cannot update index db $tmpdb");
      ow::filelock::lock($tmpfile, LOCK_UN) or writelog("cannot unlock file $tmpfile");
      unlink($tmpfile);
      ow::dbm::unlinkdb($tmpdb);
      rmdir($tmpdir);
      return -9;
   }

   # check the rebuild integrity
   my @rebuildmsgids = get_messageids_sorted_by_offset($tmpdb);

   if ($#rebuildmsgids != 0) {
      writelog("incorrect count of rebuild message ids ($#rebuildmsgids)");
      ow::filelock::lock($tmpfile, LOCK_UN) or writelog("cannot unlock file $tmpfile");
      unlink($tmpfile);
      ow::dbm::unlinkdb($tmpdb);
      rmdir($tmpdir);
      return -10;
   }

   my $rebuildsize = (get_message_attributes($rebuildmsgids[0], $tmpdb))[$_SIZE];

   if ($writtensize != $rebuildsize) {
      writelog("rebuild message size does not equal written message size");
      ow::filelock::lock($tmpfile, LOCK_UN) or writelog("cannot unlock file $tmpfile");
      unlink($tmpfile);
      ow::dbm::unlinkdb($tmpdb);
      rmdir($tmpdir);
      return -11;
   }

   operate_message_with_ids('move', \@rebuildmsgids, $tmpfile, $tmpdb, $folderfile, $folderdb);

   ow::filelock::lock($tmpfile, LOCK_UN) or writelog("cannot unlock file $tmpfile");
   unlink($tmpfile);
   ow::dbm::unlinkdb($tmpdb);
   rmdir($tmpdir);

   return (0, $rebuildmsgids[0], @partialmsgids);
}

sub shiftblock {
   my ($fh, $start, $size, $movement) = @_;

   return 0 if $movement == 0;

   my $movestart = 0;
   my $buff      = '';
   my $ioerr     = 0;
   my $left      = $size;

   if ($movement > 0) {
      while ($left > $BUFF_blocksize && !$ioerr) {
          $movestart = $start + $left - $BUFF_blocksize;
          seek($fh, $movestart, 0);
          read($fh, $buff, $BUFF_blocksize);
          seek($fh, $movestart + $movement, 0);
          print $fh $buff or $ioerr++;
          $left = $left - $BUFF_blocksize;
      }

      if (!$ioerr) {
         seek($fh, $start, 0);
         read($fh, $buff, $left);
         seek($fh, $start + $movement, 0);
         print $fh $buff or $ioerr++;
      }

   } elsif ($movement < 0) {
      while ($left > $BUFF_blocksize && !$ioerr) {
         $movestart = $start + $size - $left;
         seek($fh, $movestart, 0);
         read($fh, $buff, $BUFF_blocksize);
         seek($fh, $movestart + $movement, 0);
         print $fh $buff or $ioerr++;
         $left = $left - $BUFF_blocksize;
      }

      if (!$ioerr) {
         $movestart = $start + $size - $left;
         seek($fh, $movestart, 0);
         read($fh, $buff, $left);
         seek($fh, $movestart + $movement, 0);
         print $fh $buff or $ioerr++;
      }
   }

   return -1 if $ioerr;

   return 1;
}

sub empty_folder {
   my ($folderfile, $folderdb) = @_;

   sysopen(F, $folderfile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(gettext('Cannot open file:') . " $folderfile ($!)");

   close(F) or
      openwebmailerror(gettext('Cannot close file:') . " $folderfile ($!)");

   if (ow::dbm::existdb($folderdb)) {
      ow::dbm::unlinkdb($folderdb) or
         openwebmailerror(gettext('Cannot delete db:') . " $folderdb ($!)");
   }

   return -2 if update_folderindex($folderfile, $folderdb) < 0;

   return 0;
}

sub msgattr2string {
   # we use \n as delimiter for attributes
   # since we assume max record len is 1024,
   # len(msgid) < 128, len(other fields) < 60, len(delimiter) = 10,
   # so len( from + to + subject + contenttype + references ) must < 826
   my @attr = @_;

   foreach my $attribute ($_OFFSET, $_SIZE, $_HEADERSIZE) {
      $attr[$attribute] = 0 unless defined $attr[$attribute];
   }

   foreach my $attribute ($_HEADERCHKSUM, $_RECVDATE, $_DATE, $_FROM, $_TO, $_SUBJECT, $_CONTENT_TYPE, $_CHARSET, $_STATUS, $_REFERENCES) {
      $attr[$attribute] = '' unless defined $attr[$attribute];
   }

   foreach my $attribute ($_FROM, $_TO, $_SUBJECT, $_CONTENT_TYPE, $_REFERENCES, $_CHARSET) {
      $attr[$attribute] =~ s/[\r\n]/ /sg;
   }

   writelog(ow::tool::stacktrace("message attributes error"))
     if $attr[$_OFFSET] < 0 || $attr[$_HEADERSIZE] <= 0 || $attr[$_SIZE] <= $attr[$_HEADERSIZE];

   my $value = join("\n", @attr);

   if (length $value > 800) {
      # truncate TO, SUBJECT, and REFERENCES attributes to 256 characters
      foreach my $i ($_TO, $_SUBJECT, $_REFERENCES) {
         $attr[$i] = substr($attr[$i],0,253) . '...' if length $attr[$i] > 256;
      }

      $value = join("\n", @attr);

      if (length $value > 800) {
         # truncate FROM, TO, SUBJECT, CONTENT_TYPE, and REFERENCES to 160 characters
         foreach my $p ($_FROM, $_TO, $_SUBJECT, $_CONTENT_TYPE, $_REFERENCES) {
            $attr[$p] = substr($attr[$p],0,157) . '...' if length $attr[$p] > 160;
         }

         $value = join("\n", @attr);
      }
   }

   return $value;
}

sub string2msgattr {
   my $string = shift;

   my @attr = defined $string ? split(/\n/, $string) : ();

   # $string should be like:
   # '283933767
   # 5175
   # 3272
   # <IO<CE><E9>ef=(<C0><91><D9>Y<EA>qE
   # 20061230133722
   # 20061201133654
   # "Sampei02" <sampei02@tiscali.it>
   # <sendmail-milter-users@lists.sourceforge.net>
   # [Sendmail-milter-users] two milter filters ?
   # text/plain; charset="us-ascii"
   # us-ascii
   # RO
   # <20050320225023.M10321@acatysmoof.com> <000b01c52f35$a8e9bd70$6602a8c0@typo> <20050322235332.M67567@acatysmoof.com>'

   $attr[$_OFFSET]       = 0 unless defined $attr[$_OFFSET];
   $attr[$_SIZE]         = 0 unless defined $attr[$_SIZE];
   $attr[$_HEADERSIZE]   = 0 unless defined $attr[$_HEADERSIZE];
   $attr[$_HEADERCHKSUM] = '' unless defined $attr[$_HEADERCHKSUM];
   $attr[$_RECVDATE]     = '' unless defined $attr[$_RECVDATE];
   $attr[$_DATE]         = '' unless defined $attr[$_DATE];
   $attr[$_FROM]         = '' unless defined $attr[$_FROM];
   $attr[$_TO]           = '' unless defined $attr[$_TO];
   $attr[$_SUBJECT]      = '' unless defined $attr[$_SUBJECT];
   $attr[$_CONTENT_TYPE] = '' unless defined $attr[$_CONTENT_TYPE];
   $attr[$_CHARSET]      = '' unless defined $attr[$_CHARSET];
   $attr[$_STATUS]       = '' unless defined $attr[$_STATUS];
   $attr[$_REFERENCES]   = '' unless defined $attr[$_REFERENCES];

   return @attr;
}

sub simpleheader {
   my $fullheader = shift;

   my $simpleheader        = '';
   my $lastline            = 'NONE';
   my $regex_simpleheaders = qr/^(?:from|reply-to|to|cc|date|subject):\s?/i;

   foreach my $line (split(/\n/, $fullheader)) {
      if ($line =~ m/^\s+/) {
         $simpleheader .= "$line\n" if $lastline eq 'HEADER';
      } elsif ($line =~ m/$regex_simpleheaders/) {
         $simpleheader .= "$line\n";
         $lastline = 'HEADER';
      } else {
         $lastline = 'NONE';
      }
   }

   return $simpleheader;
}

sub is_internal_subject {
   my $subject = shift;
   return 1 if $subject =~ m/(?:DON'T DELETE THIS MESSAGE|Message from mail server)/;
   return 0;
}

sub is_msgattr_consistent_with_folder {
   # check if a message is valid based on its attr
   my ($r_attr, $folderhandle) = @_;

   writelog("debug_mailprocess :: checking message attributes against spool file") if $config{debug_mailprocess};

   # fail if the db entry for this message is zeroed out or message not indexed yet
   return 0 if (
                  $r_attr->[$_OFFSET] < 0
                  || $r_attr->[$_HEADERSIZE] <= 0
                  || $r_attr->[$_SIZE] <= $r_attr->[$_HEADERSIZE]
               );

   my $buff = '';

   # fail if the first 5 bytes at the db offset are not the 'From ' message starter
   seek($folderhandle, $r_attr->[$_OFFSET], 0);
   read($folderhandle, $buff, 5);
   return 0 if $buff !~ m/^From /;

   # fail if the 5 bytes after the message are defined, but are not the next message 'From ' starter
   seek($folderhandle, $r_attr->[$_OFFSET] + $r_attr->[$_SIZE], 0);
   read($folderhandle, $buff, 5);
   return 0 if defined $buff && $buff ne '' && $buff !~ m/^From /;

   # the offset and size of this message seem to match what is in the db
   return 1;
}

sub buffer_readblock {
   # use buffered file reads to quickly scan through a mail file
   # read a new block from the file to the buffer
   # return the length of bytes read

   writelog("debug_maildb_buffer - buffer_readblock - BUFF_EOF=$BUFF_EOF BUFF_fileoffset=$BUFF_fileoffset BUFF_size=$BUFF_size BUFF_start=$BUFF_start") if $config{debug_maildb_buffer};

   if (!$BUFF_EOF) {
      # make sure we are still in the file where we think we should be
      seek($BUFF_filehandle, $BUFF_fileoffset, 0);

      # read FILEHANDLE, SCALAR, LENGTH, OFFSET
      my $readlen = read($BUFF_filehandle, $BUFF_buff, $BUFF_blocksize, $BUFF_size);

      $BUFF_EOF = 1 if $readlen < $BUFF_blocksize;
      $BUFF_start = $BUFF_fileoffset - $BUFF_size;
      $BUFF_size += $readlen;
      $BUFF_fileoffset += $readlen;

      writelog("debug_maildb_buffer - buffer_readblock - BUFF_EOF=$BUFF_EOF BUFF_fileoffset=$BUFF_fileoffset BUFF_size=$BUFF_size BUFF_start=$BUFF_start readlen=$readlen") if $config{debug_maildb_buffer};

      return $readlen;
   }

   writelog("debug_maildb_buffer - buffer_readblock - BUFF_EOF=1") if $config{debug_maildb_buffer};

   return 0;
}

sub buffer_startmsgchk {
   # check for the start of a new message
   my $pos = shift;

   writelog("debug_maildb_buffer - buffer_startmsgchk - pos=$pos") if $config{debug_maildb_buffer};

   # verify preceding new line characters
   # if this fails, bump the position to invalidate it
   $pos++ if $pos >= 1 && substr($BUFF_buff, $pos - 1, 1) ne "\n";

   # clear out the old buffer contents so we do not scan through them again
   buffer_skipchars($pos) if $pos;

   # just in case we got too close to the end of the buffer, better top it up
   # or we might not match the regex
   buffer_readblock() if $BUFF_size < 200;

   # check this message start more closely (this will fail if the preceding newline characters check above failed)
   if ($BUFF_buff =~ m/$BUFF_regex/) {
      writelog("debug_maildb_buffer - buffer_startmsgchk - BUFF_start=$BUFF_start BUFF_regex=$BUFF_regex") if $config{debug_maildb_buffer};

      # the buffer contains a line that matches the BUFF_regex
      # qr/^From .*(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+([A-Z]{3,4}\d?\s+)?(\d\d+)/;
      return $BUFF_start;
   } else {
      # if a 'From' is not a msgstart, skip it so we will not meet it again
      buffer_skipchars(4) if substr($BUFF_buff, 0, 4) eq 'From';
      return -1;
   }
}

sub buffer_getchars {
   # get chars from the buffer
   #  - up to the given size in bytes
   #  - or the entire buffer/file if size == -1
   my $size = shift;

   writelog("debug_maildb_buffer - buffer_getchars - size=$size BUFF_size=$BUFF_size BUFF_EOF=$BUFF_EOF") if $config{debug_maildb_buffer};

   # make sure the buffer contains enough bytes to meet the request
   buffer_readblock() while (($size < 0 or $size > $BUFF_size) && !$BUFF_EOF);

   $size = $BUFF_size if $size < 0;

   my $content = substr($BUFF_buff, 0, $size);

   buffer_skipchars($size); # gotten chars are removed from the buffer

   writelog("debug_maildb_buffer - buffer_getchars - content='$content' taken from buffer") if $config{debug_maildb_buffer};

   return $content;
}

sub buffer_skipchars {
   # skip past chars in the buffer
   # the entire buffer/file if size = -1
   # chars are removed from the buffer
   my $skip = shift;

   writelog("debug_maildb_buffer - buffer_skipchars - skip=$skip") if $config{debug_maildb_buffer};

   if ($skip < 0) {
      $BUFF_EOF  = 1;
      $BUFF_size = 0;
      $BUFF_buff = '';
   } elsif ($skip >= $BUFF_size) {
      # skipping passed the end of the buffer
      $BUFF_size       = 0;
      $BUFF_buff       = '';
      $BUFF_fileoffset = $BUFF_start + $skip;
      buffer_readblock();
   } else {
      $BUFF_start += $skip;
      $BUFF_size  -= $skip;
      $BUFF_buff   = substr($BUFF_buff, $skip);
   }
}

sub buffer_skipleading {
   # skip past chars in the buffer
   # while $delim string is found
   # chars are removed from the buffer
   my $delim = shift;
   my $len   = length $delim;

   writelog("debug_maildb_buffer - buffer_skipleading - delim=$delim len=$len BUFF_size=$BUFF_size") if $config{debug_maildb_buffer};

   return unless $len;

   my $skip = 0;

   buffer_readblock() if $BUFF_size < $len;

   # shrink the buffer size to be the same as the length of the delimter
   while ($BUFF_size >= $len && substr($BUFF_buff, $skip, $len) eq $delim) {
      $skip += $len;
      $BUFF_size -= $len;

      writelog("debug_maildb_buffer - buffer_skipleading - while loop skip=$skip BUFF_size=$BUFF_size") if $config{debug_maildb_buffer};

      if ($BUFF_size < $len) {
         writelog("debug_maildb_buffer - buffer_skipleading - BUFF_size=$BUFF_size < len=$len") if $config{debug_maildb_buffer};

         $BUFF_start += $skip;
         $BUFF_buff = substr($BUFF_buff, $skip);
         buffer_readblock();
         $skip = 0;
      }
   }

   $BUFF_start += $skip;
   $BUFF_buff = substr($BUFF_buff, $skip);

   writelog("debug_maildb_buffer - buffer_skipleading - BUFF_start=$BUFF_start") if $config{debug_maildb_buffer};
}

sub buffer_index {
   # search the buffer for a given string
   # if $keep = 1 then buffer contents will grow until $string is found
   # otherwise, previous contents of buffer are discarded
   my ($keep, @strings) = @_;

   writelog("debug_maildb_buffer - buffer_index - keep=$keep strings=" . join(',', @strings)) if $config{debug_maildb_buffer};

   my %strings = ();

   foreach my $string (@strings) {
      $strings{$string}{len}    = length $string;
      $strings{$string}{offset} = 0;
   }

   my $pos = -1;

   while ($pos < 0) {
      # search the buffer for the next message start
      foreach my $str (@strings) {
         $pos = index($BUFF_buff, $str, $strings{$str}{offset});

         writelog("debug_maildb_buffer - buffer_index - found string string='$str' at index pos=$pos") if $config{debug_maildb_buffer};

         return ($pos, $str) if $pos >= 0;
      }

      # keep the buffer size reasonable	- only keep last 1024 byte
      buffer_skipchars($BUFF_size - 1024) if !$keep && $BUFF_size > $BUFF_blocksizemax;

      $strings{$_}{offset} = ($BUFF_size - $strings{$_}{len}) for @strings;
      last unless buffer_readblock(); # stop at EOF
   }

   return (-1, ''); # not reached
}

1;
