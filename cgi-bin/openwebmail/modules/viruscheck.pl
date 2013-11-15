package ow::viruscheck;
#
# viruscheck.pl - routines to call external checker to detect virus
#

use strict;
use warnings FATAL => 'all';

require "modules/tool.pl";

# sub scanmsg(pipecmd, msg_reference)
# ret (0, report): message is clean
#     (1, report, virusname): virus found
#     (-1, report): scanner has runtime error

#
# The following routines assume the clamav is used for the viruscheck.
# To make this work, you have to start up the clamd first,
# then set 'enable_viruscheck yes' in the openwebmail.conf
#

# cmd:    /usr/local/bin/clamdscan --mbox --disable-summary --stdout -
# output: stream: OK
#         stream: VirusName FOUND
sub scanmsg {
   my $ret = pipecmd_msg(@_);

   my $report = $ret;
   $report =~ s/[\n\r]+/ /gs;
   $report =~ s/\s+$//gs;
   $report =~ s/^\s+//gs;

   if ($ret =~ m#^stream: OK#) {
      return (0, $report);
   } elsif ($ret =~ m#^stream: (.*?) FOUND#sg) {
      my $virusname = $1;
      return (1, $report, $virusname);
   } else {
      return (-1, $report);
   }
}

# common routine, ret pipe output #########################################
sub pipecmd_msg {
   my ($pipecmd, $r_message) = @_;

   # username of euid
   my $username = getpwuid($>);

   $pipecmd = ow::tool::untaint($pipecmd);
   $pipecmd =~ s/\@\@\@USERNAME\@\@\@/$username/g;

   my ($outfh, $outfile) = ow::tool::mktmpfile('viruscheck.out');
   my ($errfh, $errfile) = ow::tool::mktmpfile('viruscheck.err');

   # STDIN gets closed if this is not a separate sub for some unknown reason
   my $pipeerror = _pipecmd_msg($pipecmd, $r_message, $outfile, $errfile);
   return $pipeerror if $pipeerror;

   # slurp in all the output
   local $/ = undef;

   my $stderr = <$errfh>;
   close($errfh) or return("could not close the stderrfile $errfile: $!");

   my $stdout = <$outfh>;
   close($outfh) or return("could not close the stdoutfile $outfile: $!");

   unlink $errfile;
   unlink $outfile;

   foreach ($stderr, $stdout) {
      return $_ if defined $_ && $_ =~ m#\S#g;
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

   # this close fails because clamdscan exits immediately, so do not check for error
   close(P);
   return 0;
}

1;
