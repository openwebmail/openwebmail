#
# maildb.pl are functions for mail folderfile.
#
# 1. it speeds up the message access on folder file by hashing important 
#    information with perl dbm.
# 2. it parse mail recursively.
# 3. it converts uuencoded blocks into baed64-encoded attachments
# 4. it supports full content search and caches results for repeated queries.
#
# IMPORTANT!!!
#
# Functions in this file will do locks for dbm before read/write.
# They doesn't do locks for folderfile/folderhandle and relies the 
# caller for that lock.
# Functions with folderfile/folderhandle in argument must be inside
# a folderfile lock session
#
# An global variable $config{'dbm_ext'} needs to be defined to represent the
# dbm filename extension on your system. 
# ex: use 'db' for FreeBSD and 'dir' for Solaris
#
# An global variable $config{'use_dotlockfile'} needs to be defined to use 
# dotlockfile style locking
# This is recommended only if the lockd on your nfs server or client is broken
# ps: FrreBSD/Linux nfs server/client may need this. Solaris doesn't.
#
# 2001/12/21 tung@turtle.ee.ncku.edu.tw
#
use strict;
use Fcntl qw(:DEFAULT :flock);
use FileHandle;

use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES);
use vars qw(%month %timezones);

# extern vars
use vars qw(%config);	# defined in caller openwebmail-xxx.pl

# message attribute number, CONST
($_OFFSET, $_FROM, $_TO, $_DATE, $_SUBJECT, $_CONTENT_TYPE, $_STATUS, $_SIZE, $_REFERENCES)
 =(0,1,2,3,4,5,6,7,8);

# %month is used in the getheaders() sub to convert localtime() dates to
# a better format for readability and sorting.
%month = qw(Jan   1
            Feb   2
            Mar   3
            Apr   4
            May   5
            Jun   6
            Jul   7
            Aug   8
            Sep   9
            Oct   10
            Nov   11
            Dec   12);

# @monthday=qw(31 31 29 31 30 31 30 31 31 30 31 30 31);

%timezones = qw(ACDT +1030
                ACST +0930
                ADT  -0300
                AEDT +1100
                AEST +1000
                AHDT -0900
                AHST -1000
                AST  -0400
                AT   -0200
                AWDT +0900
                AWST +0800
                AZST +0400
                BAT  +0300
                BDST +0200
                BET  -1100
                BST  -0300
                BT   +0300
                BZT2 -0300
                CADT +1030
                CAST +0930
                CAT  -1000
                CCT  +0800
                CDT  -0500
                CED  +0200
                CET  +0100
                CST  -0600
                EAST +1000
                EDT  -0400
                EED  +0300
                EET  +0200
                EEST +0300
                EST  -0500
                FST  +0200
                FWT  +0100
                GMT  +0000
                GST  +1000
                HDT  -0900
                HST  -1000
                IDLE +1200
                IDLW -1200
                IST  +0530
                IT   +0330
                JST  +0900
                JT   +0700
                MDT  -0600
                MED  +0200
                MET  +0100
                MEST +0200
                MEWT +0100
                MST  -0700
                MT   +0800
                NDT  -0230
                NFT  -0330
                NT   -1100
                NST  +0630
                NZ   +1100
                NZST +1200
                NZDT +1300
                NZT  +1200
                PDT  -0700
                PST  -0800
                ROK  +0900
                SAD  +1000
                SAST +0900
                SAT  +0900
                SDT  +1000
                SST  +0200
                SWT  +0100
                USZ3 +0400
                USZ4 +0500
                USZ5 +0600
                USZ6 +0700
                UT   +0000
                UTC  +0000
                UZ10 +1100
                WAT  -0100
                WET  +0000
                WST  +0800
                YDT  -0800
                YST  -0900
                ZP4  +0400
                ZP5  +0500
                ZP6  +0600);

if ( $config{'dbm_ext'} eq "" ) {
   $config{'dbm_ext'}=".db";
}

######################### UPDATE_HEADERDB ############################
# this routine indexes the messages in a mailfolder
# and remove those with duplicated messageids
sub update_headerdb {
   my ($headerdb, $folderfile) = @_;
   my (%HDB, %OLDHDB);
   my @oldmessageids=();

   ($headerdb =~ /^(.+)$/) && ($headerdb = $1);		# untaint ...
   if ( -e "$headerdb$config{'dbm_ext'}" ) {
      my ($metainfo, $allmessages, $internalmessages, $newmessages);

      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
      $metainfo=$HDB{'METAINFO'};
      $allmessages=$HDB{'ALLMESSAGES'};
      $internalmessages=$HDB{'INTERNALMESSAGES'};
      $newmessages=$HDB{'NEWMESSAGES'};
      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

      if ( $metainfo eq metainfo($folderfile) && $allmessages >=0  
           && $internalmessages >=0 && $newmessages >=0 ) {
         return;  
      }

      if ($config{'dbm_ext'} eq 'dir') {
         rename("$headerdb.dir", "$headerdb.old.dir");
         rename("$headerdb.pag", "$headerdb.old.pag");
      } else {
         rename("$headerdb$config{'dbm_ext'}", "$headerdb.old$config{'dbm_ext'}");
      }

      # we will try to reference records in old headerdb if possible
      @oldmessageids=get_messageids_sorted_by_offset("$headerdb.old");
      filelock("$headerdb.old$config{'dbm_ext'}", LOCK_SH);
      dbmopen(%OLDHDB, "$headerdb.old$config{'dbmopen_ext'}", undef);
   }

   my $messagenumber = -1;
   my $newmessages = 0;
   my $internalmessages = 0;

   my $inheader = 0;
   my $offset=0;
   my $totalsize=0;

   my @duplicateids=();

   my ($line, $lastheader, $namedatt_count, $zhtype);
   my ($_message_id, $_offset);
   my ($_from, $_to, $_date, $_subject);
   my ($_content_type, $_status, $_messagesize, $_references, $_inreplyto);

   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", 0600);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
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
         $HDB{$id}=join('@@@', @attr);
         $internalmessages++ if ( is_internal_subject($attr[$_SUBJECT]) );
         $newmessages++ if ($attr[$_STATUS] !~ /r/i);
         $messagenumber++;
      }  else {
         $totalsize-=$attr[$_SIZE];
         last;
      }
   }
   seek(FOLDER, $totalsize, 0);		# set file ptr back to totalsize

   while (defined($line = <FOLDER>)) {

      $offset=$totalsize;
      $totalsize += length($line);

      # ex: From tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
      # ex: From tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
      # ex: From nsb@thumper.bellcore.com Wed Mar 11 16:27:37 EST 1992
      if ( $line =~ /^From .*(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+(\w\w\w\s+)?(\d\d+)/ ) {
         if ($_messagesize >0) {

            $_from=~s/\@\@/\@\@ /g;         $_from=~s/\@$/\@ /;
            $_to=~s/\@\@/\@\@ /g;           $_to=~s/\@$/\@ /;
            $_subject=~s/\@\@/\@\@ /g;      $_subject=~s/\@$/\@ /;
            $_content_type=~s/\@\@/\@\@ /g; $_content_type=~s/\@$/\@ /;
            $_status=~s/\@\@/\@\@ /g;       $_status=~s/\@$/\@ /;
            $_references=~s/\@\@/\@\@ /g;   $_references=~s/\@$/\@ /;
            $_inreplyto=~s/\@\@/\@\@ /g;    $_inreplyto=~s/\@$/\@ /;

            # in most case, a msg references field should already contain 
            # ids in in-reply-to: field, but do check it again here
	    if ($_inreplyto =~ m/^\s*(\<\S+\>)\s*$/) {
	       $_references .= " " . $1 if ($_references!~/$1/);
	    }
	    $_references =~ s/\s{2,}/ /g;

            if ($_message_id eq '') {	# fake messageid with date and from
               if ($_date ne "") {
                  $_message_id="$_date.".(email2nameaddr($_from))[1];
               } else {
                  $_message_id = getdateserial().'.X'.int(rand()*100000);
               }
               $_message_id=~s![\<\>\(\)\s\/"':]!!g;
               $_message_id="<$_message_id>";
            }

            # flags used by openwebmail internally
            $_status .= "T" if ($namedatt_count>0);
            $_status .= "B" if ($zhtype eq 'big5');
            $_status .= "G" if ($zhtype eq 'gb');

            if (! defined($HDB{$_message_id}) ) {
               $HDB{$_message_id}=join('@@@', $_offset, $_from, $_to, 
			$_date, $_subject, $_content_type, $_status, $_messagesize, $_references);
            } else {
               my $dup=$#duplicateids+1;
               $HDB{"dup$dup-$_message_id"}=join('@@@', $_offset, $_from, $_to, 
			$_date, $_subject, $_content_type, $_status, $_messagesize, $_references);
               push(@duplicateids, "dup$dup-$_message_id");
            }
         }

         $messagenumber++;
         $_offset=$offset;
         $_from = $_to = $_date = $_subject = $_content_type ='N/A';
         $_message_id='';
         $_inreplyto = '';
         $_references = '';
         $_status = '';
         $_messagesize = length($line);
         $_date = $line;
         $inheader = 1;
         $lastheader = 'NONE';
         $namedatt_count=0;
         $zhtype='';

      } else {
         $_messagesize += length($line);

         if ($inheader) {
            if ($line =~ /^\r*$/) {
               $inheader = 0;

               # Convert to readable text from MIME-encoded
               $_from = decode_mimewords($_from);
               $_subject = decode_mimewords($_subject);

               # some dbm(ex:ndbm on solaris) can only has value shorter than 1024 byte, 
               # so we cut $_to to 256 byte to make dbm happy
               if (length($_to) >256) {
                  $_to=substr($_to, 0, 252)."...";
               }

               # extract date from the 'From ' line, it must be in this form
               my @d;
               # From tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
               # From tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
               # From nsb@thumper.bellcore.com Wed Mar 11 16:27:37 EST 1992
               $_date =~ /(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+(\w\w\w\s+)?(\d\d+)/;
               @d=($8, $month{$2}, $3, $4, $5, $6);
               if ($d[0]<50) { 		# 2 digit year
                   $d[0]+=2000; 
               } elsif ($d[0]<=1900) {
                   $d[0]+=1900;
               }
               $_date=sprintf("%4d%02d%02d%02d%02d%02d", @d);

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
                     $namedatt_count++   if ($oldstatus=~/T/);
                     $zhtype="big5"      if ($oldstatus=~/B/);
                     $zhtype="gb"        if ($oldstatus=~/G/);
                  }

                  seek(FOLDER, $totalsize, 0);
               }

            } elsif ($line =~ /^\s/) {
               $line =~ s/^\s+/ /;
               chomp($line);
               if    ($lastheader eq 'FROM') { $_from .= $line }
               elsif ($lastheader eq 'SUBJ') { $_subject .= $line }
               elsif ($lastheader eq 'TO') { $_to .= $line }
               elsif ($lastheader eq 'MESSID') { $_message_id .= $line; }
               elsif ($lastheader eq 'TYPE') { $_content_type .= $line; }
	       elsif ($lastheader eq 'REFERENCES') { $_references .= "$line "; }
	       elsif ($lastheader eq 'INREPLYTO') { $_inreplyto .= "$line "; }
            } elsif ($line =~ /^from:\s?(.+)$/ig) {
               $_from = $1;
               $lastheader = 'FROM';
            } elsif ($line =~ /^to:\s?(.+)$/ig) {
               $_to = $1;
               $lastheader = 'TO';
            } elsif ($line =~ /^subject:\s?(.+)$/ig) {
               $_subject = $1;
               $lastheader = 'SUBJ';
            } elsif ($line =~ /^message-id:\s?(.*)$/ig) {
               $_message_id = $1;
               $lastheader = 'MESSID';
	    } elsif ($line =~ /^in-reply-to:\s?(.+)$/ig) {
               $_inreplyto .= $1 . " ";
               $lastheader = 'INREPLYTO';
	    } elsif ($line =~ /^references:\s?(.+)$/ig) {
               $_references .= $1 . " ";
               $lastheader = 'REFERENCES';
            } elsif ($line =~ /^content-type:\s?(.+)$/ig) {
               $_content_type = $1;
               $lastheader = 'TYPE';
            } elsif ($line =~ /^status:\s?(.+)$/i ||
                     $line =~ /^x\-status:\s?(.+)$/i ) {
               $_status .= $1;
               $_status =~ s/\s//g;	# remove blanks
               $lastheader = 'NONE';
            } elsif ($line =~ /^priority:\s+(.*)$/i) {
               my $priority=$1;
               if ($priority =~ /^\s*urgent\s*$/i) {
                  $_status .= "I";
               }
               $lastheader = 'NONE';
            } else {
               $lastheader = 'NONE';
            }

         } else {
            if ( $line =~ /^content\-type:.*;\s+name\s*=/i ||
                 $line =~ /^\s+name\s*=/i ||
                 $line =~ /^content\-disposition:.*;\s+filename\s*=/i ||
                 $line =~ /^\s+filename\s*=/i ||
                 $line =~ /^begin [0-7][0-7][0-7][0-7]? [^\n\r]+/ ) {
               if ($line !~ /[\<\>]/ && $line !~ /type=/i) {
                  $namedatt_count++;
               }
            }
            if ( $line =~ /^content\-type:.*;\s?charset="?big5"?/i ||
                 $line =~ /^\s+charset="?big5"?/i ) {
               $zhtype="big5";
            } elsif ( $line =~ /^content\-type:.*;\s?charset="?gb2312"?/i ||
                      $line =~ /^\s+charset="?gb2312"?/i ) {
               $zhtype="gb";
            }
         }
      }

   }

   # Catch the last message, since there won't be a From: to trigger the capture
   if ($_messagesize >0) {

      $_from=~s/\@\@/\@\@ /g;         $_from=~s/\@$/\@ /;
      $_to=~s/\@\@/\@\@ /g;           $_to=~s/\@$/\@ /;
      $_subject=~s/\@\@/\@\@ /g;      $_subject=~s/\@$/\@ /;
      $_content_type=~s/\@\@/\@\@ /g; $_content_type=~s/\@$/\@ /;
      $_status=~s/\@\@/\@\@ /g;       $_status=~s/\@$/\@ /;
      $_references=~s/\@\@/\@\@ /g;   $_references=~s/\@$/\@ /;
      $_inreplyto=~s/\@\@/\@\@ /g;    $_inreplyto=~s/\@$/\@ /;

      # in most case, a msg references field should already contain 
      # ids in in-reply-to: field, but do check it again here
      if ($_inreplyto =~ m/^\s*(\<\S+\>)\s*$/) {
	 $_references .= " " . $1 if ($_references!~/$1/);
      }
      $_references =~ s/\s{2,}/ /g;

      if ($_message_id eq '') {	# fake messageid with date and from
         $_message_id="$_date.".(email2nameaddr($_from))[1];
         $_message_id=~s![\<\>\(\)\s\/"':]!!g;
         $_message_id="<$_message_id>";
      }
      
      # flags used by openwebmail internally
      $_status .= "T" if ($namedatt_count>0);
      $_status .= "B" if ($zhtype eq 'big5');
      $_status .= "G" if ($zhtype eq 'gb');

      if (! defined($HDB{$_message_id}) ) {
         $HDB{$_message_id}=join('@@@', $_offset, $_from, $_to, 
		$_date, $_subject, $_content_type, $_status, $_messagesize, $_references);
      } else {
         my $dup=$#duplicateids+1;
         $HDB{"dup$dup-$_message_id"}=join('@@@', $_offset, $_from, $_to, 
		$_date, $_subject, $_content_type, $_status, $_messagesize, $_references);
         push(@duplicateids, "dup$dup-$_message_id");
      }
   }

   close (FOLDER);

   $HDB{'METAINFO'}=metainfo($folderfile);
   $HDB{'ALLMESSAGES'}=$messagenumber+1;
   $HDB{'INTERNALMESSAGES'}=$internalmessages;
   $HDB{'NEWMESSAGES'}=$newmessages;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
   dbmclose(%HDB);

   # remove old headerdb
   if (defined(%OLDHDB)) {
      dbmclose(%OLDHDB);
      filelock("$headerdb.old$config{'dbm_ext'}", LOCK_UN);
      unlink("$headerdb.old$config{'dbm_ext'}", "$headerdb.old.dir", "$headerdb.old.pag");
   }

   # remove if any duplicates
   if ($#duplicateids>=0) {
      operate_message_with_ids("delete", \@duplicateids, $folderfile, $headerdb);
   }

   return;
}

################## END UPDATEHEADERDB ####################

############### GET_MESSAGEIDS_SORTED_BY_...  #################
sub get_messageids_sorted_by_offset {
   my $headerdb=$_[0];
   my (%HDB, @attr, %offset, $key, $data);

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);

   while ( ($key, $data)=each(%HDB) ) {
      next if ( $key eq 'METAINFO' 
             || $key eq 'NEWMESSAGES' 
             || $key eq 'INTERNALMESSAGES' 
             || $key eq 'ALLMESSAGES' 
             || $key eq "" );

      @attr=split( /@@@/, $data );
      $offset{$key}=$attr[$_OFFSET];
   }

   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

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

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
   $metainfo=$HDB{'METAINFO'};
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   filelock($cachefile, LOCK_EX);

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
      $_=<CACHE>; 
      $_=<CACHE>;
      $_=<CACHE>;
      $_=<CACHE>;
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

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   @messageids=sort { $dateserial{$b}<=>$dateserial{$a} } keys(%dateserial);
   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_from {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %from, %dateserial, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

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

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

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

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

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
}


sub get_info_messageids_sorted_by_size {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %size, %dateserial, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

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

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

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

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
   @attr=split(/@@@/, $HDB{$messageid} );
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
   return(@attr);
}

sub get_message_block {
   my ($messageid, $headerdb, $folderhandle)=@_;
   my (@attr, $buff);

   @attr=get_message_attributes($messageid, $headerdb);
   if ($#attr>=0) {
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
   my $folderhandle=FileHandle->new();
   my %HDB;

   update_headerdb($headerdb, $folderfile);

   my @messageids=get_messageids_sorted_by_offset($headerdb);
   my $movement=0;
   my @attr;
   my $i;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", 0600);

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
            dbmclose(%HDB);
            filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
            return(-1);
         }
         $headerlen=length($header);
         $headerend=$messagestart+$headerlen;

         # update status, flags from rfc2076
         my $status_update = "";
         $status_update .= "R" if ($status =~ m/r/i); # Read
         $status_update .= "U" if ($status =~ m/u/i); # undownloaded & not deleted
         $status_update .= "N" if ($status =~ m/n/i); # New
         $status_update .= "D" if ($status =~ m/d/i); # to be Deleted
         $status_update .= "O" if ($status =~ m/o/i); # Old
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
         shiftblock($folderhandle, $headerend, $foldersize-$headerend, $movement);

         seek($folderhandle, $messagestart, 0);
         print $folderhandle $header;

         seek($folderhandle, $foldersize+$movement, 0);
         truncate($folderhandle, tell($folderhandle));
         close ($folderhandle);

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

         last;
      }
   }
   $i++;

   # if size of this message is changed
   if ($movement!=0) {
      #  change offset attr for messages after the above one 
      for (;$i<=$#messageids; $i++) {
         @attr=split(/@@@/, $HDB{$messageids[$i]});
         $attr[$_OFFSET]+=$movement;
         $HDB{$messageids[$i]}=join('@@@', @attr);
      }
   }

   # update folder metainfo
   $HDB{'METAINFO'}=metainfo($folderfile);

   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   return(0);
}

#################### END UPDATE_MESSAGE_STATUS ######################

###################### OP_MESSAGE_WITH_IDS #########################
# operate messages with @messageids from src folderfile to dst folderfile
# available $op: "move", "copy", "delete"
sub operate_message_with_ids {
   my ($op, $r_messageids, $srcfile, $srcdb, $dstfile, $dstdb)=@_;
   my $folderhandle=FileHandle->new();
   my (%HDB, %HDB2);
   my $messageids = join("\n", @{$r_messageids});

   # $lang_err{'inv_msg_op'}
   return(-1) if ($op ne "move" && $op ne "copy" && $op ne "delete"); 
   return(0) if ($srcfile eq $dstfile || $#{$r_messageids} < 0);

   update_headerdb($srcdb, $srcfile);
   open ($folderhandle, "+<$srcfile") or 
      return(-2);	# $lang_err{'couldnt_open'} $srcfile!

   if ($op eq "move" || $op eq "copy") {
      open (DEST, ">>$dstfile") or
         return(-3);	# $lang_err{'couldnt_open'} $destination!
      update_headerdb("$dstdb", $dstfile);
   }

   my @allmessageids=get_messageids_sorted_by_offset($srcdb);
   my ($blockstart, $blockend, $writepointer);
   my ($messagestart, $messagesize, $messagevalid, @attr, $buff);
   my $counted=0;
   
   filelock("$srcdb$config{'dbm_ext'}", LOCK_EX);
   dbmopen (%HDB, "$srcdb$config{'dbmopen_ext'}", 0600);

   if ($op eq "move" || $op eq "copy") {
      filelock("$dstdb$config{'dbm_ext'}", LOCK_EX);
      dbmopen (%HDB2, "$dstdb$config{'dbmopen_ext'}", 0600);
   }

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
            shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart);
            $writepointer=$writepointer+($blockend-$blockstart);
            $blockstart=$blockend=$messagestart+$messagesize;
         } else {
            $blockend=$messagestart+$messagesize;
         }

         # append msg to dst folder only if 
         # op=move/copy and msg doesn't exist in dstfile
         if (($op eq "move" || $op eq "copy") && 
             !defined($HDB2{$allmessageids[$i]}) ) {

            seek($folderhandle, $attr[$_OFFSET], 0);
            $attr[$_OFFSET]=tell(DEST);

            # copy message from $folderhandle to DEST
            my $left=$attr[$_SIZE];
            while ($left>0) {
               if ($left>=32768) {
                   read($folderhandle, $buff, 32768);
                   print DEST $buff;
                   $left=$left-32768;
               } else {
                   read($folderhandle, $buff, $left);
                   print DEST $buff;
                   $left=0;
               }
            }

            $HDB2{'NEWMESSAGES'}++ if ($attr[$_STATUS]!~/r/i);
            $HDB2{'INTERNALMESSAGES'}++ if (is_internal_subject($attr[$_SUBJECT]));
            $HDB2{'ALLMESSAGES'}++;
            $HDB2{$allmessageids[$i]}=join('@@@', @attr);
         } 
         
         if ($op eq 'move' || $op eq 'delete') {
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
   }

   if ( ($op eq 'move' || $op eq 'delete') && $counted>0 ) {
      shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart);
      seek($folderhandle, $writepointer+($blockend-$blockstart), 0);
      truncate($folderhandle, tell($folderhandle));
   }

   if ($op eq "move" || $op eq "copy") { 
      close (DEST);
      $HDB2{'METAINFO'}=metainfo($dstfile);
      dbmclose(%HDB2);
      filelock("$dstdb$config{'dbm_ext'}", LOCK_UN);
   }

   close ($folderhandle);
   $HDB{'METAINFO'}=metainfo($srcfile);
   dbmclose(%HDB);
   filelock("$srcdb$config{'dbm_ext'}", LOCK_UN);

   return($counted);
}
#################### END OP_MESSAGE_WITH_IDS #######################

#################### DELETE_MESSAGE_BY_AGE #######################
sub delete_message_by_age {
   my ($age, $headerdb, $folderfile)=@_;

   my $folderhandle=FileHandle->new();
   my %HDB;
   my (@allmessageids, @agedids);
   
   return 0 if ( ! -f $folderfile );

   update_headerdb($headerdb, $folderfile);

   @allmessageids=get_messageids_sorted_by_offset($headerdb);

   filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", 0600);
   foreach (@allmessageids) {
      my @attr = split(/@@@/, $HDB{$_});
      push(@agedids, $_) if (dateserial2age($attr[$_DATE])>=$age);
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   return 0 if ($#agedids==-1);
   return(operate_message_with_ids('delete', \@agedids, $folderfile, $headerdb));
}

################### END DELETE_MESSAGE_BY_AGE #####################

####################### MOVE_OLDMSG_FROM_FOLDER #################
sub move_oldmsg_from_folder {
   my ($srcfile, $srcdb, $dstfile, $dstdb)=@_;
   my (%HDB, $key, $data, @attr);
   my @messageids=();

   filelock("$srcdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen (%HDB, "$srcdb$config{'dbmopen_ext'}", undef);

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

   dbmclose(%HDB);
   filelock("$srcdb$config{'dbm_ext'}", LOCK_UN);

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

   update_headerdb($headerdb, $folderfile);

   # find all partial msgids
   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
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
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   # check completeness 
   if ($partialtotal<1) {	# last part not found
      return(-1);
   }
   for (my $i=1; $i<=$partialtotal; $i++) {
      if ($partialmsgids[$i] eq "") {	# some part missing
         return(-2);
      }
   }

   my $tmpfile="/tmp/rebuild_tmp_$$";
   my $tmpdb="/tmp/.rebuild_tmp_$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);
   ($tmpdb =~ /^(.+)$/) && ($tmpdb = $1);

   filelock("$tmpfile", LOCK_EX);
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
   filelock("$tmpfile", LOCK_EX);

   # index tmpfile, get the msgid
   update_headerdb($tmpdb, $tmpfile);

   # check the rebuild integrity
   my @rebuildmsgids=get_messageids_sorted_by_offset($tmpdb);
   if ($#rebuildmsgids!=0) {
      unlink("$tmpdb$config{'dbm_ext'}", $tmpfile);
      return(-3);
   }
   my $rebuildsize=(get_message_attributes($rebuildmsgids[0], $tmpdb))[$_SIZE];
   if ($writtensize!=$rebuildsize) {
      unlink("$tmpdb$config{'dbm_ext'}", $tmpfile);
      return(-4);
   }

   my $moved=operate_message_with_ids("move", \@rebuildmsgids, 
				$tmpfile, $tmpdb, $folderfile, $headerdb);

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
            if ( $body =~ /\nbegin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n/ims ) {
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
   while ( $body =~ m/\nbegin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n/igms ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid eq "$nodeid-$i" ) {
         my ($uumode, $uufilename, $uubody) = ($1, $2, $3);
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

   $body =~ s/\nbegin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n//igms;
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
   my $attfilename;
   my %temphash;

   $attfilename = $attcontenttype;
#   $attcontenttype =~ s/^(.+);.*/$1/g;
   if ($attfilename =~ s/^.+name\s?[:=]\s?"?([^"]+)"?.*$/$1/ig) {
      $attfilename = decode_mimewords($attfilename);
   } elsif ($attfilename =~ s/^.+name\s?[:=]\s?"?[\w]+''([^"]+)"?.*$/$1/ig) {
      $attfilename = unescapeURL($attfilename);
   } else {
      $attfilename = $attdisposition || '';
      if ($attfilename =~ s/^.+filename\s?=\s?"?([^"]+)"?.*$/$1/ig) {
         $attfilename = decode_mimewords($attfilename);
      } elsif ($attfilename =~ s/^.+filename\s?=\s?"?[\w]+''([^"]+)"?.*$/$1/ig) {
         $attfilename = unescapeURL($attfilename);
      } else {
         $attfilename = "Unknown.".contenttype2ext($attcontenttype);
      }
   }
   $attfilename=~s|[\\/]|!|g;	# the filename of attachments should not contain / or \

   $attdisposition =~ s/^(.+);.*/$1/g;

   # guess a better contenttype
   if ( $attcontenttype =~ m!(\Qapplication/octet-stream\E)!i ||
        $attcontenttype =~ m!(\Qvideo/mpg\E)!i ) {
      my $oldtype=$1;
      $attfilename=~ /\.([\w\d]*)$/;
      my $newtype=ext2contenttype($1);
      $attcontenttype=~ s!$oldtype!$newtype!i;
   }

   # the 2 attr are coming from parent block
   $temphash{subtype} = $subtype;
   $temphash{boundary} = $boundary;

   $temphash{header} = decode_mimewords($attheader);
   $temphash{r_content} = $r_attcontent;
   $temphash{contentlength} = $attcontentlength;
   $temphash{contenttype} = $attcontenttype || 'text/plain';
   $temphash{encoding} = $attencoding;
   $temphash{disposition} = $attdisposition;
   $temphash{filename} = $attfilename;
   $temphash{id} = $attid;
   $temphash{location} = $attlocation;
   $temphash{nodeid} = $nodeid;
   $temphash{description} = $attdescription;
   $temphash{referencecount} = 0;
   return(\%temphash);
}

sub contenttype2ext {
   my $contenttype=$_[0];
   my ($class, $ext, $dummy)=split(/[\/\s;,]+/, $contenttype);
   
   return("txt") if ($contenttype eq "N/A");
   return("mp3") if ($contenttype=~m!audio/mpeg!i);
   return("au")  if ($contenttype=~m!audio/x\-sun!i);
   return("ra")  if ($contenttype=~m!audio/x\-realaudio!i);

   $ext=~s/^x-//i;
   return(lc($ext))  if length($ext) <=4;

   return("txt") if ($class =~ /text/i);
   return("msg") if ($class =~ /message/i);

   return("doc") if ($ext =~ /msword/i);
   return("ppt") if ($ext =~ /powerpoint/i);
   return("xls") if ($ext =~ /excel/i);
   return("vsd") if ($ext =~ /visio/i);
   return("vcf") if ($ext =~ /vcard/i);
   return("tar") if ($ext =~ /tar/i);
   return("zip") if ($ext =~ /zip/i);
   return("avi") if ($ext =~ /msvideo/i);
   return("mov") if ($ext =~ /quicktime/i);
   return("swf") if ($ext =~ /shockwave-flash/i);
   return("hqx") if ($ext =~ /mac-binhex40/i);
   return("ps")  if ($ext =~ /postscript/i);
   return("js")  if ($ext =~ /javascript/i);
   return("bin");
}

sub ext2contenttype {
   my $ext=$_[0];

   return("application/msword") 	if ($ext =~ /doc$/i);
   return("application/x-mspowerpoint") if ($ext =~ /ppt$/i);
   return("application/x-msexcel") 	if ($ext =~ /xls$/i);
   return("video/mpeg")			if ($ext =~ /(mpeg|mpg|mp2|mpe)$/i);
   return("video/x-msvideo")		if ($ext =~ /(avi|wav|dl|fli)$/i);
   return("video/quicktime")		if ($ext =~ /(mov|qt)$/i);
   return("audio/mpeg")			if ($ext =~ /mp3$/i);
   return("text/xml")			if ($ext =~ /xml$/i);
   return("text/html")			if ($ext =~ /(html|htm)$/i);
   return("text/plain")			if ($ext =~ /(txt|text|c|h|cpp|cc|asm|pas|f77|lst|sh|pl)$/i);
   return("application/pdf")		if ($ext =~ /pdf$/i);
   return("application/postscript")	if ($ext =~ /(ps|eps|ai)$/i);
   return("application/mac-binhex40")	if ($ext =~ /hqx$/i);
   return("application/x-javascript")	if ($ext =~ /js$/i);
   return("application/x-msvisio")	if ($ext =~ /visio$/i);
   return("application/x-vcard")	if ($ext =~ /vcf$/i);
   return("application/x-shockwave-flash")	if ($ext =~ /swf$/i);
   return("application/x-zip-compressed")	if ($ext =~ /zip$/i);

   return("application/octet-stream");
}
####################### END PARSE_.... related ###########################

#################### SEARCH_MESSAGES_FOR_KEYWORD ###########################
# searchtype: subject, from, to, date, attfilename, header, textcontent, all
sub search_info_messages_for_keyword {
   my ($keyword, $searchtype, $headerdb, $folderhandle, $cachefile, $ignore_internal)=@_;
   my ($metainfo, $cache_metainfo, $cache_headerdb, $cache_keyword, $cache_searchtype, $cache_ignore_internal);
   my (%HDB, @messageids, $messageid);
   my ($totalsize, $new)=(0,0);
   my %found=();

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
   $metainfo=$HDB{'METAINFO'};
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   filelock($cachefile, LOCK_EX);

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
      open(CACHE, ">$cachefile");
      print CACHE $metainfo, "\n";
      print CACHE $headerdb, "\n";
      print CACHE $keyword, "\n";
      print CACHE $searchtype, "\n";
      print CACHE $ignore_internal, "\n";

      @messageids=get_messageids_sorted_by_offset($headerdb, $folderhandle);

      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);

      foreach $messageid (@messageids) {
         my (@attr, $block, $header, $body, $r_attachments) ;
         @attr=split(/@@@/, $HDB{$messageid});
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));

         # check subject, from, to, date
         if ( ( ($searchtype eq 'all' || 
                 $searchtype eq 'subject') &&
                ($attr[$_SUBJECT]=~/$keyword/i ||
                 $attr[$_SUBJECT]=~/\Q$keyword\E/i) )  ||
              ( ($searchtype eq 'all' || 
                 $searchtype eq 'from') &&
                ($attr[$_FROM]=~/$keyword/i ||
                 $attr[$_FROM]=~/\Q$keyword\E/i) )  ||
              ( ($searchtype eq 'all' || 
                 $searchtype eq 'to') &&
                ($attr[$_TO]=~/$keyword/i ||
                 $attr[$_TO]=~/\Q$keyword\E/i) )  ||
              ( ($searchtype eq 'all' || 
                 $searchtype eq 'date') &&
                ($attr[$_DATE]=~/$keyword/i ||
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
            if ( $header =~ /$keyword/im ||
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
               if ( $body =~ /$keyword/im ||
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
                  if ( ${$r_attachment}{encoding} =~ /^quoted-printable/i ) {
                     ${${$r_attachment}{r_content}} = decode_qp( ${${$r_attachment}{r_content}});
                  } elsif ( ${$r_attachment}{encoding} =~ /^base64/i ) {
                     ${${$r_attachment}{r_content}} = decode_base64( ${${$r_attachment}{r_content}});
                  } elsif ( ${$r_attachment}{encoding} =~ /^x-uuencode/i ) {
                     ${${$r_attachment}{r_content}} = uudecode( ${${$r_attachment}{r_content}});
                  }
                  if ( ${${$r_attachment}{r_content}} =~ /$keyword/im ||
                       ${${$r_attachment}{r_content}} =~ /\Q$keyword\E/im ) {
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
               if ( ${$r_attachment}{filename} =~ /$keyword/im ||
                    ${$r_attachment}{filename} =~ /\Q$keyword\E/im ) { 
                  $new++ if ($attr[$_STATUS]!~/r/i);
                  $totalsize+=$attr[$_SIZE];
                  $found{$messageid}=1;
                  last;	# leave attachments check in one message
               }
            }
         }
      }

      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

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

######################## HTML related ##############################
# it is suggested calling these following routine in the following order:
# html4nobase, html4link, html4disablejs, html4disableembcgi, 
# html4attachment, html4mailto, html2table

# since this routine deals with base directive, 
# it must be called first before other html...routines when converting html
sub html4nobase {
   my $html=$_[0];
   my $urlbase; 
   if ( $html =~ m#\<base\s+href\s*=\s*"?([^\<\>]*?)"?\>#i ) {
      $urlbase=$1;
      $urlbase=~s#/[^/]+$#/#;
   }

   $html =~ s#\<base\s+([^\<\>]*?)\>##gi;
   if ( ($urlbase ne "") && ($urlbase !~ /^file:/) ) {
      $html =~ s#(\<a\s+href|background|src|method|action)(=\s*"?)#$1$2$urlbase#gi;
      # recover links that should not be changed by base directive
      $html =~ s#\Q$urlbase\E(http://|https://|ftp://|cid:|mailto:)#$1#gi;
   }
   return($html);
}

my @jsevents=('onAbort', 'onBlur', 'onChange', 'onClick', 'onDblClick', 
              'onDragDrop', 'onError', 'onFocus', 'onKeyDown', 'onKeyPress', 
              'onKeyUp', 'onLoad', 'onMouseDown', 'onMouseMove', 'onMouseOut',
              'onMouseOver', 'onMouseUp', 'onMove', 'onReset', 'onResize', 
              'onSelect', 'onSubmit', 'onUnload');

# this routine is used to add target=_blank to links in a html message
# so clicking on it will open a new window
sub html4link {
   my $html=$_[0];
   $html=~s/(<a\s+[^\<\>]*?>)/_link_target_blank($1)/igems;
   return($html);
}

sub _link_target_blank {
   my $link=$_[0];
#   foreach my $event (@jsevents) {
#      return($link) if ($link =~ /$event/i);
#   }
   if ($link =~ /target=/i ||
       $link =~ /javascript:/i ) {
      return($link);
   }
   $link=~s/<a\s+([^\<\>]*?)>/<a $1 target=_blank>/is;
   return($link);
}

# this routine disables the javascript in a html message
# to avoid user being hijacked by some eval programs
sub html4disablejs {
   my $html=$_[0];
   my $event;

   foreach $event (@jsevents) {
      $html=~s/$event/_$event/imsg;
   }
   $html=~s/<script([^\<\>]*?)>/<disable_script$1>\n<!--\n/imsg;
   $html=~s/<!--\s*<!--/<!--/imsg;
   $html=~s/<\/script>/\n\/\/-->\n<\/disable_script>/imsg;
   $html=~s/\/\/-->\s*\/\/-->/\/\/-->/imsg;
   $html=~s/<([^\<\>]*?)javascript:([^\<\>]*?)>/<$1disable_javascript:$2>/imsg;
   
   return($html);
}

# this routine disables the embedded CGI in a html message
# to avoid user email addresses being confirmed by spammer through embedded CGIs
sub html4disableembcgi {
   my $html=$_[0];
   $html=~s!(src|background)\s*=\s*("?https?://[\w\.\-]+?/?[^\s<>]*[\w/])([\b|\n| ]*)!_clean_embcgi($1,$2,$3)!egis;
   return($html);
}

sub _clean_embcgi {
   my ($type, $url, $end)=@_;

   if ($url=~/\?/s && $url !~ /\Q$ENV{'HTTP_HOST'}\E/is) { # non local CGI found
      $url=~s/["']//g;
      return("alt='Embedded CGI removed by $config{'name'}.\n$url'".$end);
   } else {
      return("$type=$url".$end);
   }
}

# this routine is used to resolve crossreference inside attachments
# by converting them to request attachment from openwebmail cgi
sub html4attachments {
   my ($html, $r_attachments, $scripturl, $scriptparm)=@_;
   my $i;

   for ($i=0; $i<=$#{$r_attachments}; $i++) {
      my $filename=escapeURL(${${$r_attachments}[$i]}{filename});
      my $link="$scripturl/$filename?$scriptparm&amp;attachment_nodeid=${${$r_attachments}[$i]}{nodeid}&amp;";
      my $cid="cid:"."${${$r_attachments}[$i]}{id}";
      my $loc=${${$r_attachments}[$i]}{location};

      if ( ($cid ne "cid:" && $html =~ s#\Q$cid\E#$link#ig ) ||
           ($loc ne "" && $html =~ s#\Q$loc\E#$link#ig ) ||
           # ugly hack for strange CID     
           ($filename ne "" && $html =~ s#CID:\{[\d\w\-]+\}/$filename#$link#ig )
         ) {
         # this attachment is referenced by the html
         ${${$r_attachments}[$i]}{referencecount}++;
      }
   }
   return($html);
}

# this routine chnage mailto: into webmail composemail function
# to make it works with base directive, we use full url
# to make it compatible with undecoded base64 block, 
# we put new url into a seperate line
sub html4mailto {
   my ($html, $scripturl, $scriptparm)=@_;
   my $protocol=get_protocol();
   $html =~ s/(=\s*"?)mailto:\s?([^\s]*?)\s?("?\s*\>)/$1\n$protocol:\/\/$ENV{'HTTP_HOST'}$scripturl\?$scriptparm&amp;to=$2\n$3/ig;
   return($html);
}

sub html2table {
   my $html=$_[0];

   $html =~ s#<!doctype[^\<\>]*?\>##i;
   $html =~ s#\<html[^\>]*?\>##i;
   $html =~ s#\</html\>##i;
   $html =~ s#\<head\>##i;
   $html =~ s#\</head\>##i;
   $html =~ s#\<meta[^\<\>]*?\>##gi;
   $html =~ s#\<body([^\<\>]*?)\>#\<table width=100% border=0 cellpadding=2 cellspacing=0 $1\>\<tr\>\<td\>#i;
   $html =~ s#\</body\>#\</td\>\</tr\>\</table\>#i;

   $html =~ s#\<!--.*?--\>##ges;
   $html =~ s#\<style[^\<\>]*?\>#\n\<!-- style begin\n#gi;
   $html =~ s#\</style\>#\nstyle end --\>\n#gi;
   $html =~ s#\<[^\<\>]*?stylesheet[^\<\>]*?\>##gi;
   $html =~ s#(\<div[^\<\>]*?)position\s*:\s*absolute\s*;([^\<\>]*?\>)#$1$2#gi;

   return($html);
}

sub html2text {
   my $t=$_[0];

   $t=~s!\s+! !g;
   $t=~s|<style>.*?</style>||isg;
   $t=~s|<script>.*?</script>||isg;

   $t=~s!<title[^\<\>]*?>!\n\n!ig;
   $t=~s!</title>!\n\n!ig;
   $t=~s!<br>!\n!ig;
   $t=~s!<hr[^\<\>]*?>!\n-----------------------------------------------------------------------\n!ig;

   $t=~s!<p>\s?</p>!\n\n!ig; 
   $t=~s!<p>!\n\n!ig; 
   $t=~s!</p>!\n\n!ig;

   $t=~s!<th[^\<\>]*?>!\n!ig;
   $t=~s!</th>! !ig;
   $t=~s!<tr[^\<\>]*?>!\n!ig;
   $t=~s!</tr>! !ig;
   $t=~s!<td[^\<\>]*?>! !ig;
   $t=~s!</td>! !ig;

   $t=~s!<--.*?-->!!isg;

   $t=~s!<[^\<\>]*?>!!gsm;

   $t=~s!&nbsp;! !g;
   $t=~s!&lt;!<!g;
   $t=~s!&gt;!>!g;
   $t=~s!&amp;!&!g;
   $t=~s!&quot;!\"!g;
   $t=~s!&#8364;!�!g;	# Euro symbo 

   $t=~s!\n\n\s+!\n\n!g;

   return($t);
}

sub text2html {
   my $t=$_[0];

   $t=~s/&/ESCAPE_AMP/g;

   $t=~s!�!&#8364;!g;	# Euro symbo 
   $t=~s/\"/ &quot;/g;
   $t=~s/</ &lt;/g;
   $t=~s/>/ &gt;/g;

   $t=~s/ {2}/ &nbsp;/g;
   $t=~s/\t/ &nbsp;&nbsp;&nbsp;&nbsp;/g;
   $t=~s/\n/<BR>\n/g;

   foreach (qw(http https ftp nntp news gopher telnet)) {
      $t=~s!($_://[\w\d\-\.]+?/?[^\s<>]*[\w/])([\b|\n| ]*)!<a href="$1" target="_blank">$1</A>$2!gs;
   }
   $t=~s!([\b|\n| ]+)(www\.[\w\d\-\.]+\.[\w\d\-]{2,3})([\b|\n| ]*)!$1<a href="http://$2" target="_blank">$2</a>$3!gs;

   # remove the blank inserted just now
   $t=~s/ (&quot;|&lt;|&gt;)/$1/g;
   $t=~s/ESCAPE_AMP/&amp;/g;

   return($t);
}

sub str2html {
   my $s=$_[0];

   $s=~s/&/&amp;/g;
   $s=~s/\"/&quot;/g;
   $s=~s/</&lt;/g;
   $s=~s/>/&gt;/g;
   return($s);
}

######################## END HTML related ##############################

#################### SHIFTBLOCK ####################
sub shiftblock {
   my ($fh, $start, $size, $movement)=@_;
   my ($oldoffset, $movestart, $left, $buff);

   return if ($movement == 0 );

   $oldoffset=tell($fh);
   $left=$size;
   if ( $movement >0 ) {
      while ($left>0) {
         if ($left>=32768) {
             $movestart=$start+$left-32768;
             seek($fh, $movestart, 0);
             read($fh, $buff, 32768);
             seek($fh, $movestart+$movement, 0);
             print $fh $buff;
             $left=$left-32768;
         } else {
             $movestart=$start;
             seek($fh, $movestart, 0);
             read($fh, $buff, $left);
             seek($fh, $movestart+$movement, 0);
             print $fh $buff;
             $left=0;
         }
      }

   } elsif ( $movement <0 ) {
      while ($left>0) {
         if ($left>=32768) {
             $movestart=$start+$size-$left;
             seek($fh, $movestart, 0);
             read($fh, $buff, 32768);
             seek($fh, $movestart+$movement, 0);
             print $fh $buff;
             $left=$left-32768;
         } else {
             $movestart=$start+$size-$left;
             seek($fh, $movestart, 0);
             read($fh, $buff, $left);
             seek($fh, $movestart+$movement, 0);
             print $fh $buff;
             $left=0;
         }
      }
   }
   seek($fh, $oldoffset, 0);
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
      return(1);
   } else {
      return(0);
   }
} 
  
#################### END IS_INTERNAL_SUBJECT ###################

#################### DATESERIAL2AGE ###########################
# this routine takes the message date to calc the age of a message
# it is not very precise since it always treats Feb as 28 days
sub dateserial2age  {
   my $dateserial=$_[0];
   my @daybase=(0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);

   $dateserial =~ /^(\d\d\d\d)(\d\d)(\d\d)\d\d\d\d\d\d$/;
   my ($year, $mon, $day) =($1, $2, $3); 

   my ($nowyear,$nowyday) =(localtime())[5,7];
   $nowyear+=1900;
   $nowyday++;

   return(($nowyear-$year)*365+$nowyday-($daybase[$mon]+$day));
}

#################### END DATESERIAL2AGE ###########################

1;
