#!/usr/bin/perl -T
#
# this is a command used to check mail status for a user
#
# 03/17/2001 Ebola@turtle.ee.ncku.edu.tw
#
#
# syntax: checkmail.pl [-q] [-p] [-i] [-a] [-f userlist] [user1 user2 ...]
#

local $POP3_PROCESS_LIMIT=10;
local $POP3_TIMEOUT=20;

use strict;
no strict 'vars';
use Fcntl qw(:DEFAULT :flock);

$ENV{PATH} = ""; # no PATH should be needed

push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");
require "etc/openwebmail.conf";
require "auth.pl";
require "openwebmail-shared.pl";
require "mime.pl";
require "filelock.pl";
require "maildb.pl";
require "mailfilter.pl";
require "pop3mail.pl";

local $opt_pop3=0;
local $opt_verify=0;
local $opt_quiet=0;
local $pop3_process_count=0;

local $user;
local @userlist;
local %username=();
local %complete=();
local ($uid, $gid, $homedir);
local $folderdir;
local %prefs;

sub checknewmail {
   my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
   my $user_filter_repeatlimit;
   my $user_filter_fakedsmtp;

   if ( ! -f $spoolfile || (stat($spoolfile))[7]==0 ) {
      print ("$username{$user} has no mail\n") if (!$opt_quiet);
      return 0;
   }

   # get setting from user preference or global
   if ( defined($prefs{'filter_repeatlimit'}) ) {
      $user_filter_repeatlimit=$prefs{'filter_repeatlimit'};
   } else {
      $user_filter_repeatlimit=$filter_repeatlimit;
   }
   if ( defined($prefs{'filter_fakedsmtp'}) ) {
      $user_filter_fakedsmtp=$prefs{'filter_fakedsmtp'};
   } else {
      $user_filter_fakedsmtp=($filter_fakedsmtp eq 'yes'||$filter_fakedsmtp==1)?1:0;
   }

   my @folderlist=();
   my $filtered=mailfilter($user, 'INBOX', $folderdir, \@folderlist, 
				$filter_repeatlimit, $filter_fakedsmtp);
   if ($filtered>0) {
      writelog("filter $filtered msgs from INBOX");
   }

   if (!$opt_quiet) {
      my (%HDB, $allmessages, $internalmessages, $newmessages);
      filelock("$headerdb.$dbm_ext", LOCK_SH);
      dbmopen (%HDB, $headerdb, undef);
      $allmessages=$HDB{'ALLMESSAGES'};
      $internalmessages=$HDB{'INTERNALMESSAGES'};
      $newmessages=$HDB{'NEWMESSAGES'};
      dbmclose(%HDB);
      filelock("$headerdb.$dbm_ext", LOCK_UN);

      if ($newmessages > 0 ) {
         print ("$username{$user} has new mail\n");
      } elsif ($allmessages-$internalmessages > 0 ) {
         print ("$username{$user} has mail\n");
      } else {
         print ("$username{$user} has no mail\n");
      }
   }
}

sub getpop3s {
   my $timeout=$_[0];
   my ($spoolfile, $header)=get_folderfile_headerdb($user, 'INBOX');
   my (%accounts, $response);
   my %pop3error=( -1=>"pop3book read error",
                   -2=>"connect error",
                   -3=>"server not ready",
                   -4=>"'user' error",
                   -5=>"'pass' error",
                   -6=>"'stat' error",
                   -7=>"'retr' error",
                   -8=>"spoolfile write error",
                   -9=>"pop3book write error");
   my $childpid;

   if ( ! -f "$folderdir/.pop3.book" ) {
      return;
   }

   # create system spool file /var/mail/xxxx
   if ( ! -f "$spoolfile" ) {
      open (F, ">>$spoolfile");
      close(F);
   }

   if (getpop3book("$folderdir/.pop3.book", \%accounts) <0) {
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
            my ($pop3host, $pop3user, $mbox);
            my ($response, $dummy);

            ($pop3host, $pop3user, $dummy) = split(/:/,$_, 3);
            $response = retrpop3mail($pop3host, $pop3user, 
         				"$folderdir/.pop3.book",  $spoolfile);
            if ( $response<0) {
               writelog("pop3 $pop3error{$response} at $pop3user\@$pop3host");
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
   my @validfolders = @{&getfolders(0)};
   my ($folderfile, $headerdb);
   foreach (@validfolders) {
      ($folderfile, $headerdb)=get_folderfile_headerdb($user, $_);
      update_headerdb($headerdb, $folderfile);
   }
   return;
}

sub adduser2list {
   my $name=$_[0];
   my @realids=();

   $name=~s/\s+$//;
   $name=~s/^\s+//;
   if ($name=~/^[A-Za-z0-9_]+$/) {
      @realids=get_userlist_by_virtualuser($name, "$openwebmaildir/genericstable.r");
      if ($#realids>=0) {
         foreach (@realids) {
            push(@userlist, $_);
            $username{$_}=$name;
         }
      } else {
         push(@userlist, $name);
         $username{$name}=$name;
      }
   }
   return;
}

################################ main ##################################

# handle zombie
$SIG{CHLD} = sub { my $pid=wait; $complete{$pid}=1; $pop3_process_count--; };	

if ($ARGV[0] eq "--") {
   adduser2list($ARGV[1]);
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
         foreach $u (get_userlist()) {
            next if ($u eq 'root' || $u eq 'toor'||
                     $u eq 'daemon' || $u eq 'operator' || $u eq 'bin' ||
                     $u eq 'tty' || $u eq 'kmem' || $u eq 'uucp');
            adduser2list($u);
         }
      } elsif ($ARGV[$i] eq "--file" || $ARGV[$i] eq "-f") {
         $i++;
         if ( -f $ARGV[$i] ) {
            open(USER, $ARGV[$i]);
            while (<USER>) {
               adduser2list($_);
            }
            close(USER);
         }
      } else {
         adduser2list($ARGV[$i]);
      }
   }
}
           

my $usercount=0;
foreach $user (@userlist) {
   # reset back to root before switch to next user
   $>=0;

   ($user =~ /^(.+)$/) && ($user = $1);  # untaint $user...
   ($uid, $homedir) = (get_userinfo($user))[1,3];
   next if ($uid eq '' || $homedir eq '/');

   $uid=$> if (($homedirspools ne 'yes') && ($homedirfolders ne 'yes'));
   $gid=getgrnam('mail');

   set_euid_egid_umask($uid, $gid, 0077);

   if ( $homedirfolders eq 'yes') {
      $folderdir = "$homedir/$homedirfolderdirname";
   } else {
      $folderdir = "$openwebmaildir/users/$user";
   }
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
   print "Syntax: checkmail.pl [-q] [-p] [-i] [-f userlist] [user1 user2 ...]

 -q, --quite  \t quiet, no output
 -p, --pop3   \t fetch pop3 mail for user
 -i, --index  \t check index for user folders and reindex if needed
 -a, --alluser\t check for all users in passwd
 -f, --file   \t user list file, each line contains a username

";
   exit 1;
}
