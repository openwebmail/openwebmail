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
readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
require $config{'auth_module'} or
   openwebmailerror("Can't open authentication module $config{'auth_module'}");

use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw($folderdir);
use vars qw(%prefs);

# extern vars
use vars qw($pop3_authserver);	# defined in auth_pop3.pl

################################ main ##################################

my $POP3_PROCESS_LIMIT=10;
my $POP3_TIMEOUT=20;

my @userlist=();
my %complete=();

my $opt_pop3=0;
my $opt_verify=0;
my $opt_quiet=0;
my $pop3_process_count=0;

# handle zombie
$SIG{CHLD} = sub { my $pid=wait; $complete{$pid}=1; $pop3_process_count--; };	

if ($ARGV[0] eq "--") {
   push(@userlist, $ARGV[1]);
} else {
   my $i=0;
   for ($i=0; $i<=$#ARGV; $i++) {
      if ($ARGV[$i] eq "--pop3" || $ARGV[$i] eq "-p") {
         $opt_pop3=1;
      } elsif ($ARGV[$i] eq "--index" || $ARGV[$i] eq "-i") {
         $opt_verify=1;
      } elsif ($ARGV[$i] eq "--quiet" || $ARGV[$i] eq "-q") {
         $opt_quiet=1;
      } elsif ($ARGV[$i] eq "--alluser" || $ARGV[$i] eq "-a") {
         foreach my $u (get_userlist()) {
            push(@userlist, $u);
         }
      } elsif ($ARGV[$i] eq "--file" || $ARGV[$i] eq "-f") {
         $i++;
         if ( -f $ARGV[$i] ) {
            open(USER, $ARGV[$i]);
            while (<USER>) {
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
   print "Syntax: checkmail.pl [-q] [-p] [-i] [-f userlist] [user1 user2 ...]

 -q, --quite  \t quiet, no output
 -p, --pop3   \t fetch pop3 mail for user
 -i, --index  \t check index for user folders and reindex if needed
 -a, --alluser\t check for all users in passwd
 -f, --file   \t user list file, each line contains a username

";
   exit 1;
}

my $usercount=0;
foreach $loginname (@userlist) {
   # reset back to root before switch to next user
   $>=0;

   ($loginname, $domain, $user, $userrealname, $uuid, $ugid, $homedir)
	=get_domain_user_userinfo($loginname);
   if ($user eq "") {
      print("user $loginname doesn't exist\n") if (!$opt_quiet);
      next;
   }
   next if ($homedir eq '/');
   next if ($user eq 'root' || $user eq 'toor'||
            $user eq 'daemon' || $user eq 'operator' || $user eq 'bin' ||
            $user eq 'tty' || $user eq 'kmem' || $user eq 'uucp');

   if ( -f "$config{'ow_etcdir'}/users.conf/$user") { # read per user conf
      readconf(\%config, \%config_raw, "$config{'ow_etcdir'}/users.conf/$user");
   }

   if ( $config{'use_homedirspools'} || $config{'use_homedirfolders'} ) {
      my $mailgid=getgrnam('mail');
      set_euid_egid_umask($uuid, $mailgid, 0077);	
      if ( $) != $mailgid) {	# egid must be mail since this is a mail program...
         openwebmailerror("Set effective gid to mail($mailgid) failed!");
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
   checknewmail();

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

sub checknewmail {
   my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');

   if (defined($pop3_authserver) && $config{'getmail_from_pop3_authserver'}) {
      my $login=$user; 
      $login .= "\@$domain" if ($config{'auth_withdomain'});
      my $response = retrpop3mail($login, $pop3_authserver, "$folderdir/.authpop3.book", $spoolfile);
      if ( $response<0) {
         writelog("pop3 error - $pop3error{$response} at $login\@$pop3_authserver");
      }
   }

   if ( ! -f $spoolfile || (stat($spoolfile))[7]==0 ) {
      print ("$loginname has no mail\n") if (!$opt_quiet);
      return 0;
   }

   my @folderlist=();
   my $filtered=mailfilter($user, 'INBOX', $folderdir, \@folderlist, 
	$prefs{'filter_repeatlimit'}, $prefs{'filter_fakedsmtp'}, $prefs{'filter_fakedexecontenttype'});
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
         print ("$loginname has new mail\n");
      } elsif ($allmessages-$internalmessages > 0 ) {
         print ("$loginname has mail\n");
      } else {
         print ("$loginname has no mail\n");
      }
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
      update_headerdb($headerdb, $folderfile);
   }
   return;
}
