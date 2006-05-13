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
require "shares/filterbook.pl";

# extern vars
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES);	# defined in maildb.pl
use vars qw(%config %lang_err);
use vars qw(%op_order %ruletype_order %folder_order);	# table defined in filterbook.pl

########## FILTERMESSAGE #########################################
# filter inbox messages in background
# return: 0 filter not necessary
#         1 filter started (either forground or background)
# there are 4 op for a msg: 'copy', 'move', 'delete' and 'keep'
use vars qw($_filter_complete);
sub filtermessage {
   my ($user, $folder, $r_prefs)=@_;

   if (!$config{'enable_userfilter'} &&
       !$config{'enable_globalfilter'} &&
       !$config{'enable_smartfilter'} &&
       !$config{'enabel_viruscheck'} &&
       !$config{'enable_spamcheck'}) {
      return 0;				# return immediately if nothing to do
   }

   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   return 0 if ( ! -f $folderfile );	# check existence of folderfile

   my $forced_recheck=0;
   my $filtercheckfile=dotpath('filter.check');

   # automic 'test & set' the metainfo value in filtercheckfile
   my $metainfo=ow::tool::metainfo($folderfile);
   if (!-f $filtercheckfile) {
      sysopen(F, $filtercheckfile, O_WRONLY|O_APPEND|O_CREAT); close(F);
      $forced_recheck=1;	# new filterrule added?, so do filtering on all msg
   }

   ow::filelock::lock($filtercheckfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $filtercheckfile");
   if (!sysopen(FILTERCHECK, $filtercheckfile, O_RDONLY)) {
      ow::filelock::lock($filtercheckfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $filtercheckfile");
   }
   $_=<FILTERCHECK>;
   close(FILTERCHECK);
   if ($_ eq $metainfo) {
      ow::filelock::lock($filtercheckfile, LOCK_UN);
      return 0;
   }
   if (!sysopen(FILTERCHECK, $filtercheckfile, O_WRONLY|O_TRUNC|O_CREAT)) {
      ow::filelock::lock($filtercheckfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $filtercheckfile");
   }
   print FILTERCHECK $metainfo;
   close(FILTERCHECK);
   ow::filelock::lock($filtercheckfile, LOCK_UN);

   if (!ow::filelock::lock($folderfile, LOCK_EX)) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'mailfilter_error'} (".f2u($folderfile)." write lock error)");
   }
   if (!update_folderindex($folderfile, $folderdb)<0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'mailfilter_error'} (Couldn't update index db ".f2u($folderdb).")");
   }

   my @allmessageids=();
   my ($total, $r_msgid2attrs)=get_msgid2attrs($folderdb, 1, $_OFFSET, $_STATUS); # 1 means ignore_internal
   foreach my $id (keys %{$r_msgid2attrs}) {
      next if (${${$r_msgid2attrs}{$id}}[1]=~/V/ && !$forced_recheck);	# skip verified msg if no forced check
      next if (${${$r_msgid2attrs}{$id}}[1]=~/Z/);			# skip any zapped msg
      push(@allmessageids, $id);
   }
   @allmessageids= sort {
                        ${${$r_msgid2attrs}{$a}}[0]<=>${${$r_msgid2attrs}{$b}}[0]
                        } @allmessageids;
   if ($#allmessageids<0) {
      ow::filelock::lock($folderfile, LOCK_UN);
      return 0;				# retuen immediately if no message found
   }

   if (${$r_prefs}{'bgfilterthreshold'}>0 &&
       $#allmessageids+1>=${$r_prefs}{'bgfilterthreshold'}) {

      # release folder lock before fork, the forked child does lock in per message basis
      ow::filelock::lock($folderfile, LOCK_UN);

      local $_filter_complete=0;
      local $SIG{CHLD} = sub { wait; $_filter_complete=1 if ($?==0) };	# signaled when filter completes
      local $|=1; # flush all output

      if ( fork() == 0) {		# child
         close(STDIN); close(STDOUT); close(STDERR);
         writelog("debug - mailfilter process forked - " .__FILE__.":". __LINE__) if ($config{'debug_fork'}||$config{'debug_mailfilter'});

         ow::suid::drop_ruid_rgid(); # set ruid=euid to avoid fork in spamcheck.pl
         filter_allmessageids($user, $folder, $r_prefs,
                              $folderfile, $folderdb, $metainfo, $filtercheckfile, $forced_recheck,
                              \@allmessageids, 0);	# 0 means no globallock

         writelog("debug - mailfilter process terminated - " .__FILE__.":". __LINE__) if ($config{'debug_fork'}||$config{'debug_mailfilter'});
         openwebmail_exit(0);	# terminate this forked filter process
      }

      # wait background filtering to complete for few seconds
      my $seconds=${$r_prefs}{'bgfilterwait'}; $seconds=5 if ($seconds<5);
      for (my $i=0; $i<$seconds; $i++) {
         sleep 1;
         last if ($_filter_complete);
      }

   } else {
      writelog("debug - mailfilter allmessageids started - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});
      filter_allmessageids($user, $folder, $r_prefs,
                           $folderfile, $folderdb, $metainfo, $filtercheckfile, $forced_recheck,
                           \@allmessageids, 1);		# 1 meas has globallock
      writelog("debug - mailfilter allmessageids ended - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});
      ow::filelock::lock($folderfile, LOCK_UN);
   }

   return(1);
}

sub filter_allmessageids {
   my ($user, $folder, $r_prefs,
       $folderfile, $folderdb, $metainfo, $filtercheckfile, $forced_recheck,
       $r_allmessageids, $has_globallock)=@_;

   my $pidfile;
   # threshold>0 means the bg filter may be actived if inbox have enough new msgs,
   # so we update pid file to terminate any other bg filter process
   if (${$r_prefs}{'bgfilterthreshold'}>0) {
      $pidfile=dotpath('filter.pid');
      sysopen(F, $pidfile, O_WRONLY|O_TRUNC|O_CREAT); print F $$; close(F);
   }

   # get @filterrules
   my (%filterrules, @sorted_filterrules);
   my $filterbookfile=dotpath('filter.book');
   if ($config{'enable_userfilter'} && -f $filterbookfile) {
      read_filterbook($filterbookfile, \%filterrules);
   }
   if ($config{'enable_globalfilter'} && -f $config{'global_filterbook'}) {
      read_filterbook($config{'global_filterbook'}, \%filterrules);
   }
   foreach my $key (sort_filterrules(\%filterrules)) {
      my $r_rule=$filterrules{$key};
      next if (!${$r_rule}{enable} ||
               ${$r_rule}{op} ne 'copy' &&
               ${$r_rule}{op} ne 'move' &&
               ${$r_rule}{op} ne 'delete');
      if (${$r_rule}{dest} eq 'DELETE') {
         next if (${$r_rule}{op} eq 'copy');			# copy to DELETE is meaningless
         ${$r_rule}{op}='delete' if (${$r_rule}{op} eq 'move');	# move to DELETE is 'delete'
      }
      push(@sorted_filterrules, $key);
   }
   # return immediately if nothing to do
   return 1 if ($#sorted_filterrules<0 &&
                !$config{'enable_smartfilter'} &&
                !$config{'enabel_viruscheck'} &&
                !$config{'enable_spamcheck'});

   my $repeatstarttime=time()-86400;	# only count repeat for messages within one day
   my %repeatlists=();
   my %is_verified=();
   my ($io_errcount, $viruscheck_errcount, $spamcheck_errcount)=(0, 0);
   my ($appended, $append_errmsg)=(0, '');

   my $i=$#{$r_allmessageids};
   while ($i>=0) {
      my $messageid_i=${$r_allmessageids}[$i];
      writelog("debug - mailfilter loop $i, msgid=$messageid_i - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});

      if ($is_verified{$messageid_i} ||	# skip already verified msg
          $messageid_i=~/^DUP\d+\-/ ) {	# skip duplicated msg in src folder
         $i--; next;
      }
      last if ($io_errcount>=3);

      if (!$has_globallock) {
         # terminated if other filter process is active on same folder
         sysopen(F, $pidfile, O_RDONLY); $_=<F>; close(F);
         if ($_ ne $$) {
            my $m="mailfilter - bg process terminated - reason: another filter pid=$_ is avtive."; writelog($m);
            openwebmail_exit(0);
         }

         # reload messageids if folder is changed
         my $curr_metainfo=ow::tool::metainfo($folderfile);
         if ($metainfo ne $curr_metainfo) {
            my ($lockget_err, $lockget_errmsg)=lockget_messageids($folderfile, $folderdb, $r_allmessageids);
            if ($lockget_err<0) {
               my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
               openwebmail_exit(0);
            } else {
               $i=$#{$r_allmessageids};
               my $m="mailfilter - reload $i msgids - reason: $folderfile is changed"; writelog($m);
            }

            if (!sysopen(FILTERCHECK, $filtercheckfile, O_WRONLY|O_TRUNC|O_CREAT)) {
               my $m="mailfilter - $filtercheckfile open error"; writelog($m); writehistory($m);
               openwebmail_exit(0);
            }
            print FILTERCHECK $curr_metainfo;
            close(FILTERCHECK);
            $metainfo=$curr_metainfo;

            next;
         }
      }

      my ($headersize, $header, $decoded_header, $currmessage, $body)=(0, "", "", "", "");
      my (%msg, $r_attachments, $r_smtprelays, $r_connectfrom, $r_byas);
      my ($is_body_decoded, $is_attachments_decoded)=(0, 0);
      my ($reserved_in_folder, $to_be_moved)=(0, 0);

      my @attr = get_message_attributes($messageid_i, $folderdb);
      if ($#attr<0) {	# msg not found in db
         $i--; next;
      }
      if (is_internal_subject($attr[$_SUBJECT]) || $attr[$_STATUS]=~/Z/i) {	# skip internal or zapped
         $is_verified{$messageid_i}=1;
         $i--; next;
      }

      # if flag V not found, this msg has not been filtered before (Verify)
      if ($attr[$_STATUS] !~ /V/i || $forced_recheck) {
         # 0. read && check msg header
         my ($lockget_err, $lockget_errmsg)=lockget_message_header($messageid_i, $folderfile, $folderdb, \$header, $has_globallock);
         if ($lockget_err<0) {
            my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
            mark_folderdb_err($folderdb) if ($lockget_err<=-3);
            $io_errcount++; $i--; next;
         }

         writelog("debug - mailfilter check $messageid_i, subject=$attr[$_SUBJECT] - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});

         if ($attr[$_STATUS] !~ /V/i) {
            my %FDB;
            ow::dbm::open(\%FDB, $folderdb, LOCK_EX);
            $attr[$_STATUS].="V";
            $FDB{$messageid_i}=msgattr2string(@attr);
            ow::dbm::close(\%FDB, $folderdb);
         }
         # 1. virus check
         if ($config{'enable_viruscheck'} && !$to_be_moved) {
            writelog("debug - mailfilter viruscheck $messageid_i - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});

            my $virusfound=0;
            if ($header=~/^X\-OWM\-VirusCheck: ([a-z]+)/m) {		# virus checked in fetchmail.pl
               $virusfound=1 if ($1 eq 'virus');
            } elsif (${$r_prefs}{'viruscheck_source'} eq 'all' &&	# to be checked here
                     !$viruscheck_errcount &&
                     $attr[$_SIZE] <= ${$r_prefs}{'viruscheck_maxsize'}*1024 &&
                     $attr[$_SIZE]-$attr[$_HEADERSIZE] > ${$r_prefs}{'viruscheck_minbodysize'}*1024 ) {
               if ($currmessage eq "") {
                  ($lockget_err, $lockget_errmsg)=lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);
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
                  my $m="viruscheck - virus $err found in msg $messageid_i"; writelog($m); writehistory($m);
                  $virusfound=1;
               }
            }
            if ($virusfound) {
               ($appended, $append_errmsg)=append_filteredmsg_to_folder($folderfile, $folderdb,
				$messageid_i, \@attr, \$currmessage, $user, $config{'virus_destination'}, $has_globallock);
               if ($appended >=0) {
                  writelog("debug - mailfilter move $messageid_i -> $config{'virus_destination'} - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});
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
            writelog("debug - mailfilter static rules check $messageid_i - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});

            foreach my $key (@sorted_filterrules) {
               my $r_rule=$filterrules{$key};
               my $is_matched=0;

               # precompile text into regex of msg charset for speed
               if (!defined ${$r_rule}{'regex.'.$attr[$_CHARSET]}) {
                  my $text=(iconv(${$r_rule}{charset}, $attr[$_CHARSET], ${$r_rule}{text}))[0];
                  if (${$r_prefs}{'regexmatch'} && ow::tool::is_regex($text)) {	# do regex compare?
                     ${$r_rule}{'regex.'.$attr[$_CHARSET]}=qr/$text/im;
                  } else {
                     ${$r_rule}{'regex.'.$attr[$_CHARSET]}=qr/\Q$text\E/im;
                  }
               }

               if ( ${$r_rule}{type} eq 'from' || ${$r_rule}{type} eq 'to' || ${$r_rule}{type} eq 'subject') {
                  if ($decoded_header eq "") {
                     $decoded_header=decode_mimewords_iconv($header, $attr[$_CHARSET]);
                     $decoded_header=~s/\s*\n\s+/ /sg; # concate folding lines
                  }
                  if (!defined $msg{from}) { # this is defined after parse_header is called
                     ow::mailparse::parse_header(\$decoded_header, \%msg);
                  }
                  if ($msg{${$r_rule}{type}}=~/${$r_rule}{'regex.'.$attr[$_CHARSET]}/
                      xor ${$r_rule}{inc} eq 'exclude') {
                      $is_matched=1;
                  }

               } elsif ( ${$r_rule}{type} eq 'header' ) {
                  if ($decoded_header eq "") {
                     $decoded_header=decode_mimewords_iconv($header, $attr[$_CHARSET]);
                     $decoded_header=~s/\s*\n\s+/ /sg; # concate folding lines
                  }
                  if ($decoded_header=~/${$r_rule}{'regex.'.$attr[$_CHARSET]}/
                      xor ${$r_rule}{inc} eq 'exclude') {
                      $is_matched=1;
                  }

               } elsif ( ${$r_rule}{type} eq 'smtprelay' ) {
                  if (!defined $r_smtprelays) {
                     ($r_smtprelays, $r_connectfrom, $r_byas)=ow::mailparse::get_smtprelays_connectfrom_byas_from_header($header);
                  }
                  my $smtprelays;
                  foreach my $relay (@{$r_smtprelays}) {
                     $smtprelays.="$relay, ${$r_connectfrom}{$relay}, ${$r_byas}{$relay}, ";
                  }
                  if ($smtprelays=~/${$r_rule}{'regex.'.$attr[$_CHARSET]}/
                      xor ${$r_rule}{inc} eq 'exclude') {
                      $is_matched=1;
                  }

               } elsif ( ${$r_rule}{type} eq 'textcontent' ) {
                  if ($currmessage eq "") {
                     ($lockget_err, $lockget_errmsg)=lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);
                     if ($lockget_err<0) {
                        my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
                        mark_folderdb_err($folderdb) if ($lockget_err<=-3);
                        $io_errcount++; $i--; next;
                     }
                  }
                  if (!defined @{$r_attachments}) {
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
                     if ($body=~/${$r_rule}{'regex.'.$attr[$_CHARSET]}/
                         xor ${$r_rule}{inc} eq 'exclude') {
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
                           if (${${$r_attachment}{r_content}}=~/${$r_rule}{'regex.'.$attr[$_CHARSET]}/
                               xor ${$r_rule}{inc} eq 'exclude') {
                              $is_matched=1;
                              last;	# leave attachments loop of this msg
                           }
                        }
                     }
                  } # end !$is_matched bodytext

               } elsif (${$r_rule}{type} eq 'attfilename') {
                  if ($currmessage eq "") {
                     ($lockget_err, $lockget_errmsg)=lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);
                     if ($lockget_err<0) {
                        my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
                        mark_folderdb_err($folderdb) if ($lockget_err<=-3);
                        $io_errcount++; $i--; next;
                     }
                  }
                  if (!defined @{$r_attachments}) {
                     ($header, $body, $r_attachments)=ow::mailparse::parse_rfc822block(\$currmessage);
                  }
                  # check attachments
                  foreach my $r_attachment (@{$r_attachments}) {
                     if (${$r_attachment}{filename}=~/${$r_rule}{'regex.'.$attr[$_CHARSET]}/
                         xor ${$r_rule}{inc} eq 'exclude') {
                        $is_matched=1;
                        last;	# leave attachments loop of this msg
                     }
                  }
               }

               if ($is_matched) {
                  # cp msg to other folder and set reserved_in_folder or to_be_moved flag
                  filterruledb_increase($key, 1);

                  if (!defined ${$r_rule}{fsdest}) {
                     ${$r_rule}{fsdest}=(iconv(${$r_rule}{charset}, ${$r_prefs}{fscharset}, ${$r_rule}{dest}))[0];
                  }

                  if ( ${$r_rule}{op} eq 'move' || ${$r_rule}{op} eq 'copy') {
                     if (${$r_rule}{fsdest} eq $folder) {
                        $reserved_in_folder=1;
                     } else {
                        ($appended, $append_errmsg)=append_filteredmsg_to_folder($folderfile, $folderdb,
					$messageid_i, \@attr, \$currmessage, $user, ${$r_rule}{fsdest}, $has_globallock);
                     }
                  }

                  if (${$r_rule}{op} eq 'move' || ${$r_rule}{op} eq 'delete') {
                     if ($appended>=0) {
                        if (!$reserved_in_folder) {
                           if ($config{'debug_mailfilter'}) {
                              my $fstext=(iconv(${$r_rule}{charset}, ${$r_prefs}{fscharset}, ${$r_rule}{text}))[0];
                              writelog("debug - mailfilter move $messageid_i -> ${$r_rule}{fsdest} (rule: ${$r_rule}{type} ${$r_rule}{inc} $fstext) - " .__FILE__.":". __LINE__);
                           }
                           $to_be_moved=1;
                           filterfolderdb_increase(${$r_rule}{fsdest}, 1);
                        }
                     } else {
                        my $m="mailfilter - ${$r_rule}{fsdest} write error"; writelog($m); writehistory($m);
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
            writelog("debug - mailfilter spamcheck $messageid_i - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});

            my $spamfound=0;
            if ($header=~/^X\-OWM\-SpamCheck: \** ([\d\.]+)/m) {	# spam checked in fetchmail.pl
               $spamfound=1 if ($1 > ${$r_prefs}{'spamcheck_threshold'});
            } elsif (${$r_prefs}{'spamcheck_source'} eq 'all' && 		# to be checked here
                     !$spamcheck_errcount &&
                     $attr[$_SIZE] <= ${$r_prefs}{'spamcheck_maxsize'}*1024) {
               if ($currmessage eq "") {
                  ($lockget_err, $lockget_errmsg)=lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);
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
                  my $m="spamcheck - spam $spamlevel/${$r_prefs}{'spamcheck_threshold'} found in msg $messageid_i";
                  writelog($m); writehistory($m);
                  $spamfound=1;
               } else {
                  my $m="spamcheck - notspam $spamlevel/${$r_prefs}{'spamcheck_threshold'} found in msg $messageid_i";
                  writelog($m); writehistory($m);
               }
            }
            if ($spamfound) {
               ($appended, $append_errmsg)=append_filteredmsg_to_folder($folderfile, $folderdb,
				$messageid_i, \@attr, \$currmessage, $user, $config{'spam_destination'}, $has_globallock);
               if ($appended >=0) {
                  writelog("debug - mailfilter move $messageid_i -> $config{'spam_destination'} - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});
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
            writelog("debug - mailfilter smart rules check $messageid_i - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});

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
                     $messageid_i=~/\Q.TMDA@\E/) ||	# TMDA
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
               if (!defined $r_smtprelays) {
                  ($r_smtprelays, $r_connectfrom, $r_byas)=ow::mailparse::get_smtprelays_connectfrom_byas_from_header($header);
               }
               # move msg to trash if the first relay has invalid/faked hostname
               if (defined ${$r_smtprelays}[0]) {
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
                  ($lockget_err, $lockget_errmsg)=lockget_message_block($messageid_i, $folderfile, $folderdb, \$currmessage, $has_globallock);
                  if ($lockget_err<0) {
                     my $m="mailfilter - $lockget_errmsg"; writelog($m); writehistory($m);
                     mark_folderdb_err($folderdb) if ($lockget_err<=-3);
                     $io_errcount++; $i--; next;
                  }
               }
               if (!defined @{$r_attachments}) {
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
				$messageid_i, \@attr, \$currmessage, $user, 'mail-trash', $has_globallock);
               if ($appended>=0) {
                  writelog("debug - mailfilter move $messageid_i -> mail-trash (smartrule: $matchedsmartrule) - " .__FILE__.":". __LINE__) if ($config{'debug_mailfilter'});
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
            my %FDB;
            ow::dbm::open(\%FDB, $folderdb, LOCK_EX);
            if ($attr[$_STATUS]!~/Z/i) {
               $attr[$_STATUS].='Z';
               $FDB{$messageid_i}=msgattr2string(@attr);
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
         if (!defined $repeatlists{$msgstr}) {
            $repeatlists{$msgstr}=[];	# reference of null array
         }
         push (@{$repeatlists{$msgstr}}, $messageid_i);
      }

      # remember this msgid so we won't recheck it again after @allmessageids reload event
      $is_verified{$messageid_i}=1;
      $i--;
   } # end of messageids loop

   if ( $has_globallock || ow::filelock::lock($folderfile, LOCK_EX) ) {
      # remove repeated msgs with repeated count > ${$r_prefs}{'filter_repeatlimit'}
      my (@repeatedids, $fromsubject, $r_ids);
      while ( ($fromsubject,$r_ids) = each %repeatlists) {
         push(@repeatedids, @{$r_ids}) if ($#{$r_ids}>=${$r_prefs}{'filter_repeatlimit'});
      }
      if ($#repeatedids>=0) {
         my ($trashfile, $trashdb)=get_folderpath_folderdb($user, 'mail-trash');
         my ($moved, $errmsg);
         if (ow::filelock::lock($trashfile, LOCK_EX) ) {
            ($moved, $errmsg)=operate_message_with_ids('move', \@repeatedids, $folderfile, $folderdb, $trashfile, $trashdb);
            ow::filelock::lock($trashfile, LOCK_UN);
            if ($moved>0) {
               if ($config{'debug_mailfilter'}) {
                  my $idsstr=join(',', @repeatedids);
                  writelog("debug - mailfilter move $idsstr -> mail-trash (smartrule: filter_repeatlimit) - " .__FILE__.":". __LINE__);
               }
               filterruledb_increase("filter_repeatlimit", $moved);
               filterfolderdb_increase('mail-trash', $moved);
            } elsif ($moved<0) {
               writelog($errmsg); writehistory($errmsg);
            }
         } else {
            my $m="$lang_err{'couldnt_writelock'} $trashfile"; writelog($m); writehistory($m);
         }
      }

      my $is_allmessageids_checked=0;
      if ($metainfo eq ow::tool::metainfo($folderfile)) {	# folder not changed since messageids loop ends until now
         $is_allmessageids_checked=1;
      }
      my $zapped=folder_zapmessages($folderfile, $folderdb);
      if ($zapped==-9||$zapped==-10) { # zap again if index inconsistence or data error
         $zapped=folder_zapmessages($folderfile, $folderdb);
         if ($zapped<0) {
            my $m="mailfilter - $folderfile zap error $zapped"; writelog($m); writehistory($m);
         }
      }
      if ($is_allmessageids_checked) {
         ow::filelock::lock($filtercheckfile, LOCK_EX|LOCK_NB);
         if (sysopen(FILTERCHECK, $filtercheckfile, O_WRONLY|O_TRUNC|O_CREAT)) {
            print FILTERCHECK ow::tool::metainfo($folderfile);
            close(FILTERCHECK);
         }
         ow::filelock::lock($filtercheckfile, LOCK_UN);
      }

      ow::filelock::lock($folderfile, LOCK_UN) if (!$has_globallock);
   }
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
# >0 match, <0 unmatch, ==0 unknown
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
   my ($folderfile, $folderdb, $messageid, $r_attr, $r_currmessage, $user, $destination, $has_globallock)=@_;

   if ($$r_currmessage eq "") {
      my ($lockget_err, $lockget_errmsg)=lockget_message_block($messageid, $folderfile, $folderdb, $r_currmessage, $has_globallock);
      return(-1, $lockget_errmsg) if ($lockget_err<0);
   }

   my ($dstfile, $dstdb)=get_folderpath_folderdb($user, $destination);
   if (!-f $dstfile) {
      sysopen(DEST, $dstfile, O_WRONLY|O_TRUNC|O_CREAT) or return(-1, "$dstfile write open error");
      close(DEST);
   }
   ow::filelock::lock($dstfile, LOCK_EX) or return(-2, "$dstfile write lock error");
   my ($err, $errmsg)=append_message_to_folder($messageid, $r_attr, $r_currmessage, $dstfile, $dstdb);
   ow::filelock::lock($dstfile, LOCK_UN);

   return($err, $errmsg) if ($err<0);
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
