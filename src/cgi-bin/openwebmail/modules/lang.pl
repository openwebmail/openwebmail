package ow::lang;
#
# lang.pl - language tables and routines
#

use strict;
use vars qw(%charactersets %RTL);

# preferred MIME character sets as described in
# http://www.iana.org/assignments/character-sets
# http://www.w3.org/International/O-HTTP-charset
# http://en.wikipedia.org/wiki/Category:Character_sets
# no, this is not all charsets - its the most common ones
%charactersets = (    # OWM Locale      HTTP Name
   'BIG5'        => [ 'Big5',              'big5'],
   'CP1250'      => [ 'CP1250',    'windows-1250'],
   'CP1251'      => [ 'CP1251',    'windows-1251'],
   'CP1252'      => [ 'CP1252',    'windows-1252'],
   'CP1253'      => [ 'CP1253',    'windows-1253'],
   'CP1254'      => [ 'CP1254',    'windows-1254'],
   'CP1255'      => [ 'CP1255',    'windows-1255'],
   'CP1256'      => [ 'CP1256',    'windows-1256'],
   'CP1257'      => [ 'CP1257',    'windows-1257'],
   'CP1258'      => [ 'CP1258',    'windows-1258'],
   'EUCKR'       => [ 'eucKR',           'euc-kr'],
   'EUCJP'       => [ 'eucJP',           'euc-jp'],
   'GB2312'      => [ 'GB2312',          'gb2312'],
   'ISO88591'    => [ 'ISO8859-1',   'iso-8859-1'],
   'ISO88592'    => [ 'ISO8859-2',   'iso-8859-2'],
   'ISO88593'    => [ 'ISO8859-3',   'iso-8859-3'],
   'ISO88594'    => [ 'ISO8859-4',   'iso-8859-4'],
   'ISO88595'    => [ 'ISO8859-5',   'iso-8859-5'],
   'ISO88596'    => [ 'ISO8859-6',   'iso-8859-6'],
   'ISO88597'    => [ 'ISO8859-7',   'iso-8859-7'],
   'ISO88598'    => [ 'ISO8859-8',   'iso-8859-8'],
   'ISO88599'    => [ 'ISO8859-9',   'iso-8859-9'],
   'ISO885910'   => [ 'ISO8859-10', 'iso-8859-10'],
   'ISO885911'   => [ 'ISO8859-11', 'iso-8859-11'],
   'ISO885913'   => [ 'ISO8859-13', 'iso-8859-13'],
   'ISO885914'   => [ 'ISO8859-14', 'iso-8859-14'],
   'ISO885915'   => [ 'ISO8859-15', 'iso-8859-15'],
   'ISO885916'   => [ 'ISO8859-16', 'iso-8859-16'],
   'ISO2022KR'   => [ 'ISO2022-KR', 'iso-2022-kr'],
   'ISO2022JP'   => [ 'ISO2022-JP', 'iso-2022-jp'],
   'KOI7'        => [ 'KOI7',              'koi7'],
   'KOI8R'       => [ 'KOI8-R',          'koi8-r'],
   'KOI8U'       => [ 'KOI8-U',          'koi8-u'],
   'KSC5601'     => [ 'KSC5601',        'ksc5601'],
   'SHIFTJIS'    => [ 'Shift_JIS',    'shift_jis'],
   'TIS620'      => [ 'TIS-620',        'tis-620'],
   'USASCII'     => [ 'US-ASCII',      'us-ascii'],
   'UTF7'        => [ 'UTF-7',            'utf-7'],
   'UTF8'        => [ 'UTF-8',            'utf-8'],
   'UTF16'       => [ 'UTF-16',          'utf-16'],
   'UTF32'       => [ 'UTF-32',          'utf-32'],
   'WINDOWS1250' => [ 'CP1250',    'windows-1250'],
   'WINDOWS1251' => [ 'CP1251',    'windows-1251'],
   'WINDOWS1252' => [ 'CP1252',    'windows-1252'],
   'WINDOWS1253' => [ 'CP1253',    'windows-1253'],
   'WINDOWS1254' => [ 'CP1254',    'windows-1254'],
   'WINDOWS1255' => [ 'CP1255',    'windows-1255'],
   'WINDOWS1256' => [ 'CP1256',    'windows-1256'],
   'WINDOWS1257' => [ 'CP1257',    'windows-1257'],
   'WINDOWS1258' => [ 'CP1258',    'windows-1258'],
);

# Right-to-Left language table, used to switch direction of text and arrows
%RTL = (
   'ar_AE.CP1256'    => 1, # arabic
   'ar_AE.ISO8859-6' => 1,
   'ar_AE.UTF-8'     => 1,
   'he_IL.CP1255'    => 1, # hebrew
   'he_IL.UTF-8'     => 1,
   'ur_PK.UTF-8'     => 1, # urdu
);

sub charset_for_locale {
   my $charset = shift;
   if (defined $charset && $charset) {
      $charset =~ s/[-_\s]//sg;
      return 0 unless $charset;
      $charset = uc($charset);
      return $charactersets{$charset}->[0] if exists $charactersets{$charset};
   }
   return 0;
}

sub is_charset_supported {
   my $charset = uc shift;
   return 0 unless defined $charset && $charset;
   $charset =~ s/[-_\s]//sg;
   return exists $charactersets{$charset};
}

sub guess_browser_locale {
   my $available_locales = shift;

   # default to English US
   $ENV{HTTP_ACCEPT_LANGUAGE} = 'en_US'
     unless defined $ENV{HTTP_ACCEPT_LANGUAGE} && $ENV{HTTP_ACCEPT_LANGUAGE} =~ m#^[A-Za-z0-9-._*,;=\s]+$#gs;

   # default to UTF-8
   $ENV{HTTP_ACCEPT_CHARSET} = 'UTF-8'
     unless defined $ENV{HTTP_ACCEPT_CHARSET} && $ENV{HTTP_ACCEPT_CHARSET} =~ m#^[A-Za-z0-9-._*,;=\s]+$#gs;

   # Internet Explorer does not send HTTP_ACCEPT_CHARSET
   $ENV{HTTP_ACCEPT_CHARSET} = 'UTF-8'
     if defined $ENV{HTTP_USER_AGENT} && $ENV{HTTP_USER_AGENT} =~ m/MSIE/;

   foreach my $lang (parse_http_accept($ENV{HTTP_ACCEPT_LANGUAGE})) {
      next if $lang eq '*';
      $lang =~ s#^(..)#lc("$1_")#e; # ENUS -> en_US
      $lang =~ s#_$##;              # en_ -> en

      my %unique = ();
      my @available_matching_languages = grep { !$unique{$_}++ }  # eliminate duplicates
                                          map { m/^(.*?)\./; $1 } # only the en_US part
                                         grep { m/^$lang/ }       # only the matches to this lang
                                         sort keys %{$available_locales};

      foreach my $available_language (@available_matching_languages) {
         if ($ENV{HTTP_ACCEPT_CHARSET} =~ /UTF-8/i) {
            my $locale = "$available_language\.UTF-8";
            return $locale if (exists $available_locales->{$locale});
         }
         foreach my $charset (parse_http_accept($ENV{HTTP_ACCEPT_CHARSET})) {
            next if $charset eq '*';
            $charset = $charactersets{$charset}[0] if exists $charactersets{$charset}; # UTF8 -> UTF-8
            my $locale = "$available_language\.$charset";                              # en_US.UTF-8
            return $locale if (exists $available_locales->{$locale});
         }
      }

      # no http_accept_charset matches available locales for the desired language.
      # pick the first available locale that matches the desired language.
      if (defined $available_matching_languages[0]) {
         my $first_locale = (grep m/^$available_matching_languages[0]/, sort keys %{$available_locales})[0];
         return $first_locale if defined $first_locale;
      }
   }

   # we do not have any locale for the desired language - return en_US.UTF-8
   return 'en_US.UTF-8'
}

sub parse_http_accept {
   # parses HTTP_ACCEPT_CHARSET and HTTP_ACCEPT_LANGUAGES environment vars
   # returns as an array to the caller, sorted by the q setting
   my $string = shift;
   $string =~ s#[\s_-]##gs;
   return  map { $_->[0] }
          sort { $b->[1] <=> $a->[1] || $a->[0] cmp $b->[0] }
           map { m/([A-Za-z0-9*]+);(?:[Qq]=)?([\d.]+)/?[$1, $2]:[$_, 1] }
         split (/,/, uc($string));
}

sub localeinfo {
   # this sub is intended to parse already validated locale names
   my $locale = shift; # en_US.UTF-8
   my ($language, $country, $charset) = $locale =~ m/^(..)_(..)\.(.*)$/;
   my $charsetkey = uc($charset);
   $charsetkey =~ s#[_-]##g; # UTF8
   return (
            $language,                      # en
            $country,                       # US
            $charsetkey,                    # UTF8
            $charset,                       # UTF-8 (OWM Locale)
            $charactersets{$charsetkey}[1], # utf-8 (HTTP)
          );
}

1;

