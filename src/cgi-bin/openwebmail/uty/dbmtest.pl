#!/usr/bin/perl
#
# find out proper settings for option dbm_ext, dbmopen_ext and dbmopen_haslock
#
use strict;
use Fcntl qw(:DEFAULT :flock);
use FileHandle;

if (tell_has_bug()) {
   print qq|\nWARNING, the perl on your system has serious bug in routine tell()!\n|.
         qq|While openwebmail can work properly with this bug, other perl application\n|.
         qq|may not function properly and thus cause data loss.\n|.
         qq|We suggest that you should patch your perl as soon as possible.\n\n\n|;
}

my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock)=dbm_test();
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
   }
}

print qq|The dbm options in openwebmail.conf should be set as follows:\n\n|.
      qq|dbm_ext    \t\t$dbm_ext\n|.
      qq|dbmopen_ext\t\t$dbmopen_ext\n|.
      qq|dbmopen_haslock\t\t$dbmopen_haslock\n\n|;

exit 0;

sub dbm_test {
   my (%DB, @filelist);
   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock);

   mkdir ("/tmp/dbmtest.$$", 0755);

   dbmopen(%DB, "/tmp/dbmtest.$$/test", 0600); dbmclose(%DB);
   opendir (TESTDIR, "/tmp/dbmtest.$$");
   while (defined(my $filename = readdir(TESTDIR))) {
      ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...
      if ($filename!~/^\./ ) {
         push(@filelist, $filename);
         unlink("/tmp/dbmtest.$$/$filename");
      }
   }
   closedir(TESTDIR);
   @filelist=reverse sort(@filelist);
   if ($filelist[0]=~/(\..*)$/) {
      ($dbm_ext, $dbmopen_ext)=($1, '');
   } else {
      ($dbm_ext, $dbmopen_ext)=('.db', '.db');
   }

   filelock_flock("/tmp/dbmtest.$$/test$dbm_ext", LOCK_EX);
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 5;	# timeout 5 sec
      dbmopen(%DB, "/tmp/dbmtest.$$/test$dbmopen_ext", 0600); dbmclose(%DB);
      alarm 0;
   };
   if ($@) {	# eval error, it means timeout
      $dbmopen_haslock=1;
   } else {
      $dbmopen_haslock=0;
   }
   filelock_flock("/tmp/dbmtest.$$/test$dbm_ext", LOCK_UN);

   opendir (TESTDIR, "/tmp/dbmtest.$$");
   while (defined(my $filename = readdir(TESTDIR))) {
     ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...
      unlink("/tmp/dbmtest.$$/$filename") if ($filename!~/^\./ );
   }
   closedir(TESTDIR);

   rmdir("/tmp/dbmtest.$$");

   # convert value to str
   if ($dbmopen_ext eq $dbm_ext) {
      $dbmopen_ext='%dbm_ext%';
   } elsif ($dbmopen_ext eq "") {
      $dbmopen_ext='none';
   }
   if ($dbmopen_haslock) {
      $dbmopen_haslock='yes';
   } else {
      $dbmopen_haslock='no';
   }
   return($dbm_ext, $dbmopen_ext, $dbmopen_haslock);
}

sub tell_has_bug {
   my $offset;
   my $testfile="/tmp/testfile.$$";
   ($testfile =~ /^(.+)$/) && ($testfile = $1);

   open(F, ">$testfile"); print F "test"; close(F);
   open(F, ">>$testfile"); $offset=tell(F); close(F);
   unlink($testfile);
   
   return 1 if ($offset==0);
   return 0;
}   

# Routine from filelock.pl ##############################################

# this routine provides flock with filename
# it opens the file to get the handle if need,
# than do lock operation on the related filehandle
my %opentable;
sub filelock_flock {
   my ($filename, $lockflag)=@_;
   my ($dev, $inode, $fh);

   ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint...

   if ( (! -e $filename) && $lockflag ne LOCK_UN) {
      sysopen(F, $filename, O_RDWR|O_CREAT, 0600); # create file for lock
      close(F);
   }

   ($dev, $inode)=(stat($filename))[0,1];
   if ($dev eq '' || $inode eq '') {
      return(0);
   }

   if (defined($opentable{"$dev-$inode"}) ) {	
      $fh=$opentable{"$dev-$inode"};
   } else { # handle not found, open it!
      $fh=FileHandle->new();
      if (sysopen($fh, $filename, O_RDWR)) {
         $opentable{"$dev-$inode"}=$fh;
      } else {
         return(0);
      }
   }

   # Since nonblocking lock may return errors
   # even the target is locked by others for just a few seconds,
   # we turn nonblocking lock into a blocking lock with timeout limit=60sec
   # thus the lock will have more chance to success.

   if ( $lockflag & LOCK_NB ) {	# nonblocking lock
      my $retval;
      eval {
         local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
         alarm 60;
         $retval=flock($fh, $lockflag & (~LOCK_NB) );	
         alarm 0;
      };
      if ($@) {	# eval error, it means timeout
         $retval=0;
      }
      return($retval);

   } else {			# blocking lock				
      return(flock($fh, $lockflag));
   }
}

sub tell_has_bug {
   my $offset;
   my $testfile="/tmp/testfile.$$";
   ($testfile =~ /^(.+)$/) && ($testfile = $1);

   open(F, ">$testfile"); print F "test"; close(F);
   open(F, ">>$testfile"); $offset=tell(F); close(F);
   unlink($testfile);
   
   return 1 if ($offset==0);
   return 0;
}   
