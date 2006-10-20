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
# then set 'enable_viruscheck yes' in the openwebmail.conf
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
   # refer to perlopentut and perlipc for more information.
   my ($pipecmd, $r_message)=@_;

   my $username=getpwuid($>);	# username of euid
   $pipecmd=~s/\@\@\@USERNAME\@\@\@/$username/g;

   my ($outfh, $outfile)=ow::tool::mktmpfile('viruscheck.out');
   my ($errfh, $errfile)=ow::tool::mktmpfile('viruscheck.err');

   local $|=1; # flush all output

   # alias STDERR and STDOUT to get the output of the pipe
   open(STDERR,">&=".fileno($errfh)) or return("dup STDERR failed: $!");
   open(STDOUT,">&=".fileno($outfh)) or return("dup STDOUT failed: $!");

   local $SIG{PIPE} = 'IGNORE'; # don't die if the fork pipe breaks

   my ($out, $err, $errmsg);
   open(P, "|$pipecmd") or return("can't fork to pipecmd: $! pipecmd: $pipecmd");
   if (ref($r_message) eq 'ARRAY') {
      print P @{$r_message} or return("can't write to pipe: $!");
   } else {
      print P ${$r_message} or return("can't write to pipe: $!");
   }
   close(P) or return("pipe broke - check connection to clamd - status: $?");

   close($errfh) or return("can't close errfh: $!");
   close($outfh) or return("can't close outfh: $!");

   sysopen(F, $errfile, O_RDONLY) or return("can't open errfile $errfile: $!");
   $err = <F>;
   close(F) or return("can't close errfile $errfile: $!");
   unlink $errfile;

   sysopen(F, $outfile, O_RDONLY) or return("can't open outfile $outfile: $!");
   $out = <F>;
   close(F) or return("can't close outfile $outfile: $!");
   unlink $outfile;

   return $err if (defined $err && $err ne '' && $err !~ m/^\s+$/s);
   return $out;
}

1;
