#!/usr/bin/perl
#
# find out proper settings for option dbm_ext and dbmopen_ext
#
mkdir ("/tmp/dbmtest.$$", 0755);
dbmopen(%DB, "/tmp/dbmtest.$$/test", 0600);
dbmclose(%DB);
opendir (TESTDIR, "/tmp/dbmtest.$$");
while (defined($filename = readdir(TESTDIR))) {
   if ($filename!~/^\./ ) {
      push(@filelist, $filename);
      unlink("/tmp/dbmtest.$$/$filename");
   }
}
closedir(TESTDIR);
rmdir("/tmp/dbmtest.$$");

@filelist=sort(@filelist);
if ($filelist[0]=~/\.(.*)/) {
   print qq|dbm_ext\t\t$1\n|.
         qq|dbmopen_ext\tnone\n|;
} else {
   print qq|dbm_ext\t\t.db\n|.
         qq|dbmopen_ext\t\%dbm_ext\%\n|;
}
