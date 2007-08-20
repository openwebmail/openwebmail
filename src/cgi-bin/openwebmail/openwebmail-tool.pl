#!/usr/bin/suidperl -T
#
# openwebmail-tool.pl - command tool for mail/event/notify/index...
#
# 03/27/2003 tung.AT.turtle.ee.ncku.edu.tw
#            Ebola.AT.turtle.ee.ncku.edu.tw
#
use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { local $1; $SCRIPT_DIR=$1 }
if ($SCRIPT_DIR eq '' && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { local $1; $SCRIPT_DIR=$1 }
}
if ($SCRIPT_DIR eq '') {
   print qq|\nOpenWebMail is unable to locate itself on this system,\n|.
         qq|please put 'the path of openwebmail CGI directory' to\n|.
         qq|the first line of file /etc/openwebmail_path.conf\n\n|.
         qq|For example, if the script is\n\n|.
         qq|/usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl,\n\n|.
         qq|then the content of /etc/openwebmail_path.conf should be:\n\n|.
         qq|/usr/local/www/cgi-bin/openwebmail/\n\n|;
   exit 0;
}
push (@INC, $SCRIPT_DIR);

foreach (qw(ENV BASH_ENV CDPATH IFS TERM)) {delete $ENV{$_}}; $ENV{PATH}='/bin:/usr/bin'; # secure ENV
umask(0002); # make sure the openwebmail group can write
use strict;
use Fcntl qw(:DEFAULT :flock);
use Net::SMTP;

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/execute.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "modules/mailparse.pl";
require "modules/spamcheck.pl";
require "modules/viruscheck.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/lockget.pl";
require "shares/cut.pl";
require "shares/getmsgids.pl";
require "shares/fetchmail.pl";
require "shares/pop3book.pl";
require "shares/adrbook.pl";
require "shares/calbook.pl";
require "shares/filterbook.pl";
require "shares/mailfilter.pl";
require "shares/lunar.pl";
require "shares/upgrade.pl";

# optional module
ow::tool::has_module('IO/Socket/SSL.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($default_logindomain $loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs);
use vars qw(%lang_text);

# extern vars
use vars qw($_DBVERSION);		# defined in maildb.pl
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES);
use vars qw(%is_config_option);		# from ow-shared.pl
use vars qw(%is_internal_dbkey);	# from maildb.pl

# local globals
use vars qw($POP3_TIMEOUT %opt $startup_ruid);

# used to remember ruid of user who executes this script
$startup_ruid=$< if (!defined $startup_ruid);
#
# speedycgi guarentees a persistennt copy is used again
# only if the script is executed by same user(ruid),
# since routine openwebmail_requestbegin() clears ruid of persistence copy,
# we store the ruid in $startup_ruid.

########## main ##################################################
$POP3_TIMEOUT=20;

%opt=('null'=>1);
$default_logindomain="";

# by default, the $startup_ruid (ruid of the user running this script) is used as runtime euid
# but euid $> is used if operation is either from inetd, -m (query mail status ) or -e(query event status)
my $euid_to_use=$startup_ruid;
my @list=();

openwebmail_requestbegin();

# no buffer on stdout
local $|=1;

if ($ARGV[0] eq "--") {		# called by inetd
   push(@list, $ARGV[1]);
   $opt{'mail'}=1; $opt{'event'}=1; $opt{'null'}=0; $euid_to_use=$>;
} else {
   for (my $i=0; $i<=$#ARGV; $i++) {
      if ($ARGV[$i] eq "--init") {
         $opt{'init'}=1;
      } elsif ($ARGV[$i] eq "--test" || $ARGV[$i] eq "-w") {
         $opt{'test'}=1;
      } elsif ($ARGV[$i] eq "--langconv" || $ARGV[$i] eq "-v") {
         $opt{'langconv'}=1;
         $i++; $opt{'srclocale'}=$ARGV[$i];
         $i++; $opt{'dstlocale'}=$ARGV[$i];

      } elsif ($ARGV[$i] eq "--yes" || $ARGV[$i] eq "-y") {
         $opt{'yes'}=1;
      } elsif ($ARGV[$i] eq "--no") {
         $opt{'no'}=1;
      } elsif ($ARGV[$i] eq "--debug") {
         $opt{'debug'}=1;
      } elsif ($ARGV[$i] eq "--quiet" || $ARGV[$i] eq "-q") {
         $opt{'quiet'}=1;

      } elsif ($ARGV[$i] eq "--domain" || $ARGV[$i] eq "-d") {
         $i++ if $ARGV[$i+1]!~/^\-/;
         $default_logindomain=safedomainname($ARGV[$i]);
      } elsif ($ARGV[$i] eq "--alluser" || $ARGV[$i] eq "-a") {
         $opt{'allusers'}=1;
      } elsif ($ARGV[$i] eq "--file" || $ARGV[$i] eq "-f") {
         $i++;
         if ( -f $ARGV[$i] ) {
            sysopen(F, $ARGV[$i], O_RDONLY);
            while (<F>) { chomp $_; push(@list, $_); }
            close(F);
         }

      } elsif ($ARGV[$i] eq "--thumbnail" || $ARGV[$i] eq "-t") {
         $opt{'thumbnail'}=1;

      } elsif ($ARGV[$i] eq "--index" || $ARGV[$i] eq "-i") {
         $opt{'iv'}='ALL'; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-id") {
         $i++; $opt{'id'}=$ARGV[$i]; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-iv") {
         $i++; $opt{'iv'}=$ARGV[$i]; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-if") {
         $i++; $opt{'if'}=$ARGV[$i]; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-ir") {
         $i++; $opt{'ir'}=$ARGV[$i]; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-iz") {
         $i++; $opt{'iz'}=$ARGV[$i]; $opt{'null'}=0;

      } elsif ($ARGV[$i] eq "--mail" || $ARGV[$i] eq "-m") {
         $opt{'mail'}=1; $opt{'null'}=0; $euid_to_use=$>;
      } elsif ($ARGV[$i] eq "--event" || $ARGV[$i] eq "-e") {
         $opt{'event'}=1; $opt{'null'}=0; $euid_to_use=$>;
      } elsif ($ARGV[$i] eq "--notify" || $ARGV[$i] eq "-n") {
         $opt{'notify'}=1; $opt{'null'}=0;

      } elsif ($ARGV[$i] eq "--pop3" || $ARGV[$i] eq "-p") {
         $opt{'pop3'}=1; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--size" || $ARGV[$i] eq "-s") {
         $opt{'size'}=1; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--unlock" || $ARGV[$i] eq "-u") {
         $opt{'unlock'}=1; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--zaptrash" || $ARGV[$i] eq "-z") {
         $opt{'zap'}=1; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--convert_addressbooks" || $ARGV[$i] eq "-c") {
         $opt{'convert_addressbooks'}=1; $opt{'null'}=0;

      } else {
         push(@list, $ARGV[$i]);
      }
   }
}

$>=$euid_to_use;

# load the default config, but don't merge it into the config hash yet
# because there may be paths that get changed in the custom config
load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");

if ( -f "$SCRIPT_DIR/etc/openwebmail.conf") {
   # load the custom config over the default config and merge everything
   read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
   print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if ($opt{'debug'});
} else {
   # there is no custom config, so just do the merge with the default config
   read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
}

$logindomain=$default_logindomain||ow::tool::hostname();
$logindomain=lc(safedomainname($logindomain));
if (defined $config{'domainname_equiv'}{'map'}{$logindomain}) {
   print "D domain equivalence found: $logindomain -> $config{'domainname_equiv'}{'map'}{$logindomain}\n" if ($opt{'debug'});
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain};
}
if ( -f "$config{'ow_sitesconfdir'}/$logindomain") {
   read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if ($opt{'debug'});
}

%prefs = readprefs();
loadlang("$prefs{'locale'}"); # for converted filename $lang_text{abook_converted}

writelog("debug - request tool begin, argv=".join(' ',@ARGV)." - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
my $retval=0;
if ($opt{'init'}) {
   $retval=init();
} elsif ($opt{'test'}) {
   $retval=do_test();
} elsif ($opt{'langconv'}) {
   $retval=langconv($opt{'srclocale'}, $opt{'dstlocale'}, 1);
} elsif ($opt{'thumbnail'}) {
   $retval=makethumbnail(\@list);
} else {
   if ($opt{'convert_addressbooks'} && $>==0) {	# only allow root to convert globalbook
      print "converting GLOBAL addressbook..." if (!$opt{'quiet'});
      $retval=convert_addressbook('global', (ow::lang::localeinfo($prefs{'locale'}))[6]);
      if ($retval<0) {
         print "error:$@. EXITING\n";
         openwebmail_exit($retval);
      }
      print "done.\n" if (!$opt{'quiet'});
   }

   if ($opt{'allusers'}) {
      $retval=allusers(\@list);
      openwebmail_exit($retval) if ($retval<0);
   }

   if ($#list>=0 && !$opt{'null'}) {
      $retval=usertool($euid_to_use, \@list);
   } elsif ($opt{'convert_addressbooks'}) {
      # don't show help after converting just GLOBAL book
   } else {
      $retval=showhelp();
   }
}
writelog("debug - request tool end, argv=".join(' ',@ARGV)." - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_exit($retval);

########## showhelp ##############################################
sub showhelp {
   print qq|
Syntax: openwebmail-tool.pl --init [options]
        openwebmail-tool.pl --test
        openwebmail-tool.pl --langconv srclocale dstlocale
        openwebmail-tool.pl -t [options] [image1 image2 ...]
        openwebmail-tool.pl [options] [user1 user2 ...]

common options:
 -q, --quite  \t quiet, no output
     --debug  \t print debug information

init options:
 -y, --yes    \t default answer yes to send site report
     --no     \t default answer no  to send site report

thumbnail option:
 -f <imglist> \t image list from file, each line for one path
 -t, --thumbnail make thumbnail for images

mail/calendar options:
 -a, --alluser\t check for all users in all domains
 -d, --domain \t default domain for user with no domain specified
 -e, --event  \t check today's calendar event
 -f <userlist>\t userlist from file, each line for one user
 -i, --index  \t verify index of all folders and reindex if needed
 -id <folder> \t dump index of folder
 -iv <folder> \t verify index of folder and reindex if needed
 -if <folder> \t fast rebuild index of folder
 -ir <folder> \t rebuild index of folder
 -iz <folder> \t clear zap messages from folder
 -m, --mail   \t check new mail
 -n, --notify \t check and send calendar notification email
 -p, --pop3   \t fetch pop3 mail for user
 -s, --size   \t check user quota and cut mails/files if over quotalimit
 -u, --unlock  \t remove file locks related to user
 -z, --zaptrash\t remove stale messages from trash folder
 -c, --convert_addressbooks\t convert addressbookglobal (and all users with -a) addressbooks to vcard format

miscellanous options:
 --init        \t create the initial files and directories needed for openwebmail to operate
 -v, --langconv\t convert src locale files to dst locale to begin new translation
 -w, --test    \t run openwebmail-tool but don't write any files or make changes

ps: <folder> can be INBOX, ALL or folder filename

|;
   return 1;
}

########## init ##################################################
sub init {
   print "\n";

   my $err=do_test(1);
   if ($err<0) {
      print qq|And execute '$SCRIPT_DIR/openwebmail-tool.pl --init' again!\n\n|.
            qq|ps: If you are running openwebmail in persistent mode,\n|.
            qq|    don't forget to 'touch openwebmail*.pl', so speedycgi\n|.
            qq|    will reload all scripts, modules and conf files in --init.\n\n|;
      return $err;
   }

   foreach my $table ('b2g', 'g2b', 'lunar') {
      if ( $config{$table.'_map'} ) {
         my $tabledb="$config{'ow_mapsdir'}/$table";
         my $err=0;
         if (ow::dbm::exist($tabledb)) {
            my %T;
            if (!ow::dbm::open(\%T, $tabledb, LOCK_SH) ||
                !ow::dbm::close(\%T, $tabledb) ) {
               ow::dbm::unlink($tabledb);
               print "delete old db $tabledb\n";
            }
         }
         if ( !ow::dbm::exist($tabledb)) {
            die "$config{$table.'_map'} not found" if (!-f $config{$table.'_map'});
            print "creating db $config{'ow_mapsdir'}/$table ...";
            $err=-2 if ($table eq 'b2g' and mkdb_b2g()<0);
            $err=-3 if ($table eq 'g2b' and mkdb_g2b()<0);
            $err=-4 if ($table eq 'lunar' and mkdb_lunar()<0);
            if ($err < 0) {
               print "error!\n"; return $err;
            }
            print "done.\n";
         }
      }
   }

   %prefs = readprefs();	# send_mail() uses $prefs{...}

   print "\nCreating UTF-8 locales...\n";
   my $available_locales=available_locales();
   foreach my $srclocale (sort keys %{$available_locales}) {
      next if $srclocale =~ 'UTF-8';
      next if $srclocale =~ 'ja_JP';
      next if $srclocale =~ 'zh_';
      next if $srclocale =~ 'ISO8859-8'; # Visual Hebrew is not supported
      my $dstlocale=$srclocale;
      $dstlocale=~s/[.].*$/.UTF-8/g;
      langconv($srclocale, $dstlocale, 0);
   }
   print "...done.\n\n";
             
   my $id = $ENV{'USER'} || $ENV{'LOGNAME'} || getlogin || (getpwuid($>))[0];
   my $hostname=ow::tool::hostname();
   my $realname=(getpwnam($id))[6]||$id;
   my $to="stats\@openwebmail.acatysmoof.com";
   my $date = ow::datetime::dateserial2datefield(ow::datetime::gmtime2dateserial(), $config{'default_timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my $subject="site report - $hostname";
   my $os;
   if ( -f "/usr/bin/uname") {
      $os=`/usr/bin/uname -srm`; chomp($os);
   } else {
      $os=`/bin/uname -srm`; chomp($os);
   }
   my $content=qq|OS: $os\n|.
               qq|Perl: $]\n|.
               qq|WebMail: $config{'name'} $config{'version'} $config{'releasedate'}\n|;

   if ($opt{'yes'}) {
      print qq|$content\n|.
             qq|sending site report...\n|;
      send_mail("$id\@$hostname", $realname, $to, $date, $subject, "$content \n");
   } elsif ($opt{'no'} or $opt{'debug'}) {
      print qq|$content\n|.
             qq|No site report sent.\n|;
   } else {
      print qq|Welcome to the OpenWebMail!\n\n|.
            qq|This program is going to send a short message back to the developer,\n|.
            qq|so we could have the idea that who is installing and how many sites are\n|.
            qq|using this software, the content to be sent is:\n\n|.
            qq|$content\n|.
            qq|Send the site report?(Y/n) |;
      $_=<STDIN>;
      if ($_!~/n/i) {
         print qq|sending report...\n|;
         send_mail("$id\@$hostname", $realname, $to, $date, $subject, "$content \n")
      }
   }
   print qq|\nThank you.\n\n|;
   return 0;
}

sub do_test {
   my ($in_init)=@_;
   my $err=0;
   print "\n" if (!$in_init);

   if ($MIME::Base64::VERSION < 3.00) {
      $err--;
      print "Base64.pm\t\t$INC{'MIME/Base64.pm'}\n\n";
      print "Your MIME::Base64 module is too old ($MIME::Base64::VERSION),\n".
            "please update to 3.00 or later.\n\n\n";
   }

   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock)=ow::dbm::guessoptions();

   print_dbm_module() if (!$in_init);

   $err-- if (check_db_file_pm()<0);
   $err-- if (check_dbm_option($in_init, $dbm_ext, $dbmopen_ext, $dbmopen_haslock)<0);
   $err-- if (check_savedsuid_support()<0);

   return $err;
}

sub print_dbm_module {
   print "Your perl uses the following packages for dbm:\n\n";
   my @pm;
   foreach (keys %INC) { push (@pm, $_) if (/DB.*File/); }
   foreach (sort @pm) { print "$_\t\t$INC{$_}\n"; }
   print "\n\n";
}

sub check_db_file_pm {
   my $dbfile_pm=$INC{'DB_File.pm'};
   if ($dbfile_pm) {
      my $t;
      sysopen(F, $dbfile_pm, O_RDONLY); while(<F>) {$t.=$_;} close(F);
      $t=~s/\s//gms;
      if ($t!~/\$arg\[3\]=0666unlessdefined\$arg\[3\];/sm
       && $t!~/\$arg\[3\]=0666if\@arg>=4&&!defined\$arg\[3\];/sm) {
         print qq|Please modify $dbfile_pm by adding\n\n|.
               qq|\t\$arg[3] = 0666 unless defined \$arg[3];\n\n|.
               qq|before the following text (about line 247)\n\n|.
               qq|\t# make recno in Berkeley DB version 2 work like recno in version 1\n\n\n|;
         return -1;
      }
   }
   return 0;
}

sub check_dbm_option {
   my ($in_init, $dbm_ext, $dbmopen_ext, $dbmopen_haslock)=@_;

   my $err=0;
   if ($dbm_ext          ne $ow::dbm::dbm_ext ||
       $dbmopen_ext      ne $ow::dbm::dbmopen_ext ||
       ($dbmopen_haslock ne $ow::dbm::dbmopen_haslock && $dbmopen_haslock) ) {
      $err++;
   }

   my %str;
   @str{'dbm_ext', 'dbmopen_ext', 'dbmopen_haslock'}=
      ($dbm_ext, $dbmopen_ext, $dbmopen_haslock);
   @str{'conf_dbm_ext', 'conf_dbmopen_ext', 'conf_dbmopen_haslock'}=
      ($ow::dbm::dbm_ext, $ow::dbm::dbmopen_ext, $ow::dbm::dbmopen_haslock);
   foreach ('dbm_ext', 'dbmopen_ext', 'conf_dbm_ext', 'conf_dbmopen_ext') {
      $str{$_}='none' if ($str{$_} eq '');
   }
   foreach ('dbmopen_haslock', 'conf_dbmopen_haslock') {
      if ($str{$_}) {
         $str{$_}='yes';
      } else {
         $str{$_}='no';
      }
   }

   if ($in_init && $err) {
      print qq|Please change '$SCRIPT_DIR/etc/dbm.conf' from\n\n|.
            qq|dbm_ext         \t$str{conf_dbm_ext}\n|.
            qq|dbmopen_ext     \t$str{conf_dbmopen_ext}\n|.
            qq|dbmopen_haslock \t$str{conf_dbmopen_haslock}\n|.
            qq|\nto\n\n|.
            qq|dbm_ext         \t$str{dbm_ext}\n|.
            qq|dbmopen_ext     \t$str{dbmopen_ext}\n|.
            qq|dbmopen_haslock \t$str{dbmopen_haslock}\n\n\n|;
   }
   if (!$in_init) {
      print qq|'$SCRIPT_DIR/etc/dbm.conf' should be set as follows:\n\n|.
            qq|dbm_ext         \t$str{dbm_ext}\n|.
            qq|dbmopen_ext     \t$str{dbmopen_ext}\n|.
            qq|dbmopen_haslock \t$str{dbmopen_haslock}\n\n\n|;
   }

   return -1 if ($err);
   return 0;
}

sub check_savedsuid_support {
   return if ($>!=0);

   $>=65534;
   $>=0;
   if ($>!=0) {
      print qq|Your system didn't have saved suid support,\n|.
            qq|please set the following option in $SCRIPT_DIR/etc/suid.conf\n\n|.
            qq|\thas_savedsuid_support no\n\n\n|;
      return -1;
   }
   return 0;
}

########## langconv routines #####################################
sub langconv {
   my ($srclocale, $dstlocale, $verbose)=@_;

   print "langconv $srclocale -> $dstlocale\n";

   unless (-f "$config{ow_langdir}/$srclocale") {
      die "src locale $srclocale does not exist in $config{ow_langdir}";
   }
   my $srccharset = (ow::lang::localeinfo($srclocale))[6];
   my $dstcharset = (ow::lang::localeinfo($dstlocale))[6];

   if (!is_convertible($srccharset, $dstcharset)) {
      die "src locale charset $srclocale -> dst locale charset $dstlocale is not convertible";
   }

   langconv_file("$config{'ow_langdir'}/$srclocale", $srclocale,
                 "$config{'ow_langdir'}/$dstlocale", $dstlocale, 1, $verbose);

   langconv_dir("$config{'ow_templatesdir'}/$srclocale", $srclocale,
                "$config{'ow_templatesdir'}/$dstlocale", $dstlocale, $verbose);

   langconv_dir("$config{'ow_htmldir'}/javascript/htmlarea.openwebmail/popups/$srclocale", $srclocale,
                "$config{'ow_htmldir'}/javascript/htmlarea.openwebmail/popups/$dstlocale", $dstlocale, $verbose);

   return 0;
}

sub langconv_dir {
   my ($srcdir, $srclocale, $dstdir, $dstlocale, $verbose)=@_;

   print "langconv dir $srcdir -> $dstdir\n" if ($verbose);

   die "srcdir $srcdir doesn't exist" if (!-d $srcdir);
   if (!-d $dstdir) {
      $dstdir=ow::tool::untaint($dstdir);
      mkdir($dstdir, 0755) || die "create $dstdir error ($!)";
      chmod(0755, $dstdir);
   }

   my @files;

   opendir(D, $srcdir) || die "can't open directory: $srcdir";
   while (my $f=readdir(D)) {
      next if ($f =~ /^\..*/);
      next if ($f =~ /.*README.*/);
      push(@files, $f);
   }
   closedir(D);

   foreach my $f (@files) {
      langconv_file("$srcdir/$f", $srclocale,
                    "$dstdir/$f", $dstlocale, 0, $verbose);
   }
}

sub langconv_file {
   my ($srcfile, $srclocale, $dstfile, $dstlocale, $check_pkgname, $verbose)=@_;

   print "langconv file $srcfile -> $dstfile\n" if ($verbose);

   my @lines;
   sysopen(F, $srcfile, O_RDONLY) || die "$srcfile open error ($!)";
   @lines=<F>;
   close(F);

   if ($check_pkgname) {
      my $srcpkg = $srclocale;
      $srcpkg=~s/[\.\-]/_/g; # en_US_ISO8859_1

      my $dstpkg = $dstlocale;
      $dstpkg=~s/[\.\-]/_/g;

      if ($lines[0] ne "package ow::$srcpkg;\n") {
         die "$srcfile 1st line is not 'package ow::$srcpkg;'";
      }
      $lines[0]="package ow::$dstpkg;\n";
   }

   # change charset name in html file
   my $srccharset = (ow::lang::localeinfo($srclocale))[6];
   my $dstcharset = (ow::lang::localeinfo($dstlocale))[6];

   foreach (@lines) {
      s!content="text/html; charset=$srccharset"!content="text/html; charset=$dstcharset"!ig;
      s!charset: $srccharset!charset: $dstcharset!ig;
   }

   my $content=join('', @lines);
   ($content)=iconv($srccharset, $dstcharset, $content);

   $dstfile=ow::tool::untaint($dstfile);
   sysopen(F, $dstfile, O_WRONLY|O_TRUNC|O_CREAT) || die "$dstfile open error ($!)";
   print F $content;
   close(F);

   my ($fmode, $fuid, $fgid)=(stat($srcfile))[2,4,5];
   chmod(ow::tool::untaint($fmode), $dstfile);
   chown(ow::tool::untaint($fuid), ow::tool::untaint($fgid), $dstfile);

   return 0;
}

########## make_thumbnail ########################################
sub makethumbnail {
   my $r_files=$_[0];
   my $err=0;

   my $convertbin=ow::tool::findbin("convert");
   if ($convertbin eq '') {
      print "Program convert doesn't exist\n" if (!$opt{'quiet'});
      return -1;
   }
   my @cmd=($convertbin, '+profile', '*', '-interlace', 'NONE', '-geometry', '64x64');

   foreach my $image (@{$r_files}) {
      next if ( $image!~/\.(jpe?g|gif|png|bmp|tif)$/i || !-f $image);

      my $thumbnail=ow::tool::untaint(path2thumbnail($image));
      my @p=split(/\//, $thumbnail); pop(@p);
      my $thumbnaildir=join('/', @p);
      if (!-d "$thumbnaildir") {
         if (!mkdir (ow::tool::untaint("$thumbnaildir"), 0755)) {
            print "$!\n" if (!$opt{'quiet'});
            $err++; next;
         }
      }

      my ($img_atime,$img_mtime)= (stat($image))[8,9];
      if (-f $thumbnail) {
         my ($thumbnail_atime,$thumbnail_mtime)= (stat($thumbnail))[8,9];
         if ($thumbnail_mtime==$img_mtime) {
            print "$thumbnail already exist.\n" if (!$opt{'quiet'});
            next;
         }
      }
      my ($stdout, $stderr, $exit, $sig)=ow::execute::execute(@cmd, $image, $thumbnail);

      if (!$opt{'quiet'}) {
         print "$thumbnail";
         if ($exit||$sig) {
            print ", exit $exit" if ($exit);
            print ", signal $sig" if ($sig);
            print "\n";
            print "($stderr)\n" if ($stderr);
            $err++; next;
         } else {
            print "\n";
         }
      }

      if (-f "$thumbnail.0") {	# use 1st thumbnail of merged gifs
         my @f;
         foreach (1..20) {
            push(@f, "$thumbnail.$_");
         }
         unlink @f;
         rename("$thumbnail.0", $thumbnail);
      }
      if (-f $thumbnail) {
         utime(ow::tool::untaint($img_atime), ow::tool::untaint($img_mtime), $thumbnail)
      }
   }
   return($err);
}

sub path2thumbnail {
   my @p=split(/\//, $_[0]);
   my $tfile=pop(@p); $tfile=~s/\.[^\.]*$/\.jpg/i;
   push(@p, '.thumbnail');
   return(join('/',@p)."/$tfile");
}


########## user folder/calendar routines #########################
sub allusers {
   my $r_list=$_[0];
   my $loaded_domain=0;
   my %userhash=();

   # trap this once now.  Let usertool() test it at the domain level later
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
        !$config{'use_homedirspools'} &&
       ($config{'mailspooldir'} eq "/var/mail" ||
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "This operation is only available to root\n"; openwebmail_exit(0);
   }

   # if there's localusers defined for vdomain,
   # we should grab them otherwise they'll be missed
   foreach (@{$config{'localusers'}}) {
      if (/^(.+)\@(.+)$/) {
         $userhash{$2}{$1}=1;
      } else {
         $userhash{$logindomain}{$_}=1;
      }
   }

   my @domains=($logindomain);
   foreach (alldomains()) {
      push(@domains, $_) if ($_ ne $logindomain);
   }

   foreach $logindomain (@domains) {

      # REINIT %config for auth_module as each domain may use different auth_module!

      %config_raw=();
      load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
      if ( -f "$SCRIPT_DIR/etc/openwebmail.conf") {
         read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
         print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if ($opt{'debug'});
      }

      if ( -f "$config{'ow_sitesconfdir'}/$logindomain") {
         read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
         print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if ($opt{'debug'});
      }

      ow::auth::load($config{'auth_module'});
      print "D ow::auth::load $config{'auth_module'}\n" if ($opt{'debug'});

      my ($errcode, $errmsg, @userlist)=ow::auth::get_userlist(\%config);
      if ($errcode!=0) {
         writelog("userlist error - $config{'auth_module'}, ret $errcode , $errmsg");
         if ($errcode==-1) {
            print "-a is not supported by $config{'auth_module'}, use -f instead\n" if (!$opt{'quiet'});
         } else {
            print "Unable to get userlist, error code $errcode\n" if (!$opt{'quiet'});
         }
      } else {
         $loaded_domain++;
         foreach (@userlist) {
            if (/^(.+)\@(.+)$/) {
               $userhash{$2}{$1}=1;
            } else {
               $userhash{$logindomain}{$_}=1;
            }
         }
      }
   }

   foreach $logindomain ( sort keys %userhash ) {
      foreach (sort keys %{$userhash{$logindomain}}) {
         push @{$r_list}, "$_\@$logindomain";
      }
   }

   return if ($loaded_domain>0);
   return -1;
}


sub alldomains {
   my %domainnames=();

   if ( ! opendir(SITEDIR, $config{'ow_sitesconfdir'})){
      writelog("siteconf dir error $config{'ow_sitesconfdir'} $!");
      print "Unable to read siteconf dir $config{'ow_sitesconfdir'} $!\n" if (!$opt{'quiet'});
      return -1;
   }
   while ($domain=readdir(SITEDIR)) {
      next if ($domain=~/^(\.|readme|sameple)/i);
      $domainnames{$domain}=1;
      print "D found domain $domain\n" if ($opt{'debug'});
   }
   closedir(SITEDIR);

   return(keys %domainnames);
}

sub usertool {
   my ($euid_to_use, $r_userlist)=@_;
   my $hostname=ow::tool::hostname();
   my %homedir_processed=();
   my $usercount=0;

   foreach $loginname (@{$r_userlist}) {
      # reset back to init $euid before switch to next user
      #$>=0;
      $>=$euid_to_use;

      %config_raw=();
      load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
      if ( -f "$SCRIPT_DIR/etc/openwebmail.conf") {
         read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
         print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if ($opt{'debug'});
      }

      if ($config{'smtpauth'}) {	# load smtp auth user/pass
         read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/smtpauth.conf");
         if ($config{'smtpauth_username'} eq "" || $config{'smtpauth_password'} eq "") {
            die "Invalid username/password in $SCRIPT_DIR/etc/smtpauth.conf!";
         }
      }

      if ($loginname=~/^(.+)\@(.+)$/) {
         ($loginuser, $logindomain)=($1, $2);
      } else {
         $loginuser=$loginname;
         $logindomain=$default_logindomain||$hostname;
      }
      $loginuser=lc($loginuser) if ($config{'case_insensitive_login'});
      $logindomain=lc(safedomainname($logindomain));
      print "D loginuser=$loginuser, logindomain=$logindomain\n" if ($opt{'debug'});

      if (defined $config{'domainname_equiv'}{'map'}{$logindomain}) {
         $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain};
         print "D logindomain equiv to $logindomain\n" if ($opt{'debug'});
      }

      if (!is_localuser("$loginuser\@$logindomain") && -f "$config{'ow_sitesconfdir'}/$logindomain") {
         read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
         print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if ($opt{'debug'});
      }
      ow::auth::load($config{'auth_module'});
      print "D ow::auth::load $config{'auth_module'}\n" if ($opt{'debug'});

      update_virtuserdb();	# update index db of virtusertable

      ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
				=get_domain_user_userinfo($logindomain, $loginuser);
      if ($opt{'debug'}) {
         print "D get_domain_user_info()\n";
         print "D domain=$domain (auth_withdomain=$config{'auth_withdomain'})\n";
         print "D user=$user, realname=$userrealname\n";
         print "D uuid=$uuid, ugid=$ugid, homedir=$homedir\n";
      }

      if ($user eq "") {
         print "user $loginname doesn't exist\n" if (!$opt{'quiet'});
         next;
      }
      if ($user eq 'root' || $user eq 'toor'||
          $user eq 'daemon' || $user eq 'operator' || $user eq 'bin' ||
          $user eq 'tty' || $user eq 'kmem' || $user eq 'uucp') {
         print "D system user $user, skipped!\n" if ($opt{'debug'});
         next;
      }

      if ( $>!=$uuid &&
           $>!=0 &&	# setuid root is required if spool is located in system dir
           !$config{'use_homedirspools'} &&
          ($config{'mailspooldir'} eq "/var/mail" ||
           $config{'mailspooldir'} eq "/var/spool/mail")) {
         print "This operation is only available to root\n"; openwebmail_exit(0);
      }

      # load user config
      my $userconf="$config{'ow_usersconfdir'}/$user";
      $userconf="$config{'ow_usersconfdir'}/$domain/$user" if ($config{'auth_withdomain'});
      if ( -f "$userconf") {
         read_owconf(\%config, \%config_raw, "$userconf");
         print "D readconf $userconf\n" if ($opt{'debug'});
      }

      # override auto guessing domainanmes if loginame has domain
      if (${$config_raw{'domainnames'}}[0] eq 'auto' && $loginname=~/\@/) {
         $config{'domainnames'}=[ $logindomain ];
      }
      # override realname if defined in config
      if ($config{'default_realname'} ne 'auto') {
         $userrealname=$config{'default_realname'};
         print "D change realname to $userrealname\n" if ($opt{'debug'});
      }

      my $syshomedir=$homedir;	# keep this for later use
      my $owuserdir = ow::tool::untaint("$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/$user":$user));
      if ( !$config{'use_syshomedir'} ) {
         $homedir = $owuserdir;
         print "D change homedir to $homedir\n" if ($opt{'debug'});
      }
      if ($homedir eq '/') {
         print "D homedir is /, skipped!\n" if ($opt{'debug'});
      }

      if (defined $homedir_processed{$homedir}) {
         print "D $loginname homedir already processed, skipped!\n" if ($opt{'debug'});
         next;
      }
      $homedir_processed{$homedir}=1;

      $user=ow::tool::untaint($user);
      $uuid=ow::tool::untaint($uuid);
      $ugid=ow::tool::untaint($ugid);
      $homedir=ow::tool::untaint($homedir);

      # create domainhome for stuff not put in syshomedir
      if (!$config{'use_syshomedir'} || !$config{'use_syshomedir_for_dotdir'} ) {
         if ($config{'auth_withdomain'}) {
            my $domainhome=ow::tool::untaint("$config{'ow_usersdir'}/$domain");
            if (!-d $domainhome) {
               mkdir($domainhome, 0750) or die("Couldn't create domain homedir $domainhome");
               my $mailgid=getgrnam('mail');
               chown($uuid, $mailgid, $domainhome);
            }
         }
      }
      upgrade_20030323();
      # create owuserdir for stuff not put in syshomedir
      if (!$config{'use_syshomedir'} || !$config{'use_syshomedir_for_dotdir'} ) {
         if (!-d $owuserdir) {
            my $fgid=(split(/\s+/,$ugid))[0];
            if (mkdir ($owuserdir, 0700) && chown($uuid, $fgid, $owuserdir)) {
               writelog("create owuserdir - $owuserdir, uid=$uuid, gid=$fgid");
               print "D create owuserdir $owuserdir, uid=$uuid, gid=$fgid\n" if ($opt{'debug'});
            } else {
               print "D couldn't create $owuserdir ($!)\n" if ($opt{'debug'});
               next;
            }
         }
      }

      umask(0077);
      if ( $>==0 ) { # switch to uuid:mailgid if process is setuid to root
         my $mailgid=getgrnam('mail');	# for better compatibility with other mail progs
         ow::suid::set_euid_egids($uuid, $ugid, $mailgid);
         if ( $)!~/\b$mailgid\b/) {	# group mail doesn't exist?
            print "Set effective gid to mail($mailgid) failed!"; openwebmail_exit(0);
         }
      }
      print "D ruid=$<, euid=$>, rgid=$(, eguid=$)\n" if ($opt{'debug'});

      # locate existing .openwebmail
      find_and_move_dotdir($syshomedir, $owuserdir) if (!-d dotpath('/'));	# locate existing .openwebmail

      # get user release date
      my $user_releasedate=read_releasedatefile();

      if ( ! -d $homedir ) {
         print "D $homedir doesn't exist\n" if ($opt{'debug'});
         next;
      }

      my $folderdir=ow::tool::untaint("$homedir/$config{'homedirfolderdirname'}");
      if ( ! -d $folderdir ) {
         if (-f "$homedir/.openwebmailrc") {
            if (mkdir ($folderdir, 0700)) {
               writelog("create folderdir - $folderdir, euid=$>, egid=$)");
               print "D create folderdir $folderdir, euid=$>, egid=$<\n" if ($opt{'debug'});
               upgrade_20021218($user_releasedate);
            } else {
               print "D couldn't create $folderdir ($!)\n" if ($opt{'debug'});
               next;
            }
         } else {
            print "D $folderdir doesn't exist\n" if ($opt{'debug'});
            next;
         }
      }

      if ($user_releasedate ne "") {		# release file found
         check_and_create_dotdir(dotpath('/'));	# create dirs under ~/.openwebmail/
         if ($user_releasedate ne $config{'releasedate'}) {
            upgrade_all($user_releasedate);
            print "D do release upgrade...\n" if ($opt{'debug'});
            update_releasedatefile();
         }
         update_openwebmailrc($user_releasedate);
      }
      if ( ! -d dotpath('/') ) {
         print "D ".dotpath('/')." doesn't exist\n" if ($opt{'debug'});
         next;
      }

      # create dirs under ~/.openwebmail/
      check_and_create_dotdir(dotpath('/'));

      # remove stale folder db
      my (@validfolders, $inboxusage, $folderusage);
      getfolders(\@validfolders, \$inboxusage, \$folderusage);
      del_staledb($user, \@validfolders);

      %prefs = readprefs();

      if ($opt{'pop3'}) {
         my $ret=pop3_fetches($POP3_TIMEOUT);
         print "pop3_fetches($POP3_TIMEOUT) return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }
      if ($opt{'zap'}) {
         my $ret=clean_trash_spamvirus();
         print "clean_trash_spamvirus() return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }

      if ($opt{'ir'}) {
         my $ret=folderindex('rebuild', $opt{'ir'});
         print "folderindex('rebuild', $opt{'ir'}) return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      } elsif ($opt{'if'}) {
         my $ret=folderindex('fastrebuild', $opt{'if'});
         print "folderindex('fastrebuild', $opt{'if'}) return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      } elsif ($opt{'iv'}) {
         my $ret=folderindex('verify', $opt{'iv'});
         print "folderindex('verify', $opt{'iv'}) return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      } elsif ($opt{'id'}) {
         my $ret=folderindex('dump', $opt{'id'});
         print "folderindex('dump', $opt{'id'}) return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      } elsif ($opt{'iz'}) {
         my $ret=folderindex('zap', $opt{'iz'});
         print "folderindex('zap', $opt{'iz'}) return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }

      if ($opt{'size'}) {
         my $ret=checksize();
         print "checksize() return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }
      if ($opt{'mail'}||$opt{'pop3'}) {	# call checknewmail for pop3 because we want mail filtering
         my $ret=checknewmail();
         print "checknewmail() return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }
      if ($opt{'event'}) {
         my $ret=checknewevent();
         print "checknewevent() return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }
      if ($opt{'notify'}) {
         my $ret=checknotify();
         print "checknotify() return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }
      if ($opt{'unlock'}) {
         my $ret=unlockfiles();
         print "unlockfiles() return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }
      if ($opt{'convert_addressbooks'}) {
         loadlang("$prefs{'locale'}"); # for converted filename $lang_text{abook_converted}
         print "converting user $user addressbook..." if (!$opt{'quiet'});
         my $ret=convert_addressbook('user', (ow::lang::localeinfo($prefs{'locale'}))[6]);
         print "done.\n" if (!$opt{'quiet'});
      }

      $usercount++;
   }

   if ($usercount>0) {
      return 0;
   } else {
      return 1;
   }
}


sub folderindex {
   my ($op, $folder)=@_;
   my (@validfolders, $inboxusage, $folderusage);

   if ($folder eq 'ALL') {
      getfolders(\@validfolders, \$inboxusage, \$folderusage);
   } else {
      push(@validfolders, $folder);
   }

   foreach (@validfolders) {
      my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $_);
      my %FDB;

      if (! -f $folderfile) {
         print "$folderfile doesn't exist\n" if (!$opt{'quiet'});
         next;
      }

      # in case any error in dump, return immediately and do not proceed next
      if ($op eq "dump") {
         my %folderinfo; foreach (keys %is_internal_dbkey) { $folderinfo{$_}=0 }
         my (@messageids, @attr, $buff, $buff2, $headerlen);
         my $error=0;

         if (!ow::dbm::exist($folderdb)) {
            print "db $folderdb doesn't exist\n" if (!$opt{'quiet'});
            return -1;
         }
         @messageids=get_messageids_sorted_by_offset($folderdb);

         if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB)) {
            print "Couldn't get read lock on $folderfile\n" if (!$opt{'quiet'});
            return -1;
         }
         if (!ow::dbm::open(\%FDB, $folderdb, LOCK_SH)) {
            print "Couldn't get read lock on db $folderdb\n" if (!$opt{'quiet'});
            ow::filelock::lock($folderfile, LOCK_UN);
            return -1;
         }
         sysopen(FOLDER, $folderfile, O_RDONLY);

         for(my $i=0; $i<=$#messageids; $i++) {
            @attr=get_message_attributes($messageids[$i], $folderdb);
            next if ($#attr<0);        # msg not found in db

            $headerlen=$attr[$_HEADERSIZE]||6;
            seek(FOLDER, $attr[$_OFFSET], 0);
            read(FOLDER, $buff, $headerlen);
            seek(FOLDER, $attr[$_OFFSET]+$attr[$_SIZE], 0);
            read(FOLDER, $buff2, 6);

            my @check=(0,0,0);
            $check[0]=1 if ( $buff=~/^From / );
            $check[1]=1 if ( $attr[$_HEADERCHKSUM] eq ow::tool::calc_checksum(\$buff) );
            $check[2]=1 if ( $buff2=~/^From / || $buff2 eq "" );

            $error++ if (!$check[0] || !$check[1] || !$check[2]);

            printf ("%s%s%s %4d, OFFSET:%8d, SIZE:%8d, HSIZE:%4d, DATE:%s, RECVDATE:%s, CHARSET:%s, STAT:%s, MSGID:%s, FROM:%s, TO:%s, SUB:%s\n",
                    $check[0]?'+':'-', $check[1]?'+':'-', $check[2]?'+':'-',
                    $i+1, $attr[$_OFFSET], $attr[$_SIZE], $attr[$_HEADERSIZE], $attr[$_DATE], $attr[$_RECVDATE], $attr[$_CHARSET], $attr[$_STATUS],
                    substr($messageids[$i],0,50), $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]) if (!$opt{'quiet'});
            #printf ("buf=$buff, buff2=$buff2\n");

            $folderinfo{'ALLMESSAGES'}++;
            if ($attr[$_STATUS]=~/Z/i) {
               $folderinfo{'ZAPMESSAGES'}++; $folderinfo{'ZAPSIZE'}+=$attr[$_SIZE];
            } elsif (is_internal_subject($attr[$_SUBJECT])) {
               $folderinfo{'INTERNALMESSAGES'}++; $folderinfo{'INTERNALSIZE'}+=$attr[$_SIZE];
            } elsif ($attr[$_STATUS]!~/R/i) {
               $folderinfo{'NEWMESSAGES'}++;
            }
         }

         $folderinfo{'DBVERSION'}=$_DBVERSION;
         $folderinfo{'METAINFO'}=ow::tool::metainfo($folderfile);
         if (!$opt{'quiet'}) {
            print "\n";
            foreach my $key (qw(DBVERSION METAINFO ALLMESSAGES NEWMESSAGES INTERNALMESSAGES INTERNALSIZE ZAPMESSAGES ZAPSIZE)) {
               my $sign="+++";
               if ($FDB{$key} ne $folderinfo{$key}) {
                  $sign="---"; $error++;
               }
               printf("$sign %-16s db:%-30s, folder:%-30s\n", $key, $FDB{$key}, $folderinfo{$key});
            }
         }
         ow::dbm::close(\%FDB, $folderdb);
         close(FOLDER);
         ow::filelock::lock($folderfile, LOCK_UN);

         print "$error errors in db $folderdb\n" if (!$opt{'quiet'});

      } elsif ($op eq "zap") {
         if (!ow::filelock::lock($folderfile, LOCK_EX)) {
            print "Couldn't get write lock on $folderfile\n" if (!$opt{'quiet'});
            next;
         }
         my $ret=folder_zapmessages($folderfile, $folderdb);
         $ret=folder_zapmessages($folderfile, $folderdb) if ($ret==-9||$ret==-10);
         if ($ret>=0) {
            print "$ret messages have been zapped from $folder\n" if (!$opt{'quiet'});
         } elsif ($ret<0) {
            print "zap folder return error $ret\n" if (!$opt{'quiet'});
         }
         ow::filelock::lock($folderfile, LOCK_UN);

      } else {
         if (!ow::filelock::lock($folderfile, LOCK_EX)) {
            print "Couldn't get write lock on $folderfile\n" if (!$opt{'quiet'});
            next;
         }
         my $ret;
         if ($op eq "verify") {
            $ret=update_folderindex($folderfile, $folderdb);
         } elsif ($op eq "rebuild") {
            ow::dbm::unlink($folderdb);
            $ret=update_folderindex($folderfile, $folderdb);
         } elsif ($op eq "fastrebuild") {
            if (!ow::dbm::open(\%FDB, $folderdb, LOCK_EX, 0600)) {
               print "Couldn't get write lock on db $folderdb\n" if (!$opt{'quiet'});
               ow::filelock::lock($folderfile, LOCK_UN);
               next;
            }
            @FDB{'METAINFO', 'LSTMTIME'}=('ERR', -1);
            ow::dbm::close(\%FDB, $folderdb);
            $ret=update_folderindex($folderfile, $folderdb);
         }
         ow::filelock::lock($folderfile, LOCK_UN);

         if (!$opt{'quiet'}) {
            if ($ret<0) {
               print "db $folderdb $op error $ret\n";
            } elsif ($op ne 'verify' || ($op eq 'verify' && $ret==0)) {
               print "db $folderdb $op ok\n";
            } else {
               print "db $folderdb $op & updated ok\n";
            }
         }
      }
   }
   return 0;
}


sub clean_trash_spamvirus {
   my %reserveddays=('mail-trash' => $prefs{'trashreserveddays'},
                     'spam-mail'  => $prefs{'spamvirusreserveddays'},
                     'virus-mail' => $prefs{'spamvirusreserveddays'} );
   my (@f, $msg);
   push(@f, 'virus-mail') if ($config{'has_virusfolder_by_default'});
   push(@f, 'spam-mail') if ($config{'has_spamfolder_by_default'});
   push(@f, 'mail-trash');
   foreach my $folder (@f) {
      my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
      if (ow::filelock::lock($folderfile, LOCK_EX)) {
         my $deleted=delete_message_by_age($reserveddays{$folder}, $folderdb, $folderfile);
         if ($deleted > 0) {
            $msg.=', ' if ($msg ne '');
            $msg.="$deleted msg deleted from $folder";
         }
         ow::filelock::lock($folderfile, LOCK_UN);
      }
   }
   if ($msg ne '') {
      writelog("clean trash/spam/virus - $msg");
      writehistory("clean trash/spam/virus - $msg");
      print "clean trash/spam/virus - $msg\n" if (!$opt{'quiet'});
   }
   return 0;
}


sub checksize {
   return 0 if (!$config{'quota_module'});
   ow::quota::load($config{'quota_module'});

   my ($ret, $errmsg, $quotausage, $quotalimit)=ow::quota::get_usage_limit(\%config, $user, $homedir, 0);
   if ($ret<0) {
      print "$errmsg\n" if (!$opt{'quiet'});
      return $ret;
   }
   $quotalimit=$config{'quota_limit'} if ($quotalimit<0);
   return 0 if (!$quotalimit);

   my $i=0;
   while ($quotausage>$quotalimit && $i<2) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
      return 0 if ($quotausage<=$quotalimit);

      my (@validfolders, $inboxusage, $folderusage);
      getfolders(\@validfolders, \$inboxusage, \$folderusage);

      my $sizetocut=($quotausage-$quotalimit*0.9)*1024;
      if ($config{'delmail_ifquotahit'} && !$config{'delfile_ifquotahit'}) {
         cutfoldermails($sizetocut, $user, @validfolders);
      } elsif (!$config{'delmail_ifquotahit'} && $config{'delfile_ifquotahit'}) {
         my $webdiskrootdir=$homedir.absolute_vpath("/", $config{'webdisk_rootpath'});
         cutdirfiles($sizetocut, $webdiskrootdir);
      } else {	# both delmail/delfile are on or off, choose by percent
         if ($folderusage>$quotausage*0.5) {
            cutfoldermails($sizetocut, $user, @validfolders);
         } else {
            my $webdiskrootdir=$homedir.absolute_vpath("/", $config{'webdisk_rootpath'});
            cutdirfiles($sizetocut, $webdiskrootdir);
         }
      }
      $i++;
   }
   return 0;
}


sub checknewmail {
   my ($spoolfile, $folderdb)=get_folderpath_folderdb($user, 'INBOX');
   print "$loginname " if (!$opt{'quiet'});

   if ($config{'authpop3_getmail'}) {
      my $authpop3book=dotpath('authpop3.book');
      my %accounts;
      if (-f "$authpop3book" && readpop3book("$authpop3book", \%accounts)>0) {
         my $login=$user;  $login.="\@$domain" if ($config{'auth_withdomain'});
         my ($pop3ssl, $pop3passwd, $pop3del)
		=(split(/\@\@\@/, $accounts{"$config{'authpop3_server'}:$config{'authpop3_port'}\@\@\@$login"}))[2,4,5];

         my ($ret, $errmsg) = fetchmail($config{'authpop3_server'}, $config{'authpop3_port'}, $pop3ssl,
                                        $login, $pop3passwd, $pop3del);
         if ($ret<0) {
            writelog("pop3 error - $errmsg at $login\@$config{'authpop3_server'}:$config{'authpop3_port'}");
         }
      }
   }

   if ( ! -f $spoolfile || (stat($spoolfile))[7]==0 ) {
      print "has no mail\n" if (!$opt{'quiet'});
      return 0;
   }

   update_folderindex($spoolfile, $folderdb);

   # filtermessage in background
   filtermessage($user, 'INBOX', \%prefs);

   if (!$opt{'quiet'}) {
      my %FDB;
      if (!ow::dbm::open(\%FDB, $folderdb, LOCK_SH)) {
         print "couldn't get read lock on db $folderdb\n";
         return -1;
      }
      my $newmessages=$FDB{'NEWMESSAGES'};
      my $oldmessages=$FDB{'ALLMESSAGES'}-$FDB{'ZAPMESSAGES'}-$FDB{'INTERNALMESSAGES'}-$newmessages;
      ow::dbm::close(\%FDB, $folderdb);

      if ($newmessages == 1 ) {
         print "has 1 new mail\n";
      } elsif ($newmessages > 1 ) {
         print "has $newmessages new mails\n";
      } elsif ($oldmessages == 1 ) {
         print "has 1 mail\n";
      } elsif ($oldmessages > 1 ) {
         print "has $oldmessages mails\n";
      } else {
         print "has no mail\n";
      }
   }
   return 0;
}


sub checknewevent {
   my ($newevent, $oldevent);

   my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($wdaynum, $year, $month, $day, $hour, $min)=(ow::datetime::seconds2array($localtime))[6,5,4,3,2,1];
   $year+=1900; $month++;
   my $hourmin=sprintf("%02d%02d", $hour, $min);

   my $dow=$ow::datetime::wday_en[$wdaynum];
   my $date=sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

   my (%items, %indexes);
   if ( readcalbook(dotpath('calendar.book'), \%items, \%indexes, 0)<0 ) {
      return -1;
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'locale'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

   my @indexlist=();
   push(@indexlist, @{$indexes{$date}}) if (defined $indexes{$date});
   push(@indexlist, @{$indexes{'*'}})   if (defined $indexes{'*'});
   @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

   for my $index (@indexlist) {
      if ($date=~/$items{$index}{'idate'}/ ||
          $date2=~/$items{$index}{'idate'}/ ||
          ow::datetime::easter_match($year,$month,$day,$items{$index}{'idate'}) ) {
         if ($items{$index}{'starthourmin'}>=$hourmin ||
             $items{$index}{'endhourmin'}>$hourmin ||
             $items{$index}{'starthourmin'}==0) {
            $newevent++;
         } else {
            $oldevent++;
         }
      }
   }

   if (!$opt{'quiet'}) {
      if ($newevent > 0 ) {
         print "$loginname has new event\n";
      } elsif ($oldevent > 0 ) {
         print "$loginname has event\n";
      }
   }
   return 0;
}


sub checknotify {
   my %message=();

   my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($wdaynum, $year, $month, $day, $hour, $min)=(ow::datetime::seconds2array($localtime))[6,5,4,3,2,1];
   $year+=1900; $month++;

   my $dow=$ow::datetime::wday_en[$wdaynum];
   my $date=sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

   my $notifycheckfile=dotpath('notify.check');

   my $checkstart="0000";
   if ( -f $notifycheckfile ) {
      sysopen(NOTIFYCHECK, $notifycheckfile, O_RDONLY) or return -1; # read err
      my $lastcheck=<NOTIFYCHECK>;
      close(NOTIFYCHECK);
      $checkstart=$1 if ($lastcheck=~/$date(\d\d\d\d)/);
   }

   my $checkend="2400";
   my ($wdaynum2, $year2, $month2, $day2, $hour2, $min2)=
      (ow::datetime::seconds2array($localtime+$config{'calendar_email_notifyinterval'}*60))[6,5,4,3,2,1];
   $checkend=sprintf("%02d%02d", $hour2, $min2) if ( $day2 eq $day );

   return 0 if ($checkend<=$checkstart);

   sysopen(NOTIFYCHECK, $notifycheckfile, O_WRONLY|O_TRUNC|O_CREAT) or return -2; # write err
   print NOTIFYCHECK "$date$checkend";
   close(NOTIFYCHECK);

   my (%items, %indexes);

   if ( readcalbook(dotpath('calendar.book'), \%items, \%indexes, 0)<0 ) {
      return -3;
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'locale'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

   my @indexlist=();
   push(@indexlist, @{$indexes{$date}}) if (defined $indexes{$date});
   push(@indexlist, @{$indexes{'*'}})   if (defined $indexes{'*'});
   @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

   my $future_items=0;
   for my $index (@indexlist) {
      if ( $items{$index}{'email'} &&
           ($date=~/$items{$index}{'idate'}/  ||
            $date2=~/$items{$index}{'idate'}/ ||
            ow::datetime::easter_match($year,$month,$day,$items{$index}{'idate'})) ) {
         if ( ($items{$index}{'starthourmin'}>=$checkstart &&
               $items{$index}{'starthourmin'}<$checkend) ||
              ($items{$index}{'starthourmin'}==0 &&
               $checkstart eq "0000") ) {
            my $itemstr;
            if ($items{$index}{'starthourmin'}==0) {
               $itemstr="##:##\n";
            } elsif ($items{$index}{'endhourmin'}==0) {
               $itemstr=hourmin($items{$index}{'starthourmin'})."\n";
            } else {
               $itemstr=hourmin($items{$index}{'starthourmin'})."-".hourmin($items{$index}{'endhourmin'})."\n";
            }
            $itemstr.=(iconv($items{$index}{'charset'}, (ow::lang::localeinfo($prefs{'locale'}))[6], $items{$index}{'string'}))[0]."\n";
            $itemstr.=$items{$index}{'link'}."\n" if ($items{$index}{'link'});

            if (defined $message{$items{$index}{'email'}}) {
               $message{$items{$index}{'email'}} .= $itemstr;
            } else {
               $message{$items{$index}{'email'}} = $itemstr;
            }
         }
         if ($items{$index}{'starthourmin'}>=$checkend) {
            $future_items++;
         }
      }
   }

   if ($future_items==0) { # today has no more item to notify, set checkend to 2400
      if (sysopen(NOTIFYCHECK, $notifycheckfile, O_WRONLY|O_TRUNC|O_CREAT)) {
         print NOTIFYCHECK $date."2400";
         close(NOTIFYCHECK);
      }
   }

   my ($m, $d)=(sprintf("%02d",$month), sprintf("%02d",$day));
   my $title=$prefs{'dateformat'}||"mm/dd/yyyy";
   $title=~s/yyyy/$year/; $title=~s/mm/$m/; $title=~s/dd/$d/;
   $title.=" (".hourmin($checkstart)."-".hourmin($checkend).")\n\n";
   my $from=$prefs{'email'};
   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, dotpath('from.book'));
   my $realname=$userfrom{$from};
   foreach my $email (keys %message) {
      my $date = ow::datetime::dateserial2datefield(ow::datetime::gmtime2dateserial(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
      my $ret=send_mail($from, $realname, $email, $date, "calendar notification", $title.$message{$email});
      if (!$opt{'quiet'}) {
         print "mailing notification to $email for $loginname";
         print ", return $ret" if ($ret!=0);
         print "\n";
      }
   }
   return 0;
}


sub hourmin {
   return("$1:$2") if ($_[0] =~ /(\d+)(\d{2})$/);
   return($_[0]);
}


sub send_mail {
   my ($from, $realname, $to, $date, $subject, $body)=@_;

   $from =~ s/['"]/ /g;  # Get rid of shell escape attempts
   $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts

   ($realname =~ /^(.+)$/) && ($realname = '"'.$1.'"');
   foreach ($from, $to, $date) { $_=ow::tool::untaint($_) }

   # fake a messageid for this message
   my $fakedid = ow::datetime::gmtime2dateserial().'.M'.int(rand()*100000);
   $fakedid="<$fakedid".'@'."${$config{'domainnames'}}[0]>";

   my $smtp;
   # try to connect to one of the smtp servers available
   my $smtpserver;
   foreach $smtpserver (@{$config{'smtpserver'}}) {
      my $connectmsg = "send message - trying to connect to smtp server $smtpserver:$config{'smtpport'}";
      writelog($connectmsg);

      $smtp=Net::SMTP->new($smtpserver,
                           Port => $config{'smtpport'},
                           Timeout => 60,
                           Hello => ${$config{'domainnames'}}[0]);

      if ($smtp) {
         $connectmsg = "send message - connected to smtp server $smtpserver:$config{'smtpport'}";
         writelog($connectmsg);
         last;
      } else {
         $connectmsg = "send message - error connecting to smtp server $smtpserver:$config{'smtpport'}";
         writelog($connectmsg);
      }
   }

   unless ($smtp) {
      # we didn't connect to any smtp servers successfully
      die(
           qq|Couldn't open SMTP servers |.
           join(", ", @{$config{'smtpserver'}}).
           qq| at port $config{'smtpport'}!|
         );
   }

   # SMTP SASL authentication (PLAIN only)
   if ($config{'smtpauth'}) {
      my $auth = $smtp->supports("AUTH");
      $smtp->auth($config{'smtpauth_username'}, $config{'smtpauth_password'}) or
         die "SMTP server $smtpserver error - ".$smtp->message;
   }

   $smtp->mail($from);

   my @recipients=();
   foreach (ow::tool::str2list($to,0)) {
      my $email=(ow::tool::email2nameaddr($_))[1];
      next if ($email eq "" || $email=~/\s/);
      push (@recipients, $email);
   }
   if (! $smtp->recipient(@recipients, { SkipBad => 1 }) ) {
      $smtp->reset();
      $smtp->quit();
      return -1;
   }

   my $prefcharset = (ow::lang::localeinfo($prefs{'locale'}))[6];

   $smtp->data();
   $smtp->datasend("From: ".ow::mime::encode_mimewords("$realname <$from>", ('Charset'=>"$prefcharset"))."\n",
                   "To: ".ow::mime::encode_mimewords($to, ('Charset'=>"$prefcharset"))."\n");
   $smtp->datasend("Reply-To: ".ow::mime::encode_mimewords($prefs{'replyto'}, ('Charset'=>"$prefcharset"))."\n") if ($prefs{'replyto'});

   $smtp->datasend("Subject: ".ow::mime::encode_mimewords($subject, ('Charset'=>"$prefcharset"))."\n",
                   "Date: $date\n",
                   "Message-Id: $fakedid\n",
                   safexheaders($config{'xheaders'}),
                   "MIME-Version: 1.0\n",
                   "Content-Type: text/plain; charset=$prefcharset\n\n",
                   $body, "\n\n");
   $smtp->datasend($config{'mailfooter'}, "\n") if ($config{'mailfooter'}=~/[^\s]/);

   if (!$smtp->dataend()) {
      $smtp->reset();
      $smtp->quit();
      return -2;
   }
   $smtp->quit();

   return 0;
}

sub pop3_fetches {
   my $timeout=$_[0];
   my ($spoolfile, $header)=get_folderpath_folderdb($user, 'INBOX');
   # create system spool file /var/mail/xxxx
   if ( ! -f "$spoolfile" ) {
      sysopen(F, $spoolfile, O_WRONLY|O_APPEND|O_CREAT, 0600); close(F);
   }

   my %accounts=();
   my $pop3bookfile=dotpath('pop3.book');

   return 0 if (!-f $pop3bookfile);
   return -1 if (readpop3book($pop3bookfile, \%accounts) <0);

   foreach (values %accounts) {
      my ($pop3host,$pop3port,$pop3ssl, $pop3user,$pop3passwd, $pop3del, $enable,)=split(/\@\@\@/,$_);
      next if (!$enable);

      my $disallowed=0;
      foreach ( @{$config{'pop3_disallowed_servers'}} ) {
         if ($pop3host eq $_) {
            $disallowed=1; last;
         }
      }
      next if ($disallowed);

      my ($ret, $errmsg) = fetchmail($pop3host, $pop3port, $pop3ssl,
                                     $pop3user, $pop3passwd, $pop3del);
      if ( $ret<0) {
         writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
      }
   }

   return 0;
}

sub unlockfiles {
   my @cmd;
   my $lsofbin=ow::tool::findsbin('lsof')||ow::tool::findbin('lsof');
   if ($lsofbin eq '') {
      print "Program lsof not found, please install lsof first";
      return 1;
   }

   my $folderdir=ow::tool::untaint("$homedir/$config{'homedirfolderdirname'}");
   my $dbdir=ow::tool::untaint(dotpath('/'));
   my $spooldir=(get_folderpath_folderdb($user, 'INBOX'))[0]; $spooldir=~s!(.*)/.*!$1!;

   push(@cmd, $lsofbin, '+w', '-l', '-S2', '-Di');
   foreach ($spooldir, $folderdir, $dbdir, $config{'ow_etcdir'}) {
      push(@cmd, '+d'.$_);
   }
   push(@cmd, '-a', '-d^cwd');

   # since lsof read/write tmp cache file with ruid no matter what euid is
   # so we set euid=root or euid won't have enough privilege to read/write lsof cache file
   my $euid=$>; $>=0 if ($<==0);
   my ($stdout, $stderr, $exit, $sig)=ow::execute::execute(@cmd);
   $>=$euid if ($<==0);

   my @pids;
   foreach (split(/\n/, $stdout)) {
      my ($cmd, $pid, $puid, $fd, $type, $device, $size, $mode, $fname)=split(/\s+/);
      next if ($puid!=$euid);
      next if ($fd!~/\d+([A-Za-z])([A-Za-z])/);
      my ($rw, $lock)=($1, $2);
      print "program=$cmd, pid=$pid, lock=$lock, file=$fname\n";
      push(@pids, ow::tool::untaint($pid));
   }
   if ($#pids>=0) {
      print "\nKill above processes to remove filelock for $user? (y/N) ";
      $_=<STDIN>;
      kill 9, @pids if (/y/i);
   }
   return 0;
}
