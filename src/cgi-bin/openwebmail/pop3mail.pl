#
# pop3mail.pl - functions for pop3 mail retrieval
#
# 2001/02/15 eddie@turtle.ee.ncku.edu.tw
#

use Fcntl qw(:DEFAULT :flock);
use FileHandle;
use IO::Socket;

sub getpop3book {
   my $pop3book = $_[0];
   my %account;

   if ( -f "$pop3book" ) {
      filelock($pop3book, LOCK_SH);
      open (POP3BOOK,"$pop3book") or
         return ();
      while (<POP3BOOK>) {
      	 chomp($_);
      	 my ($pop3host, $pop3user, $pop3passwd, $pop3del, $lastid) = split(/:/, $_);
         $account{"$pop3host:$pop3user"} = "$pop3host:$pop3user:$pop3passwd:$pop3del:$lastid";
      }
      close (POP3BOOK);
      filelock($pop3book, LOCK_UN);
   }
   return %account;
}

sub writebackpop3book {
   my ($pop3book, %accounts) = @_;

   if ( -f "$pop3book" ) {
      filelock($pop3book, LOCK_EX);
      open (POP3BOOK,">$pop3book") or
         return (-6);
      foreach (values %accounts) {
      	 chomp($_);
      	 print POP3BOOK $_ . "\n";
      }
      close (POP3BOOK);
      filelock($pop3book, LOCK_UN);
   }
}

sub retrpop3mail {
   my ($pop3host, $pop3user, $pop3book, $spoolfile)=@_;
   my (%accounts, $pop3passwd, $pop3del, $lastid);
   my ($ServerPort, $remote_sock);
   my ($locate, $nMailCount, $newid);
   my ($dummy, $i);

   %accounts = getpop3book($pop3book);
   ($dummy, $dummy, $pop3passwd, $pop3del, $lastid)=
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
   if ($@) {	# eval error, it means timeout
       return(-3);
   }
   if (!$remote_sock) { # connect error
       return(-3);
   }

   $remote_sock->autoflush(1);

   $_=<$remote_sock>;
   if (/^\-/) {
      return(-3);
   }

   print $remote_sock "user $pop3user\n";
   $_=<$remote_sock>;
   if (/^\-/) {
      return(-3);
   }

   print $remote_sock "pass $pop3passwd\n";
   $_=<$remote_sock>;
   if (/^\-/) {
      return(-4);
   }

   print $remote_sock "stat\n";
   $_=<$remote_sock>;
   if (/^\-/) {
      return(-3);
   }
   ($dummy, $nMailCount, $dummy) = split(/\s/,$_);
   if ($nMailCount == 0) {
      print $remote_sock "quit\n";
      return 0;
   }

   print $remote_sock "uidl " . $nMailCount . "\n";
   $_ = <$remote_sock>;
   if (/^\-/) {
      return(-3);
   }
   ($dummy, $dummy, $newid)=split(/\s/);
   if ($newid eq $lastid) {
      print $remote_sock "quit\n";
      return 0;
   }

   $locate = 1;
   for ($i=1; $i<=$nMailCount; $i++) {
      print $remote_sock "uidl ".$i."\n";
      $_ = <$remote_sock>;
      split(/\s/,$_);
      if ($lastid eq $_[2]) {
         $locate = $i;
   	 last;
      }
   }
   
   ### retr all messages
   for ($i=$locate; $i<=$nMailCount; $i++) {
      my ($FileContent,$stAddress,$stDate)=("","","");

      print $remote_sock "retr ".$i."\n";
      while (<$remote_sock>) {	# use loop to filter out verbose output
         if ( /^\+/ ) {
            next;
         } elsif (/^\-/) {
            return(-5);
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
         if ($_ eq "." ) {
            last;		#end and exit while
         }
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
             my $time="$hour:$min:$sec";

             $year=$year+1900;
             $mon=$monthstr[$mon]; 
             $wday=$wdaystr[$wday];

             if (/^Date:\s+(\w+),\s+(\d+)\s+(\w+)\s+(\d+)\s+([\d:]+)/) { 
                 #Date: Wed, 9 Sep 1998 19:30:16 +0800 (CST)
                 $wday=$1; $mday=$2; $mon=$3; $year=$4; $time=$5;
             } elsif (/^Date:\s+(\d+)\s+(\w+)\s+(\d+)\s+([\d:]+)/) { 
                 #Date: 07 Sep 2000 23:01:36 +0200
                 $mday=$1; $mon=$2; $year=$3; $time=$4;
             } elsif (/^Date:\s+(\w+),\s+(\w+)\s+(\d+),\s+(\d+)\s+([\d:]+)/) { 
                 #Date: Wednesday, February 10, 1999 3:39 PM
                 $wday=$1; $mon=$2; $mday=$3; $year=$4; $time=$5;
                 $wday=~s/^(...).*/$1/;
                 $mon=~s/^(...).*/$1/;
             }
             $stDate="$wday $mon $mday $time $year";
         }
      }

      # append message to mail folder
      filelock($spoolfile, LOCK_EX);
      open(IN,">>$spoolfile") or return(-2);
      print IN "From $stAddress $stDate\n";
      print IN $FileContent;
      print IN "\n";		# mark mail end 
      close(IN);
      filelock($spoolfile, LOCK_UN);

      if ($pop3del == 1) {
         print $remote_sock "dele " . $i . "\n";
      }
   }

   ###  write back to pop3book
   $accounts{"$pop3host:$pop3user"} = "$pop3host:$pop3user:$pop3passwd:$pop3del:$newid";
   writebackpop3book($pop3book, %accounts);
   print $remote_sock "quit\n";
   return($nMailCount-$locate+1);	# return number of fetched mail
}

1;
