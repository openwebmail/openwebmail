package ow::viruscheck;
use strict;
#
# viruscheck.pl - routines to call external checker to detect virus
#
# 2004/07/01 tung.AT.turtle.ee.ncku.edu.tw
#
use strict;
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
   my $username=getpwuid($>);	# username of euid
   my $pipecmd=ow::tool::untaint($_[0]); $pipecmd=~s/\@\@\@USERNAME\@\@\@/$username/g;
   my $r_message=$_[1]; # either sting ref or array ref may be used
   my $tmpfile=ow::tool::untaint("/tmp/.viruscheck.tmpfile.$$");

   # ensure tmpfile is owned by current euid but wll be writeable for forked pipe
   open(F, ">$tmpfile"); close(F); chmod(0666, $tmpfile);	

   # the pipe forked by shell may use ruid/rgid(bash) or euid/egid(sh, tcsh)
   # since that won't change the result, so we don't use fork to change ruid/rgid
   _pipecmd_msg($pipecmd, $r_message, $tmpfile);

   open(F, $tmpfile); $_=<F>; close(F); $_=~s/[\r\n]//g;
   unlink $tmpfile;

   return $_;
}

# result/err in tmpfile since result may be used by different process
sub _pipecmd_msg {
   my ($pipecmd, $r_message, $tmpfile)=@_;
   my $errmsg;
   if (open(P, "|$pipecmd 2>/dev/null > $tmpfile")) {
      if (ref($r_message) eq 'ARRAY') {
         print P @{$r_message} or $errmsg=$!;
      } else {
         print P ${$r_message} or $errmsg=$!;
      }
      close(P);
   } else {
      $errmsg=$!;
   }
   if ($errmsg ne '') {
      open(F, ">$tmpfile"); print F $errmsg; close(F);
   }
}

1;
