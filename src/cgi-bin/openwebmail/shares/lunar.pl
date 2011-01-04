
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

# lunar.pl - convert solar calendar to chinese lunar calendar

use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);

use vars qw(%config);

sub mkdb_lunar {
   # -1: cannot open db
   # -2: cannot open file
   my $lunardb = ow::tool::untaint("$config{ow_mapsdir}/lunar");

   my %LUNAR = ();

   if (!ow::dbm::opendb(\%LUNAR, $lunardb, LOCK_EX, 0644)) {
      writelog("cannot open db $lunardb");
      return -1;
   }

   if (!sysopen(T, $config{lunar_map}, O_RDONLY)) {
      writelog("cannot open file $config{lunar_map} ($!)");
      return -2;
   }

   $_ = <T>; # skip first line

   while (my $line = <T>) {
      $line =~ s/\s//g;
      my @a = split(/,/, $line, 2);
      $LUNAR{$a[0]} = $a[1];
   }

   close(T) or writelog("cannot close file $config{lunar_map} ($!)");

   ow::dbm::closedb(\%LUNAR, $lunardb) or writelog("cannot close db $lunardb");

   return 0;
}

sub solar2lunar {
   my ($year, $mon, $day) = @_;

   my $lunardb = ow::tool::untaint("$config{ow_mapsdir}/lunar");

   if (ow::dbm::existdb($lunardb)) {
      my %LUNAR = {};

      my $date  = sprintf("%04d%02d%02d", $year, $mon, $day);

      ow::dbm::opendb(\%LUNAR, $lunardb, LOCK_SH) or writelog("cannot open db $lunardb");

      my ($lunaryear, $lunarmonth, $lunarday) = split(/,/, $LUNAR{$date});

      ow::dbm::closedb(\%LUNAR, $lunardb) or writelog("cannot close db $lunardb");

      return ($lunaryear, $lunarmonth, $lunarday);
   } else {
      writelog("db $lunardb does not exist");
      return undef;
   }
}

1;
