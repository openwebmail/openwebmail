package ow::dbm;
use strict;
#
# dbm.pl - dbm routines that hides differences of various DBM implementations
#
# 2003/12/07 tung.AT.turtle.ee.ncku.edu.tw
#

# $dbm_errmsg will contain brief hint in case any error happens,
# the caller routine may use it to form a more complete error message

########## No configuration required from here ###################

use Fcntl qw(:DEFAULT :flock);
require "modules/tool.pl";

use vars qw($dbm_ext $dbmopen_ext $dbmopen_haslock);
use vars qw($dbm_errno $dbm_errmsg $dbm_warning);

my %conf;
if (($_=ow::tool::find_configfile('etc/dbm.conf', 'etc/dbm.conf.default')) ne '') {
   my ($ret, $err)=ow::tool::load_configfile($_, \%conf);
   die $err if ($ret<0);
}

$dbm_ext=$conf{'dbm_ext'}||'.db';
$dbmopen_ext=$conf{'dbmopen_ext'}||''; $dbmopen_ext='' if ($dbmopen_ext eq 'none');
$dbmopen_haslock=$conf{'dbmopen_haslock'}||'yes'; $dbmopen_haslock=($dbmopen_haslock=~/yes/i)?1:0;

########## end init ##############################################

sub open {
   my ($r_hash, $db, $flag, $perm)=@_;
   $perm=0600 if (!$perm);
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');

   my ($openerror, $dbtype, $defaultdbtype)=('', '', '');
   for (my $retry=0; $retry<3; $retry++) {
      if (!$dbmopen_haslock) {
         if (! -f "$db$dbm_ext") { # ensure dbm existance before lock
            my (%t, $createerror);
            dbmopen(%t, "$db$dbmopen_ext", $perm) or $createerror=$!;
            dbmclose(%t);
            if ($createerror ne '') {
               ($dbm_errno, $dbm_errmsg)=(-1, $createerror);
               return 0;
            } elsif (! -f "$db$dbm_ext") {	# dbmopen ok but dbm file not found
               ($dbm_errno, $dbm_errmsg)=(-2, "wrong dbm_ext/dbmopen_ext setting?");
               return 0;
            }
         }
         if (! ow::filelock::lock("$db$dbm_ext", $flag, $perm) ) {
            if ($flag & LOCK_SH) {
               ($dbm_errno, $dbm_errmsg)=(-3, "read lock failed");
            } else {
               ($dbm_errno, $dbm_errmsg)=(-3, "write lock failed");
            }
            return 0;
         }
      }

      return 1 if (dbmopen(%{$r_hash}, "$db$dbmopen_ext", $perm));
      $openerror=$!;

      ow::filelock::lock("$db$dbm_ext", LOCK_UN) if (!$dbmopen_haslock);

      # db may be temporarily unavailable because of too many concurrent accesses,
      # eg: reading a message with lots of attachments
      if ($openerror=~/Resource temporarily unavailable/) {
         $dbm_warning.="db temporarily unavailable, retry ".($retry+1).". ";
         sleep 1;
         next;
      }

      # if existing db is in wrong format, then unlink it and create a new one
      if ( -f "$db$dbm_ext" && -r _ && $dbtype eq '') {
         $dbtype=get_dbtype("$db$dbm_ext");
         $defaultdbtype=get_defaultdbtype();
         if ($dbtype ne $defaultdbtype) {	# db is in wrong format
            if (unlink("$db$dbm_ext") ) {
               $dbm_warning="changing db format from $dbtype to $defaultdbtype. ";
               next;
            } else {
               $openerror.="(wrong db format, default:$defaultdbtype, $db$dbm_ext:$dbtype)";
            }
         }
      }

      last;	# default to exit the loop
   }
   ($dbm_errno, $dbm_errmsg)=(-4 , $openerror);
   return 0;
}

sub close {
   my ($r_hash, $db)=@_;
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');

   dbmclose(%{$r_hash});
   ow::filelock::lock("$db$dbm_ext", LOCK_UN) if (!$dbmopen_haslock);
   return 1;
}

sub exist {
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');
   return 1 if (-f "$_[0]$dbm_ext");
   return 0;
}

sub rename {
   my ($olddb, $newdb)=@_;
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');

   if ($dbm_ext eq '.dir' || $dbm_ext eq '.pag') {
     return 1 if (rename("$olddb.dir", "$newdb.dir") && 
                  rename("$olddb.pag", "$newdb.pag") );
   } else {
     return 1 if (rename("$olddb$dbm_ext", "$newdb$dbm_ext") );
   }
   ($dbm_errno, $dbm_errmsg)=(-1, $!);
   return 0;
}

sub chown {
   my ($uid, $gid, @dblist)=@_;
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');
   return 1 if (chown($uid, $gid, dblist2dbfiles(@dblist)));
   ($dbm_errno, $dbm_errmsg)=(-1, $!); 
   return 0;
}

sub chmod {
   my ($fmode, @dblist)=@_;
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');
   return 1 if (chmod($fmode, dblist2dbfiles(@dblist)));
   ($dbm_errno, $dbm_errmsg)=(-1, $!);
   return 0;
}

sub unlink {
   ($dbm_errno, $dbm_errmsg, $dbm_warning)=(0, '', '');
   return 1 if (unlink(dblist2dbfiles(@_)));
   ($dbm_errno, $dbm_errmsg)=(-1, $!);
   return 0;
}

########## misc support routine ##################################

use vars qw($_defaultdbtype);
sub get_defaultdbtype {
   if ($_defaultdbtype eq '') {
      my $t=ow::tool::untaint("/tmp/.dbmtest.$$");
      my %t; dbmopen(%t, "$t$dbmopen_ext", 0600); dbmclose(%t);

      $_defaultdbtype=get_dbtype("$t$dbm_ext");

      unlink ("$t$dbm_ext", "$t.dir", "$t.pag");
    }
    return($_defaultdbtype);
}

sub get_dbtype {
   my $f=ow::tool::untaint("/tmp/.flist.$$");
   open(F, ">$f"); print F "$_[0]\n"; close(F);	# pass arg through file for safety

   my $dbtype=`/usr/bin/file -f $f`; unlink($f);
   $dbtype=~s/^.*?:\s*//; $dbtype=~s/\s*$//;

   return($dbtype);
}

sub dblist2dbfiles {
   my @dbfiles=();
   foreach (@_) {	# @_ is list of db to be deleted
      my $db=ow::tool::untaint($_);
      if ($dbm_ext eq '.dir' || $dbm_ext eq '.pag') {
         push(@dbfiles, "$db.dir", "$db.pag");
      } else {
         push(@dbfiles, "$db$dbm_ext");
      }
   }
   return(@dbfiles);
}

1;
