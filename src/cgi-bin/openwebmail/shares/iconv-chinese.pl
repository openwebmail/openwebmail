
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

# iconv-chinese.pl - charset conversion between big5 <-> gb2312 charsets
# Since chinese conversion in iconv() is incomplete, we use this instead
# The table and code were adopted from Encode::HanConvert on CPAN

use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);

use vars qw(%config);

sub mkdb_b2g {
   # -1: cannot open db
   # -2: cannot open file
   my $b2gdb = ow::tool::untaint("$config{ow_mapsdir}/b2g");

   my %B2G = ();

   if (!ow::dbm::opendb(\%B2G, $b2gdb, LOCK_EX, 0644)) {
      writelog("cannot open db $b2gdb");
      return -1;
   }

   if (!sysopen(T, $config{b2g_map}, O_RDONLY)) {
      writelog("cannot open file $config{b2g_map} ($!)");
      return -2;
   }

   $_ = <T>; # skip first line
   $_ = <T>; # skip second line

   while (my $line = <T>) {
      $line =~ m/^(..)\s(..)/;
      $B2G{$1} = $2;
   }

   close(T) or writelog("cannot close file $config{b2g_map} ($!)");

   ow::dbm::closedb(\%B2G, $b2gdb) or writelog("cannot close db $b2gdb");

   return 0;
}

sub mkdb_g2b {
   # -1: cannot open db
   # -2: cannot open file
   my $g2bdb = ow::tool::untaint("$config{ow_mapsdir}/g2b");

   my %G2B = ();

   if (!ow::dbm::opendb(\%G2B, $g2bdb, LOCK_EX, 0644)) {
      writelog("cannot open db $g2bdb ($!)");
      return -1;
   }

   if (!sysopen(T, $config{g2b_map}, O_RDONLY)) {
      writelog("cannot open file $config{g2b_map} ($!)");
      return -2;
   }

   $_ = <T>; # skip first line
   $_ = <T>; # skip second line

   while (defined(my $line = <T>)) {
      next unless $line =~ m/^(..)\s(..)/;
      $G2B{$1} = $2;
   }

   close(T) or writelog("cannot close file $config{g2b_map} ($!)");

   ow::dbm::closedb(\%G2B, $g2bdb) or writelog("cannot close db $g2bdb");

   return 0;
}

sub b2g {
   # big5:       hi A1-F9,       lo 40-7E A1-FE (big5-1984, big5-eten, big5-cp950, big5-unicode)
   # big5-hkscs: hi 88-F9,       lo 40-7E A1-FE
   # big5E:      hi 81-8E A1-F9, lo 40-7E A1-FE
   # from http://i18n.linux.org.tw/li18nux/big5/doc/big5-intro.txt
   # use range of big5
   my $str = shift;

   my $b2gdb = ow::tool::untaint("$config{ow_mapsdir}/b2g");

   if (ow::dbm::existdb($b2gdb)) {
      my %B2G = ();

      ow::dbm::opendb(\%B2G, $b2gdb, LOCK_SH) or writelog("cannot open db $b2gdb");

      $str =~ s/([\xA1-\xF9][\x40-\x7E\xA1-\xFE])/$B2G{$1}/eg;

      ow::dbm::closedb(\%B2G, $b2gdb) or writelog("cannot close db $b2gdb");
   } else {
      writelog("db does not exist $b2gdb");
   }

   return $str;
}

sub g2b {
   # gb2312-1980: hi A1-F7, lo A1-FE, range hi*lo
   # gb12345    : hi A1-F9, lo A1-FE, range hi*lo
   # gbk        : hi 81-FE, lo 40-7E 80-FE, range hi*lo
   # from http://www.haiyan.com/steelk/navigator/ref/gbindex1.htm
   # use range of gb2312
   my $str = shift;

   my $g2bdb = ow::tool::untaint("$config{ow_mapsdir}/g2b");

   if (ow::dbm::existdb($g2bdb)) {
      my %G2B = ();

      ow::dbm::opendb(\%G2B, $g2bdb, LOCK_SH) or writelog("cannot open db $g2bdb");

      $str =~ s/([\xA1-\xF9][\xA1-\xFE])/$G2B{$1}/eg;

      ow::dbm::closedb(\%G2B, $g2bdb) or writelog("cannot close db $g2bdb");
   }

   return $str;
}

1;
