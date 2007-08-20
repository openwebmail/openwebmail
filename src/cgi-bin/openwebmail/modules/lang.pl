package ow::lang;
#
# lang.pl - language tables and routines
#

use strict;
use vars qw(%languagecodes %countrycodes %charactersets %RTL);

# LANGUAGE CODES
# derived from ISO-639-1 (updated 06/24/2006)
# http://www.loc.gov/standards/iso639-2/langcodes.html
%languagecodes = (
   'aa' => 'Afar',
   'ab' => 'Abkhazian',
   'ae' => 'Avestan',
   'af' => 'Afrikaans',
   'ak' => 'Akan',
   'am' => 'Amharic',
   'an' => 'Aragonese',
   'ar' => 'Arabic',
   'as' => 'Assamese',
   'av' => 'Avaric',
   'ay' => 'Aymara',
   'az' => 'Azerbaijani',
   'ba' => 'Bashkir',
   'be' => 'Belarusian',
   'bg' => 'Bulgarian',
   'bh' => 'Bihari',
   'bi' => 'Bislama',
   'bm' => 'Bambara',
   'bn' => 'Bengali',
   'bo' => 'Tibetan',
   'br' => 'Breton',
   'bs' => 'Bosnian',
   'ca' => 'Catalan',
   'ce' => 'Chechen',
   'ch' => 'Chamorro',
   'co' => 'Corsican',
   'cr' => 'Cree',
   'cs' => 'Czech',
   'cv' => 'Chuvash',
   'cy' => 'Welsh',
   'da' => 'Danish',
   'de' => 'German',
   'dv' => 'Divehi',
   'dz' => 'Dzongkha',
   'ee' => 'Ewe',
   'el' => 'Greek',
   'en' => 'English',
   'eo' => 'Esperanto',
   'es' => 'Spanish',
   'et' => 'Estonian',
   'eu' => 'Basque',
   'fa' => 'Persian',
   'ff' => 'Fulah',
   'fi' => 'Finnish',
   'fj' => 'Fijian',
   'fo' => 'Faroese',
   'fr' => 'French',
   'fy' => 'Western Frisian',
   'ga' => 'Irish',
   'gd' => 'Gaelic',
   'gl' => 'Galician',
   'gn' => 'Guarani',
   'gu' => 'Gujarati',
   'gv' => 'Manx',
   'ha' => 'Hausa',
   'he' => 'Hebrew',
   'hi' => 'Hindi',
   'ho' => 'Hiri Motu',
   'hr' => 'Croatian',
   'ht' => 'Haitian',
   'hu' => 'Hungarian',
   'hy' => 'Armenian',
   'hz' => 'Herero',
   'ia' => 'Interlingua',
   'id' => 'Indonesian',
   'ie' => 'Interlingue',
   'ig' => 'Igbo',
   'ii' => 'Sichuan Yi',
   'ik' => 'Inupiaq',
   'io' => 'Ido',
   'is' => 'Icelandic',
   'it' => 'Italian',
   'iu' => 'Inuktitut',
   'ja' => 'Japanese',
   'jv' => 'Javanese',
   'ka' => 'Georgian',
   'kg' => 'Kongo',
   'ki' => 'Kikuyu',
   'kj' => 'Kuanyama',
   'kk' => 'Kazakh',
   'kl' => 'Kalaallisut',
   'km' => 'Khmer',
   'kn' => 'Kannada',
   'ko' => 'Korean',
   'kr' => 'Kanuri',
   'ks' => 'Kashmiri',
   'ku' => 'Kurdish',
   'kv' => 'Komi',
   'kw' => 'Cornish',
   'ky' => 'Kirghiz',
   'la' => 'Latin',
   'lb' => 'Luxembourgish',
   'lg' => 'Ganda',
   'li' => 'Limburgan',
   'ln' => 'Lingala',
   'lo' => 'Lao',
   'lt' => 'Lithuanian',
   'lu' => 'Luba-Katanga',
   'lv' => 'Latvian',
   'mg' => 'Malagasy',
   'mh' => 'Marshallese',
   'mi' => 'Maori',
   'mk' => 'Macedonian',
   'ml' => 'Malayalam',
   'mn' => 'Mongolian',
   'mo' => 'Moldavian',
   'mr' => 'Marathi',
   'ms' => 'Malay',
   'mt' => 'Maltese',
   'my' => 'Burmese',
   'na' => 'Nauru',
   'nb' => 'Norwegian Bokmål',
   'nd' => 'Ndebele, North',
   'ne' => 'Nepali',
   'ng' => 'Ndonga',
   'nl' => 'Dutch',
   'nn' => 'Norwegian Nynorsk',
   'no' => 'Norwegian',
   'nr' => 'Ndebele, South',
   'nv' => 'Navajo',
   'ny' => 'Chichewa',
   'oc' => 'Occitan',
   'oj' => 'Ojibwa',
   'om' => 'Oromo',
   'or' => 'Oriya',
   'os' => 'Ossetian',
   'pa' => 'Panjabi',
   'pi' => 'Pali',
   'pl' => 'Polish',
   'ps' => 'Pushto',
   'pt' => 'Portuguese',
   'qu' => 'Quechua',
   'rm' => 'Raeto-Romance',
   'rn' => 'Rundi',
   'ro' => 'Romanian',
   'ru' => 'Russian',
   'rw' => 'Kinyarwanda',
   'sa' => 'Sanskrit',
   'sc' => 'Sardinian',
   'sd' => 'Sindhi',
   'se' => 'Northern Sami',
   'sg' => 'Sango',
   'si' => 'Sinhalese',
   'sk' => 'Slovak',
   'sl' => 'Slovenian',
   'sm' => 'Samoan',
   'sn' => 'Shona',
   'so' => 'Somali',
   'sq' => 'Albanian',
   'sr' => 'Serbian',
   'ss' => 'Swati',
   'st' => 'Sotho, Southern',
   'su' => 'Sundanese',
   'sv' => 'Swedish',
   'sw' => 'Swahili',
   'ta' => 'Tamil',
   'te' => 'Telugu',
   'tg' => 'Tajik',
   'th' => 'Thai',
   'ti' => 'Tigrinya',
   'tk' => 'Turkmen',
   'tl' => 'Tagalog',
   'tn' => 'Tswana',
   'to' => 'Tonga',
   'tr' => 'Turkish',
   'ts' => 'Tsonga',
   'tt' => 'Tatar',
   'tw' => 'Twi',
   'ty' => 'Tahitian',
   'ug' => 'Uighur',
   'uk' => 'Ukrainian',
   'ur' => 'Urdu',
   'uz' => 'Uzbek',
   've' => 'Venda',
   'vi' => 'Vietnamese',
   'vo' => 'Volapk',
   'wa' => 'Walloon',
   'wo' => 'Wolof',
   'xh' => 'Xhosa',
   'yi' => 'Yiddish',
   'yo' => 'Yoruba',
   'za' => 'Zhuang',
   'zh' => 'Chinese',
   'zu' => 'Zulu',
);

# COUNTRY CODES
# derived from ISO-3166-1 (updated 06/24/2006)
# http://www.iso.org/iso/en/prods-services/iso3166ma/02iso-3166-code-lists/list-en1.html
%countrycodes = (
   'AD' => 'Andorra',
   'AE' => 'United Arab Emirates',
   'AF' => 'Afghanistan',
   'AG' => 'Antigua and Barbuda',
   'AI' => 'Anguilla',
   'AL' => 'Albania',
   'AM' => 'Armenia',
   'AN' => 'Antilles',
   'AO' => 'Angola',
   'AQ' => 'Antarctica',
   'AR' => 'Argentina',
   'AS' => 'American Samoa',
   'AT' => 'Austria',
   'AU' => 'Australia',
   'AW' => 'Aruba',
   'AX' => 'Åland Islands',
   'AZ' => 'Azerbaijan',
   'BA' => 'Bosnia and Herzegovina',
   'BB' => 'Barbados',
   'BD' => 'Bangladesh',
   'BE' => 'Belgium',
   'BF' => 'Burkina Faso',
   'BG' => 'Bulgaria',
   'BH' => 'Bahrain',
   'BI' => 'Burundi',
   'BJ' => 'Benin',
   'BM' => 'Bermuda',
   'BN' => 'Brunei Darussalam',
   'BO' => 'Bolivia',
   'BR' => 'Brazil',
   'BS' => 'Bahamas',
   'BT' => 'Bhutan',
   'BV' => 'Bouvet Island',
   'BW' => 'Botswana',
   'BY' => 'Belarus',
   'BZ' => 'Belize',
   'CA' => 'Canada',
   'CC' => 'Cocos (Keeling) Islands',
   'CD' => 'Congo, The Democratic Republic Of The',
   'CF' => 'Central African Republic',
   'CG' => 'Congo',
   'CH' => 'Switzerland',
   'CI' => 'Côte D\'Ivoire',
   'CK' => 'Cook Islands',
   'CL' => 'Chile',
   'CM' => 'Cameroon',
   'CN' => 'China',
   'CO' => 'Colombia',
   'CR' => 'Costa Rica',
   'CS' => 'Serbia and Montenegro',
   'CU' => 'Cuba',
   'CV' => 'Cape Verde',
   'CX' => 'Christmas Island',
   'CY' => 'Cyprus',
   'CZ' => 'Czech Republic',
   'DE' => 'Germany',
   'DJ' => 'Djibouti',
   'DK' => 'Denmark',
   'DM' => 'Dominica',
   'DO' => 'Dominican Republic',
   'DZ' => 'Algeria',
   'EC' => 'Ecuador',
   'EE' => 'Estonia',
   'EG' => 'Egypt',
   'EH' => 'Western Sahara',
   'ER' => 'Eritrea',
   'ES' => 'Spain',
   'ET' => 'Ethiopia',
   'FI' => 'Finland',
   'FJ' => 'Fiji',
   'FK' => 'Falkland Islands (Malvinas)',
   'FM' => 'Micronesia, Federated States Of',
   'FO' => 'Faroe Islands',
   'FR' => 'France',
   'GA' => 'Gabon',
   'GB' => 'United Kingdom',
   'GD' => 'Grenada',
   'GE' => 'Georgia',
   'GF' => 'French Guiana',
   'GG' => 'Guernsey',
   'GH' => 'Ghana',
   'GI' => 'Gibraltar',
   'GL' => 'Greenland',
   'GM' => 'Gambia',
   'GN' => 'Guinea',
   'GP' => 'Guadeloupe',
   'GQ' => 'Equatorial Guinea',
   'GR' => 'Greece',
   'GS' => 'South Georgia and The South Sandwich Islands',
   'GT' => 'Guatemala',
   'GU' => 'Guam',
   'GW' => 'Guinea-Bissau',
   'GY' => 'Guyana',
   'HK' => 'Hong Kong',
   'HM' => 'Heard Island and McDonald Islands',
   'HN' => 'Honduras',
   'HR' => 'Croatia',
   'HT' => 'Haiti',
   'HU' => 'Hungary',
   'ID' => 'Indonesia',
   'IE' => 'Ireland',
   'IL' => 'Israel',
   'IM' => 'Isle Of Man',
   'IN' => 'India',
   'IO' => 'British Indian Ocean Territory',
   'IQ' => 'Iraq',
   'IR' => 'Iran',
   'IS' => 'Iceland',
   'IT' => 'Italy',
   'JE' => 'Jersey',
   'JM' => 'Jamaica',
   'JO' => 'Jordan',
   'JP' => 'Japan',
   'KE' => 'Kenya',
   'KG' => 'Kyrgyzstan',
   'KH' => 'Cambodia',
   'KI' => 'Kiribati',
   'KM' => 'Comoros',
   'KN' => 'Saint Kitts and Nevis',
   'KP' => 'Korea, Democratic People\'s Republic Of',
   'KR' => 'Korea',
   'KW' => 'Kuwait',
   'KY' => 'Cayman Islands',
   'KZ' => 'Kazakhstan',
   'LA' => 'Lao People\'s Democratic Republic',
   'LB' => 'Lebanon',
   'LC' => 'Saint Lucia',
   'LI' => 'Liechtenstein',
   'LK' => 'Sri Lanka',
   'LR' => 'Liberia',
   'LS' => 'Lesotho',
   'LT' => 'Lithuania',
   'LU' => 'Luxembourg',
   'LV' => 'Latvia',
   'LY' => 'Libyan Arab Jamahiriya',
   'MA' => 'Morocco',
   'MC' => 'Monaco',
   'MD' => 'Moldova',
   'MG' => 'Madagascar',
   'MH' => 'Marshall Islands',
   'MK' => 'Macedonia',
   'ML' => 'Mali',
   'MM' => 'Myanmar',
   'MN' => 'Mongolia',
   'MO' => 'Macao',
   'MP' => 'Northern Mariana Islands',
   'MQ' => 'Martinique',
   'MR' => 'Mauritania',
   'MS' => 'Montserrat',
   'MT' => 'Malta',
   'MU' => 'Mauritius',
   'MV' => 'Maldives',
   'MW' => 'Malawi',
   'MX' => 'Mexico',
   'MY' => 'Malaysia',
   'MZ' => 'Mozambique',
   'NA' => 'Namibia',
   'NC' => 'New Caledonia',
   'NE' => 'Niger',
   'NF' => 'Norfolk Island',
   'NG' => 'Nigeria',
   'NI' => 'Nicaragua',
   'NL' => 'Netherlands',
   'NO' => 'Norway',
   'NP' => 'Nepal',
   'NR' => 'Nauru',
   'NU' => 'Niue',
   'NZ' => 'New Zealand',
   'OM' => 'Oman',
   'PA' => 'Panama',
   'PE' => 'Peru',
   'PF' => 'French Polynesia',
   'PG' => 'Papua New Guinea',
   'PH' => 'Philippines',
   'PK' => 'Pakistan',
   'PL' => 'Poland',
   'PM' => 'Saint Pierre and Miquelon',
   'PN' => 'Pitcairn',
   'PR' => 'Puerto Rico',
   'PS' => 'Palestinian Territory, Occupied',
   'PT' => 'Portugal',
   'PW' => 'Palau',
   'PY' => 'Paraguay',
   'QA' => 'Qatar',
   'RE' => 'Réunion',
   'RO' => 'Romania',
   'RU' => 'Russian Federation',
   'RW' => 'Rwanda',
   'SA' => 'Saudi Arabia',
   'SB' => 'Solomon Islands',
   'SC' => 'Seychelles',
   'SD' => 'Sudan',
   'SE' => 'Sweden',
   'SG' => 'Singapore',
   'SH' => 'Saint Helena',
   'SI' => 'Slovenia',
   'SJ' => 'Svalbard and Jan Mayen',
   'SK' => 'Slovakia',
   'SL' => 'Sierra Leone',
   'SM' => 'San Marino',
   'SN' => 'Senegal',
   'SO' => 'Somalia',
   'SR' => 'Suriname',
   'ST' => 'Sao Tome and Principe',
   'SV' => 'El Salvador',
   'SY' => 'Syrian Arab Republic',
   'SZ' => 'Swaziland',
   'TC' => 'Turks and Caicos Islands',
   'TD' => 'Chad',
   'TF' => 'French Southern Territories',
   'TG' => 'Togo',
   'TH' => 'Thailand',
   'TJ' => 'Tajikistan',
   'TK' => 'Tokelau',
   'TL' => 'Timor-Leste',
   'TM' => 'Turkmenistan',
   'TN' => 'Tunisia',
   'TO' => 'Tonga',
   'TR' => 'Turkey',
   'TT' => 'Trinidad and Tobago',
   'TV' => 'Tuvalu',
   'TW' => 'Taiwan',
   'TZ' => 'Tanzania',
   'UA' => 'Ukraine',
   'UG' => 'Uganda',
   'UM' => 'United States Minor Outlying Islands',
   'US' => 'United States',
   'UY' => 'Uruguay',
   'UZ' => 'Uzbekistan',
   'VA' => 'Vatican City State',
   'VC' => 'Saint Vincent and The Grenadines',
   'VE' => 'Venezuela',
   'VG' => 'Virgin Islands, British',
   'VI' => 'Virgin Islands, U.S.',
   'VN' => 'Viet Nam',
   'VU' => 'Vanuatu',
   'WF' => 'Wallis and Futuna',
   'WS' => 'Samoa',
   'YE' => 'Yemen',
   'YT' => 'Mayotte',
   'ZA' => 'South Africa',
   'ZM' => 'Zambia',
   'ZW' => 'Zimbabwe',
);

# preferred MIME character sets as described in
# http://www.iana.org/assignments/character-sets
# http://www.w3.org/International/O-HTTP-charset
# http://en.wikipedia.org/wiki/Category:Character_sets
# no, this is not all charsets - its the most common ones
%charactersets = ( # OWM Locale      HTTP Name
   'BIG5'      => [ 'Big5',              'big5'],
   'CP1250'    => [ 'CP1250',    'windows-1250'],
   'CP1251'    => [ 'CP1251',    'windows-1251'],
   'CP1252'    => [ 'CP1252',    'windows-1252'],
   'CP1253'    => [ 'CP1253',    'windows-1253'],
   'CP1254'    => [ 'CP1254',    'windows-1254'],
   'CP1255'    => [ 'CP1255',    'windows-1255'],
   'CP1256'    => [ 'CP1256',    'windows-1256'],
   'CP1257'    => [ 'CP1257',    'windows-1257'],
   'CP1258'    => [ 'CP1258',    'windows-1258'],
   'EUCKR'     => [ 'eucKR',           'euc-kr'],
   'EUCJP'     => [ 'eucJP',           'euc-jp'],
   'GB2312'    => [ 'GB2312',          'gb2312'],
   'ISO88591'  => [ 'ISO8859-1',   'iso-8859-1'],
   'ISO88592'  => [ 'ISO8859-2',   'iso-8859-2'],
   'ISO88593'  => [ 'ISO8859-3',   'iso-8859-3'],
   'ISO88594'  => [ 'ISO8859-4',   'iso-8859-4'],
   'ISO88595'  => [ 'ISO8859-5',   'iso-8859-5'],
   'ISO88596'  => [ 'ISO8859-6',   'iso-8859-6'],
   'ISO88597'  => [ 'ISO8859-7',   'iso-8859-7'],
   'ISO88598'  => [ 'ISO8859-8',   'iso-8859-8'],
   'ISO88599'  => [ 'ISO8859-9',   'iso-8859-9'],
   'ISO885910' => [ 'ISO8859-10', 'iso-8859-10'],
   'ISO885911' => [ 'ISO8859-11', 'iso-8859-11'],
   'ISO885913' => [ 'ISO8859-13', 'iso-8859-13'],
   'ISO885914' => [ 'ISO8859-14', 'iso-8859-14'],
   'ISO885915' => [ 'ISO8859-15', 'iso-8859-15'],
   'ISO885916' => [ 'ISO8859-16', 'iso-8859-16'],
   'ISO2022KR' => [ 'ISO2022-KR', 'iso-2022-kr'],
   'ISO2022JP' => [ 'ISO2022-JP', 'iso-2022-jp'],
   'KOI7'      => [ 'KOI7',              'koi7'],
   'KOI8R'     => [ 'KOI8-R',          'koi8-r'],
   'KOI8U'     => [ 'KOI8-U',          'koi8-u'],
   'KSC5601'   => [ 'KSC5601',        'ksc5601'],
   'SHIFTJIS'  => [ 'Shift_JIS',    'shift_jis'],
   'TIS620'    => [ 'TIS-620',        'tis-620'],
   'USASCII'   => [ 'US-ASCII',      'us-ascii'],
   'UTF7'      => [ 'UTF-7',            'utf-7'],
   'UTF8'      => [ 'UTF-8',            'utf-8'],
   'UTF16'     => [ 'UTF-16',          'utf-16'],
   'UTF32'     => [ 'UTF-32',          'utf-32'],
   'WINDOWS1250' => [ 'CP1250',  'windows-1250'],
   'WINDOWS1251' => [ 'CP1251',  'windows-1251'],
   'WINDOWS1252' => [ 'CP1252',  'windows-1252'],
   'WINDOWS1253' => [ 'CP1253',  'windows-1253'],
   'WINDOWS1254' => [ 'CP1254',  'windows-1254'],
   'WINDOWS1255' => [ 'CP1255',  'windows-1255'],
   'WINDOWS1256' => [ 'CP1256',  'windows-1256'],
   'WINDOWS1257' => [ 'CP1257',  'windows-1257'],
   'WINDOWS1258' => [ 'CP1258',  'windows-1258'],
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

sub is_charset_supported {
   my $charset = uc($_[0]);
   $charset =~ s/[-_\s]//sg;
   return exists $charactersets{$charset};
}

sub guess_browser_locale {
   my $available_locales = $_[0];

   $ENV{HTTP_ACCEPT_LANGUAGE} = "en_US"
     unless defined $ENV{HTTP_ACCEPT_LANGUAGE} && $ENV{HTTP_ACCEPT_LANGUAGE} =~ m#^[A-Za-z0-9-._*,;=\s]+$#gs;

   $ENV{HTTP_ACCEPT_CHARSET} = "ISO8859-1"
     unless defined $ENV{HTTP_ACCEPT_CHARSET} && $ENV{HTTP_ACCEPT_CHARSET} =~ m#^[A-Za-z0-9-._*,;=\s]+$#gs;

   # Internet Explorer doesn't send HTTP_ACCEPT_CHARSET
   $ENV{HTTP_ACCEPT_CHARSET} = "UTF-8"
     if defined $ENV{HTTP_USER_AGENT} && $ENV{HTTP_USER_AGENT} =~ /MSIE/;

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
            $charset = $charactersets{$charset}[0] if exists $charactersets{$charset}; # ISO88591 -> ISO8859-1
            my $locale = "$available_language\.$charset";                              # en_US.ISO8859-1
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

   # we don't have any locale for the desired language - return en_US
   if ($ENV{HTTP_ACCEPT_CHARSET} =~ /UTF-8/i) {
      return "en_US.UTF-8"
   }
   return "en_US.ISO8859-1";
}

sub parse_http_accept {
   # parses HTTP_ACCEPT_CHARSET and HTTP_ACCEPT_LANGUAGES environment vars
   # returns as an array to the caller, sorted by the q setting
   my $string = $_[0];
   $string =~ s#[\s_-]##gs;
   return  map { $_->[0] }
          sort { $b->[1] <=> $a->[1] || $a->[0] cmp $b->[0] }
           map { m/([A-Za-z0-9*]+);(?:[Qq]=)?([\d.]+)/?[$1, $2]:[$_, 1] }
         split (/,/, uc($string));
}

sub localeinfo {
   # this sub is intended to parse already validated locale names
   my $locale = $_[0]; # en_US.ISO8859-1
   my ($language, $country, $charset) = $locale =~ m/^(..)_(..)\.(.*)$/;
   my $charsetkey = uc($charset);
   $charsetkey =~ s#[_-]##g; # ISO88591
   return (
            $language,                      # en
            $languagecodes{$language},      # English
            $country,                       # US
            $countrycodes{$country},        # United States
            $charsetkey,                    # ISO88591
            $charset,                       # ISO8859-1  (OWM Locale)
            $charactersets{$charsetkey}[1], # iso-8859-1 (HTTP)
          );
}

1;

