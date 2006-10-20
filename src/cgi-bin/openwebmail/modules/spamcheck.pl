package ow::spamcheck;
#
# spamcheck.pl - routines to call external checker to detect spam
#
# 2004/07/01 tung.AT.turtle.ee.ncku.edu.tw
#

use strict;
use Fcntl qw(:DEFAULT :flock);
use IO::Socket;
require "modules/tool.pl";
require "modules/suid.pl";

# sub scanmsg(pipecmd, msg_reference)
# ret (spamlevel, '');
#     (-99999, runtime error);
# sub learnspam(pipecmd, msg_reference)
# ret (learned, exxamed);
#     (-99999, runtime error);
# sub larnham(pipecmd, msg_reference)
# ret (learned, exxamed);
#     (-99999, runtime error);

#
# The following routines assume the spamassassin is used for the spamcheck.
# To make this work, you have to start up the spamd first,
# then set 'enable_spamcheck yes' in the openwbemail.conf
# To speedup the spamcheck, it is recommended to use -L or --local options
# when you startup the spamd daemon, or user may encounter noticeable delay
# in message access
#

use vars qw (%spamcerr);
%spamcerr= (
   64 => "command line usage error",
   65 => "data format error",
   66 => "cannot open input",
   67 => "addressee unknown",
   68 => "host name unknown",
   69 => "service unavailable",
   70 => "internal software error",
   71 => "system error (e.g., can't fork)",
   72 => "critical OS file missing",
   73 => "can't create (user) output file",
   74 => "input/output error",
   75 => "temp failure; user is invited to retry",
   76 => "remote error in protocol",
   77 => "permission denied",
   78 => "configuration error",
);

# cmd:    /usr/local/bin/spamc -c -x -t60
# output: 212.8/5
sub scanmsg {
   my $ret=pipecmd_msg(@_);
   $ret =~ s/[\r\n]//g;

   # spamc exit with spam level
   return ($1, '') if ($ret=~m!([\+\-]?[\d\.]+)/([\d+\.])! && $2!=0);

   # determine runtime error
   my $exit=$?&255;
   return(-99999, "spamc error, exit=$exit, ret=$ret, spamcerr=$spamcerr{$exit}") if (defined $spamcerr{$exit});
   return(-99999, "spamd error, exit=$exit, ret=$ret");
}

# cmd:    /usr/local/bin/sa-learn --local --spam
# output: Learned from 1 message(s) (1 message(s) examined).
sub learnspam {
   my $ret=pipecmd_msg(@_);
   $ret =~ s/[\r\n]//g;
   return (-99999, $ret) if ($ret!~/(\d+) message.*?(\d+) message/);
   return($1, $2);
}

# cmd:    /usr/local/bin/sa-learn --local --ham
# output: Learned from 1 message(s) (1 message(s) examined).
sub learnham {
   my $ret=pipecmd_msg(@_);
   $ret =~ s/[\r\n]//g;
   return (-99999, $ret) if ($ret!~/(\d+) message.*?(\d+) message/);
   return($1, $2);
}

# common routine, ret pipe output #########################################
sub pipecmd_msg {
   # refer to perlopentut and perlipc for more information.
   my ($pipecmd, $r_message)=@_;

   my $username=getpwuid($>);	# username of euid
   $pipecmd=~s/\@\@\@USERNAME\@\@\@/$username/g;

   my ($outfh, $outfile)=ow::tool::mktmpfile('spamcheck.out');
   my ($errfh, $errfile)=ow::tool::mktmpfile('spamcheck.err');

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
   close(P) or return("pipe broke - check connection to spamd - status: $?");

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
