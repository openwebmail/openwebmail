#
# mailfilter.pl - function for mail filter
#
# 2001/03/15 Ebola@turtle.ee.ncku.edu.tw

# return: 0=nothing, <0=error, n=filted count
# there are 4 op for a msg: 'copy', 'move', 'delete' and 'keep'
sub mailfilter {
   my ($folderfile, $headerdb, $folderdir, $r_validfolders, $user, $uid, $gid)=@_;
   my @filterrules;
   my $folderhandle=FileHandle->new();
   my %HDB;
   my ($blockstart, $blockend, $writepointer);
   my (@allmessageids, $i);
   my $removed=0;
   
   ## check existence of spoolfile
   if ( ! -f $folderfile ) {
      return 0;
   }
   ## check .filter_check ##
   if ( -f "$folderdir/.filter.check" ) {
      open (FILTERCHECK, "$folderdir/.filter.check" ) or 
         return -1; # $lang_err{'couldnt_open'} .filter.check!
      if (<FILTERCHECK> eq metainfo($folderfile)) {
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

   if ( $global_filterbook ne "" && -f "$global_filterbook" ) {
      if (open (FILTER,"$global_filterbook")) {
         while (<FILTER>) {
            chomp($_);
            push (@filterrules, $_);
         }
         close (FILTER);
      }
   }

   ## open INBOX, since spool must exist => lock before open ##
   unless (filelock($folderfile, LOCK_EX|LOCK_NB)) {
      return -3; # $lang_err{'couldnt_lock'} $folderfile!
   }
   update_headerdb($headerdb, $folderfile);
   open ($folderhandle, "+<$folderfile") or 
      return -4; # $lang_err{'couldnt_open'} $folderfile!;

   @allmessageids=get_messageids_sorted_by_offset($headerdb);

   ## open INBOX dbm => lock before open ##
   filelock("$headerdb.$dbm_ext", LOCK_EX);
   dbmopen (%HDB, $headerdb, 600);

   $blockstart=$blockend=$writepointer=0;

   for ($i=0; $i<=$#allmessageids; $i++) {
      my ($priority, $rules, $include, $text, $op, $destination, $enable);
      my ($messagestart, $messagesize);
      my @attr = split(/@@@/, $HDB{$allmessageids[$i]});
      my ($currmessage, $header, $body, $r_attachments)=("", "", "", "");
      my $matched=0;
      
      ## if match filterrules => do $op (copy, move or delete)
      foreach my $line (sort @filterrules) {
         $matched=0;

         ($priority, $rules, $include, $text, $op, $destination, $enable) = split(/\@\@\@/, $line);
         if ( $enable eq '') {	# compatible with old format
            ($priority, $rules, $include, $text, $destination, $enable) = split(/\@\@\@/, $line);
            $op='move';
         }
         $destination =~ s/\.\.+//g;
         $destination =~ s/[\s\/\`\|\<\>;]//g; # remove dangerous char

         ## check if current rule is enabled ##
         next unless ($enable == 1);
         next if ( $op ne 'copy' && $op ne 'move' && $op ne 'delete');

         if ($destination eq 'DELETE') {
            if ( $op eq 'copy' ) {
                next;			# copy to DELETE is meaningless
            } elsif ($op eq 'move') {
                $op='delete';		# move to DELETE is 'delete'
            }
         } elsif ($destination eq 'INBOX') { 
            $op='keep';		# keep this msg in INBOX and skip all other rules.
            last;
         }
         
         if ( $rules eq 'from' ) {
            if (   ($include eq 'include' && $attr[$_FROM] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_FROM] !~ /$text/i)  ) {
               $matched=1;
               if ( $op eq 'move' || $op eq 'copy') {
                  if ($currmessage eq "") {
                     seek($folderhandle, $attr[$_OFFSET], 0);
                     read($folderhandle, $currmessage, $attr[$_SIZE]);
                  }
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user, $uid, $gid);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }

         } elsif ( $rules eq 'to' ) {
            if (   ($include eq 'include' && $attr[$_TO] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_TO] !~ /$text/i)  ) {
               $matched=1;
               if ( $op eq 'move' || $op eq 'copy') {
                  if ($currmessage eq "") {
                     seek($folderhandle, $attr[$_OFFSET], 0);
                     read($folderhandle, $currmessage, $attr[$_SIZE]);
                  }
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user, $uid, $gid);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }

         } elsif ( $rules eq 'subject' ) {
            if (   ($include eq 'include' && $attr[$_SUBJECT] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_SUBJECT] !~ /$text/i)  ) {
               $matched=1;
               if ( $op eq 'move' || $op eq 'copy') {
                  if ($currmessage eq "") {
                     seek($folderhandle, $attr[$_OFFSET], 0);
                     read($folderhandle, $currmessage, $attr[$_SIZE]);
                  }
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user, $uid, $gid);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }

         } elsif ( $rules eq 'header' ) {
            if ($currmessage eq "") {
               seek($folderhandle, $attr[$_OFFSET], 0);
               read($folderhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($header eq "") {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
            }

            $header=decode_mimewords($header);
            if (  ( $include eq 'include' && $header =~ /$text/im )
                ||( $include eq 'exclude' && $header !~ /$text/im ) ) {
               $matched=1;
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user, $uid, $gid);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }

         } elsif ( $rules eq 'smtprelay' ) {
            if ($currmessage eq "") {
               seek($folderhandle, $attr[$_OFFSET], 0);
               read($folderhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($header eq "") {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
            }

            my $smtprelays="";
            my @a=split(/Received:/,$header);
            shift @a;
            foreach (@a) {
               if (/^.* by\s([^\s]+)\s.*$/is) {
                  $smtprelays .= ", $1";
               }
               if (/^.* from\s([^\s]+)\s.*$/is) {
                  $smtprelays .= ", $1";
               }
            }
            if (  ( $include eq 'include' && $smtprelays =~ /$text/im )
                ||( $include eq 'exclude' && $smtprelays !~ /$text/im ) ) {
               $matched=1;
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user, $uid, $gid);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }

         } elsif ( $rules eq 'body' ) {
            if ($currmessage eq "") {
               seek($folderhandle, $attr[$_OFFSET], 0);
               read($folderhandle, $currmessage, $attr[$_SIZE]);
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
               $matched=1;
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user, $uid, $gid);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }
            next if ($matched);

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
                     $matched = 1;
                     last;	# leave attachments check in one message
                  }
               }
            }
            if ($matched) {
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user, $uid, $gid);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }
                        
         } elsif ($rules eq 'attfilename') {
            if ($currmessage eq "") {
               seek($folderhandle, $attr[$_OFFSET], 0);
               read($folderhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($header eq "") {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
            }

            # check attachments
            foreach my $r_attachment (@{$r_attachments}) {
               if (   ( $include eq 'include' && ${$r_attachment}{filename} =~ /$text/i )
                    ||( $include eq 'exclude' && ${$r_attachment}{filename} !~ /$text/i )  ) {
                  $matched = 1;
                  last;	# leave attachments check in one message
               }
            }
            if ($matched) {
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user, $uid, $gid);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }
         }
         
      } # end @filterrules
         
      if ( $matched && ($op eq 'move' || $op eq 'delete') ) {
         ## remove message ##
         $removed++;

         $messagestart=$attr[$_OFFSET];
         $messagesize=$attr[$_SIZE];

         shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart);

         $writepointer=$writepointer+($blockend-$blockstart);
         $blockstart=$blockend=$messagestart+$messagesize;

         delete $HDB{$allmessageids[$i]};
         
         $HDB{'NEWMESSAGES'}-- if ($attr[$_STATUS]!~/r/i);
         $HDB{'INTERNALMESSAGES'}-- if ($attr[$_SUBJECT]=~/DON'T DELETE THIS MESSAGE/);
         $HDB{'ALLMESSAGES'}--;
         
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

   if ($removed>0) {
      shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart);
      seek($folderhandle, $writepointer+($blockend-$blockstart), 0);
      truncate($folderhandle, tell($folderhandle));
   }
   close ($folderhandle);

   $HDB{'METAINFO'}=metainfo($folderfile);
   dbmclose(%HDB);
   filelock("$headerdb.$dbm_ext", LOCK_UN);

   filelock($folderfile, LOCK_UN);
   
   ## update .filter.check ##
   if (-f "$folderdir/.filter.check" ) {
      open (FILTERCHECK, ">$folderdir/.filter.check" ) or
         return -5; # $lang_err{'couldnt_open'} .filter.check!
      print FILTERCHECK metainfo($folderfile);
      truncate(FILTERCHECK, tell(FILTERCHECK));
      close (FILTERCHECK);
   } else {
      open (FILTERCHECK, ">$folderdir/.filter.check" ) or
         return -5; # $lang_err{'couldnt_open'} .filter.check!
      print FILTERCHECK metainfo($folderfile);
      close (FILTERCHECK);
   }

   return($removed);
}


sub append_message_to_folder {
   my ($messageid, $r_attr, $r_currmessage, $destination, 
	$r_validfolders, $user, $uid, $gid)=@_;
   my %HDB2;
   my ($dstfile, $dstdb)=get_folderfile_headerdb($user, $destination);
   ($dstfile =~ /^(.+)$/) && ($dstfile = $1);  # untaint $dstfile
   ($dstdb =~ /^(.+)$/) && ($dstdb = $1);  # untaint $dstdb

   if(! -f $dstfile) {
      if (open (DEST, ">$dstfile")) {
         close (DEST);
         push (@{$r_validfolders}, $destination);
      }
   }
   
   filelock($dstfile, LOCK_EX|LOCK_NB) || return(-2);

   update_headerdb($dstdb, $dstfile);
             
   filelock("$dstdb.$dbm_ext", LOCK_EX);

   dbmopen (%HDB2, $dstdb, 600);
   if (! defined($HDB2{$messageid}) ) {	# append only if not found in dstfile
      my @attr2=@{$r_attr};

      open(DEST, ">>$dstfile") || return(-1);
      $attr2[$_OFFSET]=tell(DEST);
      if (${$r_currmessage} =~ /^From /) {
         $attr2[$_SIZE]=length(${$r_currmessage});
         print DEST ${$r_currmessage};
      } else {
         $attr2[$_SIZE]=length("From ")+length(${$r_currmessage});
         print DEST "From ", ${$r_currmessage};
      }
      close (DEST);

      $HDB2{$messageid}=join('@@@', @attr2);
      $HDB2{'NEWMESSAGES'}++ if ($attr2[$_STATUS]!~/r/i);
      $HDB2{'INTERNALMESSAGES'}++ if ($attr2[$_SUBJECT]=~/DON'T DELETE THIS MESSAGE/);
      $HDB2{'ALLMESSAGES'}++;
      $HDB2{'METAINFO'}=metainfo($dstfile);
   }
   dbmclose(%HDB2);

   filelock("$dstdb.$dbm_ext", LOCK_UN);
   filelock($dstfile, LOCK_UN);
   return(0);
}

1;
