#!/usr/bin/perl
#
# syntax: perl distimg.pl [gif1] [gif2]...
#
# this script make a shell script to be used to copy icons
#
# default.english             -> other default.*
# cool3d.english              -> other cool3d.*
# default.chinese.traditional -> default.chinese.simplified
# cool3d.chinese.traditional  -> cool3d.chinese.simplified
#
my $iconsetsdir="/usr/local/www/data/openwebmail/images/iconsets";
chdir($iconsetsdir);
opendir(D, $iconsetsdir);
my @files=readdir(D);
closedir(D);

my @defult;
my @cool3d;
my @misc;

foreach (@files) {
   next if (/^\./);
   push(@default, $_) if (/^Default\./ && $_!~/Chinese/ && $_!~/English/);
   push(@cool3d, $_)  if (/^Cool3D\./  && $_!~/Chinese/ && $_!~/English/);
   push(@misc, $_)  if (/^XP\./ || /^Adjunct\./);
}

foreach my $img (@ARGV) {
   foreach my $destdir (@misc) {
      print `cp -v Cool3D/$img $destdir/$img`;
   }

   foreach my $destdir (@default) {
      print `cp -v Default.English/$img $destdir/$img`;
   }

   foreach my $destdir (@cool3d) {
      print `cp -v Cool3D.English/$img $destdir/$img`;
   }
   print `cp -v Cool3D.Chinese.Traditional/$img Cool3D.Chinese.Simplified/$img`;
}
