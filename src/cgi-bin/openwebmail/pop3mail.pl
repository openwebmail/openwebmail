use strict;
#
# pop3mail.pl - functions for pop3 mail retrieval
#
# 2001/06/01 eddie@turtle.ee.ncku.edu.tw
#

use Fcntl qw(:DEFAULT :flock);
use FileHandle;
use IO::Socket;

sub getpop3book {
   my ($pop3book, $r_accounts) = @_;
   my $i=0;

   %{$r_accounts}=();

   if ( -f "$pop3book" ) {
      filelock($pop3book, LOCK_SH);
      open (POP3BOOK,"$pop3book") or return(-1);
      while (<POP3BOOK>) {
      	 chomp($_);
      	 my ($pop3host, $pop3user, $pop3passwd, $pop3email, $pop3del, $lastid) = split(/:/, $_);
         if ($lastid eq '') {	# compatible with old version
      	    ($pop3host, $pop3user, $pop3passwd, $pop3del, $lastid) = split(/:/, $_);
            $pop3email="$pop3user\@$pop3host";
         }
         ${$r_accounts}{"$pop3host:$pop3user"} = "$pop3host:$pop3user:$pop3passwd:$pop3email:$pop3del:$lastid";
         $i++;
      }
      close (POP3BOOK);
      filelock($pop3book, LOCK_UN);
   }
   return($i);
}

sub writebackpop3book {
   my ($pop3book, $r_accounts) = @_;

   if ( -f "$pop3book" ) {
      filelock($pop3book, LOCK_EX);
      open (POP3BOOK,">$pop3book") or
         return (-1);
      foreach (values %{$r_accounts}) {
      	 chomp($_);
      	 print POP3BOOK $_ . "\n";
      }
      close (POP3BOOK);
      filelock($pop3book, LOCK_UN);
   }
   return(0);
}


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
   my (%accounts, $pop3passwd, $pop3email, $pop3del, $lastid);
   my ($ServerPort, $remote_sock);
   my ($last, $nMailCount, $support_uidl, $retr_total);
   my ($dummy, $i);

   if ( getpop3book($pop3book, \%accounts)<0 ) {
      return(-1);
   }

   ($dummy, $dummy, $pop3passwd, $pop3email, $pop3del, $lastid)=
			split(/:/, $accounts{"$pop3host:$pop3user"});

   # bypass taint check for file create
   ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1); 	
   ($pop3host =~ /^(.+)$/) && ($pop3host = $1); 	

   $ServerPort='110';
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 5;
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
   $support_uidl=0;

   # use 'uidl' to find the msg being retrieved last time
   print $remote_sock "uidl " . $nMailCount . "\r\n";
   $_ = <$remote_sock>;
   if (/^\+/) {
      $support_uidl=1;
      if ($lastid eq (split(/\s/))[2]) {	# +OK N ID
         print $remote_sock "quit\r\n";
         return 0;
      }
      if ($lastid ne "none") {
         for ($i=1; $i<$nMailCount; $i++) {
            print $remote_sock "uidl ".$i."\r\n";
            $_ = <$remote_sock>;
            if ($lastid eq (split(/\s/))[2]) {
               $last = $i;
               last;
            }
         }
      } else {
         $last = 1;
      }

   # use 'last' to find the msg being retrieved last time
   } else {
      print $remote_sock "last\r\n";
      $_ = <$remote_sock>;
      if (/^\+/) { # server does support last
         $last=(split(/\s/))[1];		# +OK N
         if ($last eq $nMailCount) {
            print $remote_sock "quit\r\n";
            return 0;
         }
      }
   }

   # if last retrieved msg not found, fetech from the beginning
   $last=0 if ($last==-1);

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
      s/\s+$//;
      $FileContent = "$_\n";

      #####  read else lines of message
      while ( <$remote_sock>) {
         s/\s+$//;
         last if ($_ eq "." );	#end and exit while
         $FileContent .= "$_\n";

         # get $stAddress, $stDate to compose the mail delimer 'From xxxx' line
         if ( /^from:\s+(.+)$/i && $stAddress eq "" ) {
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

         } elsif ( /^Date:/ && $stDate eq "" ) {
             my @monthstr=qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
             my @wdaystr=qw(Sun Mon Tus Wen Thu Fri Sat);
             my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime;

             $year=$year+1900;
             $mon=$monthstr[$mon]; 
             $wday=$wdaystr[$wday];

             if (/^Date:\s+(\w+),\s+(\d+)\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s/) { 
                 #Date: Wed, 9 Sep 1998 19:30:16 +0800 (CST)
                 $wday=$1; $mday=$2; $mon=$3; $year=$4; $hour=$5; $min=$6; $sec=$7;
             } elsif (/^Date:\s+(\d+)\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s/) { 
                 #Date: 07 Sep 2000 23:01:36 +0200
                 $mday=$1; $mon=$2; $year=$3; $hour=$4; $min=$5; $sec=$6;
             } elsif (/^Date:\s+(\w+),\s+(\w+)\s+(\d+),\s+(\d+)\s+(\d+):(\d+):(\d+)\s/) { 
                 #Date: Wednesday, February 10, 1999 3:39 PM
                 $wday=$1; $mon=$2; $mday=$3; $year=$4; $hour=$5; $min=$6; $sec=$7;
                 $wday=~s/^(...).*/$1/;
                 $mon=~s/^(...).*/$1/;
             }
             $stDate=sprintf("%3s %3s %2d %02d:%02d:%02d %4d",
                             $wday, $mon, $mday, $hour,$min,$sec, $year);
         }
      }

      # append message to mail folder
      filelock($spoolfile, LOCK_EX);
      open(IN,">>$spoolfile") or return(-8);
      print IN "From $stAddress $stDate\n";
      print IN $FileContent;
      print IN "\n";		# mark mail end 
      close(IN);
      filelock($spoolfile, LOCK_UN);

      if ($pop3del == 1) {
         print $remote_sock "dele " . $i . "\r\n";
         $_=<$remote_sock>;
      }

      $lastid="none";
      if ($support_uidl) {
         print $remote_sock "uidl " . $i . "\r\n";
         $_=<$remote_sock>;
         if (/^\+/) {
            $lastid=(split(/\s/))[2];
         }
      }

      $retr_total++;
   }
   print $remote_sock "quit\r\n";
   close($remote_sock);

   ###  write back to pop3book
   $accounts{"$pop3host:$pop3user"} = "$pop3host:$pop3user:$pop3passwd:$pop3email:$pop3del:$lastid";
   if (writebackpop3book($pop3book, \%accounts)<0) {
      return(-9);
   }

   # return number of fetched mail
   return($retr_total);		
}

1;
