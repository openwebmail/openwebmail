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
require "openwebmail-shared.pl";

local $user;
local $userip='localhost';
local ($uid, $gid, $homedir);
local $folderdir;

$user = $ARGV[0];
if ($user eq "--") {	# may be called by fingerd?
   $user = $ARGV[1];
}
if ($user !~ /^[A-Za-z0-9_]+$/) {
   print("invalid userid\n");
   exit 1;	# invalid userid
}
($user =~ /^(.+)$/) && ($user = $1);  # untaint $user...

$uid=0; $gid = getgrnam('mail');
if (($homedirspools eq 'yes') || ($homedirfolders eq 'yes')) {
   my $ugid;
   ($uid, $ugid, $homedir) = (getpwnam($user))[2,3,7];
   if ($uid eq '') {
      print ("no such user\n");
      exit 2;
   }
}
set_euid_egid_umask($uid, $gid, 0077);

if ( $homedirfolders eq 'yes') {
   $folderdir = "$homedir/$homedirfolderdirname";
} else {
   $folderdir = "$openwebmaildir/users/$user";
}
if ( ! -d $folderdir ) {
   print("$folderdir doesn't exist\n");
   exit 3;	# no folderdir exist
}


my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
if ( ! -f $spoolfile || (stat($spoolfile))[7]==0 ) {
   print ("$user has no mail\n");
   exit 0;
}

require "mime.pl";
require "maildb.pl";
require "mailfilter.pl";

my @folderlist=();
my $removed=mailfilter($spoolfile, $headerdb, 
			$folderdir, \@folderlist, $user, $uid, $gid);
if ($removed>0) {
   writelog("filter $removed msgs from $spoolfile");
}

my (%HDB, $allmessages, $internalmessages, $newmessages);
filelock("$headerdb.$dbm_ext", LOCK_SH);
dbmopen (%HDB, $headerdb, undef);
$allmessages=$HDB{'ALLMESSAGES'};
$internalmessages=$HDB{'INTERNALMESSAGES'};
$newmessages=$HDB{'NEWMESSAGES'};
dbmclose(%HDB);
filelock("$headerdb.$dbm_ext", LOCK_UN);

if ($newmessages > 0 ) {
   print ("$user has new mail\n");
} elsif ($allmessages-$internalmessages > 0 ) {
   print ("$user has mail\n");
} else {
   print ("$user has no mail\n");
}
exit 0;
