push(@INC, '.');
require "etc/lang/en";

use vars qw(%match);
sub matchkey {
   $match{$_[0]}++;
}

foreach my $file (@ARGV) {
   undef $/;
   open(F, $file); my $data=<F>; close(F);

   $data=~s/lang_wdbutton\{["']?(.*?)["']?\}/matchkey($1)/igems;
   $data=~s/lang_text\{["']?(.*?)["']?\}/matchkey($1)/igems;
   $data=~s/lang_err\{["']?(.*?)["']?\}/matchkey($1)/igems;
}

my @k=sort { $match{$a} <=> $match{$b} } (keys %match);
foreach (@k) {
   if (!defined $ow::en::lang_err{$_} &&
       !defined $ow::en::lang_text{$_} &&
       !defined $ow::en::lang_wdbutton{$_}
      ) {
      print "$_ => $match{$_}\n";
   }
}

