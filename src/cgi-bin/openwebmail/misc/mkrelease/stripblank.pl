if ($#ARGV <0 ) {
   print "$0 files_to_stripe\n";
   exit 1;
}

foreach my $file (@ARGV) {
   next if (!open(F, $file));
   next if ($file!~/\.(txt|htm|html|css|js|pl|php|doc|template|cf|conf|sh)$/i &&
            $file!~m!/lang/!);

   my @lines=();
   my $strip=0;
   while (<F>) {
      my $len=length($_);
      s/\s*$//;
      push(@lines, "$_\n");
      $strip=1 if (length($_)+1 != $len);
   }
   close(F);

   next if (!$strip || !open(F, ">$file"));
   foreach (@lines) {
      print F $_;
   }
   close(F);
   print "strip $file ok\n";
}

