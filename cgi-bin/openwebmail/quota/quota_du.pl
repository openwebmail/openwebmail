package ow::quota_du;

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);
require "modules/dbm.pl";
require "modules/filelock.pl";
require "modules/execute.pl";

sub get_usage_limit {
   #  0 : ok
   # -1 : parameter format error
   # -2 : quota system/internal error
   my ($r_config, $user, $homedir, $uptodate) = @_;

   # This module gets the user quotausage by running the 'du' program,
   # it is recommended if your openwebmail user is not real unix user.
   # To reduce the overhead introduced by running 'du', the quotausage info
   # will be cached in $duinfo_db temporarily for $duinfo_lifetime seconds

   # You may set $duinfo_lifetime to 0 to disable the cache
   my $duinfo_db       = '/var/tmp/duinfo';
   my $duinfo_lifetime = 60;

   return(-1, "$homedir does not exist") unless -d $homedir;

   my %Q         = ();
   my $timestamp = 0;
   my $usage     = 0;
   my $now       = time();

   if (!ow::dbm::existdb("$duinfo_db") && $duinfo_lifetime > 0) {
      my $mailgid = getgrnam('mail');

      ow::dbm::opendb(\%Q, $duinfo_db, LOCK_EX, 0664) or
         return(-2, "Quota db create error, $ow::dbm::errmsg");

      ow::dbm::closedb(\%Q, $duinfo_db);

      ow::dbm::chowndb($>, $mailgid, $duinfo_db) or
         return(-2, "Quota db chown error, $ow::dbm::errmsg");
   }

   if (!$uptodate && $duinfo_lifetime > 0) {
      ow::dbm::opendb(\%Q, $duinfo_db, LOCK_EX, 0664) or
         return(-2, "Quota db open error, $ow::dbm::errmsg");

      ($timestamp, $usage) = split(/\@\@\@/, $Q{"$user\@\@\@$homedir"}) if defined $Q{"$user\@\@\@$homedir"};

      ow::dbm::closedb(\%Q, $duinfo_db);

      return(0, '', $usage, -1) if !defined $timestamp || ($now - $timestamp >= 0 && $now - $timestamp <= $duinfo_lifetime);
   }

   my ($stdout, $stderr, $exit, $sig) = ow::execute::execute('/usr/bin/du', '-sk', $homedir);

   return(-2, "exec /usr/bin/du error, $stderr") if ($exit || $sig);

   $usage = (split(/\s/, $stdout))[0];

   return(0, '', $usage, -1) if $duinfo_lifetime == 0;

   ow::dbm::opendb(\%Q, $duinfo_db, LOCK_EX, 0664) or
      return(-2, "Quota db open error, $ow::dbm::errmsg");

   $Q{"$user\@\@\@$homedir"} = "$now\@\@\@$usage";

   ow::dbm::closedb(\%Q, $duinfo_db);

   return(0, '', $usage, -1);
}

1;
