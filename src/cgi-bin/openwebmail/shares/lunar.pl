#
# lunar.pl - convert solar calendar to chinese lunar calendar
#

#                              The BSD License
#
#  Copyright (c) 2009-2010, The OpenWebMail Project
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

use strict;
use vars qw(%config);
use Fcntl qw(:DEFAULT :flock);

sub mkdb_lunar {
   my %LUNAR;
   my $lunardb = ow::tool::untaint("$config{ow_mapsdir}/lunar");

   ow::dbm::open(\%LUNAR, $lunardb, LOCK_EX, 0644) or return -1;
   sysopen(T, $config{lunar_map}, O_RDONLY);
   $_ = <T>;
   while (<T>) {
      s/\s//g;
      my @a = split(/,/, $_, 2);
      $LUNAR{$a[0]} = $a[1];
   }
   close(T);
   ow::dbm::close(\%LUNAR, $lunardb);

   return 0;
}

sub solar2lunar {
   my ($year, $mon, $day) = @_;

   my $lunardb = ow::tool::untaint("$config{ow_mapsdir}/lunar");

   if (ow::dbm::exist($lunardb)) {
      my %LUNAR = {};
      my $date  = sprintf("%04d%02d%02d", $year, $mon, $day);

      ow::dbm::open(\%LUNAR, $lunardb, LOCK_SH);
      my ($lunaryear, $lunarmonth, $lunarday) = split(/,/, $LUNAR{$date});
      ow::dbm::close(\%LUNAR, $lunardb);

      return ($lunaryear, $lunarmonth, $lunarday);
   } else {
      return(); # return undef
   }
}

1;
