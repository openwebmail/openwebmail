#!/usr/bin/perl -T
#
# this is a command used to check mail status for a user
#
# 03/17/2001 Ebola@turtle.ee.ncku.edu.tw
#
#
# syntax: checkmail.pl [userid]
#

use strict;
no strict 'vars';
use Fcntl qw(:DEFAULT :flock);

$ENV{PATH} = ""; # no PATH should be needed

push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");
require "etc/openwebmail.conf";

my $user = $ARGV[0];
if ($user eq "--") {	# may be called by fingerd?
   $user = $ARGV[1];
}
if ($user !~ /^[A-Za-z0-9_]+$/) {
   print("invalid userid\n");
   exit 1;	# invalid userid
}
($user =~ /^(.+)$/) && ($user = $1);  # untaint $user...

my ($login, $pass, $uid, $gid, $homedir);
if (($homedirspools eq 'yes') || ($homedirfolders eq 'yes')) {
   ($login, $pass, $uid, $gid, $homedir) = (getpwnam($user))[0,1,2,3,7];
   if ($login ne $user) {
      print ("no such user\n");
      exit 2;
   }
   $gid = getgrnam('mail');
   $) = $gid;
   $> = $uid;
   umask(0077); # make sure only owner can read/write
} else {
   $uid=0; $gid=0;
}

my $folderdir;
if ( $homedirfolders eq 'yes') {
   $folderdir = "$homedir/$homedirfolderdirname";
} else {
   $folderdir = "$userprefsdir/$user";
}
if ( ! -d $folderdir ) {
   print("$folderdir doesn't exist\n");
   exit 3;	# no folderdir exist
}


my $spoolfile;
if ($homedirspools eq "yes") {
   $spoolfile = "$homedir/$homedirspoolname";
} elsif ($hashedmailspools eq "yes") {
   $user =~ /^(.)(.)/;
   my $firstchar = $1;
   my $secondchar = $2;
   $spoolfile = "$mailspooldir/$firstchar/$secondchar/$user";
} else {
   $spoolfile = "$mailspooldir/$user";
}
if ( ! -f $spoolfile || (stat($spoolfile))[7]==0 ) {
   print ("$user has no mail\n");
   exit 0;
}
my $headerdb="$folderdir/.$user";


require "mime.pl";
require "maildb.pl";
require "mailfilter.pl";

my @folderlist=();
mailfilter($spoolfile, $headerdb, $folderdir, \@folderlist, $uid, $gid);

my (%HDB, $allmessages, $newmessages);
filelock("$headerdb.$dbm_ext", LOCK_SH);
dbmopen (%HDB, $headerdb, undef);
$allmessages=$HDB{'ALLMESSAGES'};
$newmessages=$HDB{'NEWMESSAGES'};
dbmclose(%HDB);
filelock("$headerdb.$dbm_ext", LOCK_UN);

if ($newmessages > 0 ) {
   print ("$user has new mail\n");
} elsif ($allmessages > 0 ) {
   print ("$user has mail\n");
} else {
   print ("$user has no mail\n");
}
exit 0;
