#
# maildb.pl - mail indexing routines
#
# 2001/12/21 tung.AT.turtle.ee.ncku.edu.tw
#
# it speeds up the message access on folder file by caching important
# information with perl dbm.
#

#
# IMPORTANT!!!
#
# Functions in this file don't do locks for folderfile/folderhandle.
# They rely the caller to do that lock
#
# Functions with folderfile/folderhandle in argument must be inside
# a folderfile lock session
#
use strict;
use Fcntl qw(:DEFAULT :flock);
use FileHandle;

# extern vars, defined in caller openwebmail-xxx.pl
use vars qw(%config %prefs);

# globals, message attribute number constant
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET);
($_OFFSET, $_FROM, $_TO, $_DATE, $_SUBJECT, $_CONTENT_TYPE, $_STATUS, $_SIZE, $_REFERENCES, $_CHARSET)
=(0,1,2,3,4,5,6,7,8,9);

use vars qw(%is_internal_dbkey);
%is_internal_dbkey= (
  METAINFO => 1,
  NEWMESSAGES => 1,
  INTERNALMESSAGES => 1,
  ALLMESSAGES => 1,
  ZAPSIZE => 1,
  "" => 1
);

########## UPDATE_FOLDERDB #######################################
# this routine indexes the mesgs in folder nad mark duplicated msgs with Z (to be zapped)
use vars qw($regex_delimiter);
$regex_delimiter=qr/^From .*(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+([A-Z]{3,4}\d?\s+)?(\d\d+)/;
sub update_folderindex {
   my ($folderfile, $folderdb) = @_;
   my (%FDB, %OLDFDB);
   my @oldmessageids=();
   my $dberr=0;

   $folderdb=ow::tool::untaint($folderdb);
   if (ow::dbm::exist($folderdb)) {
      ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or return -1;
      my ($metainfo, $allmessages, $internalmessages, $newmessages, $zapsize)=
         @FDB{'METAINFO', 'ALLMESSAGES', 'INTERNALMESSAGES', 'NEWMESSAGES', 'ZAPSIZE'};
      ow::dbm::close(\%FDB, $folderdb);

      if ( $metainfo eq ow::tool::metainfo($folderfile) && $zapsize>=0
           && $allmessages>=0 && $internalmessages>=0 && $newmessages>=0 ) {
         return 0;
      }

      # we will try to reference records in old folderdb if possible
      ow::dbm::rename($folderdb, "$folderdb.old");
      @oldmessageids=get_messageids_sorted_by_offset("$folderdb.old");
      ow::dbm::open(\%OLDFDB, "$folderdb.old", LOCK_SH) or return -1;
   }

   my ($messagenumber, $zapsize, $newmessages, $internalmessages) = (-1, 0, 0, 0);
   my ($offset, $totalsize)=(0, 0);
   my %message;	# member: message-id, offset, from, to, date, subject, 
              	#         content-type, status, size, references, charset, in-reply-to
   my %flag;	# internal flag, member: T(has att), V(verified), Z(to be zapped);

   if (!ow::dbm::open(\%FDB, $folderdb, LOCK_EX)) {
      ow::dbm::close(\%OLDFDB, "$folderdb.old") if (defined(%OLDFDB));
      return -1;
   }
   %FDB=();	# ensure the folderdb is empty
   open (FOLDER, $folderfile);

   # copy records from oldhdb as more as possible
   my $foldersize=(stat(FOLDER))[7];
   foreach my $id (@oldmessageids) {
      my @attr=split(/\@\@\@/, $OLDFDB{$id});
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
         if ( ! ($FDB{$id}=join('@@@', @attr)) ) {
            $totalsize-=$attr[$_SIZE];
            last;
         }
         $zapsize+=$attr[$_SIZE] if ($attr[$_STATUS]=~/Z/i);
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
   my ($buff, $bufflen, $readlen, $block, $bkstart, $bkend)=('', '', 0, 0);
   while ( !$dberr && !$eof ) {

      if ($bkstart>0) {			# reserve unprocessed data in buff
         $buff=substr($buff, $bkstart);	$bufflen=length($buff);
         $bkstart=0;
      }
      $readlen=read(FOLDER, $buff, 32768, $bufflen); $bufflen=length($buff);
      $eof=1 if ($readlen <32768);

      while (!$dberr) {
         if ($bkstart>$bufflen) {	# large oldmsg matched in block process?
            seek(FOLDER, $totalsize, 0);# quick seek to start of next mesage
            $buff='';
            $bkstart=0;
            last;
         } elsif (($bkend=index($buff, "\n\n", $bkstart)) >= $bkstart) {# "\n\n" found
            $bkend++; 							# bkend point at end of "\n\n"
            while (substr($buff, $bkend+1, 1) eq "\n") { $bkend++ }	# find all continuous \n greedily
            last if ($bkend+1 >= $bufflen && !$eof);			# read next 32k from file if continuous \n is in buff end
         } elsif ($bufflen-$bkstart>32768 ) {			# cut if buff > 32k. this is safe as mail header or att header won't be that large
            $bkend=$bkstart+32768-1;
         } else {							# read next 32k from file
            last;
         }

         ### BLOCK PROCESSING START ############################################################

         $offset=$totalsize;

         $block=substr($buff, $bkstart, $bkend-$bkstart+1);

         # ex: From Tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
         # ex: From Tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
         # ex: From Nssb@thumper.bellcore.com Wed Mar 11 16:27:37 EST 1992
         if ($block=~/^From / && $block =~ /$regex_delimiter/ ) {
            if ($message{size}>0) {	# save info of prevous msg to FDB
               update_msgrecord(\%FDB, \%message, \%flag, \$zapsize, \$dberr);
            }

            %message=();
            $messagenumber++;
            $message{offset} = $offset;

            foreach (qw(from to date subject content-type)) { $message{$_}='N/A' }
            foreach (qw(message-id status references charset in-reply-to)) { $message{$_}='' }
            foreach (qw(T V Z)) { $flag{$_}=0 }

            ow::mailparse::parse_header(\$block, \%message);
            $message{status}.=$message{'x-status'} if (defined($message{'x-status'}));
            $message{status}.='I' if ($message{priority}=~/urgent/i);

            # Convert to readable text from MIME-encoded
            foreach (qw(from to subject)) {
               $message{$_} = ow::mime::decode_mimewords($message{$_});
            }

            # some dbm(ex:ndbm on solaris) can only has value shorter than 1024 byte,
            # so we cut $message{to} to 256 byte to make dbm happy
            $message{to}=substr($message{to}, 0, 252)."..." if (length($message{to})>256);

            my $dateserial=ow::datetime::datefield2dateserial($message{date});
            my $deliserial=ow::datetime::delimiter2dateserial($message{delimiter}, $config{'deliver_use_GMT'}, $prefs{'daylightsaving'}) ||
                           ow::datetime::gmtime2dateserial();
            if ($dateserial eq "") {
               $dateserial=$deliserial;
            } elsif ($deliserial ne "") {
                my $t=ow::datetime::dateserial2gmtime($deliserial) -
                      ow::datetime::dateserial2gmtime($dateserial);
                if ($t>86400*7 || $t<-86400) { # msg transmission time
                   # use deliverytime in case sender host may have wrong time configuration
                   $dateserial=$deliserial;
                }
            }
            $message{date}=$dateserial;

            $internalmessages++ if (is_internal_subject($message{subject}));
            $newmessages++ if ($message{status} !~ /r/i);

            # check if msg info recorded in old folderdb, we can seek to msg end quickly
            if (defined($OLDFDB{$message{'message-id'}}) ) {
               my ($oldstatus, $oldmsgsize, $oldcharset)=
                  (split(/@@@/, $OLDFDB{$message{'message-id'}}))[$_STATUS, $_SIZE, $_CHARSET];
               my $bkend2=$bkstart+$oldmsgsize-1;	# bkend2 is the olmsg end in buff

               if ($bkend2>$bkend) {
                  my $is_oldmsg_matched=0;

                  if ($bkend2+5<$bufflen) {	# is 'next msg start' in buff?
                     $is_oldmsg_matched=1 if (substr($buff, $bkend2-1, 7) eq "\n\nFrom ");
                  } else {
                     my $fpos=tell(FOLDER); 		# keep old file pointer position
                     my $tmpbuff;
                     if (seek(FOLDER, $message{offset}+$oldmsgsize-2, 0)) {
                        read(FOLDER, $tmpbuff, 7);
                        $is_oldmsg_matched=1 if ($tmpbuff eq "\n\nFrom " || length($tmpbuff)==2);	# next msgstart or EOF found
                     }
                     seek(FOLDER, $fpos, 0);
                  }
                  if ($is_oldmsg_matched) {
                     foreach (qw(T V Z)) { $flag{$_}=1 if ($oldstatus=~/$_/i) } # copy internal flags
                     $message{charset}=$oldcharset;  
                     $zapsize+=$oldmsgsize if ($oldstatus=~/Z/i);
                     $bkend=$bkend2;		# extend bkend to oldmsg end
                  }
               }
             }
             $message{size} = $bkend-$bkstart+1;

         } else {	# msg body block
            if ($message{'content-type'}=~/^multipart/i) {
               if ($block=~/^\-\-/) {	# att header
                  if ($message{charset} eq '' &&
                      $block =~ /^content\-type:.*;\s*charset="?([^\s"';]*)"?/ims) {
                     $message{charset}=$1;
                  }
                  if (!$flag{T} &&
                      ($block =~ /^content\-type:.*;\s*name\s*\*?=/ims ||
                       $block =~ /^content\-disposition:.*;\s*filename\s*\*?=/ims) ) {
                     $flag{T}=1;
                  }
               }
            } elsif ($message{'content-type'} eq 'N/A' ||
                     $message{'content-type'}=~/^text\/plain/) {
               if (!$flag{T} && $message{size} < 16384 &&	# we assume an uuencode block appears very early
                   $block =~ /^begin [0-7][0-7][0-7][0-7]? [^\n\r]+/mi) {
                  $flag{T}=1;
               }
            }

            $message{size} += ($bkend-$bkstart+1);
         }

         #### BLOCK PROCESSING END #############################################################

         $totalsize += ($bkend-$bkstart+1);
         $bkstart = $bkend+1;
      }
   } # end while( !$dberr & !eof )

   if (!$dberr) {
      if ($bufflen-$bkstart>0) {
         $message{size} += ($bufflen-$bkstart);
      }
      if ($message{size}>0) {	# save info of prevous msg to FDB
         update_msgrecord(\%FDB, \%message, \%flag, \$zapsize, \$dberr);
      }
   }
   close (FOLDER);

   if ( !$dberr ) {
      $FDB{'ALLMESSAGES'}=$messagenumber+1;
      $FDB{'INTERNALMESSAGES'}=$internalmessages;
      $FDB{'NEWMESSAGES'}=$newmessages;
      $FDB{'ZAPSIZE'}=$zapsize;
      $FDB{'METAINFO'}=ow::tool::metainfo($folderfile) or $dberr++;
   }

   ow::dbm::close(\%FDB, $folderdb);

   # remove old folderdb
   if (defined(%OLDFDB)) {
      ow::dbm::close(\%OLDFDB, "$folderdb.old");
      ow::dbm::unlink("$folderdb.old");
   }

   return -1 if ($dberr);
   return 1;
}

sub update_msgrecord {
   my ($r_FDB, $r_message, $r_flag, $r_zapsize, $r_dberr)=@_;

   foreach (qw(from to subject content-type status references in-reply-to)) {
      ${$r_message}{$_}=~s/\@\@/\@\@ /g; ${$r_message}{$_}=~s/\@$/\@ /;
   }

   # try to get charset from contenttype header
   ${$r_message}{charset}=$1 if (${$r_message}{charset} eq "" && ${$r_message}{'content-type'}=~/charset\s*=\s*"?([^\s"';]*)"?\s?/i);

   # in most case, a msg references field should already contain
   # ids in in-reply-to: field, but do check it again here
   if (${$r_message}{'in-reply-to'} =~ m/^\s*(\<\S+\>)\s*$/) {
      ${$r_message}{references} .= " " . $1 if (${$r_message}{references}!~/\Q$1\E/);
   }
   ${$r_message}{references} =~ s/\s{2,}/ /g;

   if (${$r_message}{'message-id'} eq '') {	# fake messageid with date and from
      ${$r_message}{'message-id'}="${$r_message}{date}.".(ow::tool::email2nameaddr(${$r_message}{from}))[1];
      ${$r_message}{'message-id'}=~s![\<\>\(\)\s\/"':]!!g;
      ${$r_message}{'message-id'}="<${$r_message}{'message-id'}>";
   }
   # dbm record should not longer than 1024? cut here to make dbm happy
   ${$r_message}{'message-id'}='<'.substr(${$r_message}{'message-id'}, 1, 250).'>' if (length(${$r_message}{'message-id'})>256);

   # flags used by openwebmail internally
   foreach (qw(T V Z)) { ${$r_message}{status} .= $_ if (${$r_flag}{$_}) }
   ${$r_message}{status} =~ s/\s//g;	# remove blanks

   my $id=${$r_message}{'message-id'}; 
   if (defined(${$r_FDB}{$id})) {	# duplicated msg found?
      if (${$r_message}{status}!~/Z/) {	
         #  mark previous one as zap
         my @attr0=split(/\@\@\@/, ${$r_FDB}{$id});
         $attr0[$_STATUS].='Z' if ($attr0[$_STATUS]!~/Z/i);
         ${$r_FDB}{"DUP$attr0[$_OFFSET]-$id"}=join('@@@',@attr0);
         ${$r_zapsize}+=$attr0[$_SIZE];
      } else {
         # mark this msg as zap
         ${$r_message}{status}.='Z';
         ${$r_zapsize}+=${$r_message}{size};
         $id="DUP${$r_message}{offset}-$id";
      }
   }
   ${$r_FDB}{$id}=make_msgrecord($id, ${$r_message}{offset}, ${$r_message}{from}, ${$r_message}{to},
      ${$r_message}{date}, ${$r_message}{subject}, ${$r_message}{'content-type'}, ${$r_message}{status}, 
      ${$r_message}{size}, ${$r_message}{references}, ${$r_message}{charset})
      or ${$r_dberr}++;
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
########## END UPDATE_FOLDERDB ####################################

########## GET_MESSAGEIDS_OSRTED_BY_OFFSET #######################
sub get_messageids_sorted_by_offset {
   my $folderdb=$_[0];
   my (%FDB, %offset, $key, $data);

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or return keys(%offset);
   while ( ($key, $data)=each(%FDB) ) {
      $offset{$key}=(split(/@@@/, $data))[$_OFFSET] if (!$is_internal_dbkey{$key});
   }
   ow::dbm::close(\%FDB, $folderdb);

   return( sort { $offset{$a}<=>$offset{$b} } keys(%offset) );
}
########## END GET_MESSAGEIDS_OSRTED_BY_OFFSET ###################

########## GET_INFO_MSGID2ATTRS ##################################
sub get_info_msgid2attrs {
   my ($folderdb, $ignore_internal, @attrnum)=@_;

   my %msgid2attr=();
   my ($total, $new, $totalsize)=(0,0,0);;
   my (%FDB, $key, $data, @attr);

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH)
      or return ($totalsize, $total, $new, \%msgid2attr);
   while ( ($key, $data)=each(%FDB) ) {
      if ($is_internal_dbkey{$key}) {
         $new=$data if ($key eq 'NEWMESSAGES');
         next;
      } else {
         @attr=split( /@@@/, $data );
         next if ($attr[$_STATUS]=~/Z/i);
         next if ($ignore_internal && is_internal_subject($attr[$_SUBJECT]));
         $total++;
         $totalsize+=$attr[$_SIZE];
         my @attr2=@attr[@attrnum];
         $msgid2attr{$key}=\@attr2;
      }
   }
   ow::dbm::close(\%FDB, $folderdb);

   return($totalsize, $total, $new, \%msgid2attr);
}
########## END GET_INFO_MSGID2ATTRS ##############################

########## GET_MESSAGE_.... ######################################
sub get_message_attributes {
   my ($messageid, $folderdb)=@_;
   my (%FDB, @attr);

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or return @attr;

   @attr=split(/@@@/, $FDB{$messageid} );
   ow::dbm::close(\%FDB, $folderdb);
   return(@attr);
}

sub get_message_block {
   my ($messageid, $folderdb, $folderhandle)=@_;
   my (@attr, $buff);

   @attr=get_message_attributes($messageid, $folderdb);
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
   my ($messageid, $folderdb, $folderhandle)=@_;
   my (@attr, $header);

   @attr=get_message_attributes($messageid, $folderdb);
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
########## END GET_MESSAGE_.... ##################################

########## UPDATE_MESSAGE_STATUS #################################
sub update_message_status {
   my ($messageid, $status, $folderdb, $folderfile) = @_;
   my $messageoldstatus='';
   my $folderhandle=FileHandle->new();
   my %FDB;
   my $ioerr=0;

   if (update_folderindex($folderfile, $folderdb)<0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      writelog("db error - Couldn't update index db $folderdb");
      writehistory("db error - Couldn't update index db $folderdb");
      return -1;
   }

   my @messageids=get_messageids_sorted_by_offset($folderdb);
   my $movement=0;
   my @attr;
   my $i;

   ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or return -1;

   for ($i=0; $i<=$#messageids; $i++) {
      if ($messageids[$i] eq $messageid) {
         @attr=split(/@@@/, $FDB{$messageid});

         $messageoldstatus=$attr[$_STATUS];
         last if ($messageoldstatus eq $status);

         my $messagestart=$attr[$_OFFSET];
         my $messagesize=$attr[$_SIZE];
         my ($header, $headerend, $headerlen, $newheaderlen);
         my $buff;

         open ($folderhandle, "+<$folderfile");
         # since setvbuf is only available before perl 5.8.0, we put this inside eval
         eval { my $_vbuf; $folderhandle->setvbuf($_vbuf, _IOFBF, 32768) };
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

            $FDB{'METAINFO'}="ERR";
            ow::dbm::close(\%FDB, $folderdb);

            # forced reindex since metainfo = ERR
            return -3 if (update_folderindex($folderfile, $folderdb)<0);
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
            # set attributes in folderdb for this status changed message
            if ($messageoldstatus!~/r/i && $status=~/r/i) {
               $FDB{'NEWMESSAGES'}--;
               $FDB{'NEWMESSAGES'}=0 if ($FDB{'NEWMESSAGES'}<0); # should not happen
            } elsif ($messageoldstatus=~/r/i && $status!~/r/i) {
               $FDB{'NEWMESSAGES'}++;
            }
            $FDB{'ZAPSIZE'}+=$movement if ($status=~/Z/i);

            $attr[$_SIZE]=$messagesize+$movement;
            $attr[$_STATUS]=$status;
            $FDB{$messageid}=join('@@@', @attr);
         }

         last;
      }
   }
   $i++;

   # if size of this message is changed
   if ($movement!=0 && !$ioerr) {
      #  change offset attr for messages after the above one
      for (;$i<=$#messageids; $i++) {
         @attr=split(/@@@/, $FDB{$messageids[$i]});
         $attr[$_OFFSET]+=$movement;
         $FDB{$messageids[$i]}=join('@@@', @attr);
      }
   }

   # update folder metainfo
   $FDB{'METAINFO'}=ow::tool::metainfo($folderfile) if (!$ioerr);

   ow::dbm::close(\%FDB, $folderdb);

   if (!$ioerr) {
      return 0;
   } else {
      return -3;
   }
}
########## END UPDATE_MESSAGE_STATUS #############################

########## OP_MESSAGE_WITH_IDS ###################################
# operate messages with @messageids from src folderfile to dst folderfile
# available $op: "move", "copy", "delete"
sub operate_message_with_ids {
   my ($op, $r_messageids, $srcfile, $srcdb, $dstfile, $dstdb)=@_;
   my (%FDB, %FDB2);
   my $ioerr=0;

   # $lang_err{'inv_msg_op'}
   return -1 if ($op ne "move" && $op ne "copy" && $op ne "delete");
   return 0 if ($srcfile eq $dstfile || $#{$r_messageids} < 0);

   if (update_folderindex($srcfile, $srcdb)<0) {
      writelog("db error - Couldn't update index db $srcdb");
      writehistory("db error - Couldn't update index db $srcdb");
      return -1;
   }

   return -3 if (!open(SRC, $srcfile));
   return -1 if (!ow::dbm::open(\%FDB, $srcdb, LOCK_EX));

   my $dsthandle=FileHandle->new();
   if ($op eq "move" || $op eq "copy") {
      if (update_folderindex($dstfile, $dstdb)<0) {
         ow::dbm::close(\%FDB, $srcdb);
         close (SRC);
         writelog("db error - Couldn't update index db $dstdb");
         writehistory("db error - Couldn't update index db $dstdb");
         return -1;
      }

      if (!open ($dsthandle, "+<$dstfile")) {
         ow::dbm::close(\%FDB, $srcdb);
         close (SRC);
         return -5;
      }
      # since setvbuf is only available before perl 5.8.0, we put this inside eval
      eval { my $_dstvbuf; $dsthandle->setvbuf($_dstvbuf, _IOFBF, 32768) };
      seek($dsthandle, 0, 2);	# seek end explicitly to cover tell() bug in perl 5.8

      if (!ow::dbm::open(\%FDB2,$dstdb, LOCK_EX)) {
         close ($dsthandle);
         ow::dbm::close(\%FDB, $srcdb);
         close (SRC);
         writelog("db error - Couldn't open index db $dstdb");
         writehistory("db error - Couldn't open index db $dstdb");
         return -1;
      }
   }

   my ($is_message_valid, @attr, $buff);
   my $counted=0;
   foreach my $messageid (@{$r_messageids}) {
      next if (!defined($FDB{$messageid}));

      @attr=split(/@@@/, $FDB{$messageid});
      $is_message_valid=1;

      if ($attr[$_OFFSET]>0) {
         seek(SRC, $attr[$_OFFSET], 0);
         read(SRC, $buff, 5);
         $is_message_valid=0 if ($buff!~/^From /);
      }
      if ($attr[$_SIZE]>10) {
         seek(SRC, $attr[$_OFFSET]+$attr[$_SIZE], 0);
         read(SRC, $buff, 5);
         $is_message_valid=0 if ($buff!~/^From / && $buff ne "");
      } else {
         $is_message_valid=0;
      }
      
      if ($is_message_valid) {
         $counted++;
         # append msg to dst folder only if op=move/copy and msg doesn't exist in dstfile
         if (($op eq "move" || $op eq "copy") && !$ioerr ) {
            if (defined($FDB2{$messageid})) {
               my @attr0=split(/\@\@\@/, $FDB2{$messageid});
               if ($attr0[$_SIZE] eq $attr[$_SIZE]) {	# skip the cp because same size
                  if ($attr0[$_STATUS]=~s/Z//ig) {
                     $FDB2{$messageid}=join('@@@', @attr0);
                     $FDB2{'ZAPSIZE'}-=$attr0[$_SIZE];
                  }
               } else {
                  if ($attr0[$_STATUS]!~/Z/i) {		# mark old duplicated one as zap
                     $attr0[$_STATUS].='Z';
                     $FDB2{'ZAPSIZE'}+=$attr0[$_SIZE];
                  }
                  $FDB2{"DUP$attr0[$_OFFSET]-$messageid"}=join('@@@', @attr0);
                  delete $FDB2{$messageid};
               }
            }   

            if (!defined($FDB2{$messageid})) {	# cp message from SRC to $dsthandle 
               # since @attr will be used for FDB2 temporarily and $attr[$_OFFSET] will be modified
               # we save it in $srcoffset and copy it back after write of dst folder
               my $srcoffset=$attr[$_OFFSET];

               seek(SRC, $attr[$_OFFSET], 0);
               $attr[$_OFFSET]=tell($dsthandle);
               my $left=$attr[$_SIZE];
               while ($left>32768) {
                  read(SRC, $buff, 32768);
                  print $dsthandle $buff or $ioerr++;
                  $left-=32768;
               }
               read(SRC, $buff, $left);
               print $dsthandle $buff or $ioerr++;

               if (!$ioerr) {
                  $FDB2{'NEWMESSAGES'}++ if ($attr[$_STATUS]!~/r/i);
                  $FDB2{'INTERNALMESSAGES'}++ if (is_internal_subject($attr[$_SUBJECT]));
                  $FDB2{'ALLMESSAGES'}++;
                  $FDB2{$messageid}=join('@@@', @attr);
               }
               $attr[$_OFFSET]=$srcoffset;
            }
         }

         if (($op eq 'move' || $op eq 'delete') && !$ioerr && $attr[$_STATUS]!~/Z/i) {
            $attr[$_STATUS].='Z';	# to be zapped in the future
            $FDB{'ZAPSIZE'}+=$attr[$_SIZE];
            $FDB{$messageid}=join('@@@', @attr);	# $attr[$_OFFSET] is used here
         }
      }

      last if ($ioerr);
   }

   if ($op eq "move" || $op eq "copy") {
      close ($dsthandle);
      $FDB2{'METAINFO'}=ow::tool::metainfo($dstfile) if (!$ioerr);
      ow::dbm::close(\%FDB2,$dstdb);
   }

   close (SRC);
   ow::dbm::close(\%FDB, $srcdb);

   return -8 if ($ioerr);
   return($counted);
}

sub folder_zapmessages {
   my ($srcfile, $srcdb)=@_;
   my %FDB;
   my $ioerr=0;

   if (update_folderindex($srcfile, $srcdb)<0) {
      writelog("db error - Couldn't update index db $srcdb");
      writehistory("db error - Couldn't update index db $srcdb");
      return -2;
   }

   return -1 if ( !ow::dbm::open(\%FDB, $srcdb, LOCK_SH) );
   my $zapsize=$FDB{'ZAPSIZE'};
   ow::dbm::close(\%FDB, $srcdb);
   return 0 if ($zapsize==0);	# no zap messages in folder

   my @allmessageids=get_messageids_sorted_by_offset($srcdb);

   my $folderhandle=FileHandle->new();
   return -3 if (!open ($folderhandle, "+<$srcfile"));
   # since setvbuf is only available before perl 5.8.0, we put this inside eval
   eval { my $_vbuf; $folderhandle->setvbuf($_vbuf, _IOFBF, 32768) };

   return -1 if ( !ow::dbm::open(\%FDB, $srcdb, LOCK_EX) );

   my ($blockstart, $blockend, $writepointer);
   my ($messagestart, $messagesize, $messagevalid, @attr, $buff);
   my $counted=0;

   $blockstart=$blockend=$writepointer=0;

   for (my $i=0; $i<=$#allmessageids; $i++) {
      @attr=split(/@@@/, $FDB{$allmessageids[$i]});
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

      if ($attr[$_STATUS]=~/Z/ && $messagevalid) { # msg to be zaped
         $counted++;

         if (shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart)<0) {
            writelog("data error - msg $allmessageids[$i] in $srcfile shiftblock failed");
            writehistory("data error - msg $allmessageids[$i] in $srcfile shiftblock failed");
            $ioerr++;
         } else {
            $writepointer=$writepointer+($blockend-$blockstart);
            $blockstart=$blockend=$messagestart+$messagesize;
         }

         if (!$ioerr) {
            $FDB{'NEWMESSAGES'}-- if ($attr[$_STATUS]!~/r/i);
            $FDB{'INTERNALMESSAGES'}-- if (is_internal_subject($attr[$_SUBJECT]));
            $FDB{'ALLMESSAGES'}--;
            $FDB{'ZAPSIZE'}-=$attr[$_SIZE];
            delete $FDB{$allmessageids[$i]};
         }

      } else {						# msg to be kept in same folder
         $blockend=$messagestart+$messagesize;

         my $movement=$writepointer-$blockstart;
         if ($movement<0) {
            $attr[$_OFFSET]+=$movement;
            $FDB{$allmessageids[$i]}=join('@@@', @attr);
         }
      }

      last if ($ioerr);
   }

   if ($counted>0 && !$ioerr) {
      if (shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart)<0) {
         writelog("data error - msgs in $srcfile shiftblock failed");
         writehistory("data error - msgs in $srcfile shiftblock failed");
         $ioerr++;
      } else {
         seek($folderhandle, $writepointer+($blockend-$blockstart), 0);
         truncate($folderhandle, tell($folderhandle));
      }
   }

   close ($folderhandle);

   if (!$ioerr) {
      foreach (qw(NEWMESSAGES INTERNALMESSAGES ALLMESSAGES ZAPSIZE)) {
         $FDB{$_}=0 if $FDB{$_}<0;	# should not happen
      }
      $FDB{'METAINFO'}=ow::tool::metainfo($srcfile);
   }
   ow::dbm::close(\%FDB, $srcdb);

   return -8 if ($ioerr);
   return($counted);
}

########## END OP_MESSAGE_WITH_IDS ###############################

########## DELETE_MESSAGE_BY_AGE #################################
sub delete_message_by_age {
   my ($dayage, $folderdb, $folderfile)=@_;
   return 0 if ( ! -f $folderfile );

   my $folderhandle=do { local *FH };
   my (%FDB, @allmessageids, @agedids);

   if (update_folderindex($folderfile, $folderdb)<0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      writelog("db error - Couldn't update index db $folderdb");
      writehistory("db error - Couldn't update index db $folderdb");
      return 0;
   }
   @allmessageids=get_messageids_sorted_by_offset($folderdb);

   ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or return -1;

   my $agestarttime=time()-$dayage*86400;
   foreach (@allmessageids) {
      my @attr = split(/@@@/, $FDB{$_});
      push(@agedids, $_) if (ow::datetime::dateserial2gmtime($attr[$_DATE])<=$agestarttime); # too old
   }
   ow::dbm::close(\%FDB, $folderdb);

   return 0 if ($#agedids==-1);

   operate_message_with_ids('delete', \@agedids, $folderfile, $folderdb);
   return(folder_zapmessages($folderfile, $folderdb));
}
########## END DELETE_MESSAGE_BY_AGE #############################

########## MOVE_OLDMSG_FROM_FOLDER ###############################
sub move_oldmsg_from_folder {
   my ($srcfile, $srcdb, $dstfile, $dstdb)=@_;
   my (%FDB, $key, $data, @attr);
   my @messageids=();

   ow::dbm::open(\%FDB, $srcdb, LOCK_SH) or return -1;

   # if oldmsg == internal msg or 0, then do not read ids
   if ( $FDB{'ALLMESSAGES'}-$FDB{'NEWMESSAGES'} > $FDB{'INTERNALMESSAGES'} ) {
      while ( ($key, $data)=each(%FDB) ) {
         next if ($is_internal_dbkey{$key});
         @attr=split( /@@@/, $data );
         if ( $attr[$_STATUS] =~ /r/i &&
              !is_internal_subject($attr[$_SUBJECT]) ) {
            push(@messageids, $key);
         }
      }
   }

   ow::dbm::close(\%FDB, $srcdb);

   # no old msg found
   return 0 if ($#messageids==-1);

   operate_message_with_ids('move', \@messageids, $srcfile, $srcdb,
				  		   $dstfile, $dstdb);
   folder_zapmessages($srcfile, $srcdb);
}
########## END MOVE_OLDMSG_FROM_FOLDER ###########################

########## REBUILD_MESSAGE_WITH_PARTIALID ########################
# rebuild orig msg with partial msgs in the same folder
sub rebuild_message_with_partialid {
   my ($folderfile, $folderdb, $partialid)=@_;
   my (%FDB, @messageids);
   my ($partialtotal, @partialmsgids, @offset, @size);

   if (update_folderindex($folderfile, $folderdb)<0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      writelog("db error - Couldn't update index db $folderdb");
      writehistory("db error - Couldn't update index db $folderdb");
      return -1;
   }

   # find all partial msgids
   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or return -2;

   @messageids=keys %FDB;
   foreach my $id (@messageids) {
      next if ($is_internal_dbkey{$id});
      my @attr=split( /@@@/, $FDB{$id} );
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
   ow::dbm::close(\%FDB, $folderdb);

   # check completeness
   if ($partialtotal<1) {	# last part not found
      return -3;
   }
   for (my $i=1; $i<=$partialtotal; $i++) {
      if ($partialmsgids[$i] eq "") {	# some part missing
         return -4;
      }
   }

   my $tmpfile=ow::tool::untaint("/tmp/rebuild_tmp_$$");
   my $tmpdb=ow::tool::untaint("/tmp/.rebuild_tmp_$$");

   ow::filelock::lock("$tmpfile", LOCK_EX) or return -5;
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
   ow::filelock::lock("$tmpfile", LOCK_EX) or return -6;

   # index tmpfile, get the msgid
   if (update_folderindex($tmpfile, $tmpdb)<0) {
      ow::filelock::lock($tmpfile, LOCK_UN);
      writelog("db error - Couldn't update index db $tmpdb");
      writehistory("db error - Couldn't update index db $tmpdb");
      return -7;
   }

   # check the rebuild integrity
   my @rebuildmsgids=get_messageids_sorted_by_offset($tmpdb);
   if ($#rebuildmsgids!=0) {
      unlink($tmpfile);
      ow::dbm::unlink($tmpdb);
      return -8;
   }
   my $rebuildsize=(get_message_attributes($rebuildmsgids[0], $tmpdb))[$_SIZE];
   if ($writtensize!=$rebuildsize) {
      unlink($tmpfile);
      ow::dbm::unlink($tmpdb);
      return -9;
   }

   operate_message_with_ids("move", \@rebuildmsgids, $tmpfile, $tmpdb, $folderfile, $folderdb);

   unlink($tmpfile);
   ow::dbm::unlink($tmpdb);

   return(0, $rebuildmsgids[0], @partialmsgids);
}
########## END REBUILD_MESSAGE_WITH_PARTIALID ####################

########## SHIFTBLOCK ############################################
sub shiftblock {
   my ($fh, $start, $size, $movement)=@_;
   my ($oldoffset, $movestart, $left, $buff);
   my $ioerr=0;

   return 0 if ($movement == 0 );

   $oldoffset=tell($fh);
   $left=$size;
   if ( $movement >0 ) {
      while ($left>32768 && !$ioerr) {
          $movestart=$start+$left-32768;
          seek($fh, $movestart, 0);
          read($fh, $buff, 32768);
          seek($fh, $movestart+$movement, 0);
          print $fh $buff or $ioerr++;
          $left=$left-32768;
      }
      if (!$ioerr) {
         seek($fh, $start, 0);
         read($fh, $buff, $left);
         seek($fh, $start+$movement, 0);
         print $fh $buff or $ioerr++;
      }

   } elsif ( $movement <0 ) {
      while ($left>32768 && !$ioerr) {
         $movestart=$start+$size-$left;
         seek($fh, $movestart, 0);
         read($fh, $buff, 32768);
         seek($fh, $movestart+$movement, 0);
         print $fh $buff or $ioerr++;
         $left=$left-32768;
      }
      if (!$ioerr) {
         $movestart=$start+$size-$left;
         seek($fh, $movestart, 0);
         read($fh, $buff, $left);
         seek($fh, $movestart+$movement, 0);
         print $fh $buff or $ioerr++;
      }
   }
   seek($fh, $oldoffset, 0);

   return -1 if ($ioerr);
   return 1;
}
########## END SHIFTBLOCK ########################################

########## EMPTYFOLDER ###########################################
sub emptyfolder {
   my ($folderfile, $folderdb) = @_;

   open (F, ">$folderfile") or return -1;
   close (F);
   return -2 if (update_folderindex($folderfile, $folderdb) <0);

   return 0;
}
########## END EMPTYFOLDER #######################################

########## SIMPLEHEADER ##########################################
sub simpleheader {
   my $simpleheader="";
   my $lastline = 'NONE';
   my $regex_simpleheaders=qr/^(?:from|reply\-to|to|cc|date|subject):\s?/i;

   foreach (split(/\n/, $_[0])) {	# $_[0] is header
      if (/^\s+/) {
         $simpleheader.="$_\n" if ($lastline eq 'HEADER');
      } elsif (/$regex_simpleheaders/) {
         $simpleheader .= "$_\n"; $lastline = 'HEADER';
      } else {
         $lastline = 'NONE';
      }
   }
   return($simpleheader);
}
########## END SIMPLEHEADER ######################################

########## IS_INTERNAL_SUBJECT ###################################
sub is_internal_subject {
   return 1 if ($_[0] =~ /(?:DON'T DELETE THIS MESSAGE|Message from mail server)/);
   return 0;
}
########## END IS_INTERNAL_SUBJECT ###############################

1;
