#
# maildb.pl - mail indexing/parsing routines
#
# 2001/12/21 tung.AT.turtle.ee.ncku.edu.tw
#
# Description
#
# 1. it speeds up the message access on folder file by caching important
#    information with perl dbm.
# 2. it parse mail recursively.
# 3. it converts uuencoded blocks into baed64-encoded attachments
# 4. it supports full content search and caches results for repeated queries.
#
# IMPORTANT!!!
#
# Functions in this file will do locks for dbm before read/write.
# but they don't do locks for folderfile/folderhandle. They rely the
# caller to do that lock
# Functions with folderfile/folderhandle in argument must be inside
# a folderfile lock session
#
# The following global variables needs to be defined
# $config{'dbm_ext'} - the ext name of db
# $config{'dbmopen_ext'} - the ext name passed when doing dbmopen
# $config{'dbmopen_haslock'} - whether dbmopen() will do filelock by itself
# $config{'use_dotlockfile'} - whether to use dotlockfile style locking,
#                              recommended only if the lockd on your nfs
#                              server or client is broken
# ps: FrreBSD/Linux nfs server/client may need this. Solaris doesn't.
#
use strict;
use Fcntl qw(:DEFAULT :flock);

# extern vars, defined in caller openwebmail-xxx.pl
use vars qw(%config);

# globals, message attribute number constant
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET);
($_OFFSET, $_FROM, $_TO, $_DATE, $_SUBJECT, $_CONTENT_TYPE, $_STATUS, $_SIZE, $_REFERENCES, $_CHARSET)
 =(0,1,2,3,4,5,6,7,8,9);

# dirty init
$config{'dbm_ext'}=".db" if ($config{'dbm_ext'} eq "");

######################### UPDATE_HEADERDB ############################
# this routine indexes the messages in a mailfolder
# and remove those with duplicated messageids
sub update_headerdb {
   my ($headerdb, $folderfile) = @_;
   my (%HDB, %OLDHDB);
   my @oldmessageids=();
   my $dberr=0;

   ($headerdb =~ /^(.+)$/) && ($headerdb = $1);		# untaint ...
   if ( -e "$headerdb$config{'dbm_ext'}" ) {
      my ($metainfo, $allmessages, $internalmessages, $newmessages);

      open_dbm(\%HDB, $headerdb, LOCK_SH) or return -1;

      $metainfo=$HDB{'METAINFO'};
      $allmessages=$HDB{'ALLMESSAGES'};
      $internalmessages=$HDB{'INTERNALMESSAGES'};
      $newmessages=$HDB{'NEWMESSAGES'};

      close_dbm(\%HDB, $headerdb);

      if ( $metainfo eq metainfo($folderfile) && $allmessages >=0
           && $internalmessages >=0 && $newmessages >=0 ) {
         return 0;
      }

      rename("$headerdb.dir", "$headerdb.old.dir");
      rename("$headerdb.pag", "$headerdb.old.pag");
      rename("$headerdb$config{'dbm_ext'}", "$headerdb.old$config{'dbm_ext'}") if ($config{'dbm_ext'} ne '.dir' and $config{'dbm_ext'} ne '.pag') ;

      # we will try to reference records in old headerdb if possible
      @oldmessageids=get_messageids_sorted_by_offset("$headerdb.old");

      open_dbm(\%OLDHDB, "$headerdb.old", LOCK_SH) or return -1;
   }

   my ($messagenumber, $newmessages, $internalmessages) = (-1, 0, 0);
   my ($inheader, $offset, $totalsize)=(0, 0, 0);
   my @duplicateids=();

   my ($line, $lastheader, $delimiter, $has_att, $verified);
   my ($_message_id, $_offset);
   my ($_from, $_to, $_date, $_subject);
   my ($_content_type, $_status, $_messagesize, $_references, $_inreplyto, $_charset);

   my $ret=open_dbm(\%HDB, $headerdb, LOCK_EX);
   if (!$ret) {
      close_dbm(\%OLDHDB, "$headerdb.old") if (defined(%OLDHDB));
      return -1;
   }

   %HDB=();	# ensure the headerdb is empty

   open (FOLDER, $folderfile);

   # copy records from oldhdb as more as possible
   my $foldersize=(stat(FOLDER))[7];
   foreach my $id (@oldmessageids) {
      my @attr=split(/\@\@\@/, $OLDHDB{$id});
      my $buff;

      last if ($attr[$_OFFSET] != $totalsize);
      $totalsize+=$attr[$_SIZE];

      if ($totalsize!=$foldersize) {
         seek(FOLDER, $totalsize, 0);
         read(FOLDER, $buff, 5);	# file ptr is 5 byte after totalsize now!
      } else {
         $buff="From ";
      }

      if ( $buff=~/^From /) { # ya, msg end is found!
         if ( ! ($HDB{$id}=join('@@@', @attr)) ) {
            $totalsize-=$attr[$_SIZE];
            last;
         }
         $internalmessages++ if ( is_internal_subject($attr[$_SUBJECT]) );
         $newmessages++ if ($attr[$_STATUS] !~ /r/i);
         $messagenumber++;
      }  else {
         $totalsize-=$attr[$_SIZE];
         last;
      }
   }
   seek(FOLDER, $totalsize, 0);		# set file ptr back to totalsize

   my $eof=0;
   while ( !$dberr ) {
      if (defined($line = <FOLDER>)) {
         $offset=$totalsize;
         $totalsize += length($line);
      } else {
         $eof=1;
      }

      # ex: From Tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
      # ex: From Tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
      # ex: From Nssb@thumper.bellcore.com Wed Mar 11 16:27:37 EST 1992
      if ( $eof || $line =~ /^From .*(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+([A-Z]{3,4}\d?\s+)?(\d\d+)/ ) {
         if ($_messagesize >0) {	# save previous msg

            $_from=~s/\@\@/\@\@ /g;         $_from=~s/\@$/\@ /;
            $_to=~s/\@\@/\@\@ /g;           $_to=~s/\@$/\@ /;
            $_subject=~s/\@\@/\@\@ /g;      $_subject=~s/\@$/\@ /;
            $_content_type=~s/\@\@/\@\@ /g; $_content_type=~s/\@$/\@ /;
            $_status=~s/\@\@/\@\@ /g;       $_status=~s/\@$/\@ /;
            $_references=~s/\@\@/\@\@ /g;   $_references=~s/\@$/\@ /;
            $_inreplyto=~s/\@\@/\@\@ /g;    $_inreplyto=~s/\@$/\@ /;

            # try to get charset from contenttype header
            $_charset=$1 if ($_charset eq "" && $_content_type=~/charset\s*=\s*"?([^\s"';]*)"?\s?/i);

            # in most case, a msg references field should already contain
            # ids in in-reply-to: field, but do check it again here
            if ($_inreplyto =~ m/^\s*(\<\S+\>)\s*$/) {
               $_references .= " " . $1 if ($_references!~/\Q$1\E/);
            }
            $_references =~ s/\s{2,}/ /g;

            if ($_message_id eq '') {	# fake messageid with date and from
               $_message_id="$_date.".(email2nameaddr($_from))[1];
               $_message_id=~s![\<\>\(\)\s\/"':]!!g;
               $_message_id="<$_message_id>";
            }
            # dbm record should not longer than 1024? cut here to make dbm happy
            $_message_id='<'.substr($_message_id, 1, 250).'>' if (length($_message_id)>256);

            # flags used by openwebmail internally
            $_status .= "T" if ($has_att);
            $_status .= "V" if ($verified);

            	if (! defined($HDB{$_message_id}) ) {
               $HDB{$_message_id}=make_msgrecord($_message_id, $_offset, $_from, $_to,
                  $_date, $_subject, $_content_type, $_status, $_messagesize, $_references, $_charset)
                  or $dberr++;
            } else {
               my $dup=$#duplicateids+1;
               $HDB{"dup$dup-$_message_id"}=make_msgrecord("dup$dup-$_message_id", $_offset, $_from, $_to,
		  $_date, $_subject, $_content_type, $_status, $_messagesize, $_references, $_charset)
                  or $dberr++;
               push(@duplicateids, "dup$dup-$_message_id") if (!$dberr);
            }
         }

         last if ($eof||$dberr);

         $messagenumber++;
         $delimiter=$line;
         $_offset=$offset;
         $_from = $_to = $_date = $_subject = $_content_type ='N/A';
         $_charset = $_message_id = $_inreplyto = $_references = $_status = '';
         $_messagesize = length($line);
         $inheader = 1;
         $lastheader = 'NONE';
         $has_att=0;
         $verified=0;

      } else {
         $_messagesize += length($line);

         if ($inheader) {
            if ($line =~ /^\r*$/) {	# 1st blank line after msg header
               $inheader = 0;

               # Convert to readable text from MIME-encoded
               $_from = decode_mimewords($_from);
               $_to = decode_mimewords($_to);
               $_subject = decode_mimewords($_subject);

               # some dbm(ex:ndbm on solaris) can only has value shorter than 1024 byte,
               # so we cut $_to to 256 byte to make dbm happy
               $_to=substr($_to, 0, 252)."..." if (length($_to)>256);

               my $dateserial=datefield2dateserial($_date);
               my $deliserial=delimiter2dateserial($delimiter, $config{'deliver_use_GMT'}) ||
                              gmtime2dateserial();
               if ($dateserial eq "") {
                  $dateserial=$deliserial; 
               } elsif ($deliserial ne "") {
                   my $t=dateserial2gmtime($deliserial)-dateserial2gmtime($dateserial); 
                   if ($t>86400*7 || $t<-86400) { # msg transmission time
                      # use deliverytime in case sender host may have wrong time configuration
                      $dateserial=$deliserial; 
                   }
               }
               $_date=$dateserial;

               $internalmessages++ if (is_internal_subject($_subject));
               $newmessages++ if ($_status !~ /r/i);

               # check if msg info recorded in old headerdb, we can seek to msg end quickly
               if (defined($OLDHDB{$_message_id}) ) {
                  my ($oldstatus, $oldmsgsize)=
                     (split(/@@@/, $OLDHDB{$_message_id}))[$_STATUS, $_SIZE];
                  my $buff='';

                  seek(FOLDER, $_offset+$oldmsgsize, 0);
                  read(FOLDER, $buff, 5);

                  if ( $buff=~/^From /) { # ya, msg end is found!
                     $_messagesize=$oldmsgsize;
                     $totalsize=$_offset+$_messagesize;
                     # copy vars related to content
                     $has_att=1  if ($oldstatus=~/T/);
                     $verified=1 if ($oldstatus=~/V/);
                  }

                  seek(FOLDER, $totalsize, 0);
               }

            } elsif ($line =~ /^\s/) {
               $line =~ s/^\s+/ /;
               chomp($line);
               if    ($lastheader eq 'FROM') { $_from .= $line }
               elsif ($lastheader eq 'TO') { $_to .= $line }
               elsif ($lastheader eq 'SUBJ') { $_subject .= $line }
               elsif ($lastheader eq 'DATE') { $_date .= $line; }
               elsif ($lastheader eq 'MESSID') { $_message_id .= $line; }
               elsif ($lastheader eq 'TYPE') { $_content_type .= $line; }
	       elsif ($lastheader eq 'REFERENCES') { $_references .= "$line "; }
	       elsif ($lastheader eq 'INREPLYTO') { $_inreplyto .= "$line "; }
            } elsif ($line =~ /^from:\s*(.*)$/ig) {
               $_from = $1;
               $lastheader = 'FROM';
            } elsif ($line =~ /^to:\s*(.*)$/ig) {
               $_to = $1;
               $lastheader = 'TO';
            } elsif ($line =~ /^subject:\s*(.*)$/ig) {
               $_subject = $1;
               $lastheader = 'SUBJ';
            } elsif ($line =~ /^date:\s*(.*)$/ig) {
               $_date = $1;
               $lastheader = 'DATE';
            } elsif ($line =~ /^message-id:\s*(.*)$/ig) {
               $_message_id = $1;
               $lastheader = 'MESSID';
	    } elsif ($line =~ /^in-reply-to:\s*(.*)$/ig) {
               $_inreplyto .= $1 . " ";
               $lastheader = 'INREPLYTO';
	    } elsif ($line =~ /^references:\s*(.*)$/ig) {
               $_references .= $1 . " ";
               $lastheader = 'REFERENCES';
            } elsif ($line =~ /^content-type:\s*(.*)$/ig) {
               $_content_type = $1;
               $lastheader = 'TYPE';
            } elsif ($line =~ /^status:\s*(.*)$/i ||
                     $line =~ /^x\-status:\s*(.*)$/i ) {
               $_status .= $1;
               $_status =~ s/\s//g;	# remove blanks
               $lastheader = 'NONE';
            } elsif ($line =~ /^priority:\s*(.*)$/i) {
               my $priority=$1;
               if ($priority =~ /^\s*urgent\s*$/i) {
                  $_status .= "I";
               }
               $lastheader = 'NONE';
            } else {
               $lastheader = 'NONE';
            }

         } else {
            if ($has_att==0 &&
                ($line =~ /^content\-type:.*;\s+name\s*\*?=/i ||
                 $line =~ /^\s+name\s*=/i ||
                 $line =~ /^content\-disposition:.*;\s+filename\s*\*?=/i ||
                 $line =~ /^\s+filename\s*=/i ||
                 $line =~ /^begin [0-7][0-7][0-7][0-7]? [^\n\r]+/) &&
                ($line !~ /[\<\>]/ && $line !~ /type=/i) ) {
               $has_att=1;
            }
            if ($_charset eq '' &&
                ($line =~ /^content\-type:.*;\s?charset="?([^\s"';]*)"?/i ||
                 $line =~ /^\s+charset="?([^\s"';]*)"?/i) ) {
               $_charset=$1;
            }
         }
      }

   } # end while( !$dberr )

   close (FOLDER);

   if ( !$dberr ) {
      $HDB{'ALLMESSAGES'}=$messagenumber+1;
      $HDB{'INTERNALMESSAGES'}=$internalmessages;
      $HDB{'NEWMESSAGES'}=$newmessages;
      $HDB{'METAINFO'}=metainfo($folderfile) or $dberr++;
   }

   close_dbm(\%HDB, $headerdb);

   # remove old headerdb
   if (defined(%OLDHDB)) {
      close_dbm(\%OLDHDB, "$headerdb.old");
      unlink("$headerdb.old$config{'dbm_ext'}", "$headerdb.old.dir", "$headerdb.old.pag");
   }

   if ($dberr) {
      return -1;
   } else {
      # remove if any duplicates
      operate_message_with_ids("delete", \@duplicateids, $folderfile, $headerdb) if ($#duplicateids>=0);
      return 1;
   }
}

sub make_msgrecord {
   my $key=shift(@_);
   my $value=join('@@@', @_);
   return $value if (length($key.$value)<=1000);

   foreach my $field ($_TO, $_SUBJECT, $_REFERENCES) {
      $_[$field]=substr($_[$field],0,256) if (length($_[$field])>256);
   }
   $value=join('@@@', @_);
   return $value if (length($key.$value)<=1000);

   foreach my $field ($_FROM, $_TO, $_SUBJECT, $_CONTENT_TYPE, $_REFERENCES) {
      $_[$field]=substr($_[$field],0,128) if (length($_[$field])>128);
   }
   return(join('@@@', @_));
}
################## END UPDATEHEADERDB ####################

############### GET_MESSAGEIDS_SORTED_BY_...  #################
sub get_messageids_sorted_by_offset {
   my $headerdb=$_[0];
   my (%HDB, @attr, %offset, $key, $data);

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return keys(%offset);

   while ( ($key, $data)=each(%HDB) ) {
      next if ( $key eq 'METAINFO'
             || $key eq 'NEWMESSAGES'
             || $key eq 'INTERNALMESSAGES'
             || $key eq 'ALLMESSAGES'
             || $key eq "" );

      @attr=split( /@@@/, $data );
      $offset{$key}=$attr[$_OFFSET];
   }

   close_dbm(\%HDB, $headerdb);

   return( sort { $offset{$a}<=>$offset{$b} } keys(%offset) );
}

sub get_info_messageids_sorted {
   my ($headerdb, $sort, $cachefile, $ignore_internal)=@_;
   my (%HDB, $metainfo);
   my ($cache_metainfo, $cache_headerdb, $cache_sort, $cache_ignore_internal);
   my ($totalsize, $new)=(0,0);
   my $r_messageids;
   my $r_messagedepths;
   my @messageids=();
   my @messagedepths=();
   my $messageids_size;
   my $messagedepths_size;
   my $rev;

   if ( $sort eq 'date' ) {
      $sort='date'; $rev=0;
   } elsif ( $sort eq 'date_rev' ) {
      $sort='date'; $rev=1;
   } elsif ( $sort eq 'sender' ) {
      $sort='sender'; $rev=0;
   } elsif ( $sort eq 'sender_rev' ) {
      $sort='sender'; $rev=1;
   } elsif ( $sort eq 'recipient' ) {
      $sort='recipient'; $rev=0;
   } elsif ( $sort eq 'recipient_rev' ) {
      $sort='recipient'; $rev=1;
   } elsif ( $sort eq 'size' ) {
      $sort='size'; $rev=0;
   } elsif ( $sort eq 'size_rev' ) {
      $sort='size'; $rev=1;
   } elsif ( $sort eq 'subject' ) {
      $sort='subject'; $rev=1;
   } elsif ( $sort eq 'subject_rev' ) {
      $sort='subject'; $rev=0;
   } else {
      $sort='status'; $rev=0;
   }

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return ($totalsize, $new, \@messageids, \@messagedepths);

   $metainfo=$HDB{'METAINFO'};
   close_dbm(\%HDB, $headerdb);

   filelock($cachefile, LOCK_EX) or
      return($totalsize, $new, \@messageids, \@messagedepths);

   if ( -e $cachefile ) {
      open(CACHE, $cachefile);
      $cache_metainfo=<CACHE>; chomp($cache_metainfo);
      $cache_headerdb=<CACHE>; chomp($cache_headerdb);
      $cache_sort=<CACHE>;     chomp($cache_sort);
      $cache_ignore_internal=<CACHE>; chomp($cache_ignore_internal);
      $totalsize=<CACHE>;      chomp($totalsize);
      close(CACHE);
   }

   if ( $cache_metainfo ne $metainfo || $cache_headerdb ne $headerdb ||
        $cache_sort ne $sort || $cache_ignore_internal ne $ignore_internal ||
        $totalsize=~/[^\d]/ ) {
      ($cachefile =~ /^(.+)$/) && ($cachefile = $1);		# untaint ...
      open(CACHE, ">$cachefile");
      print CACHE $metainfo, "\n", $headerdb, "\n", $sort, "\n", $ignore_internal, "\n";
      if ( $sort eq 'date' ) {
         ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_date($headerdb, $ignore_internal);
      } elsif ( $sort eq 'sender' ) {
         ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_from($headerdb, $ignore_internal);
      } elsif ( $sort eq 'recipient' ) {
         ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_to($headerdb, $ignore_internal);
      } elsif ( $sort eq 'size' ) {
         ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_size($headerdb, $ignore_internal);
      } elsif ( $sort eq 'subject' ) {
         ($totalsize, $new, $r_messageids, $r_messagedepths)=get_info_messageids_sorted_by_subject($headerdb, $ignore_internal);
      } elsif ( $sort eq 'status' ) {
         ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_status($headerdb, $ignore_internal);
      }

      $messageids_size = @{$r_messageids};

      @messagedepths=@{$r_messagedepths} if $r_messagedepths;
      $messagedepths_size = @messagedepths;

      print CACHE join("\n", $totalsize, $new, $messageids_size, $messagedepths_size, @{$r_messageids}, @messagedepths);
      close(CACHE);
      if ($rev) {
         @messageids=reverse @{$r_messageids};
         @messagedepths=reverse @{$r_messagedepths} if $r_messagedepths;
      } else {
         @messageids=@{$r_messageids};
         @messagedepths=@{$r_messagedepths} if $r_messagedepths;
      }

   } else {
      open(CACHE, $cachefile);
      $_=<CACHE>; $_=<CACHE>; $_=<CACHE>; $_=<CACHE>;	# skip 4 lines
      $totalsize=<CACHE>; chomp($totalsize);
      $new=<CACHE>;       chomp($new);
      $messageids_size=<CACHE>; chomp($messageids_size);
      $messagedepths_size=<CACHE>; chomp($messagedepths_size);
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

   filelock($cachefile, LOCK_UN);

   return($totalsize, $new, \@messageids, \@messagedepths);
}

sub get_info_messageids_sorted_by_date {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %dateserial, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return ($totalsize, $new, \@messageids);

   while ( ($key, $data)=each(%HDB) ) {
      if ( $key eq 'METAINFO' ||
           $key eq 'ALLMESSAGES' ||
           $key eq 'INTERNALMESSAGES' ||
           $key eq "" ) {
         next;
      } elsif ( $key eq 'NEWMESSAGES' ) {
         $new=$data;
         next;
      } else {
         @attr=split( /@@@/, $data );
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));
         $totalsize+=$attr[$_SIZE];
         $dateserial{$key}=$attr[$_DATE];
      }
   }
   close_dbm(\%HDB, $headerdb);

   @messageids=sort { $dateserial{$b}<=>$dateserial{$a} } keys(%dateserial);
   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_from {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %from, %dateserial, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return ($totalsize, $new, \@messageids);

   while ( ($key, $data)=each(%HDB) ) {
      if ( $key eq 'METAINFO' ||
           $key eq 'ALLMESSAGES' ||
           $key eq 'INTERNALMESSAGES' ||
           $key eq "" ) {
         next;
      } elsif ( $key eq 'NEWMESSAGES' ) {
         $new=$data;
         next;
      } else {
         @attr=split( /@@@/, $data );
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));
         $totalsize+=$attr[$_SIZE];
         $from{$key}=lc($attr[$_FROM]);
         $dateserial{$key}=$attr[$_DATE];
      }
   }
   close_dbm(\%HDB, $headerdb);

   @messageids=sort { $dateserial{$b} <=> $dateserial{$a}; } keys(%dateserial);

   # try to group message of same 'from'
   my %groupdate=();
   my %groupmembers=();
   foreach $key (@messageids) {
      if ( !defined($groupdate{$from{$key}}) ) {
         my @members=($key);
         $groupmembers{$from{$key}}=\@members;
         $groupdate{$from{$key}}=$dateserial{$key};
      } else {
         my $r_members=$groupmembers{$from{$key}};
         push(@{$r_members}, $key);
      }
   }
   @messageids=();

   # sort group by groupdate
   my @froms=sort {$groupdate{$b} <=> $groupdate{$a}} keys(%groupdate);
   foreach my $from (@froms) {
      push(@messageids, @{$groupmembers{$from}});
   }

   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_to {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %to, %dateserial, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return ($totalsize, $new, \@messageids);

   while ( ($key, $data)=each(%HDB) ) {
      if ( $key eq 'METAINFO' ||
           $key eq 'ALLMESSAGES' ||
           $key eq 'INTERNALMESSAGES' ||
           $key eq "" ) {
         next;
      } elsif ( $key eq 'NEWMESSAGES' ) {
         $new=$data;
         next;
      } else {
         @attr=split( /@@@/, $data );
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));
         $totalsize+=$attr[$_SIZE];
         $to{$key}=lc($attr[$_TO]);
         $dateserial{$key}=$attr[$_DATE];
      }
   }
   close_dbm(\%HDB, $headerdb);

   @messageids=sort { $dateserial{$b} <=> $dateserial{$a}; } keys(%dateserial);

   # try to group message of same 'to'
   my %groupdate=();
   my %groupmembers=();
   foreach $key (@messageids) {
      if ( !defined($groupdate{$to{$key}}) ) {
         my @members=($key);
         $groupmembers{$to{$key}}=\@members;
         $groupdate{$to{$key}}=$dateserial{$key};
      } else {
         my $r_members=$groupmembers{$to{$key}};
         push(@{$r_members}, $key);
      }
   }
   @messageids=();

   # sort group by groupdate
   my @tos=sort {$groupdate{$b} <=> $groupdate{$a}} keys(%groupdate);
   foreach my $to (@tos) {
      push(@messageids, @{$groupmembers{$to}});
   }

   return($totalsize, $new, \@messageids);
}

# this routine actually sorts messages by thread,
# contributed by <james@tiger-marmalade.com"> James Dean Palmer
sub get_info_messageids_sorted_by_subject {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %subject, %dateserial, %references, $key, $data);
   my ($totalsize, $new)=(0,0);
   my (%thread_parent, @thread_pre_roots, @thread_roots, %thread_children);
   my (@message_ids, @message_depths);

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return ($totalsize, $new, \@message_ids, \@message_depths);

   while ( ($key, $data)=each(%HDB) ) {
      if ( $key eq 'METAINFO' ||
           $key eq 'ALLMESSAGES' ||
           $key eq 'INTERNALMESSAGES' ||
           $key eq "" ) {
         next;
      } elsif ( $key eq 'NEWMESSAGES' ) {
         $new=$data;
         next;
      } else {
         @attr=split( /@@@/, $data );
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));
         $totalsize+=$attr[$_SIZE];
         $dateserial{$key}=$attr[$_DATE];
	 $references{$key}=$attr[$_REFERENCES];
         $subject{$key}=$attr[$_SUBJECT];
         $subject{$key}=~s/Res?:\s*//ig;
         $subject{$key}=~s/\[\d+\]//g;
         $subject{$key}=~s/[\[\]]//g;
      }
   }
   close_dbm(\%HDB, $headerdb);

   # In the first pass we need to make sure each message has a valid
   # parent message.  We also track which messages won't have parent
   # messages (@thread_roots).
   foreach my $key (keys %references) {
      my @parents = reverse split(/ /, $references{$key}); # most nearby first
      my $parent = "ROOT.nonexist";	# this should be a string that would never be used as a messageid
      foreach my $id (@parents) {
         if ( defined($subject{$id}) ) {
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
                            $subject{$a} cmp $subject{$b} or $dateserial{$a} <=> $dateserial{$b};
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
   foreach my $id (sort {$dateserial{$b}<=>$dateserial{$a};} keys %thread_parent) {
      if ($thread_parent{$id} && $id ne "ROOT.nonexist") {
         if ($dateserial{$thread_parent{$id}} lt $dateserial{$id} ) {
            $dateserial{$thread_parent{$id}}=$dateserial{$id};
         }
         push @{$thread_children{$thread_parent{$id}}}, $id;
      }
   }

   # Finally, we recursively traverse the tree.
   @thread_roots = sort { $dateserial{$a} <=> $dateserial{$b}; } @thread_roots;
   foreach my $key (@thread_roots) {
      _recursively_thread ($key, 0,
		\@message_ids, \@message_depths, \%thread_children, \%dateserial);
   }
   return($totalsize, $new, \@message_ids, \@message_depths);
}

sub _recursively_thread {
   my ($id, $depth,
	$r_message_ids, $r_message_depths, $r_thread_children, $r_dateserial) = @_;

   push @{$r_message_ids}, $id;
   push @{$r_message_depths}, $depth;
   if (defined(${$r_thread_children}{$id})) {
      my @children = sort { ${$r_dateserial}{$a} <=> ${$r_dateserial}{$b}; } @{${$r_thread_children}{$id}};
      foreach my $thread (@children) {
         _recursively_thread ($thread, $depth+1,
	 $r_message_ids, $r_message_depths, $r_thread_children, $r_dateserial);
      }
   }
   return;
}

sub get_info_messageids_sorted_by_size {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %size, %dateserial, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return ($totalsize, $new, \@messageids);

   while ( ($key, $data)=each(%HDB) ) {
      if ( $key eq 'METAINFO' ||
           $key eq 'ALLMESSAGES' ||
           $key eq 'INTERNALMESSAGES' ||
           $key eq "" ) {
         next;
      } elsif ( $key eq 'NEWMESSAGES' ) {
         $new=$data;
         next;
      } else {
         @attr=split( /@@@/, $data );
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));
         $totalsize+=$attr[$_SIZE];
         $size{$key}=$attr[$_SIZE];
         $dateserial{$key}=$attr[$_DATE];
      }
   }
   close_dbm(\%HDB, $headerdb);

   @messageids=sort {
                    $size{$b} <=> $size{$a} or $dateserial{$b} <=> $dateserial{$a};
                    } keys(%size);
   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_status {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %status, %dateserial, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return ($totalsize, $new, \@messageids);

   while ( ($key, $data)=each(%HDB) ) {
      if ( $key eq 'METAINFO' ||
           $key eq 'ALLMESSAGES' ||
           $key eq 'INTERNALMESSAGES' ||
           $key eq "" ) {
         next;
      } elsif ( $key eq 'NEWMESSAGES' ) {
         $new=$data;
         next;
      } else {
         @attr=split( /@@@/, $data );
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));
         $totalsize+=$attr[$_SIZE];
         if ($attr[$_STATUS]=~/r/i) {
            if ($attr[$_STATUS]=~/i/i) {
               $status{$key}=1;
            } else {
               $status{$key}=0;
            }
         } else {
            if ($attr[$_STATUS]=~/i/i) {
               $status{$key}=3;
            } else {
               $status{$key}=2;
            }
         }
         $dateserial{$key}=$attr[$_DATE];
      }
   }
   close_dbm(\%HDB, $headerdb);

   @messageids=sort {
                    $status{$b} <=> $status{$a} or $dateserial{$b} <=> $dateserial{$a};
                    } keys(%status);
   return($totalsize, $new, \@messageids);
}
############### END GET_MESSAGEIDS_SORTED_BY_...  #################

####################### GET_MESSAGE_.... ###########################
sub get_message_attributes {
   my ($messageid, $headerdb)=@_;
   my (%HDB, @attr);

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return @attr;

   @attr=split(/@@@/, $HDB{$messageid} );
   close_dbm(\%HDB, $headerdb);
   return(@attr);
}

sub get_message_block {
   my ($messageid, $headerdb, $folderhandle)=@_;
   my (@attr, $buff);

   @attr=get_message_attributes($messageid, $headerdb);
   if ($#attr>=7 && $attr[$_SIZE]>=0) {
      my $oldoffset=tell($folderhandle);
      seek($folderhandle, $attr[$_OFFSET], 0);
      read($folderhandle, $buff, $attr[$_SIZE]);
      seek($folderhandle, $oldoffset, 0);
   } else {
      $buff="";
   }
   return(\$buff);
}

sub get_message_header {
   my ($messageid, $headerdb, $folderhandle)=@_;
   my (@attr, $header);

   @attr=get_message_attributes($messageid, $headerdb);
   if ($#attr>=0) {
      my $oldoffset=tell($folderhandle);
      seek($folderhandle, $attr[$_OFFSET], 0);
      $header="";
      while(<$folderhandle>) {
         $header.=$_;
         last if ($_ eq "\n");
      }
      seek($folderhandle, $oldoffset, 0);
   } else {
      $header="";
   }
   return(\$header);
}
###################### END GET_MESSAGE_.... ########################

###################### UPDATE_MESSAGE_STATUS ########################
sub update_message_status {
   my ($messageid, $status, $headerdb, $folderfile) = @_;
   my $messageoldstatus='';
   my $folderhandle=do { local *FH };
   my %HDB;
   my $ioerr=0;

   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      writelog("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      writehistory("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      return -1;
   }

   my @messageids=get_messageids_sorted_by_offset($headerdb);
   my $movement=0;
   my @attr;
   my $i;

   open_dbm(\%HDB, $headerdb, LOCK_EX) or return -1;

   for ($i=0; $i<=$#messageids; $i++) {
      if ($messageids[$i] eq $messageid) {
         @attr=split(/@@@/, $HDB{$messageid});

         $messageoldstatus=$attr[$_STATUS];
         last if ($messageoldstatus eq $status);

         my $messagestart=$attr[$_OFFSET];
         my $messagesize=$attr[$_SIZE];
         my ($header, $headerend, $headerlen, $newheaderlen);
         my $buff;

         open ($folderhandle, "+<$folderfile");
         seek ($folderhandle, $messagestart, 0);
         $header="";
         while (<$folderhandle>) {
            last if ($_ eq "\n" && $header=~/\n$/);
            $header.=$_;
         }
         if ($header !~ /^From /) { # index not consistent with folder content
            close ($folderhandle);

            writelog("db warning - msg $messageid in $folderfile index inconsistence");
            writehistory("db warning - msg $messageid in $folderfile index inconsistence");

            $HDB{'METAINFO'}="ERR";
            close_dbm(\%HDB, $headerdb);

            # forced reindex since metainfo = ERR
            return -3 if (update_headerdb($headerdb, $folderfile)<0);
            return -2;
         }
         $headerlen=length($header);
         $headerend=$messagestart+$headerlen;

         # update status, flags from rfc2076
         my $status_update = "";
         if ($status=~/[ro]/i) {
            $status_update .= "R" if ($status=~/r/i); # Read
            $status_update .= "O" if ($status=~/o/i); # Old
         } else {
            $status_update .= "N" if ($status=~/n/i); # New
            $status_update .= "U" if ($status=~/u/i); # still Undownloaded & Undeleted
         }
         $status_update .= "D" if ($status=~/d/i); # to be Deleted
         if ($status_update ne "") {
            if (!($header =~ s/^status:.*\n/Status: $status_update\n/im)) {
               $header .= "Status: $status_update\n";
            }
         } else {
            $header =~ s/^status:.*\n//im;
         }

	 # update x-status
         $status_update = "";
         $status_update .= "A" if ($status =~ m/a/i); # Answered
         $status_update .= "I" if ($status =~ m/i/i); # Important
         $status_update .= "D" if ($status =~ m/d/i); # to be Deleted
         if ($status_update ne "") {
            if (!($header =~ s/^x-status:.*\n/X-Status: $status_update\n/im)) {
               $header .= "X-Status: $status_update\n";
            }
         } else {
            $header =~ s/^x-status:.*\n//im;
         }

         $newheaderlen=length($header);
         $movement=$newheaderlen-$headerlen;

         my $foldersize=(stat($folderhandle))[7];
         if (shiftblock($folderhandle, $headerend, $foldersize-$headerend, $movement)<0) {
            writelog("data error - msg $messageids[$i] in $folderfile shiftblock failed");
            writehistory("data error - msg $messageids[$i] in $folderfile shiftblock failed");
            $ioerr++;
         }

         if (!$ioerr) {
            seek($folderhandle, $messagestart, 0);
            print $folderhandle $header or $ioerr++;
         }
         if (!$ioerr) {
            seek($folderhandle, $foldersize+$movement, 0);
            truncate($folderhandle, tell($folderhandle));
         }
         close ($folderhandle);

         if (!$ioerr) {
            # set attributes in headerdb for this status changed message
            if ($messageoldstatus!~/r/i && $status=~/r/i) {
               $HDB{'NEWMESSAGES'}--;
               $HDB{'NEWMESSAGES'}=0 if ($HDB{'NEWMESSAGES'}<0); # should not happen
            } elsif ($messageoldstatus=~/r/i && $status!~/r/i) {
               $HDB{'NEWMESSAGES'}++;
            }
            $attr[$_SIZE]=$messagesize+$movement;
            $attr[$_STATUS]=$status;
            $HDB{$messageid}=join('@@@', @attr);
         }

         last;
      }
   }
   $i++;

   # if size of this message is changed
   if ($movement!=0 && !$ioerr) {
      #  change offset attr for messages after the above one
      for (;$i<=$#messageids; $i++) {
         @attr=split(/@@@/, $HDB{$messageids[$i]});
         $attr[$_OFFSET]+=$movement;
         $HDB{$messageids[$i]}=join('@@@', @attr);
      }
   }

   # update folder metainfo
   $HDB{'METAINFO'}=metainfo($folderfile) if (!$ioerr);

   close_dbm(\%HDB, $headerdb);

   if (!$ioerr) {
      return 0;
   } else {
      return -3;
   }
}
#################### END UPDATE_MESSAGE_STATUS ######################

###################### OP_MESSAGE_WITH_IDS #########################
# operate messages with @messageids from src folderfile to dst folderfile
# available $op: "move", "copy", "delete"
sub operate_message_with_ids {
   my ($op, $r_messageids, $srcfile, $srcdb, $dstfile, $dstdb)=@_;
   my $folderhandle=do { local *FH };
   my (%HDB, %HDB2);
   my $messageids = join("\n", @{$r_messageids});
   my $ioerr=0;

   # $lang_err{'inv_msg_op'}
   return -1 if ($op ne "move" && $op ne "copy" && $op ne "delete");
   return 0 if ($srcfile eq $dstfile || $#{$r_messageids} < 0);

   if (update_headerdb($srcdb, $srcfile)<0) {
      writelog("db error - Couldn't update index db $srcdb$config{'dbm_ext'}");
      writehistory("db error - Couldn't update index db $srcdb$config{'dbm_ext'}");
      return -2;
   }

   open ($folderhandle, "+<$srcfile") or
      return -3;	# $lang_err{'couldnt_open'} $srcfile!

   if ($op eq "move" || $op eq "copy") {
      open (DEST, ">>$dstfile") or
         return -5;	# $lang_err{'couldnt_open'} $destination!
      seek(DEST, 0, 2);	# seek end explicitly to cover tell() bug in perl 5.8

      if (update_headerdb("$dstdb", $dstfile)<0) {
         close ($folderhandle);
         close (DEST);
         writelog("db error - Couldn't update index db $dstdb$config{'dbm_ext'}");
         writehistory("db error - Couldn't update index db $dstdb$config{'dbm_ext'}");
         return -4;
      }

      if ( !open_dbm(\%HDB2,$dstdb, LOCK_EX) ) {
         close ($folderhandle);
         close (DEST);
         writelog("db error - Couldn't open index db $dstdb$config{'dbm_ext'}");
         writehistory("db error - Couldn't open index db $dstdb$config{'dbm_ext'}");
         return -1;
      }
   }

   my @allmessageids=get_messageids_sorted_by_offset($srcdb);

   if ( !open_dbm(\%HDB, $srcdb, LOCK_EX) ) {
      if ($op eq "move" || $op eq "copy") {
         close (DEST);
         close_dbm(\%HDB2,$dstdb);
      }
      return -1;
   }

   my ($blockstart, $blockend, $writepointer);
   my ($messagestart, $messagesize, $messagevalid, @attr, $buff);
   my $counted=0;

   $blockstart=$blockend=$writepointer=0;

   for (my $i=0; $i<=$#allmessageids; $i++) {
      @attr=split(/@@@/, $HDB{$allmessageids[$i]});
      $messagestart=$attr[$_OFFSET];
      $messagesize=$attr[$_SIZE];
      $messagevalid=1;

      seek($folderhandle, $attr[$_OFFSET], 0);
      if ($attr[$_OFFSET] == 0) {
         $messagevalid=1;
      } elsif ($attr[$_SIZE]<=5) {
         $messagevalid=0;
      } else {
         read($folderhandle, $buff, 5);
         $messagevalid=0 if ($buff!~/^From /);
      }

      if ($messageids =~ /^\Q$allmessageids[$i]\E$/m && $messagevalid) { # msg to be operated
         $counted++;

         if ($op eq 'move' || $op eq 'delete') {
            if (shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart)<0) {
               writelog("data error - msg $allmessageids[$i] in $srcfile shiftblock failed");
               writehistory("data error - msg $allmessageids[$i] in $srcfile shiftblock failed");
               $ioerr++;
            } else {
               $writepointer=$writepointer+($blockend-$blockstart);
               $blockstart=$blockend=$messagestart+$messagesize;
            }
         } else {
            $blockend=$messagestart+$messagesize;
         }

         # append msg to dst folder only if
         # op=move/copy and msg doesn't exist in dstfile
         if (($op eq "move" || $op eq "copy") &&
             !defined($HDB2{$allmessageids[$i]}) && !$ioerr ) {

            seek($folderhandle, $attr[$_OFFSET], 0);
            $attr[$_OFFSET]=tell(DEST);

            # copy message from $folderhandle to DEST
            my $left=$attr[$_SIZE];
            while ($left>0) {
               if ($left>=32768) {
                   read($folderhandle, $buff, 32768);
                   print DEST $buff or $ioerr++;
                   $left=$left-32768;
               } else {
                   read($folderhandle, $buff, $left);
                   print DEST $buff or $ioerr++;
                   $left=0;
               }
            }

            if (!$ioerr) {
               $HDB2{'NEWMESSAGES'}++ if ($attr[$_STATUS]!~/r/i);
               $HDB2{'INTERNALMESSAGES'}++ if (is_internal_subject($attr[$_SUBJECT]));
               $HDB2{'ALLMESSAGES'}++;
               $HDB2{$allmessageids[$i]}=join('@@@', @attr);
            }
         }
         if (($op eq 'move' || $op eq 'delete') && !$ioerr) {
            $HDB{'NEWMESSAGES'}-- if ($attr[$_STATUS]!~/r/i);
            $HDB{'NEWMESSAGES'}=0 if ($HDB{'NEWMESSAGES'}<0); # should not happen
            $HDB{'INTERNALMESSAGES'}-- if (is_internal_subject($attr[$_SUBJECT]));
            $HDB{'ALLMESSAGES'}--;
            delete $HDB{$allmessageids[$i]};
         }

      } else {						# msg to be kept in same folder
         $blockend=$messagestart+$messagesize;

         if ($op eq 'move' || $op eq 'delete') {
            my $movement=$writepointer-$blockstart;
            if ($movement<0) {
               $attr[$_OFFSET]+=$movement;
               $HDB{$allmessageids[$i]}=join('@@@', @attr);
            }
         }
      }

      last if ($ioerr);
   }

   if ( ($op eq 'move' || $op eq 'delete') && $counted>0 && !$ioerr) {
      if (shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart)<0) {
         writelog("data error - msgs in $srcfile shiftblock failed");
         writehistory("data error - msgs in $srcfile shiftblock failed");
         $ioerr++;
      } else {
         seek($folderhandle, $writepointer+($blockend-$blockstart), 0);
         truncate($folderhandle, tell($folderhandle));
      }
   }

   if ($op eq "move" || $op eq "copy") {
      $HDB2{'METAINFO'}=metainfo($dstfile) if (!$ioerr);
      close (DEST);
      close_dbm(\%HDB2,$dstdb);
   }

   close ($folderhandle);
   $HDB{'METAINFO'}=metainfo($srcfile) if (!$ioerr);
   close_dbm(\%HDB, $srcdb);

   if (!$ioerr) {
      return($counted);
   } else {
      return -8;
   }
}
#################### END OP_MESSAGE_WITH_IDS #######################

#################### DELETE_MESSAGE_BY_AGE #######################
sub delete_message_by_age {
   my ($dayage, $headerdb, $folderfile)=@_;
   return 0 if ( ! -f $folderfile );

   my $folderhandle=do { local *FH };
   my (%HDB, @allmessageids, @agedids);

   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      writelog("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      writehistory("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      return 0;
   }
   @allmessageids=get_messageids_sorted_by_offset($headerdb);

   open_dbm(\%HDB, $headerdb, LOCK_EX) or return -1;

   my $agestarttime=time()-$dayage*86400;
   foreach (@allmessageids) {
      my @attr = split(/@@@/, $HDB{$_});
      push(@agedids, $_) if (dateserial2gmtime($attr[$_DATE])<=$agestarttime); # too old
   }
   close_dbm(\%HDB, $headerdb);

   return 0 if ($#agedids==-1);
   return(operate_message_with_ids('delete', \@agedids, $folderfile, $headerdb));
}
################### END DELETE_MESSAGE_BY_AGE #####################

####################### MOVE_OLDMSG_FROM_FOLDER #################
sub move_oldmsg_from_folder {
   my ($srcfile, $srcdb, $dstfile, $dstdb)=@_;
   my (%HDB, $key, $data, @attr);
   my @messageids=();

   open_dbm(\%HDB, $srcdb, LOCK_SH) or return -1;

   # if oldmsg == internal msg or 0, then do not read ids
   if ( $HDB{'ALLMESSAGES'}-$HDB{'NEWMESSAGES'} > $HDB{'INTERNALMESSAGES'} ) {
      while ( ($key, $data)=each(%HDB) ) {
         next if ( $key eq 'METAINFO'
                || $key eq 'NEWMESSAGES'
                || $key eq 'INTERNALMESSAGES'
                || $key eq 'ALLMESSAGES'
                || $key eq "" );
         @attr=split( /@@@/, $data );
         if ( $attr[$_STATUS] =~ /r/i &&
              !is_internal_subject($attr[$_SUBJECT]) ) {
            push(@messageids, $key);
         }
      }
   }

   close_dbm(\%HDB, $srcdb);

   # no old msg found
   return 0 if ($#messageids==-1);

   return(operate_message_with_ids('move', \@messageids, $srcfile, $srcdb,
					  		   $dstfile, $dstdb));
}
##################### END MOVE_OLDMSG_FROM_FOLDER #################

##################### REBUILD_MESSAGE_WITH_PARTIALID #################
# rebuild orig msg with partial msgs in the same folder
sub rebuild_message_with_partialid {
   my ($folderfile, $headerdb, $partialid)=@_;
   my (%HDB, @messageids);
   my ($partialtotal, @partialmsgids, @offset, @size);

   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      writelog("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      writehistory("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      return -1;
   }

   # find all partial msgids
   open_dbm(\%HDB, $headerdb, LOCK_SH) or return -2;

   @messageids=keys %HDB;
   foreach my $id (@messageids) {
      next if ( $id eq 'METAINFO'
             || $id eq 'NEWMESSAGES'
             || $id eq 'INTERNALMESSAGES'
             || $id eq 'ALLMESSAGES'
             || $id eq "" );

      my @attr=split( /@@@/, $HDB{$id} );
      next if ($attr[$_CONTENT_TYPE] !~ /^message\/partial/i );

      $attr[$_CONTENT_TYPE] =~ /;\s*id="(.+?)";?/i;
      next if ($partialid ne $1);

      if ($attr[$_CONTENT_TYPE] =~ /;\s*number="?(.+?)"?;?/i) {
         my $n=$1;
         $partialmsgids[$n]=$id;
         $offset[$n]=$attr[$_OFFSET];
         $size[$n]=$attr[$_SIZE];
         $partialtotal=$1 if ($attr[$_CONTENT_TYPE] =~ /;\s*total="?(.+?)"?;?/i);
      }
   }
   close_dbm(\%HDB, $headerdb);

   # check completeness
   if ($partialtotal<1) {	# last part not found
      return -3;
   }
   for (my $i=1; $i<=$partialtotal; $i++) {
      if ($partialmsgids[$i] eq "") {	# some part missing
         return -4;
      }
   }

   my $tmpfile="/tmp/rebuild_tmp_$$";
   my $tmpdb="/tmp/.rebuild_tmp_$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);
   ($tmpdb =~ /^(.+)$/) && ($tmpdb = $1);

   filelock("$tmpfile", LOCK_EX) or return -5;
   open (TMP,  ">$tmpfile");
   open (FOLDER, "$folderfile");

   seek(FOLDER, $offset[1], 0);
   my $line = <FOLDER>;
   my $writtensize = length($line);
   print TMP $line;	# copy delimiter line from 1st partial message

   for (my $i=1; $i<=$partialtotal; $i++) {
      my $currsize=0;
      seek(FOLDER, $offset[$i], 0);

      # skip header of the partial message
      while (defined($line = <FOLDER>)) {
         $currsize += length($line);
         last if ( $line =~ /^\r*$/ );
      }

      # read body of the partial message and copy to tmpfile
      while (defined($line = <FOLDER>)) {
         $currsize += length($line);
         $writtensize += length($line);
         print TMP $line;
         last if ( $currsize>=$size[$i] );
      }
   }

   close(TMP);
   close(FOLDER);
   filelock("$tmpfile", LOCK_EX) or return -6;

   # index tmpfile, get the msgid
   if (update_headerdb($tmpdb, $tmpfile)<0) {
      filelock($tmpfile, LOCK_UN);
      writelog("db error - Couldn't update index db $tmpdb$config{'dbm_ext'}");
      writehistory("db error - Couldn't update index db $tmpdb$config{'dbm_ext'}");
      return -7;
   }

   # check the rebuild integrity
   my @rebuildmsgids=get_messageids_sorted_by_offset($tmpdb);
   if ($#rebuildmsgids!=0) {
      unlink("$tmpdb$config{'dbm_ext'}", $tmpfile);
      return -8;
   }
   my $rebuildsize=(get_message_attributes($rebuildmsgids[0], $tmpdb))[$_SIZE];
   if ($writtensize!=$rebuildsize) {
      unlink("$tmpdb$config{'dbm_ext'}", $tmpfile);
      return -9;
   }

   operate_message_with_ids("move", \@rebuildmsgids, $tmpfile, $tmpdb, $folderfile, $headerdb);

   unlink("$tmpdb$config{'dbm_ext'}", $tmpfile);

   return(0, $rebuildmsgids[0], @partialmsgids);
}
##################### END REBUILD_MESSAGE_WITH_PARTIALID #################

####################### PARSE_.... related ###########################
# Handle "message/rfc822,multipart,uuencode inside message/rfc822" encapsulatio
#
# Note: These parse_... routine are designed for CGI program !
#       if (nodeid eq "") {
#          # html display / content search mode
#          only attachment contenttype of text/... or n/a will be returned
#       } elsif (node eq "all") {
#          # used in message forwarding
#          all attachments are returned
#       } elsif (node eq specific-id ) {
#          # html requesting an attachment with specific nodeid
#          only return attachment with the id
#       }
#
sub parse_rfc822block {
   my ($r_block, $nodeid, $searchid)=@_;
   my @attachments=();
   my ($headerlen, $header, $body, $contenttype, $encoding, $description);

   $nodeid=0 unless defined $nodeid;
   $headerlen=index(${$r_block},  "\n\n");
   $header=substr(${$r_block}, 0, $headerlen);
   ($contenttype, $encoding, $description)=get_contenttype_encoding_from_header($header);

   if ($contenttype =~ /^multipart/i) {
      my $boundary = $contenttype;
      my $subtype = $contenttype;
      my $boundarylen;
      my ($bodystart, $boundarystart, $nextboundarystart, $attblockstart);

      $boundary =~ s/.*?boundary\s?=\s?"([^"]+)".*$/$1/i ||
      $boundary =~ s/.*?boundary\s?=\s?([^\s]+)\s?.*$/$1/i;

      $boundary="--$boundary";
      $boundarylen=length($boundary);

      $subtype =~ s/^multipart\/(.*?)[;\s].*$/$1/i;

      $bodystart=$headerlen+2;

      $boundarystart=index(${$r_block}, $boundary, $bodystart);
      if ($boundarystart >= $bodystart) {
          $body=substr(${$r_block}, $bodystart, $boundarystart-$bodystart);
      } else {
          $body=substr(${$r_block}, $bodystart);
          return($header, $body, \@attachments);
      }

      my $i=0;
      $attblockstart=$boundarystart+$boundarylen;
      while ( substr(${$r_block}, $attblockstart, 2) ne "--") {
         # skip \n after boundary
         while ( substr(${$r_block}, $attblockstart, 1) =~ /[\n\r]/ ) {
            $attblockstart++;
         }

         $nextboundarystart=index(${$r_block}, "$boundary\n", $attblockstart);
         if ($nextboundarystart <= $attblockstart) {
            $nextboundarystart=index(${$r_block}, "$boundary--", $attblockstart);
         }
         if ($nextboundarystart > $attblockstart) {
            # normal attblock handling
            if ( $searchid eq "" || $searchid eq "all") {
               my $r_attachments2=parse_attblock($r_block, $attblockstart, $nextboundarystart-$attblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            } elsif ($searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/) {
               my $r_attachments2=parse_attblock($r_block, $attblockstart, $nextboundarystart-$attblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
               last;	# attblock after this is not the one to look for...
            }
            $boundarystart=$nextboundarystart;
            $attblockstart=$boundarystart+$boundarylen;
         } else {
            # abnormal attblock, last one?
            if ( $searchid eq "" || $searchid eq "all" ||
                 $searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/ ) {
               my $left=length(${$r_block})-$attblockstart;
               if ($left>0) {
                  my $r_attachments2=parse_attblock($r_block, $attblockstart, $left ,$subtype, $boundary, "$nodeid-$i", $searchid);
                  push(@attachments, @{$r_attachments2});
               }
            }
            last;
         }

         $i++;
      }
      return($header, $body, \@attachments);

   } elsif ($contenttype =~ /^message\/partial/i ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         my $partialbody=substr(${$r_block}, $headerlen+2);
         my ($partialid, $partialnumber, $partialtotal);
         $partialid=$1 if ($contenttype =~ /;\s*id="(.+?)";?/i);
         $partialnumber=$1 if ($contenttype =~ /;\s*number="?(.+?)"?;?/i);
         $partialtotal=$1 if ($contenttype =~ /;\s*total="?(.+?)"?;?/i);
         my $filename;
         if ($partialtotal) {
            $filename="Partial-$partialnumber.$partialtotal.msg";
         } else {
            $filename="Partial-$partialnumber.msg";
         }
         push(@attachments, make_attachment("","", "Content-Type: $contenttype",\$partialbody, length($partialbody),
   	    $encoding,"message/partial", "attachment; filename=$filename",$partialid,$partialnumber,$description, $nodeid) );
      }
      $body=''; # zero the body since it becomes to message/partial
      return($header, $body, \@attachments);

   } elsif ($contenttype =~ /^message\/external\-body/i ) {
      $body=substr(${$r_block}, $headerlen+2);
      my @extbodyattr=split(/;\s*/, $contenttype);
      shift (@extbodyattr);
      $body="This is an external body reference.\n\n".
            join(";\n", @extbodyattr)."\n\n".
            $body;
      return($header, $body, \@attachments);

   } elsif ($contenttype =~ /^message/i ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         $body=substr(${$r_block}, $headerlen+2);
         my ($header2, $body2, $r_attachments2)=parse_rfc822block(\$body, "$nodeid-0", $searchid);
         if ( $searchid eq "" || $searchid eq "all" || $searchid eq $nodeid ) {
            $header2 = decode_mimewords($header2);
            my $temphtml="$header2\n\n$body2";
            push(@attachments, make_attachment("","", "",\$temphtml, length($temphtml),
   		$encoding,$contenttype, "inline; filename=Unknown.msg","","",$description, $nodeid) );
         }
         push (@attachments, @{$r_attachments2});
      }
      $body=''; # zero the body since it becomes to header2, body2 and r_attachment2
      return($header, $body, \@attachments);

   } elsif ( $contenttype =~ /^text/i || $contenttype eq 'N/A' ) {
      $body=substr(${$r_block}, $headerlen+2);
      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid-0/ ) {
         # Handle uuencode blocks inside a text/plain mail
         if ( $contenttype =~ /^text\/plain/i || $contenttype eq 'N/A' ) {
            if ( $body =~ /(?:\nbegin|^begin) [0-7][0-7][0-7][0-7]? [^\n\r]+\n.+?\nend\n/ims ) {
               my $r_attachments2;
               ($body, $r_attachments2)=parse_uuencode_body($body, "$nodeid-0", $searchid);
               push(@attachments, @{$r_attachments2});
            }
         }
      }
      return($header, $body, \@attachments);

   } else {
      if ( $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         $body=substr(${$r_block}, $headerlen+2);
         if ($body !~ /^\s*$/ ) { # if attach contains only \s, discard it
            push(@attachments, make_attachment("","", "",\$body,length($body),
					$encoding,$contenttype, "","","",$description, $nodeid) );
         }
      } else {
         # null searchid means CGI is in returning html code or in context searching
         # thus content of an non-text based attachment is no need to be returned
         my $bodylength=length(${$r_block})-($headerlen+2);
         my $fakeddata="snipped...";
         push(@attachments, make_attachment("","", "",\$fakeddata,$bodylength,
					$encoding,$contenttype, "","","",$description, $nodeid) );
      }
      return($header, " ", \@attachments);
   }

}

# Handle "message/rfc822,multipart,uuencode inside multipart" encapsulation.
sub parse_attblock {
   my ($r_buff, $attblockstart, $attblocklen, $subtype, $boundary, $nodeid, $searchid)=@_;
   my @attachments=();
   my ($attheader, $attcontent, $attencoding, $attcontenttype,
	$attdisposition, $attid, $attlocation, $attdescription);
   my $attheaderlen;
   if (/^\-\-\n/) {	# return empty array
      return(\@attachments)
   }

   $attheaderlen=index(${$r_buff},  "\n\n", $attblockstart) - $attblockstart;
   $attheader=substr(${$r_buff}, $attblockstart, $attheaderlen);
   $attencoding=$attcontenttype='N/A';

   my $lastline='NONE';
   foreach (split(/\n/, $attheader)) {
      if (/^\s/) {
         s/^\s+//; # fields in attheader use ';' as delimiter, no space is ok
         if    ($lastline eq 'TYPE')     { $attcontenttype .= $_ }
         elsif ($lastline eq 'DISPOSITION') { $attdisposition .= $_ }
         elsif ($lastline eq 'LOCATION') { $attlocation .= $_ }
         elsif ($lastline eq 'DESC') { $attdescription .= $_ }
      } elsif (/^content-type:\s+(.+)$/ig) {
         $attcontenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.+)$/ig) {
         $attencoding = $1;
         $lastline = 'NONE';
      } elsif (/^content-disposition:\s+(.+)$/ig) {
         $attdisposition = $1;
         $lastline = 'DISPOSITION';
      } elsif (/^content-id:\s+(.+)$/ig) {
         $attid = $1;
         $attid =~ s/^\<(.+)\>$/$1/;
         $lastline = 'NONE';
      } elsif (/^content-location:\s+(.+)$/ig) {
         $attlocation = $1;
         $lastline = 'LOCATION';
      } elsif (/^content-description:\s+(.+)$/ig) {
         $attdescription = $1;
         $lastline = 'DESC';
      } else {
         $lastline = 'NONE';
      }
   }

   if ($attcontenttype =~ /^multipart/i) {
      my $boundary = $attcontenttype;
      my $subtype = $attcontenttype;
      my $boundarylen;

      my ($boundarystart, $nextboundarystart, $subattblockstart);
      my $subattblock="";

      $boundary =~ s/.*?boundary\s?=\s?"([^"]+)".*$/$1/i ||
      $boundary =~ s/.*?boundary\s?=\s?([^\s]+)\s?.*$/$1/i;

      $boundary =~ s/.*?boundary\s?=\s?"?([^\s"]+)[\s"]?.*$/$1/i;
      $boundary="--$boundary";
      $boundarylen=length($boundary);

      $subtype =~ s/^multipart\/(.*?)[;\s].*$/$1/i;

      $boundarystart=index(${$r_buff}, $boundary, $attblockstart);
      if ($boundarystart < $attblockstart) {
	 # boundary not found in this multipart block
         # we handle this attblock as text/plain
         $attcontenttype=~s!^multipart/\w+!text/plain!;
         if ( ($searchid eq "all") || ($searchid eq $nodeid) ||
              ($searchid eq "" && $attcontenttype=~/^text/i) ) {
            my $attcontentlength=$attblocklen-($attheaderlen+2);
            $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+2, $attcontentlength);
            if ($attcontent !~ /^\s*$/ ) { # if attach contains only \s, discard it
               push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
			$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation,$attdescription, $nodeid) );
            }
         }
         return(\@attachments);	# return this non-boundaried multipart as text
      }

      my $i=0;
      $subattblockstart=$boundarystart+$boundarylen;
      while ( substr(${$r_buff}, $subattblockstart, 2) ne "--") {
         # skip \n after boundary
         while ( substr(${$r_buff}, $subattblockstart, 1) =~ /[\n\r]/ ) {
            $subattblockstart++;
         }

         $nextboundarystart=index(${$r_buff}, "$boundary\n", $subattblockstart);
         if ($nextboundarystart <= $subattblockstart) {
            $nextboundarystart=index(${$r_buff}, "$boundary--", $subattblockstart);
         }

         if ($nextboundarystart > $subattblockstart) {
            # normal attblock
            if ( $searchid eq "" || $searchid eq "all" ) {
               my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $nextboundarystart-$subattblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            } elsif ( $searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/ ) {
               my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $nextboundarystart-$subattblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
               last;	# attblock after this is not the one to look for...
            }
            $boundarystart=$nextboundarystart;
            $subattblockstart=$boundarystart+$boundarylen;
         } else {
            # abnormal attblock, last one?
            if ( $searchid eq "" || $searchid eq "all" ||
                 $searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/ ) {
               my $left=$attblocklen-$subattblockstart;
               if ($left>0) {
                  my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $left ,$subtype, $boundary, "$nodeid-$i", $searchid);
                  push(@attachments, @{$r_attachments2});
               }
            }
            last;
         }

         $i++;
      }

   } elsif ($attcontenttype =~ /^message\/external\-body/i ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         my $attcontentlength=$attblocklen-($attheaderlen+2);
         $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+2, $attcontentlength);

         my @extbodyattr=split(/;\s*/, $attcontenttype);
         shift (@extbodyattr);
         $attcontent="This is an external body reference.\n\n".
                     join(";\n", @extbodyattr)."\n\n".
                     $attcontent;

         push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
		$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation,$attdescription, $nodeid) );
      }

   } elsif ($attcontenttype =~ /^message/i ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+2, $attblocklen-($attheaderlen+2));
         if ( $attencoding =~ /^quoted-printable/i) {
            $attcontent = decode_qp($attcontent);
         } elsif ($attencoding =~ /^base64/i) {
            $attcontent = decode_base64($attcontent);
         } elsif ($attencoding =~ /^x-uuencode/i) {
            $attcontent = uudecode($attcontent);
         }
         my ($header2, $body2, $r_attachments2)=parse_rfc822block(\$attcontent, "$nodeid-0", $searchid);
         if ( $searchid eq "" || $searchid eq "all" || $searchid eq $nodeid ) {
            $header2 = decode_mimewords($header2);
            my $temphtml="$header2\n\n$body2";
            push(@attachments, make_attachment($subtype,"", $attheader,\$temphtml, length($temphtml),
		$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation,$attdescription, $nodeid) );
         }
         push (@attachments, @{$r_attachments2});
      }

   } elsif ($attcontenttype =~ /^text/i || $attcontenttype eq "N/A" ) {
      $attcontenttype="text/plain" if ($attcontenttype eq "N/A");
      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         my $attcontentlength=$attblocklen-($attheaderlen+2);
         $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+2, $attcontentlength);
         if ($attcontent !~ /^\s*$/ ) { # if attach contains only \s, discard it
            push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
		$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation,$attdescription, $nodeid) );
         }
      }

   } else {
      if ( $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         my $attcontentlength=$attblocklen-($attheaderlen+2);
         $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+2, $attcontentlength);
         if ($attcontent !~ /^\s*$/ ) { # if attach contains only \s, discard it
            push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
		$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation,$attdescription, $nodeid) );
         }
      } else {
         # null searchid means CGI is in returning html code or in context searching
         # thus content of an non-text based attachment is no need to be returned
         my $attcontentlength=$attblocklen-($attheaderlen+2);
         my $fakeddata="snipped...";
         push(@attachments, make_attachment($subtype,$boundary, $attheader,\$fakeddata,$attcontentlength,
		$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation,$attdescription, $nodeid) );
      }

   }
   return(\@attachments);
}

# convert uuencode block into base64 encoded atachment
sub parse_uuencode_body {
   my ($body, $nodeid, $searchid)=@_;
   my @attachments=();
   my $i;

   # Handle uuencode blocks inside a text/plain mail
   $i=0;
   while ( $body =~ m/(\nbegin|^begin) ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n/igms ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid eq "$nodeid-$i" ) {
         my ($uumode, $uufilename, $uubody) = ($2, $3, $4);
         my $uutype;

         $uufilename=~/\.([\w\d]+)$/;
         $uutype=ext2contenttype($1);

         # convert and inline uuencode block into an base64 encoded attachment
         my $uuheader=qq|Content-Type: $uutype;\n|.
                      qq|\tname="$uufilename"\n|.
                      qq|Content-Transfer-Encoding: base64\n|.
                      qq|Content-Disposition: attachment;\n|.
                      qq|\tfilename="$uufilename"|;
         $uubody=encode_base64(uudecode($uubody));

         push( @attachments, make_attachment("","", $uuheader,\$uubody, length($uubody),
		"base64",$uutype, "attachment; filename=$uufilename","","","uuencoded attachment", "$nodeid-$i") );
      }
      $i++;
   }

   $body =~ s/(?:\nbegin|^begin) [0-7][0-7][0-7][0-7]? [^\n\r]+\n.+?\nend\n//igms;
   return ($body, \@attachments);
}

sub get_contenttype_encoding_from_header {
   my $header=$_[0];
   my ($contenttype, $encoding, $description) = ('N/A', 'N/A', '');

   my $lastline = 'NONE';
   foreach (split(/\n/, $header)) {
      if (/^\s/) {
         s/^\s+/ /;
         if ($lastline eq 'TYPE') { $contenttype .= $_ }
         elsif ($lastline eq 'ENCODING') { $encoding .= $_ }
         elsif ($lastline eq 'DESC') { $description .= $_ }
      } elsif (/^content-type:\s+(.+)$/ig) {
         $contenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.+)$/ig) {
         $encoding = $1;
         $lastline = 'ENCODING';
      } elsif (/^content-description:\s+(.+)$/ig) {
         $description = $1;
         $lastline = 'DESC';
      } else {
         $lastline = 'NONE';
      }
   }
   return($contenttype, $encoding, $description);
}

# subtype and boundary are inherit from parent attblocks,
# they are used to distingush if two attachments are winthin same group
# note: the $r_attcontent is a reference to the contents of an attachment,
#       this routine will save this reference to attachment hash directly.
#       It means the caller must ensures the variable referenced by
#       $r_attcontent is kept untouched!
sub make_attachment {
   my ($subtype,$boundary, $attheader,$r_attcontent,$attcontentlength,
	$attencoding,$attcontenttype,
        $attdisposition,$attid,$attlocation,$attdescription, $nodeid)=@_;

   my ($attcharset, $attfilename, $attfilenamecharset);
   $attcharset=$1 if ($attcontenttype=~/charset="?([^\s"';]*)"?\s?/i);
   ($attfilename, $attfilenamecharset)=get_filename_charset($attcontenttype, $attdisposition);

   # guess a better contenttype
   # $attcontenttype =~ s/^(.+);.*/$1/g;
   if ( $attcontenttype =~ m!(\Qapplication/octet-stream\E)!i ||
        $attcontenttype =~ m!(\Qvideo/mpg\E)!i ) {
      my $oldtype=$1;
      $attfilename=~ /\.([\w\d]*)$/;
      my $newtype=ext2contenttype($1);
      $attcontenttype=~ s!$oldtype!$newtype!i;
   }
   # remove file=... from disipotion
   $attdisposition =~ s/^(.+);.*/$1/g;

   return({	# return reference of hash
	subtype		=> $subtype,	# from parent block
	boundary	=> $boundary,	# from parent block
	header		=> $attheader,	# attheader is not decoded yet
	r_content 	=> $r_attcontent,
	contentlength	=> $attcontentlength,
	contenttype 	=> $attcontenttype || 'text/plain',
	charset		=> $attcharset || '',
	encoding 	=> $attencoding,
	disposition 	=> $attdisposition,
	filename 	=> $attfilename,
	filenamecharset => $attfilenamecharset||$attcharset,
	id 		=> $attid,
	location 	=> $attlocation,
	nodeid		=> $nodeid,
	description 	=> $attdescription,
	referencecount	=> 0
   });
}

sub get_filename_charset {
   my ($contenttype, $disposition)=@_;
   my ($filename, $filenamecharset);

   $filename = $contenttype;
   if ($filename =~ s/^.+name\s?\*?[:=]\s?"?[\w\d\-]+''([^"]+)"?.*$/$1/ig) {
      $filename = unescapeURL($filename);
   } elsif ($filename =~ s/^.+name\s?\*?[:=]\s?"?([^"]+)"?.*$/$1/ig) {
      $filenamecharset = $1 if ($filename =~ m{=\?([^?]*)\?[bq]\?[^?]+\?=}xi);
      $filename = decode_mimewords($filename);
   } else {
      $filename = $disposition || '';
      if ($filename =~ s/^.+filename\s?\*?=\s?"?[\w\d\-]+''([^"]+)"?.*$/$1/ig) {
         $filename = unescapeURL($filename);
      } elsif ($filename =~ s/^.+filename\s?\*?=\s?"?([^"]+)"?.*$/$1/ig) {
         $filenamecharset = $1 if ($filename =~ m{=\?([^?]*)\?[bq]\?[^?]+\?=}xi);
         $filename = decode_mimewords($filename);
      } else {
         $filename = "Unknown.".contenttype2ext($contenttype);
      }
   }
   # the filename of achments should not contain path delimiter,
   # eg:/,\,: We replace it with !
   $filename = zh_dospath2fname($filename, '!');	# dos path
   $filename =~ s|/|!|g;	# unix path
   $filename =~ s|:|!|g;	# mac path and dos drive

   return($filename, $filenamecharset);
}

# sub contenttype2ext & ext2contenttype is moved to ow-shared.pl
# since webdisk uses ext2contenttype in downloadfile

####################### END PARSE_.... related ###########################

#################### SEARCH_MESSAGES_FOR_KEYWORD ###########################
# searchtype: subject, from, to, date, attfilename, header, textcontent, all
# prefs_charset: the charset of the keyword
sub search_info_messages_for_keyword {
   my ($keyword, $prefs_charset, $searchtype, $headerdb, $folderhandle, $cachefile, $ignore_internal, $regexmatch)=@_;
   my ($metainfo, $cache_metainfo, $cache_headerdb, $cache_keyword, $cache_searchtype, $cache_ignore_internal);
   my (%HDB, @messageids, $messageid);
   my ($totalsize, $new)=(0,0);
   my %found=();

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return($totalsize, $new, \%found);

   $metainfo=$HDB{'METAINFO'};
   close_dbm(\%HDB, $headerdb);

   filelock($cachefile, LOCK_EX) or return($totalsize, $new, \%found);

   if ( -e $cachefile ) {
      open(CACHE, $cachefile);
      $cache_metainfo=<CACHE>; chomp($cache_metainfo);
      $cache_headerdb=<CACHE>; chomp($cache_headerdb);
      $cache_keyword=<CACHE>; chomp($cache_keyword);
      $cache_searchtype=<CACHE>; chomp($cache_searchtype);
      $cache_ignore_internal=<CACHE>; chomp($cache_ignore_internal);
      close(CACHE);
   }

   if ( $cache_metainfo ne $metainfo || $cache_headerdb ne $headerdb ||
        $cache_keyword ne $keyword || $cache_searchtype ne $searchtype ||
        $cache_ignore_internal ne $ignore_internal ) {
      ($cachefile =~ /^(.+)$/) && ($cachefile = $1);		# untaint ...
      @messageids=get_messageids_sorted_by_offset($headerdb, $folderhandle);

      open_dbm(\%HDB, $headerdb, LOCK_SH) or return($totalsize, $new, \%found);

      $regexmatch = $regexmatch && is_regex($keyword);	# check if keyword a valid regex

      foreach $messageid (@messageids) {
         my (@attr, $block, $header, $body, $r_attachments) ;
         @attr=split(/@@@/, $HDB{$messageid});
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));

         my $is_conv=is_convertable($attr[$_CHARSET], $prefs_charset);
         if ($is_conv) {
            ($attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT])=
               iconv($attr[$_CHARSET], $prefs_charset, $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]);
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
                (($regexmatch && $attr[$_DATE]=~/$keyword/i) ||
                 $attr[$_DATE]=~/\Q$keyword\E/i) )
            ) {
            $new++ if ($attr[$_STATUS]!~/r/i);
            $totalsize+=$attr[$_SIZE];
            $found{$messageid}=1;
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
            $header = decode_mimewords($header);
            $header=~s/\n / /g;	# handle folding roughly
            ($header)=iconv($attr[$_CHARSET], $prefs_charset, $header) if ($is_conv);

            if ( ($regexmatch && $header =~ /$keyword/im) ||
                 $header =~ /\Q$keyword\E/im ) {
               $new++ if ($attr[$_STATUS]!~/r/i);
               $totalsize+=$attr[$_SIZE];
               $found{$messageid}=1;
               next;
            }
         }

         # read and parse message
         if ($searchtype eq 'all' || $searchtype eq 'textcontent' || $searchtype eq 'attfilename') {
            seek($folderhandle, $attr[$_OFFSET], 0);
            read($folderhandle, $block, $attr[$_SIZE]);
            ($header, $body, $r_attachments)=parse_rfc822block(\$block);
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
                  $body = uudecode($body);
               }
               ($body)=iconv($attr[$_CHARSET], $prefs_charset, $body) if ($is_conv);
               if ( ($regexmatch && $body =~ /$keyword/im) ||
                    $body =~ /\Q$keyword\E/im ) {
                  $new++ if ($attr[$_STATUS]!~/r/i);
                  $totalsize+=$attr[$_SIZE];
                  $found{$messageid}=1;
                  next;
               }
            }
            # check attachments
            foreach my $r_attachment (@{$r_attachments}) {
               if ( ${$r_attachment}{contenttype} =~ /^text/i ||
                    ${$r_attachment}{contenttype} eq "N/A" ) {	# read all for text/plain. text/html
                  my $content;
                  if ( ${$r_attachment}{encoding} =~ /^quoted-printable/i ) {
                     $content = decode_qp( ${${$r_attachment}{r_content}});
                  } elsif ( ${$r_attachment}{encoding} =~ /^base64/i ) {
                     $content = decode_base64( ${${$r_attachment}{r_content}});
                  } elsif ( ${$r_attachment}{encoding} =~ /^x-uuencode/i ) {
                     $content = uudecode( ${${$r_attachment}{r_content}});
                  } else {
                     $content=${${$r_attachment}{r_content}};
                  }
                  my $attcharset=${$r_attachment}{charset}||$attr[$_CHARSET];
                  if (is_convertable($attcharset, $prefs_charset)) {
                     ($content)=iconv($attcharset, $prefs_charset, $content);
                  }

                  if ( ($regexmatch && $content =~ /$keyword/im) ||
                       $content =~ /\Q$keyword\E/im ) {
                     $new++ if ($attr[$_STATUS]!~/r/i);
                     $totalsize+=$attr[$_SIZE];
                     $found{$messageid}=1;
                     last;	# leave attachments check in one message
                  }
               }
            }
         }

	 # check attfilename
         if ($searchtype eq 'all' || $searchtype eq 'attfilename') {
            foreach my $r_attachment (@{$r_attachments}) {
               my $filename=${$r_attachment}{filename};
               my $attcharset=${$r_attachment}{filenamecharset}||${$r_attachment}{charset}||$attr[$_CHARSET];
               if (is_convertable($attcharset, $prefs_charset)) {
                  ($filename)=iconv($attcharset, $prefs_charset, $filename);
               }
               if ( ($regexmatch && $filename =~ /$keyword/im) ||
                    $filename =~ /\Q$keyword\E/im ) {
                  $new++ if ($attr[$_STATUS]!~/r/i);
                  $totalsize+=$attr[$_SIZE];
                  $found{$messageid}=1;
                  last;	# leave attachments check in one message
               }
            }
         }
      }

      close_dbm(\%HDB, $headerdb);

      open(CACHE, ">$cachefile");
      print CACHE $metainfo, "\n";
      print CACHE $headerdb, "\n";
      print CACHE $keyword, "\n";
      print CACHE $searchtype, "\n";
      print CACHE $ignore_internal, "\n";
      print CACHE join("\n", $totalsize, $new, keys(%found));
      close(CACHE);

   } else {
      open(CACHE, $cachefile);
      $_=<CACHE>;
      $_=<CACHE>;
      $_=<CACHE>;
      $_=<CACHE>;
      $_=<CACHE>;
      $totalsize=<CACHE>; chomp($totalsize);
      $new=<CACHE>;       chomp($new);
      while (<CACHE>) {
         chomp; $found{$_}=1;
      }
      close(CACHE);
   }

   filelock($cachefile, LOCK_UN);

   return($totalsize, $new, \%found);
}
#################### END SEARCH_MESSAGES_FOR_KEYWORD ######################

#################### SHIFTBLOCK ####################
sub shiftblock {
   my ($fh, $start, $size, $movement)=@_;
   my ($oldoffset, $movestart, $left, $buff);
   my $ioerr=0;

   return 0 if ($movement == 0 );

   $oldoffset=tell($fh);
   $left=$size;
   if ( $movement >0 ) {
      while ($left>0 && !$ioerr) {
         if ($left>=32768) {
             $movestart=$start+$left-32768;
             seek($fh, $movestart, 0);
             read($fh, $buff, 32768);
             seek($fh, $movestart+$movement, 0);
             print $fh $buff or $ioerr++;
             $left=$left-32768;
         } else {
             $movestart=$start;
             seek($fh, $movestart, 0);
             read($fh, $buff, $left);
             seek($fh, $movestart+$movement, 0);
             print $fh $buff or $ioerr++;
             $left=0;
         }
      }

   } elsif ( $movement <0 ) {
      while ($left>0 && !$ioerr) {
         if ($left>=32768) {
             $movestart=$start+$size-$left;
             seek($fh, $movestart, 0);
             read($fh, $buff, 32768);
             seek($fh, $movestart+$movement, 0);
             print $fh $buff or $ioerr++;
             $left=$left-32768;
         } else {
             $movestart=$start+$size-$left;
             seek($fh, $movestart, 0);
             read($fh, $buff, $left);
             seek($fh, $movestart+$movement, 0);
             print $fh $buff or $ioerr++;
             $left=0;
         }
      }
   }
   seek($fh, $oldoffset, 0);

   if ($ioerr) {
      return -1;
   } else {
      return 1;
   }
}
#################### END SHIFTBLOCK ####################

#################### SIMPLEHEADER ######################
sub simpleheader {
   my $header=$_[0];
   my $simpleheader="";

   my $lastline = 'NONE';
   foreach (split(/\n/, $header)) {
      if (/^\s/) {
         s/^\s+/ /;
         if ( ($lastline eq 'FROM') || ($lastline eq 'REPLYTO') ||
              ($lastline eq 'DATE') || ($lastline eq 'SUBJ') ||
              ($lastline eq 'TO') || ($lastline eq 'CC') ) {
            $simpleheader .= $_;
         }
      } elsif (/^</) {
         $simpleheader .= $_;
         $lastline = 'NONE';
      } elsif (/^from:\s?/ig) {
         $simpleheader .= $_;
         $lastline = 'FROM';
      } elsif (/^reply-to:\s?/ig) {
         $simpleheader .= $_;
         $lastline = 'REPLYTO';
      } elsif (/^to:\s?/ig) {
         $simpleheader .= $_;
         $lastline = 'TO';
      } elsif (/^cc:\s?/ig) {
         $simpleheader .= $_;
         $lastline = 'CC';
      } elsif (/^date:\s?/ig) {
         $simpleheader .= $_;
         $lastline = 'DATE';
      } elsif (/^subject:\s?/ig) {
         $simpleheader .= $_;
         $lastline = 'SUBJ';
      } else {
         $lastline = 'NONE';
      }
   }
   return($simpleheader);
}
################### END SIMPLEHEADER ###################

#################### IS_INTERNAL_SUBJECT ###################
sub is_internal_subject {
   if ($_[0] =~ /DON'T DELETE THIS MESSAGE/ ||
       $_[0] =~ /Message from mail server/ ) {
      return 1;
   } else {
      return 0;
   }
}
#################### END IS_INTERNAL_SUBJECT ###################

1;
