#!/usr/bin/perl
#
# this uty adds debug log line at the begining of all subroutine,
# so calling of each routine will be logged into /tmp/openwebmail.debug
#

use strict;
if ($#ARGV<0) {
   print "debugadd file1 file2 ...\n";
   exit;
}

my $updatedfile=0;
my $totalinsertion=0;
foreach my $script (@ARGV) {
   my $content='';
   my $insertion=0;
   my $package=0;
   print "add debug code to $script ...";
   open (F, $script);
   while (<F>) {
      my $line=$_;
      if ($line=~/^sub .*{\s*/ && $line!~/sub log_time/) {
         $content.=$line;
         my $debugline=$line;
         $debugline=~s/^sub //;
         $debugline=~s/\s*{.*$//g;
         chomp($debugline);
         $debugline=qq|ow::tool::log_time('$debugline :', \@_);\n|;
         $content.=$debugline;
         $insertion++;
      } elsif ($line=~/^package ow::/) {
         $package=1;
         $content.=$line;
      } else {
         $content.=$line;
      }
   }
   close(F);

   if ($package) {
      print "package skipped\n";
   } elsif ($insertion) {
      if (open (F, ">$script")) {
         print F $content;
         close(F);
         print "$insertion line added\n";
         $updatedfile++;
         $totalinsertion+=$insertion;
      } else {
         print "update err!\n";
      }
   } else {
      print "\n";
   }
}

print "$updatedfile file updated (total $totalinsertion line added)\n";
