package ow::tnef;
use strict;
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
require "modules/tool.pl";
require "modules/suid.pl";

sub get_tnef_filelist {
   my ($tnefbin, $r_tnef)=@_;
   my @filelist=();
   my $tmpfile=ow::tool::tmpname('tnef.tmpfile');

   # ensure tmpfile is owned by current euid but wll be writeable for forked pipe
   open(F, ">$tmpfile"); close(F); chmod(0666, $tmpfile);

   # the pipe forked by shell may use ruid/rgid(bash) or euid/egid(sh, tcsh)
   # since that won't change the result, so we don't use fork to change ruid/rgid
   open(F, "|$tnefbin -t > $tmpfile"); print F ${$r_tnef}; close(F);

   open(F, $tmpfile); unlink $tmpfile;
   while (<F>) { chomp; push(@filelist, $_) if ($_ ne ''); }
   close(F);

   return(@filelist);
}

sub get_tnef_archive {
   my ($tnefbin, $tnefname, $r_tnef)=@_;
   my ($arcname, $arcdata);
   my @filelist=();
   my $tmpdir=ow::tool::tmpname('tnef.tmpdir');

   if ($<!=$> && $<!=0) {
      local $SIG{CHLD}; undef $SIG{CHLD};  # disable $SIG{CHLD} temporarily for wait()
      local $|=1; # flush all output

      if (fork()==0) {
         close(STDIN); close(STDOUT); close(STDERR);
         # drop ruid/rgid to guarentee child ruid=euid=current euid, rgid=egid=current gid
         # thus dir/files created by child will be owned by current euid/egid
         ow::suid::drop_ruid_rgid();
         _extract_files_from_tnef($tnefbin, $r_tnef, $tmpdir);
         exit 0;
      }
      wait;
   } else {
      _extract_files_from_tnef($tnefbin, $r_tnef, $tmpdir);
   }

   opendir(T, $tmpdir);
   while (defined($_=readdir(T))) {
      push(@filelist, $_) if ($_ ne '.' && $_ ne '..');
   }
   close(T);
   if ($#filelist<0) {
      return('', \$arcdata);
   } elsif ($#filelist==0) {
      open(F, "$tmpdir/$filelist[0]"); $arcname=$filelist[0];
   } else {
      my ($zipbin, $tarbin, $gzipbin);
      $arcname=$tnefname; $arcname=~s/\.[\w\d]{0,4}$//;
      if (($zipbin=ow::tool::findbin('zip')) ne '') {
         open(F, "$zipbin -ryqj - $tmpdir|"); $arcname.=".zip";
      } elsif (($tarbin=ow::tool::findbin('tar')) ne '') {
         if (($gzipbin=ow::tool::findbin('gzip')) ne '') {
            open(F, "$tarbin -C $tmpdir -cf - .|$gzipbin -q -|"); $arcname.=".tgz";
         } else {
            open(F, "$tarbin -C $tmpdir -cf - .|"); $arcname.=".tar";
         }
      } else {
         return('', \$arcdata);
      }
   }
   local $/; undef $/; $arcdata=<F>;
   close(F);

   my $rmbin=ow::tool::findbin('rm');
   # cmd passed as array, so no shell in used, thus the rm is using current euid/egid
   system($rmbin, '-Rf', $tmpdir) if ($rmbin ne '');

   return($arcname, \$arcdata, @filelist);
}
sub _extract_files_from_tnef {
   my ($tnefbin, $r_tnef, $tmpdir)=@_;

   # set umask so the dir/file created by tnefbin will be readable
   # by uid/gid other than current euid/egid
   # (eg: if the shell is bash and current ruid!=0, the following froked
   #      tar/gzip may have ruid=euid=current ruid,
   #      which is not the same as current euid)
   my $oldumask=umask(0000);

   mkdir ($tmpdir, 0755);
   open(F, "|$tnefbin --overwrite -C $tmpdir"); print F ${$r_tnef}; close(F);

   umask($oldumask);
}

1;
