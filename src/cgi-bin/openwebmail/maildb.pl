#
# maildb.pl are functions for mail spool file.
#
# 1. it greatly speeds up the mail spool files access by hash 
#    important info with the perl build in dbm. 
# 2. it can parse mail with unlimited level attachments through 
#    recursive parsing
# 3. it converts uuencoded blocks in message body into baed64-encoded 
#    attachments.
# 4. it supports search on mail spool file and cache the results for 
#    repeated queries.
#
# 2001/04/06 tung@turtle.ee.ncku.edu.tw
#
# IMPORTANT!!!
#
# Functions in this file will do locks for dbm before read/write.
# They doesn't do locks for spoolfile/spoolhandle and relies the 
# caller for that lock.
# Functions with spoolfile/spoolhandle in argument must be inside
# a spool lock session
#
# An global variable $dbm_ext needs to be defined to represent the
# dbm filename extension on your system. 
# ex: use 'db' for FreeBSD and 'dir' for Solaris

use Fcntl qw(:DEFAULT :flock);
use FileHandle;

# CONSTANT, message attribute number
($_OFFSET, $_FROM, $_TO, $_DATE, $_SUBJECT, $_CONTENT_TYPE, $_STATUS, $_SIZE)
 =(0,1,2,3,4,5,6,7);

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

if ( $dbm_ext eq "" ) {
   $dbm_ext="db";
}

######################### UPDATE_HEADERDB ############################

sub update_headerdb {
   my ($headerdb, $spoolfile) = @_;
   my (%HDB, @datearray);

   if ( -e "$headerdb.$dbm_ext" ) {
      my ($metainfo, $allmessages, $newmessages);

      filelock("$headerdb.$dbm_ext", LOCK_SH);
      dbmopen (%HDB, $headerdb, undef);
      $metainfo=$HDB{'METAINFO'};
      $allmessages=$HDB{'ALLMESSAGES'};
      $newmessages=$HDB{'NEWMESSAGES'};
      dbmclose(%HDB);
      filelock("$headerdb.$dbm_ext", LOCK_UN);

      if ( $metainfo ne metainfo($spoolfile) 
        || $allmessages eq "" 
        || $newmessages eq "" ) {
         ($headerdb =~ /^(.+)$/) && ($headerdb = $1);		# bypass taint check
         unlink ("$headerdb.db", "$headerdb.dir","$headerdb.pag");
      }
   }

   if ( !(-e "$headerdb.$dbm_ext") ) {
      open (SPOOL, $spoolfile);
      dbmopen(%HDB, $headerdb, 0600);
      filelock("$headerdb.$dbm_ext", LOCK_EX);

      my $messagenumber = -1;
      my $newmessages = 0;
      my $internalmessages = 0;
      my $lastline;
      my $line;
      my $inheader = 1;
      my $offset=0;
      my $total_size=0;

      my ($_message_id, $_offset);
      my ($_from, $_to, $_date, $_subject);
      my ($_content_type, $_status, $_messagesize);

      %HDB=();	# ensure the header is empty

      while (defined($line = <SPOOL>)) {

         $offset=$total_size;
         $total_size += length($line);

         if ($line =~ /^From /) {

            unless ($messagenumber == -1) {
               if ( $spoolfile=~ m#/SENT#i ) {
### We aren't interested in the sender in this case, but the recipient
### Handling it this way avoids having a separate sort sub for To:.
                  $_from = (split(/,/, $_to))[0];
               }
### Convert to readable text from MIME-encoded
               $_from = decode_mimewords($_from);
               $_subject = decode_mimewords($_subject);

               @datearray = split(/\s+/, $_date);
               shift @datearray;
               shift @datearray;
               shift @datearray;
               $_date = "$month{$datearray[0]}/$datearray[1]/$datearray[3] $datearray[2]";

               if ( $_subject =~ /DON'T DELETE THIS MESSAGE/ ) {
                  $internalmessages++;
               }
               if ( $_status !~ /r/i ) {
                  $newmessages++;
               }

### some dbm(ex:ndbm on solaris) can only has value shorter than 1024 byte, 
### so we cut $_to to 256 byte to make dbm happy
               if (length($_to) >256) {
                  $_to=substr($_to, 0, 252)."...";
               }

               $HDB{$_message_id}=join('@@@', $_offset, $_from, $_to, 
			$_date, $_subject, $_content_type, $_status, $_messagesize);
            }

            $messagenumber++;
            $_offset=$offset;
            $_from = $_to = $_date = $_subject = $_message_id = $_content_type ='N/A';
            $_status = '';
            $_messagesize = length($line);
            $_date = $line;
            $inheader = 1;
            $lastline = 'NONE';

         } else {
            $_messagesize += length($line);

            if ($inheader) {
               if ($line =~ /^\r*$/) {
                  $inheader = 0;
               } elsif ($line =~ /^\s/) {
                  if    ($lastline eq 'FROM') { $_from .= $line }
                  elsif ($lastline eq 'SUBJ') { $_subject .= $line }
                  elsif ($lastline eq 'TO') { $_to .= $line }
                  elsif ($lastline eq 'MESSID') { 
                     $line =~ s/^\s+//;
                     chomp($line);
                     $_message_id .= $line;
                  }
               } elsif ($line =~ /^from:\s+(.+)$/ig) {
                  $_from = $1;
                  $lastline = 'FROM';
               } elsif ($line =~ /^to:\s+(.+)$/ig) {
                  $_to = $1;
                  $lastline = 'TO';
               } elsif ($line =~ /^subject:\s+(.+)$/ig) {
                  $_subject = $1;
                  $lastline = 'SUBJ';
               } elsif ($line =~ /^message-id:\s+(.*)$/ig) {
                  $_message_id = $1;
                  $lastline = 'MESSID';
               } elsif ($line =~ /^content-type:\s+(.+)$/ig) {
                  $_content_type = $1;
                  $lastline = 'NONE';
               } elsif ($line =~ /^status:\s+(.+)$/ig) {
                  $_status = $1;
                  $lastline = 'NONE';
               } else {
                  $lastline = 'NONE';
               }
            }
         }
      }

###### Catch the last message, since there won't be a From: to trigger the capture

      unless ($messagenumber == -1) {
         if ( $spoolfile=~ m#/SENT#i ) {
###### We aren't interested in the sender in this case, but the recipient
###### Handling it this way avoids having a separate sort sub for To:.
            $_from = (split(/,/, $_to))[0];
         }
         $_from = decode_mimewords($_from);
         $_subject = decode_mimewords($_subject);

         @datearray = split(/\s+/, $_date);
         shift @datearray;
         shift @datearray;
         shift @datearray;
         $_date = "$month{$datearray[0]}/$datearray[1]/$datearray[3] $datearray[2]";

         if ( $_subject =~ /DON'T DELETE THIS MESSAGE/ ) {
            $internalmessages++;
         }
         if ( $_status !~ /r/i ) {
            $newmessages++;
         }

### some dbm(ex:ndbm on solaris) can only has value shorter than 1024 byte, 
### so we cut $_to to 256 byte to make dbm happy
         if (length($_to) >256) {
            $_to=substr($_to, 0, 252)."...";
         }

         $HDB{$_message_id}=join('@@@', $_offset, $_from, $_to, 
		$_date, $_subject, $_content_type, $_status, $_messagesize);
      }

      $HDB{'METAINFO'}=metainfo($spoolfile);
      $HDB{'ALLMESSAGES'}=$messagenumber+1-$internalmessages;
      $HDB{'NEWMESSAGES'}=$newmessages;
      filelock("$headerdb.$dbm_ext", LOCK_UN);
      dbmclose(%HDB);
      close (SPOOL);
   }
}

# return a string composed by the modify time & size of a file
sub metainfo {
   my @l;

   if (-e $_[0]) {
      # $dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks
      @l=stat($_[0]);
      return("mtime=$l[9] size=$l[7]");
   } else {
      return("");
   }
}

################## END UPDATEHEADERDB ####################

############### GET_MESSAGEIDS_SORTED_BY_...  #################

sub get_messageids_sorted_by_offset {
   my $headerdb=$_[0];
   my (%HDB, @attr, %offset, $key, $data);

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);

   while ( ($key, $data)=each(%HDB) ) {
      next if ( $key eq 'METAINFO' 
             || $key eq 'NEWMESSAGES' 
             || $key eq 'ALLMESSAGES' 
             || $key eq "" );

      @attr=split( /@@@/, $data );
      $offset{$key}=$attr[$_OFFSET];
   }

   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   return( sort { $offset{$a}<=>$offset{$b} } keys(%offset) );
}

sub get_messageids_sorted {
   my ($headerdb, $sort, $cachefile)=@_;
   my (%HDB, $metainfo, $cache_metainfo, $cache_headerdb, $cache_sort);
   my @messageids;
   my $rev;
   if ( $sort eq 'date' ) {
      $sort='date'; $rev=0;
   } elsif ( $sort eq 'date_rev' ) {
      $sort='date'; $rev=1;
   } elsif ( $sort eq 'sender' ) {
      $sort='sender'; $rev=0;
   } elsif ( $sort eq 'sender_rev' ) {
      $sort='sender'; $rev=1;
   } elsif ( $sort eq 'size' ) {
      $sort='size'; $rev=0;
   } elsif ( $sort eq 'size_rev' ) {
      $sort='size'; $rev=1;
   } elsif ( $sort eq 'subject' ) {
      $sort='subject'; $rev=0;
   } elsif ( $sort eq 'subject_rev' ) {
      $sort='subject'; $rev=1;
   } else {
      $sort='status'; $rev=0;
   }

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
   $metainfo=$HDB{'METAINFO'};
   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   filelock($cachefile, LOCK_EX);

   if ( -e $cachefile ) {
      open(CACHE, $cachefile);
      $cache_metainfo=<CACHE>; chomp($cache_metainfo);
      $cache_headerdb=<CACHE>; chomp($cache_headerdb);
      $cache_sort=<CACHE>;     chomp($cache_sort);
      close(CACHE);
   }

   if ( $cache_metainfo ne $metainfo || $cache_headerdb ne $headerdb ||
        $cache_sort ne $sort ) {
      ($cachefile =~ /^(.+)$/) && ($cachefile = $1);		# bypass taint check
      open(CACHE, ">$cachefile");
      print CACHE $metainfo, "\n", $headerdb, "\n", $sort, "\n";
      if ( $sort eq 'date' ) {
         @messageids =get_messageids_sorted_by_date($headerdb);
      } elsif ( $sort eq 'sender' ) {
         @messageids =get_messageids_sorted_by_from($headerdb);
      } elsif ( $sort eq 'size' ) {
         @messageids =get_messageids_sorted_by_size($headerdb);
      } elsif ( $sort eq 'subject' ) {
         @messageids =get_messageids_sorted_by_subject($headerdb);
      } elsif ( $sort eq 'status' ) {
         @messageids =get_messageids_sorted_by_status($headerdb);
      }
      print CACHE join("\n", @messageids);
      close(CACHE);

   } else {
      open(CACHE, $cachefile);
      $_=<CACHE>; 
      $_=<CACHE>;
      $_=<CACHE>;
      while (<CACHE>) {
         chomp; push (@messageids, $_);
      }
      close(CACHE);
   }

   filelock($cachefile, LOCK_UN);

   if ($rev) {
      return(reverse @messageids);
   } else {
      return(@messageids);
   }
}

sub get_messageids_sorted_by_date {
   my $headerdb=$_[0];
   my (%HDB, @attr, %datestr, $key, $data);

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);

   while ( ($key, $data)=each(%HDB) ) {
      next if ( $key eq 'METAINFO' 
             || $key eq 'NEWMESSAGES' 
             || $key eq 'ALLMESSAGES' 
             || $key eq "" );

      @attr=split( /@@@/, $data );
      $datestr{$key}=datestr($attr[$_DATE]);
   }

   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   return( sort { $datestr{$b}<=>$datestr{$a} } keys(%datestr) );
}

sub get_messageids_sorted_by_from {
   my $headerdb=$_[0];
   my (%HDB, @attr, %from, %datestr, $key, $data);

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);

   while ( ($key, $data)=each(%HDB) ) {
      next if ( $key eq 'METAINFO' 
             || $key eq 'NEWMESSAGES' 
             || $key eq 'ALLMESSAGES' 
             || $key eq "" );

      @attr=split( /@@@/, $data );
      $from{$key}=$attr[$_FROM];
      $datestr{$key}=datestr($attr[$_DATE]);
   }

   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   return( sort {
                lc($from{$a}) cmp lc($from{$b}) or $datestr{$b} <=> $datestr{$a};
                } keys(%from) );
}

sub get_messageids_sorted_by_subject {
   my $headerdb=$_[0];
   my (%HDB, @attr, %subject, %datestr, $key, $data);

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);

   while ( ($key, $data)=each(%HDB) ) {
      next if ( $key eq 'METAINFO' 
             || $key eq 'NEWMESSAGES' 
             || $key eq 'ALLMESSAGES' 
             || $key eq "" );

      @attr=split( /@@@/, $data );
      $subject{$key}=$attr[$_SUBJECT];
      $datestr{$key}=datestr($attr[$_DATE]);
   }

   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   return( sort {
                lc($subject{$a}) cmp lc($subject{$b}) or $datestr{$b} <=> $datestr{$a};
                } keys(%subject) );
}

sub get_messageids_sorted_by_size {
   my $headerdb=$_[0];
   my (%HDB, @attr, %size, %datestr, $key, $data);

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);

   while ( ($key, $data)=each(%HDB) ) {
      next if ( $key eq 'METAINFO' 
             || $key eq 'NEWMESSAGES' 
             || $key eq 'ALLMESSAGES' 
             || $key eq "" );

      @attr=split( /@@@/, $data );
      $size{$key}=$attr[$_SIZE];
      $datestr{$key}=datestr($attr[$_DATE]);
   }

   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   return( sort {
                $size{$b} <=> $size{$a} or $datestr{$b} <=> $datestr{$a};
                } keys(%size) );
}

sub get_messageids_sorted_by_status {
   my $headerdb=$_[0];
   my (%HDB, @attr, %status, %datestr, $key, $data);

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);

   while ( ($key, $data)=each(%HDB) ) {
      next if ( $key eq 'METAINFO' 
             || $key eq 'NEWMESSAGES' 
             || $key eq 'ALLMESSAGES' 
             || $key eq "" );

      @attr=split( /@@@/, $data );
      if ($attr[$_STATUS]=~/r/i) {
         $status{$key}=0;
      } else {
         $status{$key}=1;
      }
      $datestr{$key}=datestr($attr[$_DATE]);
   }

   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   return( sort { 
                $status{$b} <=> $status{$a} or $datestr{$b} <=> $datestr{$a};
                } keys(%status) );
}


############### END GET_MESSAGEIDS_SORTED_BY_...  #################

####################### GET_MESSAGE_.... ###########################

sub get_message_attributes {
   my ($messageid, $headerdb)=@_;
   my (%HDB, @attr);

   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen(%HDB, $headerdb, undef);
   @attr=split(/@@@/, $HDB{$messageid} );
   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);
   return(@attr);
}


sub get_message_block {
   my ($messageid, $headerdb, $spoolhandle)=@_;
   my (@attr, $buff);

   $buff="";
   @attr=get_message_attributes($messageid, $headerdb);
   return if ($#attr<0);   

   my $oldoffset=tell($spoolhandle);
   seek($spoolhandle, $attr[$_OFFSET], 0);
   read($spoolhandle, $buff, $attr[$_SIZE]);
   seek($spoolhandle, $oldoffset, 0);

   return(\$buff);
}

###################### END GET_MESSAGE_.... ########################

####################### PARSE_.... related ###########################
# Handle "message/rfc822,multipart,uuencode inside message/rfc822" encapsulatio 
#
# Note: These parse_... routine are designed for CGI program !
#       When calling parse_... with no $searid, these routine assume
#       it is CGI in returning html text page or in content search,
#       so contents of nont-text-based attachment wont be returned!
#       When calling parse_... with a searchid, these routine assume
#       it is CGI in requesting one specific non-text-based attachment,
#       one the attachment whose nodeid matches the searchid will be returned

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

      $boundary =~ s/.*boundary\s?="?([^"]+)"?.*$/$1/i;
      $subtype =~ s/^multipart\/(.*?)[;\s].*$/$1/i;
      $boundarylen=length($boundary);

      $bodystart=$headerlen+2;
      
      $boundarystart=index(${$r_block}, "--$boundary", $bodystart);
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
         while ( substr(${$r_block}, $attblockstart, 1) eq "\n" ) {
            $attblockstart++;
         }

         $nextboundarystart=index(${$r_block}, "--$boundary", $attblockstart);
         if ($nextboundarystart > $attblockstart) {
            if ( $searchid eq "") {
               # attblock handling
               my $r_attachments2=parse_attblock($r_block, $attblockstart, $nextboundarystart-$attblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            } elsif ($searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/) {
               # attblock handling
               my $r_attachments2=parse_attblock($r_block, $attblockstart, $nextboundarystart-$attblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
               last;	# attblock after this is not he one to look for...
            }
            $boundarystart=$nextboundarystart;
            $attblockstart=$boundarystart+$boundarylen;
         } else {
            # attblock handling
            if ( $searchid eq "" || $searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/ ) {
               my $r_attachments2=parse_attblock($r_block, $attblockstart, length(${$r_block})-$attblockstart ,$subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            }
            last;
         }

         $i++;
      }
      return($header, $body, \@attachments);

   } elsif ($contenttype =~ /^message/i ) {
      if ( $searchid eq "" || $searchid=~/^$nodeid-0/ ) {
         $body=substr(${$r_block}, $headerlen+2);
         my ($header2, $body2, $r_attachments2)=parse_rfc822block(\$body, "$nodeid-0", $searchid);

         if ( $searchid eq "" || $searchid eq $nodeid ) {
            $header2 = decode_mimewords($header2);

            my $temphtml=headerbody2html($header2, $body2);
            push(@attachments, make_attachment("","", "",\$temphtml, length($temphtml),
   		$encoding,"text/html", "inline; filename=Unknown.msg","","", $nodeid) );
         }
         push (@attachments, @{$r_attachments2});
      }
      return($header, $body, \@attachments);

   } elsif ( ($contenttype eq 'N/A') || ($contenttype =~ /^text\/plain/i) ) {
      if ( $searchid eq "" || $searchid=~/^$nodeid-0/ ) {
         $body=substr(${$r_block}, $headerlen+2);
         # Handle uuencode blocks inside a text/plain mail
         if ( $body =~ /\n\nbegin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n/ims ) {
            my $r_attachments2;
            ($body, $r_attachments2)=parse_uuencode_body($body, "$nodeid-0", $searchid);
            push(@attachments, @{$r_attachments2});
         }
      }
      return($header, $body, \@attachments);

   } elsif ( ($contenttype ne 'N/A') && !($contenttype =~ /^text/i) ) {
      if ( $searchid eq "" || $searchid eq $nodeid ) {
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

   return if (/^\-\-\n/);

   $attheaderlen=index(${$r_buff},  "\n\n", $attblockstart) - $attblockstart;
   $attheader=substr(${$r_buff}, $attblockstart, $attheaderlen);
   $attencoding=$attcontenttype='N/A';

   my $lastline='NONE';
   foreach (split(/\n/, $attheader)) {
      if (/^\s/) {
         if ($lastline eq 'TYPE') { $attcontenttype .= $_ }
      } elsif (/^content-type:\s+(.+)$/ig) {
         $attcontenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.+)$/ig) {
         $attencoding = $1;
         $lastline = 'NONE';
      } elsif (/^content-disposition:\s+(.+)$/ig) {
         $attdisposition = $1;
         $lastline = 'NONE';
      } elsif (/^content-id:\s+(.+)$/ig) {
         $attid = $1; 
         $attid =~ s/^\<(.+)\>$/$1/;
         $lastline = 'NONE';
      } elsif (/^content-location:\s+(.+)$/ig) {
         $attlocation = $1;
         $lastline = 'NONE';
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

      $boundary =~ s/.*boundary\s?="?([^"]+)"?.*$/$1/i;
      $subtype =~ s/^multipart\/(.*?)[;\s].*$/$1/i;
      $boundarylen=length($boundary);
      
      $boundarystart=index(${$r_buff}, "--$boundary", $attblockstart);
      if ($boundarystart < $attblockstart) {
          return(\());
      }

      my $i=0;
      $subattblockstart=$boundarystart+$boundarylen;
      while ( substr(${$r_buff}, $subattblockstart, 2) ne "--") {
         # skip \n after boundary
         while ( substr(${$r_buff}, $subattblockstart, 1) eq "\n" ) {
            $subattblockstart++;
         }

         $nextboundarystart=index(${$r_buff}, "--$boundary", $subattblockstart);
         if ($nextboundarystart > $subattblockstart) {
            if ( $searchid eq "") {
               # attblock handling
               my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $nextboundarystart-$subattblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            } elsif ( $searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/ ) {
               # attblock handling
               my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $nextboundarystart-$subattblockstart, $subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
               last;	# attblock after this is not the one to look for...
            }
            $boundarystart=$nextboundarystart;
            $subattblockstart=$boundarystart+$boundarylen;
         } else {
            # attblock handling
            if ( $searchid eq "" || $searchid eq "$nodeid-$i" || $searchid=~/^$nodeid-$i-/ ) {
               my $r_attachments2=parse_attblock($r_buff, $subattblockstart, $attblocklen-$subattblockstart ,$subtype, $boundary, "$nodeid-$i", $searchid);
               push(@attachments, @{$r_attachments2});
            }
            last;
         }

         $i++;
      }

   } elsif ($attcontenttype =~ /^message/i ) {
      if ( $searchid eq "" || $searchid=~/^$nodeid-0/ ) {
         $attcontent=substr(${$r_buff}, $attblockstart+$attheaderlen+2, $attblocklen-($attheaderlen+2));
         my ($header2, $body2, $r_attachments2)=parse_rfc822block(\$attcontent, "$nodeid-0", $searchid);

         if ( $searchid eq "" || $searchid eq $nodeid ) {
            $header2 = decode_mimewords($header2);

            my $temphtml=headerbody2html($header2, $body2);
            push(@attachments, make_attachment($subtype,"", $attheader,\$temphtml, length($temphtml),
		$attencoding,"text/html", "inline; filename=Unknown.msg",$attid,$attlocation, $nodeid));
         }
         push (@attachments, @{$r_attachments2});
      }

   } elsif ($attcontenttype ne "N/A" ) {

      # the content of an attachment is returned only if
      #  a. the searchid is looking for this attachment
      #  b. this attachment is text based

      if ( ($searchid eq $nodeid) ||
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
   while ( $body =~ m/\n\nbegin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n/igms ) {
      if ( $searchid eq "" || $searchid eq "$nodeid-$i" ) {
         my ($uumode, $uufilename, $uubody) = ($1, $2, $3);
         my $uutype;
         if ($uufilename=~/\.doc$/i) {
            $uutype="application/msword";
         } elsif ($uufilename=~/\.ppt$/i) {
            $uutype="application/x-msexcel";
         } elsif ($uufilename=~/\.xls$/i) {
            $uutype="application/x-mspowerpoint";
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

   $body =~ s/\n\nbegin ([0-7][0-7][0-7][0-7]?) ([^\n\r]+)\n(.+?)\nend\n//igms;
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

sub headerbody2html {
   my ($header, $body)=@_;
   my ($contenttype, $encoding)=get_contenttype_encoding_from_header($header);

   if ($contenttype =~ /^text/i) {
      if ($encoding =~ /^quoted-printable/i) {
          $body = decode_qp($body);
      } elsif ($encoding =~ /^base64/i) {
          $body = decode_base64($body);
      }
   }
   $header = text2html($header);
   if ($contenttype =~ m#^text/html#i) { # convert into html table
      $body = html4nobase($body); 
      $body = html2table($body); 
   } else {	
      $body = text2html($body);
   }

   # be aware the message header are keep untouched here 
   # in order to make it easy for further parsing
   my $temphtml=qq|<table width="100%" border=0 cellpadding=2 cellspacing=0>\n|.
                qq|<tr bgcolor=#dddddd><td>\n|.
                qq|<font size=-1>\n|.
                qq|$header\n|.
                qq|</font>\n|.
                qq|</td></tr>\n|.
                qq|\n\n|.
                qq|<tr><td>\n|.
                qq|$body\n|.
                qq|</td></tr></table>|;
   return($temphtml);
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
   unless ($attfilename =~ s/^.+name[:=]"?([^"]+)"?.*$/$1/ig) {
      $attfilename = $attdisposition || '';
      unless ($attfilename =~ s/^.+filename="?([^"]+)"?.*$/$1/ig) {
         $attfilename = "Unknown.".contenttype2ext($attcontenttype);
      }
   }

   # the 2 attr are coming from parent block
   $temphash{subtype} = $subtype;
   $temphash{boundary} = $boundary;

   $temphash{header} = decode_mimewords($attheader);
   $temphash{r_content} = $r_attcontent;
   $temphash{contentlength} = $attcontentlength;
   $temphash{filename} = decode_mimewords($attfilename);
   $temphash{contenttype} = $attcontenttype || 'text/plain';
   $temphash{encoding} = $attencoding;
   $temphash{id} = $attid;
   $temphash{location} = $attlocation;
   $temphash{nodeid} = $nodeid;

   return(\%temphash);
}

sub contenttype2ext {
   my $contenttype=$_[0];
   my ($class, $ext, $dummy)=split(/[\/\s;,]+/, $contenttype);
   
   return($ext)  if length($ext) <=4;
   return("vcf") if ($ext =~ /vcard/i);

   return("txt") if ($class =~ /text/i);
   return("msg") if ($class =~ /message/i);

   return("doc") if ($ext =~ /msword/i);
   return("ppt") if ($ext =~ /powerpoint/i);
   return("xls") if ($ext =~ /excel/i);
   return("tar") if ($ext =~ /tar/i);
   return("zip") if ($ext =~ /zip/i);
   return("vsd") if ($ext =~ /visio/i);
   return("bin");
}
####################### END PARSE_.... related ###########################

#################### SEARCH_MESSAGES_FOR_KEYWORD ###########################

sub search_messages_for_keyword {
   my ($keyword, $headerdb, $spoolhandle, $cachefile)=@_;
   my %found;
   my (%HDB, @messageids);
   my ($metainfo, $cache_metainfo, $cache_headerdb, $cache_keyword);
   my ($messageid, $readsize, $buff);

   filelock($cachefile, LOCK_EX);
   filelock("$headerdb.$dbm_ext", LOCK_SH);
   dbmopen (%HDB, $headerdb, undef);

   $metainfo=$HDB{'METAINFO'};

   if ( -e $cachefile ) {
      open(CACHE, $cachefile);
      $cache_metainfo=<CACHE>; chomp($cache_metainfo);
      $cache_headerdb=<CACHE>; chomp($cache_headerdb);
      $cache_keyword=<CACHE>; chomp($cache_keyword);
      close(CACHE);
   }
   if ( $cache_metainfo ne $metainfo || $cache_headerdb ne $headerdb ||
        $cache_keyword ne $keyword ) {
      ($cachefile =~ /^(.+)$/) && ($cachefile = $1);		# bypass taint check
      open(CACHE, ">$cachefile");
      print CACHE $metainfo, "\n", $headerdb, "\n", $keyword, "\n";

      @messageids=get_messageids_sorted_by_offset($headerdb, $spoolhandle);

      foreach $messageid (@messageids) {
         my (@attr, $block, $header, $body, $r_attachments) ;

# check de-mimed header first since header in mail folder is raw format.
         $header=$HDB{$messageid};
         if ( $header =~ /$keyword/i ) {
            print CACHE $messageid, "\n";			
            $found{$messageid}=1;
            next;
         }

# check body
         @attr=split(/@@@/, $header);
         seek($spoolhandle, $attr[$_OFFSET], 0);
         read($spoolhandle, $block, $attr[$_SIZE]);

         ($header, $body, $r_attachments)=parse_rfc822block(\$block);
         if ( $attr[$_CONTENT_TYPE] =~ /^text/i ) {	# read all for text/plain. text/html
            if ( $header =~ /content-transfer-encoding:\s+quoted-printable/i) {
               $body = decode_qp($body);
            } elsif ($header =~ /content-transfer-encoding:\s+base64/i) {
               $body = decode_base64($body);
            }
         }
         if ( $body =~ /$keyword/im ) {
            print CACHE $messageid, "\n";
            $found{$messageid}=1;
            next;
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
                  print CACHE $messageid, "\n";
                  $found{$messageid}=1;
                  last;	# leave attachments check in one message
               }
            }
         }
      }
      close(CACHE);

   } else {
      open(CACHE, $cachefile);
      $_=<CACHE>; 
      $_=<CACHE>;
      $_=<CACHE>;
      while (<CACHE>) {
         chomp; $found{$_}=1;
      }
      close(CACHE);
   }

   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);
   filelock($cachefile, LOCK_UN);

   return(%found);
}

#################### END SEARCH_MESSAGES_FOR_KEYWORD ######################

#################### GET_MESSAGEADDRS_SORTED_BY_COUNT #############

sub get_messageaddrs_sorted_by_count {
   my @headerdbs = @_;
   my (@messageids, %count, %name, %date);
   my ($headerdb, $messageid);
   my @emails;

   foreach $headerdb (@headerdbs) {
      @messageids=get_messageids_sorted_by_offset($headerdb);
      foreach $messageid (@messageids) {
         my (@attr, $from, $name, $email);

         @attr=get_message_attributes($messageid, $headerdb);
         if ( $headerdb=~ m#/SENT#i ) {
            $from=$attr[$_TO];
         } else {
            $from=$attr[$_FROM];
         }

         if ( $from=~/@/ ) {
            if ($from=~ /^"?(.+?)"?\s*<(.*)>$/ ) {
               $name=$1;
               $email=$2;
            } elsif ($from=~ /<?(.*@.*)>?\s+\((.+?)\)/ ) {
               $email=$2;
               $name=$1;
            } else {
               $email=$from;
               $email=~s/\s*(.+@.+)\s*/$1/;
               $name=$email;
            }
            if ($email=~/^root@/ || $email=~/daemon@/i ) {
               next;
            }
            $count{$email}++;

### change name for same email addr if date is newer
            if (datestr($attr[$_DATE]) > $date{$email} ) {
               $date{$email}=datestr($attr[$_DATE]); 
               $name{$email}=$name;
            }
         }
      }
   }   

   @emails=sort { $count{$b} <=> $count {$a} ||
                  $date{$b} <=> $date{$a} } keys(%count);

   for (my $i=0; $i<=$#emails; $i++) {
      $emails[$i]=$name{$emails[$i]}.":".
                  $emails[$i].":".
                  $count{$emails[$i]}.":".
                  $date{$emails[$i]};
   }
   return(@emails);
}

################ END GET_MESSAGEADDRS_SORTED_BY_COUNT #############

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
      my $filename=CGI::escape(${${$r_attachments}[$i]}{filename});
      my $link="$scripturl/$filename?$scriptparm&amp;attachment_nodeid=${${$r_attachments}[$i]}{nodeid}&amp;";
      my $cid="cid:"."${${$r_attachments}[$i]}{id}";
      my $loc=${${$r_attachments}[$i]}{location};
      $html =~ s#\Q$loc\E#$link#ig if ($loc ne "");
      $html =~ s#\Q$cid\E#$link#ig if ($cid ne "cid:");
      # ugly hack for strange CID     
      $html =~ s#CID:\{[\d\w\-]+\}/$filename#$link#ig if ($filename ne "");
   }
   return($html);
}

# this routine chnage mailto: into webmail composemail function
# to make it works with base directive, we use full url
# to make it compatible with undecoded base64 block, we put new url into a seperate line
sub html4mailto {
   my ($html, $scripturl, $scriptparm)=@_;
   $html =~ s/(=\s*"?)mailto:\s?([^\s]*?)\s?("?\s*\>)/$1\nhttp:\/\/$ENV{'HTTP_HOST'}$scripturl\?$scriptparm&amp;to=$2\n$3/ig;
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

   return($html);
}

sub str2html {
   my $s=$_[0];

   $s=~s/&/&amp;/g;
   $s=~s/\"/&quot;/g;
   $s=~s/</&lt;/g;
   $s=~s/>/&gt;/g;
   return($s);
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

######################## END HTML related ##############################

################### FILELOCK ###########################
# this routine provides flock with filename
# it opens the file to get the handle if need,
# than do lock operation on the related filehandle
my %opentable;
sub filelock {
   my ($filename, $lockflag)=@_;
   my $fh;

   $fh=$opentable{$filename};

  if (! defined($fh)) {                        # handle not found, open it!
      $fh=FileHandle->new();   
      if ( (! -e $filename) && $lockflag ne LOCK_UN) {
         ($filename =~ /^(.+)$/) && ($filename = $1);   
         sysopen($fh, $filename, O_RDWR|O_CREAT, 0600); # create file for lock
         close($fh);
      } 
      if (sysopen($fh, $filename, O_RDWR)) {
         $opentable{$filename}=$fh;
      } else {
         return(0);
      }
   }

# Since nonblocking lock may return errors 
# even the target is locked by others for just a few seconds,
# we turn nonblocking lock into a blocking lock with timeout limit=10sec
# thus the lock will have more chance to success.

   if ( $lockflag & LOCK_NB ) {	# nonblocking lock
      my $retval;
      eval {
         local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
         alarm 30;
         $retval=flock($fh, $lockflag & (~LOCK_NB) );	
         alarm 0;
      };
      if ($@) {	# eval error, it means timeout
         $retval=0;
      }
      return($retval);

   } else {			# blocking lock				
      return(flock($fh, $lockflag));
   }
}

#################### END LOCKFILE ####################

#################### SHIFTBLOCK ####################
sub shiftblock {
   my ($fh, $start, $size, $movement)=@_;
   my ($oldoffset, $movestart, $left, $buff);

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

   } else {	# $movement <0
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

#################### LOG_TIME (for profiling) ####################

sub log_time {
   my @msg=@_;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
   my ($today, $time);

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime;
   $year+=1900; $mon++;
   $today=sprintf("%4d%02d%02d", $year, $mon, $mday);
   $time=sprintf("%02d%02d%02d",$hour,$min, $sec);

   open(Z, ">> /tmp/time.log");

# unbuffer mode
   select(Z); $| = 1;    
   select(stdout); 

   print Z "$today $time ", join(" ",@msg), "\n";
   close(Z);
   1;
}

################## END LOG_TIME (for profiling) ##################

1;
