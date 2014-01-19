#!/usr/bin/perl

use strict;
use warnings;

$|++;
use Getopt::Long qw(:config auto_abbrev);
use File::Find;
use File::Basename;
use HTML::Template;

use vars qw($global $option);

die "Present working directory is undefined.\n" unless defined $ENV{PWD} && -d $ENV{PWD};
die "This script must be run as root (su -)... quitting.\n" unless defined $ENV{USER} && $ENV{USER} eq 'root';

#===================
# Set Global Options
#===================
$global = {
             programname => File::Basename::basename($0,(qw(.pl .exe))),
             version     => 20101112,
             gitrepo     => 'http://github.com/openwebmail/openwebmail.git',
             git         => '/usr/local/bin/git',
             tar         => '/usr/bin/tar',
             msgen       => '/usr/local/bin/msgen',
             msgmerge    => '/usr/local/bin/msgmerge',
             msgfmt      => '/usr/local/bin/msgfmt',
             iconv       => '/usr/local/bin/iconv',
             java        => '/usr/local/bin/java',
             md5         => '/sbin/md5',
             rm          => '/bin/rm',
          };

#=========================
# Set Default User Options
#=========================
$option->{help}    = undef;

#=====================================================
# Override default options with user-specified options
#=====================================================
my $result = GetOptions(
                        # "saver=s"               => \$opt->{compoutputdir},
                        "help"                  => \&help,
                       );

if ($result == 0) {
   print "The command line could not be processed properly.\n";
   print "Please run '$global->{programname} -help' for usage information.\n\n";
   exit 1;
}

# sanity check global config and options
die "The git command cannot be executed.\n" unless -x $global->{git};
die "The tar command cannot be executed.\n" unless -x $global->{tar};
die "The msgen command cannot be executed.\n" unless -x $global->{msgen};
die "The msgmerge command cannot be executed.\n" unless -x $global->{msgmerge};
die "The msgfmt command cannot be executed.\n" unless -x $global->{msgfmt};
die "The iconv command cannot be executed.\n" unless -x $global->{iconv};
die "The java command cannot be executed.\n" unless -x $global->{java};
die "The md5 command cannot be executed.\n" unless -x $global->{md5};
die "The rm command cannot be executed.\n" unless -x $global->{rm};

# get the revision number currently at the HEAD of the repo
my $gitinfo = `$global->{git} ls-remote --heads $global->{gitrepo}`;
die "Cannot get git info ($!).\n" unless defined $gitinfo && $gitinfo;

my ($revisionhead) = $gitinfo =~ m#(\S{7})\S+?\s+refs/heads/master#igs;
print "$gitinfo\n\n$revisionhead\n\n";
die "Cannot determine the HEAD revision SHA1 from repository.\n" unless defined $revisionhead;

# get revision information for an existing -current tarball to determine if we need to update
my $revisioncurrent = 0;
if (-f 'openwebmail-current.tar.gz') {
   my $openwebmailconf = `$global->{tar} -xzOf openwebmail-current.tar.gz cgi-bin/openwebmail/etc/defaults/openwebmail.conf`;
   $revisioncurrent = $1 if $openwebmailconf =~ m#revision\s+(\S{1,7})#igs;
}

# do we need to update?
die "Current revision ($revisioncurrent) == HEAD revision ($revisionhead) :: No update required.\n" if $revisioncurrent eq $revisionhead;

print "Updating current revision ($revisioncurrent) ==> HEAD revision ($revisionhead)\n";

# we are updating, remove the old one
if (-f 'openwebmail-current.tar.gz') {
   unlink('openwebmail-current.tar.gz') or die "Cannot delete file openwebmail-current.tar.gz: ($!)";
}

# prepare to clone
if (-d 'gittemp') {
   print "Removing gittemp...\n";
   system("$global->{rm} -rf gittemp");
}

# clone the latest code from github
print "Getting the latest code from $global->{gitrepo}...\n";
system("$global->{git} clone $global->{gitrepo} gittemp > /dev/null") == 0
  or die "Respository checkout failed: ($?)\n";

#==========================
# NOTICE: CHANGE DIRECTORY
#==========================
chdir 'gittemp' or die "Cannot change to directory gittemp: ($!)\n";

# update the openwebmail.conf release date and rev number with HEAD
print "Setting revision and release date...\n";
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $releasedate = sprintf('%04d%02d%02d', $year + 1900, $mon + 1, $mday);

my $configfile = './cgi-bin/openwebmail/etc/defaults/openwebmail.conf';
open(CONF, $configfile) or die "Cannot open ${configfile}: $!\n";
sysread CONF, my $default_conf, -s CONF; # slurp
close(CONF) or die "Cannot close ${configfile}: $!\n";

$default_conf =~ s#^(releasedate[^\d]+)\d{8}#$1$releasedate#img;
$default_conf =~ s#^(revision[^\S]+)\S{1,7}#$1$revisionhead#img;

open(CONF, ">$configfile") or die "Cannot open ${configfile}: $!\n";
print CONF $default_conf;
close(CONF) or die "Cannot close ${configfile}: $!\n";

# generate changes.txt from git logs
print "Generating changes.txt file...\n";
my $rawlog = `$global->{git} log --graph --date=short --pretty=format:'%cd (%h %cn)%n%B'`;
die "Cannot get raw log: ($!)\n" unless defined $rawlog && $rawlog;

$rawlog =~ s/^ +//gm;                      # remove leading spaces
$rawlog =~ s/ +$//gm;                      # remove trailing spaces
$rawlog =~ s/(.*?)git\-svn\-id:.*$/$1/igm; # remove git-svn-id: lines
$rawlog =~ s/[\n\r]{2,}$/\n/gm;            # remove consecutive blank lines

my $changesfile = './data/openwebmail/doc/changes.txt';
open(CHANGES, ">$changesfile") or die "Cannot open ${changesfile}: $!\n";
print CHANGES $rawlog;
close(CHANGES) or die "Cannot close ${changesfile}: $!\n";

print "Removing .git directory...\n";
system("$global->{rm} -rf .git");

# generate new owm.pot PO template from sources
print "Generating POT template from sources...\n";
my $potfile = './cgi-bin/openwebmail/etc/lang/owm.pot';

if (-f $potfile) {
   unlink($potfile) or die("Cannot delete pot file $potfile\n");
}

my $owm_xgettext = './cgi-bin/openwebmail/misc/mkrelease/owm-xgettext.pl';
chmod 0777, $owm_xgettext;
my @sourcefiles = glob 'cgi-bin/openwebmail/*.pl cgi-bin/openwebmail/{shares,modules}/* data/openwebmail/layouts/*/templates/*';
system("$owm_xgettext -f @sourcefiles -o $potfile > /dev/null") == 0
   or die "Cannot extract strings from sources: $!\n";

# create the en_US PO file
print "Generating up to date en_US.UTF-8.po...\n";
my $en_US = './cgi-bin/openwebmail/etc/lang/en_US.UTF-8.po';
system("$global->{msgen} -o $en_US $potfile") == 0
  or die "Cannot create $en_US from POT source ${potfile}: $!";

# update the other PO files with any new strings
my @pofiles = glob 'cgi-bin/openwebmail/etc/lang/*.po';
foreach my $pofile (sort @pofiles) {
   my $filename = File::Basename::basename($pofile,(qw(.po)));

   next if $filename eq 'en_US.UTF-8.po';

   print "Updating strings in ${filename}...\n";
   system("$global->{msgmerge} --update --sort-output --quiet --backup=none $pofile $potfile") == 0
      or die "Cannot merge strings into $filename: ($!)\n";
}

# auto-create any other character sets needed
my $pofilefrom = './cgi-bin/openwebmail/etc/lang/zh_TW.UTF-8.po';
my $pofileto   = './cgi-bin/openwebmail/etc/lang/zh_TW.Big5.po';
if (-f $pofilefrom) {
   print "Converting zh_TW.UTF-8.po -> zh_TW.Big5.po...\n";

   # do not check for errors since some characters cannot be converted perfectly
   system("$global->{iconv} --from-code=UTF-8 --to-code=BIG-5 --unicode-subst='<U+%04X>' $pofilefrom > $pofileto");

   open(PO, $pofileto) or die "Cannot open ${pofileto}: $!\n";
   sysread PO, my $pofileto_text, -s PO; # slurp
   close(PO) or die "Cannot close ${pofileto}: $!\n";

   $pofileto_text =~ s#Content-Type: text/plain; charset=UTF-8#Content-Type: text/plain; charset=Big5#;

   open(PO, ">$pofileto") or die "Cannot open ${pofileto}: $!\n";
   print PO $pofileto_text;
   close(PO) or die "Cannot close ${pofileto}: $!\n";
}

# package ckeditor
# get this ckeditor build number
my $LEGAL = './data/openwebmail/javascript/ckeditor/LEGAL';
open(FILE, "<$LEGAL") or die "Cannot open file: $LEGAL ($!)";
my $firstline = <FILE>;
close(FILE) or die "Cannot close file: $LEGAL ($!)";

my ($build) = $firstline =~ m/^.*\s(\d+)\s.*$/;

print "Building CKEditor (rev$build)...\n";

# run "java -jar _dev/releaser/ckreleaser/ckreleaser.jar -h" for help
system("$global->{java} -jar ./data/openwebmail/javascript/ckeditor/_dev/releaser/ckreleaser/ckreleaser.jar ./data/openwebmail/javascript/ckeditor/_dev/releaser/openwebmail-ckreleaser.release ./data/openwebmail/javascript/ckeditor ckeditor_build \"for OpenWebMail rev$build\" build_$build --verbose");

system("$global->{rm} -rf ./data/openwebmail/javascript/ckeditor");

rename('ckeditor_build/release','./data/openwebmail/javascript/ckeditor')
  or die "Cannot rename directory: ckeditor_build/release -> ./data/openwebmail/javascript/ckeditor ($!)";

system("$global->{rm} -rf ckeditor_build");

system("$global->{rm} -rf ./data/openwebmail/javascript/ckeditor/_source ./data/openwebmail/javascript/ckeditor/ckeditor_basic.js ./data/openwebmail/javascript/ckeditor/openwebmail-*");

print "done\n"; # ckeditor complete

# set permissions on all the files
print "Permissioning files and directories...\n";

find(
       {
          wanted => sub {
                           my $mode = (-d) ? 0755 : 0644;
                           chmod $mode, $File::Find::name; # all directories 755, all files 644
                           chown 0, 0, $File::Find::name;  # everything root:root to start
                        },
          follow => 1,
       },
       './data/openwebmail/javascript/ckeditor', # starting from
    );

my $mailgid = getgrnam('mail') or die "Cannot get mail gid number: ($!)";
chown 0, $mailgid, glob './cgi-bin/openwebmail/* ./cgi-bin/openwebmail/{auth,quota,modules,shares,misc,etc}/*';

chmod oct(4755), glob './cgi-bin/openwebmail/openwebmail*.pl';
chmod 0755, glob './cgi-bin/openwebmail/{vacation,userstat,preload}.pl';
chmod 0771, glob './cgi-bin/openwebmail/etc/{users,sessions}';
chmod 0640, glob './cgi-bin/openwebmail/etc/smtpauth.conf';

# update openwebmail.acatysmoof.com
if ($ENV{HOST} eq 'gouda.acatysmoof.com') {
   print "Updating openwebmail.acatysmoof.com...\n";

   # first the homepage
   my %months = (
                   1  => 'January',
                   2  => 'February',
                   3  => 'March',
                   4  => 'April',
                   5  => 'May',
                   6  => 'June',
                   7  => 'July',
                   8  => 'August',
                   9  => 'September',
                   10 => 'October',
                   11 => 'November',
                   12 => 'December',
                );

   my $revisionstring = '(' . $months{$mon + 1} . " $mday, " . ($year + 1900) . " Rev $revisionhead)";

   my $index = '/home/alex/openwebmail.acatysmoof.com/index.html';
   open(INDEX, "<$index") or die "Cannot open file ${index}: ($!)\n";
   sysread INDEX, my $indexhtml, -s INDEX; # slurp
   close(INDEX) or die "Cannot close file ${index}: ($!)\n";

   $indexhtml =~ s/\([a-z]+\s\d+,\s\d+\sRev\s\S+\)/$revisionstring/igs;

   open(INDEX, ">$index") or die "Cannot open file ${index}: ($!)\n";
   print INDEX $indexhtml;
   close(INDEX) or die "Cannot close file ${index}: ($!)\n";

   # and then the language page

   # LANGUAGE CODES
   # derived from ISO-639-1 (updated 06/24/2006)
   # http://www.loc.gov/standards/iso639-2/langcodes.html
   my %languagecodes = (
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
                          'nb' => 'Norwegian Bokmal',
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
                          'si' => 'Sinhala',
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
   my %countrycodes = (
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
                         'AX' => 'Aland Islands',
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
                         'CI' => "Cote D'Ivoire",
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
                         'KP' => "Korea, Democratic People's Republic Of",
                         'KR' => 'Korea',
                         'KW' => 'Kuwait',
                         'KY' => 'Cayman Islands',
                         'KZ' => 'Kazakhstan',
                         'LA' => "Lao People's Democratic Republic",
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
                         'RE' => 'Reunion',
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

   my $langstathtml = qq|
   <table cellpadding="4" cellspacing="0" border="0" width="100%" id="languagestats">
   <tr>
     <td class="heading">Filename</td>
     <td class="heading">Language</td>
     <td class="heading">Country</td>
     <td class="heading">Progress</td>
   </tr>|;

   foreach my $pofile (@pofiles) {
      my $filename = File::Basename::basename($pofile,(qw(.po)));
      my ($language, $country, $charset) = $filename =~ m/^([^_]+)_([^.]+).(.*)$/;

      my $postats = `$global->{msgfmt} --statistics -c $pofile --output-file /dev/null 2>&1`;

      my ($translated, $fuzzy, $untranslated) = $postats =~ m/(\d+) trans[^\d]+(?:(\d+) fuzz[^\d]+)?(?:(\d+) untran[^\d]+)?/;
      $translated   = defined $translated ? $translated : 0;
      $fuzzy        = defined $fuzzy ? $fuzzy : 0;
      $untranslated = defined $untranslated ? $untranslated : 0;

      my $allcount = $translated + $fuzzy + $untranslated;

      my $translatedpercent   = $translated ? int((($translated * 100) / $allcount) + .5) : 0;
      my $fuzzypercent        = $fuzzy ? int((($fuzzy * 100) / $allcount) + .5) : 0;
      my $untranslatedpercent = $untranslated ? int((($untranslated * 100) / $allcount) + .5) : 0;

      $langstathtml .= qq|
      <tr>
         <td><a href="http://raw.github.com/openwebmail/openwebmail/master/cgi-bin/openwebmail/etc/lang/$filename.po" target="_new">$filename</a></td>
         <td>$languagecodes{$language}</td>
         <td>$countrycodes{$country}</td>
         <td align="center">
           <div id="progressbar">
             <div class="fuzzy" style="width: | . ($fuzzypercent + $translatedpercent) . qq|%;"></div>
             <div class="| . ($translatedpercent == 100 ? 'alltranslated' : 'translated') . qq|" style="width: | . $translatedpercent . qq|%;"></div>
             <div class="text">$translatedpercent\% ($translated translated), $fuzzypercent\% ($fuzzy fuzzy), $untranslatedpercent\% ($untranslated untranslated)</div>
           </div>
         </td>
      </tr>|;
   }

   $langstathtml .= qq|
      </table>|;

   my $langpage = '/home/alex/openwebmail.acatysmoof.com/doc/tech/i18n/index.htm';
   open(LANGPAGE, "<$langpage") or die "Cannot open file ${langpage}: ($!)\n";
   sysread LANGPAGE, my $langpagehtml, -s LANGPAGE; # slurp
   close(LANGPAGE) or die "Cannot close file ${langpage}: ($!)\n";

   $langpagehtml =~ s/(<!-- STATS -->).*(<!-- END STATS -->)/$1\n$langstathtml\n$2/igs;

   open(LANGPAGE, ">$langpage") or die "Cannot open file ${langpage}: ($!)\n";
   print LANGPAGE $langpagehtml;
   close(LANGPAGE) or die "Cannot close file ${langpage}: ($!)\n";
}

# pack it up
print "Creating the tarball...\n";
system("$global->{tar} -czf ../openwebmail-current.tar.gz data cgi-bin") == 0
   or die "Cannot create the tarball: ($?)";

#==========================
# NOTICE: CHANGE DIRECTORY
#==========================
chdir '..' or die "Cannot change to directory ..: ($!)\n";

# writing md5
print "Writing MD5SUM...\n";
my $md5sum = `$global->{md5} -r openwebmail-current.tar.gz`;
open(MD5, ">MD5SUM") or die "Cannot open file MS5SUM ($!)";
print MD5 $md5sum;
close(MD5) or die "Cannot close file MD5SUM: ($!)";

# clean up
print "Cleaning up...\n";
system("$global->{rm} -rf gittemp") == 0
   or die "Cannot remove gittemp directory";

print "done.\n";

sub help {
   die "Showing help requires the Pod::Text module, which cannot be found: $@"
      unless eval "require Pod::Text";

   my $parser = Pod::Text->new(
                                 sentence => 0,
                                 width    => 90,
                                 margin   => 3,
                              );

   $parser->parse_from_file($0);

   exit 0;
}

# ALL DOCUMENTATION BELOW THIS LINE

=pod

=head1

=head1 NAME

mkcurrent - collect, permission, and package a tarball of OpenWebMail from a git repository

=head1 DESCRIPTION

This script creates an openwebmail-current tarball by performing the following:

=over 4

=item - check out the latest version from a git repository

=item - generate a changes.txt file from the git logs

=item - update the release date and revision number in openwebmail.conf

=item - change the file permissions to the correct defaults

=item - tar it all up

=back

THIS SCRIPT MUST BE RUN AS ROOT!

=head1 OPTIONS

All options below can be optionally abbreviated to their shortest unique name. Options are in typical usage order.

=over 4

=item help

Prints this help file.

=cut

