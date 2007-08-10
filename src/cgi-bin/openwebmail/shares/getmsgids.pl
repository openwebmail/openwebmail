#
# getmsgids.pl - get/search messageids and related info for msglist in for folderview
#
# The search supports full content search and caches results for repeated queries.
#

use strict;
use Fcntl qw(:DEFAULT :flock);
use MIME::Base64;
use MIME::QuotedPrint;

use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES);	# defined in maildb.pl
use vars qw(%config %prefs);
use vars qw(%lang_folders %lang_err);

use vars qw($_index_complete);
sub getinfomessageids {
   my ($user, $folder, $sort, $msgdatetype, $searchtype, $keyword)=@_;
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);

   if ($sort eq 'date') {
      $sort=$msgdatetype || $prefs{'msgdatetype'};
   } elsif ($sort eq 'date_rev') {
      $sort=($msgdatetype || $prefs{'msgdatetype'}).'_rev';
   }

   # do new indexing in background if folder > 10 M && empty db
   if (!ow::dbm::exist($folderdb) && (-s $folderfile) >= 10485760) {
      local $_index_complete=0;
      local $SIG{CHLD} = sub { wait; $_index_complete=1 if ($?==0) };	# signaled when indexing completes
      local $|=1; # flush all output
      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);
         writelog("debug - update folderindex process forked - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});

         ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or openwebmail_exit(1);
         update_folderindex($folderfile, $folderdb);
         ow::filelock::lock($folderfile, LOCK_UN);

         writelog("debug - update folderindex process terminated - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});
         openwebmail_exit(0);
      }

      for (my $i=0; $i<120; $i++) {	# wait index to complete for 120 seconds
         sleep 1;
         last if ($_index_complete);
      }

      if ($_index_complete==0) {
         openwebmailerror(__FILE__, __LINE__, f2u($folderfile)." $lang_err{'under_indexing'}");
      }
   } else {	# do indexing directly if small folder
      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} ".f2u($folderfile)."!");
      if (update_folderindex($folderfile, $folderdb)<0) {
         ow::filelock::lock($folderfile, LOCK_UN);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} db ".f2u($folderdb));
      }
      ow::filelock::lock($folderfile, LOCK_UN);
   }

   # Since recipients are displayed instead of sender in folderview of
   # SENT/DRAFT folder, the $sort must be changed from 'sender' to
   # 'recipient' in this case
   if ( $folder=~ m#sent-mail#i ||
        $folder=~ m#saved-drafts#i ||
        $folder=~ m#\Q$lang_folders{'sent-mail'}\E#i ||
        $folder=~ m#\Q$lang_folders{'saved-drafts'}\E#i ) {
      $sort='recipient' if ($sort eq 'sender');
   }

   my ($totalsize, $new, $r_messageids, $r_messagedepths);

   if ( $keyword ne '' ) {
      my $folderhandle=do { local *FH };
      my %FDB;
      my $r_haskeyword;
      my @messageids=();
      my @messagedepths=();

      ($r_messageids, $r_messagedepths)=get_messageids_sorted($folderdb, $sort, "$folderdb.cache", $prefs{'hideinternal'});

      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} ".f2u($folderfile)."!");

      sysopen($folderhandle, $folderfile, O_RDONLY);
      $r_haskeyword=search_info_messages_for_keyword(
			$keyword, $prefs{'charset'}, $searchtype, $folderdb, $folderhandle,
			dotpath('search.cache'), $prefs{'hideinternal'}, $prefs{'regexmatch'});
      close($folderhandle);

      ow::dbm::open(\%FDB, $folderdb, LOCK_SH);
      foreach my $messageid (keys %{$r_haskeyword}) {
         my @attr=string2msgattr($FDB{$messageid});
         $new++ if ($attr[$_STATUS]!~/R/i);
         $totalsize+=$attr[$_SIZE];
      }
      ow::dbm::close(\%FDB, $folderdb);

      ow::filelock::lock($folderfile, LOCK_UN);

      for (my $i=0; $i<@{$r_messageids}; $i++) {
	my $id = ${$r_messageids}[$i];
	if ( ${$r_haskeyword}{$id} == 1 ) {
	  push (@messageids, $id);
	  push (@messagedepths, ${$r_messagedepths}[$i]);
        }
      }
      return($totalsize, $new, \@messageids, \@messagedepths);

   } else { # return: $totalsize, $new, $r_messageids for whole folder
      my %FDB;

      ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         return($totalsize, $new, $r_messageids, $r_messagedepths);
      $new=$FDB{'NEWMESSAGES'};
      $totalsize=(stat($folderfile))[7];
      $totalsize=$totalsize-$FDB{'INTERNALSIZE'}-$FDB{'ZAPSIZE'};
      ow::dbm::close(\%FDB, $folderdb);

      ($r_messageids, $r_messagedepths)=get_messageids_sorted($folderdb, $sort, "$folderdb.cache", $prefs{'hideinternal'});

      return($totalsize, $new, $r_messageids, $r_messagedepths);
   }
}

# searchtype: subject, from, to, date, attfilename, header, textcontent, all
# prefs_charset: the charset of the keyword
sub search_info_messages_for_keyword {
   my ($keyword, $prefs_charset, $searchtype, $folderdb, $folderhandle, $cachefile, $ignore_internal, $regexmatch)=@_;
   my ($cache_lstmtime, $cache_folderdb, $cache_keyword, $cache_searchtype, $cache_ignore_internal);
   my (%FDB, @messageids, $messageid);
   my %found=();

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
      return(\%found);
   my $lstmtime=$FDB{'LSTMTIME'};
   ow::dbm::close(\%FDB, $folderdb);

   ow::filelock::lock($cachefile, LOCK_EX) or
      return(\%found);

   if ( -e $cachefile ) {
      sysopen(CACHE, $cachefile, O_RDONLY);
      foreach ($cache_lstmtime, $cache_folderdb, $cache_keyword, $cache_searchtype, $cache_ignore_internal) {
         $_=<CACHE>; chomp;
      }
      close(CACHE);
   }

   if ( $cache_lstmtime ne $lstmtime || $cache_folderdb ne $folderdb ||
        $cache_keyword ne $keyword || $cache_searchtype ne $searchtype ||
        $cache_ignore_internal ne $ignore_internal ) {
      $cachefile=ow::tool::untaint($cachefile);
      @messageids=get_messageids_sorted_by_offset($folderdb, $folderhandle);

      ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         return(\%found);

      # check if keyword a valid regex
      $regexmatch = $regexmatch && ow::tool::is_regex($keyword);

      foreach $messageid (@messageids) {
         my (@attr, $date, $block, $header, $body, $r_attachments);
         @attr=string2msgattr($FDB{$messageid});
         next if ($attr[$_STATUS]=~/Z/i);
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));

         my $msgcharset=$attr[$_CHARSET];
         if ($msgcharset eq '' && $prefs_charset eq 'utf-8') {
            # assume msg is from sender using same language as the recipient's browser
            my $browserlocale = ow::lang::guess_browser_locale($config{'available_locales'});
            $msgcharset = (ow::lang::localeinfo($browserlocale))[6];
         }
         ($attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT])=
               iconv('utf-8', $prefs_charset, $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]);

         if ($searchtype eq 'all' || $searchtype eq 'date') {
            $date=ow::datetime::dateserial2str($attr[$_DATE],
                                               $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                               $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'});
         }

         # check subject, from, to, date
         if ( ( ($searchtype eq 'all' ||
                 $searchtype eq 'subject') &&
                (($regexmatch && $attr[$_SUBJECT]=~/$keyword/i) ||
                 $attr[$_SUBJECT]=~/\Q$keyword\E/i) )  ||
              ( ($searchtype eq 'all' ||
                 $searchtype eq 'from') &&
                (($regexmatch && $attr[$_FROM]=~/$keyword/i) ||
                 $attr[$_FROM]=~/\Q$keyword\E/i) )  ||
              ( ($searchtype eq 'all' ||
                 $searchtype eq 'to') &&
                (($regexmatch && $attr[$_TO]=~/$keyword/i) ||
                 $attr[$_TO]=~/\Q$keyword\E/i) )  ||
              ( ($searchtype eq 'all' ||
                 $searchtype eq 'date') &&
                (($regexmatch && $date=~/$keyword/i) ||
                 $date=~/\Q$keyword\E/i) )
            ) {
            $found{$messageid}=1;
         }
         # try to find msgs in same thread with references if seaching subject
         if ($searchtype eq 'subject') {
            my @references=split(/\s+/, $attr[$_REFERENCES]);
            foreach my $refid (@references) {
               # if a msg is already in %found, then we put all msgs it references in %found
               $found{$refid}=1 if ($found{$messageid} && defined $FDB{$refid});
               # if a msg references any member in %found, thn we put this msg in %found
               $found{$messageid}=1 if ($found{$refid});
            }
         }
         if ($found{$messageid}) {
            next;
         }

	 # check header
         if ($searchtype eq 'all' || $searchtype eq 'header') {
            # check de-mimed header first since header in mail folder is raw format.
            seek($folderhandle, $attr[$_OFFSET], 0);
            $header="";
            while(<$folderhandle>) {
               $header.=$_;
               last if ($_ eq "\n");
            }
            $header = decode_mimewords_iconv($header, $prefs_charset);
            $header=~s/\n / /g;	# handle folding roughly

            if ( ($regexmatch && $header =~ /$keyword/im) ||
                 $header =~ /\Q$keyword\E/im ) {
               $found{$messageid}=1;
               next;
            }
         }

         # read and parse message
         if ($searchtype eq 'all' || $searchtype eq 'textcontent' || $searchtype eq 'attfilename') {
            seek($folderhandle, $attr[$_OFFSET], 0);
            read($folderhandle, $block, $attr[$_SIZE]);
            ($header, $body, $r_attachments)=ow::mailparse::parse_rfc822block(\$block);
         }

	 # check textcontent: text in body and attachments
         if ($searchtype eq 'all' || $searchtype eq 'textcontent') {
            # check body
            if ( $attr[$_CONTENT_TYPE] =~ /^text/i ||
                 $attr[$_CONTENT_TYPE] eq "N/A" ) { # read all for text/plain,text/html
               if ( $header =~ /content-transfer-encoding:\s+quoted-printable/i) {
                  $body = decode_qp($body);
               } elsif ($header =~ /content-transfer-encoding:\s+base64/i) {
                  $body = decode_base64($body);
               } elsif ($header =~ /content-transfer-encoding:\s+x-uuencode/i) {
                  $body = ow::mime::uudecode($body);
               }
               ($body)=iconv($msgcharset, $prefs_charset, $body);
               if ( ($regexmatch && $body =~ /$keyword/im) ||
                    $body =~ /\Q$keyword\E/im ) {
                  $found{$messageid}=1;
                  next;
               }
            }
            # check attachments
            foreach my $r_attachment (@{$r_attachments}) {
               if ( ${$r_attachment}{'content-type'} =~ /^text/i ||
                    ${$r_attachment}{'content-type'} eq "N/A" ) {	# read all for text/plain. text/html
                  my $content;
                  if ( ${$r_attachment}{'content-transfer-encoding'} =~ /^quoted-printable/i ) {
                     $content = decode_qp( ${${$r_attachment}{r_content}});
                  } elsif ( ${$r_attachment}{'content-transfer-encoding'} =~ /^base64/i ) {
                     $content = decode_base64( ${${$r_attachment}{r_content}});
                  } elsif ( ${$r_attachment}{'content-transfer-encoding'} =~ /^x-uuencode/i ) {
                     $content = ow::mime::uudecode( ${${$r_attachment}{r_content}});
                  } else {
                     $content=${${$r_attachment}{r_content}};
                  }
                  my $attcharset=${$r_attachment}{charset}||$msgcharset;
                  ($content)=iconv($attcharset, $prefs_charset, $content);

                  if ( ($regexmatch && $content =~ /$keyword/im) ||
                       $content =~ /\Q$keyword\E/im ) {
                     $found{$messageid}=1;
                     last;	# leave attachments check in one message
                  }
               }
            }
         }

	 # check attfilename
         if ($searchtype eq 'all' || $searchtype eq 'attfilename') {
            foreach my $r_attachment (@{$r_attachments}) {
               my $attcharset=${$r_attachment}{filenamecharset}||${$r_attachment}{charset}||$msgcharset;
               my ($filename)=iconv($attcharset, $prefs_charset, ${$r_attachment}{filename});

               if ( ($regexmatch && $filename =~ /$keyword/im) ||
                    $filename =~ /\Q$keyword\E/im ) {
                  $found{$messageid}=1;
                  last;	# leave attachments check in one message
               }
            }
         }
      }

      ow::dbm::close(\%FDB, $folderdb);

      sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT) or logtime("cache write error $!");
      foreach ($lstmtime, $folderdb, $keyword, $searchtype, $ignore_internal) {
         print CACHE $_, "\n";
      }
      print CACHE join("\n", keys(%found));
      close(CACHE);

   } else {
      sysopen(CACHE, $cachefile, O_RDONLY);
      for (0..4) { $_=<CACHE>; }	# skip 5 lines
      while (<CACHE>) {
         chomp; $found{$_}=1;
      }
      close(CACHE);
   }

   ow::filelock::lock($cachefile, LOCK_UN);

   return(\%found);
}

########## GET_MESSAGEIDS_SORTED_BY_...  #########################

use vars qw(%sorttype);
%sorttype= (
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

sub get_messageids_sorted {
   my ($folderdb, $sort, $cachefile, $ignore_internal)=@_;
   my ($cache_lstmtime, $cache_folderdb, $cache_sort, $cache_ignore_internal);
   my %FDB;
   my $r_messageids;
   my $r_messagedepths;
   my @messageids=();
   my @messagedepths=();
   my $messageids_size;
   my $messagedepths_size;
   my $rev;

   if (defined $sorttype{$sort}) {
      ($sort, $rev)=@{$sorttype{$sort}};
   } else {
      ($sort, $rev)= ('date', 0);
   }

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
      return(\@messageids, \@messagedepths);
   my $lstmtime=$FDB{'LSTMTIME'};
   ow::dbm::close(\%FDB, $folderdb);

   ow::filelock::lock($cachefile, LOCK_EX) or
      return(\@messageids, \@messagedepths);

   if ( -e $cachefile ) {
      sysopen(CACHE, $cachefile, O_RDONLY);
      foreach ($cache_lstmtime, $cache_folderdb, $cache_sort, $cache_ignore_internal) {
         $_=<CACHE>; chomp;
      }
      close(CACHE);
   }

   # LSTMTIME will be upated in case the message list of a folder is changed,
   # eg: 1. db is rebuild
   #     2. messages added into or removed from db
   # But LSTMTIME won't be changed in message_status_update.
   # so we don't have to reload msglist from db after a message status is changed
   if ( $cache_lstmtime ne $lstmtime || $cache_folderdb ne $folderdb ||
        $cache_sort ne $sort || $cache_ignore_internal ne $ignore_internal) {
      $cachefile=ow::tool::untaint($cachefile);
      sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT);
      print CACHE $lstmtime, "\n", $folderdb, "\n", $sort, "\n", $ignore_internal, "\n";
      if ( $sort eq 'sentdate') {
         ($r_messageids)=get_messageids_sorted_by_sentdate($folderdb, $ignore_internal);
      } elsif ( $sort eq 'recvdate' ) {
         ($r_messageids)=get_messageids_sorted_by_recvdate($folderdb, $ignore_internal);
      } elsif ( $sort eq 'sender' ) {
         ($r_messageids)=get_messageids_sorted_by_from($folderdb, $ignore_internal);
      } elsif ( $sort eq 'recipient' ) {
         ($r_messageids)=get_messageids_sorted_by_to($folderdb, $ignore_internal);
      } elsif ( $sort eq 'size' ) {
         ($r_messageids)=get_messageids_sorted_by_size($folderdb, $ignore_internal);
      } elsif ( $sort eq 'subject' ) {
         ($r_messageids, $r_messagedepths)=get_messageids_sorted_by_subject($folderdb, $ignore_internal);
      } elsif ( $sort eq 'status' ) {
         ($r_messageids)=get_messageids_sorted_by_status($folderdb, $ignore_internal);
      }

      $messageids_size = @{$r_messageids};

      @messagedepths=@{$r_messagedepths} if $r_messagedepths;
      $messagedepths_size = @messagedepths;

      print CACHE join("\n", $messageids_size, $messagedepths_size, @{$r_messageids}, @messagedepths);
      close(CACHE);
      if ($rev) {
         @messageids=reverse @{$r_messageids};
         @messagedepths=reverse @{$r_messagedepths} if $r_messagedepths;
      } else {
         @messageids=@{$r_messageids};
         @messagedepths=@{$r_messagedepths} if $r_messagedepths;
      }

   } else {
      sysopen(CACHE, $cachefile, O_RDONLY);
      for (0..3) { $_=<CACHE>; }	# skip $lstmtime, $folderdb, $sort, $ignore_internal
      foreach ($messageids_size, $messagedepths_size) {
         $_=<CACHE>; chomp;
      }
      my $i = 0;
      while (<CACHE>) {
         chomp;
         if ($rev) {
            if ($i < $messageids_size) { unshift (@messageids, $_); }
            else { unshift (@messagedepths, $_); }
         } else {
            if ($i < $messageids_size) { push (@messageids, $_); }
            else { push (@messagedepths, $_); }
         }
	 $i++;
      }
      close(CACHE);
   }
   ow::filelock::lock($cachefile, LOCK_UN);

   return(\@messageids, \@messagedepths);
}


sub get_messageids_sorted_by_sentdate {
   my ($folderdb, $ignore_internal)=@_;

   my ($total, $r_msgid2attrs)=get_msgid2attrs($folderdb, $ignore_internal, $_DATE);
   my @messageids= sort {
                        ${${$r_msgid2attrs}{$a}}[0]<=>${${$r_msgid2attrs}{$b}}[0];
                        } keys %{$r_msgid2attrs};
   return(\@messageids);
}

sub get_messageids_sorted_by_recvdate {
   my ($folderdb, $ignore_internal)=@_;

   my ($total, $r_msgid2attrs)=get_msgid2attrs($folderdb, $ignore_internal, $_RECVDATE);
   my @messageids= sort {
                        ${${$r_msgid2attrs}{$a}}[0]<=>${${$r_msgid2attrs}{$b}}[0];
                        } keys %{$r_msgid2attrs};
   return(\@messageids);
}

sub get_messageids_sorted_by_from {
   my ($folderdb, $ignore_internal)=@_;

   my ($total, $r_msgid2attrs)=get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_FROM);

   my %msgfromname=();
   foreach my $id (keys %{$r_msgid2attrs}) {
      $msgfromname{$id}= lc ( (ow::tool::email2nameaddr(${${$r_msgid2attrs}{$id}}[1]))[0] );
   }
   my @messageids= sort {
                        $msgfromname{$a} cmp $msgfromname{$b} or
                        ${${$r_msgid2attrs}{$b}}[0]<=>${${$r_msgid2attrs}{$a}}[0];
                        } keys %msgfromname;
   return(\@messageids);
}

sub get_messageids_sorted_by_to {
   my ($folderdb, $ignore_internal)=@_;

   my ($total, $r_msgid2attrs)=get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_TO);

   my %msgtoname=();
   foreach my $id (keys %{$r_msgid2attrs}) {
      my @tos=ow::tool::str2list(${${$r_msgid2attrs}{$id}}[1]);
      $msgtoname{$id}= lc( (ow::tool::email2nameaddr($tos[0]))[0] );
   }
   my @messageids= sort {
                        $msgtoname{$a} cmp $msgtoname{$b} or
                        ${${$r_msgid2attrs}{$b}}[0]<=>${${$r_msgid2attrs}{$a}}[0];
                        } keys %msgtoname;
   return(\@messageids);
}

sub get_messageids_sorted_by_size {
   my ($folderdb, $ignore_internal)=@_;

   my ($total, $r_msgid2attrs)=get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_SIZE);
   my @messageids= sort {
                        ${${$r_msgid2attrs}{$a}}[1]<=>${${$r_msgid2attrs}{$b}}[1] or
                        ${${$r_msgid2attrs}{$a}}[0]<=>${${$r_msgid2attrs}{$b}}[0]
                        } keys %{$r_msgid2attrs};
   return(\@messageids);
}

sub get_messageids_sorted_by_status {
   my ($folderdb, $ignore_internal)=@_;

   my ($total, $r_msgid2attrs)=get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_STATUS);
   my %status;
   foreach my $key (keys %{$r_msgid2attrs}) {
      my $status=${${$r_msgid2attrs}{$key}}[1];
      if ($status=~/R/i) {
         $status{$key}=0;
      } else {
         $status{$key}=2;
      }
      $status{$key}++ if ($status=~/i/i);
   }
   my @messageids=sort {
                       $status{$b} <=> $status{$a} or
                       ${${$r_msgid2attrs}{$b}}[0]<=>${${$r_msgid2attrs}{$a}}[0]
                       } keys %status;
   return(\@messageids);
}

# this routine actually sorts messages by thread,
# contributed by <james.AT.tiger-marmalade.com> James Dean Palmer
sub get_messageids_sorted_by_subject {
   my ($folderdb, $ignore_internal)=@_;

   my ($total, $r_msgid2attrs)=get_msgid2attrs($folderdb, $ignore_internal, $_DATE, $_REFERENCES, $_SUBJECT);

   my (%subject, %date);
   foreach my $key (keys %{$r_msgid2attrs}) {
      $date{$key}=${${$r_msgid2attrs}{$key}}[0];
      $subject{$key}=${${$r_msgid2attrs}{$key}}[2];
      $subject{$key}=~s/Res?:\s*//ig;
      $subject{$key}=~s/\[\d+\]//g;
      $subject{$key}=~s/[\[\]]//g;
   }

   my (%thread_parent, @thread_pre_roots, @thread_roots, %thread_children);

   # In the first pass we need to make sure each message has a valid
   # parent message.  We also track which messages won't have parent
   # messages (@thread_roots).
   foreach my $key (keys %date) {
      my @parents = reverse split(/ /, ${${$r_msgid2attrs}{$key}}[1]); # most nearby first
      my $parent = "ROOT.nonexist";	# this should be a string that would never be used as a messageid
      foreach my $id (@parents) {
         if ($id ne $key && defined $subject{$id}) {
 	    $parent = $id;
	    last;
         }
      }
      $thread_parent{$key} = $parent;
      $thread_children{$key} = ();
      push @thread_pre_roots, $key if ($parent eq "ROOT.nonexist");
   }

   # Some thread_parent will be completely disconnected, but title is the same
   # so we should connect them with the earliest article by the same title.
   @thread_pre_roots = sort {
                            $subject{$a} cmp $subject{$b} or
                            $date{$a} <=> $date{$b}
                            } @thread_pre_roots;
   my $previous_id = "";
   foreach my $id (@thread_pre_roots) {
      if ($previous_id && $subject{$id} eq $subject{$previous_id}) {
         $thread_parent{$id} = $previous_id;
         $thread_children{$id} = ();
      } else {
         push @thread_roots, $id;
         $previous_id = $id;
      }
   }

   # In the second pass we need to determine which children get
   # associated with which parent.  We do this so we can traverse
   # the thread tree from the top down.
   #
   # We also update the parent date with the latest one of the children,
   # thus late coming message won't be hidden in case it belongs to a
   # very old root
   #
   foreach my $id (sort {$date{$b}<=>$date{$a};} keys %thread_parent) {
      if ($thread_parent{$id} && $id ne "ROOT.nonexist") {
         if ($date{$thread_parent{$id}} lt $date{$id} ) {
            $date{$thread_parent{$id}}=$date{$id};
         }
         push @{$thread_children{$thread_parent{$id}}}, $id;
      }
   }

   my (@message_ids, @message_depths);

   # Finally, we recursively traverse the tree.
   @thread_roots = sort { $date{$a} <=> $date{$b}; } @thread_roots;
   foreach my $key (@thread_roots) {
      _recursively_thread ($key, 0,
		\@message_ids, \@message_depths, \%thread_children, \%date);
   }
   return(\@message_ids, \@message_depths);
}

sub _recursively_thread {
   my ($id, $depth,
	$r_message_ids, $r_message_depths, $r_thread_children, $r_date) = @_;

   unshift @{$r_message_ids}, $id;
   unshift @{$r_message_depths}, $depth;
   if (defined ${$r_thread_children}{$id}) {
      my @children = sort { ${$r_date}{$a} <=> ${$r_date}{$b}; } @{${$r_thread_children}{$id}};
      foreach my $thread (@children) {
         _recursively_thread ($thread, $depth+1,
	 $r_message_ids, $r_message_depths, $r_thread_children, $r_date);
      }
   }
   return;
}

########## END GET_MESSAGEIDS_SORTED_BY_...  #####################

1;
