#!/usr/bin/suidperl -T
#
# openwebmail-tool.pl - command tool for mail/event/notify/index...
#
# 03/27/2003 tung.AT.turtle.ee.ncku.edu.tw
#            Ebola.AT.turtle.ee.ncku.edu.tw
#            
use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { $SCRIPT_DIR=$1; }
}
if (!$SCRIPT_DIR) { 
   print qq|\nOpen WebMail is unable to locate itself on this system,\n|.
         qq|please put 'the path of openwebmail CGI directory' to\n|.
         qq|the first line of file /etc/openwebmail_path.conf\n\n|.
         qq|For example, if the script is\n\n|.
         qq|/usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl,\n\n|.
         qq|then the content of /etc/openwebmail_path.conf should be:\n\n|.
         qq|/usr/local/www/cgi-bin/openwebmail/\n\n|;
   exit 0;
}
push (@INC, $SCRIPT_DIR);

$ENV{PATH} = ""; 	# no PATH should be needed
$ENV{ENV} = "";		# no startup script for sh
$ENV{BASH_ENV} = ""; 	# no startup script for bash

use strict;
use Fcntl qw(:DEFAULT :flock);
use Net::SMTP;

require "ow-shared.pl";
require "filelock.pl";
require "mime.pl";
require "maildb.pl";
require "mailfilter.pl";
require "pop3mail.pl";
require "lunar.pl";
require "iconv-chinese.pl";
require "execute.pl";

# common globals
use vars qw(%config %config_raw %default_config %default_config_raw);
use vars qw($default_logindomain $loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw($folderdir);
use vars qw(%prefs);

# extern vars
use vars qw(@wdaystr %pop3error);	# defined in ow-shared.pl
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET);

# local globals
use vars qw($POP3_PROCESS_LIMIT $POP3_TIMEOUT);
use vars qw(%opt $pop3_process_count %complete);

################################ main ##################################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop
$SIG{CHLD}=sub { wait }; 	# prevent zombie

$POP3_PROCESS_LIMIT=10;
$POP3_TIMEOUT=20;

%opt=('null'=>1);
$default_logindomain="";
$pop3_process_count=0;
%complete=();

my @list=();

# set to ruid for secure access, this will be set to euid $> 
# if operation is from inetd or -m (query mail status ) or -e(query event status)
my $euid_to_use=$<;	

# no buffer on stdout
local $|=1;

if ($ARGV[0] eq "--") {		# called by inetd
   push(@list, $ARGV[1]);
   $opt{'mail'}=1; $opt{'event'}=1; $opt{'null'}=0; $euid_to_use=$>;
} else {
   for (my $i=0; $i<=$#ARGV; $i++) {
      if ($ARGV[$i] eq "--init") {
         $opt{'init'}=1;
      } elsif ($ARGV[$i] eq "--test") {
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
            open(F, $ARGV[$i]);
            while (<F>) { chomp $_; push(@list, $_); }
            close(F);
         }

      } elsif ($ARGV[$i] eq "--thumbnail" || $ARGV[$i] eq "-t") {
         $opt{'thumbnail'}=1;

      } elsif ($ARGV[$i] eq "--index" || $ARGV[$i] eq "-i") {
         $opt{'iv'}='ALL'; $opt{'null'}=0; $euid_to_use=$<;
      } elsif ($ARGV[$i] eq "-id") {
         $i++; $opt{'id'}=$ARGV[$i]; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-iv") {
         $i++; $opt{'iv'}=$ARGV[$i]; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-if") {
         $i++; $opt{'if'}=$ARGV[$i]; $opt{'null'}=0;
      } elsif ($ARGV[$i] eq "-ir") {
         $i++; $opt{'ir'}=$ARGV[$i]; $opt{'null'}=0;

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
      } elsif ($ARGV[$i] eq "--zaptrash" || $ARGV[$i] eq "-z") {
         $opt{'zap'}=1; $opt{'null'}=0;

      } else {
         push(@list, $ARGV[$i]);
      }
   }
}

$>=$euid_to_use;

my $retval=0;
if ($opt{'init'}) {
   $retval=init();
} elsif ($opt{'test'}) {
   $retval=do_test();
} elsif ($opt{'thumbnail'}) {
   $retval=makethumbnail(\@list); 
} else {
   if ($opt{'allusers'}) {
      $retval=allusers(\@list);
      openwebmail_exit($retval) if ($retval<0);
   }
   if ($#list>=0 && !$opt{'null'}) {
      $retval=usertool($euid_to_use, \@list);
   } else {
      $retval=showhelp();
   }
}

openwebmail_exit($retval);

############################## showhelp #######################################
sub showhelp {
   print "
Syntax: openwebmail-tool.pl --init [options]
        openwebmail-tool.pl --test
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
 -a, --alluser\t check for all users in passwd
 -d, --domain \t default domain for user with no domain specified
 -e, --event  \t check today's calendar event
 -f <userlist>\t userlist from file, each line for one user
 -i, --index  \t verify index of all folders and reindex if needed
 -id <folder> \t dump index of folder
 -iv <folder> \t verify index of folder and reindex if needed
 -if <folder> \t fast rebuild index of folder
 -ir <folder> \t rebuild index of folder
 -m, --mail   \t check new mail
 -n, --notify \t check and send calendar notification email
 -p, --pop3   \t fetch pop3 mail for user
 -s, --size   \t check user quota and cut mails/files if over quotalimit
 -z, --zaptrash\t remove stale messages from trash folder

ps: <folder> can be INBOX, ALL or folder filename

";
   return 1;
}

############################## init #######################################
sub init {
   my $err=0;
   print "\n";

   if (!defined(%default_config_raw)) {	# read default only once if persistent mode
      readconf(\%default_config, \%default_config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
      print "D readconf $SCRIPT_DIR/etc/openwebmail.conf.default\n" if ($opt{'debug'});
   }
   %config=%default_config; %config_raw =%default_config_raw;
   if (-f "$SCRIPT_DIR/etc/openwebmail.conf") {
      readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
      print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if ($opt{'debug'});
   }

   $logindomain=$default_logindomain||hostname();
   $logindomain=lc(safedomainname($logindomain));
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain} if (defined($config{'domainname_equiv'}{'map'}{$logindomain}));
   if ( -f "$config{'ow_sitesconfdir'}/$logindomain") {
      readconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
      print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if ($opt{'debug'});
   }

   if (check_tell_bug() <0) {
      print qq|Please hit 'Enter' to continue or Ctrl-C to break.\n|;
      $_=<STDIN> if (!$opt{'yes'} && !$opt{'no'});
   }

   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock)=dbm_test();
   $err++ if (check_db_file_pm()<0);
   $err++ if (check_dbm_option(0, $dbm_ext, $dbmopen_ext, $dbmopen_haslock, %config)<0);
   $err++ if (check_savedsuid_support()<0);
   if ($err>0) {
      print qq|And execute '$SCRIPT_DIR/openwebmail-tool.pl --init' again!.\n\n|;
      return -1;
   }

   foreach my $table ('b2g', 'g2b', 'lunar') {
      if ( $config{$table.'_map'} ne 'none' &&
           -f "$config{'ow_etcdir'}/$table$config{'dbm_ext'}") {
         my %T; $err=0;
         dbmopen(%T, "$config{'ow_etcdir'}/$table$config{'dbmopen_ext'}", undef) or $err=1;
         dbmclose(%T);
         if ($err) {
            unlink("$config{'ow_etcdir'}/$table$config{'dbm_ext'}");
            print "delete old $config{'ow_etcdir'}/$table$config{'dbm_ext'}\n";
         }
      }
   }
   if ($config{'b2g_map'} ne 'none' && !-f "$config{'ow_etcdir'}/b2g$config{'dbm_ext'}") {
      die "$config{'b2g_map'} not found" if (!-f $config{'b2g_map'});
      print "creating $config{'ow_etcdir'}/b2g$config{'dbm_ext'} ...";
      if (mkdb_b2g()<0) {
         print "error!\n"; return -2;
      }
      print "done.\n";
   }
   if ($config{'g2b_map'} ne 'none' && !-f "$config{'ow_etcdir'}/g2b$config{'dbm_ext'}") {
      die "$config{'g2b_map'} not found" if (!-f $config{'g2b_map'});
      print "creating $config{'ow_etcdir'}/g2b$config{'dbm_ext'} ...";
      if (mkdb_g2b()<0) {
         print "error!\n"; return -3;
      }
      print "done.\n";
   }
   if ($config{'lunar_map'} ne 'none' && !-f "$config{'ow_etcdir'}/lunar$config{'dbm_ext'}") {
      die "$config{'lunar_map'} not found" if (!-f $config{'lunar_map'});
      print "creating $config{'ow_etcdir'}/lunar$config{'dbm_ext'} ...";
      if (mkdb_lunar()<0) {
         print "error!\n"; return -4;
      }
      print "done.\n";
   }

   %prefs = readprefs();	# send_mail() uses $prefs{...}

   my $id = $ENV{'USER'} || $ENV{'LOGNAME'} || getlogin || (getpwuid($>))[0];
   my $hostname=hostname();
   my $realname=(getpwnam($id))[6]||$id;
   my $to="openwebmail\@turtle.ee.ncku.edu.tw";
   my $date = dateserial2datefield(gmtime2dateserial(), $config{'default_timeoffset'});
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

   print qq|\nWelcome to the Open WebMail!\n\n|.
         qq|This program is going to send a short message back to the developer,\n|.
         qq|so we could have the idea that who is installing and how many sites are\n|.
         qq|using this software, the content to be sent is:\n\n|.
         qq|$content\n|.
         qq|Send the site report?(Y/n) |;

   if ($opt{'yes'}) {
      print qq|Yes.\n|;
      print qq|sending report...\n|;
      send_mail("$id\@$hostname", $realname, $to, $date, $subject, "$content \n");
   } elsif ($opt{'no'}) {
      print qq|No.\n|;
   } else {
      $_=<STDIN>;
      if ($_!~/^n/) {
         print qq|sending report...\n|;
         send_mail("$id\@$hostname", $realname, $to, $date, $subject, "$content \n")
      }
   }
   print qq|\nThank you.\n\n|;
   return 0;
}

sub do_test {
   my $err=0;
   print "\n";

   if (!defined(%default_config_raw)) {	# read default only once if persistent mode
      readconf(\%default_config, \%default_config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
      print "D readconf $SCRIPT_DIR/etc/openwebmail.conf.default\n" if ($opt{'debug'});
   }
   %config=%default_config; %config_raw =%default_config_raw;
   if (-f "$SCRIPT_DIR/etc/openwebmail.conf") {
      readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
      print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if ($opt{'debug'});
   }

   $logindomain=$default_logindomain||hostname();
   $logindomain=lc(safedomainname($logindomain));
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain} if (defined($config{'domainname_equiv'}{'map'}{$logindomain}));
   if ( -f "$config{'ow_sitesconfdir'}/$logindomain") {
      readconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
      print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if ($opt{'debug'});
   }

   check_tell_bug();
   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock)=dbm_test();
   print_dbm_module();
   check_db_file_pm();
   check_dbm_option(1, $dbm_ext, $dbmopen_ext, $dbmopen_haslock, %config);
   check_savedsuid_support();
}
   

sub check_tell_bug {
   my $offset;
   my $testfile="/tmp/testfile.$$";
   ($testfile =~ /^(.+)$/) && ($testfile = $1);

   open(F, ">$testfile"); print F "test"; close(F);
   open(F, ">>$testfile"); $offset=tell(F); close(F);
   unlink($testfile);

   if ($offset==0) {
      print qq|WARNING!\n\n|.
            qq|The perl on your system has serious bug in routine tell()!\n|.
            qq|While openwebmail can work properly with this bug, other perl application\n|.
            qq|may not function properly and thus cause data loss.\n\n|.
            qq|We suggest that you should patch your perl as soon as possible.\n\n\n|;
      return -1;
   }
   return 0;
}

sub dbm_test {
   my (%DB, @filelist, @delfiles);
   my ($dbm_ext, $dbmopen_ext, $dbmopen_haslock);

   mkdir ("/tmp/dbmtest.$$", 0755);

   dbmopen(%DB, "/tmp/dbmtest.$$/test", 0600); dbmclose(%DB);

   @delfiles=();
   opendir (TESTDIR, "/tmp/dbmtest.$$");
   while (defined(my $filename = readdir(TESTDIR))) {
      ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...
      if ($filename!~/^\./ ) {
         push(@filelist, $filename);
         push(@delfiles, "/tmp/dbmtest.$$/$filename");
      }
   }
   closedir(TESTDIR);
   unlink(@delfiles) if ($#delfiles>=0);

   @filelist=reverse sort(@filelist);
   if ($filelist[0]=~/(\..*)$/) {
      ($dbm_ext, $dbmopen_ext)=($1, '');
   } else {
      ($dbm_ext, $dbmopen_ext)=('.db', '.db');
   }

   my $result;
   filelock("/tmp/dbmtest.$$/test$dbm_ext", LOCK_EX);
   eval {
      local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
      alarm 5;	# timeout 5 sec
      $result = dbmopen(%DB, "/tmp/dbmtest.$$/test$dbmopen_ext", 0600);
      dbmclose(%DB) if ($result);
      alarm 0;
   };
   if ($@ or !$result) {	# eval error, it means timeout
      $dbmopen_haslock=1;
   } else {
      $dbmopen_haslock=0;
   }
   filelock("/tmp/dbmtest.$$/test$dbm_ext", LOCK_UN);

   @delfiles=();
   opendir (TESTDIR, "/tmp/dbmtest.$$");
   while (defined(my $filename = readdir(TESTDIR))) {
      ($filename =~ /^(.+)$/) && ($filename = $1);	# untaint ...
      push(@delfiles, "/tmp/dbmtest.$$/$filename") if ($filename!~/^\./ );
   }
   closedir(TESTDIR);
   unlink(@delfiles) if ($#delfiles>=0);

   rmdir("/tmp/dbmtest.$$");

   return($dbm_ext, $dbmopen_ext, $dbmopen_haslock);
}

sub print_dbm_module {
   print "You perl uses the following packages for dbm::\n\n";
   my @pm;
   foreach (keys %INC) { push (@pm, $_) if (/DB.*File/); }
   foreach (sort @pm) { print "$_\t\t$INC{$_}\n"; }
   print "\n\n";
}

sub check_db_file_pm {
   my $dbfile_pm=$INC{'DB_File.pm'};
   if ($dbfile_pm) {
      my $t;
      open(F, $dbfile_pm); while(<F>) {$t.=$_;} close(F);
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
   my ($showtest, $dbm_ext, $dbmopen_ext, $dbmopen_haslock, %config)=@_;

   if ($dbm_ext ne $config{'dbm_ext'} ||
       $dbmopen_ext ne $config{'dbmopen_ext'} ||
       ($dbmopen_haslock ne $config{'dbmopen_haslock'} && $dbmopen_haslock) ) {

      if ($dbmopen_ext eq $dbm_ext) {	# convert value to str
         $dbmopen_ext='%dbm_ext%';
      } elsif ($dbmopen_ext eq "") {
         $dbmopen_ext='none';
      }
      if ($dbmopen_haslock) {
         $dbmopen_haslock='yes';
      } else {
         $dbmopen_haslock='no';
      }
      print qq|Please change the following 3 options in openwebmail.conf\n|.
            qq|from\n|.
            qq|\tdbm_ext         \t$config_raw{'dbm_ext'}\n|.
            qq|\tdbmopen_ext     \t$config_raw{'dbmopen_ext'}\n|.
            qq|\tdbmopen_haslock \t$config_raw{'dbmopen_haslock'}\n|.
            qq|to\n|.
            qq|\tdbm_ext         \t$dbm_ext\n|.
            qq|\tdbmopen_ext     \t$dbmopen_ext\n|.
            qq|\tdbmopen_haslock \t$dbmopen_haslock\n\n\n|;
      return -1;
   }

   if ($showtest) {
      print qq|The dbm options in openwebmail.conf should be set as follows:\n\n|.
            qq|dbm_ext         \t$config_raw{'dbm_ext'}\n|.
            qq|dbmopen_ext     \t$config_raw{'dbmopen_ext'}\n|.
            qq|dbmopen_haslock \t$config_raw{'dbmopen_haslock'}\n\n\n|;
   }
   return 0;
} 

sub check_savedsuid_support {
   return if ($>!=0);

   $>=65534; 
   $>=0;
   if ($>!=0) {
      print qq|Your system didn't have saved suid support,\n|.
            qq|please set the following option in openwebmail.conf\n\n|.
            qq|\tsavedsuid_support no\n\n\n|;
      return -1;
   }
   return 0;
}

############################## make_thumbnail ################################
sub makethumbnail {
   my $r_files=$_[0];
   my $err=0;

   my $convertbin;
   foreach ('/usr/local/bin', '/usr/bin', '/bin', '/usr/X11R6/bin/', '/opt/bin') {
      if ( -x "$_/convert") {
         $convertbin="$_/convert";
      }
   }
   if (!$convertbin) {
      print "Program convert doesn't exist\n" if (!$opt{'quiet'});
      return -1;
   }
   my @cmd=($convertbin, '+profile', '*', '-interlace', 'NONE', '-geometry', '64x64');

   foreach my $image (@{$r_files}) {
      next if ( $image!~/\.(jpe?g|gif|png|bmp|tif)$/i || !-f $image);

      my $thumbnail=path2thumbnail($image);
      ($thumbnail =~ /^(.*)$/) && ($thumbnail = $1);

      my @p=split(/\//, $thumbnail); pop(@p);
      my $thumbnaildir=join('/', @p);
      if (!-d "$thumbnaildir") {
         ($thumbnaildir =~ /^(.*)$/) && ($thumbnaildir = $1);
         if (!mkdir ("$thumbnaildir", 0755)) {
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
      my ($stdout, $stderr, $exit, $sig)=openwebmail::execute::execute(@cmd, $image, $thumbnail);

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
         ($img_atime  =~ /^(.*)$/) && ($img_atime = $1);
         ($img_mtime  =~ /^(.*)$/) && ($img_mtime = $1);
         utime($img_atime, $img_mtime, $thumbnail)
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


######################### user folder/calendar routines #####################
sub allusers {
   my $r_list=$_[0];

   if (!defined(%default_config_raw)) {	# read default only once if persistent mode
      readconf(\%default_config, \%default_config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
      print "D readconf $SCRIPT_DIR/etc/openwebmail.conf.default\n" if ($opt{'debug'});
   }
   %config=%default_config; %config_raw =%default_config_raw;
   if (-f "$SCRIPT_DIR/etc/openwebmail.conf") {
      readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
      print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if ($opt{'debug'});
   }

   $logindomain=$default_logindomain||hostname();
   $logindomain=lc(safedomainname($logindomain));
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain} if (defined($config{'domainname_equiv'}{'map'}{$logindomain}));
   if ( -f "$config{'ow_sitesconfdir'}/$logindomain") {
      readconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
      print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if ($opt{'debug'});
   }

   if ( $>!=0 &&	# setuid is required if spool is located in system dir
       ($config{'mailspooldir'} eq "/var/mail" || 
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "This operation is only available to root\n"; openwebmail_exit(0);
   }
   loadauth($config{'auth_module'});
   print "D loadauth $config{'auth_module'}\n" if ($opt{'debug'});

   # update virtusertable
   my $virtname=$config{'virtusertable'}; $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   update_virtusertable("$config{'ow_etcdir'}/$virtname", $config{'virtusertable'});

   my ($errcode, $errmsg, @userlist)=get_userlist(\%config);
   if ($errcode!=0) {
      writelog("userlist error - $config{'auth_module'}, ret $errcode , $errmsg");
      if ($errcode==-1) {
         print "-a is not supported by $config{'auth_module'}, use -f instead\n" if (!$opt{'quiet'});
      } else {
         print "Unable to get userlist, error code $errcode\n" if (!$opt{'quiet'});
      }
      return -1; 
   }
   push(@{$r_list}, @userlist);
   return 0;
}


sub usertool {
   my ($euid_to_use, $r_userlist)=@_;
   my $hostname=hostname();
   my $usercount=0;

   foreach $loginname (@{$r_userlist}) {
      # reset back to init $euid before switch to next user
      #$>=0;
      $>=$euid_to_use;

      %config=(); %config_raw=();
      if (!defined(%default_config_raw)) {	# read default only once if persistent mode
         readconf(\%default_config, \%default_config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
         print "D readconf $SCRIPT_DIR/etc/openwebmail.conf.default\n" if ($opt{'debug'});
      }
      %config=%default_config; %config_raw =%default_config_raw;
      if (-f "$SCRIPT_DIR/etc/openwebmail.conf") {
         readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf");
         print "D readconf $SCRIPT_DIR/etc/openwebmail.conf\n" if ($opt{'debug'});
      }

      if ($config{'smtpauth'}) {	# load smtp auth user/pass
         readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/smtpauth.conf");
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

      if (defined($config{'domainname_equiv'}{'map'}{$logindomain})) {
         $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain};
         print "D logindomain equiv to $logindomain\n" if ($opt{'debug'});
      }

      if (!is_localuser("$loginuser\@$logindomain") && -f "$config{'ow_sitesconfdir'}/$logindomain") {
         readconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
         print "D readconf $config{'ow_sitesconfdir'}/$logindomain\n" if ($opt{'debug'});
      }
      loadauth($config{'auth_module'});
      print "D loadauth $config{'auth_module'}\n" if ($opt{'debug'});

      # update virtusertable
      my $virtname=$config{'virtusertable'}; $virtname=~s!/!.!g; $virtname=~s/^\.+//;
      update_virtusertable("$config{'ow_etcdir'}/$virtname", $config{'virtusertable'});

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
      next if ($user eq 'root' || $user eq 'toor'||
               $user eq 'daemon' || $user eq 'operator' || $user eq 'bin' ||
               $user eq 'tty' || $user eq 'kmem' || $user eq 'uucp');

      if ( $>!=$uuid &&
           $>!=0 &&	# setuid root is required if spool is located in system dir
          ($config{'mailspooldir'} eq "/var/mail" || 
           $config{'mailspooldir'} eq "/var/spool/mail")) {
         print "This operation is only available to root\n"; openwebmail_exit(0);
      }

      # load user config
      my $userconf="$config{'ow_usersconfdir'}/$user";
      $userconf="$config{'ow_usersconfdir'}/$domain/$user" if ($config{'auth_withdomain'});
      if ( -f "$userconf") {
         readconf(\%config, \%config_raw, "$userconf");
         print "D readconf $userconf\n" if ($opt{'debug'});
      }

      # override auto guessing domainanmes if loginame has domain
      if ($config_raw{'domainnames'} eq 'auto' && $loginname=~/\@/) {
         $config{'domainnames'}=[ $logindomain ];
      }
      # override realname if defined in config
      if ($config{'default_realname'} ne 'auto') {
         $userrealname=$config{'default_realname'};
         print "D change realname to $userrealname\n" if ($opt{'debug'});
      }

      if ( !$config{'use_syshomedir'} ) {
         $homedir = "$config{'ow_usersdir'}/$user";
         $homedir = "$config{'ow_usersdir'}/$domain/$user" if ($config{'auth_withdomain'});
         print "D change homedir to $homedir\n" if ($opt{'debug'});
      }
      $folderdir = "$homedir/$config{'homedirfolderdirname'}";
      print "D folderdir=$folderdir\n" if ($opt{'debug'});
      next if ($homedir eq '/');

      ($user =~ /^(.+)$/) && ($user = $1);  # untaint $user
      ($uuid =~ /^(.+)$/) && ($uuid = $1);
      ($ugid =~ /^(.+)$/) && ($ugid = $1);
      ($homedir =~ /^(.+)$/) && ($homedir = $1);  # untaint $homedir
      ($folderdir =~ /^(.+)$/) && ($folderdir = $1);  # untaint $folderdir

      umask(0077);
      if ( $>==0 ) { # switch to uuid:mailgid if process is setuid to root
         my $mailgid=getgrnam('mail');	# for better compatibility with other mail progs
         set_euid_egids($uuid, $mailgid, split(/\s+/,$ugid)); 
         if ( $)!~/\b$mailgid\b/) {	# group mail doesn't exist?
            print "Set effective gid to mail($mailgid) failed!"; openwebmail_exit(0);            
         }
      }
      print "D ruid=$<, euid=$>, rgid=$(, eguid=$)\n" if ($opt{'debug'});

      if ( ! -d $homedir ) {
         print "$homedir doesn't exist\n" if (!$opt{'quiet'});
         next;
      }
      if ( ! -d $folderdir ) {
         print "$folderdir doesn't exist\n" if (!$opt{'quiet'});
         next;
      }
      if ( ! -f "$folderdir/.openwebmailrc" ) {
         print "$folderdir/.openwebmailrc doesn't exist or open error\n" if (!$opt{'quiet'});
         next;
      }

      %prefs = readprefs();

      if ($opt{'pop3'}) {
         my $ret=getpop3s($POP3_TIMEOUT);
         print "getpop3s($POP3_TIMEOUT) return $ret\n" if (!$opt{'quiet'} && $ret!=0);
      }
      if ($opt{'zap'}) {
         my $ret=cleantrash();
         print "cleantrash() return $ret\n" if (!$opt{'quiet'} && $ret!=0);
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
   my (@validfolders, $folderusage);

   if ($folder eq 'ALL') {
      getfolders(\@validfolders, \$folderusage);
   } else {
      push(@validfolders, $folder);
   }

   foreach (@validfolders) {
      my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $_);
      my %HDB;

      next if (! -f $folderfile);

      if (!filelock($folderfile, LOCK_EX|LOCK_NB)) {
         printf ("Couldn't get write lock on $folderfile") if (!$opt{'quiet'});
         return -1;
      }
      if ($op eq "dump") {
         my (@messageids, @attr, $buff, $buff2);
         my $error=0;

         if (! -f "$headerdb$config{'dbm_ext'}") {
            printf ("$headerdb$config{'dbm_ext'} doesn't exist") if (!$opt{'quiet'});
            return -1;
         }
         @messageids=get_messageids_sorted_by_offset($headerdb);

         if (!filelock($folderfile, LOCK_SH)) {
            printf ("Couldn't get read lock on $folderfile") if (!$opt{'quiet'});
            return -1;
         }
         if (!open_dbm(\%HDB, $headerdb, LOCK_SH)) {
            filelock($folderfile, LOCK_UN);
            printf ("Couldn't get read lock on $headerdb$config{'dbm_ext'}") if (!$opt{'quiet'});
            return -1;
         }
         open (FOLDER, $folderfile);

         if (  $HDB{'METAINFO'} eq metainfo($folderfile) ) {
            print "+++" if (!$opt{'quiet'});
         } else {
            print "---" if (!$opt{'quiet'}); $error++;
         }
         printf (" METAINFO db:'%s' folder:'%s'\n", $HDB{'METAINFO'}, metainfo($folderfile)) if (!$opt{'quiet'});

         for(my $i=0; $i<=$#messageids; $i++) {
            @attr=get_message_attributes($messageids[$i], $headerdb);
            seek(FOLDER, $attr[$_OFFSET], 0);
            read(FOLDER, $buff, 6);
            seek(FOLDER, $attr[$_OFFSET]+$attr[$_SIZE], 0);
            read(FOLDER, $buff2, 6);

            if ( $buff=~/^From / && ($buff2=~/^From /||$buff2 eq "")) {
               print "+++" if (!$opt{'quiet'});
            } else {
               print "---" if (!$opt{'quiet'}); $error++;
            }
            printf (" %4d, OFFSET:%8d, SIZE:%8d, DATE:%s, CHARSET:%s, STAT:%3s, MSGID:%s, FROM:%s, TO:%s, SUB:%s\n",
			$i, $attr[$_OFFSET], $attr[$_SIZE], $attr[$_DATE], $attr[$_CHARSET], $attr[$_STATUS],
                            substr($messageids[$i],0,50), $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]) if (!$opt{'quiet'});
            #printf ("buf=$buff, buff2=$buff2\n");
         }

         close_dbm(\%HDB, $headerdb);
         close(FOLDER);
         filelock($folderfile, LOCK_UN);

         print "$error errors in $headerdb$config{'dbm_ext'}\n" if (!$opt{'quiet'});
         return 0 if ($error==0);
         return -1;
      } else {
         my $ret;
         if ($op eq "verify") {
            $ret=update_headerdb($headerdb, $folderfile);
         } elsif ($op eq "rebuild") {
            unlink("$headerdb$config{'dbm_ext'}");
            $ret=update_headerdb($headerdb, $folderfile);
         } elsif ($op eq "fastrebuild") {
            if (!open_dbm(\%HDB, $headerdb, LOCK_EX, 0600)) {
               print "Couldn't get write lock on $headerdb$config{'dbm_ext'}\n" if (!$opt{'quiet'});
               return -1;
            }
            $HDB{'METAINFO'}="ERR";
            close_dbm(\%HDB, $headerdb);
            $ret=update_headerdb($headerdb, $folderfile);
         }

         if (!$opt{'quiet'}) {
            if ($ret<0) {
               print "$headerdb$config{'dbm_ext'} $op error $ret\n";
            } elsif ($op ne 'verify' || ($op eq 'verify' && $ret==0)) {
               print "$headerdb$config{'dbm_ext'} $op ok\n";
            } else {
               print "$headerdb$config{'dbm_ext'} $op & updated ok\n";
            }
         }
      }
      filelock($folderfile, LOCK_UN);
   }
   return 0;
}


sub cleantrash {
   my ($trashfile, $trashdb)=get_folderfile_headerdb($user, 'mail-trash');
   if (filelock($trashfile, LOCK_EX|LOCK_NB)) {
      my $deleted=delete_message_by_age($prefs{'trashreserveddays'}, $trashdb, $trashfile);
      if ($deleted >0) {
         writelog("clean trash - delete $deleted msgs from mail-trash");
         writehistory("clean trash - delete $deleted msgs from mail-trash");
         print "$deleted msgs deleted from mail-trash\n" if (!$opt{'quiet'});
      }
      filelock($trashfile, LOCK_UN);
   }
   return 0;
}


sub checksize {
   return 0 if ($config{'quota_module'} eq "none");
   loadquota($config{'quota_module'});

   my ($ret, $errmsg, $quotausage, $quotalimit)=quota_get_usage_limit(\%config, $user, $homedir, 0);
   if ($ret<0) {
      print "$errmsg\n" if (!$opt{'quiet'});
      return $ret;
   }
   $quotalimit=$config{'quota_limit'} if ($quotalimit<0);
   return 0 if (!$quotalimit);
   
   my (@validfolders, $folderusage);
   my $i=0;
   while ($quotausage>$quotalimit && $i<2) {
      $quotausage=(quota_get_usage_limit(\%config, $user, $homedir, 1))[2]; # get uptodate usage
      return 0 if ($quotausage<=$quotalimit);

      my $sizetocut=($quotausage-$quotalimit*0.9)*1024;
      if ($config{'delmail_ifquotahit'} && !$config{'delfile_ifquotahit'}) {
         cutfoldermails($sizetocut, @validfolders);
      } elsif (!$config{'delmail_ifquotahit'} && $config{'delfile_ifquotahit'}) {
         my $webdiskrootdir=$homedir.absolute_vpath("/", $config{'webdisk_rootpath'});
         cutdirfiles($sizetocut, $webdiskrootdir);
      } else {	# both delmail/delfile are on or off, choose by percent
         getfolders(\@validfolders, \$folderusage);
         if ($folderusage>$quotausage*0.5) {
            cutfoldermails($sizetocut, @validfolders);
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
   my ($spoolfile, $headerdb)=get_folderfile_headerdb($user, 'INBOX');
   print "$loginname " if (!$opt{'quiet'});

   if ($config{'getmail_from_pop3_authserver'}) {
      my $authpop3book="$folderdir/.authpop3.book";
      my %accounts;
      if (-f "$authpop3book" && readpop3book("$authpop3book", \%accounts)>0) {
         my $login=$user;  $login.="\@$domain" if ($config{'auth_withdomain'});
         my ($pop3passwd, $pop3del)
		=(split(/\@\@\@/, $accounts{"$config{'pop3_authserver'}:$config{'pop3_authport'}\@\@\@$login"}))[3,4];
         my $response = retrpop3mail($config{'pop3_authserver'},$config{'pop3_authport'}, $login,$pop3passwd, $pop3del,
				"$folderdir/.uidl.$login\@$config{'pop3_authserver'}", 
				$spoolfile);
         if ( $response<0) {
            writelog("pop3 error - $pop3error{$response} at $login\@$config{'pop3_authserver'}:$config{'pop3_authport'}");
         }
      }
   }

   if ( ! -f $spoolfile || (stat($spoolfile))[7]==0 ) {
      print "has no mail\n" if (!$opt{'quiet'});
      return 0;
   }

   my @folderlist=();
   my ($filtered, $r_filtered);
   if ($config{'enable_smartfilters'}) {
      ($filtered, $r_filtered)=mailfilter($user, 'INBOX', $folderdir, \@folderlist, $prefs{'regexmatch'},
					$prefs{'filter_repeatlimit'}, $prefs{'filter_badformatfrom'},
					$prefs{'filter_fakedsmtp'}, $prefs{'filter_fakedfrom'},
					$prefs{'filter_fakedexecontenttype'});
   } else {
      ($filtered, $r_filtered)=mailfilter($user, 'INBOX', $folderdir, \@folderlist, $prefs{'regexmatch'},
					0, 0, 0, 0, 0);
   }
   if ($filtered>0) {
      writelog("filter message - filter $filtered msgs from INBOX");
      writehistory("filter message - filter $filtered msgs from INBOX");
   }

   if (!$opt{'quiet'}) {
      my (%HDB, $allmessages, $internalmessages, $newmessages);
      if (!open_dbm(\%HDB, $headerdb, LOCK_SH)) {
         print "couldn't get read lock on $headerdb$config{'dbm_ext'}\n";
         return -1;
      }
      $allmessages=$HDB{'ALLMESSAGES'};
      $internalmessages=$HDB{'INTERNALMESSAGES'};
      $newmessages=$HDB{'NEWMESSAGES'};
      close_dbm(\%HDB, $headerdb);

      if ($newmessages > 0 ) {
         print "has new mail\n";
      } elsif ($allmessages-$internalmessages > 0 ) {
         print "has mail\n";
      } else {
         print "has no mail\n";
      }
   }
   return 0;
}


sub checknewevent {
   my ($newevent, $oldevent);
   my $g2l=time();
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$prefs{'timeoffset'})) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime
   }
   $g2l+=timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($wdaynum, $year, $month, $day, $hour, $min)=(gmtime($g2l))[6,5,4,3,2,1];
   $year+=1900; $month++;
   my $hourmin=sprintf("%02d%02d", $hour, $min);

   my $dow=$wdaystr[$wdaynum];
   my $date=sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      return -1;
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'language'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

   my ($easter_month, $easter_day) = gregorian_easter($year); # compute once

   my @indexlist=();
   push(@indexlist, @{$indexes{$date}}) if (defined($indexes{$date}));
   push(@indexlist, @{$indexes{'*'}})   if (defined($indexes{'*'}));
   @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

   for my $index (@indexlist) {
      if ($date=~/$items{$index}{'idate'}/ ||
          $date2=~/$items{$index}{'idate'}/ ||
          easter_match($year,$month,$day, $easter_month,$easter_day,
                                      $items{$index}{'idate'}) ) {
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
   my $g2l=time();
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$prefs{'timeoffset'})) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime
   }
   $g2l+=timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($wdaynum, $year, $month, $day, $hour, $min)=(gmtime($g2l))[6,5,4,3,2,1];
   $year+=1900; $month++;

   my $dow=$wdaystr[$wdaynum];
   my $date=sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

   my $checkstart="0000";
   if ( -f "$folderdir/.notify.check" ) {
      open (NOTIFYCHECK, "$folderdir/.notify.check" ) or return -1; # read err
      my $lastcheck=<NOTIFYCHECK>;
      close (NOTIFYCHECK);
      $checkstart=$1 if ($lastcheck=~/$date(\d\d\d\d)/);
   }

   my $checkend="2400";
   my ($wdaynum2, $year2, $month2, $day2, $hour2, $min2)=(gmtime($g2l+$config{'calendar_email_notifyinterval'}*60))[6,5,4,3,2,1];
   $checkend=sprintf("%02d%02d", $hour2, $min2) if ( $day2 eq $day );

   return 0 if ($checkend<=$checkstart);

   open (NOTIFYCHECK, ">$folderdir/.notify.check" ) or return -2; # write err
   print NOTIFYCHECK "$date$checkend";
   truncate(NOTIFYCHECK, tell(NOTIFYCHECK));
   close (NOTIFYCHECK);

   my (%items, %indexes);

   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      return -3;
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'language'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

   my ($easter_month, $easter_day) = gregorian_easter($year); # compute once

   my @indexlist=();
   push(@indexlist, @{$indexes{$date}}) if (defined($indexes{$date}));
   push(@indexlist, @{$indexes{'*'}})   if (defined($indexes{'*'}));
   @indexlist=sort { ($items{$a}{'starthourmin'}||1E9)<=>($items{$b}{'starthourmin'}||1E9) } @indexlist;

   my $future_items=0;
   for my $index (@indexlist) {
      if ( $items{$index}{'email'} &&
           ($date=~/$items{$index}{'idate'}/  || 
            $date2=~/$items{$index}{'idate'}/ ||
            easter_match($year,$month,$day, $easter_month,$easter_day,
                                      $items{$index}{'idate'})) ) {
         if ( ($items{$index}{'starthourmin'}>=$checkstart &&
               $items{$index}{'starthourmin'}<$checkend) ||
              ($items{$index}{'starthourmin'}==0 &&
               $checkstart eq "0000") ) {
            my $itemstr;
            if ($items{$index}{'starthourmin'}==0) {
               $itemstr="##:##";
            } elsif ($items{$index}{'endhourmin'}==0) {
               $itemstr=hourmin($items{$index}{'starthourmin'});
            } else {
               $itemstr=hourmin($items{$index}{'starthourmin'})."-".hourmin($items{$index}{'endhourmin'});
            }
            $itemstr .= "  $items{$index}{'string'}";
            $itemstr .= " ($items{$index}{'link'})" if ($items{$index}{'link'});

            if (defined($message{$items{$index}{'email'}})) {
               $message{$items{$index}{'email'}} .= $itemstr."\n";
            } else {
               $message{$items{$index}{'email'}} = $itemstr."\n";
            }
         }
         if ($items{$index}{'starthourmin'}>=$checkend) {
            $future_items++;
         }
      }
   }

   if ($future_items==0) { # today has no more item to notify, set checkend to 2400
      if (open (NOTIFYCHECK, ">$folderdir/.notify.check" )) {
         print NOTIFYCHECK $date."2400";
         truncate(NOTIFYCHECK, tell(NOTIFYCHECK));
         close (NOTIFYCHECK);
      }
   }

   my $title=$prefs{'dateformat'}||"mm/dd/yyyy";
   my ($m, $d)=(sprintf("%02d",$month), sprintf("%02d",$day));
   $title=~s/yyyy/$year/; $title=~s/mm/$m/; $title=~s/dd/$d/;
   $title.=" Event(s) between ".hourmin($checkstart)."-".hourmin($checkend)."\n".
           "------------------------------------------------------------\n";
   my $from=$prefs{'email'};
   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, "$folderdir/.from.book");
   my $realname=$userfrom{$from};
   foreach my $email (keys %message) {
      my $date = dateserial2datefield(gmtime2dateserial(), $prefs{'timeoffset'});
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
   ($from =~ /^(.+)$/) && ($from = $1);
   ($to =~ /^(.+)$/) && ($to = $1);
   ($date =~ /^(.+)$/) && ($date = $1);

   # fake a messageid for this message
   my $fakedid = gmtime2dateserial().'.M'.int(rand()*100000);
   $fakedid="<$fakedid".'@'."${$config{'domainnames'}}[0]>";

   my $smtp;
   $smtp=Net::SMTP->new($config{'smtpserver'},
                        Port => $config{'smtpport'},
                        Timeout => 120,
                        Hello => ${$config{'domainnames'}}[0]) or
      die "Couldn't SMTP server $config{'smtpserver'}:$config{'smtpport'}!";

   # SMTP SASL authentication (PLAIN only)
   if ($config{'smtpauth'}) {
      my $auth = $smtp->supports("AUTH");
      $smtp->auth($config{'smtpauth_username'}, $config{'smtpauth_password'}) or
         die "SMTP server $config{'smtpserver'} error - ".$smtp->message;
   }

   $smtp->mail($from);

   my @recipients=();
   foreach (str2list($to,0)) {
      my $email=(email2nameaddr($_))[1];
      next if ($email eq "" || $email=~/\s/);
      push (@recipients, $email);
   }
   if (! $smtp->recipient(@recipients, { SkipBad => 1 }) ) {
      $smtp->reset();
      $smtp->quit();
      return -1;
   }

   $smtp->data();
   $smtp->datasend("From: ".encode_mimewords("$realname <$from>", ('Charset'=>$prefs{'charset'}))."\n",
                   "To: ".encode_mimewords($to, ('Charset'=>$prefs{'charset'}))."\n");
   $smtp->datasend("Reply-To: ".encode_mimewords($prefs{'replyto'}, ('Charset'=>$prefs{'charset'}))."\n") if ($prefs{'replyto'});

   my $xmailer = $config{'name'};
   $xmailer .= " $config{'version'} $config{'releasedate'}" if ($config{'xmailer_has_version'});

   $smtp->datasend("Subject: ".encode_mimewords($subject, ('Charset'=>$prefs{'charset'}))."\n",
                   "Date: $date\n",
                   "Message-Id: $fakedid\n",
                   "X-Mailer: $xmailer\n",
                   "MIME-Version: 1.0\n",
                   "Content-Type: text/plain; charset=$prefs{'charset'}\n\n",
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

sub getpop3s {
   my $timeout=$_[0];
   my ($spoolfile, $header)=get_folderfile_headerdb($user, 'INBOX');
   my (%accounts, $response);

   # create system spool file /var/mail/xxxx
   if ( ! -f "$spoolfile" ) {
      open (F, ">>$spoolfile"); close(F);
   }

   return 0 if (!-f "$folderdir/.pop3.book");
   return -1 if (readpop3book("$folderdir/.pop3.book", \%accounts) <0);

   # fork a child to do fetch pop3 mails and return immediately
   if (%accounts >0) {
      while ($pop3_process_count>$POP3_PROCESS_LIMIT) {
         sleep 1;
      }

      $pop3_process_count++;
      local $|=1; 			# flush all output
      local $SIG{CHLD} = sub { my $pid=wait; $complete{$pid}=1; $pop3_process_count--; }; # handle zombie

      my $childpid=fork();
      if ( $childpid == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);

         foreach (values %accounts) {
            my ($pop3host,$pop3port, $pop3user,$pop3passwd, $pop3del, $enable)=split(/\@\@\@/,$_);
            next if (!$enable);

            my $disallowed=0;
            foreach ( @{$config{'disallowed_pop3servers'}} ) {
               if ($pop3host eq $_) {
                  $disallowed=1; last;
               }
            }
            next if ($disallowed);

            my $response = retrpop3mail($pop3host,$pop3port, $pop3user,$pop3passwd, $pop3del,
					"$folderdir/.uidl.$pop3user\@$pop3host",
					$spoolfile);
            if ( $response<0) {
               writelog("pop3 error - $pop3error{$response} at $pop3user\@$pop3host:$pop3port");
            }
         }
         openwebmail_exit(0);
      }

      for (my $i=0; $i<$timeout; $i++) { # wait fetch to complete for $timeout seconds
         sleep 1;
         last if ($complete{$childpid});
      }
   }
   return 0;
}
