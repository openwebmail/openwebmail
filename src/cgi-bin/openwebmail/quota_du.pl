package openwebmail::quota_du;
use strict;
#
# quota_du.pl - calc user quota by /usr/bin/du
#
# 2003/04/06 tung@turtle.ee.ncku.edu.tw
#

# This module gets the user quotausage by running the 'du' program,
# it is recommended if your openwebmail user is not real unix user.
# To reduce the overhead introduced by running 'du', the quotausage info
# will be cached in $duinfo_db temporarily for $duinfo_lifetime seconds
#
# You may set $duinfo_lifetime to 0 to disable the cache
#

my $duinfo_db="/var/tmp/duinfo";
my $duinfo_lifetime=60;

################### No configuration required from here ###################

use Fcntl qw(:DEFAULT :flock);
require "filelock.pl";
require "execute.pl";

#  0 : ok
# -1 : parameter format error
# -2 : quota system/internal error
sub get_usage_limit {
   my ($r_config, $user, $homedir, $uptodate)=@_;
   return(-1, "$homedir doesn't exist") if (!-d $homedir);

   local *filelock;
   if ( ${$r_config}{'use_dotlockfile'} ) {
      *filelock=*openwebmail::filelock::dotfile_lock;
   } else {
      *filelock=*openwebmail::filelock::flock_lock;
   }

   my (%Q, $timestamp, $usage);
   my $now=time();

   if (!-f "$duinfo_db${$r_config}{'dbm_ext'}" && $duinfo_lifetime>0) {
      my $mailgid=getgrnam('mail');
      dbmopen (%Q, "$duinfo_db${$r_config}{'dbmopen_ext'}", 0664) or
         return(-2, "Couldn't create quota info db ($!)");
      dbmclose(%Q);
      chown($>, $mailgid, "$duinfo_db${$r_config}{'dbm_ext'}") or
         return(-2, "Couldn't set owner of quota info db ($!)");
   }

   if (!$uptodate && $duinfo_lifetime>0) {
      if (!${$r_config}{'dbmopen_haslock'}) {
         filelock("$duinfo_db${$r_config}{'dbm_ext'}", LOCK_SH) or
            return(-2, "Quota db $duinfo_db${$r_config}{'dbm_ext'} readlock error ($@)");
      }
      dbmopen (%Q, "$duinfo_db${$r_config}{'dbmopen_ext'}", undef);
      ($timestamp, $usage)=split(/\@\@\@/, $Q{"$user\@\@\@$homedir"}) if (defined($Q{"$user\@\@\@$homedir"}));
      dbmclose(%Q);
      filelock("$duinfo_db${$r_config}{'dbm_ext'}", LOCK_UN) if (!${$r_config}{'dbmopen_haslock'});

      if ($now-$timestamp>=0 && $now-$timestamp<=$duinfo_lifetime) {
         return(0, "", $usage, -1);
      }
   }

   my ($stdout, $stderr, $exit, $sig)=openwebmail::execute::execute('/usr/bin/du', '-sk', $homedir);
   return(-2, "exec /usr/bin/du error ($stderr)") if ($exit||$sig);
   $usage=(split(/\s/, $stdout))[0];
   return(0, "", $usage, -1) if ($duinfo_lifetime==0);

   if (!${$r_config}{'dbmopen_haslock'}) {
      filelock("$duinfo_db${$r_config}{'dbm_ext'}", LOCK_EX) or
         return(-2, "Quota db $duinfo_db${$r_config}{'dbm_ext'} writelock error ($@)");
   }
   dbmopen (%Q, "$duinfo_db${$r_config}{'dbmopen_ext'}", 0664);
   $Q{"$user\@\@\@$homedir"}="$now\@\@\@$usage";
   dbmclose(%Q);
   filelock("$duinfo_db${$r_config}{'dbm_ext'}", LOCK_UN) if (!${$r_config}{'dbmopen_haslock'});

   return(0, "", $usage, -1);
}

1;
