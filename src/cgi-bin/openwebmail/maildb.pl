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
# 2001/12/11 tung@turtle.ee.ncku.edu.tw
#

use Fcntl qw(:DEFAULT :flock);
use FileHandle;

# CONSTANT, message attribute number
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
   $config{'dbm_ext'}="db";
}

######################### UPDATE_HEADERDB ############################
# this routine indexes the messages in a mailfolder
# and remove those with duplicated messageids
sub update_headerdb {
   my ($headerdb, $folderfile) = @_;
   my (%HDB, %OLDHDB);

   ($headerdb =~ /^(.+)$/) && ($headerdb = $1);		# bypass taint check
   if ( -e "$headerdb$config{'dbm_ext'}" ) {
      my ($metainfo, $allmessages, $internalmessages, $newmessages);

      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%HDB, $headerdb, undef);
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
      filelock("$headerdb.old$config{'dbm_ext'}", LOCK_SH);
      dbmopen(%OLDHDB, "$headerdb.old", undef);
   }

   my $messagenumber = -1;
   my $newmessages = 0;
   my $internalmessages = 0;

   my $inheader = 0;
   my $offset=0;
   my $totalsize=0;

   my @duplicateids=();

   my ($line, $lastline, $lastheader);
   my ($_message_id, $_offset);
   my ($_from, $_to, $_date, $_subject);
   my ($_content_type, $_status, $_messagesize, $_references, $_inreplyto);

   dbmopen(%HDB, $headerdb, 0600);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
   %HDB=();	# ensure the headerdb is empty

   open (FOLDER, $folderfile);

   $lastline="\r";
   while (defined($line = <FOLDER>)) {

      $offset=$totalsize;
      $totalsize += length($line);

      # ex: From tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
      # ex: From tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
      if ( $lastline =~ /^\r*$/ &&
           ($line =~ /^From .*(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+:\d+:\d+)\s+(\d\d+)/ ||
            $line =~ /^From .*(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+:\d+)\s+\w\w\w\s+(\d\d+)/) ) {
         if ($messagenumber != -1) {

            $_from=~s/\@\@/\@\@ /g;
            $_to=~s/\@\@/\@\@ /g;
            $_subject=~s/\@\@/\@\@ /g;
            $_content_type=~s/\@\@/\@\@ /g;
            $_status=~s/\@\@/\@\@ /g;
            $_references=~s/\@\@/\@\@ /g;
            $_inreplyto=~s/\@\@/\@\@ /g;

	    # Include the "in-reply-to" as a reference unless it looks invalid.
	    if ($_inreplyto =~ m/^\s*(\<\S+\>)\s*$/) {
	       $_references .= " " . $1;
	    }
	    $_references =~ s/\s{2,}/ /g;

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
         $_from = $_to = $_date = $_subject = $_message_id = $_content_type ='N/A';
         $_inreplyto = '';
         $_references = '';
         $_status = '';
         $_messagesize = length($line);
         $_date = $line;
         $inheader = 1;
         $lastheader = 'NONE';

      } else {
         $_messagesize += length($line);

         if ($inheader) {
            if ($line =~ /^\r*$/) {
               $inheader = 0;

               ### Convert to readable text from MIME-encoded
               $_from = decode_mimewords($_from);
               $_subject = decode_mimewords($_subject);

               # some dbm(ex:ndbm on solaris) can only has value shorter than 1024 byte, 
               # so we cut $_to to 256 byte to make dbm happy
               if (length($_to) >256) {
                  $_to=substr($_to, 0, 252)."...";
               }

               # extract date from the 'From ' line, it must be in this form
               # From tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
               # From tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
               if ($_date=~/(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+:\d+:\d+)\s+(\d\d+)/ ) {
                  $_date = "$month{$2}/$3/$5 $4";
               } elsif ($_date =~ /^From .*(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+:\d+)\s+\w\w\w\s+(\d\d+)/ ) {
                  $_date = "$month{$2}/$3/$5 $4:00";
               }

               $internalmessages++ if (is_internal_subject($_subject));
               $newmessages++ if ($_status !~ /r/i);

               # check if msg info recorded in old headerdb, we can seek to msg end quickly
               if (defined($OLDHDB{$_message_id}) ) {
                  my $oldmsgsize=(split(/@@@/, $OLDHDB{$_message_id}))[$_SIZE];
                  my $buff='';

                  seek(FOLDER, $_offset+$oldmsgsize, 0);
                  read(FOLDER, $buff, 6);
                  
                  if ( $buff=~/^From /) { # ya, msg end is found!
                     $_messagesize=$oldmsgsize;
                     $totalsize=$_offset+$_messagesize;
                  }  

                  seek(FOLDER, $totalsize, 0);
               }

            } elsif ($line =~ /^\s/) {
               if    ($lastheader eq 'FROM') { $_from .= $line }
               elsif ($lastheader eq 'SUBJ') { $_subject .= $line }
               elsif ($lastheader eq 'TO') { $_to .= $line }
               elsif ($lastheader eq 'MESSID') { 
                  $line =~ s/^\s+//;
                  chomp($line);
                  $_message_id .= $line;
               }
	       elsif ($lastheader eq 'REFERENCES') { $_references .= "$line "; }
	       elsif ($lastheader eq 'INREPLYTO') { $_inreplyto .= "$line "; }
            } elsif ($line =~ /^from:\s+(.+)$/ig) {
               $_from = $1;
               $lastheader = 'FROM';
            } elsif ($line =~ /^to:\s+(.+)$/ig) {
               $_to = $1;
               $lastheader = 'TO';
            } elsif ($line =~ /^subject:\s+(.+)$/ig) {
               $_subject = $1;
               $lastheader = 'SUBJ';
            } elsif ($line =~ /^message-id:\s+(.*)$/ig) {
               $_message_id = $1;
               $lastheader = 'MESSID';
	    } elsif ($line =~ /^in-reply-to:\s+(.+)$/ig) {
               $_inreplyto .= $1 . " ";
               $lastheader = 'INREPLYTO';
	    } elsif ($line =~ /^references:\s+(.+)$/ig) {
               $_references .= $1 . " ";
               $lastheader = 'REFERENCES';
            } elsif ($line =~ /^content-type:\s+(.+)$/ig) {
               $_content_type = $1;
               $lastheader = 'NONE';
            } elsif ($line =~ /^status:\s+(.+)$/i) {
               $_status .= $1;
               $_status =~ s/\s//g;	# remove blanks
               $lastheader = 'NONE';
            } elsif ($line =~ /^x-status:\s+(.+)$/i) {
               $_status .= $1;
               $_status =~ s/\s//g;	# remove blanks
               $lastheader = 'NONE';
            } else {
               $lastheader = 'NONE';
            }
         }
      }

      $lastline=$line;
   }

   # Catch the last message, since there won't be a From: to trigger the capture
   if ($messagenumber != -1) {

      $_from=~s/\@\@/\@\@ /g;
      $_to=~s/\@\@/\@\@ /g;
      $_subject=~s/\@\@/\@\@ /g;
      $_content_type=~s/\@\@/\@\@ /g;
      $_status=~s/\@\@/\@\@ /g;
      $_references=~s/\@\@/\@\@ /g;
      $_inreplyto=~s/\@\@/\@\@ /g;

      # Include the "in-reply-to" as a reference unless it looks invalid.
      if ($_inreplyto =~ m/^\s*(\<\S+\>)\s*$/) {
         $_references .= " " . $1;
      }
      $_references =~ s/\s{2,}/ /g;

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
   dbmopen(%HDB, $headerdb, undef);

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
      $sort='subject'; $rev=0;
   } elsif ( $sort eq 'subject_rev' ) {
      $sort='subject'; $rev=1;
   } elsif ( $sort eq 'thread' ) {
      $sort='thread'; $rev=1;
   } elsif ( $sort eq 'thread_rev' ) {
      $sort='thread'; $rev=0;
   } else {
      $sort='status'; $rev=0;
   }

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
      ($cachefile =~ /^(.+)$/) && ($cachefile = $1);		# bypass taint check
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
         ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_subject($headerdb, $ignore_internal);
      } elsif ( $sort eq 'status' ) {
         ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_status($headerdb, $ignore_internal);
      } elsif ( $sort eq 'thread' ) {
         ($totalsize, $new, $r_messageids, $r_messagedepths)=get_info_messageids_sorted_by_thread($headerdb, $ignore_internal);
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
   my (%HDB, @attr, %datestr, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
         $datestr{$key}=datestr($attr[$_DATE]);
      }
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   @messageids=sort { $datestr{$b}<=>$datestr{$a} } keys(%datestr);
   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_from {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %from, %datestr, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
         $from{$key}=$attr[$_FROM];
         $datestr{$key}=datestr($attr[$_DATE]);
      }
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   @messageids=sort {
                    lc($from{$a}) cmp lc($from{$b}) or $datestr{$b} <=> $datestr{$a};
                    } keys(%from);
   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_to {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %to, %datestr, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
         $to{$key}=$attr[$_TO];
         $datestr{$key}=datestr($attr[$_DATE]);
      }
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   @messageids=sort {
                    lc($to{$a}) cmp lc($to{$b}) or $datestr{$b} <=> $datestr{$a};
                    } keys(%to);
   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_subject {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %subject, %datestr, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
         $subject{$key}=lc($attr[$_SUBJECT]);
         # try to group thread and related followup together
         $subject{$key}=~s/\[\d+\]//g;	
         $subject{$key}=~s/[\[\]\s]//g;	
         $subject{$key}=~s/^(Re:)*//ig;	
         $datestr{$key}=datestr($attr[$_DATE]);
      }
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   @messageids=sort { if ($subject{$b} eq $subject {a}) {$datestr{$b} <=> $datestr{$a};} else { $subject{$b} cmp $subject{$a};} } keys(%datestr);

   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_thread {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %datestr, $key, $data);
   my ($totalsize, $new)=(0,0);
   my %subject;
   my (@message_ids, @message_depths, %threads, @thread_pre_roots, @thread_roots, %thread_children);

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
         $datestr{$key}=datestr($attr[$_DATE]);
	 $threads{$key}=join(" ", reverse(split(/ /, $attr[$_REFERENCES])));
         $subject{$key}=lc($attr[$_SUBJECT]);
         $subject{$key}=~s/\[\d+\]//g;	
         $subject{$key}=~s/[\[\]\s]//g;	
         $subject{$key}=~s/^(Re:)*//ig;	
      }
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   # In the first pass we need to make sure each message has a valid
   # parent message.  We also track which messages won't have parent
   # messages (@thread_roots).
   foreach my $key (keys %threads) {
      my @parents = split(/ /, $threads{$key});
      my $parent = "N/A";
      foreach my $p (@parents) {
         if ($threads{$p}) {
 	    $parent = $p;
	    last;
         }
      }
      $threads{$key} = $parent;
      $thread_children{$key} = ();
      push @thread_pre_roots, $key if ($threads{$key} eq "N/A");
   }

   # Some threads will be completely disconnected, but the title is the same
   # so we should connect them with the earliest article by the same title.
   @thread_pre_roots = sort { my $i = $subject{$a} cmp $subject{$b}; if ($i==0) {$datestr{$a} <=> $datestr{$b};} else { $i; } } @thread_pre_roots;
   my $previous_id = "";
   foreach my $id (@thread_pre_roots) {
      if ($subject{$previous_id} eq $subject{$id}) {
         $threads{$id} = $previous_id;
         $thread_children{$id} = ();
      } else {
         push @thread_roots, $id;
         $previous_id = $id;
      }
   }

   # In the second pass we need to determine which children get
   # associated with which parent.  We do this so we can traverse
   # the thread tree from the top down.
   foreach my $child (keys %threads) {
      push @{$thread_children{$threads{$child}}}, $child if ($threads{$child});
   }

   # Finally, we recursively traverse the tree.
   sub recursively_thread {
      my $node = $_[0];
      my $depth = $_[1];
      push @message_ids, $node;
      push @message_depths, $depth;
      my @children = sort { $datestr{$a} <=> $datestr{$b}; } @{$thread_children{$node}};
      foreach my $child (@children) {
         recursively_thread ($child, $depth+1);
      }
   }

   @thread_roots = sort { $datestr{$a} <=> $datestr{$b}; } @thread_roots;
   foreach my $key (@thread_roots) {
      recursively_thread ($key, 0);
   }

   return($totalsize, $new, \@message_ids, \@message_depths);
}

sub get_info_messageids_sorted_by_size {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %size, %datestr, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
         $datestr{$key}=datestr($attr[$_DATE]);
      }
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   @messageids=sort {
                    $size{$b} <=> $size{$a} or $datestr{$b} <=> $datestr{$a};
                    } keys(%size);
   return($totalsize, $new, \@messageids);
}

sub get_info_messageids_sorted_by_status {
   my ($headerdb, $ignore_internal)=@_;
   my (%HDB, @attr, %status, %datestr, $key, $data);
   my ($totalsize, $new)=(0,0);
   my @messageids;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
            $status{$key}=0;
         } else {
            $status{$key}=1;
         }
         $datestr{$key}=datestr($attr[$_DATE]);
      }
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   @messageids=sort { 
                    $status{$b} <=> $status{$a} or $datestr{$b} <=> $datestr{$a};
                    } keys(%status);
   return($totalsize, $new, \@messageids);
}


############### END GET_MESSAGEIDS_SORTED_BY_...  #################

####################### GET_MESSAGE_.... ###########################
sub get_message_attributes {
   my ($messageid, $headerdb)=@_;
   my (%HDB, @attr);

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
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
   my ($messageoldstatus, $notificationto)=('','');
   my $folderhandle=FileHandle->new();
   my %HDB;

   update_headerdb($headerdb, $folderfile);

   my @messageids=get_messageids_sorted_by_offset($headerdb);
   my $movement;
   my @attr;
   my $i;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
   dbmopen (%HDB, $headerdb, 600);

   for ($i=0; $i<=$#messageids; $i++) {
      if ($messageids[$i] eq $messageid) {
         @attr=split(/@@@/, $HDB{$messageid});

         $messageoldstatus=$attr[$_STATUS];
         last if ($messageoldstatus=~/$status/i);

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
         $headerlen=length($header);
         $headerend=$messagestart+$headerlen;

         # get notification-to 
         if ($header=~/^Disposition-Notification-To:\s?(.*?)$/im ) {
            $notificationto=$1;
         } else {
            $notificationto='';
         }


         # update status
         my $status_update = "";
         $status_update .= "R" if ($status =~ m/r/i || $messageoldstatus =~ m/r/i); # Read
         $status_update .= "O" if ($status =~ m/o/i || $messageoldstatus =~ m/o/i); # Old
         if ($status_update ne "") {
            if (!($header =~ s/^status:.*\n/Status: $status_update\n/im)) {
               $header .= "Status: $status_update\n";
            }
         }

	 # update x-status
         $status_update = "";
         $status_update .= "A" if ($status =~ m/a/i || $messageoldstatus =~ m/a/i); # Answered
         $status_update .= "D" if ($status =~ m/d/i || $messageoldstatus =~ m/d/i); # Deleted
         $status_update .= "I" if ($status =~ m/i/i || $messageoldstatus =~ m/i/i); # Important
         if ($status_update ne "") {
            if (!($header =~ s/^x-status:.*\n/X-Status: $status_update\n/im)) {
               $header .= "X-Status: $status_update\n";
            }
         }
         $header="From $header" if ($header !~ /^From /);


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
         }
         $attr[$_SIZE]=$messagesize+$movement;
         $attr[$_STATUS]=$status;
         $HDB{$messageid}=join('@@@', @attr);

         last;
      }
   }
   $i++;

   # if status is changed
   if ($messageoldstatus!~/$status/i) {
      #  change offset attr for messages after the above one 
      for (;$i<=$#messageids; $i++) {
         @attr=split(/@@@/, $HDB{$messageids[$i]});
         $attr[$_OFFSET]+=$movement;
         $HDB{$messageids[$i]}=join('@@@', @attr);
      }
      # change whole folder info
      $HDB{'METAINFO'}=metainfo($folderfile);
   }

   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   return($messageoldstatus, $notificationto);
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
   my ($messagestart, $messagesize, @attr);
   my $counted=0;
   
   filelock("$srcdb$config{'dbm_ext'}", LOCK_EX);
   dbmopen (%HDB, $srcdb, 600);

   if ($op eq "move" || $op eq "copy") {
      filelock("$dstdb$config{'dbm_ext'}", LOCK_EX);
      dbmopen (%HDB2, "$dstdb", 600);
   }

   $blockstart=$blockend=$writepointer=0;

   for (my $i=0; $i<=$#allmessageids; $i++) {
      @attr=split(/@@@/, $HDB{$allmessageids[$i]});
      $messagestart=$attr[$_OFFSET];
      $messagesize=$attr[$_SIZE];

      if ($messageids =~ /^\Q$allmessageids[$i]\E$/m) {	# msg to be operated
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
            my ($left, $buff);

            seek($folderhandle, $attr[$_OFFSET], 0);

            $attr[$_OFFSET]=tell(DEST);

            # copy message from $folderhandle to DEST and append "From " if needed
            $left=$attr[$_SIZE];
            while ($left>0) {
               if ($left>=32768) {
                   read($folderhandle, $buff, 32768);
                   # append 'From ' if 1st buff is not started with 'From '
                   if ($left==$attr[$_SIZE]  && $buff!~/^From /) {
                      print DEST "From ";
                      $attr[$_SIZE]+=length("From ");
                   }
                   print DEST $buff;
                   $left=$left-32768;
               } else {
                   read($folderhandle, $buff, $left);
                   # append 'From ' if 1st buff is not started with 'From '
                   if ($left==$attr[$_SIZE]  && $buff!~/^From /) {
                      print DEST "From ";
                      $attr[$_SIZE]+=length("From ");
                   }
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
   dbmopen (%HDB, $headerdb, undef);
   foreach (@allmessageids) {
      my @attr = split(/@@@/, $HDB{$_});
      push(@agedids, $_) if (dateage($attr[$_DATE])>=$age);
   }
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

   return(operate_message_with_ids('delete', \@agedids, $folderfile, $headerdb));
}

################### END DELETE_MESSAGE_BY_AGE #####################

####################### PARSE_.... related ###########################
# Handle "message/rfc822,multipart,uuencode inside message/rfc822" encapsulatio 
#
# Note: These parse_... routine are designed for CGI program !
#       When calling parse_... with no $searid, these routine assume
#       it is CGI in returning html text page or in content search,
#       so contents of nont-text-based attachment wont be returned!
#       When calling parse_... with a nodeid as searchid, these routine assume
#       it is CGI in requesting one specific non-text-based attachment,
#       one the attachment whose nodeid matches the searchid will be returned
#       When calling parse_... with searchid="all", these routine will return
#       all attachments. This is intended to be used in message forwording.

sub parse_rfc822block {
   my ($r_block, $nodeid, $searchid)=@_;
   my @attachments=();
   my ($headerlen, $header, $body, $contenttype, $encoding);

   $nodeid=0 unless defined $nodeid;
   $headerlen=index(${$r_block},  "\n\n");
   $header=substr(${$r_block}, 0, $headerlen);
   ($contenttype, $encoding)=get_contenttype_encoding_from_header($header);

   if ($contenttype =~ /^multipart/i) {
      my $boundary = $contenttype;
      my $subtype = $contenttype;
      my $boundarylen;
      my ($bodystart, $boundarystart, $nextboundarystart, $attblockstart);

      $boundary =~ s/.*boundary\s?=\s?"?([^"]+)"?.*$/$1/i;
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
               last;	# attblock after this is not he one to look for...
            }
            $boundarystart=$nextboundarystart;
            $attblockstart=$boundarystart+$boundarylen;
         } else {
            # abnormal attblock, last one?
            if ( $searchid eq "" || $searchid eq "all" || 
                 $searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/ ) {
               my $r_attachments2=parse_attblock($r_block, $attblockstart, length(${$r_block})-$attblockstart ,$subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            }
            last;
         }

         $i++;
      }
      return($header, $body, \@attachments);

   } elsif ($contenttype =~ /^message/i ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         $body=substr(${$r_block}, $headerlen+2);
         my ($header2, $body2, $r_attachments2)=parse_rfc822block(\$body, "$nodeid-0", $searchid);
         if ( $searchid eq "" || $searchid eq "all" || $searchid eq $nodeid ) {
            $header2 = decode_mimewords($header2);
            my $temphtml="$header2\n\n$body2";
            push(@attachments, make_attachment("","", "",\$temphtml, length($temphtml),
   		$encoding,"message/rfc822", "inline; filename=Unknown.msg","","", $nodeid) );
         }
         push (@attachments, @{$r_attachments2});
      }
      $body=''; # zero the body since it becomes to header2, body2 and r_attachment2
      return($header, $body, \@attachments);

   } elsif ( ($contenttype eq 'N/A') || ($contenttype =~ /^text\/plain/i) ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid-0/ ) {
         $body=substr(${$r_block}, $headerlen+2);
         # Handle uuencode blocks inside a text/plain mail
         if ( $body =~ /\nbegin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n/ims ) {
            my $r_attachments2;
            ($body, $r_attachments2)=parse_uuencode_body($body, "$nodeid-0", $searchid);
            push(@attachments, @{$r_attachments2});
         }
      }
      return($header, $body, \@attachments);

   } elsif ( ($contenttype ne 'N/A') && !($contenttype =~ /^text/i) ) {
      if ( $searchid eq "" || $searchid eq "all" || $searchid eq $nodeid ) {
         $body=substr(${$r_block}, $headerlen+2);
         push(@attachments, make_attachment("","", "",\$body,length($body), 
					$encoding,$contenttype, "","","", $nodeid) );
      }
      return($header, " ", \@attachments);

   } else {
      $body=substr(${$r_block}, $headerlen+2);
      return($header, $body, \@attachments);
   }
}

# Handle "message/rfc822,multipart,uuencode inside multipart" encapsulation.
sub parse_attblock {
   my ($r_buff, $attblockstart, $attblocklen, $subtype, $boundary, $nodeid, $searchid)=@_;
   my @attachments=();
   my ($attheader, $attcontent, $attencoding, $attcontenttype, 
	$attdisposition, $attid, $attlocation);
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
         if    ($lastline eq 'TYPE')     { $attcontenttype .= $_ }
         elsif ($lastline eq 'DISPOSITION') { s/^\s+//; $attdisposition .= $_ } 
         elsif ($lastline eq 'LOCATION') { s/^\s+//; $attlocation .= $_ } 
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

      $boundary =~ s/.*boundary\s?=\s?"?([^"]+)"?.*$/$1/i;
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
			$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation, $nodeid) );
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
               my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $attblocklen-$subattblockstart ,$subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            }
            last;
         }

         $i++;
      }

   } elsif ($attcontenttype =~ /^message/i ) {

      if ( $searchid eq "" || $searchid eq "all" || $searchid=~/^$nodeid/ ) {
         $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+2, $attblocklen-($attheaderlen+2));
         my ($header2, $body2, $r_attachments2)=parse_rfc822block(\$attcontent, "$nodeid-0", $searchid);

         if ( $searchid eq "" || $searchid eq "all" || $searchid eq $nodeid ) {
            $header2 = decode_mimewords($header2);
            my $temphtml="$header2\n\n$body2";
            push(@attachments, make_attachment($subtype,"", $attheader,\$temphtml, length($temphtml),
		$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation, $nodeid) );
         }
         push (@attachments, @{$r_attachments2});
      }

   } elsif ($attcontenttype ne "N/A" ) {

      # the content of an attachment is returned only if
      #  a. the searchid is looking for this attachment (all or a nodeid)
      #  b. this attachment is text based

      if ( ($searchid eq "all") || ($searchid eq $nodeid) ||
           ($searchid eq "" && $attcontenttype=~/^text/i) ) {
         my $attcontentlength=$attblocklen-($attheaderlen+2);
         $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+2, $attcontentlength);
         if ($attcontent !~ /^\s*$/ ) { # if attach contains only \s, discard it 
            push(@attachments, make_attachment($subtype,$boundary, $attheader,\$attcontent, $attcontentlength,
		$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation, $nodeid) );
         }

      # null searchid means CGI is in returning html code or in context searching
      # thus content of an non-text based attachment is no need to be returned

      } elsif ( $searchid eq "" && $attcontenttype!~/^text/i) {
         my $attcontentlength=$attblocklen-($attheaderlen+2);
         push(@attachments, make_attachment($subtype,$boundary, $attheader,\"snipped...",$attcontentlength,
		$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation, $nodeid) );
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
         if ($uufilename=~/\.doc$/i) {
            $uutype="application/msword";
         } elsif ($uufilename=~/\.ppt$/i) {
            $uutype="application/x-mspowerpoint";
         } elsif ($uufilename=~/\.xls$/i) {
            $uutype="application/x-msexcel";
         } else {
            $uutype="application/octet-stream";
         }

         # convert and inline uuencode block into an base64 encoded attachment
         my $uuheader=qq|Content-Type: $uutype;\n|.
                      qq|\tname="$uufilename"\n|.
                      qq|Content-Transfer-Encoding: base64\n|.
                      qq|Content-Disposition: attachment;\n|.
                      qq|\tfilename="$uufilename"|;
         $uubody=encode_base64(uudecode($uubody));

         push( @attachments, make_attachment("","", $uuheader,\$uubody, length($uubody),
		"base64",$uutype, "attachment; filename=$uufilename","","", "$nodeid-$i") );
      }
      $i++;
   }

   $body =~ s/\nbegin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n//igms;
   return ($body, \@attachments);
}

sub get_contenttype_encoding_from_header {
   my $header=$_[0];
   my ($contenttype, $encoding) = ('N/A', 'N/A');

   my $lastline = 'NONE';
   foreach (split(/\n/, $header)) {
      if (/^\s/) {
         if ($lastline eq 'TYPE') { $contenttype .= $_ }
         elsif ($lastline eq 'ENCODING') { $encoding .= $_ }
      } elsif (/^content-type:\s+(.+)$/ig) {
         $contenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.+)$/ig) {
         $encoding = $1;
         $lastline = 'ENCODING';
      } else {
         $lastline = 'NONE';
      }
   }
   return($contenttype, $encoding);
}

# subtype and boundary are inherit from parent attblocks,
# they are used to distingush if two attachments are winthin same group
# note: the $r_attcontent is a reference to the contents of an attachment,
#       this routine will save this reference to attachment hash directly.
#       It means the caller must ensures the variable referenced by 
#       $r_attcontent is kept untouched!
sub make_attachment {
   my ($subtype,$boundary, $attheader,$r_attcontent,$attcontentlength, 
	$attencoding,$attcontenttype, $attdisposition,$attid,$attlocation, $nodeid)=@_;
   my $attfilename;
   my %temphash;

   $attfilename = $attcontenttype;
   $attcontenttype =~ s/^(.+);.*/$1/g;
   if ($attfilename =~ s/^.+name\s?[:=]\s?"?([^"]+)"?.*$/$1/ig) {
      $attfilename = decode_mimewords($attfilename);
   } elsif ($attfilename =~ s/^.+name\*[:=]\s?"?[\w]+''([^"]+)"?.*$/$1/ig) {
      $attfilename = unescapeURL($attfilename);
   } else {
      $attfilename = $attdisposition || '';
      if ($attfilename =~ s/^.+filename\s?=\s?"?([^"]+)"?.*$/$1/ig) {
         $attfilename = decode_mimewords($attfilename);
      } elsif ($attfilename =~ s/^.+filename\*=\s?"?[\w]+''([^"]+)"?.*$/$1/ig) {
         $attfilename = unescapeURL($attfilename);
      } else {
         $attfilename = "Unknown.".contenttype2ext($attcontenttype);
      }
   }
   $attdisposition =~ s/^(.+);.*/$1/g;

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
   $temphash{referencecount} = 0;

   return(\%temphash);
}

sub contenttype2ext {
   my $contenttype=$_[0];
   my ($class, $ext, $dummy)=split(/[\/\s;,]+/, $contenttype);
   
   return("mp3") if ($contenttype=~m!audio/mpeg!i);
   return("ra")  if ($contenttype=~m!audio/x-realaudio!i);

   $ext=~s/^x-//;
   return($ext)  if length($ext) <=4;

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
   dbmopen (%HDB, $headerdb, undef);
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
      ($cachefile =~ /^(.+)$/) && ($cachefile = $1);		# bypass taint check
      open(CACHE, ">$cachefile");
      print CACHE $metainfo, "\n";
      print CACHE $headerdb, "\n";
      print CACHE $keyword, "\n";
      print CACHE $searchtype, "\n";
      print CACHE $ignore_internal, "\n";

      @messageids=get_messageids_sorted_by_offset($headerdb, $folderhandle);

      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%HDB, $headerdb, undef);

      foreach $messageid (@messageids) {
         my (@attr, $block, $header, $body, $r_attachments) ;
         @attr=split(/@@@/, $HDB{$messageid});
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));

         # check subject, from, to, date
         if ( (($searchtype eq 'all' || $searchtype eq 'subject')
                && $attr[$_SUBJECT]=~/$keyword/i) ||
              (($searchtype eq 'all' || $searchtype eq 'from')
                && $attr[$_FROM]=~/$keyword/i) ||
              (($searchtype eq 'all' || $searchtype eq 'to')
                && $attr[$_TO]=~/$keyword/i) ||
              (($searchtype eq 'all' || $searchtype eq 'date')
                && $attr[$_DATE]=~/$keyword/i) ) {
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
            if ( $header =~ /$keyword/im ) {
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
            if ( $attr[$_CONTENT_TYPE] =~ /^text/i ) {	# read all for text/plain. text/html
               if ( $header =~ /content-transfer-encoding:\s+quoted-printable/i) {
                  $body = decode_qp($body);
               } elsif ($header =~ /content-transfer-encoding:\s+base64/i) {
                  $body = decode_base64($body);
               }
               if ( $body =~ /$keyword/im ) {
                  $new++ if ($attr[$_STATUS]!~/r/i);
                  $totalsize+=$attr[$_SIZE];
                  $found{$messageid}=1;
                  next;
               }
            }
            # check attachments
            foreach my $r_attachment (@{$r_attachments}) {
               if ( ${$r_attachment}{contenttype} =~ /^text/i ) {	# read all for text/plain. text/html
                  if ( ${$r_attachment}{encoding} =~ /^quoted-printable/i ) {
                     ${${$r_attachment}{r_content}} = decode_qp( ${${$r_attachment}{r_content}});
                  } elsif ( ${$r_attachment}{encoding} =~ /^base64/i ) {
                     ${${$r_attachment}{r_content}} = decode_base64( ${${$r_attachment}{r_content}});
                  }
                  if ( ${${$r_attachment}{r_content}} =~ /$keyword/im ) {
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
               if ( ${$r_attachment}{filename} =~ /$keyword/im ) {	# read all for text/plain. text/html
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
# since this routine deals with base directive, 
# it must be called first before other html...routines when converting html
sub html4nobase {
   my $html=$_[0];
   my $urlbase; 
   if ( $html =~ m#\<base\s+href\s*=\s*"?(.*?)"?\>#i ) {
      $urlbase=$1;
      $urlbase=~s#/[^/]+$#/#;
   }

   $html =~ s#\<base\s+(.*?)\>##gi;
   if ( ($urlbase ne "") && ($urlbase !~ /^file:/) ) {
      $html =~ s#(\<a\s+href=\s*"?)#$1$urlbase#gi;
      $html =~ s#(src\s*=\s*"?)#$1$urlbase#gi;
      $html =~ s#(background\s*=\s*"?)#$1$urlbase#gi;

      # restore links that should be chnaged by base directive
      $html =~ s#\Q$urlbase\E(http://)#$1#gi;
      $html =~ s#\Q$urlbase\E(https://)#$1#gi;
      $html =~ s#\Q$urlbase\E(ftp://)#$1#gi;
      $html =~ s#\Q$urlbase\E(cid:)#$1#gi;
      $html =~ s#\Q$urlbase\E(mailto:)#$1#gi;
   }

   return($html);
}

# this routine is used to resolve crossreference inside attachments
sub html4attachments {
   my ($html, $r_attachments, $scripturl, $scriptparm)=@_;
   my $i;

   for ($i=0; $i<=$#{$r_attachments}; $i++) {
      my $filename=escapeURL(${${$r_attachments}[$i]}{filename});
      my $link="$scripturl/$filename?$scriptparm&amp;attachment_nodeid=${${$r_attachments}[$i]}{nodeid}&amp;";
      my $cid="cid:"."${${$r_attachments}[$i]}{id}";
      my $loc=${${$r_attachments}[$i]}{location};

      if ( ($loc ne "" && $html =~ s#\Q$loc\E#$link#ig ) ||
           ($cid ne "cid:" && $html =~ s#\Q$cid\E#$link#ig ) ||
           # ugly hack for strange CID     
           ($filename ne "" && $html =~ s#CID:\{[\d\w\-]+\}/$filename#$link#ig )
         ) {
         # this attachment is referenced by the html
         ${${$r_attachments}[$i]}{referencecount}++;
      }
   }
   return($html);
}

# this routine disables the javascript in a html page
# to avoid user being hijacked by some eval programs
my @jsevents=('onAbort', 'onBlur', 'onChange', 'onClick', 'onDblClick', 
              'onDragDrop', 'onError', 'onFocus', 'onKeyDown', 'onKeyPress', 
              'onKeyUp', 'onLoad', 'onMouseDown', 'onMouseMove', 'onMouseOut',
              'onMouseOver', 'onMouseUp', 'onMove', 'onReset', 'onResize', 
              'onSelect', 'onSubmit', 'onUnload');
sub html4disablejs {
   my $html=$_[0];
   my $event;

   foreach $event (@jsevents) {
      $html=~s/$event/_$event/ig;
   }
   $html=~s/<script(.*?)>/<disable_script$1>\n<!--\n/ig;
   $html=~s/<!--\s*<!--/<!--/g;
   $html=~s/<\/script>/\n\/\/-->\n<\/disable_script>/ig;
   $html=~s/\/\/-->\s*\/\/-->/\/\/-->/g;
   $html=~s/<(.*?)javascript:(.*?)>/<$1disable_javascript:$2>/ig;
   
   return($html);
}

# this routine chnage mailto: into webmail composemail function
# to make it works with base directive, we use full url
# to make it compatible with undecoded base64 block, we put new url into a seperate line
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
   $html =~ s#\<[^\<]*?stylesheet[^\>]*?\>##gi;
   $html =~ s#(\<div[^\<]*?)position\s*:\s*absolute\s*;([^\>]*?\>)#$1$2#gi;

   return($html);
}

sub html2txt {
   my $t=$_[0];

   $t=~s!\n! !g;

   $t=~s!<title.*?>!\n\n!ig;
   $t=~s!</title>!\n\n!ig;
   $t=~s!<br>!\n!ig;
   $t=~s!<hr.*?>!\n------------------------------------------------------------\n!ig;

   $t=~s!<p>\s?</p>!\n\n!ig; 
   $t=~s!<p>!\n\n!ig; 
   $t=~s!</p>!\n\n!ig;

   $t=~s!<th.*?>!\n!ig;
   $t=~s!</th>! !ig;
   $t=~s!<tr.*?>!\n!ig;
   $t=~s!</tr>! !ig;
   $t=~s!<td.*?>! !ig;
   $t=~s!</td>! !ig;

   $t=~s!<--.*?-->!!ig;

   $t=~s!<.*?>!!gsm;

   $t=~s!&nbsp;! !g;
   $t=~s!&lt;!<!g;
   $t=~s!&gt;!>!g;
   $t=~s!&amp;!&!g;
   $t=~s!&quot;!\"!g;

   $t=~s!\n\n\s+!\n\n!g;

   return($t);
}

sub text2html {
   my $t=$_[0];

   $t=~s/&/&amp;/g;
   $t=~s/\"/&quot;/g;
   $t=~s/</&lt;/g;
   $t=~s/>/&gt;/g;
   $t=~s/\n/<BR>\n/g;
   $t=~s/ {2}/ &nbsp;/g;
   $t=~s/\t/ &nbsp;&nbsp;&nbsp;&nbsp;/g;
         
   foreach (qw(http https ftp nntp news gopher telnet)) {
      $t=~s/($_:\/\/[\w\.\-]+?\/?[^\s<>]*[\w\/])([\b|\n| ]*)/<A HREF=\"$1\" TARGET=\"_blank\">$1<\/A>$2/gs;
   }
   $t=~s/([\b|\n| ]+)(www\.[-\w\.]+\.[-\w]{2,3})([\b|\n| ]*)/$1<a href=\"http:\/\/$2\" TARGET=\"_blank\">$2<\/a>$3/gs;

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

#################### COPYBLOCK ####################
sub copyblock {
   my ($srchandle, $srcstart, $dsthandle, $dststart, $size)=@_;
   my ($srcoffset, $dstoffset);
   my ($left, $buff);

   return if ($size == 0 );

   $srcoffset=tell($srchandle);
   $dstoffset=tell($dsthandle);

   seek($srchandle, $srcstart, 0);
   seek($dsthandle, $dststart, 0);

   $left=$size;
   while ($left>0) {
      if ($left>=32768) {
          read($srchandle, $buff, 32768);
          print $dsthandle $buff;
          $left=$left-32768;
      } else {
          read($srchandle, $buff, $left);
          print $dsthandle $buff;
          $left=0;
      }
   }

   seek($srchandle, $srcoffset, 0);
   seek($dsthandle, $dstoffset, 0);
   return;
}

################## END COPYBLOCK ##################

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
         if ( ($lastline eq 'FROM') || ($lastline eq 'REPLYTO') ||
              ($lastline eq 'DATE') || ($lastline eq 'SUBJ') ||
              ($lastline eq 'TO') || ($lastline eq 'CC') ) {
            $simpleheader .= $_;
         }
      } elsif (/^</) { 
         $simpleheader .= $_;
         $lastline = 'NONE';
      } elsif (/^from:\s+/ig) {
         $simpleheader .= $_;
         $lastline = 'FROM';
      } elsif (/^reply-to:\s/ig) {
         $simpleheader .= $_;
         $lastline = 'REPLYTO';
      } elsif (/^to:\s+/ig) {
         $simpleheader .= $_;
         $lastline = 'TO';
      } elsif (/^cc:\s+/ig) {
         $simpleheader .= $_;
         $lastline = 'CC';
      } elsif (/^date:\s+/ig) {
         $simpleheader .= $_;
         $lastline = 'DATE';
      } elsif (/^subject:\s+/ig) {
         $simpleheader .= $_;
         $lastline = 'SUBJ';
      } else {
         $lastline = 'NONE';
      }
   }
   return($simpleheader);
}

################### END SIMPLEHEADER ###################

#################### DATESTR ###########################
sub datestr {
   my ($date, $time, $offset) = split(/\s/, $_[0]);
   my @d = split(/\//, $date); 
   my @t = split(/:/, $time);

   if ($d[2]<50) { 
     $d[2]+=2000; 
   } elsif ($d[2]<=1900) {
     $d[2]+=1900;
   }

# sine we store message date with received time of a message:
# if no timezone in date, we assume it is local timezone
# if there is a timezone in date, it must be local timezone
# So we just don't deal with timezone.
#
#   if ($offset ne "") {
#      $offset = $timezones{$offset} unless ($offset =~ /[\+|\-]/);
#      $t[0] -= $offset / 100;
#
#      if ($t[0]<0) {				# hour
#         $t[0]+=24; $d[1]--; 
#         if ($d[1]==0) {				# monthday
#            $d[0]--; $d[1]=$monthday[$d[0]];
#            if ($d[0]==0) {			# month
#               $d[0]=12; $d[2]--; 
#            }
#         }
#      } elsif ($t[0]>=24) {			# hour
#         $t[0]-=24; $d[1]++;
#         if ($d[1]>$monthday[$d[0]]) {		# monthday
#            $d[1]=1; $d[0]++;
#            if ($d[0]>12) {			# month
#               $d[0]=1; $d[2]++;
#            }
#
#         }
#      }
#   }
   return(sprintf("%4d%02d%02d%02d%02d%02d", $d[2],$d[0],$d[1], $t[0],$t[1],$t[2]));
}

#################### END DATESTR ###########################

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

#################### END DATEAGE ###########################
# this routine takes the message date to calc the age of a message
# it is not very precise since it always treats Feb as 28 days
sub dateage  {
   my ($date, $time, $offset) = split(/\s/, $_[0]);
   my @daybase=(0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);

   my ($mon, $day, $year) = split(/\//, $date); 
   if ($year<50) { 
     $year+=2000; 
   } elsif ($year<=1900) {
     $year+=1900;
   }

   my ($nowyear,$nowyday) =(localtime())[5,7];
   $nowyear+=1900;
   $nowyday++;

   return(($nowyear-$year)*365+$nowyday-($daybase[$mon]+$day));
}

#################### END DATEAGE ###########################

1;
