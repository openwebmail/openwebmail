#!/usr/bin/perl -T
#
# this is a command tool to check mail for a user
#
# 03/17/2001 Ebola@turtle.ee.ncku.edu.tw
#            tung@turtle.ee.ncku.edu.tw
#
# syntax: checkmail.pl [-q] [-p] [-i] [-a] [-f userlist] [user1 user2 ...]
#
use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(.*?)/[\w\d\-]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\nPlease execute script checkmail.pl with full path!\n"; exit 0; }
push (@INC, $SCRIPT_DIR, ".");

$ENV{PATH} = ""; 	# no PATH should be needed
$ENV{BASH_ENV} = ""; 	# no startup script for bash

use strict;
use Fcntl qw(:DEFAULT :flock);

require "openwebmail-shared.pl";
require "mime.pl";
require "filelock.pl";
require "maildb.pl";
require "mailfilter.pl";
require "pop3mail.pl";

use vars qw(%config %config_raw);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw($folderdir);
use vars qw(%prefs);

# extern vars
use vars qw(@wdaystr);	# defined in openwebmail-shared.pl
use vars qw($pop3_authserver);	# defined in auth_pop3.pl

################################ main ##################################

my $POP3_PROCESS_LIMIT=10;
my $POP3_TIMEOUT=20;

my @userlist=();
my %complete=();

my $opt_pop3=0;
my $opt_verify=0;
my $opt_zap=0;
my $opt_quiet=0;
my $defaultdomain="";
my $pop3_process_count=0;

# handle zombie
$SIG{CHLD} = sub { my $pid=wait; $complete{$pid}=1; $pop3_process_count--; };	

# no buffer on stdout
$|=1;

if ($ARGV[0] eq "--") {
   push(@userlist, $ARGV[1]);
} else {
   my $i=0;
   for ($i=0; $i<=$#ARGV; $i++) {
      if ($ARGV[$i] eq "--pop3" || $ARGV[$i] eq "-p") {
         $opt_pop3=1;
      } elsif ($ARGV[$i] eq "--index" || $ARGV[$i] eq "-i") {
         $opt_verify=1;
      } elsif ($ARGV[$i] eq "--zaptrash" || $ARGV[$i] eq "-z") {
         $opt_zap=1;
      } elsif ($ARGV[$i] eq "--quiet" || $ARGV[$i] eq "-q") {
         $opt_quiet=1;
      } elsif ($ARGV[$i] eq "--alluser" || $ARGV[$i] eq "-a") {

         readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
         readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
         if ($defaultdomain ne "") {
            my $siteconf="$config{'ow_etcdir'}/sites.conf/$defaultdomain";
            readconf(\%config, \%config_raw, "$siteconf") if ( -f "$siteconf");
         }

         require $config{'auth_module'} or
              die("Can't open authentication module $config{'auth_module'}");

         foreach my $u (get_userlist()) {
            push(@userlist, $u);
            if ($#userlist <0 ) {
               print("-a is not supported by $config{'auth_module'}, use -f instead\n") if (!$opt_quiet);
               exit 1;
            }
         }
      } elsif ($ARGV[$i] eq "--domain" || $ARGV[$i] eq "-d") {
         $i++ if $ARGV[$i+1]!~/^\-/;
         $defaultdomain=$ARGV[$i];
      } elsif ($ARGV[$i] eq "--file" || $ARGV[$i] eq "-f") {
         $i++;
         if ( -f $ARGV[$i] ) {
            open(USER, $ARGV[$i]);
            while (<USER>) {
               chomp $_;
               push(@userlist, $_);
            }
            close(USER);
         }
      } else {
         push(@userlist, $ARGV[$i]);
      }
   }
}

if ($#userlist<0) {
   print "Syntax: checkmail.pl [-q] [-p] [-i] [-z] [-d domain] [-f userlist] [-a] [user1 user2 ...]

 -q, --quite  \t quiet, no output
 -p, --pop3   \t fetch pop3 mail for user
 -i, --index  \t check index for user folders and reindex if needed
 -z, --zaptrash\t remove stale messages from trash folder
 -d, --domain \t default domain for user with no domain specified
 -a, --alluser\t check for all users in passwd
 -f, --file   \t user list file, each line contains a username

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

   ($loginname, $domain, $user, $userrealname, $uuid, $ugid, $homedir)
	=get_domain_user_userinfo($loginname);

   if ($user eq "") {
      print("user $loginname doesn't exist\n") if (!$opt_quiet);
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
      print("$folderdir doesn't exist\n") if (!$opt_quiet);
      next;
   }
   if ( ! -f "$folderdir/.openwebmailrc" ) {
      print("$folderdir/.openwebmailrc doesn't exist\n") if (!$opt_quiet);
      next;
   }

   %prefs = %{&readprefs};

   getpop3s($POP3_TIMEOUT) if ($opt_pop3);
   verifyfolders() if ($opt_verify);
   cleantrash() if ($opt_zap);
   checknewmail();
   checknewevent();

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


sub checknewmail {
   my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
   print ("$loginname ") if (!$opt_quiet);

   if (defined($pop3_authserver) && $config{'getmail_from_pop3_authserver'}) {
      my $login=$user;
      $login .= "\@$domain" if ($config{'auth_withdomain'});
      my $response = retrpop3mail($login, $pop3_authserver, "$folderdir/.authpop3.book", $spoolfile);
      if ( $response<0) {
         writelog("pop3 error - $pop3error{$response} at $login\@$pop3_authserver");
      }
   }

   if ( ! -f $spoolfile || (stat($spoolfile))[7]==0 ) {
      print ("has no mail\n") if (!$opt_quiet);
      return 0;
   }

   my @folderlist=();
   my $filtered=mailfilter($user, 'INBOX', $folderdir, \@folderlist,
	$prefs{'filter_repeatlimit'}, $prefs{'filter_fakedsmtp'},
        $prefs{'filter_fakedfrom'}, $prefs{'filter_fakedexecontenttype'});
   if ($filtered>0) {
      writelog("filtermsg - filter $filtered msgs from INBOX");
      writehistory("filtermsg - filter $filtered msgs from INBOX");
   }

   if (!$opt_quiet) {
      my (%HDB, $allmessages, $internalmessages, $newmessages);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
      $allmessages=$HDB{'ALLMESSAGES'};
      $internalmessages=$HDB{'INTERNALMESSAGES'};
      $newmessages=$HDB{'NEWMESSAGES'};
      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);

      if ($newmessages > 0 ) {
         print ("has new mail\n") if (!$opt_quiet);
      } elsif ($allmessages-$internalmessages > 0 ) {
         print ("has mail\n") if (!$opt_quiet);
      } else {
         print ("has no mail\n") if (!$opt_quiet);
      }
   }
}

sub checknewevent {
   my ($newevent, $oldevent);
   my $g2l=time()+timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($wdaynum, $year, $month, $day, $hour, $min)=(gmtime($g2l))[6,5,4,3,2,1];
   $year+=1900; $month++;
   my $hourmin=sprintf("%02d%02d", $hour, $min);

   my (%items, %indexes, $item_count);
   $item_count=readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0);
   if ($prefs{'calendar_reminderforglobal'} && -f $config{'global_calendarbook'}) {
      $item_count+=readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
   }

   my $dow=$wdaystr[$wdaynum];
   my $date=sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

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
      print ("$loginname has new event\n") if (!$opt_quiet);
   } elsif ($oldevent > 0 ) {
      print ("$loginname has event\n") if (!$opt_quiet);
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

   my $i;
   for ($i=0; $i<$timeout; $i++) {	# wait fetch to complete for $timeout seconds
      sleep 1;
      last if ($complete{$childpid}==1);
   }
   return;
}

sub verifyfolders {
   my @validfolders;
   my $folderusage;

   getfolders(\@validfolders, \$folderusage);
   foreach (@validfolders) {
      my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $_);
      if (update_headerdb($headerdb, $folderfile)==1) {
         print "$headerdb$config{'dbm_ext'} updated\n" if (!$opt_quiet);
      }
   }
   return;
}
