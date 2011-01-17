
#                              The BSD License
#
#  Copyright (c) 2009-2011, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# statbook.pl - read/write stationery book

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);

require "modules/tool.pl";

sub read_stationerybook {
   # Read the stationery book file (assumes locking has been done elsewhere)
   my ($file, $r_stationery) = @_;

   my $ret    = 0;
   my $errmsg = '';

   # read openwebmail addressbook
   if (sysopen(STATBOOK, $file, O_RDONLY)) {
      while (my $line = <STATBOOK>) {
         chomp($line);
         my ($name, $content, $charset) = split(/\@\@\@/, $line, 3);
         $r_stationery->{$name}{content} = ow::tool::unescapeURL($content);
         $r_stationery->{$name}{charset} = $charset || '';
      }

      close(STATBOOK) or ($ret, $errmsg) = (-1, gettext('Cannot close file:') . " $file ($!)");
   } else {
      ($ret, $errmsg) = (-1, gettext('Cannot open file:') . " $file ($!)");
   }

   return ($ret, $errmsg);
}

sub write_stationerybook {
   # Write the stationery book file (assumes locking has been done elsewhere)
   my ($file, $r_stationery) = @_;

   my $ret    = 0;
   my $errmsg = '';
   my $lines  = '';

   # TODO: maybe this should be limited in size some day?
   foreach my $name (sort keys %$r_stationery) {
      my $content = ow::tool::escapeURL($r_stationery->{$name}{content});
      my $charset = $r_stationery->{$name}{charset};

      $name =~ s#\@\@#\@\@ #g;
      $name =~ s/\@$/\@ /;
      $lines .= "$name\@\@\@$content\@\@\@$charset\n";
   }

   if (sysopen(STATBOOK, $file, O_WRONLY|O_TRUNC|O_CREAT)) {
      print STATBOOK $lines;
      close(STATBOOK) or ($ret, $errmsg) = (-1, gettext('Cannot close file:') . " $file ($!)");
   } else {
      ($ret, $errmsg) = (-1, gettext('Cannot open file:') . " $file ($!)");
   }

   return ($ret, $errmsg);
}

1;
