#!/usr/bin/perl
#
#  virtualsetup.pl - setup local domain for virtual users
#
# 2003-06-02   Scott A. Mazur, scott@littlefish.ca
#
#  This script sets up the OpenWebmail 'localusers' config parameter with the list of
#  all local users.
#
#  If there's no /etc/sites.conf file for the domain then it is created with the minimum
#  parameters needed to use the auth_vdomain.pl module.  Virtual and Real users
#  will appear exactly the same in OpenWebmail, however you can add additional config
#  parameters to the /etc/sites.conf file to distinguish virtual and real users.
#
#  This will allow real and virtual users to exist on the same domain name
#  Requires ( OW 2.01 release 20030605 or better to work )
#
#  !! NOTE !!
#  This script must be run as root.  No user directories or files will be touched, but the
#  /etc/openwebmail.conf  and an /etc/sites.conf files may be modified.
#
#  You should have OpenWebmail configured and running correctly before trying this script.
#
#  Local users are found by scanning the password file and keeping any user that has
#  a home directory in /home* 
#  This may not be appropriate for all flavours of linux.  You may have to modify the code
#  if your local users are setup significantly different.  Replace function LOCAL_USERS with
#  what ever logic will work for you environment.
#
#  There are several variables which must be setup according to your site.  Be sure change
#   these before running the script.
#
#  USE AT YOUR OWN RISK!
#  No warranty, No guarantee, and by all means make backups first.
#
#  Comments, questions to scott@littlefish.ca
#

use strict;

# Change these values for your site.
#################################################################
# some of these values can be found in your existing openwebmail.conf file

# this is the local domain that will be setup for both real and virtual users
my $domain = 'mydomain.com';

# homedir is the root directory for REAL users.  It will be used in the logic
#   to determine which userids are user and which are system.
# passfile will be scanned for users.
# exclude will be used to exclude users that for what ever reason have a home 
#   directory in homedir (ok to be empty, use it if you need it).

my $homedir = '/home';
my $passfile = '/etc/passwd';
my @exclude = ();

# this is the OpenWebmail etc directory
my $ow_etc = '/var/www/cgi-bin/openwebmail/etc';

# These are the virtual config file settings
my $virtual_mailspooldir = '/var/spool/virtual';
my $virtual_ow_usersdir = '/home/virtual';
my $virtual_use_syshomedir = 'no';
my $virtual_create_syshomedir = 'no';

# if you leave any of the following parameters as blank ( '' ) then they 
# will be defaulted according to the existing Openwebmail.conf values

# this list of administrators for the virtual domain
# both real and virtual users can be administrators, but only virtual
#    users can be modified with vdomain.
#my $admlist = '' ;  # no vdomain
my $admlist = 'sysadm';

# set vdomain = 'yes' to enable vdomain adminstrator
#my $vdomain='no';
my $vdomain='yes';

# you shouldn't have to modify anything below here
#################################################################
# main script
use File::Path;

# verify version
my (%config, %subs);
my $date=scalar(localtime);
READCONFIG("$ow_etc/openwebmail.conf.default", \%config);
print "Found Openwebmail version $config{'version'}  releasedate $config{'releasedate'}\n";

if ( $config{'releasedate'} < 20030605 ) {print "Mixing virtual and real users on the same domain requires Openwebmail version 2.01 release 20030605 or newer.\nScipt aborted.\n";exit 1} 

# get the local config file
READCONFIG("$ow_etc/openwebmail.conf", \%config);
if ( $config{'auth_module'} eq 'auth_vdomain.pl' ) {print "The main config file is already using auth_module 'auth_vdomain.pl'.  Real and virtual users can't be mixed here.\nScipt aborted.\n";exit 1} 

# fill out config values
foreach (keys %config) { while ( $config{$_}=~/%(\S+)%/ ) { my $parm=$1; $config{$_}=~s/\%$parm\%/$config{$parm}/g } }

# setup substitution values
foreach ( sort ( LOCAL_USERS() ) ) {
   if ($subs{'localusers'}) { $subs{'localusers'} .= ", $_\@$domain" }
   else  { $subs{'localusers'} = "$_\@$domain" }
}
if ( ! $subs{'localusers'} ) {print "No local users found.\nScipt aborted.\n";exit 1} 
$subs{'vdomain_admlist'}=$admlist if ($admlist);
$subs{'enable_vdomain'}=$vdomain if ($vdomain);

# check for changes
my $chg=0;
foreach (keys %subs) {
   if ( $config{$_} ne $subs{$_} ) { $chg=1; $config{$_} eq $subs{$_} }
   else {delete $subs{$_}}
}

# modifiy the openwebmail.conf file
if ($chg) {
   print "Updating $ow_etc/openwebmail.conf\n";
   foreach (sort keys %subs) { print "$_ $subs{$_}\n"; }
   my @lines;
   foreach ( READFILE("$ow_etc/openwebmail.conf") ) {
      foreach my $subparm (keys %subs) {
         if (/^\s*$subparm\s/) {
            push @lines, "# line replaced by virtualsetup.pl - $date\n", "# $_\n";
            $_="$subparm		$subs{$subparm}";
            delete $subs{$subparm};
         }
      }
      push @lines,"$_\n";
   }
   if (keys %subs) {
      push @lines, "\n# line(s) added by virtualsetup.pl - $date\n";
      foreach my $subparm (keys %subs) { push @lines, "$subparm		$subs{$subparm}\n" }
   }
   UPDATEFILE("$ow_etc/openwebmail.conf", @lines);
} else { print "No changes to $ow_etc/openwebmail.conf\n" }

# create the sites.conf file
my $siteconf="$config{'ow_sitesconfdir'}/$domain";
if (! -e $siteconf) {
   print "Creating site config file $siteconf\n";
   my @lines = (
                             "# virtual sites.conf file for domain $domain\n",
                             "# generated automatically by script virtualsetup.pl - $date\n",
                             "# add additional parameters here if you want them to be unique for virtual users.\n\n",
                             "name		$config{'name'} (virtual)\n",
                             "auth_module	auth_vdomain.pl\n",
                             "auth_withdomain	yes\n\n",
                             "mailspooldir	$virtual_mailspooldir/$domain\n",
                             "ow_usersdir	$virtual_ow_usersdir\n",
                             "use_syshomedir	$virtual_use_syshomedir\n",
                             "create_syshomedir	$virtual_create_syshomedir\n"
                           );
   WRITEFILE($siteconf, scalar(getpwnam('root')), scalar(getgrnam('mail')), 0640, @lines);
} else {
   print "Site conf file $siteconf already exists.  No changes made.\n";
   print "If this is not what you expected, delete $siteconf and run this script again.\n" if ($chg);
}

print "\ndone\n";
exit 0;

###########################################################
sub LOCAL_USERS {
# replace this with code for your environment if you have to.
   my @local;
   # convert exclude list to hash for easier checking
   my %ex; foreach(@exclude) {$ex{$_}=1}
   foreach ( READFILE($passfile) ) {
      my ($user,$home)=(split(':',$_))[0,5];
      push @local, $user if ( ! $ex{$user} and $home=~/^$homedir/ ) 
   }
   return @local;
}

sub READFILE { my ($file) = @_;
   if ( ! open( MYFILE, $file ) ) { print "failed to open file: $file $!\nScript aborted\n"; exit;}
   my @lines = <MYFILE>;
   close MYFILE;
   chomp @lines;
   return @lines;
}

sub WRITEFILE { my ($file, $uid, $gid, $perm, @lines) = @_;
  if ( ! open( FILE, ">$file" ) ) { print "failed to replace file: $file $!\nScript aborted\n"; exit 1;}
  print FILE @lines;
  close FILE;
  chmod $perm,$file;
  chown $uid,$gid,$file;
  return;
}

sub UPDATEFILE { my ($file, @lines) = @_;
  if ( ! open( FILE, ">$file" ) ) { print "failed to update file: $file $!\nScript aborted\n"; exit 1;}
  print FILE @lines;
  close FILE;
  return;
}

sub READCONFIG { my ($file,$hash)=@_;
   my $intag='';
   foreach ( READFILE($file) ) {
      if ($intag) {
         if (/^\s*<\/$intag>/) {$intag=''; next}
         $$hash{$intag} .= "$_\n";
      } else {
         if ( /^\s*<\s*([^\/]\S*)\s*>/ ) {$intag=$1; next}
         s/#.*//; s/^\s+//; s/\s+$//;
         next if (/^$/);
         $$hash{$1}=$2 if ( /^(\S+)\s*(.*)$/ );
      }
   }
   return;
}
