#
# mailfilter.pl - filter INBOX messages at background
#
# 2004/07/23 tung.AT.turtle.ee.ncku.edu.tw
#            Ebola.AT.turtle.ee.ncku.edu.tw
#
# There are 4 types of checks in this mail filter
#
# 1. external viruscheck (clamav)
# 2. static global and user defined rules
# 3. external spamcheck (spamassassin)
# 4. smart filter rules
#

use strict;
use Fcntl qw(:DEFAULT :flock);
use MIME::Base64;
use MIME::QuotedPrint;

# extern vars
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET $_HEADERSIZE $_HEADERCHKSUM);
use vars qw(%config %lang_err);

# local global
use vars qw ($_PRIORITY $_RULETYPE $_INCLUDE $_TEXT $_OP $_DESTINATION $_ENABLE $_REGEX_TEXT);
($_PRIORITY, $_RULETYPE, $_INCLUDE, $_TEXT, $_OP, $_DESTINATION, $_ENABLE, $_REGEX_TEXT)=(0,1,2,3,4,5,6,7);

use vars qw(%op_order %ruletype_order %folder_order);	# rule prefered order, the smaller one is prefered
%op_order=(
   copy   => 0,
   move   => 1,
   delete => 2,
);
%ruletype_order=(
   from        => 0,
   to          => 1,
   subject     => 2,
   header      => 3,
   smtprelay   => 4,
   attfilename => 5,
   textcontent => 6
);
%folder_order=(		# folders not listed have order 0
   INBOX        => -1,
   DELETE       => 1,
   'virus-mail' => 2,
   'spam-mail'  => 3,
   'mail-trash' => 4
);

########## FILTERMESSAGE #########################################
# filter inbox messages in background
# return: 0 filtere not necessary
#         1 background filtering started
# there are 4 op for a msg: 'copy', 'move', 'delete' and 'keep'
use vars qw($_filter_complete);
sub filtermessage {
   my ($user, $folder, $r_prefs)=@_;

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   return 0 if ( ! -f $folderfile );	# check existence of folderfile

   my $forced_recheck=0;
   my $filtercheckfile=dotpath('filter.check');
   my $filterbookfile=dotpath('filter.book');
   my (@filterfiles, @filterrules);

   # automic 'test & set' the metainfo value in filtercheckfile
   my $metainfo=ow::tool::metainfo($folderfile);
   if (!-f $filtercheckfile) {
      open(F, ">>$filtercheckfile"); close(F);
      $forced_recheck=1;	# new filterrule added?, so do filtering on all msg
   }
   ow::filelock::lock($filtercheckfile, LOCK_EX) or
      openwebmailerror("$lang_err{'couldnt_lock'} $filtercheckfile");
   if (!open(FILTERCHECK, $filtercheckfile)) {
      ow::filelock::lock($filtercheckfile, LOCK_UN);
      openwebmailerror("$lang_err{'couldnt_open'} $filtercheckfile");
   }
   $_=<FILTERCHECK>;
   close(FILTERCHECK);
   if ($_ eq $metainfo) {
      ow::filelock::lock($filtercheckfile, LOCK_UN);
      return 0;
   }
   if (!open(FILTERCHECK, ">$filtercheckfile")) {
      ow::filelock::lock($filtercheckfile, LOCK_UN);
      openwebmailerror("$lang_err{'couldnt_open'} $filtercheckfile");
   }
   print FILTERCHECK $metainfo;
   close (FILTERCHECK);
   ow::filelock::lock($filtercheckfile, LOCK_UN);

   # get @filterrules
   push(@filterfiles, $filterbookfile)              if ($config{'enable_userfilter'} && -f $filterbookfile);
   push(@filterfiles, $config{'global_filterbook'}) if ($config{'enable_globalfilter'} && -f $config{'global_filterbook'});
   foreach my $filterfile (@filterfiles) {
      open (FILTER, $filterfile) or next;
      while (<FILTER>) {
         chomp($_);
         if (/^\d+\@\@\@/) { # add valid rule only
            my @rule=split(/\@\@\@/);
            next if (!$rule[$_ENABLE]||
                     $rule[$_OP] ne 'copy' && $rule[$_OP] ne 'move' && $rule[$_OP] ne 'delete');

            $rule[$_DESTINATION]=safefoldername($rule[$_DESTINATION]);
            next if (!is_defaultfolder($rule[$_DESTINATION]) && 
                     !$config{'enable_userfolders'});

            if ($rule[$_DESTINATION] eq 'DELETE') {
               next if ($rule[$_OP] eq 'copy');			# copy to DELETE is meaningless
               $rule[$_OP]='delete' if ($rule[$_OP] eq 'move');	# move to DELETE is 'delete'
            }

            # precompile text into regex for speed
            if ( (${$r_prefs}{'regexmatch'} || $filterfile eq $config{'global_filterbook'}) &&
                 ow::tool::is_regex($rule[$_TEXT]) ) {	# do regex compare?
               $rule[$_REGEX_TEXT]=qr/$rule[$_TEXT]/im;
            } else {
               $rule[$_REGEX_TEXT]=qr/\Q$rule[$_TEXT]\E/im;
            }
            push(@filterrules, \@rule);
         }
      }
      close (FILTER);
   }

   # sort rules by priority, the smaller the top
   @filterrules=sort {
                     ${$a}[$_PRIORITY]                   <=> ${$b}[$_PRIORITY]                   or
                     $op_order{${$a}[$_OP]}              <=> $op_order{${$b}[$_OP]}              or
                     $ruletype_order{${$a}[$_RULETYPE]}  <=> $ruletype_order{${$b}[$_RULETYPE]}  or
                     $folder_order{${$a}[$_DESTINATION]} <=> $folder_order{${$b}[$_DESTINATION]}
                     } @filterrules;

   if ($#filterrules<0 && 
       !$config{'enable_smartfilter'} && 
       !$config{'enabel_viruscheck'} &&
       !$config{'enable_spamcheck'}) {
      return 1;				# return immediately if nothing to do
   }

   my (@allmessageids);
   my %repeatlists=();
   my %FDB;

   my ($io_errcount, $viruscheck_errcount, $spamcheck_errcount)=(0, 0);
   my ($lockget_err, $lockget_errmsg);
   my ($appended, $append_errmsg)=(0, '');

   ($lockget_err, $lockget_errmsg)=lockget_messageids($folderfile, $folderdb, \@allmessageids);
   if ($lockget_err<0) {
      my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
      openwebmailerror("$lang_err{'mailfilter_error'} ($lockget_errmsg)");;
   }

   local $_filter_complete=0;
   local $SIG{CHLD} = sub { wait; $_filter_complete=1 if ($?==0) };	# handle zombie
   local $|=1; # flush all output

   if ( fork() == 0 ) {		# child
      close(STDIN); close(STDOUT); close(STDERR);
      ow::suid::drop_ruid_rgid(); # set ruid=euid to avoid fork in spamcheck.pl

      if ($config{'log_filter_detail'}) {
         my $m="mailfilter - bg process forked"; writelog($m); writehistory($m);
      }

      my $pidfile=dotpath('filter.pid');
      open(F, ">$pidfile"); print F $$; close(F);

      my $repeatstarttime=time()-86400;	# only count repeat for messages within one day
      my %is_verified=();
      my $i=$#allmessageids;
      while ($i>=0) {
         if ($config{'log_filter_detail'}) {
            my $m="mailfilter - loop $i, msgid=$allmessageids[$i]"; writelog($m); writehistory($m);
         }

         if ($is_verified{$allmessageids[$i]} ||	# skip already verified msg
             $allmessageids[$i]=~/^DUP\d+\-/ ) {	# skip duplicated msg in src folder
            $i--; next;
         }
         last if ($io_errcount>=3);

         # terminated if other filter process is active on same folder
         open(F, $pidfile); $_=<F>; close(F);
         if ($_ ne $$) {
            my $m="mailfilter - terminated - reason: another filter pid=$_ is avtive."; writelog($m);
            openwebmail_exit(0);
         }

         # reload messageids if folder is changed
         my $curr_metainfo=ow::tool::metainfo($folderfile);
         if ($metainfo ne $curr_metainfo) {
            ($lockget_err, $lockget_errmsg)=lockget_messageids($folderfile, $folderdb, \@allmessageids);
            if ($lockget_err<0) {
               my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
               openwebmail_exit(0);
            } else {
               my $m="mailfilter - reload $#allmessageids msgids - reason: $folder is changed"; writelog($m);
            }

            if (!open(FILTERCHECK, ">$filtercheckfile")) {
               my $m="mailfilter - $filtercheckfile open error"; writelog($m); writehistory($m);
               openwebmail_exit(0);
            }
            print FILTERCHECK $curr_metainfo;
            close (FILTERCHECK);

            $metainfo=$curr_metainfo;
            $i=$#allmessageids; next;
         }

         my ($headersize, $header, $decoded_header, $currmessage, $body)=(0, "", "", "", "");
         my (%msg, $r_attachments, $r_smtprelays, $r_connectfrom, $r_byas);
         my ($is_body_decoded, $is_attachments_decoded)=(0, 0);
         my ($reserved_in_folder, $to_be_moved)=(0, 0);

         my @attr = get_message_attributes($allmessageids[$i], $folderdb);
         if ($#attr<0) {	# msg not found in db
            $i--; next;
         }
         if (is_internal_subject($attr[$_SUBJECT]) || $attr[$_STATUS]=~/Z/i) {	# skip internal or zapped
            $is_verified{$allmessageids[$i]}=1;
            $i--; next;
         }

         # if flag V not found, this msg has not been filtered before (Verify)
         if ($attr[$_STATUS] !~ /V/i || $forced_recheck) {
            # 0. read && check msg header
            ($lockget_err, $lockget_errmsg)=lockget_message_header($allmessageids[$i], $folderfile, $folderdb, \$header);
            if ($lockget_err<0) {
               my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
               mark_folderdb_err($folderdb) if ($lockget_err<=-3);
               $io_errcount++; $i--; next;
            }

            if ($config{'log_filter_detail'}) {
               my $m="mailfilter - check $allmessageids[$i], subject=$attr[$_SUBJECT]"; writelog($m); writehistory($m);
            }

            if ($attr[$_STATUS] !~ /V/i) {
               ow::dbm::open(\%FDB, $folderdb, LOCK_EX);
               $attr[$_STATUS].="V";
               $FDB{$allmessageids[$i]}=msgattr2string(@attr);
               ow::dbm::close(\%FDB, $folderdb);
            }
            # 1. virus check
            if ($config{'enable_viruscheck'} && !$to_be_moved) {
               if ($config{'log_filter_detail'}) {
                  my $m="mailfilter - viruscheck $allmessageids[$i]"; writelog($m); writehistory($m);
               }

               my $virusfound=0;
               if ($header=~/^X\-OWM\-VirusCheck: ([a-z]+)/m) {		# virus checked in fetchmail.pl
                  $virusfound=1 if ($1 eq 'virus');
               } elsif (${$r_prefs}{'viruscheck_source'} eq 'all' &&	# to be checked here
                        !$viruscheck_errcount &&
                        $attr[$_SIZE] <= ${$r_prefs}{'viruscheck_maxsize'}*1024 &&
                        $attr[$_SIZE]-$attr[$_HEADERSIZE] > ${$r_prefs}{'viruscheck_minbodysize'}*1024 ) {
                  if ($currmessage eq "") {
                     ($lockget_err, $lockget_errmsg)=lockget_message_block($allmessageids[$i], $folderfile, $folderdb, \$currmessage);
                     if ($lockget_err<0) {
                        my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
                        mark_folderdb_err($folderdb) if ($lockget_err<=-3);
                        $io_errcount++; $i--; next;
                     }
                  }
                  my ($ret, $err)=ow::viruscheck::scanmsg($config{'viruscheck_pipe'}, \$currmessage);
                  if ($ret<0) {
                     my $m="viruscheck - pipe error - $err"; writelog($m); writehistory($m);
                     $viruscheck_errcount++;
                  } elsif ($ret>0) {
                     my $m="viruscheck - virus $err found in msg $allmessageids[$i]"; writelog($m); writehistory($m);
                     $virusfound=1;
                  }
               }
               if ($virusfound) {
                  ($appended, $append_errmsg)=append_filteredmsg_to_folder($folderfile, $folderdb,
				$allmessageids[$i], \@attr, \$currmessage, $user, $config{'virus_destination'});
                  if ($appended >=0) {
                     if ($config{'log_filter_detail'}) {
                        my $m="mailfilter - move $allmessageids[$i] -> $config{'virus_destination'}"; writelog($m); writehistory($m);
                     }
                     filterfolderdb_increase($config{'virus_destination'}, 1);
                     $to_be_moved=1;
                  } else {
                     my $m="mailfilter - $config{'virus_destination'} write error"; writelog($m); writehistory($m);
                     $io_errcount++;
                  }
               }
            }

            # 2. static filter rules (including global and personal rules)
            if (!$to_be_moved) {
               if ($config{'log_filter_detail'}) {
                  my $m="mailfilter - static rules check $allmessageids[$i]"; writelog($m); writehistory($m);
               }
               foreach my $r_rule (@filterrules) {
                  my $ruletype=${$r_rule}[$_RULETYPE];
                  my $is_matched=0;

                  if ( $ruletype eq 'from' || $ruletype eq 'to' || $ruletype eq 'subject') {
                     if ($decoded_header eq "") {
                        $decoded_header=decode_mimewords_iconv($header, $attr[$_CHARSET]);
                        $decoded_header=~s/\s*\n\s+/ /sg; # concate folding lines
                     }
                     if (!defined($msg{from})) { # this is defined after parse_header is called
                        ow::mailparse::parse_header(\$decoded_header, \%msg);
                     }
                     if ($msg{$ruletype}=~/${$r_rule}[$_REGEX_TEXT]/
                         xor ${$r_rule}[$_INCLUDE] eq 'exclude') {
                         $is_matched=1;
                     }

                  } elsif ( $ruletype eq 'header' ) {
                     if ($decoded_header eq "") {
                        $decoded_header=decode_mimewords_iconv($header, $attr[$_CHARSET]);
                        $decoded_header=~s/\s*\n\s+/ /sg; # concate folding lines
                     }
                     if ($decoded_header=~/${$r_rule}[$_REGEX_TEXT]/
                         xor ${$r_rule}[$_INCLUDE] eq 'exclude') {
                         $is_matched=1;
                     }

                  } elsif ( $ruletype eq 'smtprelay' ) {
                     if (!defined($r_smtprelays) ) {
                        ($r_smtprelays, $r_connectfrom, $r_byas)=ow::mailparse::get_smtprelays_connectfrom_byas_from_header($header);
                     }
                     my $smtprelays;
                     foreach my $relay (@{$r_smtprelays}) {
                        $smtprelays.="$relay, ${$r_connectfrom}{$relay}, ${$r_byas}{$relay}, ";
                     }
                     if ($smtprelays=~/${$r_rule}[$_REGEX_TEXT]/
                         xor ${$r_rule}[$_INCLUDE] eq 'exclude') {
                         $is_matched=1;
                     }

                  } elsif ( $ruletype eq 'textcontent' ) {
                     if ($currmessage eq "") {
                        ($lockget_err, $lockget_errmsg)=lockget_message_block($allmessageids[$i], $folderfile, $folderdb, \$currmessage);
                        if ($lockget_err<0) {
                           my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
                           mark_folderdb_err($folderdb) if ($lockget_err<=-3);
                           $io_errcount++; $i--; next;
                        }
                     }
                     if (!defined(@{$r_attachments})) {
                        ($header, $body, $r_attachments)=ow::mailparse::parse_rfc822block(\$currmessage);
                     }

                     # check body text
                     if (!$is_body_decoded) {
                        if ( $attr[$_CONTENT_TYPE] =~ /^text/i ||
                             $attr[$_CONTENT_TYPE] eq 'N/A' ) {	# for text/plain. text/html
                           if ( $header =~ /content-transfer-encoding:\s+quoted-printable/i) {
                              $body = decode_qp($body);
                           } elsif ($header =~ /content-transfer-encoding:\s+base64/i) {
                              $body = decode_base64($body);
                           } elsif ($header =~ /content-transfer-encoding:\s+x-uuencode/i) {
                              $body = ow::mime::uudecode($body);
                           }
                        }
                        $is_body_decoded=1;
                     }
                     if ( $attr[$_CONTENT_TYPE] =~ /^text/i ||
                          $attr[$_CONTENT_TYPE] eq 'N/A' ) {		# for text/plain. text/html
                        if ($body=~/${$r_rule}[$_REGEX_TEXT]/
                            xor ${$r_rule}[$_INCLUDE] eq 'exclude') {
                            $is_matched=1;
                        }
                     }

                     # check attachments text if body text not match
                     if (!$is_matched) {
                        if (!$is_attachments_decoded) {
                           foreach my $r_attachment (@{$r_attachments}) {
                              if ( ${$r_attachment}{'content-type'} =~ /^text/i ||
                                   ${$r_attachment}{'content-type'} eq "N/A" ) { # read all for text/plain. text/html
                                 if ( ${$r_attachment}{'content-transfer-encoding'} =~ /^quoted-printable/i ) {
                                    ${${$r_attachment}{r_content}} = decode_qp( ${${$r_attachment}{r_content}});
                                 } elsif ( ${$r_attachment}{'content-transfer-encoding'} =~ /^base64/i ) {
                                    ${${$r_attachment}{r_content}} = decode_base64( ${${$r_attachment}{r_content}});
                                 } elsif ( ${$r_attachment}{'content-transfer-encoding'} =~ /^x-uuencode/i ) {
                                    ${${$r_attachment}{r_content}} = ow::mime::uudecode( ${${$r_attachment}{r_content}});
                                 }
                              }
                           }
                           $is_attachments_decoded=1;
                        }
                        foreach my $r_attachment (@{$r_attachments}) {
                           if ( ${$r_attachment}{'content-type'} =~ /^text/i ||
                                ${$r_attachment}{'content-type'} eq "N/A" ) { # read all for text/plain. text/html
                              if (${${$r_attachment}{r_content}}=~/${$r_rule}[$_REGEX_TEXT]/
                                  xor ${$r_rule}[$_INCLUDE] eq 'exclude') {
                                 $is_matched=1;
                                 last;	# leave attachments loop of this msg
                              }
                           }
                        }
                     } # end !$is_matched bodytext

                  } elsif ($ruletype eq 'attfilename') {
                     if ($currmessage eq "") {
                        ($lockget_err, $lockget_errmsg)=lockget_message_block($allmessageids[$i], $folderfile, $folderdb, \$currmessage);
                        if ($lockget_err<0) {
                           my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
                           mark_folderdb_err($folderdb) if ($lockget_err<=-3);
                           $io_errcount++; $i--; next;
                        }
                     }
                     if (!defined(@{$r_attachments})) {
                        ($header, $body, $r_attachments)=ow::mailparse::parse_rfc822block(\$currmessage);
                     }
                     # check attachments
                     foreach my $r_attachment (@{$r_attachments}) {
                        if (${$r_attachment}{filename}=~/${$r_rule}[$_REGEX_TEXT]/
                            xor ${$r_rule}[$_INCLUDE] eq 'exclude') {
                           $is_matched=1;
                           last;	# leave attachments loop of this msg
                        }
                     }
                  }

                  if ($is_matched) {
                     # cp msg to other folder and set reserved_in_folder or to_be_moved flag
                     my $rulestr=join('@@@', @{$r_rule}[$_RULETYPE, $_INCLUDE, $_TEXT, $_DESTINATION]);

                     filterruledb_increase($rulestr, 1);

                     if ( ${$r_rule}[$_OP] eq 'move' || ${$r_rule}[$_OP] eq 'copy') {
                        if (${$r_rule}[$_DESTINATION] eq $folder) {
                           $reserved_in_folder=1;
                        } else {
                           ($appended, $append_errmsg)=append_filteredmsg_to_folder($folderfile, $folderdb,
					$allmessageids[$i], \@attr, \$currmessage, $user, ${$r_rule}[$_DESTINATION]);
                        }
                     }

                     if (${$r_rule}[$_OP] eq 'move' || ${$r_rule}[$_OP] eq 'delete') {
                        if ($appended>=0) {
                           if (!$reserved_in_folder) {
                              if ($config{'log_filter_detail'}) {
                                 my $m="mailfilter - move $allmessageids[$i] -> ${$r_rule}[$_DESTINATION] (rule: ${$r_rule}[$_RULETYPE] ${$r_rule}[$_INCLUDE] ${$r_rule}[$_TEXT])"; writelog($m); writehistory($m);
                              }
                              $to_be_moved=1;
                              filterfolderdb_increase(${$r_rule}[$_DESTINATION], 1);
                           }
                        } else {
                           my $m="mailfilter - ${$r_rule}[$_DESTINATION] write error"; writelog($m); writehistory($m);
                           $io_errcount++;
                        }
                        last;
                     }
                     # try next rule if mesg is not moved/deleted or io err
                  }
               } # end @filterrules
            }

            # 3. spam check
            if ($config{'enable_spamcheck'} && !$reserved_in_folder && !$to_be_moved) {
               if ($config{'log_filter_detail'}) {
                  my $m="mailfilter - spamcheck $allmessageids[$i]"; writelog($m); writehistory($m);
               }

               my $spamfound=0;
               if ($header=~/^X\-OWM\-SpamCheck: \** ([\d\.]+)/m) {	# spam checked in fetchmail.pl
                  $spamfound=1 if ($1 > ${$r_prefs}{'spamcheck_threshold'});
               } elsif (${$r_prefs}{'spamcheck_source'} eq 'all' && 		# to be checked here
                        !$spamcheck_errcount &&
                        $attr[$_SIZE] <= ${$r_prefs}{'spamcheck_maxsize'}*1024) {
                  if ($currmessage eq "") {
                     ($lockget_err, $lockget_errmsg)=lockget_message_block($allmessageids[$i], $folderfile, $folderdb, \$currmessage);
                     if ($lockget_err<0) {
                        my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
                        mark_folderdb_err($folderdb) if ($lockget_err<=-3);
                        $io_errcount++; $i--; next;
                     }
                  }
                  my ($spamlevel, $err)=ow::spamcheck::scanmsg($config{'spamcheck_pipe'}, \$currmessage);
                  if ($spamlevel==-99999) {
                     my $m="spamscheck - pipe error - $err"; writelog($m); writehistory($m);
                     $spamcheck_errcount++;
                  } elsif ($spamlevel > ${$r_prefs}{'spamcheck_threshold'}) {
                     my $m="spamcheck - spam $spamlevel/${$r_prefs}{'spamcheck_threshold'} found in msg $allmessageids[$i]";
                     writelog($m); writehistory($m);
                     $spamfound=1;
                  }
               }
               if ($spamfound) {
                  ($appended, $append_errmsg)=append_filteredmsg_to_folder($folderfile, $folderdb,
				$allmessageids[$i], \@attr, \$currmessage, $user, $config{'spam_destination'});
                  if ($appended >=0) {
                     if ($config{'log_filter_detail'}) {
                        my $m="mailfilter - move $allmessageids[$i] -> $config{'spam_destination'}"; writelog($m); writehistory($m);
                     }
                     filterfolderdb_increase($config{'spam_destination'}, 1);
                     $to_be_moved=1;
                  } else {
                     my $m="mailfilter - $config{'spam_destination'} write error"; writelog($m); writehistory($m);
                     $io_errcount++;
                  }
               }
            }

            # 4. smart filter rules
            if ($config{'enable_smartfilter'} && !$reserved_in_folder && !$to_be_moved) {
               if ($config{'log_filter_detail'}) {
                  my $m="mailfilter - smart rules check $allmessageids[$i]"; writelog($m); writehistory($m);
               }

               # bypass smart filters for good messages
               if ($config{'smartfilter_bypass_goodmessage'} &&
                   !$reserved_in_folder && !$to_be_moved ) {
                  if ( ($header=~/^X\-Mailer: Open WebMail/m && $header=~/^X\-OriginatingIP: /m) ||
                       ($header=~/^In\-Reply\-To: /m && $header=~/^References: /m) ) {
                     $reserved_in_folder=1;
                  }
               }

               # since if any smartrule matches, other smartrule would be skipped
               # so we use only one variable to record the matched smartrule.
               my $matchedsmartrule;	

               # filter message with bad format from if msg is not moved or deleted
               if (${$r_prefs}{'filter_badaddrformat'} &&
                   !$reserved_in_folder && !$to_be_moved ) {
                  my $badformat=0;
                  my $fromaddr=(ow::tool::email2nameaddr($attr[$_FROM]))[1]; $fromaddr=~s/\@.*$//;
                  if ($fromaddr=~/[^\d\w\-\._]/ ||
                      $fromaddr=~/^\d/ ||
                      ($fromaddr=~/\d/ && $fromaddr=~/\./) ) {
                     $badformat=1;
                  }
                  my ($toname, $toaddr)=ow::tool::email2nameaddr($attr[$_TO]);
                  if ($toname=~/undisclosed-recipients/i && $toaddr=~/\@/) {
                     $badformat=1;
                  }
                  if ($badformat) {
                     $matchedsmartrule='filter_badaddrformat';
                     $to_be_moved=1;
                  }
               } # end of checking bad format from

               # filter message whose from: is different than the envelope email address
               if ( ${$r_prefs}{'filter_fakedfrom'} &&
                   !$reserved_in_folder && !$to_be_moved ) {
                  my $is_software_generated=0;	# skip faked from check for msg generated by some software
                  if ( ($header=~/^\QX-Delivery-Agent: TMDA\E/m &&
                        $header=~/^\QPrecedence: bulk\E/m &&
                        $allmessageids[$i]=~/\Q.TMDA@\E/) ||	# TMDA
                       ($header=~/^\QManaged-by: RT\E/m &&
                        $header=~/^\QRT-Ticket: \E/m &&
                        $header=~/^\QPrecedence: bulk\E/m) ) {	# Request Tracker
                     $is_software_generated=1;
                  }
                  if (!$is_software_generated) {
                     my $envelopefrom='';
                     $envelopefrom=$1 if ($header=~/\(envelope\-from (\S+).*?\)/s);
                     $envelopefrom=$1 if ($envelopefrom eq "" && $header=~/^From (\S+)/);

                     # compare user and domain independently
                     my ($hdr_user, $hdr_domain)=split(/\@/, (ow::tool::email2nameaddr($attr[$_FROM]))[1]);
                     my ($env_user, $env_domain)=split(/\@/, $envelopefrom);
                     if ($hdr_user ne $env_user ||
                         ($hdr_domain ne "" && $env_domain ne "" &&
                          $hdr_domain!~/\Q$env_domain\E/i &&
                          $env_domain!~/\Q$hdr_domain\E/i) ) {
                        $matchedsmartrule='filter_fakedfrom';
                        $to_be_moved=1;
                     }
                  }
               } # end of checking fakedfrom

               # filter message from smtprelay with faked name if msg is not moved or deleted
               if ( ${$r_prefs}{'filter_fakedsmtp'} &&
                   !$reserved_in_folder && !$to_be_moved ) {
                  if (!defined($r_smtprelays) ) {
                     ($r_smtprelays, $r_connectfrom, $r_byas)=ow::mailparse::get_smtprelays_connectfrom_byas_from_header($header);
                  }
                  # move msg to trash if the first relay has invalid/faked hostname
                  if ( defined(${$r_smtprelays}[0]) ) {
                     my $relay=${$r_smtprelays}[0];
                     my $connectfrom=${$r_connectfrom}{$relay};
                     my $byas=${$r_byas}{$relay};
                     my $is_private=0; $is_private=1 if ($connectfrom =~ /(?:\[10|\[172\.[1-3][0-9]|\[192\.168|\[127\.0)\./);

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
                     if ($connectfrom !~ /\Q$dstdomain\E/i &&
                         !$is_private && !$is_valid ) {
                        $matchedsmartrule='filter_fakedsmtp';
                        $to_be_moved=1;
                     }
                  }
               } # end of checking fakedsmtp

               # filter message with faked exe contenttype if msg is not moved or deleted
               if (${$r_prefs}{'filter_fakedexecontenttype'} &&
                   !$reserved_in_folder && !$to_be_moved ) {
                  if ($currmessage eq "") {
                     ($lockget_err, $lockget_errmsg)=lockget_message_block($allmessageids[$i], $folderfile, $folderdb, \$currmessage);
                     if ($lockget_err<0) {
                        my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
                        mark_folderdb_err($folderdb) if ($lockget_err<=-3);
                        $io_errcount++; $i--; next;
                     }
                  }
                  if (!defined(@{$r_attachments})) {
                     ($header, $body, $r_attachments)=ow::mailparse::parse_rfc822block(\$currmessage);
                  }

                  # check executable attachment and contenttype
                  my $att_matched;
                  foreach my $r_attachment (@{$r_attachments}) {
                     if ( ${$r_attachment}{filename} =~ /\.(?:exe|com|bat|pif|lnk|scr)$/i &&
                          ${$r_attachment}{'content-type'} !~ /application\/octet\-stream/i &&
                          ${$r_attachment}{'content-type'} !~ /application\/x\-msdownload/i ) {
                        $matchedsmartrule='filter_fakedexecontenttype';
                        $to_be_moved=1;
                        last;	# leave attachments loop of this msg
                     }
                  }
               } # end of checking fakedexecontenttype

               if ($matchedsmartrule ne "") {
                  filterruledb_increase($matchedsmartrule, 1);
                  ($appended, $append_errmsg)=append_filteredmsg_to_folder($folderfile, $folderdb,
				$allmessageids[$i], \@attr, \$currmessage, $user, 'mail-trash');
                  if ($appended>=0) {
                     if ($config{'log_filter_detail'}) {
                        my $m="mailfilter - move $allmessageids[$i] -> mail-trash (smartrule: $matchedsmartrule)"; writelog($m); writehistory($m);
                     }
                     filterfolderdb_increase('mail-trash', 1);
                  } else {
                     my $m="mailfilter - mail-trash write error"; writelog($m); writehistory($m);
                     $io_errcount++; $to_be_moved=0;
                     last;
                  }
               }
            } # end of if enable_smartfilter

            # 5. mark to be moved message as zap
            if ($to_be_moved) {
               ow::dbm::open(\%FDB, $folderdb, LOCK_EX);
               if ($attr[$_STATUS]!~/Z/i) {
                  $attr[$_STATUS].='Z';
                  $FDB{$allmessageids[$i]}=msgattr2string(@attr);
                  $FDB{'ZAPMESSAGES'}++; $FDB{'ZAPSIZE'}+=$attr[$_SIZE];
                  if (is_internal_subject($attr[$_SUBJECT])) {
                     $FDB{'INTERNALMESSAGES'}--; $FDB{'INTERNALSIZE'}-=$attr[$_SIZE];
                  } elsif ($attr[$_STATUS]!~m/R/i) {
                     $FDB{'NEWMESSAGES'}--;
                  }
               }
               ow::dbm::close(\%FDB, $folderdb);
            }

         } # end of msg verify

         if (${$r_prefs}{'filter_repeatlimit'}>0 &&
             !$to_be_moved && !$reserved_in_folder &&
             ow::datetime::dateserial2gmtime($attr[$_DATE]) >= $repeatstarttime) {
            # store msgid with same '$from:$subject' to same array
            my $msgstr="$attr[$_FROM]:$attr[$_SUBJECT]";
            if (!defined($repeatlists{$msgstr}) ) {
               $repeatlists{$msgstr}=[];	# reference of null array
            }
            push (@{$repeatlists{$msgstr}}, $allmessageids[$i]);
         }

         # remember this msgid so we won't recheck it again after @allmessageids reload event
         $is_verified{$allmessageids[$i]}=1;
         $i--;
      } # end of messageids loop

      if (ow::filelock::lock($folderfile, LOCK_EX)) {
         # remove repeated msgs with repeated count > ${$r_prefs}{'filter_repeatlimit'}
         my (@repeatedids, $fromsubject, $r_ids);
         while ( ($fromsubject,$r_ids) = each %repeatlists) {
            push(@repeatedids, @{$r_ids}) if ($#{$r_ids}>=${$r_prefs}{'filter_repeatlimit'});
         }
         if ($#repeatedids>=0) {
            my ($trashfile, $trashdb)=get_folderpath_folderdb($user, 'mail-trash');
            if (ow::filelock::lock($trashfile, LOCK_EX) ) {
               my $moved=operate_message_with_ids('move', \@repeatedids, $folderfile, $folderdb,
         							$trashfile, $trashdb);
               ow::filelock::lock($trashfile, LOCK_UN);
               if ($moved>0) {
                  if ($config{'log_filter_detail'}) {
                     my $idsstr=join(',', @repeatedids);
                     my $m="mailfilter - move $idsstr -> mail-trash (smartrule: filter_repeatlimit)"; writelog($m); writehistory($m);
                  }
                  filterruledb_increase("filter_repeatlimit", $moved);
                  filterfolderdb_increase('mail-trash', $moved);
               } elsif ($moved<0) {
                  my $m="mailfilter - mail-trash write error"; writelog($m); writehistory($m);
               }
            } else {
               my $m="$trashfile write lock error"; writelog($m); writehistory($m);
            }
         }

         my $zapped=folder_zapmessages($folderfile, $folderdb);
         if ($zapped==-9||$zapped==-10) { # zap again if index inconsistence or data error
            $zapped=folder_zapmessages($folderfile, $folderdb);
            if ($zapped<0) {
               my $m="mailfilter - $folderfile zap error $zapped"; writelog($m); writehistory($m);
            }
         }
         ow::filelock::lock($folderfile, LOCK_UN);
      }

      if ($config{'log_filter_detail'}) {
         my $m="mailfilter - terminated normally"; writelog($m); writehistory($m);
      }
      openwebmail_exit(0);	# terminate this forked filter process
   }

   # wait background filtering to complete for few seconds
   my $seconds=${$r_prefs}{'bgfilterwait'}; $seconds=5 if ($seconds<5);
   for (my $i=0; $i<$seconds; $i++) {	
      sleep 1;
      last if ($_filter_complete);
   }
   return(1);
}

########## misc supported foutines #####################################
sub mark_folderdb_err {
   my ($folderdb)=@_;
   my %FDB;
   ow::dbm::open(\%FDB, $folderdb, LOCK_EX);
   @FDB{'METAINFO', 'LSTMTIME'}=('ERR', -1);
   ow::dbm::close(\%FDB, $folderdb);
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
########## END FILTERMESSAGE #####################################

########## APPEND_FILTEREDMSG_TO_FOLDER ##########################
sub append_filteredmsg_to_folder {
   my ($folderfile, $folderdb, $messageid, $r_attr, $r_currmessage, $user, $destination)=@_;
   my %FDB2;
   my ($dstfile, $dstdb)=get_folderpath_folderdb($user, $destination);
   my $ioerr=0;
   my @attr=@{$r_attr};

   if ($$r_currmessage eq "") {
      my ($lockget_err, $lockget_errmsg)=lockget_message_block($messageid, $folderfile, $folderdb, $r_currmessage);
      return(-1, $lockget_errmsg) if ($lockget_err<0);
   }
   if (!-f $dstfile) {
      open (DEST, ">$dstfile") or return(-2, "$dstfile write open error");
      close (DEST);
   }

   ow::filelock::lock($dstfile, LOCK_EX) or return(-2, "$dstfile write lock error");
   if (update_folderindex($dstfile, $dstdb)<0) {
      ow::filelock::lock($dstfile, LOCK_UN);
      writelog("db error - Couldn't update index db $dstdb");
      writehistory("db error - Couldn't update index db $dstdb");
      return(-2, "Couldn't update index db $dstdb");
   }
   ow::dbm::open(\%FDB2, $dstdb, LOCK_EX) or return(-1, "$dstdb dbm open error");
   if (!defined($FDB2{$messageid}) ) {	# append only if not found in dstfile
      if (! open(DEST, "+<$dstfile")) {
         ow::dbm::close(\%FDB2, $dstdb);
         return(-1, "$dstfile write open error");
      }
      $attr[$_OFFSET]=(stat(DEST))[7];
      seek(DEST, $attr[$_OFFSET], 0);
      $attr[$_SIZE]=length(${$r_currmessage});
      print DEST ${$r_currmessage} or $ioerr++;
      close (DEST);

      if (!$ioerr) {
         $FDB2{$messageid}=msgattr2string(@attr);
         if (is_internal_subject($attr[$_SUBJECT])) {
            $FDB2{'INTERNALMESSAGES'}++; $FDB2{'INTERNALSIZE'}+=$attr[$_SIZE];
         } elsif ($attr[$_STATUS]!~/R/i) {
            $FDB2{'NEWMESSAGES'}++;
         }
         $FDB2{'ALLMESSAGES'}++;
         $FDB2{'METAINFO'}=ow::tool::metainfo($dstfile);
         $FDB2{'LSTMTIME'}=time();
      }
   }
   ow::dbm::close(\%FDB2, $dstdb);
   ow::filelock::lock($dstfile, LOCK_UN);
   return(-2, "$dstfile write error") if ($ioerr);
   return 0;
}
########## END APPEND_FILTEREDMSG_TO_FOLDER ######################

########## FILTERRULEDB ##########################################
sub filterruledb_increase {
   my ($rulestr, $number)=@_; $number=1 if ($number==0);
   my $filterruledb=dotpath('filter.ruledb');
   my %DB;
   if (ow::dbm::open(\%DB, $filterruledb, LOCK_EX)) {
      my $count=(split(":", $DB{$rulestr}))[0]+$number;
      my $date=ow::datetime::gmtime2dateserial();
      $DB{$rulestr}="$count:$date";
      ow::dbm::close(\%DB, $filterruledb);
      return 0;
   } else {
      return -1;
   }
}
########## END FILTERRULEDB ######################################

########## FILTERFOLDERDB ########################################
sub filterfolderdb_increase {
   my ($foldername, $number)=@_; $number=1 if ($number==0);
   my $filterfolderdb=dotpath('filter.folderdb');
   my %DB;
   if (ow::dbm::open(\%DB, $filterfolderdb, LOCK_EX)) {
      $DB{$foldername}+=$number;
      $DB{'_TOTALFILTERED'}+=$number;
      ow::dbm::close(\%DB, $filterfolderdb);
      return 0;
   } else {
      return -1;
   }
}

sub read_filterfolderdb {
   my $clear_after_read=$_[0];
   my $filterfolderdb=dotpath('filter.folderdb');
   my (%DB, %filtered, $totalfiltered);

   ow::dbm::open(\%DB, $filterfolderdb, LOCK_EX);
   %filtered=%DB;
   $totalfiltered=$filtered{'_TOTALFILTERED'};
   delete $filtered{'_TOTALFILTERED'};

   if ($clear_after_read) {
      %DB=();
      if ($totalfiltered>0) {
         my $dststr;
         foreach my $destination (sort keys %filtered) {
            next if ($destination eq 'INBOX');
            $dststr .= ", " if ($dststr ne "");
            $dststr .= $destination;
            $dststr .= "($filtered{$destination})" if ($filtered{$destination} ne $totalfiltered);
         }
         writelog("mailfilter - filter $totalfiltered msgs from INBOX to $dststr");
         writehistory("mailfilter - filter $totalfiltered msgs from INBOX to $dststr");
      }
   }

   ow::dbm::close(\%DB, $filterfolderdb);

   return ($totalfiltered, %filtered);
}
########## END FILTERFOLDERDB ####################################

1;
