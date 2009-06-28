#
# fetchmail.pl - fetch mail messages from pop3 server
#
# 2004/07/02 tung.AT.turtle.ee.ncku.edu.tw
# 2002/03/19 eddie.AT.turtle.ee.ncku.edu.tw
#

use strict;
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

# since fetch mail from remote pop3 may be slow,
# the folder file lock is done inside routine,
# it happens when each one complete msg is retrieved

# fetch mail from pop3, call spamcheck/viruscheck
# then put X-OWM-VirusCheck and X-OWM-SpamCheck in message header
# ret >0: number of fetched msgs
#      0: no msg
#     -1: connect error
#     -2: pop3 error
#     -3: folder write error
sub fetchmail {
   my ($pop3host, $pop3port, $pop3ssl,
       $pop3user, $pop3passwd, $pop3del)=@_;
   $pop3host=ow::tool::untaint($pop3host);	# untaint for connection creation
   $pop3port=ow::tool::untaint($pop3port);

   my ($socket, $line, @result);
   eval {
      alarm 60; local $SIG{ALRM}= sub {die "alarm\n"};
      if ($pop3ssl && ow::tool::has_module('IO/Socket/SSL.pm')) {
         $socket=new IO::Socket::SSL (PeerAddr=>$pop3host, PeerPort=>$pop3port, Proto=>'tcp',);
      } else {
         $pop3port=110 if ($pop3ssl && $pop3port==995);
         $socket=new IO::Socket::INET (PeerAddr=>$pop3host, PeerPort=>$pop3port, Proto=>'tcp',);
      }
      $socket->autoflush(1);
      alarm 0;
   };
   return(-1, "connection timeout") if ($@); 		# timeout
   return(-1, "connection refused") if (!$socket);	# connect refused
   return(-1, "server not ready") if (!readdata($socket, \$line) || $line!~/^\+/);

   my $authlogin=0;
   if (sendcmd($socket, "auth login\r\n", \@result) &&
       sendcmd($socket, &encode_base64($pop3user), \@result) &&
       sendcmd($socket, &encode_base64($pop3passwd), \@result)) {
      $authlogin=1;
   }
   if (!$authlogin &&
       !(sendcmd($socket, "user $pop3user\r\n", \@result) &&
         sendcmd($socket, "pass $pop3passwd\r\n", \@result)) ) {
      sendcmd($socket, "quit\r\n", \@result); close($socket);
      return(-2, 'bad login');
   }

   my $msg_total;
   if (!sendcmd($socket, "stat\r\n", \@result)) {
      sendcmd($socket, "quit\r\n", \@result); close($socket);
      return (-2, 'stat error');
   }
   if (($msg_total=$result[0]) == 0) {			# no msg on pop3 server
      sendcmd($socket, "quit\r\n", \@result); close($socket);
      return (0, '');
   }

   my (%UIDLDB, %uidldb);				# %UIDLDB on disk, %uidldb in mem

   my $uidl_support=0;
   my $uidldb=dotpath("uidl.$pop3user\@$pop3host");
   if (sendcmd($socket, "uidl 1\r\n", \@result) &&	# 'uidl' supported on pop3 server
       ow::dbm::open(\%UIDLDB, $uidldb, LOCK_EX) ) {	# local uidldb ready
      $uidl_support=1;
   }
   my $last=-1;
   if (!$uidl_support) {
      if (sendcmd($socket, "last\r\n", \@result)) {	# 'last' supported
         if (($last=$result[0]) == $msg_total) {	# all msgs have already been read
            sendcmd($socket, "quit\r\n", \@result);
            close($socket);
            return (0, '');
         }
      } else {						# 'last' not supported
         if ($pop3del) {
            $last=0;
         } else {
            sendcmd($socket, "quit\r\n", \@result);
            close($socket);
            return (-2, 'uidl & last not supported');
         }
      }
   }

   my $spoolfile=(get_folderpath_folderdb($user, 'INBOX'))[0];

   my ($retr_total, $viruscheck_err, $spamcheck_err)=(0, 0, 0);

   foreach my $msgnum (1..$msg_total) {
      my $uidl;
      if ($uidl_support) {
         sendcmd($socket, "uidl $msgnum\r\n", \@result); $uidl=$result[1];
         if (defined $UIDLDB{$uidl}) {	# already fetched before
            $uidldb{$uidl}=1; next;
         }
      } else {
         next if ($msgnum<=$last);
      }

      if (!sendcmd($socket, "retr $msgnum\r\n", \@result)) {
         if ($uidl_support) {
            @UIDLDB{keys %uidldb}=values %uidldb if ($retr_total>0);
            ow::dbm::close(\%UIDLDB, $uidldb);
         }
         sendcmd($socket, "quit\r\n", \@result); close($socket);
         return (-2, 'retr error');
      }

      my $has_dilimeter=0;
      my $is_in_retcode=1;
      my $is_in_header=1;
      my ($msgfrom, $msgdate, $msgid, $msgsize, $headersize);
      my @lines=();

      while (1) {	# read else lines of message
         if (!readdata($socket, \$line)) {
            sendcmd($socket, "quit\r\n", \@result); close($socket);
            return (-2, 'retr data timeout');
         }

         if ($is_in_retcode) {
            next if ($line=~/^\+/);		# skip verbose +... retcode that appears before real data
            $has_dilimeter=1 if ($line=~/^From /);
            $is_in_retcode=0;
         }

         $line=~s/\r//g; 			# remove \r
         last if ($line eq ".\n" );		# end and leave while
         $line=~s/^\.\././;			# remove stuffing dot
         push(@lines, $line); $msgsize+=length($line);

         if ($is_in_header) { # try to get msgfrom/msgdate/msgid in header
            if ($line eq "\n") {
               $is_in_header=0; $headersize=$msgsize;
            } elsif ($line=~/^Message\-Id:\s+(.*)\s*$/i) {
               $msgid=$1 if ($msgid eq '');
            } elsif (!$has_dilimeter) {
               if ($line=~/^From:\s+(.+)\s*$/i) {
                  $msgfrom=get_fromemail($1) if ($msgfrom eq '');
               } elsif ($line=~/\(envelope\-from \s*(.+?)\s*\)/i) {
                  $msgfrom = $1 if ($msgfrom eq '');
               } elsif ($line=~/^Date:\s+(.*)\s*$/i) {
                  $msgdate=$1 if ($msgdate eq '');
               }
            }
         }
      }

      my $faked_dilimeter='';
      if (!$has_dilimeter) {
         my $dateserial=ow::datetime::datefield2dateserial($msgdate);
         my $dateserial_gm=ow::datetime::gmtime2dateserial();
         if ($dateserial eq "" ||
             ow::datetime::dateserial2gmtime($dateserial) -
             ow::datetime::dateserial2gmtime($dateserial_gm) > 86400 ) {
            $dateserial=$dateserial_gm;	# use current time if msg time is newer than now for 1 day
         }
         if ($config{'deliver_use_gmt'}) {
            $msgdate=ow::datetime::dateserial2delimiter($dateserial, "", $prefs{'daylightsaving'}, $prefs{'timezone'});
         } else {
            $msgdate=ow::datetime::dateserial2delimiter($dateserial, ow::datetime::gettimeoffset(), $prefs{'daylightsaving'}, $prefs{'timezone'});
         }
         $faked_dilimeter="From $msgfrom $msgdate\n";
      }

      # 1. virus check
      my ($virus_found, $viruscheck_xheader)=(0, '');
      if ($config{'enable_viruscheck'} &&
          ($prefs{'viruscheck_source'} eq 'all' || $prefs{'viruscheck_source'} eq 'pop3') &&
          !$viruscheck_err &&
          $msgsize <= $prefs{'viruscheck_maxsize'}*1024 &&
          $msgsize-$headersize > $prefs{'viruscheck_minbodysize'}*1024 ) {
         my @completemsg = ($has_dilimeter?@lines:($faked_dilimeter, @lines));
         writelog("debug - viruscheck forking cmd $config{'viruscheck_pipe'} for msg $msgid from $pop3user\@$pop3host") if $config{debug_fork};
         my ($ret, $report, $virusname) = ow::viruscheck::scanmsg($config{'viruscheck_pipe'}, \@completemsg);
         if ($ret<0) {
            writelog("viruscheck - pipe error - $report");
            writehistory("viruscheck - pipe error - $report");
            $viruscheck_err++;
         } elsif ($ret>0) {
            writelog("viruscheck - virus $virusname found in msg $msgid from $pop3user\@$pop3host");
            writehistory("viruscheck - virus $virusname found in msg $msgid from $pop3user\@$pop3host");
            $virus_found=1;
            $viruscheck_xheader="X-OWM-VirusCheck: virus $virusname found\n";
            if (defined $report && $report && $prefs{'viruscheck_include_report'}) {
               # replace blank lines with ----
               $report =~ s#([\n\r])([\n\r])#$1----$2#gs;
               # remove trailing space
               $report =~ s#\s+$##gs;
               # rfc822 folding of report
               $report =~ s#([\n\r]+)#$1  #gs;
               $viruscheck_xheader.=sprintf("X-OWM-VirusReport: $report\n");
            }
         } else {
            $viruscheck_xheader="X-OWM-VirusCheck: clean\n";
            writelog("debug - not infected for msg $msgid from $pop3user\@$pop3host, ret: $report") if $config{debug_fork};
         }
      }

      # 2. spam check
      my ($spam_found, $spamcheck_xheader)=(0, '');;
      if (!$virus_found
          && $config{'enable_spamcheck'}
          && ($prefs{'spamcheck_source'} eq 'all' || $prefs{'spamcheck_source'} eq 'pop3')
          && !$spamcheck_err
          && $msgsize <= $prefs{'spamcheck_maxsize'}*1024 ) {
         my @completemsg = ($has_dilimeter?@lines:($faked_dilimeter, @lines));
         writelog("debug - spamcheck forking cmd $config{'spamcheck_pipe'} for msg $msgid from $pop3user\@$pop3host") if $config{debug_fork};
         my ($spamscore, $report)=ow::spamcheck::scanmsg($config{'spamcheck_pipe'}, \@completemsg);
         if ($spamscore == -99999) {
            writelog("spamcheck - pipe error - $report");
            writehistory("spamcheck - pipe error - $report");
            $spamcheck_err++;
         } elsif ($spamscore > $prefs{'spamcheck_threshold'}) {
            writelog("spamcheck - spam $spamscore/$prefs{'spamcheck_threshold'} found in msg $msgid from $pop3user\@$pop3host");
            writehistory("spamcheck - spam $spamscore/$prefs{'spamcheck_threshold'} found in msg $msgid from $pop3user\@$pop3host");
            $spam_found=1;
            $spamcheck_xheader=sprintf("X-OWM-SpamCheck: %s %.1f/%.1f\n", '*' x $spamscore, $spamscore, $prefs{'spamcheck_threshold'});
            if (defined $report && $report && $prefs{'spamcheck_include_report'}) {
               # replace blank lines with ----
               $report =~ s#([\n\r])([\n\r])#$1----$2#gs;
               # remove trailing space
               $report =~ s#\s+$##gs;
               # rfc822 folding of report
               $report =~ s#([\n\r]+)#$1  #gs;
               $spamcheck_xheader.=sprintf("X-OWM-SpamReport: $report\n");
            }
         } else {
            $spamcheck_xheader=sprintf("X-OWM-SpamCheck: %s %.1f/%.1f\n", '*' x $spamscore, $spamscore, $prefs{'spamcheck_threshold'});
            writelog("debug - not spam $spamscore/$prefs{'spamcheck_threshold'} for msg $msgid from $pop3user\@$pop3host") if $config{debug_fork};
         }
      }

      # append message to mail folder
      if (!append_pop3msg_to_folder($faked_dilimeter, $viruscheck_xheader, $spamcheck_xheader, \@lines, $spoolfile)) {
         if ($uidl_support) {
            @UIDLDB{keys %uidldb}=values %uidldb if ($retr_total>0);
            ow::dbm::close(\%UIDLDB, $uidldb);
         }
         sendcmd($socket, "quit\r\n", \@result); close($socket);
         return (-3, "$spoolfile write error");
      }
      if (! ($pop3del && sendcmd($socket, "dele $msgnum\r\n", \@result)) ) {
         $uidldb{$uidl}=1 if ($uidl_support);
      }

      $retr_total++;
   }

   if ($uidl_support) {
      %UIDLDB=%uidldb if ($retr_total>0);
      ow::dbm::close(\%UIDLDB, $uidldb);
   }

   sendcmd($socket, "quit\r\n", \@result); close($socket);
   return($retr_total);	# number of fetched mail
}


sub sendcmd {
   my ($socket, $cmd, $r_result, $timeout)=@_;
   $timeout=60 if ($timeout<=0);

   my $ret;
   eval {
      alarm $timeout; local $SIG{ALRM}= sub {die "alarm\n"};
      print $socket $cmd; $ret=<$socket>;
      alarm 0;
   };
   return 0 if ($@); 		# timeout
   return 0 if ($ret eq '');	# socket not available?

   @{$r_result}=split(/\s+/, $ret);
   shift @{$r_result} if (${$r_result}[0]=~/^[\+\-]/); # rm str +OK or -ERR from @result
   return 1 if ($ret!~/^\-/);
   return 0;
}

sub readdata {
   my ($socket, $r_line, $timeout)=@_;
   $timeout=60 if ($timeout<=0);

   ${$r_line}='';	# empty line buff
   eval {
      alarm $timeout; local $SIG{ALRM}= sub {die "alarm\n"};
      ${$r_line}=<$socket>;
      alarm 0;
   };
   return 0 if ($@); 			# timeout
   return 0 if (${$r_line} eq '');	# socket not available?

   return 1;
}

sub get_fromemail {
   $_=$_[0];
   if (/^"?(.+?)"?\s*<(.*)>$/ ) {
      return $2;
   } elsif (/<?(.*@.*)>?\s+\((.+?)\)/ ) {
      return $1;
   } elsif (/<\s*(.+@.+)\s*>/ ) {
      return $1;
   } else {
      s/\s*(.+@.+)\s*/$1/;
      return $_;
   }
}

sub append_pop3msg_to_folder {
   my ($faked_dilimeter, $viruscheck_xheader, $spamcheck_xheader, $r_lines, $folderfile)=@_;

   if (!-f $folderfile) {
      sysopen(F, $folderfile, O_WRONLY|O_APPEND|O_CREAT); close(F);
   }
   return 0 if (!ow::filelock::lock($folderfile, LOCK_EX));
   if (!sysopen(F, $folderfile, O_WRONLY|O_APPEND|O_CREAT)) {
      ow::filelock::lock($folderfile, LOCK_UN);
      return 0;
   }

   my $err=0;
   my $origsize=(stat(F))[7];
   seek(F, $origsize, 0);	# seek to file end
   if ($faked_dilimeter ne '') {
      print F $faked_dilimeter or $err++;
   }

   my $is_in_header=1;
   foreach (@{$r_lines}) {
      last if ($err>0);
      if ($is_in_header && $_ eq "\n") {
         $is_in_header=0;
         if ($viruscheck_xheader ne '') {
            print F $viruscheck_xheader or $err++;
         }
         if ($spamcheck_xheader ne '') {
            print F $spamcheck_xheader or $err++;
         }
      }
      print F $_ or $err++;
   }

   if (!$err && $#{$r_lines}>=0 &&
      ${$r_lines}[$#{$r_lines}] ne "\n") { # msg not ended with empty line
      print F "\n" or $err++;
   }
   truncate(F, ow::tool::untaint($origsize)) if ($err);
   close(F);
   ow::filelock::lock($folderfile, LOCK_UN);

   return 0 if ($err);
   return 1;
}

1;
