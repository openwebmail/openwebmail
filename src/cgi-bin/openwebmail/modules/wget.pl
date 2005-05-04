package ow::wget;
#
# wget.pl - fetch url with wget, then return the filehandle of fetched object
#
# 2005/01/10 tung.AT.turtle.ee.ncku.edu.tw
#
# This module requires the wget program to be passed as $wgetbin
# wget program is available at http://www.gnu.org/software/wget/wget.html,
#

use strict;
use Fcntl qw(:DEFAULT :flock);
require "modules/tool.pl";

sub get_handle {
   my ($wgetbin, $url)=@_;

   my ($outfh, $outfile)=ow::tool::mktmpfile('wget.tmpfile');
   my ($errfh, $errfile)=ow::tool::mktmpfile('wget.err');

   open(SAVEERR,">&STDERR"); open(STDERR,">&=".fileno($errfh)); close($errfh);
   open(SAVEOUT,">&STDOUT"); open(STDOUT,">&=".fileno($outfh)); close($outfh);
   select(STDERR); $|=1; select(STDOUT); $|=1;

   local $SIG{CHLD}; undef $SIG{CHLD};  # disable $SIG{CHLD} temporarily for wait()
   system($wgetbin, "-l0", "-O-", ow::tool::untaint($url));

   open(STDERR,">&SAVEERR"); close(SAVEERR);
   open(STDOUT,">&SAVEOUT"); close(SAVEOUT);

   my $exit=$?>>8;
   if ( $exit!=0 && (-s $errfile)==0) {
      unlink($outfile, $errfile);
      return(-1, "fork error?");
   }

   my ($contenttype, $errmsg)=('', '');
   sysopen(ERR, $errfile, O_RDONLY);
   while (<ERR>) {
      $contenttype=$1 if (m!\d+ \[([a-z]+/[a-z\-]+)\]!);
      $errmsg=$_ if (/\S+/);
   }
   close(ERR);
   unlink($errfile);

   if ($exit!=0) {
      unlink($outfile);
      $errmsg=~s/^\d\d:\d\d:\d\d\s*//; $errmsg=~s/[\r\n]//g;
      return(-2, $errmsg);
   } else {
      my $handle=do { local *FH };
      sysopen($handle, $outfile, O_RDONLY);
      unlink($outfile);
      $contenttype=ow::tool::ext2contenttype($url) if ($contenttype eq '');
      return(0, '', $contenttype, $handle);
   }
}

1;
