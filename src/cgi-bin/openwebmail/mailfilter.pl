#
# mailfilter.pl - mail filter routines
#
# 2001/11/13 Ebola@turtle.ee.ncku.edu.tw
#            tung@turtle.ee.ncku.edu.tw
#

use strict;
use Fcntl qw(:DEFAULT :flock);

# extern vars
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET);
use vars qw(%config);

# return: 0=nothing, <0=error, n=filted count
# there are 4 op for a msg: 'copy', 'move', 'delete' and 'keep'
sub mailfilter {
   my ($user, $folder, $folderdir, $r_validfolders, $prefs_regexmatch,
	$filter_repeatlimit, $filter_fakedsmtp,
	$filter_fakedfrom, $filter_fakedexecontenttype)=@_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my @filterrules;
   my $folderhandle=FileHandle->new();
   my (%HDB, %FTDB, %IS_GLOBAL);
   my (@allmessageids, $i);
   my $newfilterrule=0;
   my $ioerr=0;

   ## check existence of folderfile
   if ( ! -f $folderfile ) {
      return 0;
   }
   ## check .filter_check ##
   if ( -f "$folderdir/.filter.check" ) {
      my $checkinfo;
      open (FILTERCHECK, "$folderdir/.filter.check" ) or return -1; 
      $checkinfo=<FILTERCHECK>;
      close (FILTERCHECK);
      if ($checkinfo eq metainfo($folderfile)) {
         return 0;
      }
   } else {
      $newfilterrule=1;	# new filterrule, so do filtering on all msg
   }

   ## get @filterrules ##
   if ( -f "$folderdir/.filter.book" ) {
      open (FILTER,"$folderdir/.filter.book") or return -2;
      while (<FILTER>) {
         chomp($_);
         push (@filterrules, $_) if(/^\d+\@\@\@/); # add valid rule only
      }
      close (FILTER);
   }

   if ( $config{'global_filterbook'} ne "" && -f "$config{'global_filterbook'}" ) {
      if (open (FILTER,"$config{'global_filterbook'}")) {
         while (<FILTER>) {
            chomp($_);
            push (@filterrules, $_);
            $IS_GLOBAL{$_}=1;
         }
         close (FILTER);
      }
   }

   if ( ! -e "$folderdir/.filter.book$config{'dbm_ext'}" ) {
      dbmopen (%FTDB, "$folderdir/.filter.book$config{'dbmopen_ext'}", 0600);
      dbmclose(%FTDB);
   }
   if (!$config{'dbmopen_haslock'}) {
      filelock("$folderdir/.filter.book$config{'dbm_ext'}", LOCK_EX) or return -3;
   }
   dbmopen (%FTDB, "$folderdir/.filter.book$config{'dbmopen_ext'}", 0600);

   filelock($folderfile, LOCK_EX|LOCK_NB) or return -4;
   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      writelog("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      writehistory("db error - Couldn't update index db $headerdb$config{'dbm_ext'}");
      return -4;
   }
   open ($folderhandle, "+<$folderfile") or return -5;
   @allmessageids=get_messageids_sorted_by_offset($headerdb);
   if (!$config{'dbmopen_haslock'}) {
      filelock("$headerdb$config{'dbm_ext'}", LOCK_EX) or return -6;
   }
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", 0600);

   my ($blockstart, $blockend, $writepointer)=(0,0,0);
   my %filtered=();
   my %repeatlists=();

   for ($i=0; $i<=$#allmessageids; $i++) {
      my @attr = split(/@@@/, $HDB{$allmessageids[$i]});
      my ($currmessage, $header, $body, $r_attachments)=("", "", "", "");
      my ($is_message_parsed, $is_header_decoded, $is_body_decoded, $is_attachments_decoded)=(0,0,0,0);
      my ($r_smtprelays, $r_connectfrom, $r_byas);
      my $matched=0;
      my $reserved_in_inbox=0;
      my ($priority, $rules, $include, $text, $op, $destination, $enable);
      my $regexmatch=1;

      if ($filter_repeatlimit>0) {
         # store msgid with same '$from:$subject' to same array
         if (! defined($repeatlists{"$attr[$_FROM]:$attr[$_SUBJECT]"}) ) {
            my @a=();
            $repeatlists{"$attr[$_FROM]:$attr[$_SUBJECT]"}=\@a;
         }
         push (@{$repeatlists{"$attr[$_FROM]:$attr[$_SUBJECT]"}}, $allmessageids[$i] );
      }

      # if internal flag V not found,
      # this message has not been filtered before (Verify)
      if ($attr[$_STATUS] !~ /V/i || $newfilterrule) {
         if ($attr[$_STATUS] !~ /V/i) {
            $attr[$_STATUS].="V";
            $HDB{$allmessageids[$i]}=join('@@@', @attr);
         }

         ## if match filterrules => do $op (copy, move or delete)
         foreach my $line (sort @filterrules) {
            $matched=0;

            ($priority, $rules, $include, $text, $op, $destination, $enable) = split(/\@\@\@/, $line);
            $destination = safefoldername($destination);

            # check if current rule is enabled
            next unless ($enable == 1);
            next if ( $op ne 'copy' && $op ne 'move' && $op ne 'delete');

            if ($destination eq 'DELETE') {
               if ( $op eq 'copy' ) {
                  next;			# copy to DELETE is meaningless
               } elsif ($op eq 'move') {
                  $op='delete';		# move to DELETE is 'delete'
               }
            }

            if ( ($prefs_regexmatch||$IS_GLOBAL{$line}) && is_regex($text) ) { # do regex compare?
              $regexmatch=1;
            } else {
              $regexmatch=0;
            }

            if ( $rules eq 'from' || $rules eq 'to' || $rules eq 'subject' ) {
               my %index=(from=>$_FROM, to=>$_TO, subject=>$_SUBJECT);
               if (   ($include eq 'include' && $regexmatch && $attr[$index{$rules}] =~ /$text/i)
                   || ($include eq 'include' && $attr[$index{$rules}] =~ /\Q$text\E/i)
                   || ($include eq 'exclude' && $regexmatch && $attr[$index{$rules}] !~ /$text/i)
                   || ($include eq 'exclude' && $attr[$index{$rules}] !~ /\Q$text\E/i)  ) {
                  my ($matchcount, $matchdate)=split(":", $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"});
                  $matchcount++; $matchdate=localtime2dateserial();
                  $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$matchcount:$matchdate";

                  $matched=1;
                  if ($op eq 'delete') {
                     last;
                  } elsif ( $op eq 'move' || $op eq 'copy') {
                     if ($destination eq 'INBOX') {
                        $reserved_in_inbox=1;
                        last if ($op eq 'move');
                     }
                     if ($currmessage eq "") {
                        seek($folderhandle, $attr[$_OFFSET], 0);
                        read($folderhandle, $currmessage, $attr[$_SIZE]);
                     }
                     my $append=append_message_to_folder($allmessageids[$i],
   					\@attr, \$currmessage, $destination,
   					$r_validfolders, $user);
                     if ($op eq 'move') {
                        if ($append>=0) {
                           last;
                        } else {
                           $matched=0;	# match not counted if move failed
                        }
                     }
                  }
               }

            } elsif ( $rules eq 'header' ) {
               if ($currmessage eq "") {
                  seek($folderhandle, $attr[$_OFFSET], 0);
                  read($folderhandle, $currmessage, $attr[$_SIZE]);
               }
               if ($is_message_parsed==0) {
                  ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
                  $is_message_parsed=1;
               }
               if ($is_header_decoded==0) {
                  $header=decode_mimewords($header);
                  $is_header_decoded=1;
               }

               $header=~s/\n / /g;	# handle folding roughly
               if (  ( $include eq 'include' && $regexmatch && $header =~ /$text/im )
                   ||( $include eq 'include' && $header =~ /\Q$text\E/im )
                   ||( $include eq 'exclude' && $regexmatch && $header !~ /$text/im )
                   ||( $include eq 'exclude' && $header !~ /\Q$text\E/im ) ) {
                  my ($matchcount, $matchdate)=split(":", $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"});
                  $matchcount++; $matchdate=localtime2dateserial();
                  $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$matchcount:$matchdate";

                  $matched=1;
                  if ($op eq 'delete') {
                     last;
                  } elsif ( $op eq 'move' || $op eq 'copy') {
                     if ($destination eq 'INBOX') {
                        $reserved_in_inbox=1;
                        last if ($op eq 'move');
                     }
                     my $append=append_message_to_folder($allmessageids[$i],
   					\@attr, \$currmessage, $destination,
   					$r_validfolders, $user);
                     if ($op eq 'move') {
                        if ($append>=0) {
                           last;
                        } else {
                           $matched=0;	# match not counted if move failed
                        }
                     }
                  }
               }

            } elsif ( $rules eq 'smtprelay' ) {
               if ($currmessage eq "") {
                  seek($folderhandle, $attr[$_OFFSET], 0);
                  read($folderhandle, $currmessage, $attr[$_SIZE]);
               }
               if ($is_message_parsed==0) {
                  ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
                  $is_message_parsed=1;
               }
               if (!defined($r_smtprelays) ) {
                  ($r_smtprelays, $r_connectfrom, $r_byas)=get_smtprelays_connectfrom_byas($header);
               }
               my $smtprelays;
               foreach my $relay (@{$r_smtprelays}) {
                  $smtprelays.="$relay, ${$r_connectfrom}{$relay}, ${$r_byas}{$relay}, ";
               }
               if (  ( $include eq 'include' && $regexmatch && $smtprelays =~ /$text/im )
                   ||( $include eq 'include' && $smtprelays =~ /\Q$text\E/im )
                   ||( $include eq 'exclude' && $regexmatch && $smtprelays !~ /$text/im )
                   ||( $include eq 'exclude' && $smtprelays !~ /\Q$text\E/im ) ) {
                  my ($matchcount, $matchdate)=split(":", $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"});
                  $matchcount++; $matchdate=localtime2dateserial();
                  $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$matchcount:$matchdate";

                  $matched=1;
                  if ($op eq 'delete') {
                     last;
                  } elsif ( $op eq 'move' || $op eq 'copy') {
                     if ($destination eq 'INBOX') {
                        $reserved_in_inbox=1;
                        last if ($op eq 'move');
                     }
                     my $append=append_message_to_folder($allmessageids[$i],
   					\@attr, \$currmessage, $destination,
   					$r_validfolders, $user);
                     if ($op eq 'move') {
                        if ($append>=0) {
                           last;
                        } else {
                           $matched=0;	# match not counted if move failed
                        }
                     }
                  }
               }

            } elsif ( $rules eq 'textcontent' ) {
               if ($currmessage eq "") {
                  seek($folderhandle, $attr[$_OFFSET], 0);
                  read($folderhandle, $currmessage, $attr[$_SIZE]);
               }
               if ($is_message_parsed==0) {
                  ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
                  $is_message_parsed=1;
               }
               # check body text
               if ($is_body_decoded==0) {
                  if ( $attr[$_CONTENT_TYPE] =~ /^text/i ||
                       $attr[$_CONTENT_TYPE] eq "N/A" ) {	# read all for text/plain. text/html
                     if ( $header =~ /content-transfer-encoding:\s+quoted-printable/i) {
                        $body = decode_qp($body);
                     } elsif ($header =~ /content-transfer-encoding:\s+base64/i) {
                        $body = decode_base64($body);
                     } elsif ($header =~ /content-transfer-encoding:\s+x-uuencode/i) {
                        $body = uudecode($body);
                     }
                  }
                  $is_body_decoded=1;
               }

               if (  ( $include eq 'include' && $regexmatch && $body =~ /$text/im )
                   ||( $include eq 'exclude' && $body !~ /\Q$text\E/im )
                   ||( $include eq 'include' && $regexmatch && $body =~ /$text/im )
                   ||( $include eq 'exclude' && $body !~ /\Q$text\E/im ) ) {
                  my ($matchcount, $matchdate)=split(":", $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"});
                  $matchcount++; $matchdate=localtime2dateserial();
                  $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$matchcount:$matchdate";

                  $matched=1;
                  if ($op eq 'delete') {
                     last;
                  } elsif ( $op eq 'move' || $op eq 'copy') {
                     if ($destination eq 'INBOX') {
                        $reserved_in_inbox=1;
                        last if ($op eq 'move');
                     }
                     my $append=append_message_to_folder($allmessageids[$i],
   					\@attr, \$currmessage, $destination,
   					$r_validfolders, $user);
                     if ($op eq 'move') {
                        if ($append>=0) {
                           last;
                        } else {
                           $matched=0;	# match not counted if move failed
                        }
                     }
                  }
               }
               next if ($matched);

               # check attachments text
               if ($is_attachments_decoded==0) {
                  foreach my $r_attachment (@{$r_attachments}) {
                     if ( ${$r_attachment}{contenttype} =~ /^text/i ||
                          ${$r_attachment}{contenttype} eq "N/A" ) { # read all for text/plain. text/html
                        if ( ${$r_attachment}{encoding} =~ /^quoted-printable/i ) {
                           ${${$r_attachment}{r_content}} = decode_qp( ${${$r_attachment}{r_content}});
                        } elsif ( ${$r_attachment}{encoding} =~ /^base64/i ) {
                           ${${$r_attachment}{r_content}} = decode_base64( ${${$r_attachment}{r_content}});
                        } elsif ( ${$r_attachment}{encoding} =~ /^x-uuencode/i ) {
                           ${${$r_attachment}{r_content}} = uudecode( ${${$r_attachment}{r_content}});
                        }
                     }
                  }
                  $is_attachments_decoded=1;
               }
               foreach my $r_attachment (@{$r_attachments}) {
                  if ( ${$r_attachment}{contenttype} =~ /^text/i ||
                       ${$r_attachment}{contenttype} eq "N/A" ) { # read all for text/plain. text/html
                     if (  ( $include eq 'include' && $regexmatch && ${${$r_attachment}{r_content}} =~ /$text/im )
                         ||( $include eq 'include' && ${${$r_attachment}{r_content}} =~ /\Q$text\E/im )
                         ||( $include eq 'exclude' && $regexmatch && ${${$r_attachment}{r_content}} !~ /$text/im )
                         ||( $include eq 'exclude' && ${${$r_attachment}{r_content}} !~ /\Q$text\E/im )  ) {
                        my ($matchcount, $matchdate)=split(":", $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"});
                        $matchcount++; $matchdate=localtime2dateserial();
                        $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$matchcount:$matchdate";

                        $matched = 1;
                        last;	# leave attachments check from one message
                     }
                  }
               }
               if ($matched) {
                  if ($op eq 'delete') {
                     last;
                  } elsif ( $op eq 'move' || $op eq 'copy') {
                     if ($destination eq 'INBOX') {
                        $reserved_in_inbox=1;
                        last if ($op eq 'move');
                     }
                     my $append=append_message_to_folder($allmessageids[$i],
   					\@attr, \$currmessage, $destination,
   					$r_validfolders, $user);
                     if ($op eq 'move') {
                        if ($append>=0) {
                           last;
                        } else {
                           $matched=0;	# match not counted if move failed
                        }
                     }
                  }
               }

            } elsif ($rules eq 'attfilename') {
               if ($currmessage eq "") {
                  seek($folderhandle, $attr[$_OFFSET], 0);
                  read($folderhandle, $currmessage, $attr[$_SIZE]);
               }
               if ($is_message_parsed==0) {
                  ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
                  $is_message_parsed=1;
               }
               # check attachments
               foreach my $r_attachment (@{$r_attachments}) {
                  if (   ( $include eq 'include' && $regexmatch && ${$r_attachment}{filename} =~ /$text/i )
                       ||( $include eq 'include' && ${$r_attachment}{filename} =~ /\Q$text\E/i )
                       ||( $include eq 'exclude' && $regexmatch && ${$r_attachment}{filename} !~ /$text/i )
                       ||( $include eq 'exclude' && ${$r_attachment}{filename} !~ /\Q$text\E/i )  ) {
                     my ($matchcount, $matchdate)=split(":", $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"});
                     $matchcount++; $matchdate=localtime2dateserial();
                     $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$matchcount:$matchdate";

                     $matched = 1;
                     last;	# leave attachments check from one message
                  }
               }
               if ($matched) {
                  if ($op eq 'delete') {
                     last;
                  } elsif ( $op eq 'move' || $op eq 'copy') {
                     if ($destination eq 'INBOX') {
                        $reserved_in_inbox=1;
                        last if ($op eq 'move');
                     }
                     my $append=append_message_to_folder($allmessageids[$i],
   					\@attr, \$currmessage, $destination,
   					$r_validfolders, $user);
                     if ($op eq 'move') {
                        if ($append>=0) {
                           last;
                        } else {
                           $matched=0;	# match not counted if move failed
                        }
                     }
                  }
               }
            }

         } # end @filterrules

         # filter message with faked exe contenttype if msg is not moved or deleted
         if ( $filter_fakedexecontenttype &&
              !($matched && ($op eq 'move' || $op eq 'delete')) &&
              !$reserved_in_inbox ) {
            if ($currmessage eq "") {
               seek($folderhandle, $attr[$_OFFSET], 0);
               read($folderhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($is_message_parsed==0) {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
               $is_message_parsed=1;
            }
            # check executable attachment and contenttype
            foreach my $r_attachment (@{$r_attachments}) {
               if ( ${$r_attachment}{filename} =~ /\.(exe|com|bat|pif|lnk|scr)$/i &&
                    ${$r_attachment}{contenttype} !~ /application\/octet\-stream/i &&
                    ${$r_attachment}{contenttype} !~ /application\/x\-msdownload/i ) {
                  my ($matchcount, $matchdate)=split(":", $FTDB{"filter_fakedexecontenttype"});
                  $matchcount++; $matchdate=localtime2dateserial();
                  $FTDB{"filter_fakedexecontenttype"}="$matchcount:$matchdate";

                  $matched = 1;
                  last;	# leave attachments check from one message
               }
            }
            if ($matched) {
               my $append=append_message_to_folder($allmessageids[$i],
   					\@attr, \$currmessage, 'mail-trash',
   					$r_validfolders, $user);
               if ($append>=0) {
                  $op='move';
                  $matched=1;
               } else {
                  $matched=0;	# match not counted if move failed
               }
            }
         } # end of checking faked exe contenttype

         # filter message whose from: is different than the envelope email address
         if ( $filter_fakedfrom &&
              !($matched && ($op eq 'move' || $op eq 'delete')) &&
              !$reserved_in_inbox ) {
            if ($currmessage eq "") {
               seek($folderhandle, $attr[$_OFFSET], 0);
               read($folderhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($is_message_parsed==0) {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
               $is_message_parsed=1;
            }

            my $is_tmda=0;	# skip faked from check if TMDA msg
            if ($header=~/^\QX-Delivery-Agent: TMDA\E/m &&
                $header=~/^\QPrecedence: bulk\E/m &&
                $allmessageids[$i]=~/\Q.TMDA@\E/ ) {
               $is_tmda=1;
            }
            if (! $is_tmda) {
               my $envelopefrom="";
               foreach (split(/\n/, $header)) {
                  if (/\(envelope\-from ([^\s]+).*\)/) {
                     $envelopefrom=$1; last;
                  }
               }
               if ($envelopefrom eq "") {
                  $envelopefrom=$1 if ($header=~/^From ([^\s]+)/);
               }

               # compare user and domain independently
               my ($hdr_user, $hdr_domain)=split(/\@/, (email2nameaddr($attr[$_FROM]))[1]);
               my ($env_user, $env_domain)=split(/\@/, $envelopefrom);
               if ( $hdr_user ne $env_user ||
                   ($hdr_domain ne "" &&
                    $env_domain ne "" &&
                    $hdr_domain!~/\Q$env_domain\E/i &&
                    $env_domain!~/\Q$hdr_domain\E/i) ) {
                  my ($matchcount, $matchdate)=split(":", $FTDB{"filter_fakedfrom"});
                  $matchcount++; $matchdate=localtime2dateserial();
                  $FTDB{"filter_fakedfrom"}="$matchcount:$matchdate";

                  my $append=append_message_to_folder($allmessageids[$i],
      					\@attr, \$currmessage, 'mail-trash',
      					$r_validfolders, $user);
                  if ($append>=0) {
                     $op='move';
                     $matched=1;
                  }
               }
            }
         } # end of checking faked from

         # filter message from smtprelay with faked name if msg is not moved or deleted
         if ( $filter_fakedsmtp &&
              !($matched && ($op eq 'move' || $op eq 'delete')) &&
              !$reserved_in_inbox ) {
            if ($currmessage eq "") {
               seek($folderhandle, $attr[$_OFFSET], 0);
               read($folderhandle, $currmessage, $attr[$_SIZE]);
            }
            if ($is_message_parsed==0) {
               ($header, $body, $r_attachments)=parse_rfc822block(\$currmessage);
               $is_message_parsed=1;
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

               my $is_valid;
               my @compare=( namecompare($connectfrom, $relay),
                             namecompare($byas, $relay),
                             namecompare($connectfrom, $byas) );
               if ( $compare[0]>0 || $compare[1]>0 || $compare[2]>0 ||
                   ($compare[0]==0 && $compare[1]==0 && $compare[2]==0) ) {
                  $is_valid=1;
               } else {	# all <=0 and at least one < 0
                  $is_valid=0;
               }

               # the last relay is the mail server
               my $dstdomain=domain(${$r_smtprelays}[$#{$r_smtprelays}]);
#log_time("relay $relay");
#log_time("connectfrom $connectfrom");
#log_time("byas $byas");
#log_time("dstdomain $dstdomain");
#log_time("is_private $is_private");
#log_time("is_valid $is_valid\n");
               if ($connectfrom !~ /\Q$dstdomain\E/i &&
                   !$is_private &&
                   !$is_valid ) {
                  my ($matchcount, $matchdate)=split(":", $FTDB{"filter_fakedsmtp"});
                  $matchcount++; $matchdate=localtime2dateserial();
                  $FTDB{"filter_fakedsmtp"}="$matchcount:$matchdate";

                  my $append=append_message_to_folder($allmessageids[$i],
   					\@attr, \$currmessage, 'mail-trash',
   					$r_validfolders, $user);
                  if ($append>=0) {
                     $op='move';
                     $matched=1;
                  }
               }
            }
         } # end of checking faked smtp

      } # end of if msg not verified

      # remove msg from src folder for delete or after a successful move operation
      if ( $matched &&
           ($op eq 'move' || $op eq 'delete') &&
           !$reserved_in_inbox ) {
         ## remove message ##
         $filtered{'_ALL'}++;
         $filtered{$destination}++;

         my $messagestart=$attr[$_OFFSET];
         my $messagesize=$attr[$_SIZE];

         if (shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart)<0) {
            writelog("data error - msg $allmessageids[$i] in $folderfile shiftblock failed");
            writehistory("data error - msg $allmessageids[$i] in $folderfile shiftblock failed");
            $ioerr++;
         } else {
            $writepointer=$writepointer+($blockend-$blockstart);
            $blockstart=$blockend=$messagestart+$messagesize;

            delete $HDB{$allmessageids[$i]};

            $HDB{'NEWMESSAGES'}-- if ($attr[$_STATUS]!~/r/i);
            $HDB{'INTERNALMESSAGES'}-- if (is_internal_subject($attr[$_SUBJECT]));
            $HDB{'ALLMESSAGES'}--;
         }

      } else { # message not to move or destination can not write
         my $messagestart=$attr[$_OFFSET];
         my $messagesize=$attr[$_SIZE];
         $blockend=$messagestart+$messagesize;

         my $movement=$writepointer-$blockstart;
         if ($movement<0) {
            $attr[$_OFFSET]+=$movement;
            $HDB{$allmessageids[$i]}=join('@@@', @attr);
         }
      }

     last if ($ioerr);

   } ## end of allmessages ##

   if ($filtered{'_ALL'}>0 && !$ioerr) {
      if (shiftblock($folderhandle, $blockstart, $blockend-$blockstart, $writepointer-$blockstart)<0) {
         writelog("data error - msgs in $folderfile shiftblock failed");
         writehistory("data error - msgs in $folderfile shiftblock failed");
         $ioerr++;
      } else {
         seek($folderhandle, $writepointer+($blockend-$blockstart), 0);
         truncate($folderhandle, tell($folderhandle));
      }
   }
   close ($folderhandle);

   $HDB{'METAINFO'}=metainfo($folderfile) if (!$ioerr);
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

   if (!$ioerr) {
      # remove repeated msgs with repeated count > $filter_repeatlimit
      my (@repeatedids, $fromsubject, $r_ids);
      while ( ($fromsubject,$r_ids) = each %repeatlists) {
         push(@repeatedids, @{$r_ids}) if ($#{$r_ids}>=$filter_repeatlimit);
      }
      if ($#repeatedids>=0) {
         my $repeated;
         my ($trashfile, $trashdb)=get_folderfile_headerdb($user, 'mail-trash');

         filelock($trashfile, LOCK_EX|LOCK_NB) or return -7; 
         $repeated=operate_message_with_ids('move', \@repeatedids, $folderfile, $headerdb,
   							$trashfile, $trashdb);
         filelock($trashfile, LOCK_UN);

         $filtered{'_ALL'}=$repeated;

         my ($matchcount, $matchdate)=split(":", $FTDB{"filter_repeatlimit"});
         $matchcount+=$repeated; $matchdate=localtime2dateserial();
         $FTDB{"filter_repeatlimit"}="$matchcount:$matchdate";
      }
   }

   dbmclose(%FTDB);
   filelock("$folderdir/.filter.book$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

   filelock($folderfile, LOCK_UN);

   if (!$ioerr) {
      ## update .filter.check ##
      if (-f "$folderdir/.filter.check" ) {
         open (FILTERCHECK, ">$folderdir/.filter.check" ) or  return -8; 
         print FILTERCHECK metainfo($folderfile);
         truncate(FILTERCHECK, tell(FILTERCHECK));
         close (FILTERCHECK);
      } else {
         open (FILTERCHECK, ">$folderdir/.filter.check" ) or return -8;
         print FILTERCHECK metainfo($folderfile);
         close (FILTERCHECK);
      }

      return($filtered{'_ALL'}, \%filtered);
   } else {
      return -9;
   }
}


sub append_message_to_folder {
   my ($messageid, $r_attr, $r_currmessage, $destination,
	$r_validfolders, $user)=@_;
   my %HDB2;
   my ($dstfile, $dstdb)=get_folderfile_headerdb($user, $destination);
   my $ioerr=0;

   ($dstfile =~ /^(.+)$/) && ($dstfile = $1);  # untaint $dstfile
   ($dstdb =~ /^(.+)$/) && ($dstdb = $1);  # untaint $dstdb

   if (${$r_currmessage} !~ /^From /) { # msg format error
      return -1;
   }

   if (! -f $dstfile) {
      open (DEST, ">$dstfile") or return -2;
      close (DEST);
      push (@{$r_validfolders}, $destination);
   }

   filelock($dstfile, LOCK_EX|LOCK_NB) or return -3;

   if (update_headerdb($dstdb, $dstfile)<0) {
      filelock($dstfile, LOCK_UN);
      writelog("db error - Couldn't update index db $dstdb$config{'dbm_ext'}");
      writehistory("db error - Couldn't update index db $dstdb$config{'dbm_ext'}");
      return -4;
   }

   if (!$config{'dbmopen_haslock'}) {
      filelock("$dstdb$config{'dbm_ext'}", LOCK_EX) or return -5;
   }
   dbmopen (%HDB2, "$dstdb$config{'dbmopen_ext'}", 0600);
   if (!defined($HDB2{$messageid}) ) {	# append only if not found in dstfile
      if (! open(DEST, ">>$dstfile")) {
         dbmclose(%HDB2);
         filelock("$dstdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
         filelock($dstfile, LOCK_UN);
         return -6;
      }
      seek(DEST, 0, 2);	# seek end explicitly to cover tell() bug in perl 5.8
      my @attr2=@{$r_attr};
      $attr2[$_OFFSET]=tell(DEST);
      $attr2[$_SIZE]=length(${$r_currmessage});
      print DEST ${$r_currmessage} || $ioerr++;
      close (DEST);

      if (!$ioerr) {
         $HDB2{$messageid}=join('@@@', @attr2);
         $HDB2{'NEWMESSAGES'}++ if ($attr2[$_STATUS]!~/r/i);
         $HDB2{'INTERNALMESSAGES'}++ if (is_internal_subject($attr2[$_SUBJECT]));
         $HDB2{'ALLMESSAGES'}++;
         $HDB2{'METAINFO'}=metainfo($dstfile);
      }
   }
   dbmclose(%HDB2);

   filelock("$dstdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   filelock($dstfile, LOCK_UN);
   return 0;
}


sub get_smtprelays_connectfrom_byas {
   my $header=$_[0];
   my @smtprelays=();
   my %connectfrom=();
   my %byas=();
   my ($lastline, $received, $tmp);

   foreach (split(/\n/, $header)) {
      if (/^\s/ && $lastline eq 'RECEIVED') {
         s/^\s+/ /;
         $received .= $_;
      } elsif (/^Received:(.+)$/ig) {
         $tmp=$1;
         # skip Received: line for MTA internal usage, eg:
         # Received: (qmail 16577 invoked from network); 19 Apr 2002 18:09:43 +0200
         if ($tmp=~/^\s*\(.+?\);/) {
            $lastline = 'NONE';
            next;
         }
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

# hostname compare for loosely equal
# >0 match, <0 unmatch, ==0 unknow
sub namecompare {
   my ($a, $b)=@_;

   # no compare if any one is empty
   return  0 if ($a =~/^\s*$/ || $b =~/^\s*$/ );

   # chk if both names are invalid
   if ($a =~ /[\d\w\-_]+[\.\@][\d\w\-_]+/) {
      if ($b =~ /[\d\w\-_]+[\.\@][\d\w\-_]+/ ) {	# a,b are long
         # chk if any names conatains another
         return 1 if ($a=~/\Q$b\E/i || $b=~/\Q$a\E/i);
         # chk if both names belongs to same domain
         $a=domain( (split(/\s/, $a))[0] );
         $b=domain( (split(/\s/, $b))[0] );
         return 1 if ($a eq $b && $a =~/[\d\w\-_]+\.[\d\w\-_]+/);
      } else {						# a long, b short
         $b=(split(/\s/, $b))[0];
         return 1 if ($a=~/^\Q$b\E\./i || $a=~/\@\Q$b\E/ );
      }
   } else {
      if ($b =~ /[\d\w\-_]+[\.\@][\d\w\-_]+/ ) {	# a short, b long
         $a=(split(/\s/, $a))[0];
         return 1 if ($b=~/^\Q$a\E\./i || $b=~/\@\Q$a\E/ );
      } else {						# a, b are short
         return 0 if ($a eq $b);
      }
   }
   return -1;
}

# return domain part of a FQDN
sub domain {
   my @h=split(/\./, $_[0]);
   shift (@h);
   return(join(".", @h));
}

1;
