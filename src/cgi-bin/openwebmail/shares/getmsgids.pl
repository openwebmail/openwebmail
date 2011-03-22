
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

# getmsgids.pl - get/search messageids and related info for message listview and folderview
#
# The search supports full content search and caches results for repeated queries.

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);

require "modules/mime.pl";

use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES); # defined in maildb.pl
use vars qw(%config %prefs);
use vars qw($_index_complete);
use vars qw(%sorttype);

%sorttype = (
               'date'          => ['sentdate', 0],
               'date_rev'      => ['sentdate', 1],
               'sentdate'      => ['sentdate', 0],
               'sentdate_rev'  => ['sentdate', 1],
               'recvdate'      => ['recvdate', 0],
               'recvdate_rev'  => ['recvdate', 1],
               'sender'        => ['sender', 0],
               'sender_rev'    => ['sender', 1],
               'recipient'     => ['recipient', 0],
               'recipient_rev' => ['recipient', 1],
               'size'          => ['size', 0],
               'size_rev'      => ['size', 1],
               'subject'       => ['subject', 1],
               'subject_rev'   => ['subject', 0],
               'status'        => ['status', 0],
               'status_rev'    => ['status', 1]
            );

sub getinfomessageids {
   my ($user, $folder, $sort, $msgdatetype, $searchtype, $keyword) = @_;

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   if ($sort eq 'date') {
      $sort = $msgdatetype || $prefs{msgdatetype};
   } elsif ($sort eq 'date_rev') {
      $sort = ($msgdatetype || $prefs{msgdatetype}).'_rev';
   }

   # do new indexing in background if folder > 10 M && empty db
   if (!ow::dbm::existdb($folderdb) && (-s $folderfile) >= 10485760) {
      local $_index_complete = 0;

      # signal when indexing completes
      local $SIG{CHLD} = sub { wait; $_index_complete = 1 if $? == 0 };

      # flush all output
      local $| = 1;

      # fork a child
      if (fork() == 0) {
         close(STDIN);  # close fd0
         close(STDOUT); # close fd1
         close(STDERR); # close fd2

         # perl automatically chooses the lowest available file
         # descriptor, so open some fake ones to occupy 0,1,2 to
         # avoid warnings
         sysopen(FDZERO, '/dev/null', O_RDONLY); # occupy fd0
         sysopen(FDONE, '/dev/null', O_WRONLY);  # occupy fd1
         sysopen(FDTWO, '/dev/null', O_WRONLY);  # occupy fd2

         local $SIG{__WARN__} = sub { writelog(@_); exit(1) };
         local $SIG{__DIE__}  = sub { writelog(@_); exit(1) };

         writelog("debug_fork :: update folderindex process forked") if $config{debug_fork};

         ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or openwebmail_exit(1);
         update_folderindex($folderfile, $folderdb);
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");

         writelog("debug_fork :: update folderindex process terminated") if $config{debug_fork};

         close(FDZERO);
         close(FDONE);
         close(FDTWO);

         openwebmail_exit(0);
      }

      for (my $i = 0; $i < 120; $i++) {
         # check every second for 120 seconds for index to complete
         sleep 1;
         last if $_index_complete;
      }

      # TODO: the error is not captured from the fork above so we have no idea why indexing failed
      openwebmailerror(gettext('Please try again later. The indexing process has not yet completed for folder:') . ' ' . f2u($folderfile))
        if $_index_complete == 0;
   } else {
      # do indexing directly if small folder
      # TODO: capture the errors and report them instead of just erroring out with generic messages
      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile));

      if (update_folderindex($folderfile, $folderdb) < 0) {
         ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
         openwebmailerror(gettext('Cannot update db:') . ' ' . f2u($folderdb));
      }

      ow::filelock::lock($folderfile, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . ' ' . f2u($folderfile));
   }

   my $totalsize       = 0;
   my $newmessages     = 0;
   my $r_messageids    = [];
   my $r_messagedepths = [];

   if ($keyword ne '') {
      my $folderhandle  = do { no warnings 'once'; local *FH };
      my %FDB           = ();
      my @messageids    = ();
      my @messagedepths = ();
      my $r_haskeyword  = {};

      ($r_messageids, $r_messagedepths) = get_messageids_sorted($folderdb, $sort, "$folderdb.cache", $prefs{hideinternal});

      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile));

      sysopen($folderhandle, $folderfile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($folderfile));

      $r_haskeyword = search_info_messages_for_keyword(
                                                         $keyword,
                                                         $prefs{charset},
                                                         $searchtype,
                                                         $folderdb,
                                                         $folderhandle,
                                                         dotpath('search.cache'),
                                                         $prefs{hideinternal},
                                                         $prefs{regexmatch}
                                                      );

      close($folderhandle) or writelog("cannot close file $folderfile ($!)");

      ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or writelog("cannot open db $folderdb");

      foreach my $messageid (keys %{$r_haskeyword}) {
         my @attr = string2msgattr($FDB{$messageid});
         $newmessages++ if defined $attr[$_STATUS] && $attr[$_STATUS] !~ m/R/i;
         $totalsize += $attr[$_SIZE];
      }

      ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");

      for (my $i = 0; $i < @{$r_messageids}; $i++) {
	my $id = $r_messageids->[$i];
	if (exists $r_haskeyword->{$id} && defined $r_haskeyword->{$id} && $r_haskeyword->{$id} == 1) {
	  push(@messageids, $id);
	  push(@messagedepths, $r_messagedepths->[$i]);
        }
      }

      return ($totalsize, $newmessages, \@messageids, \@messagedepths);
   } else {
      # return: $totalsize, $newmessages, $r_messageids for whole folder
      my %FDB = ();

      ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
         return($totalsize, $newmessages, $r_messageids, $r_messagedepths);

      $newmessages = $FDB{NEWMESSAGES};

      $totalsize = (stat($folderfile))[7];
      $totalsize = $totalsize - $FDB{INTERNALSIZE} - $FDB{ZAPSIZE};

      ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

      ($r_messageids, $r_messagedepths) = get_messageids_sorted($folderdb, $sort, "$folderdb.cache", $prefs{hideinternal});

      return ($totalsize, $newmessages, $r_messageids, $r_messagedepths);
   }
}

sub search_info_messages_for_keyword {
   # searchtype: subject, from, to, date, attfilename, header, textcontent, all
   # prefs_charset: the charset of the keyword
   my ($keyword, $prefs_charset, $searchtype, $folderdb, $folderhandle, $cachefile, $ignore_internal, $regexmatch) = @_;

   my $cache_lstmtime        = '';
   my $cache_folderdb        = '';
   my $cache_keyword         = '';
   my $cache_searchtype      = '';
   my $cache_ignore_internal = '';
   my %FDB                   = ();
   my @messageids            = ();
   my $messageid             = '';
   my %found                 = ();

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or return(\%found);

   my $lstmtime = $FDB{LSTMTIME};

   ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

   ow::filelock::lock($cachefile, LOCK_EX) or return(\%found);

   if (-e $cachefile) {
      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      foreach ($cache_lstmtime, $cache_folderdb, $cache_keyword, $cache_searchtype, $cache_ignore_internal) {
         $_ = <CACHE>;
         chomp;
      }

      close(CACHE) or writelog("cannot close file $cachefile ($!)");
   }

   if (
         $cache_lstmtime ne $lstmtime
         || $cache_folderdb ne $folderdb
         || $cache_keyword ne $keyword
         || $cache_searchtype ne $searchtype
         || $cache_ignore_internal ne $ignore_internal
      ) {
      $cachefile = ow::tool::untaint($cachefile);
      @messageids = get_messageids_sorted_by_offset($folderdb, $folderhandle);

      ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or return(\%found);

      # check if keyword a valid regex
      $regexmatch = $regexmatch && ow::tool::is_regex($keyword);

      my $userbrowsercharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{available_locales})))[4];

      foreach $messageid (@messageids) {
         my @attr          = ();
         my $date          = '';
         my $block         = '';
         my $header        = '';
         my $body          = '';
         my $r_attachments = [];

         @attr = string2msgattr($FDB{$messageid});

         next if $attr[$_STATUS] =~ m/Z/i;
         next if $ignore_internal && is_internal_subject($attr[$_SUBJECT]);

         my $msgcharset = $attr[$_CHARSET];

         # assume message is from sender using same language as the recipient browser if no charset defined
         $msgcharset = $userbrowsercharset if $msgcharset eq '' && $prefs_charset eq 'utf-8';

         ($attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]) = iconv('utf-8', $prefs_charset, $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]);

         if ($searchtype eq 'all' || $searchtype eq 'date') {
            $date = ow::datetime::dateserial2str($attr[$_DATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                                 $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone});
         }

         # check subject, from, to, date
         $found{$messageid} = 1 if (
                                      (
                                         ($searchtype eq 'all' || $searchtype eq 'subject')
                                         && (
                                               ($regexmatch && $attr[$_SUBJECT] =~ m/$keyword/i)
                                               || $attr[$_SUBJECT] =~ m/\Q$keyword\E/i
                                            )
                                      )

                                      ||

                                      (
                                         ($searchtype eq 'all' || $searchtype eq 'from')
                                         && (
                                               ($regexmatch && $attr[$_FROM] =~ m/$keyword/i)
                                               || $attr[$_FROM] =~ m/\Q$keyword\E/i
                                            )
                                      )

                                      ||

                                      (
                                         ($searchtype eq 'all' || $searchtype eq 'to')
                                         && (
                                               ($regexmatch && $attr[$_TO] =~ m/$keyword/i)
                                               || $attr[$_TO] =~ m/\Q$keyword\E/i
                                            )
                                      )

                                      ||

                                      (
                                         ($searchtype eq 'all' || $searchtype eq 'date')
                                         && (
                                               ($regexmatch && $date =~ m/$keyword/i)
                                               || $date =~ m/\Q$keyword\E/i
                                            )
                                      )
                                   );

         # try to find messages in same thread with references if seaching subject
         if ($searchtype eq 'subject') {
            my @references = defined $attr[$_REFERENCES] ? split(/\s+/, $attr[$_REFERENCES]) : ();

            foreach my $refid (@references) {
               # if a message is already in %found, then we put all messages it references in %found
               $found{$refid} = 1 if $found{$messageid} && defined $FDB{$refid};
               # if a message references any member in %found, than we put this message in %found
               $found{$messageid} = 1 if $found{$refid};
            }
         }

         next if exists $found{$messageid} && $found{$messageid};

         if ($searchtype eq 'all' || $searchtype eq 'header') {
	    # check header - check de-mimed header first since header in mail folder is raw format
            seek($folderhandle, $attr[$_OFFSET], 0);

            $header = '';

            while(<$folderhandle>) {
               $header .= $_;
               last if $_ eq "\n";
            }

            $header = decode_mimewords_iconv($header, $prefs_charset);
            $header =~ s/\n / /g; # handle folding roughly

            if (($regexmatch && $header =~ m/$keyword/im) || $header =~ m/\Q$keyword\E/im) {
               $found{$messageid} = 1;
               next;
            }
         }

         if ($searchtype eq 'all' || $searchtype eq 'textcontent' || $searchtype eq 'attfilename') {
            # read and parse message
            seek($folderhandle, $attr[$_OFFSET], 0);
            read($folderhandle, $block, $attr[$_SIZE]);
            ($header, $body, $r_attachments) = ow::mailparse::parse_rfc822block(\$block);
         }

         if ($searchtype eq 'all' || $searchtype eq 'textcontent') {
	    # check textcontent: text in body and attachments
            if ($attr[$_CONTENT_TYPE] =~ m/^text/i || $attr[$_CONTENT_TYPE] eq 'N/A') {
               # read all for text/plain,text/html
               my ($encoding) = $header =~ m/content-transfer-encoding:\s+([^\s+])/i;

               $body = ow::mime::decode_content($body, $encoding);

               $body = (iconv($msgcharset, $prefs_charset, $body))[0];

               if (($regexmatch && $body =~ m/$keyword/im) || $body =~ m/\Q$keyword\E/im) {
                  $found{$messageid} = 1;
                  next;
               }
            }

            # check attachments
            foreach my $r_attachment (@{$r_attachments}) {
               if ($r_attachment->{'content-type'} =~ m/^text/i || $r_attachment->{'content-type'} eq 'N/A') {
                  # read all for text/plain and text/html
                  my $content = ow::mime::decode_content(${$r_attachment->{r_content}}, $r_attachment->{'content-transfer-encoding'});

                  my $attcharset = $r_attachment->{charset} || $msgcharset;

                  ($content) = iconv($attcharset, $prefs_charset, $content);

                  if (($regexmatch && $content =~ m/$keyword/im) || $content =~ m/\Q$keyword\E/im) {
                     $found{$messageid} = 1;
                     last; # leave attachments check in one message
                  }
               }
            }
         }

         if ($searchtype eq 'all' || $searchtype eq 'attfilename') {
	    # check attfilename
            foreach my $r_attachment (@{$r_attachments}) {
               my $attcharset = $r_attachment->{filenamecharset} || $r_attachment->{charset} || $msgcharset;
               my ($filename) = iconv($attcharset, $prefs_charset, $r_attachment->{filename});

               if (($regexmatch && $filename =~ m/$keyword/im) || $filename =~ m/\Q$keyword\E/im) {
                  $found{$messageid} = 1;
                  last; # leave attachments check in one message
               }
            }
         }
      }

      ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

      sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      print CACHE join("\n", ($lstmtime, $folderdb, $keyword, $searchtype, $ignore_internal));

      print CACHE join("\n", keys(%found));

      close(CACHE) or writelog("cannot close file $cachefile ($!)");
   } else {
      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      $_ = <CACHE> for (0..4); # skip 5 lines

      while (<CACHE>) {
         chomp;
         $found{$_} = 1;
      }

      close(CACHE) or writelog("cannot close file $cachefile ($!)");
   }

   ow::filelock::lock($cachefile, LOCK_UN) or writelog("cannot unlock file $cachefile");

   return(\%found);
}

sub get_messageids_sorted {
   my ($folderdb, $sort, $cachefile, $ignore_internal) = @_;

   $ignore_internal = '' unless defined $ignore_internal;

   my $cache_lstmtime        = '';
   my $cache_folderdb        = '';
   my $cache_sort            = '';
   my $cache_ignore_internal = '';

   my %FDB                   = ();
   my $r_messageids          = [];
   my $r_messagedepths       = [];
   my @messageids            = ();
   my @messagedepths         = ();
   my $messageids_size       = 0;
   my $messagedepths_size    = 0;
   my $rev                   = 0;

   if (exists $sorttype{$sort} && defined $sorttype{$sort}) {
      ($sort, $rev) = @{$sorttype{$sort}};
   } else {
      ($sort, $rev) = ('date', 0);
   }

   if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH)) {
      writelog("cannot open db $folderdb");
      return(\@messageids, \@messagedepths);
   }

   my $lstmtime = $FDB{LSTMTIME};

   ow::dbm::closedb(\%FDB, $folderdb) or writelog("cannot close db $folderdb");

   if (!ow::filelock::lock($cachefile, LOCK_EX)) {
      writelog("cannot lock file $cachefile");
      return(\@messageids, \@messagedepths);
   }

   if (-e $cachefile) {
      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      foreach ($cache_lstmtime, $cache_folderdb, $cache_sort, $cache_ignore_internal) {
         $_ = <CACHE>;
         $_ = '' unless defined;
         chomp if defined;
      }

      close(CACHE) or writelog("cannot close file $cachefile ($!)");
   }

   # LSTMTIME will be upated in case the message list of a folder is changed,
   # eg: 1. db is rebuilt
   #     2. messages added into or removed from db
   # But LSTMTIME will not be changed in message_status_update
   # so we do not have to reload msglist from db after a message status is changed
   if (
         $cache_lstmtime ne $lstmtime
         || $cache_folderdb ne $folderdb
         || $cache_sort ne $sort
         || $cache_ignore_internal ne $ignore_internal
      ) {
      # cache is bad, rebuild it
      # gather the message ids and write them to the cachefile
      $cachefile = ow::tool::untaint($cachefile);

      sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      print CACHE $lstmtime, "\n", $folderdb, "\n", $sort, "\n", $ignore_internal, "\n";

      # message depths are only returned from get_messageids_sorted_by_subject()
      ($r_messageids, $r_messagedepths) = $sort eq 'sentdate'  ? get_messageids_sorted_by_sentdate($folderdb, $ignore_internal) :
                                          $sort eq 'recvdate'  ? get_messageids_sorted_by_recvdate($folderdb, $ignore_internal) :
                                          $sort eq 'sender'    ? get_messageids_sorted_by_from($folderdb, $ignore_internal)     :
                                          $sort eq 'recipient' ? get_messageids_sorted_by_to($folderdb, $ignore_internal)       :
                                          $sort eq 'size'      ? get_messageids_sorted_by_size($folderdb, $ignore_internal)     :
                                          $sort eq 'subject'   ? get_messageids_sorted_by_subject($folderdb, $ignore_internal)  :
                                          $sort eq 'status'    ? get_messageids_sorted_by_status($folderdb, $ignore_internal)   :
                                          get_messageids_sorted_by_sentdate($folderdb, $ignore_internal);

      $messageids_size    = scalar @{$r_messageids};
      @messagedepths      = @{$r_messagedepths} if defined $r_messagedepths && $r_messagedepths;
      $messagedepths_size = scalar @messagedepths;

      print CACHE join("\n", $messageids_size, $messagedepths_size, @{$r_messageids}, @messagedepths);

      close(CACHE) or writelog("cannot close file $cachefile ($!)");

      if ($rev) {
         @messageids    = reverse @{$r_messageids};
         @messagedepths = reverse @{$r_messagedepths} if $r_messagedepths;
      } else {
         @messageids    = @{$r_messageids};
         @messagedepths = @{$r_messagedepths} if $r_messagedepths;
      }
   } else {
      # cache is good, use it
      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $cachefile ($!)");

      # skip $lstmtime, $folderdb, $sort, $ignore_internal
      $_ = <CACHE> for (0..3);

      foreach ($messageids_size, $messagedepths_size) {
         $_ = <CACHE>;
         chomp;
      }

      my $i = 0;

      while (<CACHE>) {
         chomp;

         if ($rev) {
            if ($i < $messageids_size) {
               unshift (@messageids, $_);
            } else {
               unshift (@messagedepths, $_);
            }
         } else {
            if ($i < $messageids_size) {
               push (@messageids, $_);
            } else {
               push (@messagedepths, $_);
            }
         }

	 $i++;
      }

      close(CACHE) or writelog("cannot close file $cachefile ($!)");
   }

   ow::filelock::lock($cachefile, LOCK_UN) or writelog("cannot unlock file $cachefile");

   return (\@messageids, \@messagedepths);
}

sub get_messageids_sorted_by_sentdate {
   my ($folderdb, $ignore_internal) = @_;

   my ($total, $r_msgid2attrs) = get_msgid2attrs($folderdb, $ignore_internal, $_DATE);

   my @messageids = sort { $r_msgid2attrs->{$a}[0] <=> $r_msgid2attrs->{$b}[0] } keys %{$r_msgid2attrs};

   return \@messageids;
}

sub get_messageids_sorted_by_recvdate {
   my ($folderdb, $ignore_internal) = @_;

   my ($total, $r_msgid2attrs) = get_msgid2attrs($folderdb, $ignore_internal, $_RECVDATE);

   my @messageids = sort { $r_msgid2attrs->{$a}[0] <=> $r_msgid2attrs->{$b}[0] } keys %{$r_msgid2attrs};

   return \@messageids;
}

sub get_messageids_sorted_by_from {
   my ($folderdb, $ignore_internal) = @_;

   my ($total, $r_msgid2attrs) = get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_FROM);

   my %msgfromname = ();

   foreach my $id (keys %{$r_msgid2attrs}) {
      $msgfromname{$id} = lc((ow::tool::email2nameaddr($r_msgid2attrs->{$id}[1]))[0]);
   }

   my @messageids= sort {
                           $msgfromname{$a} cmp $msgfromname{$b}
                           || $r_msgid2attrs->{$b}[0] <=> $r_msgid2attrs->{$a}[0]
                        } keys %msgfromname;

   return \@messageids;
}

sub get_messageids_sorted_by_to {
   my ($folderdb, $ignore_internal) = @_;

   my ($total, $r_msgid2attrs) = get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_TO);

   my %msgtoname = ();

   foreach my $id (keys %{$r_msgid2attrs}) {
      my @tos = ow::tool::str2list($r_msgid2attrs->{$id}[1]);
      $msgtoname{$id} = lc((ow::tool::email2nameaddr($tos[0]))[0]);
   }

   # to is '' sometimes - push '' names to the end of the list by giving them priority 10
   my @messageids = sort {
                            my $apriority = defined $msgtoname{$a} && $msgtoname{$a} ne '' ? 1 : 10;
                            my $bpriority = defined $msgtoname{$b} && $msgtoname{$b} ne '' ? 1 : 10;

                            $apriority <=> $bpriority
                            || $msgtoname{$a} cmp $msgtoname{$b}
                            || $r_msgid2attrs->{$b}[0] <=> $r_msgid2attrs->{$a}[0]
                         } keys %msgtoname;

   return \@messageids;
}

sub get_messageids_sorted_by_size {
   my ($folderdb, $ignore_internal) = @_;

   my ($total, $r_msgid2attrs) = get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_SIZE);

   my @messageids= sort {
                           $r_msgid2attrs->{$a}[1] <=> $r_msgid2attrs->{$b}[1]
                           || $r_msgid2attrs->{$a}[0] <=> $r_msgid2attrs->{$b}[0]
                        } keys %{$r_msgid2attrs};

   return \@messageids;
}

sub get_messageids_sorted_by_status {
   my ($folderdb, $ignore_internal) = @_;

   my ($total, $r_msgid2attrs) = get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_STATUS);

   my %status = ();

   foreach my $key (keys %{$r_msgid2attrs}) {
      my $status = $r_msgid2attrs->{$key}[1];

      $status{$key} = $status =~ m/R/i ? 0 : 2;

      $status{$key}++ if $status =~ m/i/i;
   }

   my @messageids = sort {
                            $status{$b} <=> $status{$a}
                            || $r_msgid2attrs->{$b}[0] <=> $r_msgid2attrs->{$a}[0]
                         } keys %status;

   return \@messageids;
}

sub get_messageids_sorted_by_subject {
   # this routine actually sorts messages by thread
   my ($folderdb, $ignore_internal) = @_;

   my ($total, $r_msgid2attrs) = get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_REFERENCES, $_SUBJECT);

   my %subject = ();
   my %date    = ();

   foreach my $messageid (keys %{$r_msgid2attrs}) {
      $date{$messageid}    = $r_msgid2attrs->{$messageid}[0];
      $subject{$messageid} = $r_msgid2attrs->{$messageid}[2];
      $subject{$messageid} =~ s/Res?:\s*//ig;
      $subject{$messageid} =~ s/\[\d+\]//g;
      $subject{$messageid} =~ s/[\[\]]//g;
   }

   my @thread_pre_roots = ();
   my @thread_roots     = ();
   my %thread_parent    = ();
   my %thread_children  = ();

   # In the first pass we need to make sure each message has a valid
   # parent message.  We also track which messages will not have parent
   # messages (@thread_roots).
   foreach my $messageid (keys %date) {
      my $references = $r_msgid2attrs->{$messageid}[1];
      my @parents = reverse split(/ /, $references); # most nearby first
      my $parent = 'ROOT.nonexistant'; # this should be a string that would never be used as a messageid

      foreach my $id (@parents) {
         if ($id ne $messageid && defined $subject{$id}) {
 	    $parent = $id;
	    last;
         }
      }

      $thread_parent{$messageid}   = $parent;
      $thread_children{$messageid} = ();

      push(@thread_pre_roots, $messageid) if $parent eq 'ROOT.nonexistant';
   }

   # Some thread_parent will be completely disconnected, but title is the same
   # so we should connect them with the earliest article by the same title.
   @thread_pre_roots = sort {
                               $subject{$a} cmp $subject{$b}
                               || $date{$a} <=> $date{$b}
                            } @thread_pre_roots;

   my $previous_id = '';

   foreach my $id (@thread_pre_roots) {
      if ($previous_id && $subject{$id} eq $subject{$previous_id}) {
         $thread_parent{$id}   = $previous_id;
         $thread_children{$id} = ();
      } else {
         push(@thread_roots, $id);
         $previous_id = $id;
      }
   }

   # In the second pass we need to determine which children get
   # associated with which parent. We do this so we can traverse
   # the thread tree from the top down.
   #
   # We also update the parent date with the latest one of the children,
   # thus late coming message will not be hidden in case it belongs to a
   # very old root
   foreach my $id (sort { $date{$b} <=> $date{$a} } keys %thread_parent) {
      if ($thread_parent{$id} && $id ne 'ROOT.nonexistant') {
         $date{$thread_parent{$id}} = $date{$id} if $date{$thread_parent{$id}} lt $date{$id};
         push(@{$thread_children{$thread_parent{$id}}}, $id);
      }
   }

   my @message_ids    = ();
   my @message_depths = ();

   # Finally, we recursively traverse the tree.
   @thread_roots = sort { $date{$a} <=> $date{$b} } @thread_roots;

   foreach my $messageid (@thread_roots) {
      _recursively_thread($messageid, 0, \@message_ids, \@message_depths, \%thread_children, \%date);
   }

   return (\@message_ids, \@message_depths);
}

sub _recursively_thread {
   my ($id, $depth, $r_message_ids, $r_message_depths, $r_thread_children, $r_date) = @_;

   unshift @{$r_message_ids}, $id;
   unshift @{$r_message_depths}, $depth;

   if (defined $r_thread_children->{$id}) {
      my @children = sort { $r_date->{$a} <=> $r_date->{$b} } @{$r_thread_children->{$id}};

      foreach my $thread (@children) {
         _recursively_thread($thread, $depth+1, $r_message_ids, $r_message_depths, $r_thread_children, $r_date);
      }
   }

   return;
}

1;
