#
# mailfilter.pl - function for mail filter
#
# 2001/03/15 Ebola@turtle.ee.ncku.edu.tw
#

# return: 0=nothing, <0=error, n=filted count
sub mailfilter {
   my ($spoolfile, $headerdb, $folderdir, $r_validfolders, $uid, $gid)=@_;

   ## variables ##
   my @filterrules;
   my $spoolhandle=FileHandle->new();
   my (%HDB, %HDB2);
   my ($blockstart, $blockend, $writepointer);
   my (@allmessageids, $i);
   my $moved=0;
   
   ## check existence of spoolfile
   if ( ! -f $spoolfile ) {
      return 0;
   }
   ## check .filter_check ##
   if ( -f "$folderdir/.filter.check" ) {
      open (FILTERCHECK, "$folderdir/.filter.check" ) or 
         return -1; # $lang_err{'couldnt_open'} .filter.check!
      if (<FILTERCHECK> eq metainfo($spoolfile)) {
         return 0;
      }      
      close (FILTERCHECK);
   }

   ## get @filterrules ##
   if ( -f "$folderdir/.filter.book" ) {
      open (FILTER,"$folderdir/.filter.book") or 
         return -2; # $lang_err{'couldnt_open'} .filter.book!
      while (<FILTER>) {
         chomp($_);
         push (@filterrules, $_);
      }
      close (FILTER);
   }

   ## open INBOX, since spool must exist => lock before open ##
   unless (filelock($spoolfile, LOCK_EX|LOCK_NB)) {
      return -3; # $lang_err{'couldnt_lock'} $spoolfile!
   }
   update_headerdb($headerdb, $spoolfile);
   open ($spoolhandle, "+<$spoolfile") or 
      return -4; # $lang_err{'couldnt_open'} $spoolfile!;

   @allmessageids=get_messageids_sorted_by_offset($headerdb);

   ## open INBOX dbm => lock before open ##
   filelock("$headerdb.$dbm_ext", LOCK_EX);
   dbmopen (%HDB, $headerdb, 600);

   $blockstart=$blockend=$writepointer=0;

   for ($i=0; $i<=$#allmessageids; $i++) {
      my ($priority, $rules, $include, $text, $destination, $enable);
      my ($messagestart, $messagesize);
      my @attr = split(/@@@/, $HDB{$allmessageids[$i]});
      my ($currmessage, $header, $body, $r_attachments)=("", "", "", "");
      my $is_message_to_move = 0;
      my $is_destination_ok = 0;
      
      ## if match filterrules => move message ##
      foreach (sort @filterrules) {
         ($priority, $rules, $include, $text, $destination, $enable) = split(/\@\@\@/, $_);
         
         ## check is currentrule enable ##
         unless ($enable == 1) {
            next;
         }
         
         if ( $rules eq 'from' ) {
            if (   ($include eq 'include' && $attr[$_FROM] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_FROM] !~ /$text/i)  ) {
               $is_message_to_move = 1;
               last;
            }

         } elsif ( $rules eq 'to' ) {
            if (   ($include eq 'include' && $attr[$_TO] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_TO] !~ /$text/i)  ) {
               $is_message_to_move = 1;
               last;
            }

         } elsif ( $rules eq 'subject' ) {
            if (   ($include eq 'include' && $attr[$_SUBJECT] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_SUBJECT] !~ /$text/i)  ) {
               $is_message_to_move = 1;
               last;
            }

         } elsif ( $rules eq 'header' ) {
            if ($currmessage eq "") {
               seek($spoolhandle, $attr[$_OFFSET], 0);
               read($spoolhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($header eq "") {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
            }

            $header=decode_mimewords($header);
            if (  ( $include eq 'include' && $header =~ /$text/im )
                ||( $include eq 'exclude' && $header !~ /$text/im ) ) {
               $is_message_to_move = 1;
               last;
            }

         } elsif ( $rules eq 'body' ) {
            if ($currmessage eq "") {
               seek($spoolhandle, $attr[$_OFFSET], 0);
               read($spoolhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($header eq "") {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
            }

            if ( $attr[$_CONTENT_TYPE] =~ /^text/i ) {	# read all for text/plain. text/html
               if ( $header =~ /content-transfer-encoding:\s+quoted-printable/i) {
                  $body = decode_qp($body);
               } elsif ($header =~ /content-transfer-encoding:\s+base64/i) {
                  $body = decode_base64($body);
               }
            }
            if (  ( $include eq 'include' && $body =~ /$text/im )
                ||( $include eq 'exclude' && $body !~ /$text/im ) ) {
               $is_message_to_move = 1;
               last;
            }

            # check attachments body
            foreach my $r_attachment (@{$r_attachments}) {
               if ( ${$r_attachment}{contenttype} =~ /^text/i ) {	# read all for text/plain. text/html
                  if ( ${$r_attachment}{encoding} =~ /^quoted-printable/i ) {
                     ${${$r_attachment}{r_content}} = decode_qp( ${${$r_attachment}{r_content}});
                  } elsif ( ${$r_attachment}{encoding} =~ /^base64/i ) {
                     ${${$r_attachment}{r_content}} = decode_base64( ${${$r_attachment}{r_content}});
                  }
                  if (  ( $include eq 'include' && ${${$r_attachment}{r_content}} =~ /$text/im )
                      ||( $include eq 'exclude' && ${${$r_attachment}{r_content}} !~ /$text/im )  ) {
                     $is_message_to_move = 1;
                     last;	# leave attachments check in one message
                  }
               }
            }
            if ( $is_message_to_move == 1 ) {
               last;
            }
                        
         } elsif ($rules eq 'attfilename') {
            if ($currmessage eq "") {
               seek($spoolhandle, $attr[$_OFFSET], 0);
               read($spoolhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($header eq "") {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
            }

            # check attachments
            foreach my $r_attachment (@{$r_attachments}) {
               if (   ( $include eq 'include' && ${$r_attachment}{filename} =~ /$text/i )
                    ||( $include eq 'exclude' && ${$r_attachment}{filename} !~ /$text/i )  ) {
                  $is_message_to_move = 1;
                  last;	# leave attachments check in one message
               }
            }
            if ( $is_message_to_move == 1 ) {
               last;
            }
         }
         
      } # end @filterrules
         
      if ($is_message_to_move) {
         ## open destination folder, since dest may not exist => open before lock ##
         ($destination =~ /^(.+)$/) && ($destination = $1);  # untaint $destination

         if(! -f "$folderdir/$destination") {
            if (open (DEST, ">$folderdir/$destination")) {
               close (DEST);
               chmod (0600, "$folderdir/$destination");
               chown ($uid, $gid, "$folderdir/$destination");
               push (@{$r_validfolders}, $destination);
            }
         }
         if ( open(DEST, ">>$folderdir/$destination") &&
              filelock("$folderdir/$destination", LOCK_EX|LOCK_NB)) {
            $is_destination_ok=1;
         } else {
            $is_destination_ok=0;
         }
      }

      if ( $is_message_to_move && $is_destination_ok ) {

         update_headerdb("$folderdir/.$destination", "$folderdir/$destination");
             
         filelock("$folderdir/.$destination.$dbm_ext", LOCK_EX);
         dbmopen (%HDB2, "$folderdir/.$destination", 600);

         ## move message ##
         $moved++;

         $messagestart=$attr[$_OFFSET];
         $messagesize=$attr[$_SIZE];

         shiftblock($spoolhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart);

         $writepointer=$writepointer+($blockend-$blockstart);
         $blockstart=$blockend=$messagestart+$messagesize;

         if ($currmessage eq "") {
            seek($spoolhandle, $attr[$_OFFSET], 0);
            read($spoolhandle, $currmessage, $attr[$_SIZE]);
         }
            
         $attr[$_OFFSET]=tell(DEST);
         if ($currmessage =~ /^From /) {
            $attr[$_SIZE]=length($currmessage);
            print DEST $currmessage;
         } else {
            $attr[$_SIZE]=length("From ")+length($currmessage);
            print DEST "From ", $currmessage;
         }

         $HDB2{$allmessageids[$i]}=join('@@@', @attr);
         delete $HDB{$allmessageids[$i]};
         if ( $attr[$_STATUS]!~/r/i ) {
            $HDB2{'NEWMESSAGES'}++;
            $HDB{'NEWMESSAGES'}--;
         }
         $HDB2{'ALLMESSAGES'}++;
         $HDB{'ALLMESSAGES'}--;
         
         ## close destination file and dbm ##
         close (DEST);
            
         $HDB2{'METAINFO'}=metainfo("$folderdir/$destination");
         dbmclose(%HDB2);
         filelock("$folderdir/.$destination.$dbm_ext", LOCK_UN);

         filelock("$folderdir/$destination", LOCK_UN);

      } else { # message not to move or destination can not write
         $messagestart=$attr[$_OFFSET];
         $messagesize=$attr[$_SIZE];
         $blockend=$messagestart+$messagesize;

         my $movement=$writepointer-$blockstart;
         if ($movement<0) {
            $attr[$_OFFSET]+=$movement;
            $HDB{$allmessageids[$i]}=join('@@@', @attr);
         }
      }

   } ## end of allmessages ##

   if ($moved>0) {
      shiftblock($spoolhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart);
      seek($spoolhandle, $writepointer+($blockend-$blockstart), 0);
      truncate($spoolhandle, tell($spoolhandle));
   }
   close ($spoolhandle);

   $HDB{'METAINFO'}=metainfo($spoolfile);
   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   filelock($spoolfile, LOCK_UN);
   
   ## update .filter.check ##
   if (-f "$folderdir/.filter.check" ) {
      open (FILTERCHECK, ">$folderdir/.filter.check" ) or
         return -5; # $lang_err{'couldnt_open'} .filter.check!
      print FILTERCHECK metainfo($spoolfile);
      truncate(FILTERCHECK, tell(FILTERCHECK));
      close (FILTERCHECK);
   } else {
      open (FILTERCHECK, ">$folderdir/.filter.check" ) or
         return -5; # $lang_err{'couldnt_open'} .filter.check!
      print FILTERCHECK metainfo($spoolfile);
      close (FILTERCHECK);
      chmod (0600, "$folderdir/.filter.check");
      chown ($uid, $gid, "$folderdir/.filter.check");
   }

   return($moved);
}

1;
