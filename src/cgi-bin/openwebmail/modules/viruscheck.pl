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
   my ($pipecmd, $r_message)=@_;

   my $username=getpwuid($>);	# username of euid
   $pipecmd=~s/\@\@\@USERNAME\@\@\@/$username/g;
   $pipecmd=ow::tool::untaint($pipecmd);

   # ensure tmpfile is owned by current euid but wll be writeable for forked pipe
   my $tmpfile=ow::tool::tmpname('viruscheck.tmpfile');
   open(F, ">$tmpfile"); close(F); chmod(0666, $tmpfile);

   local $SIG{CHLD}; undef $SIG{CHLD};  # disable $SIG{CHLD} temporarily for wait()
   local $|=1; # flush all output
   if (fork()==0) {
      close(STDIN); close(STDOUT); close(STDERR);
      # the pipe forked by shell may use ruid/rgid(bash) or euid/egid(sh, tcsh)
      # drop ruid/rgid to guarentee child ruid=euid=current euid, rgid=egid=current gid
      # thus dir/files created by child will be owned by current euid/egid
      ow::suid::drop_ruid_rgid();
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
      # result/err in tmpfile for parent process
      if ($errmsg ne '') {
         open(F, ">$tmpfile"); print F $errmsg; close(F);
      }
      exit 0;
   }
   wait;

   open(F, $tmpfile); $_=<F>; close(F); $_=~s/[\r\n]//g;
   unlink $tmpfile;

   return $_;
}

1;
