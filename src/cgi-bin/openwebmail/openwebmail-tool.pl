#!/usr/bin/suidperl -T
#
# openwebmail-tool.pl - command tool for mail/event/notify/index...
#
# 11/04/2002 Ebola@turtle.ee.ncku.edu.tw
#            tung@turtle.ee.ncku.edu.tw
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(.*?)/[\w\d\-\.]+\.pl! ) {
   $SCRIPT_DIR=$1;
} elsif ( -f ($ENV{'openwebmail'}||$ENV{'PWD'})."/openwebmail-tool.pl" ) {
   $SCRIPT_DIR=$ENV{'openwebmail'}||$ENV{'PWD'};
   ($SCRIPT_DIR =~ /^(.+)$/) && ($SCRIPT_DIR = $1);  # untaint
}
if (!$SCRIPT_DIR) { 
   print "Please execute script openwebmail-tool.pl with full path\n".
         " or 'cd your_openwebmail_cgi_dir; ./openwebmail-tool.pl'\n"; 
   exit 1;
}
push (@INC, $SCRIPT_DIR, ".");

$ENV{PATH} = ""; 	# no PATH should be needed
$ENV{ENV} = "";		# no startup script for sh
$ENV{BASH_ENV} = ""; 	# no startup script for bash

use strict;
use Fcntl qw(:DEFAULT :flock);
use Net::SMTP;

require "ow-shared.pl";
require "mime.pl";
require "filelock.pl";
require "maildb.pl";
require "mailfilter.pl";
require "pop3mail.pl";
require "lunar.pl";
require "iconv-chinese.pl";

use vars qw(%config %config_raw);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw($folderdir);
use vars qw(%prefs);

# extern vars
use vars qw(@wdaystr);	# defined in ow-shared.pl
use vars qw($pop3_authserver);	# defined in auth_pop3.pl

################################ main ##################################

my $POP3_PROCESS_LIMIT=10;
my $POP3_TIMEOUT=20;

my @userlist=();
my %complete=();

my $opt_null=1;
my $opt_init=0;
my $opt_allusers=0;
my $opt_pop3=0;
my $opt_verify=0;
my $opt_size=0;
my $opt_zap=0;
my $opt_mail=0;
my $opt_event=0;
my $opt_notify=0;
my $opt_quiet=0;
my $opt_yes=0;
my $defaultdomain="";
my $pop3_process_count=0;

# handle zombie
$SIG{CHLD} = sub { my $pid=wait; $complete{$pid}=1; $pop3_process_count--; };
# no buffer on stdout
$|=1;

if ($ARGV[0] eq "--") {		# called by inetd
   push(@userlist, $ARGV[1]);
   $opt_mail=1; $opt_event=1; $opt_null=0;
} else {
   my $i=0;
   for ($i=0; $i<=$#ARGV; $i++) {
      if ($ARGV[$i] eq "--init") {
         $opt_init=1;
      } elsif ($ARGV[$i] eq "--yes" || $ARGV[$i] eq "-y") {
         $opt_yes=1;
      } elsif ($ARGV[$i] eq "--alluser" || $ARGV[$i] eq "-a") {
         $opt_allusers=1;
      } elsif ($ARGV[$i] eq "--domain" || $ARGV[$i] eq "-d") {
         $i++ if $ARGV[$i+1]!~/^\-/;
         $defaultdomain=$ARGV[$i];
      } elsif ($ARGV[$i] eq "--file" || $ARGV[$i] eq "-f") {
         $i++;
         if ( -f $ARGV[$i] ) {
            open(USER, $ARGV[$i]);
            while (<USER>) { chomp $_; push(@userlist, $_); }
            close(USER);
         }
      } elsif ($ARGV[$i] eq "--quiet" || $ARGV[$i] eq "-q") {
         $opt_quiet=1;
      } elsif ($ARGV[$i] eq "--event" || $ARGV[$i] eq "-e") {
         $opt_event=1; $opt_null=0;
      } elsif ($ARGV[$i] eq "--index" || $ARGV[$i] eq "-i") {
         $opt_verify=1; $opt_null=0;
      } elsif ($ARGV[$i] eq "--mail" || $ARGV[$i] eq "-m") {
         $opt_mail=1; $opt_null=0;
      } elsif ($ARGV[$i] eq "--notify" || $ARGV[$i] eq "-n") {
         $opt_notify=1; $opt_null=0;
      } elsif ($ARGV[$i] eq "--pop3" || $ARGV[$i] eq "-p") {
         $opt_pop3=1; $opt_null=0;
      } elsif ($ARGV[$i] eq "--size" || $ARGV[$i] eq "-s") {
         $opt_size=1; $opt_null=0;
      } elsif ($ARGV[$i] eq "--zaptrash" || $ARGV[$i] eq "-z") {
         $opt_zap=1; $opt_null=0;
      } else {
         push(@userlist, $ARGV[$i]);
      }
   }
}

if ($opt_init) {
   init(); exit 0;
} elsif ($opt_allusers) {
   allusers();
}


if ($#userlist<0 || $opt_null) {
   print "
Syntax: openwebmail-tool.pl --init [-y]
        openwebmail-tool.pl [options] [user1 user2 ...]

options:

-a, --alluser\t check for all users in passwd
-d, --domain \t default domain for user with no domain specified
-e, --event  \t check today's calendar event
-f, --file   \t user list file, each line contains a username
-i, --index  \t check index for user folders and reindex if needed
-m, --mail   \t check mail
-n, --notify \t check and send calendar notification email
-p, --pop3   \t fetch pop3 mail for user
-q, --quite  \t quiet, no output
-s, --size   \t check folder size, then cut them until under quota
-y, --yes    \t defalt answer yes to send site report
-z, --zaptrash\t remove stale messages from trash folder

";
   exit 1;
}

my $usercount=0;
foreach $loginname (@userlist) {
   # reset back to root before switch to next user
   $>=0;

   %config=(); %config_raw=();
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");

   my $siteconf="";
   if ($loginname=~/\@(.+)$/) {
       $siteconf="$config{'ow_etcdir'}/sites.conf/$1";
   } elsif ($defaultdomain ne "") {
       $siteconf="$config{'ow_etcdir'}/sites.conf/$defaultdomain";
   }
   readconf(\%config, \%config_raw, "$siteconf") if ( $siteconf ne "" && -f "$siteconf");

   require $config{'auth_module'} or
      die("Can't open authentication module $config{'auth_module'}");

   my $virtname=$config{'virtusertable'};
   $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   update_virtusertable("$config{'ow_etcdir'}/$virtname", $config{'virtusertable'});

   ($loginname, $domain, $user, $userrealname, $uuid, $ugid, $homedir)
	=get_domain_user_userinfo($loginname);

   if ($user eq "") {
      print "user $loginname doesn't exist\n" if (!$opt_quiet);
      next;
   }

   if ($homedir eq '/') {
      ## Lets assume it a virtual user, and see if the user exist
      if ( -d "$config{'ow_etcdir'}/users/$loginname") {
         $homedir = "$config{'ow_etcdir'}/users/$loginname";
      }
   }

   next if ($homedir eq '/');
   next if ($user eq 'root' || $user eq 'toor'||
            $user eq 'daemon' || $user eq 'operator' || $user eq 'bin' ||
            $user eq 'tty' || $user eq 'kmem' || $user eq 'uucp');

   my $userconf="$config{'ow_etcdir'}/users.conf/$user";
   $userconf .= "\@$domain" if ($config{'auth_withdomain'});
   readconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

   if ( $config{'use_homedirspools'} || $config{'use_homedirfolders'} ) {
      my $mailgid=getgrnam('mail');
      set_euid_egid_umask($uuid, $mailgid, 0077);
      if ( $) != $mailgid) {	# egid must be mail since this is a mail program...
         die("Set effective gid to mail($mailgid) failed!");
      }
   }

   if ( $config{'use_homedirfolders'} ) {
      $folderdir = "$homedir/$config{'homedirfolderdirname'}";
   } else {
      $folderdir = "$config{'ow_etcdir'}/users/$user";
      $folderdir .= "\@$domain" if ($config{'auth_withdomain'});
   }

   ($user =~ /^(.+)$/) && ($user = $1);  # untaint $user
   ($uuid =~ /^(.+)$/) && ($uuid = $1);
   ($ugid =~ /^(.+)$/) && ($ugid = $1);
   ($homedir =~ /^(.+)$/) && ($homedir = $1);  # untaint $homedir
   ($folderdir =~ /^(.+)$/) && ($folderdir = $1);  # untaint $folderdir

   if ( ! -d $folderdir ) {
      print "$folderdir doesn't exist\n" if (!$opt_quiet);
      next;
   }
   if ( ! -f "$folderdir/.openwebmailrc" ) {
      print "$folderdir/.openwebmailrc doesn't exist\n" if (!$opt_quiet);
      next;
   }

   %prefs = %{&readprefs};

   if ($opt_pop3) {
      my $ret=getpop3s($POP3_TIMEOUT);
      print "getpop3s($POP3_TIMEOUT) return $ret\n" if (!$opt_quiet && $ret!=0);
   }
   if ($opt_verify) {
      my $ret=verifyfolders();
      print "verifyfolders() return $ret\n" if (!$opt_quiet && $ret!=0);
   }
   if ($opt_zap) {
      my $ret=cleantrash();
      print "cleantrash() return $ret\n" if (!$opt_quiet && $ret!=0);
   }

   if ($opt_size) {
      my $ret=checksize();
      print "checksize() return $ret\n" if (!$opt_quiet && $ret!=0);
   }
   if ($opt_mail) {
      my $ret=checknewmail();
      print "checknewmail() return $ret\n" if (!$opt_quiet && $ret!=0);
   }
   if ($opt_event) {
      my $ret=checknewevent();
      print "checknewevent() return $ret\n" if (!$opt_quiet && $ret!=0);
   }
   if ($opt_notify) {
      my $ret=checknotify();
      print "checknotify() return $ret\n" if (!$opt_quiet && $ret!=0);
   }

   $usercount++;
}

if ($usercount>0) {
   exit 0;
} else {
   exit 1;
}

############################## routines #######################################
my %pop3error=( -1=>"pop3book read error",
                -2=>"connect error",
                -3=>"server not ready",
                -4=>"'user' error",
                -5=>"'pass' error",
                -6=>"'stat' error",
                -7=>"'retr' error",
                -8=>"spoolfile write error",
                -9=>"pop3book write error");

sub init {
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
   if ($defaultdomain ne "") {
      my $siteconf="$config{'ow_etcdir'}/sites.conf/$defaultdomain";
      readconf(\%config, \%config_raw, "$siteconf") if ( -f "$siteconf");
   }

   exit 1 if (dbm_test()<0);

   if (!-f "$config{'ow_etcdir'}/b2g$config{'dbm_ext'}") {
      die "$config{'b2g_map'} not found" if (!-f $config{'b2g_map'});
      print "creating $config{'ow_etcdir'}/b2g$config{'dbm_ext'} ...";
      if (mkdb_b2g()<0) {
         print "error!\n"; exit 1;
      }
      print "done.\n";
   }
   if (!-f "$config{'ow_etcdir'}/g2b$config{'dbm_ext'}") {
      die "$config{'g2b_map'} not found" if (!-f $config{'g2b_map'});
      print "creating $config{'ow_etcdir'}/g2b$config{'dbm_ext'} ...";
      if (mkdb_g2b()<0) {
         print "error!\n"; exit 1;
      }
      print "done.\n";
   }
   if (!-f "$config{'ow_etcdir'}/lunar$config{'dbm_ext'}") {
      die "$config{'lunar_map'} not found" if (!-f $config{'lunar_map'});
      print "creating $config{'ow_etcdir'}/lunar$config{'dbm_ext'} ...";
      if (mkdb_lunar()<0) {
         print "error!\n"; exit 1;
      }
      print "done.\n";
   }

   my $id = $ENV{'USER'} || $ENV{'LOGNAME'} || getlogin || (getpwuid($>))[0];
   my $hostname=hostname();
   my $realname=(getpwnam($id))[6]||$id;
   my $to="openwebmail\@turtle.ee.ncku.edu.tw";
   my $subject="site report - $hostname";
   my $os;
   if ( -f "/usr/bin/uname") {
      $os=`/usr/bin/uname -srmp`; chomp($os);
   } else {
      $os=`/bin/uname -srmp`; chomp($os);
   }
   my $content=qq|OS: $os\n|.
               qq|Perl: $]\n|.
               qq|WebMail: $config{'name'} $config{'version'} $config{'releasedate'}\n|;
   print qq|\nWelcome to the Open WebMail!\n\n|.
         qq|This program is going to send a short message back to the developer,\n|.
         qq|so we could have the idea that who is installing and how many sites are\n|.
         qq|using this software, the content to be sent is:\n\n|.
         qq|$content\n|.
         qq|Please hit 'Enter' to continue or Ctrl-C to break.\n|;
   if (!$opt_yes) {
      $_=<STDIN>;
   }
   send_mail("$id\@$hostname", $realname, $to, $subject, "$content \n");
   print qq|Thank you.\n|;
   return 0;
}

sub dbm_test {
   my (%DB, @filelist, @delfiles);
   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock);

   mkdir ("/tmp/dbmtest.$$", 0755);

   dbmopen(%DB, "/tmp/dbmtest.$$/test", 0600); dbmclose(%DB);

   @delfiles=();
   opendir (TESTDIR, "/tmp/dbmtest.$$");
   while (defined(my $filename = readdir(TESTDIR))) {
      ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...
      if ($filename!~/^\./ ) {
         push(@filelist, $filename);
         push(@delfiles, "/tmp/dbmtest.$$/$filename");
      }
   }
   closedir(TESTDIR);
   unlink(@delfiles) if ($#delfiles>=0);

   @filelist=reverse sort(@filelist);
   if ($filelist[0]=~/(\..*)$/) {
      ($dbm_ext, $dbmopen_ext)=($1, '');
   } else {
      ($dbm_ext, $dbmopen_ext)=('.db', '.db');
   }

   filelock("/tmp/dbmtest.$$/test$dbm_ext", LOCK_EX);
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 5;	# timeout 5 sec
      dbmopen(%DB, "/tmp/dbmtest.$$/test$dbmopen_ext", 0600); dbmclose(%DB);
      alarm 0;
   };
   if ($@) {	# eval error, it means timeout
      $dbmopen_haslock=1;
   } else {
      $dbmopen_haslock=0;
   }
   filelock("/tmp/dbmtest.$$/test$dbm_ext", LOCK_UN);

   @delfiles=();
   opendir (TESTDIR, "/tmp/dbmtest.$$");
   while (defined(my $filename = readdir(TESTDIR))) {
      ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...
      push(@delfiles, "/tmp/dbmtest.$$/$filename") if ($filename!~/^\./ );
   }
   closedir(TESTDIR);
   unlink(@delfiles) if ($#delfiles>=0);

   rmdir("/tmp/dbmtest.$$");

   return 0 if ($dbm_ext eq $config{'dbm_ext'} &&
                $dbmopen_ext eq $config{'dbmopen_ext'} &&
                (!$dbmopen_haslock ||
                 $dbmopen_haslock && $dbmopen_haslock eq $config{'dbmopen_haslock'})
               );

   # convert value to str
   if ($dbmopen_ext eq $dbm_ext) {
      $dbmopen_ext='%dbm_ext%';
   } elsif ($dbmopen_ext eq "") {
      $dbmopen_ext='none';
   }
   if ($dbmopen_haslock) {
      $dbmopen_haslock='yes';
   } else {
      $dbmopen_haslock='no';
   }

   print qq|Please change the 3 options in openwebmail.conf\n\n|.
         qq|dbm_ext           $config_raw{'dbm_ext'}\n|.
         qq|dbmopen_ext       $config_raw{'dbmopen_ext'}\n|.
         qq|dbmopen_haslock   $config_raw{'dbmopen_haslock'}\n|.
         qq|\nto\n\n|.
         qq|dbm_ext           $dbm_ext\n|.
         qq|dbmopen_ext       $dbmopen_ext\n|.
         qq|dbmopen_haslock   $dbmopen_haslock\n\n|.
         qq|Then execute '$SCRIPT_DIR/openwebmail-tool.pl --init' again.\n|;
   return -1;
}

sub hostname {
   my $hostname=`/bin/hostname`; chomp ($hostname);
   return($hostname) if ($hostname=~/\./);

   my $domain="unknow";
   open (R, "/etc/resolv.conf");
   while (<R>) {
      chop; 
      if (/domain\s+\.?(.*)/i) {$domain=$1;last;} 
   }
   close(R);
   return("$hostname.$domain");
}

sub allusers {
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
   if ($defaultdomain ne "") {
      my $siteconf="$config{'ow_etcdir'}/sites.conf/$defaultdomain";
      readconf(\%config, \%config_raw, "$siteconf") if ( -f "$siteconf");
   }

   require $config{'auth_module'} or
        die("Can't open authentication module $config{'auth_module'}");

   my $virtname=$config{'virtusertable'};
   $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   update_virtusertable("$config{'ow_etcdir'}/$virtname", $config{'virtusertable'});

   foreach my $u (get_userlist()) {
      push(@userlist, $u);
      if ($#userlist <0 ) {
         print "-a is not supported by $config{'auth_module'}, use -f instead\n" if (!$opt_quiet);
         exit 1;
      }
   }
}


sub verifyfolders {
   my (@validfolders, $folderusage);

   getfolders(\@validfolders, \$folderusage);

   foreach (@validfolders) {
      my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $_);

      filelock($folderfile, LOCK_EX|LOCK_NB) || return -1;
      my $ret=update_headerdb($headerdb, $folderfile);
      if ($ret==1) {
         print "$headerdb$config{'dbm_ext'} updated\n" if (!$opt_quiet);
      } elsif ($ret<0) {
         print "$headerdb$config{'dbm_ext'} write error\n" if (!$opt_quiet);
      }
      filelock($folderfile, LOCK_UN);
   }
   return 0;
}


sub cleantrash {
   my ($trashfile, $trashdb)=get_folderfile_headerdb($user, 'mail-trash');
   if (filelock($trashfile, LOCK_EX|LOCK_NB)) {
      my $deleted=delete_message_by_age($prefs{'trashreserveddays'}, $trashdb, $trashfile);
      if ($deleted >0) {
         writelog("cleantrash - delete $deleted msgs from mail-trash");
         writehistory("cleantrash - delete $deleted msgs from mail-trash");
      }
      filelock($trashfile, LOCK_UN);
   }
}


sub checksize {
   my (@validfolders, $folderusage);

   getfolders(\@validfolders, \$folderusage);
   return(cutfolders(@validfolders));
}


sub checknewmail {
   my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
   print "$loginname " if (!$opt_quiet);

   if (defined($pop3_authserver) && $config{'getmail_from_pop3_authserver'}) {
      my $login=$user;
      $login .= "\@$domain" if ($config{'auth_withdomain'});
      my $response = retrpop3mail($login, $pop3_authserver, "$folderdir/.authpop3.book", $spoolfile);
      if ( $response<0) {
         writelog("pop3 error - $pop3error{$response} at $login\@$pop3_authserver");
      }
   }

   if ( ! -f $spoolfile || (stat($spoolfile))[7]==0 ) {
      print "has no mail\n" if (!$opt_quiet);
      return 0;
   }

   my @folderlist=();
   my $filtered=mailfilter($user, 'INBOX', $folderdir, \@folderlist, $prefs{'regexmatch'},
	$prefs{'filter_repeatlimit'}, $prefs{'filter_fakedsmtp'},
        $prefs{'filter_fakedfrom'}, $prefs{'filter_fakedexecontenttype'});
   if ($filtered>0) {
      writelog("filtermsg - filter $filtered msgs from INBOX");
      writehistory("filtermsg - filter $filtered msgs from INBOX");
   }

   if (!$opt_quiet) {
      my (%HDB, $allmessages, $internalmessages, $newmessages);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) if (!$config{'dbmopen_haslock'});
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
      $allmessages=$HDB{'ALLMESSAGES'};
      $internalmessages=$HDB{'INTERNALMESSAGES'};
      $newmessages=$HDB{'NEWMESSAGES'};
      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

      if ($newmessages > 0 ) {
         print "has new mail\n" if (!$opt_quiet);
      } elsif ($allmessages-$internalmessages > 0 ) {
         print "has mail\n" if (!$opt_quiet);
      } else {
         print "has no mail\n" if (!$opt_quiet);
      }
   }
   return 0;
}

sub checknewevent {
   my ($newevent, $oldevent);
   my $g2l=time()+timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($wdaynum, $year, $month, $day, $hour, $min)=(gmtime($g2l))[6,5,4,3,2,1];
   $year+=1900; $month++;
   my $hourmin=sprintf("%02d%02d", $hour, $min);

   my $dow=$wdaystr[$wdaynum];
   my $date=sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

   my (%items, %indexes);

   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      return -1;
   }
   if ($prefs{'calendar_reminderforglobal'} && -f $config{'global_calendarbook'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
   }

   my @indexlist=();
   push(@indexlist, @{$indexes{$date}}) if (defined($indexes{$date}));
   push(@indexlist, @{$indexes{'*'}})   if (defined($indexes{'*'}));
   @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

   for my $index (@indexlist) {
      if ($date=~/$items{$index}{'idate'}/ ||
          $date2=~/$items{$index}{'idate'}/) {
         if ($items{$index}{'starthourmin'}>=$hourmin ||
             $items{$index}{'endhourmin'}>$hourmin ||
             $items{$index}{'starthourmin'}==0) {
            $newevent++;
         } else {
            $oldevent++;
         }
      }
   }

   if ($newevent > 0 ) {
      print "$loginname has new event\n" if (!$opt_quiet);
   } elsif ($oldevent > 0 ) {
      print "$loginname has event\n" if (!$opt_quiet);
   }

   return 0;
}

sub checknotify {
   my %message=();
   my $g2l=time()+timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($wdaynum, $year, $month, $day, $hour, $min)=(gmtime($g2l))[6,5,4,3,2,1];
   $year+=1900; $month++;

   my $dow=$wdaystr[$wdaynum];
   my $date=sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

   my $checkstart="0000";
   if ( -f "$folderdir/.notify.check" ) {
      open (NOTIFYCHECK, "$folderdir/.notify.check" ) or return -1; # read err
      my $lastcheck=<NOTIFYCHECK>;
      close (NOTIFYCHECK);
      $checkstart=$1 if ($lastcheck=~/$date(\d\d\d\d)/);
   }

   my $checkend="2400";
   my ($wdaynum2, $year2, $month2, $day2, $hour2, $min2)=(gmtime($g2l+$config{'calendar_email_notifyinterval'}*60))[6,5,4,3,2,1];
   $checkend=sprintf("%02d%02d", $hour2, $min2) if ( $day2 eq $day );

   return 0 if ($checkend<=$checkstart);

   open (NOTIFYCHECK, ">$folderdir/.notify.check" ) or return -2; # write err
   print NOTIFYCHECK "$date$checkend";
   truncate(NOTIFYCHECK, tell(NOTIFYCHECK));
   close (NOTIFYCHECK);

   my (%items, %indexes);

   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      return -3;
   }
   if ($prefs{'calendar_reminderforglobal'} && -f $config{'global_calendarbook'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
   }

   my @indexlist=();
   push(@indexlist, @{$indexes{$date}}) if (defined($indexes{$date}));
   push(@indexlist, @{$indexes{'*'}})   if (defined($indexes{'*'}));
   @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

   my $future_items=0;
   for my $index (@indexlist) {
      if ( $items{$index}{'email'} &&
           ($date=~/$items{$index}{'idate'}/ || $date2=~/$items{$index}{'idate'}/) ) {

         if ( ($items{$index}{'starthourmin'}>=$checkstart &&
               $items{$index}{'starthourmin'}<$checkend) ||
              ($items{$index}{'starthourmin'}==0 &&
               $checkstart eq "0000") ) {
            my $itemstr;
            if ($items{$index}{'starthourmin'}==0) {
               $itemstr="##:##";
            } elsif ($items{$index}{'endhourmin'}==0) {
               $itemstr=hourmin($items{$index}{'starthourmin'});
            } else {
               $itemstr=hourmin($items{$index}{'starthourmin'})."-".hourmin($items{$index}{'starthourmin'});
            }
            $itemstr .= "  $items{$index}{'string'}";
            $itemstr .= " ($items{$index}{'link'})" if ($items{$index}{'link'});

            if (defined($message{$items{$index}{'email'}})) {
               $message{$items{$index}{'email'}} .= $itemstr."\n";
            } else {
               $message{$items{$index}{'email'}} = $itemstr."\n";
            }
         }
         if ($items{$index}{'starthourmin'}>=$checkend) {
            $future_items++;
         }
      }
   }

   if ($future_items==0) { # today has no more item to notify, set checkend to 2400
      if (open (NOTIFYCHECK, ">$folderdir/.notify.check" )) {
         print NOTIFYCHECK $date."2400";
         truncate(NOTIFYCHECK, tell(NOTIFYCHECK));
         close (NOTIFYCHECK);
      }
   }

   my $from=$prefs{'email'};
   my %userfrom=get_userfrom($loginname, $user, $userrealname, "$folderdir/.from.book");
   my $realname=$userfrom{$from};
   my $title=dateserial2str(sprintf("%04d%02d%02d",$year,$month,$day),$prefs{'dateformat'}).
             "  ".hourmin($checkstart)."-".hourmin($checkend)."\n".
             "---------------------------------\n";
   foreach my $email (keys %message) {
      my $ret=send_mail($from, $realname, $email, "calendar notification", $title.$message{$email});
      if (!$opt_quiet) {
         print "mailing notification to $email for $loginname";
         print ", return $ret" if ($ret!=0);
         print "\n";
      }
   }
   return 0;
}

sub send_mail {
   my ($from, $realname, $to, $subject, $body)=@_;
   my $date = dateserial2datefield(gmtime2dateserial(), $prefs{'timeoffset'});

   $from =~ s/['"]/ /g;  # Get rid of shell escape attempts
   $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts

   ($realname =~ /^(.+)$/) && ($realname = '"'.$1.'"');
   ($from =~ /^(.+)$/) && ($from = $1);
   ($to =~ /^(.+)$/) && ($to = $1);
   ($date =~ /^(.+)$/) && ($date = $1);

   # fake a messageid for this message
   my $fakedid = gmtime2dateserial().'.M'.int(rand()*100000);
   $fakedid="<$fakedid".'@'."${$config{'domainnames'}}[0]>";

   my $smtp;
   $smtp=Net::SMTP->new($config{'smtpserver'},
                        Port => $config{'smtpport'},
                        Timeout => 120,
                        Hello => ${$config{'domainnames'}}[0]) or
      die "Couldn't SMTP server $config{'smtpserver'}:$config{'smtpport'}!";

   # SMTP SASL authentication (PLAIN only)
   if ($config{'smtpauth'}) {
      my $auth = $smtp->supports("AUTH");
      $smtp->auth($config{'smtpauth_username'}, $config{'smtpauth_password'}) or
         die "SMTP server $config{'smtpserver'} error - ".$smtp->message;
   }

   $smtp->mail($from);

   my @recipients=();
   foreach (str2list($to,0)) {
      my $email=(email2nameaddr($_))[1];
      next if ($email eq "" || $email=~/\s/);
      push (@recipients, $email);
   }
   if (! $smtp->recipient(@recipients, { SkipBad => 1 }) ) {
      $smtp->reset();
      $smtp->quit();
      return(-1);
   }

   $smtp->data();
   $smtp->datasend("From: ".encode_mimewords("$realname <$from>", ('Charset'=>$prefs{'charset'}))."\n",
                   "To: ".encode_mimewords($to, ('Charset'=>$prefs{'charset'}))."\n");
   $smtp->datasend("Reply-To: ".encode_mimewords($prefs{'replyto'}, ('Charset'=>$prefs{'charset'}))."\n") if ($prefs{'replyto'});

   my $xmailer = $config{'name'};
   $xmailer .= " $config{'version'} $config{'releasedate'}" if ($config{'xmailer_has_version'});

   $smtp->datasend("Subject: ".encode_mimewords($subject, ('Charset'=>$prefs{'charset'}))."\n",
                   "Date: $date\n",
                   "Message-Id: $fakedid\n",
                   "X-Mailer: $xmailer\n",
                   "MIME-Version: 1.0\n",
                   "Content-Type: text/plain; charset=$prefs{'charset'}\n\n",
                   $body, "\n\n");
   $smtp->datasend($config{'mailfooter'}, "\n") if ($config{'mailfooter'}=~/[^\s]/);

   if (!$smtp->dataend()) {
      $smtp->reset();
      $smtp->quit();
      return(-2);
   }
   $smtp->quit();

   return 0;
}

sub hourmin {
   if ($_[0] =~ /(\d+)(\d{2})$/) {
      return("$1:$2");
   } else {
      return($_[0]);
   }
}

sub getpop3s {
   my $timeout=$_[0];
   my ($spoolfile, $header)=get_folderfile_headerdb($user, 'INBOX');
   my (%accounts, $response);
   my $childpid;

   if ( ! -f "$folderdir/.pop3.book" ) {
      return;
   }

   # create system spool file /var/mail/xxxx
   if ( ! -f "$spoolfile" ) {
      open (F, ">>$spoolfile");
      close(F);
   }

   if (readpop3book("$folderdir/.pop3.book", \%accounts) <0) {
      return(-1);
   }

   # fork a child to do fetch pop3 mails and return immediately
   if (%accounts >0) {
      while ($pop3_process_count>$POP3_PROCESS_LIMIT) {
         sleep 1;
      }

      $pop3_process_count++;
      $|=1; 				# flush all output

      $childpid=fork();
      if ( $childpid == 0 ) {		# child
         close(STDOUT);
         close(STDIN);

         foreach (values %accounts) {
            my ($pop3host, $pop3user, $enable);
            my ($response, $dummy);
            my $disallowed=0;

            ($pop3host, $pop3user, $dummy, $dummy, $dummy, $enable) = split(/\@\@\@/,$_);
            next if (!$enable);

            foreach ( @{$config{'disallowed_pop3servers'}} ) {
               if ($pop3host eq $_) {
                  $disallowed=1; last;
               }
            }
            next if ($disallowed);

            $response = retrpop3mail($pop3host, $pop3user,
         				"$folderdir/.pop3.book",  $spoolfile);
            if ( $response<0) {
               writelog("pop3 error - $pop3error{$response} at $pop3user\@$pop3host");
            }
         }
         exit;
      }
   }

   for (my $i=0; $i<$timeout; $i++) {	# wait fetch to complete for $timeout seconds
      sleep 1;
      last if ($complete{$childpid}==1);
   }
   return 0;
}

