#
# syntax: perl mergelang.pl translated_langfile_to_be_merged
#
# this script can merge specified lang file with the current one in system
# and output the merged result to stdout.
#

my $default_lang_dir="/usr/local/www/cgi-bin/openwebmail/etc/lang/";
my $langfile=$ARGV[0];
my $lang=$langfile; $lang=~s!.*/!!;

if ($ARGV[0] eq '') {
   print "syntax: perl mergelang.pl newly_translated_langfile\n";
   exit;
}

my %tran;
my $tranheader='';
my $hashname='';

open(T, $langfile);
while (<T>) {
   my $line=$_;
   my $key=$_; $key=~s/^\s*//; $key=~s/=.*$//; $key=~s/\s*$//;
   if ($key=~/^\%/) {
      $hashname=$key;
   } else {
      $tran{$hashname.$key}=$line if ($key ne '');
   }
   $tranheader.=$line if ($hashname eq '');	# keep new header in translated file
}
close(T);

print $tranheader;

$hashname='';
open(S, "$default_lang_dir/$lang");
while (<S>) {
   my $line=$_;
   my $key=$_; $key=~s/^\s*//; $key=~s/=.*$//; $key=~s/\s*$//;

   $hashname=$key if ($key=~/^\%/);
   next if ($hashname eq '');		# skip orig header

   if (defined $tran{$hashname.$key} ) {
      print $tran{$hashname.$key};
   } else {
      print $line;
   }
}
close(S);
