#
# filelock.pl - filelock routines for local or nfs server
#
# 2001/04/25 tung.AT.turtle.ee.ncku.edu.tw
#
package openwebmail::filelock;

use strict;
use Fcntl qw(:DEFAULT :flock);

use vars qw(%opentable);
%opentable=();

# close all files which were opend for file locking
# this should be called at the end of each request to free the file handles
sub closeall {
   foreach (keys %opentable) {
      close($opentable{$_}) if ( defined(fileno($opentable{$_})) );
   }
   %opentable=();
}

# this routine provides flock with filename
# it opens the file to get the handle if need,
# than do lock operation on the related filehandle
sub flock_lock {
   my ($filename, $lockflag, $perm)=@_;

   $filename=untaint($filename);
   if ( (! -e $filename) && $lockflag ne LOCK_UN) {
      $perm=0600 if (!$perm);
      sysopen(F, $filename, O_RDWR|O_CREAT, $perm) or return 0; # create file for lock
      close(F);
   }

   my ($dev, $inode, $fh);
   ($dev, $inode)=(stat($filename))[0,1];
   return 0 if ($dev eq '' || $inode eq '');

   if (defined($opentable{"$dev-$inode"}) ) {
      $fh=$opentable{"$dev-$inode"};
   } else { # handle not found, open it!
      $fh=do { local *FH };
      if (sysopen($fh, $filename, O_RDWR) ||	# try RDWR open first
          sysopen($fh, $filename, O_RDONLY) ) {	# then RDONLY for readonly file
         $opentable{"$dev-$inode"}=$fh;
      } else {
         return 0;
      }
   }

   # turn nonblocking lock to  30 secs timeouted lock
   # so owm gets higher chance to success in case other ap locks same file for only few secs
   # turn blocking    lock to 120 secs timeouted lock
   # so openwebmaill won't hang because of file locking
   my $retval;
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      if ( $lockflag & LOCK_NB ) {	# nonblocking lock
         alarm 30;
      } else {
         alarm 120;
      }
      $retval=flock($fh, $lockflag & (~LOCK_NB) );
      alarm 0;
   };
   if ($@) {	# eval error, it means timeout
      $retval=0;
   }
   return($retval);
}


# this routine use filename.lock for the lock of filename
# it is only recommended if the files are located on remote nfs server
# and the lockd on your nfs server or client has problems
# since it is slower than flock
#
# This routine stores the shared lock counter in filename.lock and
# uses filename.lock.lock to guarentee unique access to filename.lock.
# If the filename is locates in a readonly directory, since the
# filename.lock and filename.lock.lock could not be created, this routine will
# grant all shared lock and deny all exclusive lock.
sub dotfile_lock {
   my ($filename, $lockflag, $perm)=@_;
   return 1 unless ($lockflag & (LOCK_SH|LOCK_EX|LOCK_UN));

   $filename=untaint($filename);
   if ( (! -e $filename) && $lockflag ne LOCK_UN) {
      $perm=0600 if (!$perm);
      sysopen(F, $filename, O_RDWR|O_CREAT, $perm) or return 0; # create file for lock
      close(F);
   }

   # resolve symbolic link
   my $ldepth=0;
   while (-l "$filename") {
      $ldepth++; return (0) if ($ldepth>8);		# link to deep
      $filename=readlink($filename);
   }
   $filename=untaint($filename);

   my $oldumask=umask(0111);
   my ($endtime, $mode, $count);

   if ($lockflag & LOCK_NB) {	# turn nonblock lock to 30sec blocking lock
      $endtime=time()+30;
   } else {			# turn blocking lock to 120sec blocking lock
      $endtime=time()+120;
   }

   while (time() <= $endtime) {
      my $status=0;

      if ( my $t=(stat("$filename.lock"))[9] ) {
         unlink("$filename.lock") if (time()-$t > 300);	# remove stale lock
      }

      my $locklock=_lock("$filename.lock");
      if ($locklock==0) {
         sleep 1;
         next;
      } elsif ($locklock==-1) {	# rdonly dir, no further processing
         if ($lockflag & LOCK_EX) {
            return 0;
         } else {
            return 1;
         }
      }

      if ( $lockflag & LOCK_UN ) {
         if ( -f "$filename.lock") {
            if (open(L, "+<$filename.lock") ) {
               $_=<L>; chop;
               ($mode,$count)=split(/:/);
               if ( $mode eq "READ" && $count>1 ) {
                  $count--;
                  seek(L, 0, 0);
                  print L "READ:$count\n";
                  truncate(L, tell(L));
                  close(L);
                  $status=1;
               } else {
                  close(L);
                  unlink("$filename.lock");
                  if ( -f "$filename.lock" ) {
                     $status=0;
                  } else {
                     $status=1;
                  }
               }
            } else { # can not read .lock
               $status=0;
            }
         } else { # no .lock file
            $status=1;
         }

      } elsif ( sysopen(L, "$filename.lock", O_RDWR|O_CREAT|O_EXCL) ) {
         if ( $lockflag & LOCK_EX ) {
            close(L);
         } elsif ( $lockflag & LOCK_SH ) {
            print L "READ:1\n";
            close(L);
         }
         $status=1;

      } else { # create failed, assume lock file already exists
         if ( ($lockflag & LOCK_SH) && open(L,"+<$filename.lock") ) {
            $_=<L>; chop;
            ($mode, $count)=split(/:/);
            if ( $mode eq "READ" ) {
               $count++;
               seek(L,0,0);
               print L "READ:$count\n";
               truncate(L, tell(L));
               close(L);
               $status=1;
            } else {
               $status=0;
            }
         } else {
            $status=0;
         }
      }

      if ($status==1) {
         _unlock("$filename.lock");
         umask($oldumask);
         return 1;
      } else {
         _unlock("$filename.lock");
         sleep 1;
         next;
      }
   }

   _unlock("$filename.lock");
   umask($oldumask);
   return 0;
}


# _lock and _unlock are used to lock/unlock xxx.lock
sub _lock {
   my ($filename, $staletimeout)=@_;
   $filename=untaint($filename);

   $staletimeout=60 if $staletimeout eq 0;
   if ( my $t=(stat("$filename.lock"))[9] ) {
      unlink("$filename.lock") if (time()-$t > $staletimeout);
   }
   if ( sysopen(LL, "$filename.lock", O_RDWR|O_CREAT|O_EXCL) ) {
      close(LL);
      return 1
   } else {
      if ($!=~/permission/i) {	# .lock file in readonly dir?
         return -1;
      } else {			# .lock file already exist
         return 0;
      }
   }
}

sub _unlock {
   my $filename=untaint($_[0]);
   if ( unlink("$filename.lock") ) {
      return 1;
   } else {
      if ($!=~/permission/i) {	# .lock file in readonly dir?
         return -1;
      } else {
         return 0;
      }
   }
}

sub untaint {
   local $_ = shift;
   m/^(.*)$/;
   return $1;
}

1;
