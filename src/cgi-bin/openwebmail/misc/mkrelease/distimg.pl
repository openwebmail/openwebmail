#!/usr/bin/perl
my $iconsetsdir="/usr/local/www/data/openwebmail/image/iconsets";

chdir($iconsetsdir);
opendir(D, $iconsetsdir);
my @files=readdir(D);
closedir(D);

my @defult;
my @cool3d;

foreach (@files) {
   next if (/^\./);
   push(@default, $_) if (/^Default\./ && $_!~/Chinese/ && $_!~/English/);
   push(@cool3d, $_)  if (/^Cool3D\./  && $_!~/Chinese/ && $_!~/English/);
}

foreach my $img (@ARGV) {
   foreach my $destdir (@default) {
      print `cp -v Default.English/$img $destdir/$img`;
   }
   print `cp -v Default.Chinese.Traditional/$img Default.Chinese.Simplified/$img`;

   foreach my $destdir (@cool3d) {
      print `cp -v Cool3D.English/$img $destdir/$img`;
   }
   print `cp -v Cool3D.Chinese.Traditional/$img Cool3D.Chinese.Simplified/$img`;
}
