#!/usr/bin/perl
#
# this uty removes the debug log line at the begining of all subroutine
# which were added by the debugadd.pl uty,
#

use strict;
if ($#ARGV<0) {
   print "debugdel file1 file2 ...\n";
   exit;
}

my $updatedfile=0;
my $totalremoval=0;
foreach my $script (@ARGV) {
   my $content='';
   my $removal=0;
   print "remove debug code from $script ...";
   open (F, $script);
   while (<F>) {
      my $line=$_;
      if ($line=~/^sub .*{\s*/) {
         $content.=$line;
         while ((my $nextline=<F>)) {
            if ($nextline !~ /^\s*ow::tool::log_time/) {
               $content.=$nextline; last;
            } else {
               $removal++;
            }
         }
      } else {
         $content.=$line;
      }
   }
   close(F);

   if ($removal) {
      if (open (F, ">$script")) {
         print F $content;
         close(F);
         $updatedfile++;
         $totalremoval+=$removal;
         print "$removal line removed\n";
      } else {
         print "update err!\n";
      }
   } else {
      print "\n";
   }
}

print "$updatedfile file updated (total $totalremoval line removed)\n";
