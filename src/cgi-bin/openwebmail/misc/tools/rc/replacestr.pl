+#! /usr/bin/perl -w

### An uty to replace a string in all ~/mail/.openwebmailrc under specific directories

### Aendern von Einstellungen in der Benutzerkonfiguration ~/mail/openwebmailrc
### Thu Oct 17 13:42:16 MEST 2002
### 2002, "Michael 'Mike' Loth"  <mike@loth.de> (ML129)

use strict;
use File::Find;

my @dirs		= ('/var/home');
my $filepattern		= "\/\.openwebmail\/openwebmailrc\$";
my $replacepattern	= "iconset=Cool3D.German";
my $replacestring	= "iconset=Cool3D.Deutsch";

&find({wanted => \&FileFindWanted,
       follow => 1}, 
      @dirs);

print "done.\n\n";


sub FileFindWanted {

  my $line;

  my $file = $File::Find::name;

  if ($file =~ m#$filepattern#) {
    print "working on file ".$file." ...\n";
    my ($dev, $inode, $mode, $nlink, $uid, $gid) = lstat($file);
    my $tfile = $file."~";
    open(FD1, $file) || die "Can't open input file $file\n";
    open(FD2, ">".$tfile) || die "Can't open output file $tfile\n";
    while ($line = <FD1>) {
      $line =~ s#$replacepattern#$replacestring#;
      print FD2 $line;
    }
    close(FD2);
    close(FD1);
    unlink($file);
    rename($tfile, $file);
    chmod($mode, $file);            
    chown($uid, $gid, $file);
  }
}

### EOP
