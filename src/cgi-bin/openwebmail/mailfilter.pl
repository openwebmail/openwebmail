#
# mailfilter.pl - function for mail filter
#
# 2001/03/15 Ebola@turtle.ee.ncku.edu.tw
#

# return: 0=nothing, <0=error, n=filted count
# there are 4 op for a msg: 'copy', 'move', 'delete' and 'keep'
sub mailfilter {
   my ($user, $folder, $folderdir, $r_validfolders, 
		$filter_repeatlimit, $filter_fakedsmtp)=@_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my @filterrules;
   my $folderhandle=FileHandle->new();
   my %HDB;
   my (@allmessageids, $i);
   
   ## check existence of folderfile
   if ( ! -f $folderfile ) {
      return 0;
   }
   ## check .filter_check ##
   if ( -f "$folderdir/.filter.check" ) {
      my $checkinfo;
      open (FILTERCHECK, "$folderdir/.filter.check" ) or 
         return -1; # $lang_err{'couldnt_open'} .filter.check!
      $checkinfo=<FILTERCHECK>;
      close (FILTERCHECK);
      if ($checkinfo eq metainfo($folderfile)) {
         return 0;
      }      
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
      return -3; # $lang_err{'couldnt_lock'} $folder!
   }
   update_headerdb($headerdb, $folderfile);
   open ($folderhandle, "+<$folderfile") or 
      return -4; # $lang_err{'couldnt_open'} $folder!;

   @allmessageids=get_messageids_sorted_by_offset($headerdb);

   ## open INBOX dbm => lock before open ##
   filelock("$headerdb$dbm_ext", LOCK_EX);
   dbmopen (%HDB, $headerdb, 600);

   my ($blockstart, $blockend, $writepointer)=(0,0,0);
   my $filtered=0;
   my %repeatlists=();	

   for ($i=0; $i<=$#allmessageids; $i++) {
      my ($priority, $rules, $include, $text, $op, $destination, $enable);
      my $line;
      my ($messagestart, $messagesize);
      my @attr = split(/@@@/, $HDB{$allmessageids[$i]});
      my ($currmessage, $header, $body, $r_attachments)=("", "", "", "");
      my ($r_smtprelays, $r_connectfrom, $r_byas);
      my $matched=0;

      if ($filter_repeatlimit>0) {
         # store msgid with same '$from:$subject' to same array
         if (! defined($repeatlists{"$attr[$_FROM]:$attr[$_SUBJECT]"}) ) {
            my @a=();
            $repeatlists{"$attr[$_FROM]:$attr[$_SUBJECT]"}=\@a;
         }
         push (@{$repeatlists{"$attr[$_FROM]:$attr[$_SUBJECT]"}}, $allmessageids[$i] );
      }
      
      ## if match filterrules => do $op (copy, move or delete)
      foreach $line (sort @filterrules) {
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
         
         # old version compatibility
         $rules='textcontent' if ($rules eq 'body');

         if ( $rules eq 'from' ) {
            if (   ($include eq 'include' && $attr[$_FROM] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_FROM] !~ /$text/i)  ) {
               $matched=1;
#log_time($priority, $rules, $include, $text, $op, $destination, $enable);
               if ( $op eq 'move' || $op eq 'copy') {
                  if ($currmessage eq "") {
                     seek($folderhandle, $attr[$_OFFSET], 0);
                     read($folderhandle, $currmessage, $attr[$_SIZE]);
                  }
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }

         } elsif ( $rules eq 'to' ) {
            if (   ($include eq 'include' && $attr[$_TO] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_TO] !~ /$text/i)  ) {
               $matched=1;
#log_time($priority, $rules, $include, $text, $op, $destination, $enable);
               if ( $op eq 'move' || $op eq 'copy') {
                  if ($currmessage eq "") {
                     seek($folderhandle, $attr[$_OFFSET], 0);
                     read($folderhandle, $currmessage, $attr[$_SIZE]);
                  }
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }

         } elsif ( $rules eq 'subject' ) {
            if (   ($include eq 'include' && $attr[$_SUBJECT] =~ /$text/i)
                || ($include eq 'exclude' && $attr[$_SUBJECT] !~ /$text/i)  ) {
               $matched=1;
#log_time($priority, $rules, $include, $text, $op, $destination, $enable);
               if ( $op eq 'move' || $op eq 'copy') {
                  if ($currmessage eq "") {
                     seek($folderhandle, $attr[$_OFFSET], 0);
                     read($folderhandle, $currmessage, $attr[$_SIZE]);
                  }
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user);
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
#log_time($priority, $rules, $include, $text, $op, $destination, $enable);
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user);
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
            if (!defined($r_smtprelays) ) {
               ($r_smtprelays, $r_connectfrom, $r_byas)=get_smtprelays_connectfrom_byas($header);
            }
            my $smtprelays=join(", ", @{$r_smtprelays});
            if (  ( $include eq 'include' && $smtprelays =~ /$text/im )
                ||( $include eq 'exclude' && $smtprelays !~ /$text/im ) ) {
               $matched=1;
#log_time($priority, $rules, $include, $text, $op, $destination, $enable);
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }

         } elsif ( $rules eq 'textcontent' ) {
            if ($currmessage eq "") {
               seek($folderhandle, $attr[$_OFFSET], 0);
               read($folderhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($header eq "") {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
            }

            # check body text
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
#log_time($priority, $rules, $include, $text, $op, $destination, $enable);
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }
            next if ($matched);

            # check attachments text
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
#log_time($priority, $rules, $include, $text, $op, $destination, $enable);
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user);
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
#log_time($priority, $rules, $include, $text, $op, $destination, $enable);
               if ( $op eq 'move' || $op eq 'copy') {
                  my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, $destination, 
					$r_validfolders, $user);
                  last if ($op eq 'move' && $append>=0);
               } elsif ($op eq 'delete') {
                  last;
               }
            }
         }
         
      } # end @filterrules

      # filter message from smtprelay with faked name if msg is not moved or deleted
      if ( $filter_fakedsmtp &&
           !($matched && ($op eq 'move' || $op eq 'delete')) ) {
         if ($currmessage eq "") {
            seek($folderhandle, $attr[$_OFFSET], 0);
            read($folderhandle, $currmessage, $attr[$_SIZE]);
         }
         if ($header eq "") {
            ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
         }
         if (!defined($r_smtprelays) ) {
            ($r_smtprelays, $r_connectfrom, $r_byas)=get_smtprelays_connectfrom_byas($header);
         }

         # move msg to trash if the first relay has invalid/faked hostname
         if ( defined(${$r_smtprelays}[0]) ) { 
            my $relay=${$r_smtprelays}[0];
            my $connectfrom=${$r_connectfrom}{$relay};
            my $byas=${$r_byas}{$relay};


            my $is_private=0;
            if ($connectfrom =~ /\[10\./ ||
                $connectfrom =~ /\[172\.[1-3][0-9]\./ ||
                $connectfrom =~ /\[192\.168\./ ||
                $connectfrom =~ /\[127\.0\./ ) {
                $is_private=1;
            }
           
            my $is_valid=1;
            if ($connectfrom ne "" && $connectfrom !~ /\Q$relay\E/i) {  # faked name
                if ($relay=~ /[\d\w\-_]+\.[\d\w\-_]+/ && 
                    $relay=~/\Q$byas\E/i) {
                   $is_valid=1;
                } else {
                   $is_valid=0;
                }
            }

            # the last relay is the mail server
            my $dstdomain=domain(${$r_smtprelays}[$#{$r_smtprelays}]); 

#log_time("relay $relay");
#log_time("connectfrom $connectfrom");
#log_time("byas $byas");
#log_time("dstdomain $dstdomain");
#log_time("is_private $is_private");
#log_time("is_valid $is_valid");

            if ($connectfrom !~ /\Q$dstdomain\E/i && 
                !$is_private && 
                !$is_valid ) {
               my $append=append_message_to_folder($allmessageids[$i],
					\@attr, \$currmessage, 'mail-trash', 
					$r_validfolders, $user);
               if ($append>=0) {
                  $op='move';
                  $matched=1;
               }
            }
         }

      }

      if ( $matched && ($op eq 'move' || $op eq 'delete') ) {
         ## remove message ##
         $filtered++;

         $messagestart=$attr[$_OFFSET];
         $messagesize=$attr[$_SIZE];

         shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart);

         $writepointer=$writepointer+($blockend-$blockstart);
         $blockstart=$blockend=$messagestart+$messagesize;

         delete $HDB{$allmessageids[$i]};
         
         $HDB{'NEWMESSAGES'}-- if ($attr[$_STATUS]!~/r/i);
         $HDB{'INTERNALMESSAGES'}-- if (is_internal_subject($attr[$_SUBJECT]));
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

   if ($filtered>0) {
      shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart);
      seek($folderhandle, $writepointer+($blockend-$blockstart), 0);
      truncate($folderhandle, tell($folderhandle));
   }
   close ($folderhandle);

   $HDB{'METAINFO'}=metainfo($folderfile);
   dbmclose(%HDB);
   filelock("$headerdb$dbm_ext", LOCK_UN);

   # remove repeated msgs with repeated count > $filter_repeatlimit
   my (@repeatedids, $fromsubject, $r_ids);
   while ( ($fromsubject,$r_ids) = each %repeatlists) {
      push(@repeatedids, @{$r_ids}) if ($#{$r_ids}>=$filter_repeatlimit);
   }
   if ($#repeatedids>=0) {
      my $repeated;
      my ($trashfile, $trashdb)=get_folderfile_headerdb($user, 'mail-trash');
      
      unless (filelock($trashfile, LOCK_EX|LOCK_NB)) {
         return -5; # $lang_err{'couldnt_lock'} mail-trash!
      }
      $repeated=operate_message_with_ids('move', \@repeatedids, $folderfile, $headerdb, 
							$trashfile, $trashdb);
      filelock($trashfile, LOCK_UN);
      $filtered+=$repeated;
   }   

   filelock($folderfile, LOCK_UN);
   
   ## update .filter.check ##
   if (-f "$folderdir/.filter.check" ) {
      open (FILTERCHECK, ">$folderdir/.filter.check" ) or
         return -6; # $lang_err{'couldnt_open'} .filter.check!
      print FILTERCHECK metainfo($folderfile);
      truncate(FILTERCHECK, tell(FILTERCHECK));
      close (FILTERCHECK);
   } else {
      open (FILTERCHECK, ">$folderdir/.filter.check" ) or
         return -6; # $lang_err{'couldnt_open'} .filter.check!
      print FILTERCHECK metainfo($folderfile);
      close (FILTERCHECK);
   }

   return($filtered);
}


sub append_message_to_folder {
   my ($messageid, $r_attr, $r_currmessage, $destination, 
	$r_validfolders, $user)=@_;
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
             
   filelock("$dstdb$dbm_ext", LOCK_EX);

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
      $HDB2{'INTERNALMESSAGES'}++ if (is_internal_subject($attr2[$_SUBJECT]));
      $HDB2{'ALLMESSAGES'}++;
      $HDB2{'METAINFO'}=metainfo($dstfile);
   }
   dbmclose(%HDB2);

   filelock("$dstdb$dbm_ext", LOCK_UN);
   filelock($dstfile, LOCK_UN);
   return(0);
}


sub get_smtprelays_connectfrom_byas {
   my $header=$_[0];
   my @smtprelays=();
   my %connectfrom=();
   my %byas=();
   my ($lastline, $received, $tmp);

   foreach (split(/\n/, $header)) {
      if (/^\s/ && $lastline eq 'RECEIVED') { 
         $received .= $_;
      } elsif (/^Received:(.+)$/ig) {
         $tmp=$1;
         if ($received=~ /^.*\sby\s([^\s]+)\s.*$/is) {
            if (defined($smtprelays[0])) {
               $byas{$smtprelays[0]}=$1;
            } else {
               $smtprelays[0]=$1;	# the last relay on path
               $byas{$smtprelays[0]}=$1;
            }
         }
         if ($received=~ /^.* from\s([^\s]+)\s\((.*?)\).*$/is) {
            unshift(@smtprelays, $1);
            $connectfrom{$1}=$2;
         } elsif ($received=~ /^.*\sfrom\s([^\s]+)\s.*$/is) {
            unshift(@smtprelays, $1);
         } elsif ($received=~ /^.*\(from\s([^\s]+)\).*$/is) {
            unshift(@smtprelays, $1);
         }
         $received=$tmp;
         $lastline = 'RECEIVED';
      } else {
         $lastline = 'NONE';
      }
   }
   # capture last Received: block
   if ($received=~ /^.*\sby\s([^\s]+)\s.*$/is) {
      if (defined($smtprelays[0])) {
         $byas{$smtprelays[0]}=$1;
      } else {
         $smtprelays[0]=$1;	# the last relay on path
         $byas{$smtprelays[0]}=$1;
      }
   }
   if ($received=~ /^.* from\s([^\s]+)\s\((.*?)\).*$/is) {
      unshift(@smtprelays, $1);
      $connectfrom{$1}=$2;
   } elsif ($received=~ /^.*\sfrom\s([^\s]+)\s.*$/is) {
      unshift(@smtprelays, $1);
   } elsif ($received=~ /^.*\(from\s([^\s]+)\).*$/is) {
      unshift(@smtprelays, $1);
   } 
   # count first fromhost as relay only if there are just 2 host on relaylist 
   # since it means sender pc uses smtp to talk to our mail server directly
   shift(@smtprelays) if ($#smtprelays>1);

   return(\@smtprelays, \%connectfrom, \%byas);
}


# return domain part of a FQDN
sub domain {
   my @h=split(/\./, $_[0]);
   shift (@h);
   return(join(".", @h));
}

1;
