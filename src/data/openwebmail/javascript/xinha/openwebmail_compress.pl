#!/usr/bin/perl

# This script invokes the yuicompressor.2.4.2.jar file via java in order to
# miniturize the javascript source code of xinha, making it download to browsers
# and execute much more quickly

use strict;
use warnings;
use File::Find;

my $yui_jar = "$ENV{PWD}/contrib/yuicompressor-2.4.2.jar";
die "The YUI compressor jar is not available" unless -f $yui_jar;

print "Compressing Xinha javascript...";

find(
     {
      # $File::Find::dir is the current directory name,
      # $_ is the current filename within that directory
      # $File::Find::name is the complete pathname to the file.
      wanted => sub {
                       if (
                             -f
                             && m/\.js$/
                             && $File::Find::name !~ m#/(?:\.svn|lang|abbr|HtmlEntities)/#
                          ) {
                          if (system("java -jar $yui_jar --charset UTF-8 " . quotemeta($_) . " -o " . quotemeta($_)) == 0) {
                             print ".";
                          } else {
                             print "error: $File::Find::name failed to compress ($! $?)\n";
                          }
                       }
                    },
      follow => 1,
     },

     # root path to search from
     "./",
    );

print "done\n";

