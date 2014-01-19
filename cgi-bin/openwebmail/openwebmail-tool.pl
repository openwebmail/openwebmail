#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2009-2014, The OpenWebMail Project
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

# openwebmail-tool.pl - command tool for mail/event/notify/index...

use strict;
use warnings FATAL => 'all';

use vars qw($SCRIPT_DIR);

if (-f '/etc/openwebmail_path.conf') {
   my $pathconf = '/etc/openwebmail_path.conf';
   open(F, $pathconf) or die "Cannot open $pathconf: $!";
   my $pathinfo = <F>;
   close(F) or die "Cannot close $pathconf: $!";
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die qq|

   OpenWebMail is unable to locate itself on this system.
   Please put the path of the openwebmail CGI directory as
   the first line of file /etc/openwebmail_path.conf.

   For example, if the script is:

   /usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl

   then the content of /etc/openwebmail_path.conf should be:

   /usr/local/www/cgi-bin/openwebmail/

| if $SCRIPT_DIR eq '';

push (@INC, $SCRIPT_DIR);
push (@INC, "$SCRIPT_DIR/lib");

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH} = '/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load non-OWM libraries
use Fcntl qw(:DEFAULT :flock);
use Net::SMTP;
use Cwd 'abs_path';

# load OWM libraries
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
use vars qw(%prefs $po);

# extern vars
use vars qw($_DBVERSION);	        # defined in maildb.pl
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES);
use vars qw(%is_config_option);		# from ow-shared.pl
use vars qw(%is_internal_dbkey);	# from maildb.pl

# local globals
use vars qw($POP3_TIMEOUT %opt $startup_ruid);

# speedycgi guarentees a persistent copy is used again
# only if the script is executed by same user(ruid),
# since routine openwebmail_requestbegin() clears ruid of persistence copy,
# we store the ruid in $startup_ruid:
$startup_ruid = $< unless defined $startup_ruid;

$POP3_TIMEOUT = 20;

%opt = ('null' => 1);
$default_logindomain = '';

# by default, the $startup_ruid (ruid of the user running this script) is used as runtime euid
# but euid $> is used if operation is either from inetd, -m (query mail status ) or -e(query event status)
my $euid_to_use = $startup_ruid;
my @list = ();

openwebmail_requestbegin();

# no buffer on stdout
local $| = 1;

if (defined $ARGV[0] && $ARGV[0] eq '--') {
   # called by inetd
   push(@list, $ARGV[1]);
   $opt{'mail'}=1;
   $opt{'event'}=1;
   $opt{'null'}=0;
   $euid_to_use=$>;
} else {
   for (my $i=0; $i<=$#ARGV; $i++) {
      if ($ARGV[$i] eq "--init") {
         $opt{'init'}=1;
      } elsif ($ARGV[$i] eq "--uninit") {
         $opt{'uninit'}=1;
      } elsif ($ARGV[$i] eq "--test" || $ARGV[$i] eq "-w") {
         $opt{'test'}=1;
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
         $opt{'iv'}='ALL';
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-id") {
         $i++;
         $opt{'id'}=$ARGV[$i];
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-iv") {
         $i++;
         $opt{'iv'}=$ARGV[$i];
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-if") {
         $i++;
         $opt{'if'}=$ARGV[$i];
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-ir") {
         $i++;
         $opt{'ir'}=$ARGV[$i];
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-iz") {
         $i++;
         $opt{'iz'}=$ARGV[$i];
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--mail" || $ARGV[$i] eq "-m") {
         $opt{'mail'}=1;
         $opt{'null'}=0;
         $euid_to_use=$>;
      } elsif ($ARGV[$i] eq "--event" || $ARGV[$i] eq "-e") {
         $opt{'event'}=1;
         $opt{'null'}=0;
         $euid_to_use=$>;
      } elsif ($ARGV[$i] eq "--notify" || $ARGV[$i] eq "-n") {
         $opt{'notify'}=1;
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--pop3" || $ARGV[$i] eq "-p") {
         $opt{'pop3'}=1;
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--size" || $ARGV[$i] eq "-s") {
         $opt{'size'}=1;
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--unlock" || $ARGV[$i] eq "-u") {
         $opt{'unlock'}=1;
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--zaptrash" || $ARGV[$i] eq "-z") {
         $opt{'zap'}=1;
         $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "--convert_addressbooks" || $ARGV[$i] eq "-c") {
         $opt{'convert_addressbooks'}=1;
         $opt{'null'}=0;
      } else {
         push(@list, $ARGV[$i]);
      }
   }
}

$>=$euid_to_use;

# load the default config, but don't merge it into the config hash yet
# because there may be paths that get changed in the custom config
load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");

if (-f "$SCRIPT_DIR/etc/openwebmail.conf") {
   # load the custom config over the default config and merge everything
   read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
   print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if $opt{debug};
} else {
   # there is no custom config, so just do the merge with the default config
   read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
}

$logindomain=$default_logindomain||ow::tool::hostname();
$logindomain=lc(safedomainname($logindomain));
if (defined $config{'domainname_equiv'}{'map'}{$logindomain}) {
   print "D domain equivalence found: $logindomain -> $config{'domainname_equiv'}{'map'}{$logindomain}\n" if $opt{debug};
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain};
}

if ( -f "$config{'ow_sitesconfdir'}/$logindomain") {
   read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if $opt{debug};
}

%prefs = readprefs();
$po = loadlang($prefs{locale}); # for converted filename $lang_text{abook_converted}

writelog("debug_request :: request tool begin, argv=" . join(' ', @ARGV)) if $config{debug_request};

my $retval=0;
if ($opt{'init'}) {
   $retval=init();
} elsif ($opt{'uninit'}) {
   $retval=uninit();
} elsif ($opt{'test'}) {
   $retval=do_test();
} elsif ($opt{'thumbnail'}) {
   $retval=makethumbnail(\@list);
} else {
   if ($opt{'convert_addressbooks'} && $>==0) {	# only allow root to convert globalbook
      print "converting GLOBAL addressbook..." unless $opt{quiet};
      $retval=convert_addressbook('global', (ow::lang::localeinfo($prefs{locale}))[4]);
      if ($retval<0) {
         print "error:$@. EXITING\n";
         openwebmail_exit($retval);
      }
      print "done.\n" unless $opt{quiet};
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
writelog("debug_request :: request tool end, argv=" . join(' ', @ARGV)) if $config{debug_request};

openwebmail_exit($retval);

########## showhelp ##############################################
sub showhelp {
   print qq|
Syntax: openwebmail-tool.pl --init [options]
        openwebmail-tool.pl --test
        openwebmail-tool.pl -t [options] [image1 image2 ...]
        openwebmail-tool.pl [options] [user1 user2 ...]

common options:
 -q, --quiet  \t quiet, no output
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
 --uninit      \t remove the initial files and directories needed for openwebmail to operate
 -w, --test    \t run openwebmail-tool but don't write any files or make changes

ps: <folder> can be INBOX, ALL or folder filename

|;
   return 1;
}

########## init ##################################################
sub init {
   print "\n";

   my $err = do_test(1);

   if ($err < 0) {
      print qq|And execute '$SCRIPT_DIR/openwebmail-tool.pl --init' again!\n\n|.
            qq|ps: If you are running openwebmail in persistent mode,\n|.
            qq|    don't forget to 'touch openwebmail*.pl', so speedycgi\n|.
            qq|    will reload all scripts, modules and conf files in --init.\n\n|;
      return $err;
   }

   if ($] gt "5.011005") {
      print qq|The version of Perl on your system ($]) does not support set user id.\n|.
            qq|Attempting to wrap the openwebmail perl files in a C wrapper to enable set\n|.
            qq|user id capability...\n\n|;

      my $compiler = -x '/usr/bin/cc'        ? '/usr/bin/cc'        :
                     -x '/usr/bin/gcc'       ? '/usr/bin/gcc'       :
                     -x '/usr/local/bin/gcc' ? '/usr/local/bin/gcc' :
                     die "No C compiler found. Please install a C compiler and try again.";

      print "   Found C compiler $compiler\n";

      opendir(DIR, $SCRIPT_DIR) or die "Cannot open directory: $SCRIPT_DIR";
      my @files = grep { -f "$SCRIPT_DIR/$_" && m/^openwebmail.*\.pl$/ } readdir(DIR);
      closedir(DIR) or die "Cannot close directory: $SCRIPT_DIR";

      chdir($SCRIPT_DIR) or die "Cannot change directory to: $SCRIPT_DIR";

      foreach my $file (@files) {
         $file = ow::tool::untaint($file);
         print "   wrapping file: $file...";

         if (-f ".$file") {
            print "wrapped file already exists, skipping\n";
            next;
         }

         my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($file);
         chmod $mode & 01777, $file; # wipe out set[ug]id bits
         rename($file, ".$file") or die "Cannot rename file: $file -> .$file";
         open(C,">.tmp$$.c") || die "Cannot open file: .tmp$$.c";
         print C '
                  main(argc,argv)
                  int argc;
                  char **argv;
                  {
                     execv("' . abs_path(".$file") . '",argv);
                  }
                 ' . "\n";
         close C;
         system($compiler, ".tmp$$.c", '-o', $file);
         die "Compile error for .tmp$$.c: $?" if $?;
         chmod $mode, $file;
         chown $uid, $gid, $file;
         unlink ".tmp$$.c";
         print "done\n";
      }

      print "\n";
   }

   foreach my $table ('b2g', 'g2b', 'lunar') {
      if ( $config{$table.'_map'} ) {
         my $tabledb="$config{'ow_mapsdir'}/$table";
         my $err=0;
         if (ow::dbm::existdb($tabledb)) {
            my %T;
            if (!ow::dbm::opendb(\%T, $tabledb, LOCK_SH) ||
                !ow::dbm::closedb(\%T, $tabledb) ) {
               ow::dbm::unlinkdb($tabledb);
               print "delete old db $tabledb\n";
            }
         }
         if ( !ow::dbm::existdb($tabledb)) {
            die "$config{$table.'_map'} not found" if (!-f $config{$table.'_map'});
            print "creating db $config{'ow_mapsdir'}/$table ...";
            $err=-2 if ($table eq 'b2g' and mkdb_b2g()<0);
            $err=-3 if ($table eq 'g2b' and mkdb_g2b()<0);
            $err=-4 if ($table eq 'lunar' and mkdb_lunar()<0);
            if ($err < 0) {
               print "error!\n";
               return $err;
            }
            print "done.\n";
         }
      }
   }

   %prefs = readprefs();	# send_mail() uses $prefs{...}

   my $id = $ENV{'USER'} || $ENV{'LOGNAME'} || getlogin || (getpwuid($>))[0];
   my $hostname=ow::tool::hostname();
   my $realname=(getpwnam($id))[6]||$id;
   my $to="stats\@openwebmail.acatysmoof.com";
   my $date = ow::datetime::dateserial2datefield(ow::datetime::gmtime2dateserial(), $config{'default_timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my $subject="site report - $hostname";
   my $os;
   if ( -f "/usr/bin/uname") {
      $os=`/usr/bin/uname -srm`;
      chomp($os);
   } else {
      $os=`/bin/uname -srm`;
      chomp($os);
   }
   my $content=qq|OS: $os\n|.
               qq|Perl: $]\n|.
               qq|WebMail: $config{'name'} $config{'version'} $config{'releasedate'} revision $config{revision}\n|;

   if ($opt{'yes'}) {
      print qq|$content\n|.
             qq|sending site report...\n|;
      send_mail("$id\@$hostname", $realname, $to, $date, $subject, "$content \n");
   } elsif ($opt{'no'} or $opt{'debug'}) {
      print qq|$content\n|.
             qq|No site report sent.\n|;
   } else {
      print qq|\nWelcome to OpenWebMail!\n\n|.
            qq|This program is going to send a short message back to the developers\n|.
            qq|to give us statistics for future development. The content to be sent is:\n\n|.
            qq|$content\n|.
            qq|Send the site report?(Y/n) |;
      $_ = <STDIN>;
      if ($_ !~ m/n/i) {
         print qq|sending report...\n|;
         send_mail("$id\@$hostname", $realname, $to, $date, $subject, "$content \n");
         print qq|report sent successfully.\n|;
      } else {
         print "\n";
      }
   }
   print qq|\nShow your support for OpenWebMail on Ohloh:\n| .
         qq|http://www.ohloh.net/p/openwebmail\n\n| .
         qq|Thank you.\n\n|;
   return 0;
}

sub uninit {
   # put openwebmail back to its initial state
   # this is intended for developers who need to set things
   # back to default before they commit code back to git

   # put dot files back to non-dot names
   if ($] gt "5.011005") {
      opendir(DIR, $SCRIPT_DIR) or die "Cannot open directory: $SCRIPT_DIR";
      my @dotfiles = grep { -f "$SCRIPT_DIR/$_" && m/^\.openwebmail.*\.pl$/ } readdir(DIR);
      closedir(DIR) or die "Cannot close directory: $SCRIPT_DIR";

      chdir($SCRIPT_DIR) or die "Cannot change directory to: $SCRIPT_DIR";

      foreach my $dotfile (@dotfiles) {
         $dotfile = ow::tool::untaint($dotfile);

         my ($file) = $dotfile =~ m/^\.(openwebmail.*\.pl$)/;

         print "moving $dotfile -> $file...";
         rename($dotfile,$file) or die "Cannot rename $dotfile to $file";
         print "done\n";
      }

      print "\n";
   }

   # remove db files
   foreach my $table ('b2g', 'g2b', 'lunar') {
      if ( $config{$table.'_map'} ) {
         my $tabledb = "$config{ow_mapsdir}/$table";
         if (ow::dbm::existdb($tabledb)) {
            ow::dbm::unlinkdb($tabledb);
            print "delete db $tabledb\n";
         }
      }
   }

   # remove virtusertable maps
   opendir(DIR, $config{ow_mapsdir}) or die "Cannot open directory: $config{ow_mapsdir}";
   my @virtdbs = sort grep { -f "$config{ow_mapsdir}/$_" && m/^.*virtusertable.*\.db$/ } readdir(DIR);
   closedir(DIR) or die "Cannot close directory: $config{ow_mapsdir}";

   foreach my $virtdb (@virtdbs) {
      $virtdb = ow::tool::untaint("$config{ow_mapsdir}/$virtdb");
      print "delete db $virtdb\n";
      unlink($virtdb) or die "Cannot unlink file: $virtdb";
   }
}

sub do_test {
   my $in_init = shift;

   my $err = 0;

   print "\n" unless $in_init;

   if ($MIME::Base64::VERSION lt '3.00') {
      $err--;
      print "Base64.pm\t\t$INC{'MIME/Base64.pm'}\n\n";
      print "Your MIME::Base64 module is too old ($MIME::Base64::VERSION),\n".
            "please update to 3.00 or later.\n\n\n";
   }

   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock) = ow::dbm::guessoptions();

   if (!$in_init) {
      print "Your perl uses the following packages for dbm:\n\n";
      print "$_\t\t$INC{$_}\n" for sort grep { m/DB.*File/ } keys %INC;
      print "\n\n";
   }

   $err-- if check_db_file_pm() < 0;
   $err-- if check_dbm_option($in_init, $dbm_ext, $dbmopen_ext, $dbmopen_haslock) < 0;
   $err-- if check_savedsuid_support() < 0;

   return $err;
}

sub check_db_file_pm {
   my $dbfile_pm=$INC{'DB_File.pm'};
   if ($dbfile_pm) {
      my $t;
      sysopen(F, $dbfile_pm, O_RDONLY);
      while(<F>) {
         $t .= $_
      }
      close(F);
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
   my ($in_init, $dbm_ext, $dbmopen_ext, $dbmopen_haslock) = @_;

   my $err = 0;

   $err++ if (
                $dbm_ext ne $ow::dbm::dbm_ext
                || $dbmopen_ext ne $ow::dbm::dbmopen_ext
                || ($dbmopen_haslock ne $ow::dbm::dbmopen_haslock && $dbmopen_haslock)
             );

   my %str = (
                dbm_ext              => $dbm_ext || 'none',
                dbmopen_ext          => $dbmopen_ext || 'none',
                dbmopen_haslock      => $dbmopen_haslock ? 'yes' : 'no',
                conf_dbm_ext         => $ow::dbm::dbm_ext || 'none',
                conf_dbmopen_ext     => $ow::dbm::dbmopen_ext || 'none',
                conf_dbmopen_haslock => $ow::dbm::dbmopen_haslock ? 'yes' : 'no',
             );

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

   return $err ? -1 : 0;
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

########## make_thumbnail ########################################
sub makethumbnail {
   my $r_files=$_[0];
   my $err=0;

   my $convertbin=ow::tool::findbin("convert");
   if ($convertbin eq '') {
      print "Program convert doesn't exist\n" unless $opt{quiet};
      return -1;
   }
   my @cmd=($convertbin, '+profile', '*', '-interlace', 'NONE', '-geometry', '64x64');

   foreach my $image (@{$r_files}) {
      next if ( $image!~/\.(jpe?g|gif|png|bmp|tif)$/i || !-f $image);

      my $thumbnail=ow::tool::untaint(path2thumbnail($image));
      my @p=split(/\//, $thumbnail);
      pop(@p);
      my $thumbnaildir=join('/', @p);
      if (!-d "$thumbnaildir") {
         if (!mkdir (ow::tool::untaint("$thumbnaildir"), 0755)) {
            print "$!\n" unless $opt{quiet};
            $err++;
            next;
         }
      }

      my ($img_atime,$img_mtime)= (stat($image))[8,9];
      if (-f $thumbnail) {
         my ($thumbnail_atime,$thumbnail_mtime)= (stat($thumbnail))[8,9];
         if ($thumbnail_mtime==$img_mtime) {
            print "$thumbnail already exist.\n" unless $opt{quiet};
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
            $err++;
            next;
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
   my $tfile=pop(@p);
   $tfile=~s/\.[^\.]*$/\.jpg/i;
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
      print "This operation is only available to root\n";
      openwebmail_exit(0);
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
         print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if $opt{debug};
      }

      if ( -f "$config{'ow_sitesconfdir'}/$logindomain") {
         read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
         print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if $opt{debug};
      }

      ow::auth::load($config{'auth_module'});
      print "D ow::auth::load $config{'auth_module'}\n" if $opt{debug};

      my ($errcode, $errmsg, @userlist)=ow::auth::get_userlist(\%config);
      if ($errcode!=0) {
         writelog("userlist error - $config{'auth_module'}, ret $errcode , $errmsg");
         if ($errcode==-1) {
            print "-a is not supported by $config{'auth_module'}, use -f instead\n" unless $opt{quiet};
         } else {
            print "Unable to get userlist, error code $errcode\n" unless $opt{quiet};
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

   return 0 if ($loaded_domain>0);
   return -1;
}


sub alldomains {
   my %domainnames=();

   if ( ! opendir(SITEDIR, $config{'ow_sitesconfdir'})){
      writelog("siteconf dir error $config{'ow_sitesconfdir'} $!");
      print "Unable to read siteconf dir $config{'ow_sitesconfdir'} $!\n" unless $opt{quiet};
      return -1;
   }
   while ($domain=readdir(SITEDIR)) {
      next if ($domain=~/^(\.|readme|sameple)/i);
      $domainnames{$domain}=1;
      print "D found domain $domain\n" if $opt{debug};
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
         print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if $opt{debug};
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
      print "D loginuser=$loginuser, logindomain=$logindomain\n" if $opt{debug};

      if (defined $config{'domainname_equiv'}{'map'}{$logindomain}) {
         $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain};
         print "D logindomain equiv to $logindomain\n" if $opt{debug};
      }

      if (!is_localuser("$loginuser\@$logindomain") && -f "$config{'ow_sitesconfdir'}/$logindomain") {
         read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
         print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if $opt{debug};
      }
      ow::auth::load($config{'auth_module'});
      print "D ow::auth::load $config{'auth_module'}\n" if $opt{debug};

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
         print "user $loginname doesn't exist\n" unless $opt{quiet};
         next;
      }
      if ($user eq 'root' || $user eq 'toor'||
          $user eq 'daemon' || $user eq 'operator' || $user eq 'bin' ||
          $user eq 'tty' || $user eq 'kmem' || $user eq 'uucp') {
         print "D system user $user, skipped!\n" if $opt{debug};
         next;
      }

      if ( $>!=$uuid &&
           $>!=0 &&	# setuid root is required if spool is located in system dir
           !$config{'use_homedirspools'} &&
          ($config{'mailspooldir'} eq "/var/mail" ||
           $config{'mailspooldir'} eq "/var/spool/mail")) {
         print "This operation is only available to root\n";
         openwebmail_exit(0);
      }

      # load user config
      my $userconf="$config{'ow_usersconfdir'}/$user";
      $userconf="$config{'ow_usersconfdir'}/$domain/$user" if ($config{'auth_withdomain'});
      if ( -f "$userconf") {
         read_owconf(\%config, \%config_raw, "$userconf");
         print "D readconf $userconf\n" if $opt{debug};
      }

      # override auto guessing domainanmes if loginame has domain
      if (${$config_raw{'domainnames'}}[0] eq 'auto' && $loginname=~/\@/) {
         $config{'domainnames'}=[ $logindomain ];
      }
      # override realname if defined in config
      if ($config{'default_realname'} ne 'auto') {
         $userrealname=$config{'default_realname'};
         print "D change realname to $userrealname\n" if $opt{debug};
      }

      my $syshomedir=$homedir;	# keep this for later use
      my $owuserdir = ow::tool::untaint("$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/$user":$user));
      if ( !$config{'use_syshomedir'} ) {
         $homedir = $owuserdir;
         print "D change homedir to $homedir\n" if $opt{debug};
      }
      if ($homedir eq '/') {
         print "D homedir is /, skipped!\n" if $opt{debug};
      }

      if (defined $homedir_processed{$homedir}) {
         print "D $loginname homedir already processed, skipped!\n" if $opt{debug};
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
               mkdir($domainhome, 0750) or die("cannot create domain homedir $domainhome");
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
               print "D create owuserdir $owuserdir, uid=$uuid, gid=$fgid\n" if $opt{debug};
            } else {
               print "D cannot create $owuserdir ($!)\n" if $opt{debug};
               next;
            }
         }
      }

      umask(0077);
      if ( $>==0 ) { # switch to uuid:mailgid if process is setuid to root
         my $mailgid=getgrnam('mail');	# for better compatibility with other mail progs
         ow::suid::set_euid_egids($uuid, $ugid, $mailgid);
         if ( $)!~/\b$mailgid\b/) {	# group mail doesn't exist?
            print "Set effective gid to mail($mailgid) failed!";
            openwebmail_exit(0);
         }
      }
      print "D ruid=$<, euid=$>, rgid=$(, eguid=$)\n" if $opt{debug};

      # locate existing .openwebmail
      find_and_move_dotdir($syshomedir, $owuserdir) if (!-d dotpath('/'));	# locate existing .openwebmail

      # get user release date
      my $user_releasedate=read_releasedatefile();

      if ( ! -d $homedir ) {
         print "D $homedir doesn't exist\n" if $opt{debug};
         next;
      }

      my $folderdir=ow::tool::untaint("$homedir/$config{'homedirfolderdirname'}");
      if ( ! -d $folderdir ) {
         if (-f "$homedir/.openwebmailrc") {
            if (mkdir ($folderdir, 0700)) {
               writelog("create folderdir - $folderdir, euid=$>, egid=$)");
               print "D create folderdir $folderdir, euid=$>, egid=$<\n" if $opt{debug};
               upgrade_20021218($user_releasedate);
            } else {
               print "D cannot create $folderdir ($!)\n" if $opt{debug};
               next;
            }
         } else {
            print "D $folderdir doesn't exist\n" if $opt{debug};
            next;
         }
      }

      if ($user_releasedate ne "") {		# release file found
         check_and_create_dotdir(dotpath('/'));	# create dirs under ~/.openwebmail/
         if ($user_releasedate ne $config{'releasedate'}) {
            upgrade_all($user_releasedate);
            print "D do release upgrade...\n" if $opt{debug};
            update_releasedatefile();
         }
         update_openwebmailrc($user_releasedate);
      }
      if ( ! -d dotpath('/') ) {
         print "D ".dotpath('/')." doesn't exist\n" if $opt{debug};
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
         $po = loadlang($prefs{locale}); # for converted filename $lang_text{abook_converted}
         print "converting user $user addressbook..." unless $opt{quiet};
         my $ret = convert_addressbook('user', (ow::lang::localeinfo($prefs{locale}))[4]);
         print "done.\n" unless $opt{quiet};
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
         print "$folderfile doesn't exist\n" unless $opt{quiet};
         next;
      }

      # in case any error in dump, return immediately and do not proceed next
      if ($op eq 'dump') {
         my %folderinfo;
         
         $folderinfo{$_} = 0 for keys %is_internal_dbkey;

         my (@messageids, @attr, $buff, $buff2, $headerlen);

         my $error = 0;

         if (!ow::dbm::existdb($folderdb)) {
            print "db $folderdb doesn't exist\n" unless $opt{quiet};
            return -1;
         }

         @messageids = get_messageids_sorted_by_offset($folderdb);

         if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB)) {
            print "cannot get read lock on $folderfile\n" unless $opt{quiet};
            return -1;
         }
         if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH)) {
            print "cannot get read lock on db $folderdb\n" unless $opt{quiet};
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

            printf("%s%s%s %4d, OFFSET:%8d, SIZE:%8d, HSIZE:%4d, DATE:%s, RECVDATE:%s, CHARSET:%s, STAT:%s, MSGID:%s, FROM:%s, TO:%s, SUB:%s\n",
                   ($check[0]?'+':'-'), ($check[1]?'+':'-'), ($check[2]?'+':'-'),
                   $i+1, $attr[$_OFFSET], $attr[$_SIZE], $attr[$_HEADERSIZE], $attr[$_DATE], $attr[$_RECVDATE], $attr[$_CHARSET], $attr[$_STATUS],
                   substr($messageids[$i],0,50), $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]
                  ) if (!$opt{quiet});
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
                  $sign="---";
                  $error++;
               }
               printf("$sign %-16s db:%-30s, folder:%-30s\n", $key, $FDB{$key}, $folderinfo{$key});
            }
         }
         ow::dbm::closedb(\%FDB, $folderdb);
         close(FOLDER);
         ow::filelock::lock($folderfile, LOCK_UN);

         print "$error errors in db $folderdb\n" unless $opt{quiet};
      } elsif ($op eq "zap") {
         if (!ow::filelock::lock($folderfile, LOCK_EX)) {
            print "cannot get write lock on $folderfile\n" unless $opt{quiet};
            next;
         }

         my $ret = folder_zapmessages($folderfile, $folderdb);

         # zap again if index inconsistence (-5) or shiftblock io error (-6)
         $ret = folder_zapmessages($folderfile, $folderdb) if $ret == -5 || $ret == -6;

         if ($ret>=0) {
            print "$ret messages have been zapped from $folder\n" unless $opt{quiet};
         } elsif ($ret<0) {
            print "zap folder return error $ret\n" unless $opt{quiet};
         }

         ow::filelock::lock($folderfile, LOCK_UN);
      } else {
         if (!ow::filelock::lock($folderfile, LOCK_EX)) {
            print "cannot get write lock on $folderfile\n" unless $opt{quiet};
            next;
         }
         my $ret;
         if ($op eq "verify") {
            $ret=update_folderindex($folderfile, $folderdb);
         } elsif ($op eq "rebuild") {
            ow::dbm::unlinkdb($folderdb);
            $ret=update_folderindex($folderfile, $folderdb);
         } elsif ($op eq "fastrebuild") {
            if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_EX, 0600)) {
               print "cannot get write lock on db $folderdb\n" unless $opt{quiet};
               ow::filelock::lock($folderfile, LOCK_UN);
               next;
            }
            @FDB{'METAINFO', 'LSTMTIME'}=('ERR', -1);
            ow::dbm::closedb(\%FDB, $folderdb);
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
   my %reserveddays = (
                         'mail-trash' => $prefs{trashreserveddays},
                         'spam-mail'  => $prefs{spamvirusreserveddays},
                         'virus-mail' => $prefs{spamvirusreserveddays}
                      );
   my @f   = ();
   my $msg = '';

   push(@f, 'virus-mail') if $config{has_virusfolder_by_default};
   push(@f, 'spam-mail')  if $config{has_spamfolder_by_default};
   push(@f, 'mail-trash');

   foreach my $folder (@f) {
      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

      if (ow::filelock::lock($folderfile, LOCK_EX)) {
         my $deleted = delete_message_by_age($reserveddays{$folder}, $folderdb, $folderfile);

         if ($deleted > 0) {
            $msg .= ', ' if $msg ne '';
            $msg .= "$deleted msg deleted from $folder";
         }

         ow::filelock::lock($folderfile, LOCK_UN);
      }
   }

   if ($msg ne '') {
      writelog("clean trash/spam/virus - $msg");
      writehistory("clean trash/spam/virus - $msg");
      print "clean trash/spam/virus - $msg\n" unless $opt{quiet};
   }

   return 0;
}

sub checksize {
   return 0 if (!$config{'quota_module'});
   ow::quota::load($config{'quota_module'});

   my ($ret, $errmsg, $quotausage, $quotalimit)=ow::quota::get_usage_limit(\%config, $user, $homedir, 0);
   if ($ret<0) {
      print "$errmsg\n" unless $opt{quiet};
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
   print "$loginname " unless $opt{quiet};

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
      print "has no mail\n" unless $opt{quiet};
      return 0;
   }

   update_folderindex($spoolfile, $folderdb);

   # filtermessage in background
   filtermessage($user, 'INBOX', \%prefs);

   if (!$opt{'quiet'}) {
      my %FDB;
      if (!ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH)) {
         print "cannot get read lock on db $folderdb\n";
         return -1;
      }
      my $newmessages=$FDB{'NEWMESSAGES'};
      my $oldmessages=$FDB{'ALLMESSAGES'}-$FDB{'ZAPMESSAGES'}-$FDB{'INTERNALMESSAGES'}-$newmessages;
      ow::dbm::closedb(\%FDB, $folderdb);

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
   my $newevent = 0;
   my $oldevent = 0;

   my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($wdaynum, $year, $month, $day, $hour, $min)=(ow::datetime::seconds2array($localtime))[6,5,4,3,2,1];
   $year+=1900;
   $month++;
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
   $year+=1900;
   $month++;

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
            $itemstr.=(iconv($items{$index}{'charset'}, (ow::lang::localeinfo($prefs{locale}))[4], $items{$index}{'string'}))[0]."\n";
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

   my $m = sprintf("%02d",$month);
   my $d = sprintf("%02d",$day);

   my $title = $prefs{dateformat} || 'mm/dd/yyyy';
   $title =~ s/yyyy/$year/;
   $title =~ s/mm/$m/;
   $title =~ s/dd/$d/;
   $title .= ' (' . hourmin($checkstart) . '-' . hourmin($checkend) . ")\n\n";

   my $from      = $prefs{email};
   my $userfroms = get_userfroms();
   my $realname  = (defined $from && exists $userfroms->{$from}) ? $userfroms->{$from} : ((keys %{$userfroms})[0] || '');

   foreach my $email (keys %message) {
      my $date = ow::datetime::dateserial2datefield(ow::datetime::gmtime2dateserial(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
      my $ret  = send_mail($from, $realname, $email, $date, "calendar notification", $title.$message{$email});
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
   my ($from, $realname, $to, $date, $subject, $body) = @_;

   $realname = '' unless defined $realname && $realname;

   $from     =~ s/['"]/ /g;  # Get rid of shell escape attempts
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
           qq|cannot open SMTP servers |.
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

   my @recipients = ();

   foreach (ow::tool::str2list($to)) {
      my $email = (ow::tool::email2nameaddr($_))[1];
      next if $email eq '' || $email =~ m/\s/;
      push(@recipients, $email);
   }

   if (! $smtp->recipient(@recipients, { SkipBad => 0 }) ) {
      $smtp->reset();
      $smtp->quit();
      return -1;
   }

   my $prefcharset = (ow::lang::localeinfo($prefs{'locale'}))[4];

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
      sysopen(F, $spoolfile, O_WRONLY|O_APPEND|O_CREAT, 0600);
      close(F);
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
            $disallowed=1;
            last;
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
   my $spooldir=(get_folderpath_folderdb($user, 'INBOX'))[0];
   $spooldir=~s!(.*)/.*!$1!;

   push(@cmd, $lsofbin, '+w', '-l', '-S2', '-Di');
   foreach ($spooldir, $folderdir, $dbdir, $config{'ow_etcdir'}) {
      push(@cmd, '+d'.$_);
   }
   push(@cmd, '-a', '-d^cwd');

   # since lsof read/write tmp cache file with ruid no matter what euid is
   # so we set euid=root or euid won't have enough privilege to read/write lsof cache file
   my $euid=$>;
   $>=0 if ($<==0);
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
