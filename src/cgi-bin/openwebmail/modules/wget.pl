package ow::wget;
use strict;
#
# wget.pl - fetch url with wget, then return the filehandle of fetched object
#
# 2005/01/10 tung.AT.turtle.ee.ncku.edu.tw
#
# This module requires the wget program to be passed as $wgetbin
# wget program is available at http://www.gnu.org/software/wget/wget.html,
#
require "modules/tool.pl";
sub get_handle {
   my ($wgetbin, $url)=@_;

   my $datafile=ow::tool::tmpname('wget.tmpfile');
   my $errfile=ow::tool::tmpname('wget.err');
   open(ERR, ">$errfile"); close(ERR);

   my $wgetcmd=ow::tool::untaint("$wgetbin -l0 -O- -o$errfile $url");
   open (WGET, "$wgetcmd |") or
      return(-1, $!);
   open(F, ">$datafile");
   while (<WGET>) { print F $_ }
   close(F);
   close(WGET);

   my ($contenttype, $errmsg)=('', '');
   open(ERR, $errfile);
   while (<ERR>) {
      $contenttype=$1 if (m!\d+ \[([a-z]+/[a-z\-]+)\]!);
      $errmsg=$_ if (/\S+/);
   }
   close(ERR);
   unlink($errfile);

   if ($?!=0) {
      unlink($datafile);
      $errmsg=~s/^\d\d:\d\d:\d\d\s*//; $errmsg=~s/[\r\n]//g;
      return(-2, $errmsg);
   } else {
      my $handle=do { local *FH };
      open($handle, $datafile);
      unlink($datafile);
      $contenttype=ow::tool::ext2contenttype($url) if ($contenttype eq '');
      return(0, '', $contenttype, $handle);
   }
}

1;
