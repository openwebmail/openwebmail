# this is used for profiling
use strict;

use vars qw(%lasttimeofday);
%lasttimeofday=();

sub gettimeofday {
   my ($SYS_gettimeofday, $timeval, $timezone, $sec, $usec);

   $SYS_gettimeofday = 116;  # should really be from sys/syscalls.ph
   $timeval = $timezone = ("\0" x 4) x 2;
   syscall($SYS_gettimeofday, $timeval, $timezone)
	     && die "gettimeofday failed: $!";
   ($sec, $usec) = unpack("L2", $timeval);
   return $sec +  $usec/1e6;
}

sub timeofday_init {
   %lasttimeofday=();
}

sub timeofday_diff {
   my $tag=$_[0]||'default';

   my $t=$lasttimeofday{$tag};
   $lasttimeofday{$tag}=gettimeofday();
   if ($t) {
      return(sprintf("%10.6f", $lasttimeofday{$tag}-$t));
   } else {
      return(sprintf("%10.6f", 0));
   }
}

1;
