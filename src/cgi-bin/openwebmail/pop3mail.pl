#
# pop3mail.pl - pop3 mail retrieval routines
#
# 2003/05/25 tung@turtle.ee.ncku.edu.tw
# 2002/03/19 eddie@turtle.ee.ncku.edu.tw
#

use strict;
use Fcntl qw(:DEFAULT :flock);
use IO::Socket;
require "mime.pl";

use vars qw(%config);

# return < 0 means error
# -1 uidldb lock error
# -2 uidldb open error
# -3 spool write error
# -11 connect error
# -12 server not ready
# -13 user name error
# -14 password error
# -15 stat error
# -16 bad pop3 support
# -17 retr error
sub retrpop3mail {
   my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $uidldb, $spoolfile)=@_;
   my $remote_sock;

   # untaint for connection creation
   ($pop3host =~ /^(.+)$/) && ($pop3host = $1);
   ($pop3port =~ /^(.+)$/) && ($pop3port = $1);
   # untaint for file creation
   ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1);
   # untaint for uidldb creation
   ($uidldb =~ /^(.+)$/) && ($uidldb = $1);		# untaint ...

   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 30;
      $remote_sock=new IO::Socket::INET(   Proto=>'tcp',
                                           PeerAddr=>$pop3host,
                                           PeerPort=>$pop3port);
      alarm 0;
   };
   return -11 if ($@);			# eval error, it means timeout
   return -11 if (!$remote_sock);	# connect error

   $remote_sock->autoflush(1);
   $_=<$remote_sock>;
   return -12 if (/^\-/);		# server not ready

   # try if server supports auth login(base64 encoding) first
   print $remote_sock "auth login\r\n";
   $_=<$remote_sock>;
   if (/^\+/) {
      print $remote_sock &encode_base64($pop3user);
      $_=<$remote_sock>;
      (close($remote_sock) && return -13) if (/^\-/);		# username error
      print $remote_sock &encode_base64($pop3passwd);
      $_=<$remote_sock>;
   }

   if (! /^\+/) {	# not supporting auth login or auth login failed
      print $remote_sock "user $pop3user\r\n";
      $_=<$remote_sock>;
      (close($remote_sock) && return -13) if (/^\-/);		# username error
      print $remote_sock "pass $pop3passwd\r\n";
      $_=<$remote_sock>;
      (close($remote_sock) && return -14) if (/^\-/);		# passwd error
   }
   print $remote_sock "stat\r\n";
   $_=<$remote_sock>;
   (close($remote_sock) && return -15) if (/^\-/);		# stat error


   my ($mailcount, $retr_total)=(0, 0);
   my ($uidl_support, $uidl_field, $uidl, $last)=(0, 2, -1, 0);
   my (%UIDLDB, %uidldb);

   $mailcount=(split(/\s/))[1];
   if ($mailcount == 0) {		# no message
      print $remote_sock "quit\r\n";
      close($remote_sock);
      return 0;
   }

   # use 'uidl' to find the msg being retrieved last time
   print $remote_sock "uidl 1\r\n";
   $_ = <$remote_sock>;

   if (/^\-/) {	# pop3d not support uidl, try last command
      # use 'last' to find the msg being retrieved last time
      print $remote_sock "last\r\n";
      $_ = <$remote_sock>; s/^\s+//;
      if (/^\+/) { # server does support last
         $last=(split(/\s/))[1];		# +OK N
         if ($last eq $mailcount) {
            print $remote_sock "quit\r\n";
            close($remote_sock);
            return 0;
         }
      } else {
         return -16;	# both uid and last not supported
      }

   } else {	# pop3d does support uidl
      $uidl_support=1;
      if (/^\+/) {
         $uidl_field=2;
      } else {
         $uidl_field=1;	# some broken pop3d return uidl without leading +
      }
      if (!$config{'dbmopen_haslock'}) {
         if (!filelock("$uidldb$config{'dbm_ext'}", LOCK_EX|LOCK_NB)) {
            close($remote_sock);
            return -1;
         }
      }
      if (!dbmopen(%UIDLDB, "$uidldb$config{'dbmopen_ext'}", 0600)) {
         filelock("$uidldb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
         close($remote_sock);
         return -2;
      }
   }

   # retr messages
   for (my $i=$last+1; $i<=$mailcount; $i++) {
      my ($msgcontent, $msgfrom, $msgdate)=("", "", "");

      if ($uidl_support) {
         print $remote_sock "uidl $i\r\n";
         $_ = <$remote_sock>;
         $uidl=(split(/\s/))[$uidl_field];
         if ( defined($UIDLDB{$uidl}) ) {		# already fetched before
            $uidldb{$uidl}=1; next;
         }
      }
          
      print $remote_sock "retr ".$i."\r\n";
      while (<$remote_sock>) {	# use loop to filter out verbose output
         if ( /^\+/ ) {
            next;
         } elsif (/^\-/) {
            if ($uidl_support) {
               @UIDLDB{keys %uidldb}=values %uidldb if ($retr_total>0);
               dbmclose(%UIDLDB);
               filelock("$uidldb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
            }
            close($remote_sock);
            return -17;
         } else {
            last;
         }
      }

      # first line of message
      if ( /^From / ) {
         $msgcontent = "";	#drop 1st line if containing msg delimiter
      } else {
         s/\s+$//;
         $msgcontent = "$_\n";
         $msgdate=$1 if ( /^Date:\s+(.*)$/i);
      }

      #####  read else lines of message
      while ( <$remote_sock>) {
         s/\s+$//;
         last if ($_ eq "." );	#end and exit while
         $msgcontent .= "$_\n";
         # get $msgfrom, $msgdate to compose the mail delimiter 'From xxxx' line
         if ( /\(envelope\-from \s*(.+?)\s*\)/i && $msgfrom eq "" ) {
            $msgfrom = $1;
         } elsif ( /^from:\s+(.+)$/i && $msgfrom eq "" ) {
            $_ = $1;
            if ($_=~ /^"?(.+?)"?\s*<(.*)>$/ ) {
               $_ = $2;
            } elsif ($_=~ /<?(.*@.*)>?\s+\((.+?)\)/ ) {
               $_ = $1;
            } elsif ($_=~ /<\s*(.+@.+)\s*>/ ) {
               $_ = $1;
            } else {
               $_=~ s/\s*(.+@.+)\s*/$1/;
            }
            $msgfrom = $_;

         } elsif ( /^Date:\s+(.*)$/i && $msgdate eq "" ) {
            $msgdate=$1;
         }
      }

      my $dateserial=datefield2dateserial($msgdate);
      my $gmserial=gmtime2dateserial();
      if ($dateserial eq "" ||
          dateserial2gmtime($dateserial)-dateserial2gmtime($gmserial)>86400 ) {
         $dateserial=$gmserial;	# use current time if msg time is newer than now for 1 day
      }
      if ($config{'deliver_use_GMT'}) {
         $msgdate=dateserial2delimiter($dateserial, "");
      } else {
         $msgdate=dateserial2delimiter($dateserial, gettimeoffset());
      }

      # append message to mail folder
      my $append=0;;
      if (filelock($spoolfile, LOCK_EX)) {
         if (open(IN,">>$spoolfile")) {
            print IN "From $msgfrom $msgdate\n";
            print IN $msgcontent;
            print IN "\n";		# mark mail end
            close(IN);
            $append=1;
         } 
         filelock($spoolfile, LOCK_UN);
      } 
      if (!$append) {
         if ($uidl_support) {
            @UIDLDB{keys %uidldb}=values %uidldb if ($retr_total>0);
            dbmclose(%UIDLDB);
            filelock("$uidldb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
         }
         close($remote_sock);
         return -3;
      }

      if ($pop3del == 1) {
         print $remote_sock "dele $i\r\n";
         $_=<$remote_sock>;
         $uidldb{$uidl}=1 if ($uidl_support && !/^\+/);
      } else {
         $uidldb{$uidl}=1 if ($uidl_support);
      }
      $retr_total++;
   }

   print $remote_sock "quit\r\n";
   close($remote_sock);

   if ($uidl_support) {
      %UIDLDB=%uidldb if ($retr_total>0);
      dbmclose(%UIDLDB);
      filelock("$uidldb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   }

   # return number of fetched mail
   return($retr_total);
}

1;
