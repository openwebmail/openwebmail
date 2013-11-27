
#                              The BSD License
#
#  Copyright (c) 2009-2013, The OpenWebMail Project
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

# iconv.pl - do charset conversions with system iconv() support

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);
use Text::Iconv;

require "modules/mime.pl";
require "shares/iconv-chinese.pl";
require "shares/iconv-japan.pl";

use vars qw(%config);
use vars qw(%charset_convlist %charset_equiv %charset_localname);
use vars qw($_iconv_handle $_iconv_tag);
use vars qw(%is_convertible_cache);
use vars qw(%localname_cache);

# mapping www charset to all possible iconv charset on various platforms
%charset_localname = (
                        'big5'          => [ 'BIG5', 'zh_TW-big5' ],
                        'euc-jp'        => [ 'EUC-JP', 'EUC', 'eucJP' ],
                        'euc-kr'        => [ 'EUC-KR', 'EUCKR' ],
                        'gb2312'        => [ 'GB2312', 'gb2312' ],
                        'iso-2022-jp'   => [ 'ISO-2022-JP', 'JIS' ],
                        'iso-2022-kr'   => [ 'ISO-2022-KR' ],
                        'iso-8859-1'    => [ 'ISO-8859-1', '8859-1', 'ISO8859-1', 'ISO_8859-1' ],
                        'iso-8859-2'    => [ 'ISO-8859-2', '8859-2', 'ISO8859-2', 'ISO_8859-2' ],
                        'iso-8859-3'    => [ 'ISO-8859-3', '8859-3', 'ISO8859-3', 'ISO_8859-3' ],
                        'iso-8859-4'    => [ 'ISO-8859-4', '8859-4', 'ISO8859-4', 'ISO_8859-4' ],
                        'iso-8859-5'    => [ 'ISO-8859-5', '8859-5', 'ISO8859-5', 'ISO_8859-5' ],
                        'iso-8859-6'    => [ 'ISO-8859-6', '8859-6', 'ISO8859-6', 'ISO_8859-6' ],
                        'iso-8859-7'    => [ 'ISO-8859-7', '8859-7', 'ISO8859-7', 'ISO_8859-7' ],
                        'iso-8859-8-i'  => [ 'ISO-8859-8', '8559-8', 'ISO8859-8', 'ISO_8859-8' ],
                        'iso-8859-9'    => [ 'ISO-8859-9', '8859-9', 'ISO8859-9', 'ISO_8859-9' ],
                        'iso-8859-10'   => [ 'ISO-8859-10', '8859-10', 'ISO8859-10', 'ISO_8859-10' ],
                        'iso-8859-11'   => [ 'ISO-8859-11', '8859-11', 'ISO8859-11', 'ISO_8859-11' ],
                        'iso-8859-13'   => [ 'ISO-8859-13', '8859-13', 'ISO8859-13', 'ISO_8859-13' ],
                        'iso-8859-14'   => [ 'ISO-8859-14', '8859-14', 'ISO8859-14', 'ISO_8859-14' ],
                        'iso-8859-15'   => [ 'ISO-8859-15', '8859-15', 'ISO8859-15', 'ISO_8859-15' ],
                        'iso-8859-16'   => [ 'ISO-8859-16', '8859-16', 'ISO8859-16', 'ISO_8859-16' ],
                        'koi8-r'        => [ 'KOI8-R' ],
                        'koi8-u'        => [ 'KOI8-U' ],
                        'ksc5601'       => [ 'KSC5601', 'KSC_5601', 'CP949' ],
                        'shift_jis'     => [ 'SJIS', 'SHIFT_JIS', 'SHIFT-JIS' ],
                        'tis620'        => [ 'TIS-620', 'TIS620', 'WINDOWS-874', 'CP874' ],
                        'utf-8'         => [ 'UTF-8', 'UTF8' ],
                        'windows-1250'  => [ 'WINDOWS-1250', 'CP1250' ],
                        'windows-1251'  => [ 'WINDOWS-1251', 'CP1251' ],
                        'windows-1252'  => [ 'WINDOWS-1252', 'CP1252' ],
                        'windows-1253'  => [ 'WINDOWS-1253', 'CP1253' ],
                        'windows-1254'  => [ 'WINDOWS-1254', 'CP1254' ],
                        'windows-1255'  => [ 'WINDOWS-1255', 'CP1255' ],
                        'windows-1256'  => [ 'WINDOWS-1256', 'CP1256' ],
                        'windows-1257'  => [ 'WINDOWS-1257', 'CP1257' ],
                        'windows-1258'  => [ 'WINDOWS-1258', 'CP1258' ],
                        'windows-874'   => [ 'WINDOWS-874', 'CP874', 'TIS-620', 'TIS620' ],
                     );


# convertible list of WWW charset, the definition is:
# charset in the left can be converted from the charsets in right list
%charset_convlist = (
                       'big5'          => [ 'utf-8', 'gb2312'],
                       'euc-jp'        => [ 'utf-8', 'iso-2022-jp', 'shift_jis' ],
                       'euc-kr'        => [ 'utf-8', 'ksc5601', 'iso-2022-kr' ],
                       'iso-2022-kr'   => [ 'utf-8', 'ksc5601', 'euc-kr' ],
                       'ksc5601'       => [ 'utf-8', 'euc-kr', 'iso-2022-kr' ],
                       'gb2312'        => [ 'utf-8', 'big5' ],
                       'iso-2022-jp'   => [ 'utf-8', 'shift_jis', 'euc-jp' ],
                       'iso-8859-1'    => [ 'utf-8', 'windows-1252' ],
                       'iso-8859-2'    => [ 'utf-8', 'windows-1250' ],
                       'iso-8859-3'    => [ 'utf-8', 'iso-8859-9', 'windows-1254' ],
                       'iso-8859-4'    => [ 'utf-8', 'iso-8859-10', 'windows-1254' ],
                       'iso-8859-5'    => [ 'utf-8', 'windows-1251', 'koi8-r' ],
                       'iso-8859-6'    => [ 'utf-8', 'windows-1256' ],
                       'iso-8859-7'    => [ 'utf-8', 'windows-1253' ],
                       'iso-8859-8-i'  => [ 'utf-8', 'windows-1255' ],
                       'iso-8859-9'    => [ 'utf-8', 'iso-8859-3', 'windows-1254' ],
                       'iso-8859-10'   => [ 'utf-8', 'iso-8859-4', 'windows-1254' ],
                       'iso-8859-11'   => [ 'utf-8' ],
                       'iso-8859-13'   => [ 'utf-8', 'windows-1257' ],
                       'iso-8859-14'   => [ 'utf-8' ],
                       'iso-8859-15'   => [ 'utf-8' ],
                       'iso-8859-16'   => [ 'utf-8' ],
                       'koi8-r'        => [ 'utf-8', 'windows-1251', 'iso-8859-5' ],
                       'koi8-u'        => [ 'utf-8' ],
                       'shift_jis'     => [ 'utf-8', 'iso-2022-jp', 'euc-jp' ],
                       'tis620'        => [ 'utf-8', 'windows-874' ],
                       'windows-1250'  => [ 'utf-8', 'iso-8859-2' ],
                       'windows-1251'  => [ 'utf-8', 'koi8-r', 'iso-8859-5' ],
                       'windows-1252'  => [ 'utf-8', 'iso-8859-1' ],
                       'windows-1253'  => [ 'utf-8', 'iso-8859-7' ],
                       'windows-1254'  => [ 'utf-8', 'iso-8859-9' ],
                       'windows-1255'  => [ 'utf-8', 'iso-8859-8-i' ],
                       'windows-1256'  => [ 'utf-8', 'iso-8859-6' ],
                       'windows-1257'  => [ 'utf-8', 'iso-8859-13' ],
                       'windows-1258'  => [ 'utf-8' ],
                       'windows-874'   => [ 'utf-8', 'tis620' ],
                       'utf-8'         => [
                                            'big5',
                                            'euc-jp',
                                            'euc-kr',
                                            'gb2312',
                                            'iso-2022-jp',
                                            'iso-2022-kr',
                                            'iso-8859-1',
                                            'iso-8859-2',
                                            'iso-8859-3',
                                            'iso-8859-4',
                                            'iso-8859-5',
                                            'iso-8859-6',
                                            'iso-8859-7',
                                            'iso-8859-8-i',
                                            'iso-8859-9',
                                            'iso-8859-10',
                                            'iso-8859-11',
                                            'iso-8859-13',
                                            'iso-8859-14',
                                            'iso-8859-15',
                                            'iso-8859-16',
                                            'koi8-r',
                                            'koi8-u',
                                            'ksc5601',
                                            'shift_jis',
                                            'tis620',
                                            'windows-1250',
                                            'windows-1251',
                                            'windows-1252',
                                            'windows-1253',
                                            'windows-1254',
                                            'windows-1255',
                                            'windows-1256',
                                            'windows-1257',
                                            'windows-1258',
                                            'windows-874'
                                          ]
                                );

# map old/unofficial charset name to official charset name
%charset_equiv = (
                    'big-5'          => 'big5',
                    'chinesebig5'    => 'big5',
                    'gbk'            => 'gb2312',
                    'iso-8859'       => 'iso-8859-1',
                    'us-ascii'       => 'iso-8859-1',
                    'ks_c_5601-1987' => 'ksc5601',
                    'utf8'           => 'utf-8'
                 );

%is_convertible_cache = (
                           'big5#gb2312' => 1,
                           'gb2312#big5' => 1,
                           'shift_jis#iso-2022-jp' => 1,
                           'iso-2022-jp#euc-jp' => 1,
                           'euc-jp#shift_jis' => 1
                        );

%localname_cache = ();

sub official_charset {
   my $charset = lc shift;
   return '' if !defined $charset || $charset eq '';
   $charset =~ s/iso_?8859/iso\-8859/;
   $charset = $charset_equiv{$charset} if exists $charset_equiv{$charset};
   return $charset;
}

sub is_convertible {
   my ($from, $to) = @_;

   $from = '' unless defined $from;
   $to   = '' unless defined $to;

   return 0 if $from eq '' || $to eq '';

   $from = official_charset($from);
   $to   = official_charset($to);

   return 0 if (
                  $from eq $to                        # not necessary
                  || !exists $charset_convlist{$to}   # unrecognized to charset
                  || !exists $charset_convlist{$from} # unrecognized from charset
               );

   return 1 if $from eq 'utf-8' || $to eq 'utf-8';    # utf8 is convertible with any charset

   if (!exists $is_convertible_cache{"$from#$to"}) {
      $is_convertible_cache{"$from#$to"} = 0;

      # try all possible from charset
      foreach my $charset (@{$charset_convlist{$to}}) {
         if ($from eq $charset) {
            if (my $converter = iconv_open($charset, $to)) {
               $is_convertible_cache{"$from#$to"} = 1;
            }

            last;
         }
      }
   }

   return $is_convertible_cache{"$from#$to"};
}

sub iconv {
   my ($from, $to, @text) = @_;

   return @text unless defined $from && defined $to && is_convertible($from, $to) && scalar @text > 0;

   $from = official_charset($from);
   $to   = official_charset($to);

   for (my $i = 0; $i <= $#text; $i++) {
      if (defined $text[$i]) {
         next if $text[$i] !~ m/[^\s]/;

         # try conversion routine in iconv-chinese, iconv-japan first
         if ($from  eq 'big5' && $to eq 'gb2312') {
            $text[$i] = b2g($text[$i]);
            next;
         } elsif ($from eq 'gb2312' && $to eq 'big5') {
            $text[$i] = g2b($text[$i]);
            next;
         } elsif ($from eq 'shift_jis' && $to eq 'iso-2022-jp') {
            sjis2jis(\$text[$i]);
            next;
         } elsif ($from eq 'iso-2022-jp' && $to eq 'shift_jis') {
            jis2sjis(\$text[$i]);
            next;
         } elsif ($from eq 'shift_jis' && $to eq 'euc-jp') {
            sjis2euc(\$text[$i]);
            next;
         } elsif ($from eq 'euc-jp' && $to eq 'shift_jis') {
            euc2sjis(\$text[$i]);
            next;
         } else {
            $text[$i] =~ s/(\S+)/_iconv($from, $to, $1)/egis;
         }
      }
   }

   return @text;
}

sub _iconv {
   # this routine tries to keep open the iconv handle to speedup repeated conversions
   my ($from, $to, $string) = @_;

   return $string unless defined $string and $string ne '';

   if (
         (!defined $_iconv_handle || $_iconv_handle eq '')
         || (!defined $_iconv_tag || $_iconv_tag ne "$from#$to")
      ) {
      $_iconv_handle = iconv_open($from, $to);
      $_iconv_tag = "$from#$to" if $_iconv_handle ne '';
   }

   return $string if !defined $_iconv_handle || $_iconv_handle eq ''; # no supported charset?

   my $converted = $_iconv_handle->convert($string);

   return $converted if defined $converted && $converted ne '';

   $_iconv_handle = ''; # terminate converter

   # add [charset?] error label at the beginning of text if convert failed
   return ($config{iconv_error_labels} ? "[" . uc($from) . "?]" . $string : $string);
}

sub iconv_open {
   my ($from, $to) = @_;

   return(Text::Iconv->new($localname_cache{$from}, $localname_cache{$to}))
      if defined $localname_cache{$from} && defined $localname_cache{$to};

   my $converter = '';

   foreach my $localfrom (@{$charset_localname{$from}}) {
      foreach my $localto (@{$charset_localname{$to}}) {
         eval {
                 no warnings 'all';
                 local $SIG{'__DIE__'};
                 $converter = Text::Iconv->new($localfrom, $localto)
              };
         next if $@;
         $localname_cache{$from} = $localfrom;
         $localname_cache{$to}   = $localto;
       	 return $converter;
      }
   }

   return '';
}

1;
