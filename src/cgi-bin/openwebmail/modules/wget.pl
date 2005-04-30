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

   my $datafile=ow::tool::tmpname('wget.tmpfile');
   my $errfile=ow::tool::tmpname('wget.err');
   sysopen(ERR, $errfile, O_WRONLY|O_TRUNC|O_CREAT); close(ERR);

   my $wgetcmd=ow::tool::untaint("$wgetbin -l0 -O- -o$errfile $url");

   my @cmd=($wgetbin, "-l0", "-O$datafile", "-o$errfile", $url);
   my ($stdout, $stderr, $exit, $sig)=ow::execute::execute(@cmd);
   return(-1, $stderr) if ($exit!=0 && !-f $errfile);	# fork err?

   my ($contenttype, $errmsg)=('', '');
   sysopen(ERR, $errfile, O_RDONLY);
   while (<ERR>) {
      $contenttype=$1 if (m!\d+ \[([a-z]+/[a-z\-]+)\]!);
      $errmsg=$_ if (/\S+/);
   }
   close(ERR);
   unlink($errfile);

   if ($exit!=0) {
      unlink($datafile);
      $errmsg=~s/^\d\d:\d\d:\d\d\s*//; $errmsg=~s/[\r\n]//g;
      return(-2, $errmsg);
   } else {
      my $handle=do { local *FH };
      sysopen($handle, $datafile, O_RDONLY);
      unlink($datafile);
      $contenttype=ow::tool::ext2contenttype($url) if ($contenttype eq '');
      return(0, '', $contenttype, $handle);
   }
}

1;
