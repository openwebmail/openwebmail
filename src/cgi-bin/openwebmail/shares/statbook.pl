#
# statbook.pl - read/write stationery book
#

use strict;
use Fcntl qw(:DEFAULT :flock);
use vars qw(%lang_err);

########## READ_STATIONERYBOOK ######################################
# Read the stationery book file (assumes locking has been done elsewhere)
sub read_stationerybook {
   my ($file, $r_stationery)=@_;
   my ($ret, $errmsg)=(0, '');

   # read openwebmail addressbook
   if ( sysopen(STATBOOK, $file, O_RDONLY) ) {
      while (<STATBOOK>) {
         chomp();
         my ($name, $content, $charset) = split(/\@\@\@/, $_, 3);
         ${$r_stationery}{$name}{content} = ow::tool::unescapeURL($content);
         ${$r_stationery}{$name}{charset} = $charset||'';
      }
      close(STATBOOK) or  ($ret, $errmsg)=(-1, "$lang_err{'couldnt_close'} $file! ($!)");
   } else {
      ($ret, $errmsg)=(-1, "$lang_err{'couldnt_read'} $file! ($!)");
   }

   return ($ret, $errmsg);
}
########## END READ_STATIONERYBOOK ######################################

########## WRITE_STATIONERYBOOK ######################################
# Write the stationery book file (assumes locking has been done elsewhere)
sub write_stationerybook {
   my ($file, $r_stationery)=@_;
   my ($ret, $errmsg, $lines)=(0, '', '');

   # maybe this should be limited in size some day?
   foreach (sort keys %$r_stationery) {
      my $name=$_;
      my $content=ow::tool::escapeURL(${$r_stationery}{$name}{content});
      my $charset=${$r_stationery}{$name}{charset};

      $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
      $lines .= "$name\@\@\@$content\@\@\@$charset\n";
   }

   if ( sysopen(STATBOOK, $file, O_WRONLY|O_TRUNC|O_CREAT) ) {
      print STATBOOK $lines;
      close(STATBOOK) or  ($ret, $errmsg)=(-1, "$lang_err{'couldnt_close'} $file! ($!)");
   } else {
      ($ret, $errmsg)=(-1, "$lang_err{'couldnt_write'} $file! ($!)");
   }

   return ($ret, $errmsg);
}
########## END WRITE_STATIONERYBOOK ######################################

1;
