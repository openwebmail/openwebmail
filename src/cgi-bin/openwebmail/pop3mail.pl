#
# pop3mail.pl - functions for pop3 mail retrieval
#
# 2002/03/19 eddie@turtle.ee.ncku.edu.tw
#            tung@turtle.ee.ncku.edu.tw
#

use strict;
use Fcntl qw(:DEFAULT :flock);
use FileHandle;
use IO::Socket;

use vars qw(%config);

# return < 0 means error
# -1 pop3book read error
# -2 connect error
# -3 server not ready
# -4 user name error
# -5 password error
# -6 stat error
# -7 retr error
# -8 spool write error
# -9 pop3book write error

sub retrpop3mail {
   my ($pop3host, $pop3user, $pop3book, $spoolfile)=@_;
   my (%accounts, $pop3passwd, $pop3lastid, $pop3del, $enable);
   my ($ServerPort, $remote_sock);
   my ($uidl_support, $uidl_field);
   my ($last, $nMailCount, $retr_total);
   my ($dummy, $i);

   if ( readpop3book($pop3book, \%accounts)<0 ) {
      return(-1);
   }

   ($dummy, $dummy, $pop3passwd, $pop3lastid, $pop3del, $enable)=
			split(/\@\@\@/, $accounts{"$pop3host:$pop3user"});

   # untaint for file creation
   ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1); 	
   # untaint for connection creation
   ($pop3host =~ /^(.+)$/) && ($pop3host = $1); 	

   $ServerPort='110';
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 10;
      $remote_sock=new IO::Socket::INET(   Proto=>'tcp',
                                           PeerAddr=>$pop3host,
                                           PeerPort=>$ServerPort,);
      alarm 0;
   };
   return(-2) if ($@);			# eval error, it means timeout
   return(-2) if (!$remote_sock);	# connect error

   $remote_sock->autoflush(1);
   $_=<$remote_sock>;
   return(-3) if (/^\-/);		# server not ready

   print $remote_sock "user $pop3user\r\n";
   $_=<$remote_sock>;
   return(-4) if (/^\-/);		# username error

   print $remote_sock "pass $pop3passwd\r\n";
   $_=<$remote_sock>;
   return (-5) if (/^\-/);		# passwd error

   print $remote_sock "stat\r\n";
   $_=<$remote_sock>;
   return(-6) if (/^\-/);		# stat error

   $nMailCount=(split(/\s/))[1];
   if ($nMailCount == 0) {		# no message
      print $remote_sock "quit\r\n";
      return 0;
   }

   $last=-1;
   $uidl_support=0;
   $uidl_field=2;

   # use 'uidl' to find the msg being retrieved last time
   print $remote_sock "uidl " . $nMailCount . "\r\n";
   $_ = <$remote_sock>;

   if (/^\-/) {	# pop3d not support uidl, try last command
      # use 'last' to find the msg being retrieved last time
      print $remote_sock "last\r\n";
      $_ = <$remote_sock>; s/^\s+//;
      if (/^\+/) { # server does support last
         $last=(split(/\s/))[1];		# +OK N
         if ($last eq $nMailCount) {
            print $remote_sock "quit\r\n";
            return 0;
         }
      }

   } else {	# pop3d does support uidl
      $uidl_support=1;
      if (/^\+/) {
         $uidl_field=2;
      } else {
         $uidl_field=1;	# some broken pop3d return uidl without leading +
      }

      if ($pop3lastid eq (split(/\s/))[$uidl_field]) {	# +OK N ID
         print $remote_sock "quit\r\n";
         return 0;
      }
      if ($pop3lastid ne "none") {
         for ($i=1; $i<$nMailCount; $i++) {
            print $remote_sock "uidl ".$i."\r\n";
            $_ = <$remote_sock>; s/^\s+//;
            if ($pop3lastid eq (split(/\s/))[$uidl_field]) {
               $last = $i;
               last;
            }
         }

      } else {
         $last = 0;
      }
   }

   # if last retrieved msg not found, fetech from the beginning
   $last=0 if ($last==-1);
   # set lastid to none if fetech from the beginning
   $pop3lastid="none" if ($last==0);

   # retr messages
   $retr_total=0;
   for ($i=$last+1; $i<=$nMailCount; $i++) {
      my ($FileContent,$stAddress,$stDate)=("","","");

      print $remote_sock "retr ".$i."\r\n";
      while (<$remote_sock>) {	# use loop to filter out verbose output
         if ( /^\+/ ) {
            next;
         } elsif (/^\-/) {
            return(-7);
         } else {
            last;
         }
      }

      # first line of message
      if ( /^From / ) {
         $FileContent = "";	#drop 1st line if containing msg delimiter
      } else {
         s/\s+$//;
         $FileContent = "$_\n";
         $stDate=$1 if ( /^Date:\s+(.*)$/i);
      }

      #####  read else lines of message
      while ( <$remote_sock>) {
         s/\s+$//;
         last if ($_ eq "." );	#end and exit while
         $FileContent .= "$_\n";
         # get $stAddress, $stDate to compose the mail delimiter 'From xxxx' line
         if ( /\(envelope\-from \s*(.+?)\s*\)/i && $stAddress eq "" ) {
            $stAddress = $1;
         } elsif ( /^from:\s+(.+)$/i && $stAddress eq "" ) {
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
            $stAddress = $_;

         } elsif ( /^Date:\s+(.*)$/i && $stDate eq "" ) {
            $stDate=$1;
         }
      }


      my $dateserial=datefield2dateserial($stDate);
      my $gmserial=gmtime2dateserial();
      if ($dateserial eq "" ||
          dateserial2daydiff($dateserial)-dateserial2daydiff($gmserial)>1 ) {
         $dateserial=$gmserial;	# use current time if msg time is newer than now
      }
      if ($config{'deliver_use_GMT'}) {
         $stDate=dateserial2delimiter($dateserial, "");
      } else {
         $stDate=dateserial2delimiter($dateserial, gettimeoffset());
      }

      # append message to mail folder
      filelock($spoolfile, LOCK_EX);
      open(IN,">>$spoolfile") or return(-8);
      print IN "From $stAddress $stDate\n";
      print IN $FileContent;
      print IN "\n";		# mark mail end 
      close(IN);
      filelock($spoolfile, LOCK_UN);

      if ($uidl_support) {
         print $remote_sock "uidl " . $i . "\r\n";
         $_=<$remote_sock>; s/^\s+//;
         if ($_ !~ /^\-/) {
            $pop3lastid=(split(/\s/))[$uidl_field];
         }
      }

      if ($pop3del == 1) {
         print $remote_sock "dele " . $i . "\r\n";
         $_=<$remote_sock>;
      }

      $retr_total++;
   }
   print $remote_sock "quit\r\n";
   close($remote_sock);

   ###  write back to pop3book
   $accounts{"$pop3host:$pop3user"} = "$pop3host\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3lastid\@\@\@$pop3del\@\@\@$enable";
   if (writepop3book($pop3book, \%accounts)<0) {
      return(-9);
   }

   # return number of fetched mail
   return($retr_total);		
}

1;
