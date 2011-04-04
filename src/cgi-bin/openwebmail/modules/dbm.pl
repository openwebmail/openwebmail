package ow::dbm;
#
# dbm.pl - dbm routines that hides differences of various DBM implementations
#
# 2003/12/07 tung.AT.turtle.ee.ncku.edu.tw
#

# $dbm_errmsg will contain brief hint in case any error happens,
# the caller routine may use it to form a more complete error message


use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);
require "modules/filelock.pl";
require "modules/tool.pl";

use vars qw($dbm_ext $dbmopen_ext $dbmopen_haslock);
use vars qw($dbm_errno $dbm_errmsg $dbm_warning);
use vars qw($_defaultdbtype);

my %conf = ();
my $dbmconf = ow::tool::find_configfile('etc/dbm.conf', 'etc/defaults/dbm.conf') || '';
if ($dbmconf ne '') {
   my ($ret, $err) = ow::tool::load_configfile($dbmconf, \%conf);
   die $err if $ret < 0;
}

$dbm_ext         = $conf{dbm_ext} || '.db';
$dbmopen_ext     = $conf{dbmopen_ext} || '';
$dbmopen_ext     = '' if $dbmopen_ext eq 'none';
$dbmopen_haslock = $conf{dbmopen_haslock} || 'yes';
$dbmopen_haslock = $dbmopen_haslock =~ m/yes/i ? 1 : 0;


# SUBROUTINES

sub opendb {
   my ($r_hash, $db, $flag, $perm) = @_;

   $perm = 0600 unless defined $perm && $perm;

   $dbm_errno   = 0;
   $dbm_errmsg  = '';
   $dbm_warning = '';

   my $openerror     = '';
   my $dbtype        = '';
   my $defaultdbtype = '';

   for (my $retry = 0; $retry < 3; $retry++) {
      if (!$dbmopen_haslock) {
         if (! -f "$db$dbm_ext") { # ensure dbm existence before lock
            my %t = ();
            my $createerror = '';

            dbmopen(%t, "$db$dbmopen_ext", $perm) or $createerror = $!;
            dbmclose(%t);

            if ($createerror ne '') {
               $dbm_errno  = -1;
               $dbm_errmsg = $createerror;
               return 0;
            } elsif (! -f "$db$dbm_ext") {
               # dbmopen ok but dbm file not found
               $dbm_errno  = -2;
               $dbm_errmsg = 'wrong dbm_ext/dbmopen_ext setting?';
               return 0;
            }
         }

         if (! ow::filelock::lock("$db$dbm_ext", $flag, $perm) ) {
            if ($flag & LOCK_SH) {
               $dbm_errno  = -3;
               $dbm_errmsg = 'read lock failed';
            } else {
               $dbm_errno  = -3;
               $dbm_errmsg = 'write lock failed';
            }

            return 0;
         }
      }

      return 1 if dbmopen(%{$r_hash}, "$db$dbmopen_ext", $perm);

      $openerror = $!;

      ow::filelock::lock("$db$dbm_ext", LOCK_UN) unless $dbmopen_haslock;

      # db may be temporarily unavailable because of too many concurrent accesses,
      # eg: reading a message with lots of attachments
      if ($openerror =~ m/Resource temporarily unavailable/) {
         $dbm_warning .= 'db temporarily unavailable, retry ' . ($retry + 1) . '. ';
         sleep 1;
         next;
      }

      # if existing db is in wrong format, then unlink it and create a new one
      if (-f "$db$dbm_ext" && -r _ && $dbtype eq '') {
         $dbtype = get_dbtype("$db$dbm_ext");
         $defaultdbtype = get_defaultdbtype();
         if ($dbtype ne $defaultdbtype) {
            # db is in wrong format
            if (unlink("$db$dbm_ext")) {
               $dbm_warning = 'changing db format from $dbtype to $defaultdbtype. ';
               next;
            } else {
               $openerror .= "(wrong db format, default:$defaultdbtype, $db$dbm_ext:$dbtype)";
            }
         }
      }

      last; # default to leave the loop
   }

   $dbm_errno  = -4;
   $dbm_errmsg = $openerror;

   return 0;
}

sub closedb {
   my ($r_hash, $db) = @_;
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');

   dbmclose(%{$r_hash});
   ow::filelock::lock("$db$dbm_ext", LOCK_UN) if (!$dbmopen_haslock);
   return 1;
}

sub existdb {
   ($dbm_errno, $dbm_errmsg, $dbm_warning) = (0, '', '');
   return 1 if (-f "$_[0]$dbm_ext");
   return 0;
}

sub renamedb {
   my ($olddb, $newdb) = @_;

   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');

   if ($dbm_ext eq '.dir' || $dbm_ext eq '.pag') {
     return 1 if rename("$olddb.dir", "$newdb.dir") && rename("$olddb.pag", "$newdb.pag");
   } else {
     return 1 if rename("$olddb$dbm_ext", "$newdb$dbm_ext");
   }

   $dbm_errno  = -1;
   $dbm_errmsg = $!;

   return 0;
}

sub chowndb {
   my ($uid, $gid, @dblist) = @_;
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');
   return 1 if (chown($uid, $gid, dblist2dbfiles(@dblist)));
   ($dbm_errno, $dbm_errmsg)=(-1, $!);
   return 0;
}

sub chmoddb {
   my ($fmode, @dblist) = @_;
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');
   return 1 if (chmod($fmode, dblist2dbfiles(@dblist)));
   $dbm_errno  = -1;
   $dbm_errmsg = $!;
   return 0;
}

sub unlinkdb {
   ($dbm_errno, $dbm_errmsg, $dbm_warning) = (0, '', '');
   return 1 if unlink(dblist2dbfiles(@_));
   $dbm_errno  = -1;
   $dbm_errmsg = $!;
   return 0;
}

sub guessoptions {
   my %DB              = ();
   my @filelist        = ();
   my @delfiles        = ();
   my $dbm_ext         = '';
   my $dbmopen_ext     = '';
   my $dbmopen_haslock = 0;

   my $testdir = ow::tool::mktmpdir('dbmtest.tmp');

   return ($dbm_ext, $dbmopen_ext, $dbmopen_haslock) if $testdir eq '';

   # open a db file in the test directory named 'test'
   # if it opens successfully it will append the dbm_ext to the filename
   # as it is supported on the system (usually 'test.db', but maybe 'test.dir', or 'test.pag')
   dbmopen(%DB, "$testdir/test", 0600);
   dbmclose(%DB);

   @delfiles = ();

   opendir(TESTDIR, $testdir);

   while (defined(my $filename = readdir(TESTDIR))) {
      if ($filename !~ m/^\./) {
         push(@filelist, $filename);
         push(@delfiles, ow::tool::untaint("$testdir/$filename"));
      }
   }

   closedir(TESTDIR);

   unlink(@delfiles) if scalar @delfiles > 0;

   @filelist = reverse sort(@filelist);

   if ($filelist[0] =~ m/(\.[^.]+)$/) {
      ($dbm_ext, $dbmopen_ext) = ($1, '');
   } else {
      ($dbm_ext, $dbmopen_ext) = ('.db', '.db');
   }

   my $result = '';

   ow::filelock::lock("$testdir/test$dbm_ext", LOCK_EX);

   eval {
           no warnings 'all';
           local $SIG{'__DIE__'};
           local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
           alarm 5;	# timeout 5 sec
           dbmopen(%DB, "$testdir/test$dbmopen_ext", 0600);
           dbmclose(%DB);
           alarm 0;
        };

   # eval error, it means timeout
   $dbmopen_haslock = $@ ? 1 : 0;

   ow::filelock::lock("$testdir/test$dbm_ext", LOCK_UN);

   @delfiles = ();

   opendir(TESTDIR, $testdir);

   while (defined(my $filename = readdir(TESTDIR))) {
      push(@delfiles, ow::tool::untaint("$testdir/$filename")) if $filename !~ m/^\./;
   }

   closedir(TESTDIR);

   unlink(@delfiles) if scalar @delfiles > 0;

   rmdir($testdir);

   return ($dbm_ext, $dbmopen_ext, $dbmopen_haslock);
}

sub get_defaultdbtype {
   if (!defined $_defaultdbtype || $_defaultdbtype eq '') {
      my $tmpdir    = ow::tool::mktmpdir('dbmtest.tmp');
      my $tmpdbfile = ow::tool::untaint("$tmpdir/tmpdb");

      my %TMPDB = ();

      dbmopen(%TMPDB, "$tmpdbfile$dbmopen_ext", 0600);

      dbmclose(%TMPDB);

      $_defaultdbtype = get_dbtype("$tmpdbfile$dbm_ext");

      unlink ("$tmpdbfile$dbm_ext", "$tmpdbfile.dir", "$tmpdbfile.pag");

      rmdir($tmpdir);
   }

   $_defaultdbtype = defined $_defaultdbtype ? $_defaultdbtype : '';

   return $_defaultdbtype;
}

sub get_dbtype {
   my $dbfile = shift;

   open(F, "-|") or
      do { open(STDERR,">/dev/null"); exec(ow::tool::findbin('file'), $dbfile); exit 9 };

   local $/;
   undef $/;

   my $dbtype = <F>;

   $dbtype = defined $dbtype ? $dbtype : '';

   $dbtype =~ s/^.*?:\s*//;
   $dbtype =~ s/\s*$//;

   close(F);

   return $dbtype;
}

sub dblist2dbfiles {
   my @dbfiles = ();

   foreach (@_) { # @_ is list of db name
      my $db = ow::tool::untaint($_);
      if ($dbm_ext eq '.dir' || $dbm_ext eq '.pag') {
         push(@dbfiles, "$db.dir", "$db.pag");
      } else {
         push(@dbfiles, "$db$dbm_ext");
      }
   }

   return(@dbfiles);
}

1;
