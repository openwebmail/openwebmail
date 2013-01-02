
#                              The BSD License
#
#  Copyright (c) 2009-2013, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# fetchmail.pl - fetch mail messages from pop3 server

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);
use IO::Socket;
use MIME::Base64;

require "modules/dbm.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/spamcheck.pl";
require "modules/viruscheck.pl";

use vars qw(%config %prefs $user);

sub fetchmail {
   # since fetch mail from remote pop3 may be slow,
   # the folder file lock is done inside routine,
   # it happens when each one complete message is retrieved

   # fetch mail from pop3 then call spamcheck/viruscheck
   # put X-OWM-VirusCheck and X-OWM-SpamCheck in message header
   # ret >0: number of fetched msgs
   #      0: no msg
   #     -1: connect error
   #     -2: pop3 error
   #     -3: folder write error
   my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del) = @_;
   $pop3host = ow::tool::untaint($pop3host); # untaint for connection creation
   $pop3port = ow::tool::untaint($pop3port);

   my $socket = '';
   my $line   = '';
   my @result = ();

   eval {
           no warnings 'all';
           local $SIG{'__DIE__'};

           alarm 60;

           local $SIG{ALRM} = sub { die "alarm\n" };

           if ($pop3ssl && ow::tool::has_module('IO/Socket/SSL.pm')) {
              $socket = new IO::Socket::SSL (PeerAddr => $pop3host, PeerPort => $pop3port, Proto => 'tcp');
           } else {
              $pop3port = 110 if $pop3ssl && $pop3port == 995;
              $socket = new IO::Socket::INET (PeerAddr => $pop3host, PeerPort => $pop3port, Proto => 'tcp');
           }

           $socket->autoflush(1);

           alarm 0;
        };

   return(-1, 'connection timeout') if $@;
   return(-1, 'connection refused') unless $socket;
   return(-1, 'server not ready') if !readdata($socket, \$line) || $line !~ m/^\+/;

   my $authlogin = 0;
   $authlogin = 1 if (
                        sendcmd($socket, "auth login\r\n", \@result)
                        && sendcmd($socket, &encode_base64($pop3user), \@result)
                        && sendcmd($socket, &encode_base64($pop3passwd), \@result)
                     );

   if (
         !$authlogin
         &&
         !(
             sendcmd($socket, "user $pop3user\r\n", \@result)
             && sendcmd($socket, "pass $pop3passwd\r\n", \@result)
          )
      ) {
      sendcmd($socket, "quit\r\n", \@result);
      close($socket);
      return(-2, 'bad login');
   }

   my $msg_total = 0;

   if (!sendcmd($socket, "stat\r\n", \@result)) {
      sendcmd($socket, "quit\r\n", \@result);
      close($socket);
      return (-2, 'stat error');
   }

   if (($msg_total = $result[0]) == 0) {
      # no messages on pop3 server
      sendcmd($socket, "quit\r\n", \@result);
      close($socket);
      return (0, '');
   }

   my %UIDLDB = (); # %UIDLDB in memory
   my %uidldb = (); # %uidldb database on disk

   my $uidldb = dotpath("uidl.$pop3user\@$pop3host");

   my $uidl_support = 0;

   # 'uidl' supported on pop3 server and local uidldb ready?
   $uidl_support = 1 if (sendcmd($socket, "uidl 1\r\n", \@result) && ow::dbm::opendb(\%UIDLDB, $uidldb, LOCK_EX));

   my $last = -1;

   if (!$uidl_support) {
      if (sendcmd($socket, "last\r\n", \@result)) {
         # 'last' is supported
         if (($last = $result[0]) == $msg_total) {
            # all messages have already been read
            sendcmd($socket, "quit\r\n", \@result);
            close($socket);
            return (0, '');
         }
      } else {
         # 'last' is not supported
         if ($pop3del) {
            $last = 0;
         } else {
            sendcmd($socket, "quit\r\n", \@result);
            close($socket);
            return (-2, 'uidl and last operations not supported');
         }
      }
   }

   my $spoolfile = (get_folderpath_folderdb($user, 'INBOX'))[0];

   my $retr_total     = 0;
   my $viruscheck_err = 0;
   my $spamcheck_err  = 0;

   foreach my $msgnum (1..$msg_total) {
      my $uidl = '';

      if ($uidl_support) {
         sendcmd($socket, "uidl $msgnum\r\n", \@result);

         $uidl = $result[1];

         if (defined $UIDLDB{$uidl}) {
            # already fetched before
            $uidldb{$uidl} = 1;
            next;
         }
      } else {
         next if $msgnum <= $last;
      }

      if (!sendcmd($socket, "retr $msgnum\r\n", \@result)) {
         if ($uidl_support) {
            @UIDLDB{keys %uidldb} = values %uidldb if $retr_total > 0;
            ow::dbm::closedb(\%UIDLDB, $uidldb) or writelog("cannot close db $uidldb");
         }

         sendcmd($socket, "quit\r\n", \@result);
         close($socket);
         return (-2, 'retr error');
      }

      my $has_dilimeter = 0;
      my $is_in_retcode = 1;
      my $is_in_header  = 1;

      my $msgfrom       = '';
      my $msgdate       = '';
      my $msgid         = '';
      my $msgsize       = 0;
      my $headersize    = 0;

      my @lines         = ();

      while (1) {
         # read lines of message
         if (!readdata($socket, \$line)) {
            sendcmd($socket, "quit\r\n", \@result);
            close($socket);
            return (-2, 'retr data timeout');
         }

         if ($is_in_retcode) {
            next if $line =~ m/^\+/; # skip verbose +... retcode that appears before real data
            $has_dilimeter = 1 if $line =~ m/^From /;
            $is_in_retcode = 0;
         }

         $line =~ s/\r//g;           # remove \r
         last if $line eq ".\n";     # end and leave while
         $line =~ s/^\.\././;        # remove stuffing dot

         push(@lines, $line);

         $msgsize += length($line);

         if ($is_in_header) {
            # try to get msgfrom/msgdate/msgid in header
            if ($line eq "\n") {
               $is_in_header = 0;
               $headersize = $msgsize;
            } elsif ($line =~ m/^Message\-Id:\s+(.*)\s*$/i) {
               $msgid = $1 if $msgid eq '';
            } elsif (!$has_dilimeter) {
               if ($line =~ m/^From:\s+(.+)\s*$/i) {
                  my $fromfull = $1;
                  if ($msgfrom eq '') {
                     if ($fromfull =~ m/^"?(.+?)"?\s*<(.*)>$/) {
                        $msgfrom = $2;
                     } elsif ($fromfull =~ m/<?(.*@.*)>?\s+\((.+?)\)/) {
                        $msgfrom = $1;
                     } elsif ($fromfull =~ m/<\s*(.+@.+)\s*>/ ) {
                        $msgfrom = $1;
                     } else {
                        $fromfull =~ s/\s*(.+@.+)\s*/$1/;
                        $msgfrom = $fromfull;
                     }
                  }
               } elsif ($line =~ m/\(envelope\-from \s*(.+?)\s*\)/i) {
                  $msgfrom = $1 if $msgfrom eq '';
               } elsif ($line =~ m/^Date:\s+(.*)\s*$/i) {
                  $msgdate = $1 if $msgdate eq '';
               }
            }
         }
      }

      my $faked_dilimeter = '';
      if (!$has_dilimeter) {
         my $dateserial    = ow::datetime::datefield2dateserial($msgdate);
         my $dateserial_gm = ow::datetime::gmtime2dateserial();

         # use current time if msg time is newer than now for 1 day
         $dateserial = $dateserial_gm
            if $dateserial eq '' || ow::datetime::dateserial2gmtime($dateserial) - ow::datetime::dateserial2gmtime($dateserial_gm) > 86400;

         if ($config{deliver_use_gmt}) {
            $msgdate = ow::datetime::dateserial2delimiter($dateserial, '', $prefs{daylightsaving}, $prefs{timezone});
         } else {
            $msgdate = ow::datetime::dateserial2delimiter($dateserial, ow::datetime::gettimeoffset(), $prefs{daylightsaving}, $prefs{timezone});
         }

         $faked_dilimeter = "From $msgfrom $msgdate\n";
      }

      # 1. virus check
      my $virus_found        = 0;
      my $viruscheck_xheader = '';

      if (
            $config{enable_viruscheck}
            && ($prefs{viruscheck_source} eq 'all' || $prefs{viruscheck_source} eq 'pop3')
            && !$viruscheck_err
            && $msgsize <= $prefs{viruscheck_maxsize} * 1024
            && $msgsize - $headersize > $prefs{viruscheck_minbodysize} * 1024
         ) {
         my @completemsg = ($has_dilimeter ? @lines : ($faked_dilimeter, @lines));

         writelog("debug_fork :: viruscheck forking cmd $config{viruscheck_pipe} for message $msgid from $pop3user\@$pop3host") if $config{debug_fork};

         my ($ret, $report, $virusname) = ow::viruscheck::scanmsg($config{viruscheck_pipe}, \@completemsg);

         if ($ret < 0) {
            writelog("viruscheck - pipe error - $report");
            writehistory("viruscheck - pipe error - $report");
            $viruscheck_err++;
         } elsif ($ret > 0) {
            writelog("viruscheck - virus $virusname found in message $msgid from $pop3user\@$pop3host");
            writehistory("viruscheck - virus $virusname found in message $msgid from $pop3user\@$pop3host");

            $virus_found        = 1;
            $viruscheck_xheader = "X-OWM-VirusCheck: virus $virusname found\n";

            if (defined $report && $report && $prefs{viruscheck_include_report}) {
               # replace blank lines with ----
               $report =~ s#([\n\r])([\n\r])#$1----$2#gs;

               # remove trailing space
               $report =~ s/\s+$//gs;

               # rfc822 folding of report
               $report =~ s#([\n\r]+)#$1  #gs;
               $viruscheck_xheader .= sprintf("X-OWM-VirusReport: $report\n");
            }
         } else {
            $viruscheck_xheader = "X-OWM-VirusCheck: clean\n";
            writelog("debug_fork :: not infected for message $msgid from $pop3user\@$pop3host, ret: $report") if $config{debug_fork};
         }
      }

      # 2. spam check
      my $spam_found         = 0;
      my $spamcheck_xheader  = '';

      if (
            !$virus_found
            && $config{enable_spamcheck}
            && ($prefs{spamcheck_source} eq 'all' || $prefs{spamcheck_source} eq 'pop3')
            && !$spamcheck_err
            && $msgsize <= $prefs{spamcheck_maxsize} * 1024
         ) {
         my @completemsg = ($has_dilimeter ? @lines : ($faked_dilimeter, @lines));

         writelog("debug_fork :: spamcheck forking cmd $config{spamcheck_pipe} for message $msgid from $pop3user\@$pop3host") if $config{debug_fork};

         my ($spamscore, $report) = ow::spamcheck::scanmsg($config{spamcheck_pipe}, \@completemsg);

         if ($spamscore == -99999) {
            writelog("spamcheck - pipe error - $report");
            writehistory("spamcheck - pipe error - $report");
            $spamcheck_err++;
         } elsif ($spamscore > $prefs{spamcheck_threshold}) {
            writelog("spamcheck - spam $spamscore/$prefs{spamcheck_threshold} found in msg $msgid from $pop3user\@$pop3host");
            writehistory("spamcheck - spam $spamscore/$prefs{spamcheck_threshold} found in msg $msgid from $pop3user\@$pop3host");

            $spam_found        = 1;
            $spamcheck_xheader = sprintf("X-OWM-SpamCheck: %s %.1f/%.1f\n", '*' x $spamscore, $spamscore, $prefs{spamcheck_threshold});

            if (defined $report && $report && $prefs{spamcheck_include_report}) {
               # replace blank lines with ----
               $report =~ s#([\n\r])([\n\r])#$1----$2#gs;

               # remove trailing space
               $report =~ s/\s+$//gs;

               # rfc822 folding of report
               $report =~ s#([\n\r]+)#$1  #gs;
               $spamcheck_xheader .= sprintf("X-OWM-SpamReport: $report\n");
            }
         } else {
            $spamcheck_xheader = sprintf("X-OWM-SpamCheck: %s %.1f/%.1f\n", '*' x $spamscore, $spamscore, $prefs{spamcheck_threshold});
            writelog("debug_fork :: not spam $spamscore/$prefs{spamcheck_threshold} for message $msgid from $pop3user\@$pop3host") if $config{debug_fork};
         }
      }

      # append message to mail folder
      if (!append_pop3msg_to_folder($faked_dilimeter, $viruscheck_xheader, $spamcheck_xheader, \@lines, $spoolfile)) {
         if ($uidl_support) {
            @UIDLDB{keys %uidldb} = values %uidldb if $retr_total > 0;
            ow::dbm::closedb(\%UIDLDB, $uidldb) or writelog("cannot close db $uidldb");
         }

         sendcmd($socket, "quit\r\n", \@result);
         close($socket);
         return (-3, "$spoolfile write error");
      }

      if (!($pop3del && sendcmd($socket, "dele $msgnum\r\n", \@result)) ) {
         $uidldb{$uidl} = 1 if $uidl_support;
      }

      $retr_total++;
   }

   if ($uidl_support) {
      %UIDLDB = %uidldb if $retr_total > 0;
      ow::dbm::closedb(\%UIDLDB, $uidldb) or writelog("cannot close db $uidldb");
   }

   sendcmd($socket, "quit\r\n", \@result);
   close($socket);

   return $retr_total;
}

sub sendcmd {
   my ($socket, $cmd, $r_result, $timeout) = @_;
   $timeout = 60 if !defined $timeout || $timeout <= 0;

   my $ret = '';

   eval {
           no warnings 'all';
           local $SIG{'__DIE__'};
           alarm $timeout;
           local $SIG{ALRM} = sub { die "alarm\n" };
           print $socket $cmd;
           $ret = <$socket>;
           alarm 0;
        };

   return 0 if $@;         # timeout
   return 0 if $ret eq ''; # socket not available?

   @{$r_result} = split(/\s+/, $ret);

   # remove strings +OK or -ERR from @result
   shift @{$r_result} if $r_result->[0] =~ m/^[\+\-]/;

   return 1 if $ret !~ m/^\-/;

   return 0;
}

sub readdata {
   my ($socket, $r_line, $timeout) = @_;
   $timeout = 60 if !defined $timeout || $timeout <= 0;

   ${$r_line} = ''; # empty line buff

   eval {
           no warnings 'all';
           local $SIG{'__DIE__'};
           alarm $timeout;
           local $SIG{ALRM} = sub { die "alarm\n" };
           ${$r_line} = <$socket>;
           alarm 0;
        };

   return 0 if $@;               # timeout
   return 0 if ${$r_line} eq ''; # socket not available?

   return 1;
}

sub append_pop3msg_to_folder {
   my ($faked_dilimeter, $viruscheck_xheader, $spamcheck_xheader, $r_lines, $folderfile) = @_;

   if (!-f $folderfile) {
      # create this folder since it does not exist yet
      sysopen(F, $folderfile, O_WRONLY|O_APPEND|O_CREAT) or
         writelog("cannot open file $folderfile");

      close(F) or
         writelog("cannot close file $folderfile");
   }

   if (!ow::filelock::lock($folderfile, LOCK_EX)) {
      writelog("cannot lock file $folderfile");
      return 0;
   }

   if (!sysopen(F, $folderfile, O_WRONLY|O_APPEND|O_CREAT)) {
      writelog("cannot open file $folderfile");
      ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
      return 0;
   }

   my $err      = 0;
   my $origsize = (stat(F))[7];

   seek(F, $origsize, 0); # seek to file end

   if ($faked_dilimeter ne '') {
      print F $faked_dilimeter or $err++;
   }

   my $is_in_header = 1;
   foreach my $line (@{$r_lines}) {
      last if $err > 0;

      if ($is_in_header && $line eq "\n") {
         $is_in_header = 0;

         if ($viruscheck_xheader ne '') {
            print F $viruscheck_xheader or $err++;
         }

         if ($spamcheck_xheader ne '') {
            print F $spamcheck_xheader or $err++;
         }
      }

      print F $line or $err++;
   }

   if (!$err && $#{$r_lines} >= 0 && $r_lines->[$#{$r_lines}] ne "\n") {
      # message not ended with an empty line
      print F "\n" or $err++;
   }

   truncate(F, ow::tool::untaint($origsize)) if $err;

   close(F) or writelog("cannot close file $folderfile");

   ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");

   return 0 if $err;

   return 1;
}

1;
