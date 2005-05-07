package ow::tnef;
#
# tnef.pl - tnef -> zip/tar/tgz transformation routine
#
# 2004/07/18 tung.AT.turtle.ee.ncku.edu.tw
#
# tnef (Transport Neutral Encapsulation Format) is used mostly by
# Microsoft Outlook and Exchange server
#
# This module requires the tnef program to be passed as $tnefbin
# tnef program is available at http://tnef.sourceforge.net/,
# it is written by Mark Simpson <verdammelt@users.sourceforge.net>
#

use strict;
use Fcntl qw(:DEFAULT :flock);
require "modules/tool.pl";
require "modules/suid.pl";

sub get_tnef_filelist {
   my ($tnefbin, $r_tnef)=@_;

   local $SIG{CHLD}; undef $SIG{CHLD};  # disable $SIG{CHLD} temporarily for wait()
   local $|=1; # flush all output

   my ($outfh, $outfile)=ow::tool::mktmpfile('tnef.out');
   open(F, "|-") or
      do { open(STDERR,">/dev/null"); open(STDOUT,">&=".fileno($outfh)); exec($tnefbin, "-t"); exit 9 };
   close($outfh);
   print F ${$r_tnef};
   close(F);

   my @filelist=();
   sysopen(F, $outfile, O_RDONLY); unlink $outfile;
   while (<F>) { chomp; push(@filelist, $_) if ($_ ne ''); }
   close(F);

   return(@filelist);
}

sub get_tnef_archive {
   my ($tnefbin, $tnefname, $r_tnef)=@_;
   my ($arcname, $arcdata);

   local $SIG{CHLD}; undef $SIG{CHLD};  # disable $SIG{CHLD} temporarily for wait()
   local $|=1; # flush all output

   # set umask so the dir/file created by tnefbin will be readable
   # by uid/gid other than current euid/egid
   # (eg: if the shell is bash and current ruid!=0, the following froked
   #      tar/gzip may have ruid=euid=current ruid,
   #      which is not the same as current euid)
   my $oldumask=umask(0000);
   my $tmpdir=ow::tool::mktmpdir('tnef.tmp');
   return('', \$arcdata) if ($tmpdir eq '');

   open(F, "|-") or
      do { open(STDERR,">/dev/null"); open(STDOUT,">/dev/null"); exec($tnefbin, "--overwrite", "-C", $tmpdir); exit 9 };
   print F ${$r_tnef};
   close(F);
   umask($oldumask);

   my @filelist=();
   opendir(T, $tmpdir);
   while (defined($_=readdir(T))) {
      push(@filelist, $_) if ($_ ne '.' && $_ ne '..');
   }
   close(T);

   if ($#filelist<0) {
      rmdir($tmpdir);
      return('', \$arcdata);
   } elsif ($#filelist==0) {
      sysopen(F, "$tmpdir/$filelist[0]", O_RDONLY); $arcname=$filelist[0];
   } else {
      my ($zipbin, $tarbin, $gzipbin);
      $arcname=$tnefname; $arcname=~s/\.[\w\d]{0,4}$//;
      if (($zipbin=ow::tool::findbin('zip')) ne '') {
         open(F, "-|") or
            do { open(STDERR,">/dev/null"); exec($zipbin, "-ryqj", "-", $tmpdir); exit 9 };
         $arcname.=".zip";
      } elsif (($tarbin=ow::tool::findbin('tar')) ne '') {
         if (($gzipbin=ow::tool::findbin('gzip')) ne '') {
            open(F, "-|") or
               do { open(STDERR,">/dev/null"); exec($tarbin, "-C", $tmpdir, "-zcf", "-", "."); exit 9 };
            $arcname.=".tgz";
         } else {
            open(F, "-|") or
               do { open(STDERR,">/dev/null"); exec($tarbin, "-C", $tmpdir, "-cf", "-", "."); exit 9 };
            $arcname.=".tar";
         }
      } else {
         rmdir($tmpdir);
         return('', \$arcdata);
      }
   }
   local $/; undef $/; $arcdata=<F>;
   close(F);

   my $rmbin=ow::tool::findbin('rm');
   system($rmbin, '-Rf', $tmpdir) if ($rmbin ne '');
   return($arcname, \$arcdata, @filelist);
}

1;
