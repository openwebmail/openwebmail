
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

# mailfilter.pl - filter INBOX messages in the background
#
# There are 4 types of checks in this mail filter:
# 1. external viruscheck (clamav)
# 2. static global and user defined rules
# 3. external spamcheck (spamassassin)
# 4. smart filter rules

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);

require "modules/mime.pl";
require "shares/filterbook.pl";

# extern vars
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES); # defined in maildb.pl
use vars qw(%config);
use vars qw($_filter_complete);

sub filtermessage {
   # filter inbox messages in background
   # return: 0 filter not necessary
   #         1 filter started (either forground or background)
   # there are 4 operations for a message: 'copy', 'move', 'delete' and 'keep'
   my ($user, $folder, $r_prefs) = @_;

   writelog("debug_mailfilter :: $folder :: filtermessage for user $user") if $config{debug_mailfilter};

   # return immediately if nothing to do
   return 0 if (
                  !$config{enable_userfilter}
                  && !$config{enable_globalfilter}
                  && !$config{enable_smartfilter}
                  && !$config{enable_viruscheck}
                  && !$config{enable_spamcheck}
               );

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   return 0 unless -f $folderfile;
   return 0 if -z $folderfile;

   my $forced_recheck = 0;
   my $filtercheckfile = dotpath('filter.check');

   # automatic 'test & set' the metainfo value in filtercheckfile
   my $metainfo = ow::tool::metainfo($folderfile);

   writelog("debug_mailfilter :: $folder :: metainfo before filtering is $metainfo") if $config{debug_mailfilter};

   # create the filter.check file if it does not exist
   if (!-f $filtercheckfile) {
      sysopen(F, $filtercheckfile, O_WRONLY|O_APPEND|O_CREAT) or writelog("cannot open file $filtercheckfile");
      close(F) or writelog("cannot close file $filtercheckfile ($!)");
      $forced_recheck = 1; # new filterrule added? if so do filtering on all messages
   }

   ow::filelock::lock($filtercheckfile, LOCK_EX) or
      openwebmailerror(gettext('Cannot lock file:') . " $filtercheckfile");

   if (!sysopen(FILTERCHECK, $filtercheckfile, O_RDONLY)) {
      ow::filelock::lock($filtercheckfile, LOCK_UN) or writelog("cannot unlock file $filtercheckfile");
      openwebmailerror(gettext('Cannot open file:') . " $filtercheckfile");
   }

   my $filtercheckline = <FILTERCHECK>;

   close(FILTERCHECK) or writelog("cannot close file $filtercheckfile ($!)");

   $filtercheckline = '' unless defined $filtercheckline && $filtercheckline ne '';

   writelog("debug_mailfilter :: $folder :: filter.check metainfo line : $filtercheckline") if $config{debug_mailfilter};

   if ($filtercheckline eq $metainfo) {
      # the folder metainfo timestamps match what is stored in the filter.check file
      # filtering is up to date - no need to filter right now
      ow::filelock::lock($filtercheckfile, LOCK_UN) or writelog("cannot unlock file $filtercheckfile");
      writelog("debug_mailfilter :: $folder :: folder and filter.check metainfo matches - no filtering needed") if $config{debug_mailfilter};
      return 0;
   }

   writelog("debug_mailfilter :: $folder :: folder and filter.check metainfo mismatch - updating filter.check file") if $config{debug_mailfilter};

   # update the metainfo in the filter.check file
   if (!sysopen(FILTERCHECK, $filtercheckfile, O_WRONLY|O_TRUNC|O_CREAT)) {
      ow::filelock::lock($filtercheckfile, LOCK_UN) or writelog("cannot unlock file $filtercheckfile");
      openwebmailerror(gettext('Cannot open file:') . " $filtercheckfile");
   }

   print FILTERCHECK $metainfo;

   close(FILTERCHECK) or writelog("cannot close file $filtercheckfile ($!)");
   ow::filelock::lock($filtercheckfile, LOCK_UN) or writelog("cannot unlock file $filtercheckfile");

   openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile))
      unless ow::filelock::lock($folderfile, LOCK_EX);

   writelog("debug_mailfilter :: $folder :: updating the folder index db before filtering") if $config{debug_mailfilter};

   if (!update_folderindex($folderfile, $folderdb) < 0) {
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
      openwebmailerror(gettext('Cannot update index db:') . ' ' . f2u($folderdb));
   }

   writelog("debug_mailfilter :: $folder :: update index complete - begin filtering") if $config{debug_mailfilter};

   my @allmessageids = ();

   writelog("debug_mailfilter :: $folder :: getting the offset and status of every message") if $config{debug_mailfilter};
   writelog("debug_mailfilter :: $folder :: forced_recheck = $forced_recheck") if $config{debug_mailfilter};

   # 1 means ignore_internal
   my ($total, $r_msgid2attrs) = get_msgid2attrs($folderdb, 1, $_OFFSET, $_STATUS);

   foreach my $id (keys %{$r_msgid2attrs}) {
      my $msg_status = $r_msgid2attrs->{$id}[1];
      next if defined $msg_status && $msg_status =~ m/V/ && !$forced_recheck; # skip verified messages if no forced check
      next if defined $msg_status && $msg_status =~ m/Z/;                     # skip zapped messages
      push(@allmessageids, $id);
   }

   @allmessageids = sort { $r_msgid2attrs->{$a}[0] <=> $r_msgid2attrs->{$b}[0] } @allmessageids;

   # return immediately if no message found
   if (scalar @allmessageids < 1) {
      writelog("debug_mailfilter :: $folder :: no messages found for filtering") if $config{debug_mailfilter};
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
      return 0;
   }

   writelog("debug_mailfilter :: $folder :: ready to filter " . scalar @allmessageids . " messages") if $config{debug_mailfilter};

   if ($r_prefs->{bgfilterthreshold} > 0 && scalar @allmessageids >= $r_prefs->{bgfilterthreshold}) {
      # release folder lock before fork, the forked child does lock in per message basis
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");

      local $_filter_complete = 0;
      local $SIG{CHLD} = sub { wait; $_filter_complete = 1 if $? == 0 }; # signaled when filter completes
      local $| = 1; # flush all output

      writelog("debug_mailfilter :: $folder :: forking child process to filter messages in the background") if $config{debug_fork} || $config{debug_mailfilter};

      # child
      if (fork() == 0) {
         close(STDIN);
         close(STDOUT);
         close(STDERR);

         local $SIG{__WARN__} = sub { writelog(@_); exit(1) };
         local $SIG{__DIE__}  = sub { writelog(@_); exit(1) };

         writelog("debug_mailfilter :: mailfilter process forked") if $config{debug_fork} || $config{debug_mailfilter};

         ow::suid::drop_ruid_rgid(); # set ruid=euid to avoid fork in spamcheck.pl

         filter_allmessageids(
                                $user,
                                $folder,
                                $r_prefs,
                                $folderfile,
                                $folderdb,
                                $metainfo,
                                $filtercheckfile,
                                $forced_recheck,
                                \@allmessageids,
                                0
                             ); # 0 means no globallock

         writelog("debug_mailfilter :: mailfilter process terminated") if $config{debug_fork} || $config{debug_mailfilter};

         # terminate this forked filter process
         openwebmail_exit(0);
      }

      # wait background filtering to complete for few seconds
      my $seconds = $r_prefs->{bgfilterwait} || 5;
      $seconds = 5 if $seconds < 5;

      writelog("debug_mailfilter :: $folder :: waiting $seconds for background filter to complete") if $config{debug_mailfilter};

      for (my $i = 0; $i < $seconds; $i++) {
         sleep 1;
         last if $_filter_complete;
      }
   } else {
      writelog("debug_mailfilter :: $folder :: filtering messages in the foreground") if $config{debug_mailfilter};

      filter_allmessageids(
                             $user,
                             $folder,
                             $r_prefs,
                             $folderfile,
                             $folderdb,
                             $metainfo,
                             $filtercheckfile,
                             $forced_recheck,
                             \@allmessageids,
                             1
                          ); # 1 meas has globallock

      writelog("debug_mailfilter :: $folder :: filtering messages in the foreground complete") if $config{debug_mailfilter};

      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
   }

   return 1;
}

sub filter_allmessageids {
   # given a set of messageids that are not status Z (to be zapped), and are not
   # status V (already verified), filter the messages according to the filterbook
   my (
         $user,
         $folder,
         $r_prefs,
         $folderfile,
         $folderdb,
         $metainfo,
         $filtercheckfile,
         $forced_recheck,
         $r_allmessageids,
         $has_globallock
      ) = @_;

   writelog("debug_mailfilter :: $folderfile :: sub filter_allmessageids") if $config{debug_mailfilter};

   # create a pidfile that contains the backgrounded process id in it
   # other processes can check for a running backgrounded filter and wait for it
   my $pidfile = '';

   # threshold > 0 means the bg filter may be actived if the inbox has enough new messages,
   # so we update pid file to terminate any other bg filter process
   if ($r_prefs->{bgfilterthreshold} > 0) {
      $pidfile = dotpath('filter.pid');
      writelog("debug_mailfilter :: $folderfile :: storing background process id in file $pidfile") if $config{debug_mailfilter};
      sysopen(F, $pidfile, O_WRONLY|O_TRUNC|O_CREAT) or writelog("cannot open file $pidfile ($!)");
      print F $$;
      close(F) or writelog("cannot close file $pidfile ($!)");
   }

   # get @filterrules
   my %filterrules        = ();
   my @sorted_filterrules = ();
   my $filterbookfile     = dotpath('filter.book');

   if ($config{enable_userfilter} && -f $filterbookfile) {
      writelog("debug_mailfilter :: $folderfile :: reading filterbook $filterbookfile") if $config{debug_mailfilter};
      read_filterbook($filterbookfile, \%filterrules);
   }

   if ($config{enable_globalfilter} && -f $config{global_filterbook}) {
      writelog("debug_mailfilter :: $folderfile :: reading global filterbook $config{global_filterbook}") if $config{debug_mailfilter};
      read_filterbook($config{global_filterbook}, \%filterrules);
   }

   foreach my $key (sort_filterrules(\%filterrules)) {
      my $r_rule = $filterrules{$key};

      next if (
                 !$r_rule->{enable}
                 || $r_rule->{op} ne 'copy'
                 && $r_rule->{op} ne 'move'
                 && $r_rule->{op} ne 'delete'
              );

      if ($r_rule->{dest} eq 'DELETE') {
         next if $r_rule->{op} eq 'copy';                     # copy to DELETE is meaningless
         $r_rule->{op} = 'delete' if $r_rule->{op} eq 'move'; # move to DELETE is 'delete'
      }

      writelog("debug_mailfilter :: $folderfile :: using filter rule $key") if $config{debug_mailfilter};

      push(@sorted_filterrules, $key);
   }

   writelog("debug_mailfilter :: $folderfile :: using " . scalar @sorted_filterrules . " rules") if $config{debug_mailfilter};

   # return immediately if nothing to do
   return 1 if (
                  scalar @sorted_filterrules < 1
                  && !$config{enable_smartfilter}
                  && !$config{enable_viruscheck}
                  && !$config{enable_spamcheck}
               );

   my $repeatstarttime     = time() - 86400; # only count repeat for messages within one day
   my %repeatlists         = ();
   my %is_verified         = ();
   my $io_errcount         = 0;
   my $viruscheck_errcount = 0;
   my $spamcheck_errcount  = 0;
   my $append_err          = 0;

   my $i = $#{$r_allmessageids};

   while ($i >= 0) {
      my $messageid_i = $r_allmessageids->[$i];
      writelog("debug_mailfilter :: loop $i, msgid=$messageid_i") if $config{debug_mailfilter};

      if (exists $is_verified{$messageid_i} || $messageid_i =~ m/^DUP\d+\-/) {
         # skip already verified message or duplicated msg in src folder
         $i--;
         next;
      }

      # quit if there are too many errors
      last if $io_errcount >= 3;

      if (!$has_globallock) {
         # terminated if other filter process is active on same folder
         sysopen(F, $pidfile, O_RDONLY) or writelog("cannot open file $pidfile");
         my $process_id = <F>;
         close(F) or writelog("cannot close file $pidfile ($!)");

         writelog("debug_mailfilter :: opened pidfile $pidfile") if $config{debug_mailfilter};

         if ($process_id ne $$) {
            writelog("debug_mailfilter :: bg process terminated :: another filter pid=$process_id is active") if $config{debug_mailfilter};
            openwebmail_exit(0);
         }

         # reload messageids if folder is changed
         my $curr_metainfo = ow::tool::metainfo($folderfile);

         if ($metainfo ne $curr_metainfo) {
            my $lockget_messagesize = lockget_messageids($folderfile, $folderdb, $r_allmessageids);

            openwebmail_exit(0) if $lockget_messagesize < 0;

            $i = $#{$r_allmessageids};
            writelog("debug_mailfilter :: reload $i msgids :: $folderfile is changed") if $config{debug_mailfilter};

            # update filter.check with the current metainfo
            if (!sysopen(FILTERCHECK, $filtercheckfile, O_WRONLY|O_TRUNC|O_CREAT)) {
               writelog("mailfilter - $filtercheckfile open error");
               openwebmail_exit(0);
            }

            print FILTERCHECK $curr_metainfo;

            close(FILTERCHECK) or writelog("cannot close file $filtercheckfile ($!)");

            writelog("debug_mailfilter :: updating filter.check metainfo $metainfo") if $config{debug_mailfilter};

            $metainfo = $curr_metainfo;

            next;
         }
      }

      my $headersize             = 0;
      my $header                 = '';
      my $decoded_header         = '';
      my $currmessage            = '';
      my $body                   = '';
      my %msg                    = ();
      my $r_attachments          = [];
      my $r_smtprelays           = [];
      my $r_connectfrom          = {};
      my $r_byas                 = {};
      my $is_body_decoded        = 0;
      my $is_attachments_decoded = 0;
      my $reserved_in_folder     = 0;
      my $to_be_moved            = 0;

      my @attr = get_message_attributes($messageid_i, $folderdb);

      if (scalar @attr < 1) {
         # message not found in db
         writelog("debug_mailfilter :: message not found in db") if $config{debug_mailfilter};
         $i--;
         next;
      }

      if (is_internal_subject($attr[$_SUBJECT]) || $attr[$_STATUS] =~ m/Z/i) {
         # skip internal or zapped
         writelog("debug_mailfilter :: skipping internal or zapped message $messageid_i") if $config{debug_mailfilter};
         $is_verified{$messageid_i} = 1;
         $i--;
         next;
      }

      # if V flag (Verified) is not found this message has not been filtered before
      if ($attr[$_STATUS] !~ m/V/i || $forced_recheck) {
         # 0. check spool file message header against database index for consistency
         my $lockget_headersize = lockget_message_header($messageid_i, $folderfile, $folderdb, \$header, $has_globallock);

         if ($lockget_headersize < 0) {
            writelog("mailfilter - message header inconsistent with index database, messageid=$messageid_i, folderfile=$folderfile");
            mark_folderdb_err($folderdb) if $lockget_headersize <= -3;
            $io_errcount++;
            $i--;
            next;
         }

         writelog("debug_mailfilter :: checking $messageid_i, subject=$attr[$_SUBJECT]") if $config{debug_mailfilter};

         # message matches the database, mark it Verified
         if ($attr[$_STATUS] !~ m/V/i) {
            my %FDB = ();

            ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or writelog("cannot open db $folderdb");

            $attr[$_STATUS] .= 'V';

            $FDB{$messageid_i} = msgattr2string(@attr);

            ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

            writelog("debug_mailfilter :: marked message verified") if $config{debug_mailfilter};
         }

         # 1. virus check
         if ($config{enable_viruscheck} && !$to_be_moved) {
            writelog("debug_mailfilter :: viruscheck $messageid_i") if $config{debug_mailfilter};

            my $virusfound = 0;

            if ($header =~ m/^X\-OWM\-VirusCheck: ([a-z]+)/m) {
               # already virus checked in fetchmail.pl
               $virusfound = 1 if $1 eq 'virus';
            } elsif (
                       $r_prefs->{viruscheck_source} eq 'all'
                       && !$viruscheck_errcount
                       && $attr[$_SIZE] <= $r_prefs->{viruscheck_maxsize} * 1024
                       && $attr[$_SIZE] - $attr[$_HEADERSIZE] > $r_prefs->{viruscheck_minbodysize} * 1024
                    ) {
               # to be virus checked here
               if ($currmessage eq '') {
                  my $lockget_messagesize = lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);

                  if ($lockget_messagesize < 0) {
                     writelog("mailfilter - message inconsistent with index database, messageid=$messageid_i, folderfile=$folderfile");
                     mark_folderdb_err($folderdb) if $lockget_messagesize <= -3;
                     $io_errcount++;
                     $i--;
                     next;
                  }
               }

               my ($ret, $err) = ow::viruscheck::scanmsg($config{viruscheck_pipe}, \$currmessage);

               if ($ret < 0) {
                  writelog("viruscheck - pipe error - $err");
                  $viruscheck_errcount++;
               } elsif ($ret > 0) {
                  writelog("viruscheck - virus $err found, messageid=$messageid_i, folderfile=$folderfile");
                  $virusfound = 1;
               }
            }

            if ($virusfound) {
               $append_err = append_filteredmsg_to_folder(
                                                            $folderfile,
                                                            $folderdb,
                                                            $messageid_i,
                                                            \@attr,
                                                            \$currmessage,
                                                            $user,
                                                            $config{virus_destination},
                                                            $has_globallock
                                                         );

               if ($append_err >= 0) {
                  writelog("debug_mailfilter :: move $messageid_i -> $config{virus_destination}") if $config{debug_mailfilter};
                  filterfolderdb_increase($config{virus_destination}, 1);
                  $to_be_moved = 1;
               } else {
                  writelog("mailfilter - move $messageid_i -> $config{virus_destination} error $append_err");
                  $io_errcount++;
               }
            }
         } else {
            writelog("debug_mailfilter :: skipping viruscheck") if $config{debug_mailfilter};
         }

         # 2. static filter rules (including global and personal rules)
         if (!$to_be_moved) {
            writelog("debug_mailfilter :: static rules check $messageid_i") if $config{debug_mailfilter};

            foreach my $key (@sorted_filterrules) {
               my $r_rule = $filterrules{$key};
               my $is_matched = 0;

               # precompile text into regex of message charset for speed
               if (!defined $r_rule->{'regex.' . $attr[$_CHARSET]}) {
                  my $text = (iconv($r_rule->{charset}, $attr[$_CHARSET], $r_rule->{text}))[0];

                  $text = '' unless defined $text;

                  if ($r_prefs->{regexmatch} && ow::tool::is_regex($text)) { # do regex compare?
                     $r_rule->{'regex.' . $attr[$_CHARSET]} = qr/$text/im;
                  } else {
                     $r_rule->{'regex.' . $attr[$_CHARSET]} = qr/\Q$text\E/im;
                  }
               }

               if ($r_rule->{type} eq 'from' || $r_rule->{type} eq 'to' || $r_rule->{type} eq 'subject') {
                  if ($decoded_header eq '') {
                     $decoded_header = decode_mimewords_iconv($header, $attr[$_CHARSET]);
                     $decoded_header = '' unless defined $decoded_header;
                     $decoded_header =~ s/\s*\n\s+/ /sg; # concatenate folding lines
                  }

                  ow::mailparse::parse_header(\$decoded_header, \%msg) unless defined $msg{from};

                  $is_matched = 1 if exists $msg{$r_rule->{type}}
                                     && defined $msg{$r_rule->{type}}
                                     && $msg{$r_rule->{type}} =~ m/$r_rule->{'regex.' . $attr[$_CHARSET]}/
                                     xor $r_rule->{inc} eq 'exclude';
               } elsif ($r_rule->{type} eq 'header') {
                  if ($decoded_header eq '') {
                     $decoded_header = decode_mimewords_iconv($header, $attr[$_CHARSET]);
                     $decoded_header = '' unless defined $decoded_header;
                     $decoded_header =~ s/\s*\n\s+/ /sg; # concatenate folding lines
                  }

                  $is_matched = 1 if $decoded_header =~ m/$r_rule->{'regex.' . $attr[$_CHARSET]}/
                                     xor $r_rule->{inc} eq 'exclude';
               } elsif ($r_rule->{type} eq 'smtprelay') {
                  ($r_smtprelays, $r_connectfrom, $r_byas) = ow::mailparse::get_smtprelays_connectfrom_byas_from_header($header)
                     unless defined $r_smtprelays;

                  my $smtprelays = '';

                  foreach my $relay (@{$r_smtprelays}) {
                     $smtprelays .= "$relay, $r_connectfrom->{$relay}, $r_byas->{$relay}, ";
                  }

                  $is_matched = 1 if $smtprelays =~ m/$r_rule->{'regex.' . $attr[$_CHARSET]}/
                                     xor ${$r_rule}{inc} eq 'exclude';
               } elsif ($r_rule->{type} eq 'textcontent') {
                  if ($currmessage eq '') {
                     my $lockget_messagesize = lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);

                     if ($lockget_messagesize < 0) {
                        mark_folderdb_err($folderdb) if $lockget_messagesize <= -3;
                        $io_errcount++;
                        $i--;
                        next;
                     }
                  }

                  ($header, $body, $r_attachments) = ow::mailparse::parse_rfc822block(\$currmessage)
                     unless scalar @{$r_attachments} > 0;

                  # check body text
                  if (!$is_body_decoded) {
                     if ($attr[$_CONTENT_TYPE] =~ m/^text/i || $attr[$_CONTENT_TYPE] eq 'N/A') {
                        # for text/plain. text/html
                        my ($encoding) = $header =~ m/content-transfer-encoding:\s+([^\s+])/i;
                        $body = ow::mime::decode_content($body, $encoding);
                     }

                     $is_body_decoded = 1;
                  }

                  # for text/plain. text/html
                  $is_matched = 1 if ($attr[$_CONTENT_TYPE] =~ m/^text/i || $attr[$_CONTENT_TYPE] eq 'N/A')
                                     &&
                                     ($body =~ m/$r_rule->{'regex.' . $attr[$_CHARSET]}/ xor $r_rule->{inc} eq 'exclude');

                  # check attachments text if body text not match
                  if (!$is_matched) {
                     if (!$is_attachments_decoded) {
                        foreach my $r_attachment (@{$r_attachments}) {
                           if ($r_attachment->{'content-type'} =~ /^text/i || $r_attachment->{'content-type'} eq 'N/A') {
                              # read all for text/plain. text/html
                              ${$r_attachment->{r_content}} = ow::mime::decode_content(${$r_attachment->{r_content}}, $r_attachment->{'content-transfer-encoding'});
                           }
                        }

                        $is_attachments_decoded = 1;
                     }

                     foreach my $r_attachment (@{$r_attachments}) {
                        # read all for text/plain. text/html
                        $is_matched = 1 if ($r_attachment->{'content-type'} =~ m/^text/i || $r_attachment->{'content-type'} eq 'N/A')
                                           &&
                                           (${$r_attachment->{r_content}} =~ m/$r_rule->{'regex.' . $attr[$_CHARSET]}/ xor $r_rule->{inc} eq 'exclude');

                        # leave attachments loop of this message?
                        last if $is_matched;
                     }
                  }
               } elsif ($r_rule->{type} eq 'attfilename') {
                  if ($currmessage eq '') {
                     my $lockget_messagesize = lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);

                     if ($lockget_messagesize < 0) {
                        mark_folderdb_err($folderdb) if $lockget_messagesize <= -3;
                        $io_errcount++;
                        $i--;
                        next;
                     }
                  }

                  ($header, $body, $r_attachments) = ow::mailparse::parse_rfc822block(\$currmessage)
                     unless scalar @{$r_attachments} > 0;

                  # check attachments
                  foreach my $r_attachment (@{$r_attachments}) {
                     $is_matched = 1 if $r_attachment->{filename} =~ m/$r_rule->{'regex.' . $attr[$_CHARSET]}/
                                        xor $r_rule->{inc} eq 'exclude';

                     # leave attachments loop of this message?
                     last if $is_matched;
                  }
               }

               if ($is_matched) {
                  writelog("debug_mailfilter :: matches $r_rule->{type} rule $r_rule->{'regex.' . $attr[$_CHARSET]}") if $config{debug_mailfilter};

                  # copy message to other folder and set reserved_in_folder or to_be_moved flag
                  filterruledb_increase($key, 1);

                  if (!defined $r_rule->{fsdest}) {
                     $r_rule->{fsdest} = (iconv($r_rule->{charset}, $r_prefs->{fscharset}, $r_rule->{dest}))[0];
                  }

                  if ($r_rule->{op} eq 'move' || $r_rule->{op} eq 'copy') {
                     if ($r_rule->{fsdest} eq $folder) {
                        $reserved_in_folder = 1;
                     } else {
                        $append_err = append_filteredmsg_to_folder(
                                                                     $folderfile,
                                                                     $folderdb,
                                                                     $messageid_i,
                                                                     \@attr,
                                                                     \$currmessage,
                                                                     $user,
                                                                     $r_rule->{fsdest},
                                                                     $has_globallock
                                                                  );
                     }
                  }

                  if ($r_rule->{op} eq 'move' || $r_rule->{op} eq 'delete') {
                     if ($append_err >= 0) {
                        if (!$reserved_in_folder) {
                           if ($config{debug_mailfilter}) {
                              my $fstext = (iconv($r_rule->{charset}, $r_prefs->{fscharset}, $r_rule->{text}))[0];
                              writelog("debug_mailfilter :: move message $messageid_i -> $r_rule->{fsdest} (rule: $r_rule->{type} $r_rule->{inc} $fstext)");
                           }

                           $to_be_moved = 1;
                           filterfolderdb_increase($r_rule->{fsdest}, 1);
                        }
                     } else {
                        writelog("mailfilter - move $messageid_i -> $r_rule->{fsdest} write error $append_err");
                        $io_errcount++;
                     }

                     last;
                  }
                  # try next rule if message is not moved/deleted and there is no io error
               }
            }
         } else {
            writelog("debug_mailfilter :: skipping static rules check for message already marked to be moved $messageid_i") if $config{debug_mailfilter};
         }

         # 3. spam check
         if ($config{enable_spamcheck} && !$reserved_in_folder && !$to_be_moved) {
            writelog("debug_mailfilter :: spamcheck $messageid_i") if $config{debug_mailfilter};

            my $spamfound = 0;

            if ($header =~ m/^X\-OWM\-SpamCheck: \** ([\d\.]+)/m) {
               # spam already checked in fetchmail.pl
               $spamfound = 1 if $1 > $r_prefs->{spamcheck_threshold};
            } elsif ($r_prefs->{spamcheck_source} eq 'all' && !$spamcheck_errcount && $attr[$_SIZE] <= $r_prefs->{spamcheck_maxsize} * 1024) {
               # perform spam check here
               if ($currmessage eq '') {
                  my $lockget_messagesize = lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);

                  if ($lockget_messagesize < 0) {
                     mark_folderdb_err($folderdb) if $lockget_messagesize <= -3;
                     $io_errcount++;
                     $i--;
                     next;
                  }
               }

               my ($spamlevel, $err) = ow::spamcheck::scanmsg($config{spamcheck_pipe}, \$currmessage);

               if ($spamlevel == -99999) {
                  my $m = "spamscheck - pipe error - $err";
                  writelog($m);
                  writehistory($m);
                  $spamcheck_errcount++;
               } elsif ($spamlevel > $r_prefs->{spamcheck_threshold}) {
                  my $m = "spamcheck - spam $spamlevel/$r_prefs->{spamcheck_threshold} found in msg $messageid_i";
                  writelog($m);
                  writehistory($m);
                  $spamfound = 1;
               } else {
                  my $m = "spamcheck - notspam $spamlevel/$r_prefs->{spamcheck_threshold} found in msg $messageid_i";
                  writelog($m);
                  writehistory($m);
               }
            }

            if ($spamfound) {
               $append_err = append_filteredmsg_to_folder(
                                                            $folderfile,
                                                            $folderdb,
                                                            $messageid_i,
                                                            \@attr,
                                                            \$currmessage,
                                                            $user,
                                                            $config{spam_destination},
                                                            $has_globallock
                                                         );

               if ($append_err >= 0) {
                  writelog("debug_mailfilter :: move message $messageid_i -> $config{spam_destination}") if $config{debug_mailfilter};
                  filterfolderdb_increase($config{spam_destination}, 1);
                  $to_be_moved = 1;
               } else {
                  writelog("mailfilter - move $messageid_i -> $config{spam_destination} write error $append_err");
                  $io_errcount++;
               }
            }
         }

         # 4. smart filter rules
         if ($config{enable_smartfilter} && !$reserved_in_folder && !$to_be_moved) {
            writelog("debug_mailfilter :: smart rules check $messageid_i") if $config{debug_mailfilter};

            # bypass smart filters for good messages
            if ($config{smartfilter_bypass_goodmessage} && !$reserved_in_folder && !$to_be_moved) {
               $reserved_in_folder = 1 if ($header =~ m/^X\-Mailer: Open ?WebMail/m && $header =~ m/^X\-OriginatingIP: /m)
                                          ||
                                          ($header =~ m/^In\-Reply\-To: /m && $header =~ m/^References: /m);
            }

            # since if any smartrule matches, other smartrule would be skipped
            # so we use only one variable to record the matched smartrule.
            my $matchedsmartrule = '';

            # filter message with "bad format from" if message is not moved or deleted
            if ($r_prefs->{filter_badaddrformat} && !$reserved_in_folder && !$to_be_moved) {
               my $badformat = 0;

               my $fromaddr = (ow::tool::email2nameaddr($attr[$_FROM]))[1];
               $fromaddr =~ s/\@.*$//;

               $badformat = 1 if $fromaddr =~ m/[^\d\w\-\._]/
                                 || $fromaddr =~ m/^\d/
                                 || ($fromaddr =~ m/\d/ && $fromaddr =~ m/\./);

               my ($toname, $toaddr) = ow::tool::email2nameaddr($attr[$_TO]);

               $badformat = 1 if $toname =~ m/undisclosed-recipients/i && $toaddr =~ m/\@/;

               if ($badformat) {
                  $matchedsmartrule = 'filter_badaddrformat';
                  $to_be_moved = 1;
               }
            }

            # filter message with "faked from" - whose from: is different than the envelope email address
            if ($r_prefs->{filter_fakedfrom} && !$reserved_in_folder && !$to_be_moved ) {
               # skip faked from check for messages generated by some software
               my $is_software_generated = 0;

               if (
                     # TMDA generated
                     ($header =~ m/^\QX-Delivery-Agent: TMDA\E/m && $header =~ m/^\QPrecedence: bulk\E/m && $messageid_i =~ m/\Q.TMDA@\E/)
                     ||
                     # Request Tracker generated
                     ($header =~ m/^\QManaged-by: RT\E/m && $header =~ /^\QRT-Ticket: \E/m && $header =~ m/^\QPrecedence: bulk\E/m)
                  ) {
                  $is_software_generated = 1;
               }

               if (!$is_software_generated) {
                  my $envelopefrom = '';
                  $envelopefrom = $1 if $header =~ m/\(envelope\-from (\S+).*?\)/s;
                  $envelopefrom = $1 if $envelopefrom eq '' && $header =~ m/^From (\S+)/;

                  # compare user and domain independently
                  my ($hdr_user, $hdr_domain) = split(/\@/, (ow::tool::email2nameaddr($attr[$_FROM]))[1]);
                  my ($env_user, $env_domain) = split(/\@/, $envelopefrom);
                  if (
                        $hdr_user ne $env_user
                        ||
                        (
                           $hdr_domain ne ''
                           && $env_domain ne ''
                           && $hdr_domain !~ m/\Q$env_domain\E/i
                           && $env_domain !~ m/\Q$hdr_domain\E/i
                        )
                     ) {
                     $matchedsmartrule = 'filter_fakedfrom';
                     $to_be_moved = 1;
                  }
               }
            }

            # filter message with "faked smtp" - smtprelay with faked name if message is not moved or deleted
            if ($r_prefs->{filter_fakedsmtp} && !$reserved_in_folder && !$to_be_moved) {
               if (!defined $r_smtprelays) {
                  ($r_smtprelays, $r_connectfrom, $r_byas) = ow::mailparse::get_smtprelays_connectfrom_byas_from_header($header);
               }

               # move message to trash if the first relay has invalid/faked hostname
               if (defined $r_smtprelays->[0]) {
                  my $relay       = $r_smtprelays->[0];
                  my $connectfrom = $r_connectfrom->{$relay};
                  my $byas        = $r_byas->{$relay};
                  my $is_private  = 0;

                  $is_private = 1 if $connectfrom =~ m/(?:\[10|\[172\.[1-3][0-9]|\[192\.168|\[127\.0)\./;

                  my @compare  = (
                                    namecompare($connectfrom, $relay),
                                    namecompare($byas, $relay),
                                    namecompare($connectfrom, $byas)
                                 );

                  my $is_valid = 0; # default all <= 0 and at least one < 0

                  $is_valid = 1 if $compare[0] > 0
                                   || $compare[1] > 0
                                   || $compare[2] > 0
                                   || (
                                         $compare[0] == 0
                                         && $compare[1] == 0
                                         && $compare[2] == 0
                                      );

                  # the last relay is the mail server
                  my $dstdomain = domain($r_smtprelays->[$#{$r_smtprelays}]);

                  if ($connectfrom !~ m/\Q$dstdomain\E/i && !$is_private && !$is_valid) {
                     $matchedsmartrule = 'filter_fakedsmtp';
                     $to_be_moved = 1;
                  }
               }
            }

            # filter message with "faked exe contenttype" if message is not moved or deleted
            if ($r_prefs->{filter_fakedexecontenttype} && !$reserved_in_folder && !$to_be_moved) {
               if ($currmessage eq '') {
                  my $lockget_messagesize = lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);

                  if ($lockget_messagesize < 0) {
                     mark_folderdb_err($folderdb) if $lockget_messagesize <= -3;
                     $io_errcount++;
                     $i--;
                     next;
                  }
               }

               ($header, $body, $r_attachments) = ow::mailparse::parse_rfc822block(\$currmessage)
                  unless scalar @{$r_attachments} > 0;

               # check executable attachment and contenttype
               my $att_matched = 0;
               foreach my $r_attachment (@{$r_attachments}) {
                  if (
                        $r_attachment->{filename} =~ m/\.(?:exe|com|bat|pif|lnk|scr)$/i
                        && $r_attachment->{'content-type'} !~ m/application\/octet\-stream/i
                        && $r_attachment->{'content-type'} !~ m/application\/x\-msdownload/i
                     ) {
                     $matchedsmartrule = 'filter_fakedexecontenttype';
                     $to_be_moved = 1;
                     last;
                  }
               }
            }

            if ($matchedsmartrule ne '') {
               filterruledb_increase($matchedsmartrule, 1);
               $append_err = append_filteredmsg_to_folder(
                                                            $folderfile,
                                                            $folderdb,
                                                            $messageid_i,
                                                            \@attr,
                                                            \$currmessage,
                                                            $user,
                                                            'mail-trash',
                                                            $has_globallock
                                                         );

               if ($append_err >= 0) {
                  writelog("debug_mailfilter :: move message $messageid_i -> mail-trash (smartrule: $matchedsmartrule)") if $config{debug_mailfilter};
                  filterfolderdb_increase('mail-trash', 1);
               } else {
                  writelog("mailfilter - move $messageid_i -> mail-trash write error $append_err");
                  $io_errcount++;
                  $to_be_moved = 0;
                  last;
               }
            }
         }

         # 5. mark to be moved message as zap
         if ($to_be_moved) {
            my %FDB = ();

            ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or
              openwebmailerror(gettext('Cannot open db:') . " $folderdb ($!)");

            if ($attr[$_STATUS] !~ m/Z/i) {
               $attr[$_STATUS] .= 'Z';
               $FDB{$messageid_i} = msgattr2string(@attr);
               $FDB{ZAPMESSAGES}++;
               $FDB{ZAPSIZE} += $attr[$_SIZE];

               if (is_internal_subject($attr[$_SUBJECT])) {
                  $FDB{INTERNALMESSAGES}--;
                  $FDB{INTERNALSIZE} -= $attr[$_SIZE];
               } elsif ($attr[$_STATUS] !~ m/R/i) {
                  $FDB{NEWMESSAGES}--;
               }
            }

            ow::dbm::closedb(\%FDB, $folderdb) or
              openwebmailerror(gettext('Cannot close db:') . " $folderdb ($!)");
         }
      }

      if (
            $r_prefs->{filter_repeatlimit} > 0
            && !$to_be_moved
            && !$reserved_in_folder
            && ow::datetime::dateserial2gmtime($attr[$_DATE]) >= $repeatstarttime
         ) {
         # store msgid with same '$from:$subject' to same array
         my $msgstr = "$attr[$_FROM]:$attr[$_SUBJECT]";

         $repeatlists{$msgstr} = [] unless defined $repeatlists{$msgstr};

         push (@{$repeatlists{$msgstr}}, $messageid_i);
      }

      # remember this msgid so we will not recheck it again after @allmessageids reload event
      $is_verified{$messageid_i} = 1;
      $i--;
   } # end of messageids loop

   if ($has_globallock || ow::filelock::lock($folderfile, LOCK_EX)) {
      # remove repeated msgs with repeated count > $r_prefs->{filter_repeatlimit}
      my @repeatedids = ();
      my $fromsubject = '';
      my $r_ids       = [];

      while (($fromsubject,$r_ids) = each %repeatlists) {
         push(@repeatedids, @{$r_ids}) if $#{$r_ids} >= $r_prefs->{filter_repeatlimit};
      }

      if ($#repeatedids >= 0) {
         my ($trashfile, $trashdb) = get_folderpath_folderdb($user, 'mail-trash');

         my $moved = 0;

         if (ow::filelock::lock($trashfile, LOCK_EX)) {
            $moved = operate_message_with_ids('move', \@repeatedids, $folderfile, $folderdb, $trashfile, $trashdb);

            ow::filelock::lock($trashfile, LOCK_UN) or writelog("cannot unlock file $trashfile");

            if ($moved > 0) {
               if ($config{debug_mailfilter}) {
                  my $idsstr = join(',', @repeatedids);
                  writelog("debug_mailfilter :: move messages $idsstr -> mail-trash (smartrule: filter_repeatlimit)");
               }

               filterruledb_increase("filter_repeatlimit", $moved);
               filterfolderdb_increase('mail-trash', $moved);
            }
         } else {
            writelog("Cannot lock file $trashfile");
         }
      }

      my $is_allmessageids_checked = 0;

      $is_allmessageids_checked = 1 if $metainfo eq ow::tool::metainfo($folderfile);

      my $zapped = folder_zapmessages($folderfile, $folderdb);

      if ($zapped == -5 || $zapped == -6) {
         # zap again if index inconsistence (-5) or shiftblock io error (-6)
         $zapped = folder_zapmessages($folderfile, $folderdb);

         writelog("mailfilter - $folderfile zap error $zapped") if $zapped < 0;
      }

      if ($is_allmessageids_checked) {
         ow::filelock::lock($filtercheckfile, LOCK_EX|LOCK_NB) or writelog("cannot lock file $filtercheckfile");

         if (sysopen(FILTERCHECK, $filtercheckfile, O_WRONLY|O_TRUNC|O_CREAT)) {
            print FILTERCHECK ow::tool::metainfo($folderfile);
            close(FILTERCHECK) or writelog("cannot close file $filtercheckfile ($!)");
         } else {
            writelog("cannot open file $filtercheckfile");
         }

         ow::filelock::lock($filtercheckfile, LOCK_UN) or writelog("cannot unlock file $filtercheckfile");
      }

      if (!$has_globallock) {
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
      }
   }
}

sub mark_folderdb_err {
   my $folderdb = shift;

   my %FDB = ();

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX) or writelog("cannot open db $folderdb");

   $FDB{METAINFO} = 'ERR';
   $FDB{LSTMTIME} = -1;

   ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");
}

sub namecompare {
   # hostname compare for loosely equal
   # >0 match, <0 unmatch, ==0 unknown
   my ($a, $b) = @_;

   # do not compare if any of them is empty
   return 0 if $a =~ m/^\s*$/ || $b =~ m/^\s*$/;

   # check if both names are invalid
   if ($a =~ m/[\d\w\-_]+[\.\@][\d\w\-_]+/) {
      if ($b =~ m/[\d\w\-_]+[\.\@][\d\w\-_]+/ ) {       # a,b are long
         # check if any names contains another
         return 1 if $a =~ m/\Q$b\E/i || $b =~ m/\Q$a\E/i;

         # check if both names belong to same domain
         $a = domain((split(/\s/, $a))[0]);
         $b = domain((split(/\s/, $b))[0]);
         return 1 if $a eq $b && $a =~ m/[\d\w\-_]+\.[\d\w\-_]+/;
      } else {                                          # a long, b short
         $b = (split(/\s/, $b))[0];
         return 1 if $a =~ m/^\Q$b\E\./i || $a =~ m/\@\Q$b\E/;
      }
   } else {
      if ($b =~ /[\d\w\-_]+[\.\@][\d\w\-_]+/ ) {        # a short, b long
         $a = (split(/\s/, $a))[0];
         return 1 if $b =~ m/^\Q$a\E\./i || $b =~ m/\@\Q$a\E/;
      } else {                                          # a, b are short
         return 0 if $a eq $b;
      }
   }

   return -1;
}

sub domain {
   # return domain part of a FQDN
   my $fqdn = shift;
   my @h = split(/\./, $fqdn);
   shift (@h);
   return join('.', @h);
}

sub append_filteredmsg_to_folder {
   my ($folderfile, $folderdb, $messageid, $r_attr, $r_currmessage, $user, $destination, $has_globallock) = @_;

   writelog("debug_mailprocess :: $folderfile :: append_filteredmsg_to_folder messageid $messageid") if $config{debug_mailprocess};

   if (!defined ${$r_currmessage} || ${$r_currmessage} eq '') {
      # lockget_message_block returns:
      # -1: lock/open error
      # -2: message id not in database
      # -3: invalid message size in database
      # -4: message size mismatch read error
      # -5: message start and end does not match index
      my $lockget_messagesize = lockget_message_block($messageid, $folderfile, $folderdb, $r_currmessage, $has_globallock);
      return $lockget_messagesize if $lockget_messagesize < 0;
   }

   my ($dstfile, $dstdb) = get_folderpath_folderdb($user, $destination);

   writelog("debug_mailprocess :: $folderfile :: destination $dstfile") if $config{debug_mailprocess};

   # -6: cannot open dstfile
   if (!-f $dstfile) {
      if (!sysopen(DEST, $dstfile, O_WRONLY|O_TRUNC|O_CREAT)) {
         writelog("cannot open file $dstfile ($!)");
         return -6;
      }

      close(DEST) or writelog("cannot close file $dstfile ($!)");
   }

   # -7: cannot lock dstfile
   if (!ow::filelock::lock($dstfile, LOCK_EX)) {
      writelog("cannot lock file $dstfile ($!)");
      return -7;
   }

   # append_message_to_folder returns:
   #  0: no errors
   # -1: cannot update index db       # -8
   # -2: cannot open db               # -9
   # -3: cannot open dstfile          # -10
   # -4: cannot close db              # -11
   # -5: io error printing to dstfile # -12
   my $append_err = append_message_to_folder($messageid, $r_attr, $r_currmessage, $dstfile, $dstdb);
   $append_err -= 7 if $append_err < 0; # decrement error number to come after previous errors (-8 to -12)

   # -13: cannot unlock dstfile
   if (!ow::filelock::lock($dstfile, LOCK_UN)) {
      writelog("cannot unlock file $dstfile ($!)");
      return -13;
   }

   return $append_err if $append_err < 0;

   return 0;
}

sub filterruledb_increase {
   my ($rulestr, $number) = @_;

   $number = 1 if $number == 0;

   my $filterruledb = dotpath('filter.ruledb');

   my %DB = ();

   if (ow::dbm::opendb(\%DB, $filterruledb, LOCK_EX)) {
      my $count = (split(':', $DB{$rulestr}))[0] + $number;
      my $date  = ow::datetime::gmtime2dateserial();
      $DB{$rulestr} = "$count:$date";
      ow::dbm::closedb(\%DB, $filterruledb) or writelog("cannot close db $filterruledb");;
      return 0;
   } else {
      writelog("cannot open db $filterruledb");
      return -1;
   }
}

sub filterfolderdb_increase {
   my ($foldername, $number) = @_;

   $number = 1 if !defined $number || $number <= 0;

   my $filterfolderdb = dotpath('filter.folderdb');

   my %DB = ();

   if (ow::dbm::opendb(\%DB, $filterfolderdb, LOCK_EX)) {
      $DB{$foldername} += $number;
      $DB{_TOTALFILTERED} += $number;
      ow::dbm::closedb(\%DB, $filterfolderdb) or writelog("cannot close db $filterfolderdb");
      return 0;
   } else {
      writelog("cannot open db $filterfolderdb");
      return -1;
   }
}

sub read_filterfolderdb {
   my $clear_after_read = shift;

   my $filterfolderdb = dotpath('filter.folderdb');

   my %DB = ();

   ow::dbm::opendb(\%DB, $filterfolderdb, LOCK_EX) or writelog("cannot open db $filterfolderdb");
   my %filtered = %DB;
   my $totalfiltered = $filtered{_TOTALFILTERED} || 0;
   delete $filtered{_TOTALFILTERED} if defined $filtered{_TOTALFILTERED};

   if ($clear_after_read) {
      %DB = ();
      if ($totalfiltered > 0) {
         my $dststr = '';
         foreach my $destination (sort keys %filtered) {
            next if $destination eq 'INBOX';
            $dststr .= ', ' if $dststr ne '';
            $dststr .= $destination;
            $dststr .= "($filtered{$destination})" if $filtered{$destination} ne $totalfiltered;
         }
         writelog("mailfilter - filter $totalfiltered messages from INBOX to $dststr");
         writehistory("mailfilter - filter $totalfiltered messages from INBOX to $dststr");
      }
   }

   ow::dbm::closedb(\%DB, $filterfolderdb) or writelog("cannot close db $filterfolderdb");

   return ($totalfiltered, %filtered);
}

1;
