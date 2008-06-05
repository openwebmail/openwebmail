package ow::spamcheck;
#
# spamcheck.pl - routines to call external checker to detect spam
#

use strict;
require "modules/tool.pl";
require "modules/suid.pl";

# sub scanmsg(pipecmd, msg_reference)
# ret (spamlevel, report);
#     (-99999, runtime error);
# sub learnspam(pipecmd, msg_reference)
# ret (learned, examend);
#     (-99999, runtime error);
# sub learnham(pipecmd, msg_reference)
# ret (learned, examend);
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

# cmd:    /usr/local/bin/spamc -R -x -t60
# output: 212.8/5
sub scanmsg {
   my $ret = pipecmd_msg(@_);

   # did spamc exit with spam level like 16.4/5.0 or 0.0/5.0?
   if ($ret =~ m#^([+-])?([\d.]+)/([\d.]+)#) {
      my $prefix    = defined $1?$1:'+';
      my $spamscore = $prefix eq '-'?"-$2":$2;
      my $threshold = $3; # not same as $prefs{'spamcheck_threshold'} !!!
      my ($report)  = $ret =~ m#^[+-]?[\d.]+/[\d.]+\s+(.*)#gs;
      return($spamscore, $report) unless ($spamscore == 0 && $threshold == 0);
   }

   # ret is an error past this point
   $ret =~ s/[\n\r]+/ /gs;
   $ret =~ s/\s+$//gs;
   $ret =~ s/^\s+//gs;

   # determine runtime error
   my $exit = $? & 255;
   return (-99999, "spamc error, exit=$exit, ret=$ret, spamcerr=$spamcerr{$exit}") if (exists $spamcerr{$exit});
   return (-99999, "spamc forked but then failed, check if spamd is running, exit=$exit, ret=$ret") if ($ret eq '0/0');
   return (-99999, "spamc unknown error, exit=$exit, ret=$ret");
}

# cmd:    /usr/local/bin/sa-learn --local --spam
# output: Learned from 1 message(s) (1 message(s) examined).
sub learnspam {
   my $ret = pipecmd_msg(@_);
   return (-99999, $ret) if ($ret!~/(\d+) message.*?(\d+) message/s);
   return($1, $2);
}

# cmd:    /usr/local/bin/sa-learn --local --ham
# output: Learned from 1 message(s) (1 message(s) examined).
sub learnham {
   my $ret = pipecmd_msg(@_);
   return (-99999, $ret) if ($ret!~/(\d+) message.*?(\d+) message/s);
   return($1, $2);
}

# common routine, ret pipe output #########################################
sub pipecmd_msg {
   my ($pipecmd, $r_message) = @_;

   my $username = getpwuid($>); # username of euid

   $pipecmd = ow::tool::untaint($pipecmd);
   $pipecmd =~ s/\@\@\@USERNAME\@\@\@/$username/g;

   my ($outfh, $outfile) = ow::tool::mktmpfile('spamcheck.out');
   my ($errfh, $errfile) = ow::tool::mktmpfile('spamcheck.err');

   # STDIN gets closed if this is not a separate sub for some unknown reason
   my $pipeerror = _pipecmd_msg($pipecmd, $r_message, $outfile, $errfile);
   return $pipeerror if $pipeerror;

   # slurp in all the output
   local $/ = undef;

   my $stderr=<$errfh>;
   close($errfh) || return("could not close the stderrfile $errfile: $!");

   my $stdout=<$outfh>;
   close($outfh) || return("could not close the stdoutfile $outfile: $!");

   unlink $errfile;
   unlink $outfile;

   foreach ($stderr, $stdout) {
      return $_ if (defined $_ && $_ =~ m#\S#g);
   }
}

sub _pipecmd_msg {
   my ($pipecmd, $r_message, $outfile, $errfile) = @_;
   open(P, "|$pipecmd 2>$errfile >$outfile") or return("pipecmd open failed: $!");
   if (ref($r_message) eq 'ARRAY') {
      print P @{$r_message} or return("print array to pipe failed: $!\n");
   } else {
      print P ${$r_message} or return("print string to pipe failed: $!\n");
   }
   # this close fails because spamc exits immediately, so do not check for error
   close(P);
   return 0;
}

1;
