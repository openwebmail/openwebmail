#!/usr/bin/perl
#
# this uty adds prof log line at the begining of all subroutine,
# so calling of each routine will be logged into /tmp/openwebmail.debug
#

use strict;
if ($#ARGV<0) {
   print "profadd file1 file2 ...\n";
   exit;
}

my $updatedfile=0;
my $totalinsertion=0;
foreach my $script (@ARGV) {
   my $insertion=0;
   my $require=0;
   my $content='';
   my $profbeginline;
   my $profendline;

   print "add profile code to $script ...";
   open (F, $script);
   while (<F>) {
      my $line=$_;
      if ($line=~/^require "/ && !$require) {
         $require=1;
         $content.=qq|require "misc/test/gettimeofday.pl";\n|;
         $content.=qq|ow::tool::timeofday_init();\n|;
         $content.=$line;
         $insertion++;
      } elsif ($line=~/^sub\s*([^\s\{]+)/) {
         $content.=$line;
         my $subname=$1; chomp($subname);
         if ($subname ne "log_time") {
            $profbeginline=qq|ow::tool::log_time("PROF", ow::tool::timeofday_diff("$subname"), "CALL $subname()\\t", __LINE__, __FILE__, \@_);\n|;
            $profendline  =qq|ow::tool::log_time("PROF", ow::tool::timeofday_diff("$subname"), "END  $subname()\\t", __LINE__, __FILE__);\n|;
            $content.=$profbeginline;
            $insertion++;
         }
      } elsif ($line=~/^\s*return[\s\(;]?.*;/ && $line!~/ if / && $profendline) {
         $content.=$profendline;
         $content.=$line;
         $insertion++;
      } else {
         $content.=$line;
      }
   }
   close(F);

   if ($insertion) {
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
