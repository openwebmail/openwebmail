#
# filelock.pl - functions for filelock on local or nfs server
#
# 2001/04/25 tung@turtle.ee.ncku.edu.tw
#

use FileHandle;

sub filelock {
   if ( $config{'use_dotlockfile'} ) {
      return filelock_dotlockfile(@_);
   } else {
      return filelock_flock(@_);
   }
}

# this routine provides flock with filename
# it opens the file to get the handle if need,
# than do lock operation on the related filehandle
my %opentable;
sub filelock_flock {
   my ($filename, $lockflag)=@_;
   my ($dev, $inode, $fh);

   if ( (! -e $filename) && $lockflag ne LOCK_UN) {
      ($filename =~ /^(.+)$/) && ($filename = $1);   
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
   # we turn nonblocking lock into a blocking lock with timeout limit=30sec
   # thus the lock will have more chance to success.

   if ( $lockflag & LOCK_NB ) {	# nonblocking lock
      my $retval;
      eval {
         local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
         alarm 30;
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


# this routine use filename.lock for the lock of filename
# it is only recommended if the files are located on remote nfs server
# and the lockd on your nfs server or client has problems
# since it is slower than flock
sub filelock_dotlockfile {
   my ($filename, $lockflag)=@_;
   my ($mode, $count);

   return 1 unless ($lockflag & (LOCK_SH|LOCK_EX|LOCK_UN));

   my $endtime;
   if ($lockflag & LOCK_NB) {	# turn nonblock lock to 30sec blocking lock
      $endtime=time()+30;
   } else {
      $endtime=time()+86400;
   }

   my $oldumask=umask(0111);

   # resolve symbolic link
   while (-l "$filename") {
      $filename=readlink($filename);
   }
   ($filename =~ /^(.+)$/) && ($filename = $1);		# bypass taint check
   
   while (time() <= $endtime) {
      my $status=0;

      if ( -f "$filename.lock" ) {	# remove stale lock
         my $t=(stat("$filename.lock"))[9];
         unlink("$filename.lock") if (time()-$t > 300);
      }

      if (_lock("$filename.lock")==0) {
         sleep 1;
         next;
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
            print "$_\n";
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
         return(1);
      } else {
         _unlock("$filename.lock");
         sleep 1;
         next;
      }
   }   

   _unlock("$filename.lock");
   umask($oldumask);
   return(0);
}


# _lock and _unlock are used to lock/unlock xxx.lock
sub _lock {
   my ($filename, $staletimeout)=@_;
   ($filename =~ /^(.+)$/) && ($filename = $1);		# bypass taint check

   $staletimeout=30 if $staletimeout eq 0;
   if ( -f "$filename.lock" ) {
      my $t=(stat("$filename.lock"))[9];
      unlink("$filename.lock") if (time()-$t > $staletimeout);
   }
   if ( sysopen(LL, "$filename.lock", O_RDWR|O_CREAT|O_EXCL) ) {
      close(LL);
      return(1)
   } else {
      return(0);
   }
}
sub _unlock {
   my ($filename)=$_[0];
   ($filename =~ /^(.+)$/) && ($filename = $1);		# bypass taint check

   if ( unlink("$filename.lock") ) {
      return(1);
   } else {
      return(0);
   }
}

1;
