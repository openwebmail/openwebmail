#
# ow-shared.pl - routines shared by openwebmail*.pl
#

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI::Carp qw(fatalsToBrowser carpout);
use Time::Local;

# extern vars, defined in caller openwebmail-xxx.pl
use vars qw($SCRIPT_DIR);
use vars qw($persistence_count);
use vars qw(%config %config_raw %default_config %default_config_raw);
use vars qw($thissession);
use vars qw($default_logindomain $loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);
use vars qw($sort $searchtype $keyword);
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err);	# defined in lang/xy
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET);	# defined in maildb.pl

# globals constants
use vars qw(%languagenames %languagecharsets %httpaccept2language @openwebmailrcitem);
use vars qw(%months @monthstr @wdaystr %tzoffset %fontsize);
use vars qw(%pop3error);

# The language name for each language abbreviation
%languagenames = (
   'ar.CP1256'    => 'Arabic - Windows',
   'ar.ISO8859-6' => 'Arabic - ISO 8859-6',
   'bg'           => 'Bulgarian',
   'ca'           => 'Catalan',
   'cs'           => 'Czech',
   'da'           => 'Danish',
   'de'           => 'Deutsch',			# German
   'el'           => 'Hellenic',			# Hellenic/Greek
   'en'           => 'English',
   'es'           => 'Spanish',			# Espanol
   'fi'           => 'Finnish',
   'fr'           => 'French',
   'he.ISO8859-8' => 'Hebrew - ISO 8859-8',
   'he.CP1255'    => 'Hebrew - Windows',
   'hu'           => 'Hungarian',
   'id'           => 'Indonesian',
   'it'           => 'Italiano',
   'ja_JP.eucJP'     => 'Japanese - eucJP',
   'ja_JP.Shift_JIS' => 'Japanese - ShiftJIS',
   'kr'           => 'Korean',
   'lt'           => 'Lithuanian',
   'nl'           => 'Nederlands',
   'no'           => 'Norwegian',
   'pl'           => 'Polish',
   'pt'           => 'Portuguese',
   'pt_BR'        => 'Portuguese Brazil',
   'ro'           => 'Romanian',
   'ru'           => 'Russian',
   'sk'           => 'Slovak',
   'sr'           => 'Serbian',
   'sv'           => 'Swedish',			# Svenska
   'th'           => 'Thai',
   'tr'           => 'Turkish',
   'uk'           => 'Ukrainian',
   'ur'           => 'Urdu',
   'zh_CN.GB2312' => 'Chinese - Simplified',
   'zh_TW.Big5'   => 'Chinese - Traditional '
);

# the language charset for each language abbreviation
%languagecharsets =(
   'ar.CP1256'    => 'windows-1256',	
   'ar.ISO8859-6' => 'iso-8859-6',
   'bg'           => 'windows-1251',
   'ca'           => 'iso-8859-1',
   'cs'           => 'iso-8859-2',
   'da'           => 'iso-8859-1',
   'de'           => 'iso-8859-1',
   'en'           => 'iso-8859-1',
   'el'           => 'iso-8859-7',
   'es'           => 'iso-8859-1',
   'fi'           => 'iso-8859-1',
   'fr'           => 'iso-8859-1',
   'he.CP1255'    => 'windows-1255',
   'he.ISO8859-8' => 'iso-8859-8',
   'hu'           => 'iso-8859-2',
   'id'           => 'iso-8859-1',
   'it'           => 'iso-8859-1',
   'ja_JP.eucJP'     => 'euc-jp',
   'ja_JP.Shift_JIS' => 'shift_jis',
   'kr'           => 'euc-kr',
   'lt'           => 'windows-1257',
   'nl'           => 'iso-8859-1',
   'no'           => 'iso-8859-1',
   'pl'           => 'iso-8859-2',
   'pt'           => 'iso-8859-1',
   'pt_BR'        => 'iso-8859-1',
   'ro'           => 'iso-8859-2',
   'ru'           => 'koi8-r',
   'sk'           => 'iso-8859-2',
   'sr'           => 'iso-8859-2',
   'sv'           => 'iso-8859-1',
   'th'           => 'tis-620',
   'tr'           => 'iso-8859-9',
   'uk'           => 'koi8-u',
   'ur'           => 'utf-8',
   'zh_CN.GB2312' => 'gb2312',
   'zh_TW.Big5'   => 'big5',
   'utf-8'        => 'utf-8'		# charset only, use en lang/template
);

# HTTP_ACCEPT_LANGUAGE to owm lang
%httpaccept2language =(
   'ar'    => 'ar.CP1256',
   'he'    => 'he.CP1255',
   'iw'    => 'he.ISO8859-8',
   'in'    => 'id',
   'ja'    => 'ja_JP.Shift_JIS',
   'ko'    => 'kr',
   'pt-br' => 'pt_BR',
   'zh'    => 'zh_CN.GB2312',
   'zh-cn' => 'zh_CN.GB2312',
   'zh-sg' => 'zh_CN.GB2312',
   'zh-tw' => 'zh_TW.Big5',
   'zh-hk' => 'zh_TW.Big5'
);

@openwebmailrcitem=qw(
   language charset timeoffset daylightsaving email replyto
   style iconset bgurl bgrepeat fontsize dateformat hourformat
   ctrlposition_folderview msgsperpage fieldorder sort
   ctrlposition_msgread headers usefixedfont usesmileicon
   disablejs disableemblink showhtmlastext showimgaslink sendreceipt
   confirmmsgmovecopy defaultdestination smartdestination
   viewnextaftermsgmovecopy autopop3 autopop3wait moveoldmsgfrominbox
   msgformat editcolumns editrows sendbuttonposition
   reparagraphorigmsg replywithorigmsg backupsentmsg sendcharset
   filter_repeatlimit filter_badformatfrom
   filter_fakedsmtp filter_fakedfrom filter_fakedexecontenttype
   abook_width abook_height abook_buttonposition
   abook_defaultfilter abook_defaultsearchtype abook_defaultkeyword
   calendar_defaultview calendar_holidaydef
   calendar_monthviewnumitems calendar_weekstart
   calendar_starthour calendar_endhour calendar_interval calendar_showemptyhours
   calendar_reminderdays calendar_reminderforglobal
   webdisk_dirnumitems webdisk_confirmmovecopy webdisk_confirmdel
   webdisk_confirmcompress webdisk_fileeditcolumns  webdisk_fileeditrows
   regexmatch hideinternal refreshinterval newmailsound newmailwindowtime
   dictionary trashreserveddays sessiontimeout
);

%months = qw(Jan 1 Feb 2 Mar 3 Apr 4  May 5  Jun 6
             Jul 7 Aug 8 Sep 9 Oct 10 Nov 11 Dec 12);

@monthstr=qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
@wdaystr=qw(Sun Mon Tue Wed Thu Fri Sat);

%tzoffset = qw(
    ACDT +1030  ACST +0930  ADT  -0300  AEDT +1100  AEST +1000  AHDT -0900
    AHST -1000  AST  -0400  AT   -0200  AWDT +0900  AWST +0800  AZST +0400
    BAT  +0300  BDST +0200  BET  -1100  BST  -0300  BT   +0300  BZT2 -0300
    CADT +1030  CAST +0930  CAT  -1000  CCT  +0800  CDT  -0500  CED  +0200
    CEST +0200  CET  +0100  CST  -0600
    EAST +1000  EDT  -0400  EED  +0300  EET  +0200  EEST +0300  EST  -0500
    FST  +0200  FWT  +0100
    GMT  +0000  GST  +1000
    HDT  -0900  HST  -1000
    IDLE +1200  IDLW -1200  IST  +0530  IT   +0330
    JST  +0900  JT   +0700
    MDT  -0600  MED  +0200  MET  +0100  MEST +0200  MEWT +0100  MST  -0700
    MT   +0800
    NDT  -0230  NFT  -0330  NT   -1100  NST  +0630  NZ   +1100  NZST +1200
    NZDT +1300  NZT  +1200
    PDT  -0700  PST  -0800
    ROK  +0900
    SAD  +1000  SAST +0900  SAT  +0900  SDT  +1000  SST  +0200  SWT  +0100
    USZ3 +0400  USZ4 +0500  USZ5 +0600  USZ6 +0700  UT   +0000  UTC  +0000
    UZ10 +1100
    WAT  -0100  WET  +0000  WST  +0800
    YDT  -0800  YST  -0900
    ZP4  +0400  ZP5  +0500  ZP6  +0600);

%fontsize= (
   '8pt' => ['8pt',  '7pt'],
   '9pt' => ['8pt',  '7pt'],
   '10pt'=> ['9pt',  '8pt'],
   '11pt'=> ['10pt', '9pt'],
   '12pt'=> ['11pt', '10pt'],
   '13pt'=> ['12pt', '11pt'],
   '14pt'=> ['13pt', '12pt'],
   '11px'=> ['11px', '10px'],
   '12px'=> ['11px', '10px'],
   '13px'=> ['12px', '11px'],
   '14px'=> ['13px', '12px'],
   '15px'=> ['14px', '13px'],
   '16px'=> ['15px', '14px'],
   '17px'=> ['16px', '15px']
);

%pop3error=(
   -1  => "uidldb lock error",
   -2  => "uidldb open error",
   -3  => "spool write error",
   -11 => "connect error",
   -12 => "server not ready",
   -13 => "user name error",
   -14 => "password error",
   -15 => "pop3 'stat' error",
   -16 => "pop3 bad support",
   -17 => "pop3 'retr' error"
);

####################### OPEN/CLOSE_DBM ############################
sub open_dbm {
   my ($r_hash, $db, $flag, $perm)=@_;
   $perm=0600 if (!$perm);

   my ($openerror, $dbtype)=('', '');
   for (my $retry=0; $retry<3; $retry++) {
      if (!$config{'dbmopen_haslock'}) {
         if (! -f "$db$config{'dbm_ext'}") { # ensure dbm existance before lock
            my (%t, $createerror);
            dbmopen(%t, "$db$config{'dbmopen_ext'}", $perm) or $createerror=$!;
            dbmclose(%t);
            if ($createerror ne '') {
               writelog("db error - Unable to create $db$config{'dbm_ext'}, $createerror");
               return 0;
            } elsif (! -f "$db$config{'dbm_ext'}") {	# dbmopen ok but dbm file not found
               writelog("db error - Wrong dbm_ext/dbmopen_ext value in openwebmamil.conf?");
               return 0;
            }
         }
         if (! filelock("$db$config{'dbm_ext'}", $flag, $perm) ) {
            writelog("db error - Couldn't lock $db$config{'dbm_ext'}");
            return 0;
         }
      }

      return 1 if (dbmopen(%{$r_hash}, "$db$config{'dbmopen_ext'}", $perm));
      $openerror=$!;

      filelock("$db$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

      # db may be temporarily unavailable because of too many concurrent accesses,
      # eg: reading a message with lots of attachments
      if ($openerror=~/Resource temporarily unavailable/) {
         writelog("db warning - $db$config{'dbm_ext'} temporarily unavailable, retry ".($retry+1));
         sleep 1;
         next;
      }

      # if existing db is in wrong format, then unlink it and create a new one
      if ( -f "$db$config{'dbm_ext'}" && -r _ && $dbtype eq '') {
         $dbtype=get_dbtype("$db$config{'dbm_ext'}");
         if ($dbtype ne default_dbtype()) {	# db is in wrong format
            if (unlink("$db$config{'dbm_ext'}") ) {
               writelog("db warning - unlink $db$config{'dbm_ext'} to change db format, $dbtype -> ".default_dbtype());
               writehistory("db warning - unlink $db$config{'dbm_ext'} to change db format, $dbtype -> ".default_dbtype());
               next;
            } else {
               writelog("db error - wrong db format, default:".default_dbtype().", $db$config{'dbm_ext'}:$dbtype");
            }
         }
      }

      last;	# default to exit the loop
   }
   writelog("db error - Couldn't open db $db$config{'dbm_ext'}, $openerror");
   return 0;
}

sub close_dbm {
   my ($r_hash, $db)=@_;

   dbmclose(%{$r_hash});
   filelock("$db$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   return 1;
}

use vars qw($_default_dbtype);
sub default_dbtype {
   if ($_default_dbtype eq '') {
      my $t="/tmp/.dbmtest.$$";  ($t =~ /^(.+)$/) && ($t = $1);
      my %t; dbmopen(%t, "$t$config{'dbmopen_ext'}", 0600); dbmclose(%t);

      $_default_dbtype=get_dbtype("$t$config{'dbm_ext'}");

      unlink ("$t$config{'dbm_ext'}", "$t.dir", "$t.pag");
    }
    return($_default_dbtype);
}

sub get_dbtype {
   my $f="/tmp/.flist.$$";  ($f =~ /^(.+)$/) && ($f = $1);
   open(F, ">$f"); print F "$_[0]\n"; close(F);	# pass arg through file for safety

   my $dbtype=`/usr/bin/file -f $f`; unlink($f);
   $dbtype=~s/^.*?:\s*//; $dbtype=~s/\s*$//;

   return($dbtype);
}
####################### END OPEN/CLOSE_DBM ############################

###################### CLEARVAR/ENDREQUEST/EXIT ###################
use vars qw($_vars_used);
sub openwebmail_clearall {
   # clear gobal variable for persistent perl
   undef(%SIG);
   undef(%config);
   undef(%config_raw);
   undef($thissession);
   undef(%icontext);

   undef($loginname);
   undef($logindomain);
   undef($loginuser);

   undef($domain);
   undef($user);
   undef($userrealname);
   undef($uuid);
   undef($ugid);
   undef($homedir);
   undef(%prefs);

   undef($quotausage);
   undef($quotalimit);

   undef($folderdir);
   undef(@validfolders);
   undef($folderusage);
   undef($folder);
   undef($printfolder);
   undef($escapedfolder);

   # clear opentable in filelock.pl
   openwebmail::filelock::closeall() if (defined(%openwebmail::filelock::opentable));

   # chdir back to openwebmail cgidir
   chdir($config{'ow_cgidir'}) if ($config{'ow_cgidir'});

   # back euid to root if possible, required for setuid under persistent perl
   $>=0;
}

# routine used at CGI request begin
sub openwebmail_requestbegin {
   openwebmail_clearall() if ($_vars_used);
   $_vars_used=1;
}

# routine used at CGI request end
sub openwebmail_requestend {
   openwebmail_clearall() if ($_vars_used);
   $_vars_used=0;
   $persistence_count++;
}

# routine used at exit
sub openwebmail_exit {
   openwebmail_requestend();
   exit $_[0];
}
#################### END CLEARVAR/ENDREQUEST/EXIT ###################

###################### USERENV_INIT ###################
# init user globals, switch euid
sub userenv_init {
   if (!defined(%default_config_raw)) {	# read default only once if persistent mode
      readconf(\%default_config, \%default_config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
   }
   %config=%default_config; %config_raw =%default_config_raw;
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
   readlang($config{'default_language'});	# so %lang... can be used in error msg

   if ($config{'smtpauth'}) {	# load smtp auth user/pass
      readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/smtpauth.conf");
      if ($config{'smtpauth_username'} eq "" || $config{'smtpauth_password'} eq "") {
         openwebmailerror(__FILE__, __LINE__, "$SCRIPT_DIR/etc/smtpauth.conf $lang_err{'param_fmterr'}");
      }
   }

   if (!defined(param("sessionid")) ) {
      my $clientip=get_clientip();
      sleep $config{'loginerrordelay'} if ($clientip ne "127.0.0.1");	# delayed response for non localhost
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'param_fmterr'}, $lang_err{'access_denied'}");
   }
   $thissession = param("sessionid");
   $thissession =~ s!\.\.+!!g;  # remove ..

   # sessionid format: loginname+domain-session-0.xxxxxxxxxx
   if ($thissession =~ /^([\w\.\-\%\@]+)\*([\w\.\-]*)\-session\-(0\.\d+)$/) {
      $thissession = $1."*".$2."-session-".$3;	# untaint
      ($loginname, $default_logindomain)=($1, $2); # param from sessionid
   } else {
      openwebmailerror(__FILE__, __LINE__, "Session ID $thissession $lang_err{'has_illegal_chars'}");
   }

   ($logindomain, $loginuser)=login_name2domainuser($loginname, $default_logindomain);

   if (!is_localuser("$loginuser\@$logindomain") &&  -f "$config{'ow_sitesconfdir'}/$logindomain") {
      readconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   }
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
       ($config{'mailspooldir'} eq "/var/mail" ||
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "Content-type: text/html\n\n'$0' must setuid to root"; openwebmail_exit(0);
   }
   loadauth($config{'auth_module'});

   $user='';
   # try userinfo cached in session file first
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
	=split(/\@\@\@/, (sessioninfo($thissession))[2]) if ($config{'cache_userinfo'});
   # use userinfo from auth server if user is root or null
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
	=get_domain_user_userinfo($logindomain, $loginuser) if (!$user||$uuid==0||$ugid=~/\b0\b/);

   if ($user eq "") {
      sleep $config{'loginerrordelay'};	# delayed response
      openwebmailerror(__FILE__, __LINE__, "$loginuser@$logindomain $lang_err{'user_not_exist'}!");
   }
   if (!$config{'enable_rootlogin'}) {
      if ($user eq 'root' || $uuid==0) {
         sleep $config{'loginerrordelay'};	# delayed response
         writelog("userinfo error - possible root hacking attempt");
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'norootlogin'}");
      }
   }

   # load user config
   my $userconf="$config{'ow_usersconfdir'}/$user";
   $userconf="$config{'ow_usersconfdir'}/$domain/$user" if ($config{'auth_withdomain'});
   readconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

   # override auto guessing domainanmes if loginame has domain
   if ($config_raw{'domainnames'} eq 'auto' && $loginname=~/\@/) {
      $config{'domainnames'}=[ $logindomain ];
   }
   # override realname if defined in config
   if ($config{'default_realname'} ne 'auto') {
      $userrealname=$config{'default_realname'}
   }

   if ( !$config{'use_syshomedir'} ) {
      $homedir = "$config{'ow_usersdir'}/$user";
      $homedir = "$config{'ow_usersdir'}/$domain/$user" if ($config{'auth_withdomain'});
   }
   $folderdir = "$homedir/$config{'homedirfolderdirname'}";

   ($user =~ /^(.+)$/) && ($user = $1);  # untaint ...
   ($uuid =~ /^(.+)$/) && ($uuid = $1);
   ($ugid =~ /^(.+)$/) && ($ugid = $1);
   ($homedir =~ /^(.+)$/) && ($homedir = $1);
   ($folderdir =~ /^(.+)$/) && ($folderdir = $1);

   umask(0077);
   if ( $>==0 ) {			# switch to uuid:mailgid if script is setuid root.
      my $mailgid=getgrnam('mail');	# for better compatibility with other mail progs
      set_euid_egids($uuid, $mailgid, $ugid);
      if ( $)!~/\b$mailgid\b/) { # group mail doesn't exist?
         openwebmailerror(__FILE__, __LINE__, "Set effective gid to mail($mailgid) failed!");
      }
   }

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   readlang($prefs{'language'});

   verifysession();

   if ($prefs{'iconset'}=~ /^Text\./) {
      ($prefs{'iconset'} =~ /^([\w\d\.\-_]+)$/) && ($prefs{'iconset'} = $1);
      my $icontext="$config{'ow_htmldir'}/images/iconsets/$prefs{'iconset'}/icontext";
      ($icontext =~ /^(.+)$/) && ($icontext = $1);  # untaint ...
      delete $INC{$icontext};
      require $icontext;
   }

   if ($config{'quota_module'} ne "none") {
      loadquota($config{'quota_module'});

      my ($ret, $errmsg);
      ($ret, $errmsg, $quotausage, $quotalimit)=quota_get_usage_limit(\%config, $user, $homedir, 0);
      if ($ret==-1) {
         writelog("quota error - $config{'quota_module'}, ret $ret, $errmsg");
         openwebmailerror(__FILE__, __LINE__, "Quota $lang_err{'param_fmterr'}");
      } elsif ($ret<0) {
         writelog("quota error - $config{'quota_module'}, ret $ret, $errmsg");
         openwebmailerror(__FILE__, __LINE__, $lang_err{'quota_syserr'});
      }
      $quotalimit=$config{'quota_limit'} if ($quotalimit<0);
   } else {
      ($quotausage, $quotalimit)=(0,0);
   }

   getfolders(\@validfolders, \$folderusage);
   if (param("folder")) {
      my $isvalid = 0;
      $folder = param("folder");
      foreach (@validfolders) {
         if ($folder eq $_) {
            $isvalid = 1; last;
         }
      }
      ($folder = 'INBOX') if (!$isvalid );
   } else {
      $folder = "INBOX";
   }
   $printfolder = $lang_folders{$folder} || $folder || '';
   $escapedfolder = escapeURL($folder);
   return;
}
#################### END USERENV_INIT ###################

############ LOGINNAME 2 LOGINDOMAIN LOGINUSER ##############
sub login_name2domainuser {
   my ($loginname, $default_logindomain)=@_;
   my ($logindomain, $loginuser);
   if ($loginname=~/^(.+)\@(.+)$/) {
      ($loginuser, $logindomain)=($1, $2);
   } else {
      $loginuser=$loginname;
      $logindomain=$default_logindomain||$ENV{'HTTP_HOST'}||hostname();
      $logindomain=~s/:\d+$//;	# remove port number
   }
   $loginuser=lc($loginuser) if ($config{'case_insensitive_login'});
   $logindomain=lc(safedomainname($logindomain));
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain} if (defined($config{'domainname_equiv'}{'map'}{$logindomain}));
   return($logindomain, $loginuser);
}
######### END LOGINNAME 2 LOGINDOMAIN LOGINUSER ###########

############ IS_LOCALUSER ##############
sub is_localuser {
   my $localuser=$_[0];
   foreach  ( @{$config{'localusers'}} ) {
      return 1 if ( /^$localuser$/ );
   }
   return 0;
}
############ END IS_LOCALUSER ##############

####################### READCONF #######################
# read openwebmail.conf into a hash
# the hash is 'called by reference' since we want to do 'bypass taint' on it
sub readconf {
   my ($r_config, $r_config_raw, $configfile)=@_;
   if ($configfile=~/\.\./) {	# .. in path is not allowed for higher security
      openwebmailerror(__FILE__, __LINE__, "Invalid config file path $configfile!");
   }

   open(CONFIG, $configfile) or
      openwebmailerror(__FILE__, __LINE__, "Couldn't open config file $configfile! ($!)");
   my ($key, $value)=("", "");
   my $blockmode=0;
   while ((my $line=<CONFIG>)) {
      $line=~s/\s+$//;
      if ($blockmode) {
         if ( $line =~ m!</$key>! ) {
            $blockmode=0;
         } else {
            ${$r_config_raw}{$key} .= "$line\n";
         }
      } else {
         $line=~s/#.*$//;
         $line=~s/^\s+//; $line=~s/\s+$//;
         next if ($line=~/^#/);

         if ( $line =~ m!^<(.+)>$! ) {
            $key=$1; $key=~s/^\s+//; $key=~s/\s+$//;
            ${$r_config_raw}{$key}="";
            $blockmode=1;
         } else {
            ($key, $value)=split(/\s+/, $line, 2);

            # backward compatibility
            $key='use_syshomedir'    if ($key eq 'use_homedirfolders');
            $key='create_syshomedir' if ($key eq 'create_homedir');

            if ($key ne "" && $value ne "" ) {
               ${$r_config_raw}{$key}=$value;
            }
         }
      }
   }
   close(CONFIG);

   # copy config_raw to config
   %{$r_config}=%{$r_config_raw};
   # turn ow_htmlurl from / to null to avoid // in url
   ${$r_config}{'ow_htmlurl'}='' if (${$r_config}{'ow_htmlurl'} eq '/');

   # resolv %var% in hash config
   foreach $key (keys %{$r_config}) {
      for (my $i=0; $i<5; $i++) {
        last if (${$r_config}{$key} !~ s/\%([\w\d_]+)\%/${$r_config}{$1}/msg);
      }
   }

   # processing yes/no
   foreach $key (qw(
      smtpauth use_hashedmailspools use_dotlockfile dbmopen_haslock
      use_syshomedir create_syshomedir use_homedirspools
      auth_withdomain deliver_use_GMT savedsuid_support
      error_with_debuginfo
      case_insensitive_login forced_ssl_login stay_ssl_afterlogin
      enable_rootlogin enable_domainselectmenu enable_strictvirtuser
      enable_changepwd enable_strictpwd enable_setfrom enable_setfromemail
      session_multilogin session_checksameip session_checkcookie
      cache_userinfo
      auto_createrc domainnames_override symboliclink_mbox
      enable_history enable_about about_info_software about_info_protocol
      about_info_server about_info_client about_info_scriptfilename
      xmailer_has_version xoriginatingip_has_userid
      enable_preference enable_setforward enable_strictforward
      enable_autoreply enable_strictfoldername enable_stationery
      enable_smartfilters enable_userfilter
      enable_webmail enable_calendar enable_webdisk enable_sshterm enable_vdomain
      enable_pop3 delpop3mail_by_default delpop3mail_hidden getmail_from_pop3_authserver
      webdisk_readonly webdisk_lsmailfolder webdisk_lshidden webdisk_lsunixspec webdisk_lssymlink
      webdisk_allow_symlinkcreate webdisk_allow_symlinkout webdisk_allow_thumbnail
      delmail_ifquotahit delfile_ifquotahit
      default_bgrepeat
      default_confirmmsgmovecopy default_viewnextaftermsgmovecopy
      default_moveoldmsgfrominbox forced_moveoldmsgfrominbox
      default_autopop3 default_hideinternal
      default_disablejs
      default_showhtmlastext default_showimgaslink
      default_regexmatch
      default_usefixedfont default_usesmileicon
      default_reparagraphorigmsg default_backupsentmsg
      default_abook_defaultfilter
      default_filter_badformatfrom default_filter_fakedsmtp
      default_filter_fakedfrom default_filter_fakedexecontenttype
      default_calendar_showemptyhours default_calendar_reminderforglobal
      default_webdisk_confirmmovecopy default_webdisk_confirmdel
      default_webdisk_confirmcompress
   )) {
      if (${$r_config}{$key} =~ /yes/i || ${$r_config}{$key} == 1) {
         ${$r_config}{$key}=1;
      } else {
         ${$r_config}{$key}=0;
      }
   }

   # process domain equiv table
   my %equiv=();
   my %equivlist=();
   if ( ${$r_config}{'domainname_equiv'} ne "") {
      foreach (split(/\n/, ${$r_config}{'domainname_equiv'})) {
         s/^[:,\s]+//g; s/[:,\s]+$//g;
         my ($dst, @srclist)=split(/[:,\s]+/);
         $equivlist{$dst}=\@srclist;
         foreach my $src (@srclist) {
            $equiv{$src}=$dst if ($src && $dst);
         }
      }
   }
   ${$r_config}{'domainname_equiv'}= {
      map => \%equiv,		# src -> dst
      list=> \%equivlist	# dst <= srclist
   };

   # processing auto
   if ( ${$r_config}{'domainnames'} eq 'auto' ) {
      if ($ENV{'HTTP_HOST'}=~/[A-Za-z]\./) {
         $value=$ENV{'HTTP_HOST'}; $value=~s/:\d+$//;	# remove port number
      } else {
         $value=hostname();
      }
      ${$r_config}{'domainnames'}=$value;
   }
   if ( ${$r_config}{'domainselmenu_list'} eq 'auto' ) {
      ${$r_config}{'domainselmenu_list'}=${$r_config}{'domainnames'};
   }
   if ( ${$r_config}{'default_timeoffset'} eq 'auto' ) {
      ${$r_config}{'default_timeoffset'}=gettimeoffset();
   }
   if ( ${$r_config}{'default_language'} eq 'auto' ) {
      ${$r_config}{'default_language'}=guess_language();
   }

   # processing list
   foreach $key (qw(
      domainnames domainselmenu_list spellcheck_dictionaries
      allowed_serverdomain
      allowed_clientdomain allowed_clientip
      allowed_receiverdomain disallowed_pop3servers
      vdomain_admlist vdomain_postfix_aliases vdomain_postfix_virtual localusers
      default_fromemails
   )) {
      my $liststr=${$r_config}{$key}; $liststr=~s/\s//g;
      my @list=split(/,/, $liststr);
      ${$r_config}{$key}=\@list;
   }

   # processing none
   if ( ${$r_config}{'default_bgurl'} eq 'none'|| ${$r_config}{'default_bgurl'} eq '""' ) {
      $value="${$r_config}{'ow_htmlurl'}/images/backgrounds/Transparent.gif";
      ${$r_config}{'default_bgurl'}=$value;
   }
   if ( ${$r_config}{'default_abook_defaultsearchtype'} eq 'none'|| ${$r_config}{'default_abook_defaultsearchtype'} eq '""' ) {
      ${$r_config}{'default_abook_defaultsearchtype'}="name";
   }
   foreach $key ( qw(dbmopen_ext default_realname default_abook_defaultkeyword) ){
      if ( ${$r_config}{$key} eq 'none' || ${$r_config}{$key} eq '""' ) {
         ${$r_config}{$key}="";
      }
   }

   # remove / and .. from variables that will be used in require statement for security
   foreach $key ( 'default_language', 'auth_module') {
      ${$r_config}{$key} =~ s|/||g;
      ${$r_config}{$key} =~ s|\.\.||g;
   }
   # untaint pathname variable defined in openwebmail.conf
   foreach $key (
      'smtpserver', 'auth_module', 'virtusertable',
      'mailspooldir', 'homedirspoolname', 'homedirfolderdirname',
      'dbm_ext', 'dbmopen_ext',
      'ow_cgidir', 'ow_htmldir','ow_etcdir', 'logfile',
      'ow_stylesdir', 'ow_langdir', 'ow_templatesdir',
      'ow_sitesconfdir', 'ow_usersconfdir',
      'ow_usersdir', 'ow_sessionsdir', 'html_plugin',
      'vacationinit', 'vacationpipe', 'spellcheck',
      'global_addressbook', 'global_filterbook', 'global_calendarbook',
      'pop3_authserver', 'pop3_authport',
      'vdomain_vmpop3_pwdpath', 'vdomain_vmpop3_pwdname', 'vdomain_vmpop3_mailpath',
      'vdomain_postfix_postalias', 'vdomain_postfix_postmap'
   ) {
      (${$r_config}{$key} =~ /^(.+)$/) && (${$r_config}{$key}=$1);
   }
   foreach ( @{${$r_config}{'domainnames'}} ) {
      (/^(.+)$/) && ($_=$1);
   }
   foreach ( @{${$r_config}{'vdomain_postfix_aliases'}} ) {
      (/^(.+)$/) && ($_=$1);
   }
   foreach ( @{${$r_config}{'vdomain_postfix_virtual'}} ) {
      (/^(.+)$/) && ($_=$1);
   }
   return 0;
}
##################### END READCONF #######################

##################### GUESS_LANGUAGE ########################
sub guess_language {
   my @lang;
   foreach ( split(/[,;\s]+/, lc($ENV{'HTTP_ACCEPT_LANGUAGE'})) ) {
      push(@lang, $_) if (/^[a-z\-_]+$/);
      push(@lang, $1) if (/^([a-z]+)\-[a-z]+$/ ); # eg: zh-tw -> zh
   }
   foreach my $lang (@lang) {
      return $lang                       if (defined($languagenames{$lang}));
      return $httpaccept2language{$lang} if (defined($httpaccept2language{$lang}));
   }
   return('en');
}
################### END GUESS_LANGUAGE ########################

###################### LOADAUTH/LOADQUOTA #####################
# use 'require' to load the package openwebmail::$file
# then alias symbos of routines in package openwebmail::$file to
# current(main::) package through Glob and 'tricky' symbolic reference feature
sub loadmodule {
   my ($file, @symlist)=@_;
   $file=~s|/||g; $file=~s|\.\.||g; # remove / and .. to anti path hack

   # . - is not allowed for package name
   my $pkg=$file; $pkg=~s/\.pl//; $pkg=~s/[\.\-]/_/g;

   $file="$config{'ow_cgidir'}/$file";
   ($file=~ /^(.*)$/) && ($file = $1);
   require $file; # done only once because of %INC

   no strict 'refs';	# until block end
   # traverse the symbo table of package openwebmail::$pkg
   foreach my $sym (@symlist) {
      # alias symbo of sub routine into current package
      *{"$sym"}=*{"openwebmail::".$pkg."::".$sym};
   }
   return;
}

sub loadauth {
   loadmodule($_[0], "get_userinfo",
                     "get_userlist",
                     "check_userpassword",
                     "change_userpassword");
}

sub loadquota {
   loadmodule($_[0], "get_usage_limit");
}

use vars qw($_zliberr);
sub has_zlib {
   return 1 if (defined($INC{'Compress/Zlib.pm'}));
   return 0 if ($_zliberr);
   eval { require "Compress/Zlib.pm"; };
   if ($@) {
      $_zliberr=1; return 0;
   } else {
      return 1;
   }
}
###################### END LOADAUTH/LOADQUOTA #####################

##################### QUOTA_GET_USAGE_LIMIT ###################
sub quota_get_usage_limit {
   my ($origruid, $origeuid)=($<, $>);
   $>=0; $<=0;				# set ruid/euid to root before quota query
   my @ret=get_usage_limit(@_);
   $<=$origruid; $>=$origeuid;		# fall back to original ruid/euid
   return(@ret);
}
################### END QUOTA_GET_USAGE_LIMIT #################

##################### VIRTUALUSER related ################
sub update_virtusertable {
   my ($virdb, $virfile)=@_;
   my (%DB, %DBR, $metainfo);

   ($virdb =~ /^(.+)$/) && ($virdb = $1);		# untaint ...

   if (! -e $virfile) {
      unlink("$virdb$config{'dbm_ext'}") if (-e "$virdb$config{'dbm_ext'}");
      unlink("$virdb.rev$config{'dbm_ext'}") if (-e "$virdb.rev$config{'dbm_ext'}");
      return;
   }

   if ( -e "$virdb$config{'dbm_ext'}" ) {
      my $metainfo;
      open_dbm(\%DB, $virdb, LOCK_SH) or return;
      $metainfo=$DB{'METAINFO'};
      close_dbm(\%DB, $virdb);

      return if ( $metainfo eq metainfo($virfile) );
   }

   writelog("update $virdb");

   unlink("$virdb$config{'dbm_ext'}",
          "$virdb.rev$config{'dbm_ext'}",);

   open_dbm(\%DB, $virdb, LOCK_EX, 0644) or return;
   if (!open_dbm(\%DBR, "$virdb.rev", LOCK_EX, 0644)) {
      close_dbm(\%DB, $virdb);
      return;
   }
   %DB=();	# ensure the virdb is empty
   %DBR=();

   open (VIRT, $virfile);
   while (<VIRT>) {
      s/^\s+//; s/\s+$//; s/#.*$//;
      s/(.*?)\@(.*?)%1/$1\@$2$1/;	# resolve %1 in virtusertable

      my ($vu, $u)=split(/[\s\t]+/);
      next if ($vu eq "" || $u eq "");
      next if ($vu =~ /^@/);	# don't care entries for whole domain mapping

      $DB{$vu}=$u;
      if ( defined($DBR{$u}) ) {
         $DBR{$u}.=",$vu";
      } else {
         $DBR{$u}.="$vu";
      }
   }
   close(VIRT);

   $DB{'METAINFO'}=metainfo($virfile);

   close_dbm(\%DBR, "$virdb.rev");
   close_dbm(\%DB, $virdb);
   chmod(0644, "$virdb.rev$config{'dbm_ext'}", "$virdb$config{'dbm_ext'}");
   return;
}

sub get_user_by_virtualuser {
   my ($vu, $virdb)=@_;
   my %DB=();
   my $u='';

   if ( -f "$virdb$config{'dbm_ext'}" && !-z "$virdb$config{'dbm_ext'}" ) {
      open_dbm(\%DB, $virdb, LOCK_SH) or return $u;;
      $u=$DB{$vu};
      close_dbm(\%DB, $virdb);
   }
   return($u);
}

sub get_virtualuser_by_user {
   my ($user, $virdbr)=@_;
   my %DBR=();
   my $vu='';

   if ( -f "$virdbr$config{'dbm_ext'}" && !-z "$virdbr$config{'dbm_ext'}" ) {
      open_dbm(\%DBR, $virdbr, LOCK_SH) or return $vu;
      $vu=$DBR{$user};
      close_dbm(\%DBR, $virdbr);
   }
   return($vu);
}

sub get_domain_user_userinfo {
   my ($logindomain, $loginuser)=@_;
   my ($domain, $user, $realname, $uid, $gid, $homedir);

   my $virtname=$config{'virtusertable'}; $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   $user=get_user_by_virtualuser("$loginuser", "$config{'ow_etcdir'}/$virtname");
   if ($user eq "") {
      my @domainlist=($logindomain);
      if (defined(@{$config{'domain_equiv'}{'list'}{$logindomain}})) {
         push(@domainlist, @{$config{'domain_equiv'}{'list'}{$logindomain}});
      }
      foreach (@domainlist) {
         $user=get_user_by_virtualuser("$loginuser\@$_", "$config{'ow_etcdir'}/$virtname");
         last if ($user);
      }
   }

   if ($user=~/^(.*)\@(.*)$/) {
      ($user, $domain)=($1, lc($2));
   } else {
      if (!$user) {
         if ($config{'enable_strictvirtuser'}) {
            # if the loginuser is mapped in virtusertable by any vuser,
            # then one of the vuser should be used instead of loginname for login
            my $vu=get_virtualuser_by_user($loginuser, "$config{'ow_etcdir'}/$virtname.rev");
            return("", "", "", "", "", "") if ($vu);
         }
         $user=$loginuser;
      }
      if($config{'auth_domain'} ne 'auto') {
         $domain=lc($config{'auth_domain'});
      } else {
         $domain=$logindomain;
      }
   }

   my ($errcode, $errmsg);
   if ($config{'auth_withdomain'}) {
      ($errcode, $errmsg, $realname, $uid, $gid, $homedir)=get_userinfo(\%config, "$user\@$domain");
   } else {
      ($errcode, $errmsg, $realname, $uid, $gid, $homedir)=get_userinfo(\%config, $user);
   }
   writelog("userinfo error - $config{'auth_module'}, ret $errcode, $errmsg") if ($errcode!=0);

   $realname=$loginuser if ($realname eq "");
   if ($uid ne "") {
      return($domain, $user, $realname, $uid, $gid, $homedir);
   } else {
      return("", "", "", "", "", "");
   }
}
##################### END VIRTUALUSER related ################

##################### GET_DEFAULTEMAILS, GET_USERFROM ################
sub get_defaultemails {
   my ($logindomain, $loginuser, $user)=@_;
   return (@{$config{'default_fromemails'}}) if ($config_raw{'default_fromemails'} ne "auto");

   my %emails=();
   my $virtname=$config{'virtusertable'};  $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   my $vu=get_virtualuser_by_user($user, "$config{'ow_etcdir'}/$virtname.rev");
   if ($vu ne "") {
      foreach my $name (str2list($vu,0)) {
         if ($name=~/^(.*)\@(.*)$/) {
            next if ($1 eq "");	# skip whole @domain mapping
            if ($config{'domainnames_override'}) {
               my $purename=$1;
               foreach my $host (@{$config{'domainnames'}}) {
                  $emails{"$purename\@$host"}=1;
               }
            } else {
               $emails{$name}=1;
            }
         } else {
            foreach my $host (@{$config{'domainnames'}}) {
               $emails{"$name\@$host"}=1
            }
         }
      }
   } else {
      foreach my $host (@{$config{'domainnames'}}) {
         $emails{"$loginuser\@$host"}=1;
      }
   }

   return(keys %emails);
}

sub get_userfrom {
   my ($logindomain, $loginuser, $user, $realname, $frombook)=@_;
   my %from=();

   # get default fromemail
   my @defaultemails=get_defaultemails($logindomain, $loginuser, $user);
   foreach (@defaultemails) {
      $from{$_}=$realname;
   }

   # get user defined fromemail
   if ($config{'enable_setfrom'} && open(FROMBOOK, $frombook)) {
      while (<FROMBOOK>) {
         my ($_email, $_realname) = split(/\@\@\@/, $_, 2);
         chomp($_realname);
         if ( defined($from{"$_email"}) || $config{'enable_setfromemail'} ) {
             $from{"$_email"} = $_realname;
         }
      }
      close (FROMBOOK);
   }

   return(%from);
}

sub sort_emails_by_domainnames {
   my $r_domainnames=shift(@_);
   my @email=sort(@_);

   my @result;
   foreach my $domain (@{$r_domainnames}) {
      for (my $i=0; $i<=$#email; $i++) {
         if ($email[$i]=~/\@$domain$/) {
            push(@result, $email[$i]); $email[$i]='';
         }
      }
   }
   for (my $i=0; $i<=$#email; $i++) {
      push(@result, $email[$i]) if ($email[$i]);
   }

   return(@result);
}
##################### END GET_DEFAULTEMAILS GET_USERFROM ################

###################### READPREFS #########################
sub readprefs {
   my (%prefshash, $key, $value);

   # read .openwebmailrc
   if ( -f "$folderdir/.openwebmailrc" ) {
      open (RC, "$folderdir/.openwebmailrc") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.openwebmailrc! ($!)");
      while (<RC>) {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         if ($key eq 'style') {
            $value =~ s/^\.//g;  ## In case someone gets a bright idea...
         }
         $prefshash{"$key"} = $value;
      }
      close (RC);
   }

   # read .signature
   my $signaturefile="";
   if ( -f "$folderdir/.signature" ) {
      $signaturefile="$folderdir/.signature";
   } elsif ( -f "$homedir/.signature" ) {
      $signaturefile="$homedir/.signature";
   }
   if ($signaturefile) {
      $prefshash{"signature"} = '';
      open (SIGNATURE, $signaturefile) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $signaturefile! ($!)");
      while (<SIGNATURE>) {
         $prefshash{"signature"} .= $_;
      }
      close (SIGNATURE);
   }
   $prefshash{"signature"}=~s/\s+$/\n/;

   # get default value from config for err/undefined/empty prefs entries

   # validate email with defaultemails if setfromemail is not allowed
   if (!$config{'enable_setfromemail'} || $prefshash{'email'} eq "") {
      my @defaultemails=get_defaultemails($logindomain, $loginuser, $user);
      my $valid=0;
      foreach (@defaultemails) {
         if ($prefshash{'email'} eq $_) {
            $valid=1; last;
         }
      }
      $prefshash{'email'}=$defaultemails[0] if (!$valid);
   }

   # all rc entries are disallowed to be empty
   foreach $key (@openwebmailrcitem) {
      if (defined($config{'DEFAULT_'.$key})) {
         $prefshash{$key}=$config{'DEFAULT_'.$key};
      } elsif ((!defined($prefshash{$key})||$prefshash{$key} eq "") &&
               defined($config{'default_'.$key}) ) {
         $prefshash{$key}=$config{'default_'.$key};
      }
   }
   # signature allowed to be empty but not undefined
   foreach $key ( 'signature') {
      if (defined($config{'DEFAULT_'.$key})) {
         $prefshash{$key}=$config{'DEFAULT_'.$key};
      } elsif (!defined($prefshash{$key}) &&
               defined($config{'default_'.$key}) ) {
         $prefshash{$key}=$config{'default_'.$key};
      }
   }

   # remove / and .. from variables that will be used in require statement for security
   $prefshash{'language'}=~s|/||g; $prefshash{'language'}=~s|\.\.||g;
   $prefshash{'iconset'}=~s|/||g;  $prefshash{'iconset'}=~s|\.\.||g;

   # adjust bgurl in case the OWM has been reinstalled in different place
   if ( $prefshash{'bgurl'}=~m!^(/.+)/images/backgrounds/(.*)$! &&
        $1 ne $config{'ow_htmlurl'} &&
        -f "$config{'ow_htmldir'}/images/backgrounds/$2") {
      $prefshash{'bgurl'}="$config{'ow_htmlurl'}/images/backgrounds/$2";
   }

   # entries related to ondisk dir or file
   $prefshash{'language'}=$config{'default_language'} if (!-f "$config{'ow_langdir'}/$prefshash{'language'}");
   $prefshash{'style'}=$config{'default_style'} if (!-f "$config{'ow_stylesdir'}/$prefshash{'style'}");
   $prefshash{'iconset'}=$config{'default_iconset'} if (!-d "$config{'ow_htmldir'}/images/iconsets/$prefshash{'iconset'}");

   $prefshash{'refreshinterval'}=$config{'min_refreshinterval'} if ($prefshash{'refreshinterval'} < $config{'min_refreshinterval'});
   $prefshash{'charset'}=$languagecharsets{$prefshash{'language'}} if ($prefshash{'charset'} eq "auto");

   return %prefshash;
}
##################### END READPREFS ######################

###################### READSTYLE #########################
# this routine must be called after readprefs
# since it references $prefs{'bgurl'} & prefs{'bgrepeat'}
use vars qw(%_stylecache);
sub readstyle {
   my $stylefile = $_[0] || 'Default';
   $stylefile = 'Default' if (!-f "$config{'ow_stylesdir'}/$stylefile");

   if (!defined($_stylecache{$stylefile})) {
      my (%hash, $key, $value);
      open (STYLE,"$config{'ow_stylesdir'}/$stylefile") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_stylesdir'}/$stylefile! ($!)");
      while (<STYLE>) {
         if (/###STARTSTYLESHEET###/) {
            $hash{'css'} = '';
            while (<STYLE>) {
               $hash{'css'} .= $_;
            }
         } else {
            ($key, $value) = split(/=/, $_);
            chomp($value);
            $hash{$key} = $value;
         }
      }
      close (STYLE);
      $_stylecache{$stylefile}=\%hash;
   }

   my %stylehash=%{$_stylecache{$stylefile}};	# copied from style cache

   $stylehash{'css'}=~ s/\@\@\@BG_URL\@\@\@/$prefs{'bgurl'}/g;
   if ($prefs{'bgrepeat'}) {
      $stylehash{'css'}=~ s/\@\@\@BGREPEAT\@\@\@/repeat/g;
   } else {
      $stylehash{'css'}=~ s/\@\@\@BGREPEAT\@\@\@/no-repeat/g;
   }
   $stylehash{'css'}=~ s/\@\@\@FONTSIZE\@\@\@/$prefs{'fontsize'}/g;
   $stylehash{'css'}=~ s/\@\@\@MEDFONTSIZE\@\@\@/${$fontsize{$prefs{'fontsize'}}}[0]/g;
   $stylehash{'css'}=~ s/\@\@\@SMALLFONTSIZE\@\@\@/${$fontsize{$prefs{'fontsize'}}}[1]/g;
   if ($prefs{'usefixedfont'}) {
      $stylehash{'css'}=~ s/\@\@\@FIXEDFONT\@\@\@/"Courier 10 Pitch", "Courier New", "Courier", "Lucida Console", monospace, /g;
   } else {
      $stylehash{'css'}=~ s/\@\@\@FIXEDFONT\@\@\@//g;
   }
   return %stylehash;
}
##################### END READSTYLE ######################

###################### READLANG #########################
# use 'require' to load the package openwebmail::$lang
# then aliasing symbos in package openwebmail::$lang to current package
# through Glob and 'tricky' symbolic reference feature
sub readlang {
   my $langfile=$_[0]||'en';
   $langfile=~s|/||g; $langfile=~s|\.\.||g; # remove / and .. for path hack
   $langfile='en' if (!-f "$config{'ow_langdir'}/$langfile");

   # . - is not allowed for package name
   my $pkg= $langfile; $pkg=~s/[\.\-]/_/g;

   $langfile="$config{'ow_langdir'}/$langfile";
   ($langfile=~ /^(.*)$/) && ($langfile = $1);
   require $langfile;	# done only once because of %INC

   no strict 'refs';	# until block end
   # traverse the symbo table of package openwebmail::$pkg
   foreach my $sym ( keys %{"openwebmail::".$pkg."::"} ) {
      # alias symbo into current package
      *{"$sym"}=*{"openwebmail::".$pkg."::".$sym};
   }
   return;
}
###################### END READLANG #########################

#################### READTEMPLATE ###########################
use vars qw(%_templatecache);
sub readtemplate {
   my $templatename=$_[0];
   my $lang=$prefs{'language'}||'en';
   if (!defined($_templatecache{"$lang/$templatename"})) {
      open (T, "$config{'ow_templatesdir'}/$lang/$templatename") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_templatesdir'}/$lang/$templatename! ($!)");
      local $/; undef $/; $_templatecache{"$lang/$templatename"}=<T>; # read whole file in once
      close (T);
   }
   return($_templatecache{"$lang/$templatename"});
}
#################### END READTEMPLATE ###########################

################# APPLYSTYLE ##############################
sub applystyle {
   my $template = shift;
   my $url;

   $template =~ s/\@\@\@NAME\@\@\@/$config{'name'}/g;
   $template =~ s/\@\@\@VERSION\@\@\@/$config{'version'}/g;
   $template =~ s/\@\@\@LOGO_URL\@\@\@/$config{'logo_url'}/g;
   $template =~ s/\@\@\@LOGO_LINK\@\@\@/$config{'logo_link'}/g;
   $template =~ s/\@\@\@PAGE_FOOTER\@\@\@/$config{'page_footer'}/g;
   $template =~ s/\@\@\@SESSIONID\@\@\@/$thissession/g;

   if ( -d "$config{'ow_htmldir'}/help/$prefs{'language'}" ) {
      $url="$config{'ow_htmlurl'}/help/$prefs{'language'}/index.html";
   } else {
      $url="$config{'ow_htmlurl'}/help/en/index.html";
   }
   $template =~ s/\@\@\@HELP_URL\@\@\@/$url/g;
   $template =~ s/\@\@\@HELP_TEXT\@\@\@/$lang_text{'help'}/g;

   $url=$config{'start_url'};
   if (cookie("openwebmail-ssl")) {	# backto SSL
      $url="https://$ENV{'HTTP_HOST'}$url" if ($url!~s!^https?://!https://!i);
   }
   # STARTURL in templates are all GET, so we can safely add cgi param after the url
   $url .= qq|?logindomain=$default_logindomain| if ($default_logindomain);
   $template =~ s/\@\@\@STARTURL\@\@\@/$url/g;

   $url="$config{'ow_cgiurl'}/openwebmail-prefs.pl";
   $template =~ s/\@\@\@PREFSURL\@\@\@/$url/g;
   $url="$config{'ow_cgiurl'}/openwebmail-abook.pl";
   $template =~ s/\@\@\@ABOOKURL\@\@\@/$url/g;
   $url="$config{'ow_cgiurl'}/openwebmail-viewatt.pl";
   $template =~ s/\@\@\@VIEWATTURL\@\@\@/$url/g;
   $url="$config{'ow_htmlurl'}/images";
   $template =~ s/\@\@\@IMAGEDIR_URL\@\@\@/$url/g;

   $template =~ s/\@\@\@BACKGROUND\@\@\@/$style{'background'}/g;
   $template =~ s/\@\@\@TITLEBAR\@\@\@/$style{'titlebar'}/g;
   $template =~ s/\@\@\@TITLEBAR_TEXT\@\@\@/$style{'titlebar_text'}/g;
   $template =~ s/\@\@\@MENUBAR\@\@\@/$style{'menubar'}/g;
   $template =~ s/\@\@\@WINDOW_DARK\@\@\@/$style{'window_dark'}/g;
   $template =~ s/\@\@\@WINDOW_LIGHT\@\@\@/$style{'window_light'}/g;
   $template =~ s/\@\@\@ATTACHMENT_DARK\@\@\@/$style{'attachment_dark'}/g;
   $template =~ s/\@\@\@ATTACHMENT_LIGHT\@\@\@/$style{'attachment_light'}/g;
   $template =~ s/\@\@\@COLUMNHEADER\@\@\@/$style{'columnheader'}/g;
   $template =~ s/\@\@\@TABLEROW_LIGHT\@\@\@/$style{'tablerow_light'}/g;
   $template =~ s/\@\@\@TABLEROW_DARK\@\@\@/$style{'tablerow_dark'}/g;
   $template =~ s/\@\@\@FONTFACE\@\@\@/$style{'fontface'}/g;
   $template =~ s/\@\@\@CSS\@\@\@/$style{'css'}/g;

   return $template;
}
################ END APPLYSTYLE ###########################

################ READ/WRITE POP3BOOK ##############
sub readpop3book {
   my ($pop3book, $r_accounts) = @_;
   my $i=0;

   %{$r_accounts}=();

   if ( -f "$pop3book" ) {
      filelock($pop3book, LOCK_SH) or return -1;
      open (POP3BOOK,"$pop3book") or return -1;
      while (<POP3BOOK>) {
      	 chomp($_);
         my ($pop3host,$pop3port, $pop3user,$pop3passwd, $pop3del, $enable)=split(/\@\@\@/, $_);
         $pop3passwd=decode_base64($pop3passwd);
         $pop3passwd=$pop3passwd^substr($pop3host,5,length($pop3passwd));
         ${$r_accounts}{"$pop3host:$pop3port\@\@\@$pop3user"} = "$pop3host\@\@\@$pop3port\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable";
         $i++;
      }
      close (POP3BOOK);
      filelock($pop3book, LOCK_UN);
   }
   return($i);
}

sub writepop3book {
   my ($pop3book, $r_accounts) = @_;

   ($pop3book =~ /^(.+)$/) && ($pop3book = $1); # untaint ...
   if (! -f "$pop3book" ) {
      open (POP3BOOK,">$pop3book") or return -1;
      close(POP3BOOK);
   }

   filelock($pop3book, LOCK_EX) or return -1;
   open (POP3BOOK,">$pop3book") or return -1;
   foreach (values %{$r_accounts}) {
     chomp($_);
     my ($pop3host,$pop3port, $pop3user,$pop3passwd, $pop3del,$enable)=split(/\@\@\@/, $_);
     # not secure, but better than plaintext
     $pop3passwd=$pop3passwd ^ substr($pop3host,5,length($pop3passwd));
     $pop3passwd=encode_base64($pop3passwd, '');
     print POP3BOOK "$pop3host\@\@\@$pop3port\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable\n";
   }
   close (POP3BOOK);
   filelock($pop3book, LOCK_UN);

   return 0;
}
################ END GET/WRITEBACK POP3BOOK ##############

#################### READ/WRITE CALBOOK #####################
# read the user calendar, put records into 2 hash,
# %items: index -> item fields
# %indexes: date -> indexes belong to this date
# ps: $indexshift is used to shift index so records in multiple calendar
#     won't collide on index
sub readcalbook {
   my ($calbook, $r_items, $r_indexes, $indexshift)=@_;
   my $item_count=0;

   return 0 if (! -f $calbook);

   open(CALBOOK, "$calbook") or return -1;

   while (<CALBOOK>) {
      next if (/^#/);
      chomp;
      my @a=split(/\@{3}/, $_);
      my $index=$a[0]+$indexshift;

      ${$r_items}{$index}={ idate        => $a[1],
                            starthourmin => $a[2],
                            endhourmin   => $a[3],
                            string       => $a[4],
                            link         => $a[5],
                            email        => $a[6],
                            eventcolor   => $a[7]||'none' };

      my $idate=$a[1]; $idate= '*' if ($idate=~/[^\d]/); # use '*' for regex date
      if ( !defined(${$r_indexes}{$idate}) ) {
         ${$r_indexes}{$idate}=[$index];
      } else {
         push(@{${$r_indexes}{$idate}}, $index);
      }
      $item_count++;
   }

   close(CALBOOK);

   return($item_count);
}

sub writecalbook {
   my ($calbook, $r_items)=@_;
   my @indexlist=sort { ${$r_items}{$a}{'idate'}<=>${$r_items}{$b}{'idate'} }
                       (keys %{$r_items});

   ($calbook =~ /^(.+)$/) && ($calbook = $1);	# untaint ...
   if (! -f "$calbook" ) {
      open (CALBOOK,">$calbook") or return -1;
      close(CALBOOK);
   }

   filelock($calbook, LOCK_EX) or return -1;
   open (CALBOOK, ">$calbook") or return -1;
   my $newindex=1;
   foreach (@indexlist) {
      print CALBOOK join('@@@', $newindex, ${$r_items}{$_}{'idate'},
                       ${$r_items}{$_}{'starthourmin'}, ${$r_items}{$_}{'endhourmin'},
                       ${$r_items}{$_}{'string'},
                       ${$r_items}{$_}{'link'},
                       ${$r_items}{$_}{'email'},
                       ${$r_items}{$_}{'eventcolor'})."\n";
      $newindex++;
   }
   close(CALBOOK);
   filelock($calbook, LOCK_UN);

   return($newindex);
}
#################### END READ/WRITE CALBOOK #####################

######################### GREGORIAN_EASTER ############################
# ($month, $day) = gregorian_easter($year);
# This subroutine returns the month and day of Easter in the given year,
# in the Gregorian calendar, which is what most of the world uses.
# Adapted from Rich Bowen's Date::Easter module ver 1.14
sub gregorian_easter {
    my $year = $_[0];
    my ( $G, $C, $H, $I, $J, $L, $month, $day, );
    $G = $year % 19;
    $C = int( $year / 100 );
    $H = ( $C - int( $C / 4 ) - int( ( 8 * $C ) / 25 ) + 19 * $G + 15 ) % 30;
    $I = $H - int( $H / 28 ) *
      ( 1 - int( $H / 28 ) * int( 29 / ( $H + 1 ) ) * int( ( 21 - $G ) / 11 ) );
    $J     = ( $year + int( $year / 4 ) + $I + 2 - $C + int( $C / 4 ) ) % 7;
    $L     = $I - $J;
    $month = 3 + int( ( $L + 40 ) / 44 );
    $day   = $L + 28 - ( 31 * int( $month / 4 ) );
    return ( $month, $day );
}
####################### END GREGORIAN_EASTER ##########################

########################### EASTER_MATCH ##############################
# Allow use of expression 'easter +- offset' for month and day field in $idate
# Example: Mardi Gras is ".*,easter,easter-47,.*"
# Written by James Dugal, jpd@louisiana.edu, Sept. 2002
sub easter_match {
    my ($year,$month,$day, $easter_month,$easter_day, $idate) = @_;
    return (0) unless ($idate =~ /easter/i);     # an easter record?
    my @fields = split(/,/,$idate);
    return (0) unless ($year =~ /$fields[0]/);  # year matches?

    $fields[1] =~ s/easter/$easter_month/i;
    $fields[2] =~ s/easter/$easter_day/i;
    if ($fields[1] =~ /^([\d+-]+)$/) {  #untaint
	$fields[1] = eval($1);	# allow simple arithmetic: easter-7  1+easter
    } else {
	return (0);  # bad syntax, only 0-9 + -  chars allowed
    }
    if ($fields[2] =~ /^([\d+-]+)$/) {  #untaint
	$fields[2] = eval($1);	# allow simple arithmetic: easter-7  1+easter
    } else {
	return (0);  # bad syntax, only 0-9 + -  chars allowed
    }
    # days_in_month ought to be pre-computed just once per $year, externally!
    my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
    if ( ($year%4)==0 && ( ($year%100)!=0 || ($year%400)==0 ) ) {
       $days_in_month[2]++;
    }
    if ($fields[1] > 0) { # same year, so proceed
	while($fields[2] > $days_in_month[$fields[1]]) {
	    $fields[2] -= $days_in_month[$fields[1]];
	    $fields[1]++;
	}
	while($fields[2] < 1) {
	    $fields[1] -= 1;
	    $fields[2] += $days_in_month[$fields[1]];
	}
	return (1) if ($month == $fields[1] && $day == $fields[2]);
    }
    return (0);
}
######################### END EASTER_MATCH ############################

############## VERIFYSESSION ########################
sub verifysession {
   my $now=time();
   my $modifyage=$now-(stat("$config{'ow_sessionsdir'}/$thissession"))[9];
   if ( $modifyage > $prefs{'sessiontimeout'}*60) {
      my $delfile="$config{'ow_sessionsdir'}/$thissession";
      ($delfile =~ /^(.+)$/) && ($delfile = $1);  # untaint ...
      unlink ($delfile) if ( -e "$delfile");

      my $html = applystyle(readtemplate("sessiontimeout.template"));
      httpprint([], [htmlheader(), $html, htmlfooter(1)]);

      writelog("session error - session $thissession timeout access attempt");
      writehistory("session error - session $thissession timeout access attempt");

      openwebmail_exit(0);
   }

   my $clientip=get_clientip();
   my $clientcookie=cookie("$user-sessionid");

   my ($cookie, $ip, $userinfo)=sessioninfo($thissession);
   if ( $config{'session_checkcookie'} &&
        $clientcookie ne $cookie ) {
      writelog("session error - request doesn't have proper cookie, access denied!");
      writehistory("session error - request doesn't have proper cookie, access denied !");
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'sess_cookieerr'}");
   }
   if ( $config{'session_checksameip'} &&
        $clientip ne $ip) {
      writelog("session error - request doesn't come from the same ip, access denied!");
      writehistory("session error - request doesn't com from the same ip, access denied !");
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'sess_iperr'}");
   }

   # no_update is used by auto-refresh/timeoutwarning
   my $session_noupdate=param('session_noupdate');
   if (!$session_noupdate) {
      # update the session timestamp with now-1,
      # the -1 is for nfs, utime is actually the nfs rpc setattr()
      # since nfs server current time will be used if setattr() is issued with nfs client's current time.
      utime ($now-1, $now-1, "$config{'ow_sessionsdir'}/$thissession") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}/$thissession! ($!)");
   }
   return 1;
}

sub sessioninfo {
   my $sessionid=$_[0];
   my ($cookie, $ip, $userinfo);

   openwebmailerror(__FILE__, __LINE__, "Session ID $sessionid $lang_err{'doesnt_exist'}") unless
      (-e "$config{'ow_sessionsdir'}/$sessionid");

   if ( !open(F, "$config{'ow_sessionsdir'}/$sessionid") ) {
      writelog("session error - couldn't open $config{'ow_sessionsdir'}/$sessionid ($@)");
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}/$sessionid");
   }
   $cookie= <F>; chomp $cookie;
   $ip= <F>; chomp $ip;
   $userinfo = <F>; chomp $userinfo;
   close (F);

   return($cookie, $ip, $userinfo);
}
############# END VERIFYSESSION #####################

############### GET_SPOOLFILE_FOLDERDB ################
sub get_folderfile_headerdb {
   my ($username, $foldername)=@_;
   my ($folderfile, $headerdb);

   if ($foldername eq 'INBOX') {
      if ($config{'use_homedirspools'}) {
         $folderfile = "$homedir/$config{'homedirspoolname'}";
      } elsif ($config{'use_hashedmailspools'}) {
         $username =~ /^(.)(.)/;
         my $firstchar = $1;
         my $secondchar = $2;
         $folderfile = "$config{'mailspooldir'}/$firstchar/$secondchar/$username";
      } else {
         $folderfile = "$config{'mailspooldir'}/$username";
      }
      $headerdb="$folderdir/.$username";

   } elsif ($foldername eq 'DELETE') {
      $folderfile = $headerdb ='';

   } else {
      $folderfile = "$folderdir/$foldername";
      $headerdb=$folderfile;
      ($headerdb =~ /^(.+)\/(.*)$/) && ($headerdb = "$1/.$2");
   }

   ($folderfile =~ /^(.+)$/) && ($folderfile = $1); # untaint ...
   ($headerdb =~ /^(.+)$/) && ($headerdb = $1);

   return($folderfile, $headerdb);
}
############### GET_SPOOLFILE_FOLDERDB ################

################## GETFOLDERS ####################
# return list of valid folders and calc the total folder usage(0..100%)
# NOTE: this routine will delete unused .*.(db|dir|pag),
#       the valid pattern needs to be changed f new db required for some data
sub getfolders {
   my ($r_folders, $r_usage)=@_;
   my @delfiles=();
   my @userfolders;
   my $totalsize = 0;
   my $filename;

   my @fdirs=($folderdir);		# start with root folderdir
   while (my $fdir=pop(@fdirs)) {
      opendir (FOLDERDIR, "$fdir") or
    	 openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $fdir! ($!)");

      while (defined($filename = readdir(FOLDERDIR))) {
         ($filename =~ /^(.+)$/) && ($filename = $1);   # untaint data from readdir
         next if ( $filename eq "." || $filename eq ".." );
         if (-d "$fdir/$filename" && $filename!~/^\./) { # recursive into non dot dir
            push(@fdirs,"$fdir/$filename");
            next;
         }

         # find internal file that are stale
         if ( $filename=~/^\.(.*)\.(?:db|dir|pag|lock|cache)$/) {
            if (-f "$folderdir/$1" || $1 eq $user) {
               next;	# skip files used by spool or folder
            }
            if ($filename=~/^\.(?:uidl\..*|filter\.book)\.(?:db|dir|pag)$/ ||
                $filename=~/^\.(?:search|webdisk)\.cache$/ ) {
               next;	# skip db used by system
            }
            # .*(db|dir|pag|lock|cache) will be DELETED
            # if not matched in above patterns
            push (@delfiles, "$folderdir/$filename");
            next;
         }

         # summary file size
         $totalsize += ( -s "$folderdir/$filename" ) || 0;

         # skip openwebmail internal files (conf, dbm, lock, search caches...)
         next if ( $filename=~/^\./ || $filename =~ /\.lock$/);

         # find all user folders
         if ( $filename ne 'saved-messages' &&
              $filename ne 'sent-mail' &&
              $filename ne 'saved-drafts' &&
              $filename ne 'mail-trash' ) {
            push(@userfolders, substr("$fdir/$filename",length($folderdir)+1));
         }
      }

      closedir (FOLDERDIR) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir! ($!)");
   }
   unlink(@delfiles) if ($#delfiles>=0);

   @{$r_folders}=();
   push (@{$r_folders},
         'INBOX', 'saved-messages', 'sent-mail', 'saved-drafts', 'mail-trash',
         sort(@userfolders));

   # add INBOX size to totalsize
   my ($spoolfile,$headerdb)=get_folderfile_headerdb($user, 'INBOX');
   if ( -f $spoolfile ) {
      $totalsize += ( -s "$spoolfile" ) || 0;
   } else {
      # create spool file with user uid, gid if it doesn't exist
      ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1); # untaint ...
      open (F, ">>$spoolfile"); close(F);
      chown ($uuid, (split(/\s+/,$ugid))[0], $spoolfile);
   }

   ${$r_usage}=$totalsize/1024;	# unit=k
   return;
}
################ END GETFOLDERS ##################

#################### GETMESSAGE ###########################
sub getmessage {
   my ($messageid, $mode) = @_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=do { local *FH };
   my $r_messageblock;
   my %message = ();

   filelock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderfile!");
   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
   }
   open($folderhandle, "$folderfile");
   $r_messageblock=get_message_block($messageid, $headerdb, $folderhandle);
   close($folderhandle);
   filelock($folderfile, LOCK_UN);

   if (${$r_messageblock} eq "") {	# msgid not found
      writelog("db warning - msg $messageid in $folderfile index missing");
      writehistory("db warning - msg $messageid in $folderfile index missing");
      return \%message;

   } elsif (${$r_messageblock}!~/^From / ) {	# db index inconsistance
      writelog("db warning - msg $messageid in $folderfile index inconsistence");
      writehistory("db warning - msg $messageid in $folderfile index inconsistence");

      my %HDB;
      open_dbm(\%HDB, $headerdb, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $headerdb$config{'dbm_ext'}");
      $HDB{'METAINFO'}="ERR";
      close_dbm(\%HDB, $headerdb);

      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderfile!");

      # forced reindex since metainfo = ERR
      if (update_headerdb($headerdb, $folderfile)<0) {
         filelock($folderfile, LOCK_UN);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
      }

      open($folderhandle, "$folderfile");
      $r_messageblock=get_message_block($messageid, $headerdb, $folderhandle);
      close($folderhandle);

      filelock($folderfile, LOCK_UN);

      return \%message if (${$r_messageblock} eq "" );
   }

   my ($currentheader, $currentbody, $r_currentattachments,
       $currentreturnpath, $currentfrom, $currentdate, $currentsubject,
       $currentid, $currenttype, $currentto, $currentcc, $currentbcc,
       $currentreplyto, $currentencoding, $currentstatus, $currentreceived,
       $currentpriority, $currentinreplyto, $currentreferences);

   # $r_attachment is a reference to attachment array!
   if ($mode eq "all") {
      ($currentheader, $currentbody, $r_currentattachments)
		=parse_rfc822block($r_messageblock, "0", "all");
   } else {
      ($currentheader, $currentbody, $r_currentattachments)
		=parse_rfc822block($r_messageblock, "0", "");
   }
   return \%message if ( $currentheader eq "" );

   $currentfrom = $currentdate = $currentsubject = $currenttype =
   $currentto = $currentcc = $currentreplyto = $currentencoding = 'N/A';
   $currentreturnpath = $currentstatus = $currentpriority =
   $currentinreplyto = $currentreferences = '';

   my $lastline = 'NONE';
   my @smtprelays=();
   foreach (split(/\n/, $currentheader)) {
      if (/^\s/) {
         s/^\s+/ /;
         if    ($lastline eq 'RETURNPATH') { $currentreturnpath .= $_ }
         elsif ($lastline eq 'FROM') { $currentfrom .= $_ }
         elsif ($lastline eq 'REPLYTO') { $currentreplyto .= $_ }
         elsif ($lastline eq 'DATE') { $currentdate .= $_ }
         elsif ($lastline eq 'SUBJ') { $currentsubject .= $_ }
         elsif ($lastline eq 'MESSID') { s/^\s+//; $currentid .= $_ }
         elsif ($lastline eq 'TYPE') { $currenttype .= $_ }
         elsif ($lastline eq 'ENCODING') { $currentencoding .= $_ }
         elsif ($lastline eq 'TO')   { $currentto .= $_ }
         elsif ($lastline eq 'CC')   { $currentcc .= $_ }
         elsif ($lastline eq 'BCC')   { $currentbcc .= $_ }
         elsif ($lastline eq 'INREPLYTO') { $currentinreplyto .= $_ }
         elsif ($lastline eq 'REFERENCES') { $currentreferences .= $_ }
         elsif ($lastline eq 'RECEIVED') { $currentreceived .= $_ }
      } elsif (/^return-path:\s*(.*)$/ig) {
         $currentreturnpath = $1;
         $lastline = 'RETURNPATH';
      } elsif (/^from:\s*(.*)$/ig) {
         $currentfrom = $1;
         $lastline = 'FROM';
      } elsif (/^reply-to:\s*(.*)$/ig) {
         $currentreplyto = $1;
         $lastline = 'REPLYTO';
      } elsif (/^to:\s*(.*)$/ig) {
         $currentto = $1;
         $lastline = 'TO';
      } elsif (/^cc:\s*(.*)$/ig) {
         $currentcc = $1;
         $lastline = 'CC';
      } elsif (/^bcc:\s*(.*)$/ig) {
         $currentbcc = $1;
         $lastline = 'BCC';
      } elsif (/^date:\s*(.*)$/ig) {
         $currentdate = $1;
         $lastline = 'DATE';
      } elsif (/^subject:\s*(.*)$/ig) {
         $currentsubject = $1;
         $lastline = 'SUBJ';
      } elsif (/^message-id:\s*(.*)$/ig) {
         $currentid = $1;
         $lastline = 'MESSID';
      } elsif (/^content-type:\s*(.*)$/ig) {
         $currenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.*)$/ig) {
         $currentencoding = $1;
         $lastline = 'ENCODING';
      } elsif (/^status:\s*(.*)$/ig) {
         $currentstatus .= $1;
         $currentstatus =~ s/\s//g;
         $lastline = 'NONE';
      } elsif (/^x-status:\s*(.*)$/ig) {
         $currentstatus .= $1;
         $currentstatus =~ s/\s//g;
         $lastline = 'NONE';
      } elsif (/^references:\s*(.*)$/ig) {
         $currentreferences = $1;
         $lastline = 'REFERENCES';
      } elsif (/^in-reply-to:\s*(.*)$/ig) {
         $currentinreplyto = $1;
         $lastline = 'INREPLYTO';
      } elsif (/^priority:\s*(.*)$/ig) {
         $currentpriority = $1;
         $currentstatus .= "I";
         $lastline = 'NONE';
      } elsif (/^Received:\s*(.*)$/ig) {
         my $tmp=$1;
         if ($currentreceived=~ /.*\sby\s([^\s]+)\s.*/) {
            unshift(@smtprelays, $1) if ($smtprelays[0] ne $1);
         }
         if ($currentreceived=~ /.*\sfrom\s([^\s]+)\s.*/) {
            unshift(@smtprelays, $1);
         } elsif ($currentreceived=~ /.*\(from\s([^\s]+)\).*/is) {
            unshift(@smtprelays, $1);
         }
         $currentreceived=$tmp;
         $lastline = 'RECEIVED';
      } else {
         $lastline = 'NONE';
      }
   }
   # capture last Received: block
   if ($currentreceived=~ /.*\sby\s([^\s]+)\s.*/) {
      unshift(@smtprelays, $1) if ($smtprelays[0] ne $1);
   }
   if ($currentreceived=~ /.*\sfrom\s([^\s]+)\s.*/) {
      unshift(@smtprelays, $1);
   } elsif ($currentreceived=~ /.*\(from\s([^\s]+)\).*/is) {
      unshift(@smtprelays, $1);
   }
   # count first fromhost as relay only if there are just 2 host on relaylist
   # since it means sender pc uses smtp to talk to our mail server directly
   shift(@smtprelays) if ($#smtprelays>1);

search_smtprelay:
   foreach my $relay (@smtprelays) {
      next if ($relay !~ /[\w\d\-_]+\.[\w\d\-_]+/);
      foreach (@{$config{'domainnames'}}) {
         next search_smtprelay if ($relay =~ $_);
      }
      $relay=~s/[\[\]]//g;	# remove [] around ip addr in mailheader
				# since $message{smtprelay} may be put into filterrule
                        	# and we don't want [] be treat as regular expression
      $message{smtprelay} = $relay;
      last;
   }

   $message{header} = $currentheader;
   $message{body} = $currentbody;
   $message{attachment} = $r_currentattachments;

   $message{from}    = decode_mimewords($currentfrom);
   $message{replyto} = decode_mimewords($currentreplyto) if ($currentreplyto ne "N/A");
   $message{to}      = decode_mimewords($currentto) if ($currentto ne "N/A");
   $message{cc}      = decode_mimewords($currentcc) if ($currentcc ne "N/A");
   $message{bcc}     = decode_mimewords($currentbcc) if ($currentbcc ne "N/A");
   $message{subject} = decode_mimewords($currentsubject);

   $message{returnpath} = $currentreturnpath;
   $message{date} = $currentdate;
   $message{status} = $currentstatus;
   $message{messageid} = $currentid;
   $message{contenttype} = $currenttype;
   $message{encoding} = $currentencoding;
   $message{inreplyto} = $currentinreplyto;
   $message{references} = $currentreferences;
   $message{priority} = $currentpriority;

   $message{charset} = "";
   if ($message{contenttype}=~/charset="?([^\s"';]*)"?\s?/i) {
      $message{charset}=$1;
   } else {
      foreach my $i (0 .. $#{$message{attachment}}) {
         next if (!defined(%{$message{attachment}[$i]}));
         if (${$message{attachment}[$i]}{charset} ne "") {
            $message{charset}=${$message{attachment}[$i]}{charset};
            last;
         }
      }
   }

   # Determine message's number and previous and next message IDs.
   my ($totalsize, $newmessages, $r_messageids)=getinfomessageids();
   foreach my $i (0..$#{$r_messageids}) {
      if (${$r_messageids}[$i] eq $messageid) {
         $message{"prev"} = ${$r_messageids}[$i-1] if ($i > 0);
         $message{"next"} = ${$r_messageids}[$i+1] if ($i < $#{$r_messageids});
         $message{"number"} = $i+1;
         $message{"new"} = $newmessages;
         $message{"total"}=$#{$r_messageids}+1;
         last;
      }
   }
   return \%message;
}
#################### END GETMESSAGE #######################

################### GETINFOMESSAGEIDS ###################
use vars qw($_index_complete);
sub getinfomessageids {
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);

   # do new indexing in background if folder > 10 M && empty db
   if ( (stat("$headerdb$config{'dbm_ext'}"))[7]==0 &&
        (stat($folderfile))[7] >= 10485760 ) {
      local $|=1; # flush all output
      local $SIG{CHLD} = sub { wait; $_index_complete=1 if ($?==0) };	# handle zombie
      local $_index_complete=0;
      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);
         filelock($folderfile, LOCK_SH|LOCK_NB) or openwebmail_exit(1);
         update_headerdb($headerdb, $folderfile);
         filelock($folderfile, LOCK_UN);
         openwebmail_exit(0);
      }

      for (my $i=0; $i<120; $i++) {	# wait index to complete for 120 seconds
         sleep 1;
         last if ($_index_complete);
      }

      if ($_index_complete==0) {
         openwebmailerror(__FILE__, __LINE__, "$folderfile $lang_err{'under_indexing'}");
      }
   } else {	# do indexing directly if small folder
      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderfile!");
      if (update_headerdb($headerdb, $folderfile)<0) {
         filelock($folderfile, LOCK_UN);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
      }
      filelock($folderfile, LOCK_UN);
   }

   # Since recipients are displayed instead of sender in folderview of
   # SENT/DRAFT folder, the $sort must be changed from 'sender' to
   # 'recipient' in this case
   if ( $folder=~ m#sent-mail#i ||
        $folder=~ m#saved-drafts#i ||
        $folder=~ m#\Q$lang_folders{'sent-mail'}\E#i ||
        $folder=~ m#\Q$lang_folders{'saved-drafts'}\E#i ) {
      $sort='recipient' if ($sort eq 'sender');
   }

   if ( $keyword ne '' ) {
      my $folderhandle=do { local *FH };
      my ($totalsize, $new, $r_haskeyword, $r_messageids, $r_messagedepths);
      my @messageids=();
      my @messagedepths=();

      ($totalsize, $new, $r_messageids, $r_messagedepths)=get_info_messageids_sorted($headerdb, $sort, "$headerdb.cache", $prefs{'hideinternal'});

      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderfile!");
      open($folderhandle, $folderfile);
      ($totalsize, $new, $r_haskeyword)=search_info_messages_for_keyword(
         $keyword, $prefs{'charset'}, $searchtype, $headerdb, $folderhandle,
         "$folderdir/.search.cache", $prefs{'hideinternal'}, $prefs{'regexmatch'});
      close($folderhandle);
      filelock($folderfile, LOCK_UN);

      for (my $i=0; $i<@{$r_messageids}; $i++) {
	my $id = ${$r_messageids}[$i];
	if ( ${$r_haskeyword}{$id} == 1 ) {
	  push (@messageids, $id);
	  push (@messagedepths, ${$r_messagedepths}[$i]);
        }
      }
      return($totalsize, $new, \@messageids, \@messagedepths);

   } else { # return: $totalsize, $new, $r_messageids for whole folder
      return(get_info_messageids_sorted($headerdb, $sort, "$headerdb.cache", $prefs{'hideinternal'}))
   }
}
################# END GETINFOMESSAGEIDS #################

################# FILTERMESSAGE ###########################
sub filtermessage {
   my ($filtered, $r_filtered);
   if ($config{'enable_smartfilters'}) {
      ($filtered, $r_filtered)=mailfilter($user, 'INBOX', $folderdir, \@validfolders, $prefs{'regexmatch'},
					$prefs{'filter_repeatlimit'}, $prefs{'filter_badformatfrom'},
					$prefs{'filter_fakedsmtp'}, $prefs{'filter_fakedfrom'},
					$prefs{'filter_fakedexecontenttype'});
   } else {
      ($filtered, $r_filtered)=mailfilter($user, 'INBOX', $folderdir, \@validfolders, $prefs{'regexmatch'},
					0, 0, 0, 0, 0);
   }

   if ($filtered > 0) {
      my $dststr;
      foreach my $destination (sort keys %{$r_filtered}) {
         next if ($destination eq '_ALL' || $destination eq 'INBOX');
         $dststr .= ", " if ($dststr ne "");
         $dststr .= $destination;
         $dststr .= "(${$r_filtered}{$destination})" if (${$r_filtered}{$destination} ne $filtered);
      }
      writelog("filter message - filter $filtered msgs from INBOX to $dststr");
      writehistory("filter message - filter $filtered msgs from INBOX to $dststr");
   } elsif ($filtered == -1 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} .filter.check!");
   } elsif ($filtered == -2 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} .filter.book!");
   } elsif ($filtered == -3 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} .filter.book$config{'dbm_ext'}!");
   } elsif ($filtered == -4 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} INBOX!");
   } elsif ($filtered == -5 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} INBOX!");
   } elsif ($filtered == -6 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} INBOX folder index!");
   } elsif ($filtered == -7 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} mail-trash!");
   } elsif ($filtered == -8 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} .filter.check!");
   } elsif ($filtered == -9 ) {
      openwebmailerror(__FILE__, __LINE__, "mailfilter I/O error!");
   }
   return($filtered, $r_filtered);
}
################# END FILTERMESSAGE #######################

################# CUTFOLDERMAILS ############################
sub cutfoldermails {
   my ($sizetocut, @folders)=@_;
   my ($total_foldersize, $user_foldersize)=(0,0);
   my (@userfolders, %folderfile, %headerdb);
   my $inbox_foldersize=0;

   foreach my $f (@folders) {
      ($folderfile{$f},$headerdb{$f})=get_folderfile_headerdb($user, $f);
      my $foldersize=(-s "$folderfile{$f}") + (-s "$headerdb{$f}$config{'dbm_ext'}");
      if ($f ne 'INBOX' &&
          $f ne 'saved-messages' &&
          $f ne 'sent-mail' &&
          $f ne 'saved-drafts' &&
          $f ne 'mail-trash') {
         push (@userfolders, $f);
         $user_foldersize+=$foldersize;
      }
      if ($f eq 'INBOX') {
         if ($config{'use_homedirspools'}) {
            $total_foldersize+=$foldersize;
            $inbox_foldersize=$foldersize;
         }
      } else {
         $total_foldersize+=$foldersize;
      }
   }

   # empty folders
   foreach my $f ('mail-trash', 'saved-drafts') {	
      next if ( (-s "$folderfile{$f}")==0 );

      my $sizereduced = (-s "$folderfile{$f}") + (-s "$headerdb{$f}$config{'dbm_ext'}");
      my $ret=emptyfolder($folderfile{$f}, $headerdb{$f});
      if ($ret<0) {
         writelog("emptyfolder error - folder $f ret=$ret");
         writehistory("emptyfolder error - folder $f ret=$ret");
         next;
      }
      $sizereduced -= ((-s "$folderfile{$f}") + (-s "$headerdb{$f}$config{'dbm_ext'}"));

      $total_foldersize-=$sizereduced;
      $sizetocut-=$sizereduced;
      return ($_[0]-$sizetocut) if ($sizetocut<=0);	# return cutsize
   }

   # cut folders
   my @folders_tocut=('sent-mail', 'saved-messages');
   # put @userfolders to cutlist if it occupies more than 33%
   if ($user_foldersize > $total_foldersize*0.33) {
      push (@folders_tocut, sort(@userfolders));
   } else {
      $total_foldersize -= $user_foldersize;
   }
   # put INBOX to cutlist if it occupies more than 33%
   if ($config{'use_homedirspools'}) {
      if ($inbox_foldersize > $total_foldersize*0.33) {
         push (@folders_tocut, 'INBOX');
      } else {
         $total_foldersize -= $inbox_foldersize;
      }
   }

   for (my $i=0; $i<3; $i++) {
      return ($_[0]-$sizetocut) if ($total_foldersize==0);	# return cutsize

      my $cutpercent=$sizetocut/$total_foldersize;
      $cutpercent=0.1 if ($cutpercent<0.1);

      foreach my $f (@folders_tocut) {
         next if ( (-s "$folderfile{$f}")==0 );

         my $sizereduced = (-s "$folderfile{$f}") + (-s "$headerdb{$f}$config{'dbm_ext'}");
         my $ret;
         if ($f eq 'sent-mail') {
            $ret=cutfolder($folderfile{$f}, $headerdb{$f}, $cutpercent+0.1);
         } else {
            $ret=cutfolder($folderfile{$f}, $headerdb{$f}, $cutpercent);
         }
         if ($ret<0) {
            writelog("cutfoldermails error - folder $f ret=$ret");
            writehistory("cutfoldermails error - folder $f ret=$ret");
            next;
         }
         $sizereduced -= ((-s "$folderfile{$f}") + (-s "$headerdb{$f}$config{'dbm_ext'}"));
         writelog("cutfoldermails - $f, $ret msg removed, reduced size $sizereduced");
         writehistory("cutfoldermails - $f, $ret msg removed, reduced size $sizereduced");

         $total_foldersize-=$sizereduced;
         $sizetocut-=$sizereduced;
         return ($_[0]-$sizetocut) if ($sizetocut<=0);	# return cutsize
      }
   }

   writelog("cutfoldermails error - still $sizetocut bytes to cut");
   writehistory("cutfoldermails error - still $sizetocut bytes to cut");
   return ($_[0]-$sizetocut);	# return cutsize
}

sub emptyfolder {
   my ($folderfile, $headerdb) = @_;
   my $ret;

   filelock($folderfile, LOCK_SH|LOCK_NB) or return -1;
   if (!open (F, ">$folderfile")) {
      filelock($folderfile, LOCK_UN);
      return -2;
   }
   close (F);
   $ret=update_headerdb($headerdb, $folderfile);
   filelock($folderfile, LOCK_UN);
   return -3 if ($ret<0);
   return 0;
}

sub cutfolder {				# reduce folder size by $cutpercent
   my ($folderfile, $headerdb, $cutpercent) = @_;
   my (@delids, $cutsize, %HDB);

   filelock($folderfile, LOCK_SH|LOCK_NB) or return -1;

   return -2 if (update_headerdb($headerdb, $folderfile)<0);

   my ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_date($headerdb, 0);

   open_dbm(\%HDB, $headerdb, LOCK_SH) or return -3;
   foreach my $id  (reverse @{$r_messageids}) {
      push(@delids, $id);
      $cutsize += (split(/@@@/, $HDB{$id}))[$_SIZE];
      last if ($cutsize > $totalsize*$cutpercent);
   }
   close_dbm(\%HDB, $headerdb);
   my $counted=operate_message_with_ids("delete", \@delids, $folderfile, $headerdb);

   filelock($folderfile, LOCK_UN);

   return($counted);
}
################# END CUTFOLDERMAILS ########################

################# CUTDIRFILES ########################
sub cutdirfiles {
   my ($sizetocut, $dir)=@_;
   my (%ftype, %fdate, %fsize);

   my $spoolfile=(get_folderfile_headerdb($user, 'INBOX'))[0];
   return 0 if (fullpath2vpath($dir, $spoolfile) ne "");	# skip spoolfile
   return 0 if (fullpath2vpath($dir, $folderdir) ne "");	# skip folderdir

   return -1 if (!opendir(D, $dir));
   while (defined(my $fname=readdir(D))) {
      next if ($fname eq "."|| $fname eq "..");

      my ($st_mode, $st_mtime, $st_blocks)= (lstat("$dir/$fname"))[2,9,12];
      if ( ($st_mode&0170000)==0040000 ) {	# directory
         $ftype{$fname}='d';
         $fdate{$fname}=$st_mtime;
         $fsize{$fname}=$st_blocks*512;
      } elsif ( ($st_mode&0170000)==0100000 ||	# regular file
                ($st_mode&0170000)==0120000 ) {	# symlink
         $ftype{$fname}='f';
         $fdate{$fname}=$st_mtime;
         $fsize{$fname}=$st_blocks*512;
      } else {	# unix specific filetype: fifo, socket, block dev, char dev..
         next;
      }
   }
   closedir(D);

   my $now=time();
   my @sortedlist= sort { $fdate{$a}<=>$fdate{$b} } keys(%ftype);
   foreach my $fname (@sortedlist) {
      if ($ftype{$fname} eq 'f') {
         if (unlink("$dir/$fname")) {
            $sizetocut-=$fsize{$fname};
            writelog("cutdirfiles - file $dir/$fname has been removed");
            writehistory("cutdirfiles - file $dir/$fname has been removed");
            return ($_[0]-$sizetocut) if ($sizetocut<=0);	# return cutsize
         }
      } else {	# dir
         my $sizecut=cutdirfiles($sizetocut, "$dir/$fname");
         if ($sizecut>0) {
            $sizetocut-=$sizecut;
            if (rmdir("$dir/$fname")) {
               writelog("cutdir - dir $dir/$fname has been removed");
               writehistory("cutdir - dir $dir/$fname has been removed");
            } else {
               utime($now, $fdate{$fname}, "$dir/$fname");	# set modify time back
            }
            return ($_[0]-$sizetocut) if ($sizetocut<=0);	# return cutsize
         }
      }
   }
   return ($_[0]-$sizetocut);
}
################# END CUTDIRFILES ########################

##################### WRITELOG ############################
sub writelog {
   my $logaction=$_[0];
   return if ($config{'logfile'} eq 'no' || -l "$config{'logfile'}");

   my $timestamp = localtime();
   my $loggedip = get_clientip();
   my $loggeduser = $loginuser || 'UNKNOWNUSER';
   $loggeduser .= "\@$logindomain" if ($config{'auth_withdomain'});
   $loggeduser .= "($user)" if ($user && $loginuser ne $user);

   if (open(LOGFILE,">>$config{'logfile'}")) {
      print LOGFILE "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
      close (LOGFILE);
   } else {
      # show log error only if CGI mode
      if (defined($ENV{'GATEWAY_INTERFACE'})) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'logfile'}! ($!)");
      }
   }
   return;
}
#################### END WRITELOG #########################

################## WRITEHISTORY ####################
sub writehistory {
   my $logaction=$_[0];

   my $timestamp = localtime();
   my $loggedip = get_clientip();
   my $loggeduser = $loginuser || 'UNKNOWNUSER';
   $loggeduser .= "\@$logindomain" if ($config{'auth_withdomain'});
   $loggeduser .= "($user)" if ($user && $loginuser ne $user);

   if ( -f "$folderdir/.history.log" ) {
      my ($start, $end, $buff);

      filelock("$folderdir/.history.log", LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.history.log");
      open (HISTORYLOG,"+< $folderdir/.history.log") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.history.log ($!)");
      seek(HISTORYLOG, 0, 2);	# seek to tail
      $end=tell(HISTORYLOG);

      if ( $end > ($config{'maxbooksize'} * 1024)) {
         seek(HISTORYLOG, $end-int($config{'maxbooksize'} * 1024 * 0.8), 0);
         $_=<HISTORYLOG>;
         $start=tell(HISTORYLOG);

         read(HISTORYLOG, $buff, $end-$start);

         seek(HISTORYLOG, 0, 0);
         print HISTORYLOG $buff;

         $end=tell(HISTORYLOG);
         truncate(HISTORYLOG, $end);
      }

      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
      close(HISTORYLOG);
      filelock("$folderdir/.history.log", LOCK_UN);

   } else {
      open(HISTORYLOG, ">$folderdir/.history.log") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.history.log ($!)");
      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
      close(HISTORYLOG);
   }

   return 0;
}
################ END WRITEHISTORY ##################

##################### PRINTHEADER/PRINTFOOTER #########################
sub httpprint {
   my ($r_headers, $r_htmls)=@_;
   if ( cookie("openwebmail-httpcompress") &&
        $ENV{'HTTP_ACCEPT_ENCODING'}=~/\bgzip\b/ &&
        has_zlib() ) {
      my $zhtml=Compress::Zlib::memGzip(join('',@{$r_htmls}));
      if ($zhtml) {
         print httpheader(@{$r_headers},
                          '-Content-Encoding'=>'gzip',
                          '-Vary'=>'Accept-Encoding',
                          '-Content-Length'=>length($zhtml)), $zhtml;
         return;
      }
   }
   my $len; foreach (@{$r_htmls}) { $len+=length($_); }
   print httpheader(@{$r_headers}, '-Content-Length'=>$len), @{$r_htmls};
   return;
}

sub httpheader {
   my %headers=@_;
   $headers{'-charset'}=$prefs{'charset'} if ($CGI::VERSION>=2.57);
   if (!defined($headers{'-Cache-Control'}) &&
       !defined($headers{'-Expires'}) ) {
      $headers{'-Pragma'}='no-cache';
      $headers{'-Cache-Control'}='no-cache,no-store';
   }
   return (header(%headers));
}

sub htmlheader {
   my $html = applystyle(readtemplate("header.template"));

   my $mode;
   $mode.='+' if ($persistence_count>0);
   $mode.='z' if (cookie("openwebmail-httpcompress") &&
                  $ENV{'HTTP_ACCEPT_ENCODING'}=~/\bgzip\b/ &&
                  has_zlib());
   $mode="($mode)" if ($mode);

   $html =~ s/\@\@\@MODE\@\@\@/$mode/g;
   $html =~ s/\@\@\@ICO_LINK\@\@\@/$config{'ico_url'}/g;
   $html =~ s/\@\@\@BG_URL\@\@\@/$prefs{'bgurl'}/g;
   $html =~ s/\@\@\@CHARSET\@\@\@/$prefs{'charset'}/g;

   my $info;
   if ($user) {
      $info=qq|$prefs{'email'} -|;
      if ($config{'quota_module'} ne "none") {
         $info.=qq| |.lenstr($quotausage*1024,1);
         $info.=qq| (|.(int($quotausage*1000/$quotalimit)/10).qq|%)| if ($quotalimit);
         $info.=qq| -|;
      }
   }
   $info .= " ".dateserial2str(gmtime2dateserial(), $prefs{'timeoffset'}, $prefs{'dateformat'})." -";
   $html =~ s/\@\@\@USERINFO\@\@\@/$info/g;
   return ($html);
}

sub htmlplugin {
   my $file=$_[0];
   my $html='';
   if ($file && $file ne 'none' && open(F, $file) ) {
      local $/; undef $/; $html=<F>;	# no seperator, read whole file in once
      close(F);
      $html="<center>\n$html</center>\n" if ($html);
   }
   return ($html);
}

sub htmlfooter {
   my ($mode, $jscode)=@_;
   return qq|</body></html>\n| if ($mode==0);	# null footer

   my $html = '';
   if ($mode==2) {	# read in timeout check jscript
      my $ftime= (stat("$config{'ow_sessionsdir'}/$thissession"))[9];
      my $remainingseconds= 365*86400;		# default timeout = 1 year
      if ($thissession ne "" && $ftime) {	# this is a session & session file available
         $remainingseconds = $ftime+$prefs{'sessiontimeout'}*60 - time();
      }
      $html = readtemplate("timeoutchk.js");
      $html =~ s/\@\@\@REMAININGSECONDS\@\@\@/$remainingseconds/g;
      $html =~ s/\@\@\@JSCODE\@\@\@/$jscode/g;
   }
   if ($mode>=1) {	# print footer
      $html.=readtemplate("footer.template");
      $html =~ s/\@\@\@USEREMAIL\@\@\@/$prefs{'email'}/g;
   }

   return (applystyle($html));
}
################# END PRINTHEADER/PRINTFOOTER #########################

##################### OPENWEBMAILERROR ##########################
sub openwebmailerror {
   my ($file, $linenum, $msg)=@_;
   my $mailgid=getgrnam('mail');
   $file=~s!.*/!!;
   $msg="Unknow error $msg at $file:$linenum" if (length($msg)<5);
   if ($config{'error_with_debuginfo'}) {
      $msg.=qq|<br><font class="medtext">( $file:$linenum, ruid=$<, euid=$>, egid=$), mailgid=$mailgid )</font>\n|;
   }

   if (defined($ENV{'GATEWAY_INTERFACE'})) {	# in CGI mode
      # load prefs if possible, or use default value
      my $background = $style{"background"}||"#FFFFFF"; $background =~ s/"//g;
      my $bgurl=$prefs{'bgurl'}||"/openwebmail/images/backgrounds/Globe.gif";
      my $css = $style{"css"}||
                qq|<!--\n|.
                qq|body {\n|.
                qq|background-image: url($bgurl);\n|.
                qq|background-repeat: repeat;\n|.
                qq|font-family: Arial, Helvetica, sans-serif; font-size: 10pt\n|.
                qq|}\n|.
                qq|A:link    { text-decoration: none; color: blue}\n|.
                qq|A:visited { text-decoration: none; color: blue}\n|.
                qq|A:hover   { text-decoration: none; color: red}\n|.
                qq|.medtext { font-size: 9pt;}\n|.
                qq|-->\n|;
      my $fontface = $style{"fontface"}||"Arial, Helvetica";
      my $titlebar = $style{"titlebar"}||"#002266";
      my $titlebar_text = $style{"titlebar_text"}||"#FFFFFF";
      my $window_light = $style{"window_light"}||"#EEEEEE";

      my $html = start_html(-title=>$config{'name'},
                            -bgcolor=>$background,
                            -background=>$bgurl);
      $html.=qq|<style type="text/css">\n|.
             $css.
             qq|</style>\n|.
             qq|<br><br><br><br><br><br><br>\n|.
             qq|<table border="0" align="center" width="40%" cellpadding="1" cellspacing="1">|.
             qq|<tr><td bgcolor=$titlebar nowrap>\n|.
             qq|<font color=$titlebar_text face=$fontface size="3"><b>$config{'name'} ERROR</b></font>\n|.
             qq|</td></tr>|.
             qq|<tr><td align="center" bgcolor=$window_light>\n|.
             qq|<br>$msg<br><br>\n|.
             qq|</td></tr>|.
             qq|</table>\n|.
             qq|<p align="center"><br>$config{'page_footer'}<br></p>\n|.
             qq|</body></html>|;
      # for page footer
      $html =~ s!\@\@\@HELP_URL\@\@\@!$config{'ow_htmlurl'}/help/en/index.html!g;
      $html =~ s!\@\@\@HELP_TEXT\@\@\@!Help!g;

      httpprint([], [$html]);

   } else { # command mode
      print "$msg\n($file:$linenum, ruid=$<, euid=$>, egid=$), mailgid=$mailgid)\n";
   }
   openwebmail_exit(1);
}
################### END OPENWEBMAILERROR #######################

###################### AUTOCLOSEWINDOW ##########################
sub autoclosewindow {
   my ($title, $msg, $time, $jscode)=@_;
   $time=8 if ($time<3);

   if (defined($ENV{'GATEWAY_INTERFACE'})) {	# in CGI mode
      my ($html, $temphtml);
      $html = applystyle(readtemplate("autoclose.template"));

      $html =~ s/\@\@\@MSGTITLE\@\@\@/$title/g;
      $html =~ s/\@\@\@MSG\@\@\@/$msg/g;
      $html =~ s/\@\@\@TIME\@\@\@/$time/g;
      $html =~ s/\@\@\@JSCODE\@\@\@/$jscode/g;

      $temphtml = button(-name=>"okbutton",
                         -value=>$lang_text{'ok'},
                         -onclick=>'autoclose();',
                         -override=>'1');
      $html =~ s/\@\@\@OKBUTTON\@\@\@/$temphtml/g;
      httpprint([], [htmlheader(), $html, htmlfooter(2)]);

   } else {	# command mode
      print "$title - $msg\n";
   }
   openwebmail_exit(0);
}
###################### END AUTOCLOSEWINDOW #######################

######################### ICONLINK ###############################
sub iconlink {
   my ($icon, $label, $url)=@_;
   my $link;

   if ($prefs{'iconset'} =~ /^Text\./) {
      if (defined($icontext{$icon})) {
         $link = "<b>$icontext{$icon}</b>";
      } else {
         $link = $icon;
         $link=~s/\.(?:gif|jpg|png)$//i;
         $link= "<b>[$link]</b>"
      }
   } else {
      if ($label ne "") {
         $link = qq|<IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/$icon" border="0" align="absmiddle" alt="$label">|;
      } else {
         $link = qq|<IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/$icon" border="0" align="absmiddle">|;
      }
   }
   if ($url ne "") {
      if ($label ne "") {
         $link = qq|<a $url title="$label">| . $link . qq|</a>|;
      } else {
         $link = qq|<a $url>| . $link . qq|</a>|;
      }
   }

   return($link);
}
######################### END ICONLINK ###########################

##################### escapeURL, unescapeURL #################
# escape & unescape routine are not available in CGI.pm 3.0
# so we borrow the 2 routines from 2.xx version of CGI.pm
sub unescapeURL {
    my $todecode = shift;
    return undef if (!defined($todecode));
    $todecode =~ tr/+/ /;       # pluses become spaces
    $todecode =~ s/%([0-9a-fA-F]{2})/pack("c",hex($1))/ge;
    return $todecode;
}

sub escapeURL {
    my $toencode = shift;
    return undef if (!defined($toencode));
    $toencode=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
    return $toencode;
}
##################### END escapeURL, unescapeURL #################

##################### SET_EUID_EGID_UMASK #################
# this routine save euid root to ruid in case system doesn't support saved-euid
# so we can give up euid root temporarily and get it back later.
# Saved-euid means the euid will be saved to a variable saved-euid(prepared by OS)
# before it is changed, thus the process can switch back to previous euid if required
sub set_euid_egids {
   my ($uid, @gids)=@_;
   # note! egid must be set before set euid to normal user,
   #       since a normal user can not set egid to others
   # trick: 2nd parm will be ignore, so we repeat parm 1 twice
   $) = join(" ", $gids[0], @gids);	
   if ($> != $uid) {
      $<=$> if (!$config{'savedsuid_support'} && $>==0);
      $> = $uid
   }
   return;
}
################### END SET_EUID_EGID_UMASK ###############

########################## METAINFO #########################
# return a string composed by the modify time & size of a file
sub metainfo {
   return '' if (!-e $_[0]);
   # dev, ino, mode, nlink, uid, gid, rdev, size, atime, mtime, ctime, blksize, blocks
   my @a=stat($_[0]);
   return("mtime=$a[9] size=$a[7]");
}
######################## END METAINFO #######################

#################### GET_CLIENTIP #############################
sub get_clientip {
   my $clientip;
   if (defined($ENV{'HTTP_CLIENT_IP'})) {
      $clientip=$ENV{'HTTP_CLIENT_IP'};
   } elsif (defined($ENV{'HTTP_X_FORWARDED_FOR'}) && 
            $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^(?:10\.|172\.(?:1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.0\.)/ ) {
      $clientip=(split(/,/,$ENV{'HTTP_X_FORWARDED_FOR'}))[0];
   } else {
      $clientip=$ENV{'REMOTE_ADDR'}||"127.0.0.1";
   }
   return $clientip;
}
#################### END GET_CLIENTIP #########################

#################### TIMEOFFSET2SECONDS ########################
sub timeoffset2seconds {
   my $timeoffset=$_[0];
   my $seconds=0;
   if ($timeoffset=~/^[+\-]?(\d\d)(\d\d)$/) {
      $seconds=($1*60+$2)*60;
      $seconds*=-1 if ($timeoffset=~/^\-/);
   }
   return($seconds);
}

sub seconds2timeoffset {
   my $seconds=abs($_[0]);
   my $sign=($_[0]>=0)?"+":"-";
   return(sprintf( "%s%02d%02d", $sign, int($seconds/3600), int(($seconds%3600)/60) ));
}
################## END TIMEOFFSET2SECONDS ######################

########################## IS_DST ##########################
# Check if gmtime should be DST for timezone $timeoffset.
# Since we use only 2 rules to calc daylight saving time for all timezones,
# it is not very accurate but should be enough in most cases
sub is_dst {	
   my ($gmtime, $timeoffset)=@_;
   my $year=(gmtime($gmtime))[5];
   my $seconds=timeoffset2seconds($timeoffset);

   my ($gm, $lt, $dow);
   if ($seconds >= -9*3600 && $seconds <= 3*3600 ) {	# dst rule for us timezones
      $lt=safetimegm(0,0,2, 1,3,$year);	# localtime Apr/1 2:00
      $dow=(gmtime($lt))[6];		# weekday of localtime Apr/1 2:00:01
      $gm=$lt+(7-$dow)*86400-$seconds;	# gmtime of localtime Apr/1st sunday
      return 0 if ($gmtime<$gm);

      $lt=safetimegm(0,0,2, 30,9,$year);	# localtime Oct/30 2:00
      $dow=(gmtime($lt))[6];		# weekday of localtime Oct/30
      $gm=$lt-$dow*86400-$seconds;	# gmtime of localtime Oct/last Sunday
      return 0 if ($gmtime>$gm);

   } elsif ($seconds >= 0 && $seconds <= 6*3600 ) {	# dst rule for europe timezones
      $gm=safetimegm(0,0,1, 31,2,$year);     # gmtime Mar/31 1:00
      $dow=(gmtime($gm))[6];		# weekday of gmtime Mar/31
      $gm-=$dow*86400;			# gmtime Mar/last Sunday
      return 0 if ($gmtime<$gm);

      $gm=safetimegm(0,0,1, 30,9,$year);     # gmtime Oct/30 1:00
      $dow=(gmtime($gm))[6];		# weekday of gmtime Oct/30
      $gm-=$dow*86400;			# gmtime Oct/last Sunday
      return 0 if ($gmtime>$gm);

   } else {
      return 0;
   }
   return 1;
}
######################## END IS_DST ########################

#################### GETTIMEOFFSET #########################
# notice! th difference between localtime and gmtime includes the dst shift
# so we remove the dstshift before return timeoffset
# since whether dst shift should be used depends on the date to be converted
sub gettimeoffset {
   my $t=time();			# the UTC            sec from 1970/01/01
   my $l=timegm((localtime($t))[0..5]);	# the UTC+timeoffset sec from 1970/01/01
   my $offset=sprintf(seconds2timeoffset($l-$t));

   if (is_dst($t, $offset)) {	
      $offset=sprintf(seconds2timeoffset($l-$t-3600));
   }
   return $offset;
}
#################### END GETTIMEOFFSET #########################

########################## SAFE_TIMEGM ########################
# avoid unexpected error exception from timegm
sub safetimegm {
   my ($sec,$min,$hour, $d,$m,$y)=@_;
   my @t=gmtime();
   $sec= $t[0] if ($sec<0||$sec>59);
   $min= $t[1] if ($min<0||$min>59);
   $hour=$t[2] if ($hour<0||$hour>23);
   $d   =$t[3] if ($d<1||$d>31);
   $m   =$t[4] if ($m<0||$m>11);
   $y   =$t[5] if ($y<70||$y>139);

   if ($d>28) {
      my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
      my $year=1900+$y;
      $days_in_month[2]++ if ( $year%4==0 && ($year%100!=0||$year%400==0) );
      $d=$days_in_month[$m+1] if ($d>$days_in_month[$m+1]);
   }
   return timegm($sec,$min,$hour, $d,$m,$y);
}
######################## SAFE_TIMEGM ###########################

#################### GMTIME <-> DATESERIAL #########################
# dateserial is used as an equivalent internal format to gmtime
# the is_dst effect won't be not counted in dateserial until
# the dateserial is converted to datefield, delimeterfield or str
sub gmtime2dateserial {		
   # time() is used if $_[0] undefined
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=gmtime($_[0]||time());
   return(sprintf("%4d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec));
}

sub dateserial2gmtime {
   $_[0]=~/(\d\d\d\d)(\d\d)(\d\d)(\d\d)?(\d\d)?(\d\d)?/;
   my ($year, $mon, $mday, $hour, $min, $sec)=($1, $2, $3, $4, $5, $6);
   return safetimegm($sec,$min,$hour, $mday,$mon-1,$year-1900);
}
################## END GMTIME <-> DATESERIAL #########################

################## DELIMITER <-> DATESERIAL #######################
sub delimiter2dateserial {	# return dateserial of GMT
   my ($delimiter, $deliver_use_GMT)=@_;

   # extract date from the 'From ' line, it must be in this form
   # From Tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
   # From Tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
   # From Nssb@thumper.bellcore.com   Wed Mar 11 16:27:37 EST 1992
   return("") if ($delimiter !~ /(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+([A-Z]{3,4}\d?\s+)?(\d\d+)/);

   my ($wdaystr, $monstr, $mday, $hour, $min, $sec, $zone, $year)
					=($1, $2, $3, $4, $5, $6, $7, $8);
   if ($year<50) {	# 2 digit year
      $year+=2000;
   } elsif ($year<=1900) {
      $year+=1900;
   }
   my $mon=$months{$monstr};

   my $server_timeoffset=gettimeoffset();
   my $l2g=safetimegm($sec,$min,$hour, $mday,$mon-1,$year-1900);
   if (!$deliver_use_GMT) {
      # we don't trust the zone abbreviation in delimiter line because it is not unique.
      # see http://www.worldtimezone.com/wtz-names/timezonenames.html for detail
      # since delimiter is written by local deliver, so we use $server_timeoffset instead
      $l2g-=timeoffset2seconds($server_timeoffset);
   }
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($l2g,$server_timeoffset)) ) {
      $l2g-=3600; # minus 1 hour if is_dst at that gmtime
   }
   return(gmtime2dateserial($l2g));
}

sub dateserial2delimiter {
   my ($dateserial, $timeoffset)=@_;

   my $g2l=dateserial2gmtime($dateserial);
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$timeoffset)) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime
   }
   $g2l+=timeoffset2seconds($timeoffset) if ($timeoffset);
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=gmtime($g2l);

   # From Tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
   return(sprintf("%3s %3s %2d %02d:%02d:%02d %4d",
              $wdaystr[$wday], $monthstr[$mon],$mday, $hour,$min,$sec, $year+1900));
}
################ END DELIMITER <-> DATESERIAL #######################

#################### DATEFIELD <-> DATESERIAL #####################
# notice: both the datetime and the timezone str in date field 
#         include the dst shift
sub datefield2dateserial {	# return dateserial of GMT
   my $datefield=$_[0];
   my ($sec,$min,$hour, $mday,$mon,$year, $timeoffset,$timezone, $ampm);

   $datefield=~s/GMT//;
   foreach my $s (split(/[\s,]+/, $datefield)) {
      if ($s=~/^\d\d?$/) {
         if ($s<=31 && $mday eq "") {
            $mday=$s;
         } else {
            $year=$s+1900;
            $year+=100 if ($year<1970);
         }
      } elsif ($s=~/^[A-Z][a-z][a-z]/ ) {
         for my $i (0..11) {
            if ($s=~/^$monthstr[$i]/i) {
               $mon=$i+1; last;
            }
         }
      } elsif ($s=~/^\d\d\d\d$/) {
         $year=$s;
      } elsif ($s=~/^(\d+):(\d+):?(\d+)?$/) {
         $hour=$1; $min=$2; $sec=$3;
      } elsif ($s=~/^\(?([A-Z]{3,4}\d?)\)?$/) {
         $timezone=$1;
      } elsif ($s=~/^([\+\-]\d\d:?\d\d)$/) {
         $timeoffset=$1;
         $timeoffset=~s/://;
      } elsif ($s=~/^pm$/i) {
         $ampm='pm';
      }
   }
   $hour+=12 if ($hour<12 && $ampm eq 'pm');
   $timeoffset=$tzoffset{$timezone} if ($timeoffset eq "");

   my $l2g=safetimegm($sec,$min,$hour, $mday,$mon-1,$year-1900);
   $l2g-=timeoffset2seconds($timeoffset);
   return(gmtime2dateserial($l2g));
}

sub dateserial2datefield {
   my ($dateserial, $timeoffset)=@_;

   my $g2l=dateserial2gmtime($dateserial);
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$timeoffset)) ) {
      $timeoffset=seconds2timeoffset(timeoffset2seconds($timeoffset)+3600);
   }
   $g2l+=timeoffset2seconds($timeoffset) if ($timeoffset);
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=gmtime($g2l);

   #Date: Wed, 9 Sep 1998 19:30:17 +0800 (CST)
   return(sprintf("%3s, %d %3s %4d %02d:%02d:%02d %s",
              $wdaystr[$wday], $mday,$monthstr[$mon],$year+1900, $hour,$min,$sec, $timeoffset));
}
################## END DATEFIELD <-> DATESERIAL #####################

##################### DATESERIAL2STR #######################
sub dateserial2str {
   my ($dateserial, $timeoffset, $format)=@_;

   my $g2l=dateserial2gmtime($dateserial);
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$timeoffset)) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime
   }
   $g2l+=timeoffset2seconds($timeoffset) if ($timeoffset);
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=gmtime($g2l);
   $year+=1900; $mon++;

   my $str;
   if ( $format eq "mm/dd/yyyy") {
      $str=sprintf("%02d/%02d/%04d", $mon, $mday, $year);
   } elsif ( $format eq "dd/mm/yyyy") {
      $str=sprintf("%02d/%02d/%04d", $mday, $mon, $year);
   } elsif ( $format eq "yyyy/mm/dd") {
      $str=sprintf("%04d/%02d/%02d", $year, $mon, $mday);

   } elsif ( $format eq "mm-dd-yyyy") {
      $str=sprintf("%02d-%02d-%04d", $mon, $mday, $year);
   } elsif ( $format eq "dd-mm-yyyy") {
      $str=sprintf("%02d-%02d-%04d", $mday, $mon, $year);
   } elsif ( $format eq "yyyy-mm-dd") {
      $str=sprintf("%04d-%02d-%02d", $year, $mon, $mday);

   } elsif ( $format eq "mm.dd.yyyy") {
      $str=sprintf("%02d.%02d.%04d", $mon, $mday, $year);
   } elsif ( $format eq "dd.mm.yyyy") {
      $str=sprintf("%02d.%02d.%04d", $mday, $mon, $year);
   } elsif ( $format eq "yyyy.mm.dd") {
      $str=sprintf("%04d.%02d.%02d", $year, $mon, $mday);

   } else {
      $str=sprintf("%02d/%02d/%04d", $mon, $mday, $year);
   }

   if ( $prefs{'hourformat'} eq "12") {
      my ($h, $ampm)=hour24to12($hour);
      $str.=sprintf(" %02d:%02d:%02d $ampm", $h, $min, $sec);
   } else {
      $str.=sprintf(" %02d:%02d:%02d", $hour, $min, $sec);
   }
   return($str);
}
################### END DATESERIAL2STR #####################

####################### HOUR24TO12 ###########################
sub hour24to12 {
   my $hour=$_[0];
   my $ampm="am";

   $hour =~ s/^0(.+)/$1/;
   if ($hour==24||$hour==0) {
      $hour = 12;
   } elsif ($hour > 12) {
      $hour = $hour - 12;
      $ampm = "pm";
   } elsif ($hour == 12) {
      $ampm = "pm";
   }
   return($hour, $ampm);
}
##################### END HOUR24TO12 ###########################

#################### EMAIL2NAMEADDR ######################
sub email2nameaddr {	# name, addr are guarentee to not null
   my ($name, $address)=_email2nameaddr($_[0]);
   if ($name eq "") {
      $name=$address;
      $name=~s/\@.*$//;
      $name=$address if (length($name)<=2);
   }
   return($name, $address);
}

sub _email2nameaddr {	# name may be null
   my $email=$_[0];
   my ($name, $address);

   if ($email =~ m/^\s*"?<?(.+?)>?"?\s*<(.*)>$/) {
      $name = $1; $address = $2;
   } elsif ($email =~ m/<?(.*?@.*?)>?\s+\((.+?)\)/) {
      $name = $2; $address = $1;
   } elsif ($email =~ m/<(.+)>/) {
      $name = ""; $address = $1;
   } elsif ($email =~ m/(.+)/) {
      $name = "" ; $address = $1;
   }
   $name=~s/^\s+//; $name=~s/\s+$//;
   $address=~s/^\s+//; $address=~s/\s+$//;
   return($name, $address);
}
################ END EMAIL2NAMEADDR  #####################

###################### STR2LIST #######################
sub str2list {
   my ($str, $keepnull)=@_;
   my (@list, @tmp, $delimiter);
   my $pairmode=0;
   my ($prevchar, $postchar);

   if ($str=~/,/) {
      @tmp=split(/,/, $str);
      $delimiter=',';
   } elsif ($str=~/;/) {
      @tmp=split(/;/, $str);
      $delimiter=';';
   } else {
      return($str);
   }

   foreach my $token (@tmp) {
      if ($token=~/^\s*$/) {
         last if (!$keepnull);
      }
      if ($pairmode) {
         push(@list, pop(@list).$delimiter.$token);
         if ($token=~/\Q$postchar\E/ && $token!~/\Q$prevchar\E.*\Q$postchar\E/) {
            $pairmode=0
         }
      } else {
         push(@list, $token);
         if ($token=~/^.*?(['"\(])/) {
            $prevchar=$1;
            if ($prevchar eq '(' ) {
               $postchar=')';
            } else {
               $postchar=$prevchar;
            }
            if ($token!~/\Q$prevchar\E.*\Q$postchar\E/) {
               $pairmode=1;
            }
         }
      }
   }

   foreach (@list) {
      s/^\s+//g;
      s/\s+$//g;
   }
   return(@list);
}
#################### END STR2LIST #####################

####################### LENSTR ########################
sub lenstr {
   my ($len, $bytestr)=@_;

   if ($len >= 1048576){
      $len = int($len/1048576*10+0.5)/10 . $lang_sizes{'mb'};
   } elsif ($len >= 2048) {
      $len =  int(($len/1024)+0.5) . $lang_sizes{'kb'};
   } else {
      $len = $len .$lang_sizes{'byte'} if ($bytestr);
   }
   return ($len);
}
####################### END LENSTR ########################

######################## ZH_DOSPATH2FNAME ####################
# big5: hi 81-FE, lo 40-7E A1-FE, range a440-C67E C940-F9D5 F9D6-F9FE
# gbk : hi 81-FE, lo 40-7E 80-FE, range hi*lo
sub zh_dospath2fname {
   my ($dospath, $newdelim)=@_;
   my $buff='';
   while ( 1 ) {
      # this line can't be put inside while or will go wrong in perl 5.8.0
      if ($dospath=~m!([\x81-\xFE][\x40-\x7E\x80-\xFE]|.)!g) {
         if ($1 eq '\\') {
            if ($newdelim) {
               $buff.=$newdelim;
            } else {
               $buff='';
            }
         } else {
            $buff.=$1;
         }
      } else {
         last;
      }
   }
   return $buff;
}
##################### END ZH_DOSPATH2FNAME ###################

##################### SAFEFOLDERNAME ########################
sub safefoldername {
   my $foldername=$_[0];

   # dangerous char for path interpretation
   $foldername =~ s!\.\.+!!g;
   # $foldername =~ s!/!!g;	# comment out because of sub folder

   # dangerous char for perl file open
   $foldername =~ s!^\s*[\|\<\>]+!!g;
   $foldername =~ s![\|\<\>]+\s*$!!g;

   # all dangerous char within foldername
   if ($config{'enable_strictfoldername'}) {
      $foldername =~ s![\s\`\|\<\>/;&]+!_!g;
   }
   return $foldername;
}
##################### END SAFEFOLDERNAME ########################

##################### SAFEDOMAINNAME ########################
sub safedomainname {
   my $domainname=$_[0];
   $domainname=~s!\.\.+!!g;
   $domainname=~s![^A-Za-z\d\_\-\.]!!g;	# reserve safe char only
   return($domainname);
}
##################### END SAFEDOMAINNAME ########################

######################## SAFEDLNAME ############################
sub safedlname {
   my $dlname=$_[0];
   $dlname=~s|/$||; $dlname=~s|^.*/||;	# unix path
   if (length($dlname)>45) {   # IE6 goes crazy if fname longer than 45, tricky!
      $dlname=~/^(.*)(\.[^\.]*)$/;
      $dlname=substr($1, 0, 45-length($2)).$2;
   }
   $dlname=~s|_*\._*|\.|g;
   $dlname=~s|__+|_|g;
   return($dlname);
}
######################## END SAFEDLNAME ########################

########################## EXT <-> CONTENTTYPE ##################
sub ext2contenttype {
   my $ext=lc($_[0]); $ext=~s/^.*\.//;	# remove part before .

   return("text/plain")			if ($ext =~ /^(?:asc|te?xt|cc?|h|cpp|asm|pas|f77|lst|sh|pl)$/);
   return("text/html")			if ($ext =~ /^html?$/);
   return("text/xml")			if ($ext =~ /^(?:xml|xsl)$/);
   return("text/richtext")		if ($ext eq "rtx");
   return("text/sgml")			if ($ext =~ /^sgml?$/);
   return("text/vnd.wap.wml")		if ($ext eq "wml");
   return("text/vnd.wap.wmlscript")	if ($ext eq "wmls");
   return("text/$1")			if ($ext =~ /^(?:css|rtf)$/);

   return("model/vrml")			if ($ext =~ /^(?:wrl|vrml)$/);

   return("image/jpeg")			if ($ext =~ /^(?:jpg|jpe|jpeg)$/);
   return("image/$1")			if ($ext =~ /^(bmp|gif|ief|png|psp)$/);
   return("image/tiff")			if ($ext =~ /^tiff?$/);
   return("image/x-xbitmap")		if ($ext eq "xbm");
   return("image/x-xpixmap")		if ($ext eq "xpm");
   return("image/x-cmu-raster")		if ($ext eq "ras");
   return("image/x-portable-anymap")	if ($ext eq "pnm");
   return("image/x-portable-bitmap")	if ($ext eq "pbm");
   return("image/x-portable-grayma")	if ($ext eq "pgm");
   return("image/x-portable-pixmap")	if ($ext eq "ppm");
   return("image/x-rgb")		if ($ext eq "rgb");

   return("video/mpeg")			if ($ext =~ /^(?:mpeg?|mpg|mp2)$/);
   return("video/x-msvideo")		if ($ext =~ /^(?:avi|dl|fli)$/);
   return("video/quicktime")		if ($ext =~ /^(?:mov|qt)$/);

   return("audio/x-wav")		if ($ext eq "wav");
   return("audio/mpeg")			if ($ext =~ /^(?:mp[23]|mpga)$/);
   return("audio/midi")			if ($ext =~ /^(?:midi?|kar)$/);
   return("audio/x-realaudio")		if ($ext eq "ra");
   return("audio/basic")		if ($ext =~ /^(?:au|snd)$/);
   return("audio/x-mpegurl")		if ($ext eq "m3u");
   return("audio/x-aiff")		if ($ext =~ /^aif[fc]?$/);
   return("audio/x-pn-realaudio")	if ($ext =~ /^ra?m$/);

   return("application/msword") 	if ($ext eq "doc");
   return("application/x-mspowerpoint") if ($ext eq "ppt");
   return("application/x-msexcel") 	if ($ext eq "xls");
   return("application/x-msvisio")	if ($ext eq "visio");

   return("application/postscript")	if ($ext =~ /^(?:ps|eps|ai)$/);
   return("application/mac-binhex40")	if ($ext eq "hqx");
   return("application/xhtml+xml")	if ($ext =~ /^(?:xhtml|xht)$/);
   return("application/x-javascript")	if ($ext eq "js");
   return("application/x-vcard")	if ($ext eq "vcf");
   return("application/x-shockwave-flash") if ($ext eq "swf");
   return("application/x-texinfo")	if ($ext =~ /^(?:texinfo|texi)$/);
   return("application/x-troff")	if ($ext =~ /^(?:tr|roff)$/);
   return("application/x-troff-$1")     if ($ext =~ /^(man|me|ms)$/);
   return("application/x-$1")		if ($ext =~ /^(dvi|latex|shar|tar|tcl|tex)$/);
   return("application/ms-tnef")        if ($ext =~ /^tnef$/);
   return("application/$1")		if ($ext =~ /^(pdf|zip)$/);

   return("application/octet-stream");
}

sub contenttype2ext {
   my $contenttype=$_[0];
   my ($class, $ext, $dummy)=split(/[\/\s;,]+/, $contenttype);

   return("txt")  if ($contenttype eq "N/A");
   return("mp3")  if ($contenttype=~m!audio/mpeg!i);
   return("au")   if ($contenttype=~m!audio/x\-sun!i);
   return("ra")   if ($contenttype=~m!audio/x\-realaudio!i);

   $ext=~s/^x-//i;
   return(lc($ext))  if length($ext) <=4;

   return("txt")  if ($class =~ /text/i);
   return("msg")  if ($class =~ /message/i);

   return("doc")  if ($ext =~ /msword/i);
   return("ppt")  if ($ext =~ /powerpoint/i);
   return("xls")  if ($ext =~ /excel/i);
   return("vsd")  if ($ext =~ /visio/i);
   return("vcf")  if ($ext =~ /vcard/i);
   return("tar")  if ($ext =~ /tar/i);
   return("zip")  if ($ext =~ /zip/i);
   return("avi")  if ($ext =~ /msvideo/i);
   return("mov")  if ($ext =~ /quicktime/i);
   return("swf")  if ($ext =~ /shockwave\-flash/i);
   return("hqx")  if ($ext =~ /mac\-binhex40/i);
   return("ps")   if ($ext =~ /postscript/i);
   return("js")   if ($ext =~ /javascript/i);
   return("tnef") if ($ext =~ /ms\-tnef/i);
   return("bin");
}
########################## END EXT <-> CONTENTTYPE ########################

########################## ABSOLUTE_VPATH ########################
sub absolute_vpath {
   my ($base, $vpath)=@_;
   $vpath="$base/$vpath" if ($vpath!~m|^/|);
   return('/'.join('/', path2array($vpath)));
}
####################### END ABSOLUTE_VPATH ########################

########################## PATH2ARRAY #############################
sub path2array {
   my $path=$_[0];
   my @p=();
   foreach (split(/\//, $path)) {
      if ($_ eq "." || $_ eq "") {	# remove . and //
         next;
      } elsif ($_ eq "..") {		# remove ..
         pop(@p);
      } else {
         push(@p, $_);
      }
   }
   return(@p);
}
########################## END PATH2ARRAY #############################

######################### RESOLV_SYMLINK ##########################
use vars qw(%_symlink_map);
sub resolv_symlink {
   my ($i, $path, @p)=(0, '', path2array($_[0]));
   my ($path0, %mapped);
   while(defined($_=shift(@p)) && $i<20) {
      $path0=$path;
      $path.="/$_";
      if (-l $path) {
         $path=readlink($path);
         if ($path=~m|^/|) {
            unshift(@p, path2array($path)); $path='';
         } elsif ($path=~m|\.\.|) {
            unshift(@p, path2array("$path0/$path")); $path='';
         } else {
            unshift(@p, path2array($path)); $path=$path0;
         }
         $i++;
      }
   }
   if ($i>=20) {
      return(-1, $_[0]);
   } else {
      return(0, $path);
   }
}
######################## END RESOLV_SYMLINK ########################

########################## FULLPATH2VPATH ##############################
sub fullpath2vpath {
   my ($realpath, $rootpath)=@_;
   my @p=path2array($realpath);
   my @r=path2array($rootpath);
   foreach my $r (@r) {
      return if ($r ne shift(@p));
   }
   return('/'.join('/', @p));
}
######################### END FULLPATH2VPATH ##########################

########################## VERIFYVPATH ##############################
# check hidden, symboliclink, out symboliclink, unix specific files
sub verify_vpath {
   my ($rootpath, $vpath)=@_;
   my $filename=$vpath; $filename=~s|.*/||;
   if (!$config{'webdisk_lshidden'} && $filename=~/^\./) {
      return "$lang_err{'access_denied'} ($vpath is a hidden file)\n";
   }

   my ($retcode, $realpath)=resolv_symlink("$rootpath/$vpath");
   return "$lang_err{'access_denied'} (too deep symbolic link?)\n" if ($retcode<0);

   if (-l "$rootpath/$vpath") {
      if (!$config{'webdisk_lssymlink'}) {
         return "$lang_err{'access_denied'} ($vpath is a symbolic link)\n";
      }
      if (!$config{'webdisk_allow_symlinkout'}) {
         if ( fullpath2vpath($realpath, (resolv_symlink($rootpath))[1]) eq "") {
            return "$lang_err{'access_denied'} ($vpath is symbolic linked to dir/file outside webdisk)\n";
         }
      }
   }
   if ( fullpath2vpath($realpath, (resolv_symlink($config{'ow_sessionsdir'}))[1]) ne "") {
      writelog("webdisk error - attemp to hack sessions dir!");
      return "$lang_err{'access_denied'} ($vpath is sessions dir)\n";
   }
   if ( fullpath2vpath($realpath, (resolv_symlink($config{'logfile'}))[1]) ne "") {
      writelog("webdisk error - attemp to hack log file!");
      return "$lang_err{'access_denied'} ($vpath is log file)\n";
   }

   if (!$config{'webdisk_lsmailfolder'}) {
      my $spoolfile=(get_folderfile_headerdb($user, 'INBOX'))[0];
      if ( fullpath2vpath($realpath, (resolv_symlink($folderdir))[1]) ne "" ||
           fullpath2vpath($realpath, (resolv_symlink($spoolfile))[1]) ne "" ) {
         return "$lang_err{'access_denied'} ($vpath is a mailfolder file)\n";
      }
   }
   if (!$config{'webdisk_lsunixspec'} && (-e $realpath && !-d _ && !-f _)) {
      return "$lang_err{'access_denied'} ($vpath is a unix specific file)\n";
   }
   return;
}
########################## END VERIFYVPATH ##########################

######################## IS_ADM ##########################
sub is_vdomain_adm {
   my $user=$_[0];
   if (defined(@{$config{'vdomain_admlist'}})) {
      foreach my $adm (@{$config{'vdomain_admlist'}}) {
         return 1 if ($user eq $adm);
      }
   }
   return 0;
}
###################### END IS_ADM #######################

##################### VDOMAIN_USERSPOOL ##################
sub vdomain_userspool {
   my ($vuser, $vhomedir) = @_;
   my $dest;
   my $spool="$config{'vdomain_vmpop3_mailpath'}/$domain/$vuser";
   ($spool =~ /^(.+)$/) && ($spool = $1);		# untaint

   if ( $config{'vdomain_mailbox_command'} ne "none" ) {
      $dest = qq!| "$config{'vdomain_mailbox_command'}"!;
      $dest =~ s/<domain>/$domain/g;
      $dest =~ s/<user>/$vuser/g;
      $dest =~ s/<homedir>/$vhomedir/g;
      $dest =~ s/<spoolfile>/$spool/g;
   } else {
      $dest=$spool;
   }
   return $dest;
}
##################### END VUSER_SPOOL #####################

########################## HOSTNAME ##########################
sub hostname {
   my $hostname=`/bin/hostname`; chomp ($hostname);
   return($hostname) if ($hostname=~/\./);

   my $domain="unknow";
   open (R, "/etc/resolv.conf");
   while (<R>) {
      chop;
      if (/domain\s+\.?(.*)/i) {$domain=$1;last;}
   }
   close(R);
   return("$hostname.$domain");
}
########################## END HOSTNAME ##########################

########################## FILELOCK ############################
sub filelock {
   if ( $config{'use_dotlockfile'} ) {
      return openwebmail::filelock::dotfile_lock(@_);
   } else {
      return openwebmail::filelock::flock_lock(@_);
   }
}
########################## END FILELOCK ############################

################# IS_REGEX, IS_TAINTED ##########
sub is_regex {
   return eval { m!$_[0]!; 1; };
}

sub is_tainted {
   return ! eval { join('',@_), kill 0; 1; };
}
############### END IS_REGEX, IS_TAINTED ########

#################### IS_R2LMODE ####################
# used to siwtch direct of arrow for Right-to-Left language
# eg: arabic, hebrew
sub is_RTLmode {
   if ($_[0] eq "ar.CP1256" || $_[0] eq "ar.ISO8859-6" ||  # arabic
       $_[0] eq "he.CP1255" || $_[0] eq "he.ISO8859-8" ||  # hebrew
       $_[0] eq "ur" ) {				   # urdu
      return 1;
   }
   return 0;
}
################## END IS_R2LMODE ####################

#################### LOG_TIME (for profiling) ####################
sub log_time {
   my @msg=@_;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
   my ($today, $time);

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime;
   $today=sprintf("%4d%02d%02d", $year+1900, $mon+1, $mday);
   $time=sprintf("%02d%02d%02d",$hour,$min, $sec);

   open(Z, ">> /tmp/openwebmail.debug");

   # unbuffer mode
   select(Z); local $| = 1;
   select(STDOUT);

   print Z "$today $time ", join(" ",@msg), "\n";
   close(Z);
   chmod(0666, "/tmp/openwebmail.debug");
}
################## END LOG_TIME (for profiling) ##################

1;
