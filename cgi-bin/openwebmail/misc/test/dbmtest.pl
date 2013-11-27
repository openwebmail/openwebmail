#!/usr/bin/perl
#
# find out proper settings for option dbm_ext, dbmopen_ext and dbmopen_haslock
#
use strict;
use Fcntl qw(:DEFAULT :flock);
use FileHandle;

print "\n";

check_tell_bug();
my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock)=guessoptions();
print_dbm_module();
check_db_file_pm();
print_dbm_option($dbm_ext, $dbmopen_ext, $dbmopen_haslock);
check_savedsuid_support();

exit 0;

# test routines #########################################################

sub check_tell_bug {
   my $offset;
   my $testfile="/tmp/testfile.$$";
   ($testfile =~ /^(.+)$/) && ($testfile = $1);

   open(F, ">$testfile"); print F "test"; close(F);
   open(F, ">>$testfile"); $offset=tell(F); close(F);
   unlink($testfile);

   if ($offset==0) {
      print qq|WARNING!\n\n|.
            qq|The perl on your system has serious bug in routine tell()!\n|.
            qq|While openwebmail can work properly with this bug, other perl application\n|.
            qq|may not function properly and thus cause data loss.\n\n|.
            qq|We suggest that you should patch your perl as soon as possible.\n\n\n|.
      return -1;
   }
   return 0;
}

sub guessoptions {
   my (%DB, @filelist, @delfiles);
   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock);

   mkdir ("/tmp/dbmtest.$$", 0755);

   dbmopen(%DB, "/tmp/dbmtest.$$/test", 0600); dbmclose(%DB);

   @delfiles=();
   opendir(TESTDIR, "/tmp/dbmtest.$$");
   while (defined(my $filename = readdir(TESTDIR))) {
      ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...
      if ($filename!~/^\./ ) {
         push(@filelist, $filename);
         push(@delfiles, "/tmp/dbmtest.$$/$filename");
      }
   }
   closedir(TESTDIR);
   unlink(@delfiles) if ($#delfiles>=0);

   @filelist=reverse sort(@filelist);
   if ($filelist[0]=~/(\..*)$/) {
      ($dbm_ext, $dbmopen_ext)=($1, '');
   } else {
      ($dbm_ext, $dbmopen_ext)=('.db', '.db');
   }

   my $result;
   flock_lock("/tmp/dbmtest.$$/test$dbm_ext", LOCK_EX);
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 5;	# timeout 5 sec
      $result = dbmopen(%DB, "/tmp/dbmtest.$$/test$dbmopen_ext", 0600);
      dbmclose(%DB) if ($result);
      alarm 0;
   };
   if ($@ or !$result) {	# eval error, it means timeout
      $dbmopen_haslock=1;
   } else {
      $dbmopen_haslock=0;
   }
   flock_lock("/tmp/dbmtest.$$/test$dbm_ext", LOCK_UN);

   @delfiles=();
   opendir(TESTDIR, "/tmp/dbmtest.$$");
   while (defined(my $filename = readdir(TESTDIR))) {
      ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...
      push(@delfiles, "/tmp/dbmtest.$$/$filename") if ($filename!~/^\./ );
   }
   closedir(TESTDIR);
   unlink(@delfiles) if ($#delfiles>=0);

   rmdir("/tmp/dbmtest.$$");

   return($dbm_ext, $dbmopen_ext, $dbmopen_haslock);
}

sub print_dbm_module {
   print "You perl uses the following packages for dbm::\n\n";
   my @pm;
   foreach (keys %INC) { push (@pm, $_) if (/DB.*File/); }
   foreach (sort @pm) { print "$_\t\t$INC{$_}\n"; }
   print "\n\n";
}

sub check_db_file_pm {
   my $dbfile_pm=$INC{'DB_File.pm'};
   if ($dbfile_pm) {
      my $t;
      open(F, $dbfile_pm); while(<F>) {$t.=$_;} close(F);
      $t=~s/\s//gms;
      if ($t!~/\$arg\[3\]=0666unlessdefined\$arg\[3\];/sm) {
         print qq|Please modify $dbfile_pm by adding\n\n|.
               qq|\t\$arg[3] = 0666 unless defined \$arg[3];\n\n|.
               qq|before the following text (about line 247)\n\n|.
               qq|\t# make recno in Berkeley DB version 2 work like recno in version 1\n\n\n|;
         return -1;
      }
   }
   return 0;
}

sub print_dbm_option {
   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock)=@_;

   $dbm_ext='none' if ($dbm_ext eq '');
   $dbmopen_ext='none' if ($dbmopen_ext eq '');
   if ($dbmopen_haslock) {
      $dbmopen_haslock='yes';
   } else {
      $dbmopen_haslock='no';
   }
   print qq|The dbm options in dbm.conf should be set as follows:\n\n|.
         qq|dbm_ext    \t\t$dbm_ext\n|.
         qq|dbmopen_ext\t\t$dbmopen_ext\n|.
         qq|dbmopen_haslock\t\t$dbmopen_haslock\n\n\n|;
}

sub check_savedsuid_support {
   return if ($>!=0);

   $>=65534;
   $>=0;
   if ($>!=0) {
      print qq|Your system didn't have saved suid support,\n|.
            qq|please set the following option in suid.conf\n\n|.
            qq|\tsavedsuid_support no\n\n\n|;
      return -1;
   }
   return 0;
}


# Routine from filelock.pl ##############################################
use vars qw(%opentable);
%opentable=();

# this routine provides flock with filename
# it opens the file to get the handle if need,
# than do lock operation on the related filehandle
sub flock_lock {
   my ($filename, $lockflag, $perm)=@_;
   ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...

   my ($dev, $inode, $fh, $n, $retval);

   # deal unlock first
   if ($lockflag & LOCK_UN) {
      return 1 if ( !-e $filename);
      ($dev, $inode)=(stat($filename))[0,1];
      return 0 if ($dev eq '' || $inode eq '');

      if (defined($opentable{"$dev-$inode"}) ) {
         $fh=$opentable{"$dev-$inode"}{fh};
         $retval=flock($fh, LOCK_UN);
         if ($retval) {
            $opentable{"$dev-$inode"}{n}--;
            if ($opentable{"$dev-$inode"}{n}==0) {
               delete($opentable{"$dev-$inode"});
               close($fh) if ( defined(fileno($fh)) );
            }
         }
      } else {
         return 0;
      }
      return $retval;
   }

   # else are file lock
   if (!-e $filename) {
      $perm=0600 if (!$perm);
      sysopen(F, $filename, O_RDWR|O_CREAT, $perm) or return 0; # create file for lock
      close(F);
   }
   ($dev, $inode)=(stat($filename))[0,1];
   return 0 if ($dev eq '' || $inode eq '');

   if (!defined($opentable{"$dev-$inode"}) ) {
      $fh=do { local *FH };
      if (sysopen($fh, $filename, O_RDWR) ||	# try RDWR open first
          sysopen($fh, $filename, O_RDONLY) ) {	# then RDONLY for readonly file
         $opentable{"$dev-$inode"}{fh}=$fh;
      } else {
         return 0;
      }
   } else {
      $fh=$opentable{"$dev-$inode"}{fh};
   }

   # turn nonblocking lock to  30 secs timeouted lock
   # so owm gets higher chance to success in case other ap locks same file for only few secs
   # turn blocking    lock to 120 secs timeouted lock
   # so openwebmaill won't hang because of file locking
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      if ( $lockflag & LOCK_NB ) {	# nonblocking lock
         alarm 30;
      } else {
         alarm 120;
      }
      $retval=flock($fh, $lockflag&(~LOCK_NB));
      alarm 0;
   };
   $retval=0 if ($@);	# eval error, it means timeout
   $opentable{"$dev-$inode"}{n}++ if ($retval);

   return($retval);
}
