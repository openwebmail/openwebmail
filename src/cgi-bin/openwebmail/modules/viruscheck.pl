package ow::viruscheck;
#
# viruscheck.pl - routines to call external checker to detect virus
#
# 2004/07/01 tung.AT.turtle.ee.ncku.edu.tw
#

use strict;
use Fcntl qw(:DEFAULT :flock);
require "modules/tool.pl";

# sub scanmsg(pipecmd, msg_reference)
# ret (0, null): message is clean
#     (1, virusname): virus found
#     (-1, runtime error): scanner has runtime error

#
# The following routines assume the clamav is used for the viruscheck.
# To make this work, you have to start up the clamd first,
# then set 'enable_viruscheck yes' in the openwbemail.conf
#

# cmd:    /usr/local/bin/clamdscan --mbox --disable-summary --stdout -
# output: stream: OK
#         stream: VirusName FOUND
sub scanmsg {
   my $ret=pipecmd_msg(@_);

   if ($ret=~/stream: OK/) {
      return (0, '');
   } elsif ($ret=~/stream: (.*?) FOUND/) {
      return (1, $1);
   } else {
      $ret=~s/ERROR:\s+//;
      return (-1, $ret);
   }
}

# common routine, ret pipe output #########################################
sub pipecmd_msg {
   my ($pipecmd, $r_message)=@_;

   my $username=getpwuid($>);	# username of euid
   $pipecmd=~s/\@\@\@USERNAME\@\@\@/$username/g;
   my @cmd=split(/\s+/, $pipecmd); foreach (@cmd) { (/^(.*)$/) && ($_=$1) };

   my ($outfh, $outfile)=ow::tool::mktmpfile('viruscheck.out');
   my ($errfh, $errfile)=ow::tool::mktmpfile('viruscheck.err');

   local $SIG{CHLD}; undef $SIG{CHLD};  # disable $SIG{CHLD} temporarily for wait()
   local $|=1; # flush all output

   open(P, "|-") or
      do { open(STDERR,">&=".fileno($errfh)); open(STDOUT,">&=".fileno($outfh)); exec(@cmd); exit 9 };
   close($errfh); close($outfh);

   my ($out, $err, $errmsg);
   if (ref($r_message) eq 'ARRAY') {
      print P @{$r_message} or $errmsg=$!;
   } else {
      print P ${$r_message} or $errmsg=$!;
   }
   close(P) or $errmsg=$!;

   sysopen(F, $errfile, O_RDONLY); $err=<F>; close(F); unlink $errfile;
   sysopen(F, $outfile, O_RDONLY); $out=<F>; close(F); unlink $outfile;

   foreach ($errmsg, $err, $out) {
      s/[\r\n]//g; return $_ if ($_ ne '');
   }
}

1;
