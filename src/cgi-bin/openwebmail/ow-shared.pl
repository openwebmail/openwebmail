#
# ow-shared.pl - routines shared by openwebmail*.pl
#

use strict;
use Fcntl qw(:DEFAULT :flock);

use vars qw(%languagenames %languagecharsets @openwebmailrcitem);
use vars qw(%months @monthstr @wdaystr %tzoffset %medfontsize);

# extern vars
# defined in caller openwebmail-xxx.pl
use vars qw($SCRIPT_DIR);
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);
use vars qw($sort $searchtype $keyword);
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err);	# defined in lang/xy
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET);	# defined in maildb.pl

# The language name for each language abbreviation
%languagenames = (
   'ar.CP1256'    => 'Arabic - Windows',
   'ar.ISO8859-6' => 'Arabic - ISO 8859-6',
   'bg'           => 'Bulgarian',
   'ca'           => 'Catalan',
   'cs'           => 'Czech',
   'da'           => 'Danish',
   'de'           => 'Deutsch',			# German
   'en'           => 'English',
   'el'           => 'Hellenic',			# Hellenic/Greek
   'es'           => 'Spanish',			# Espanol
   'fi'           => 'Finnish',
   'fr'           => 'French',
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
   'sv'           => 'Swedish',			# Svenska
   'th'           => 'Thai',
   'tr'           => 'Turkish',
   'uk'           => 'Ukrainian',
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
   'he.CP1255'    => 'windows-1255',	# charset only, lang/template not translated
   'he.ISO8859-8' => 'iso-8859-8',	# charset only, lang/template not translated
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
   'sv'           => 'iso-8859-1',
   'th'           => 'tis-620',
   'tr'           => 'iso-8859-9',
   'uk'           => 'koi8-u',
   'zh_CN.GB2312' => 'gb2312',
   'zh_TW.Big5'   => 'big5'
);

@openwebmailrcitem=qw(
   language charset timeoffset email replyto
   style iconset bgurl fontsize dateformat hourformat
   ctrlposition_folderview  msgsperpage sort 
   ctrlposition_msgread headers usefixedfont usesmileicon 
   disablejs disableembcgi showimgaslink sendreceipt 
   confirmmsgmovecopy defaultdestination 
   viewnextaftermsgmovecopy autopop3 moveoldmsgfrominbox
   editcolumns editrows sendbuttonposition
   reparagraphorigmsg replywithorigmsg backupsentmsg sendcharset
   filter_repeatlimit filter_fakedsmtp
   filter_fakedfrom filter_fakedexecontenttype
   abook_width abook_height abookbuttonposition
   abook_defualtfilter abook_defaultsearchtype abook_defaultkeyword
   calendar_monthviewnumitems calendar_weekstart
   calendar_starthour calendar_endhour calendar_showemptyhours
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
    CET  +0100  CST  -0600  EAST +1000  EDT  -0400  EED  +0300  EET  +0200
    EEST +0300  EST  -0500  FST  +0200  FWT  +0100  GMT  +0000  GST  +1000
    HDT  -0900  HST  -1000  IDLE +1200  IDLW -1200  IST  +0530  IT   +0330
    JST  +0900  JT   +0700  MDT  -0600  MED  +0200  MET  +0100  MEST +0200
    MEWT +0100  MST  -0700  MT   +0800  NDT  -0230  NFT  -0330  NT   -1100
    NST  +0630  NZ   +1100  NZST +1200  NZDT +1300  NZT  +1200  PDT  -0700
    PST  -0800  ROK  +0900  SAD  +1000  SAST +0900  SAT  +0900  SDT  +1000
    SST  +0200  SWT  +0100  USZ3 +0400  USZ4 +0500  USZ5 +0600  USZ6 +0700
    UT   +0000  UTC  +0000  UZ10 +1100  WAT  -0100  WET  +0000  WST  +0800
    YDT  -0800  YST  -0900  ZP4  +0400  ZP5  +0500  ZP6  +0600);

%medfontsize= (
   '9pt' => '9pt',
   '10pt'=> '9pt',
   '11pt'=> '10pt',
   '12pt'=> '11pt',
   '13pt'=> '12pt',
   '14pt'=> '13pt',
   '12px'=> '12px',
   '13px'=> '12px',
   '14px'=> '13px',
   '15px'=> '14px',
   '16px'=> '15px',
   '17px'=> '16px'
);

###################### OPENWEBMAIL_INIT ###################
# init routine to set globals, switch euid
sub openwebmail_init {
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf.default");
   readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");
   # setuid is required if mails is located in user's dir
   if ( $>!=0 && ($config{'use_homedirspools'}||$config{'use_homedirfolders'}) ) {
      print "Content-type: text/html\n\n'$0' must setuid to root"; exit 0;
   }
   if (! defined(param("sessionid")) ) {
      sleep $config{'loginerrordelay'};	# delayed response
      openwebmailerror("No user specified!");
   }

   $thissession = param("sessionid");
   $loginname = $thissession || '';
   $loginname =~ s/\-session\-0.*$//; # Grab loginname from sessionid

   my $siteconf;
   if ($loginname=~/\@(.+)$/) {
       my $domain=safedomainname($1);
       $siteconf="$config{'ow_sitesconfdir'}/$domain";
   } else {
       my $httphost=$ENV{'HTTP_HOST'};
       $httphost=~s/:\d+$//;	# remove port number
       $httphost=safedomainname($httphost);
       $siteconf="$config{'ow_sitesconfdir'}/$httphost";
   }
   readconf(\%config, \%config_raw, "$siteconf") if ( -f "$siteconf");

   if ($config{'smtpauth'}) {
      readconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/smtpauth.conf");
      if ($config{'smtpauth_username'} eq "" || $config{'smtpauth_password'} eq "") {
         openwebmailerror("Invalid username/password in $SCRIPT_DIR/etc/smtpauth.conf");
      }
   }

   require $config{'auth_module'} or
      openwebmailerror("Can't open authentication module $config{'auth_module'}");

   ($loginname, $domain, $user, $userrealname, $uuid, $ugid, $homedir)
	=get_domain_user_userinfo($loginname);
   if ($user eq "") {
      sleep $config{'loginerrordelay'};	# delayed response
      openwebmailerror("User $loginname doesn't exist!");
   }

   my $userconf="$config{'ow_usersconfdir'}/$user";
   $userconf .= "\@$domain" if ($config{'auth_withdomain'});
   readconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

   # override auto guessing domainanmes if loginame has domain
   if ($config_raw{'domainnames'} eq 'auto' && $loginname=~/\@(.+)$/) {
      $config{'domainnames'}=[ $1 ];
   }

   if ( !$config{'use_homedirfolders'} ) {
      $homedir = "$config{'ow_usersdir'}/$user";
      $homedir .= "\@$domain" if ($config{'auth_withdomain'});
   }
   $folderdir = "$homedir/$config{'homedirfolderdirname'}";

   ($user =~ /^(.+)$/) && ($user = $1);  # untaint ...
   ($uuid =~ /^(.+)$/) && ($uuid = $1);
   ($ugid =~ /^(.+)$/) && ($ugid = $1);
   ($homedir =~ /^(.+)$/) && ($homedir = $1);
   ($folderdir =~ /^(.+)$/) && ($folderdir = $1);

   umask(0077);
   if ( $config{'use_homedirspools'} || $config{'use_homedirfolders'} ) {
      my $mailgid=getgrnam('mail');
      set_euid_egids($uuid, $mailgid, $ugid);
      if ( $) != $mailgid) {	# egid must be mail since this is a mail program...
         openwebmailerror("Set effective gid to mail($mailgid) failed!");
      }
   }

   %prefs = %{&readprefs};
   %style = %{&readstyle};
   ($prefs{'language'} =~ /^([\w\d\.\-_]+)$/) && ($prefs{'language'} = $1);
   require "$config{'ow_langdir'}/$prefs{'language'}";
   if ($prefs{'iconset'}=~ /^Text\./) {
      ($prefs{'iconset'} =~ /^([\w\d\.\-_]+)$/) && ($prefs{'iconset'} = $1);
      require "$config{'ow_htmldir'}/images/iconsets/$prefs{'iconset'}/icontext";
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
}
#################### END OPENWEBMAIL_INIT ###################

####################### READCONF #######################
# read openwebmail.conf into a hash
# the hash is 'called by reference' since we want to do 'bypass taint' on it
sub readconf {
   my ($r_config, $r_config_raw, $configfile)=@_;

   if ($configfile=~/\.\./) {	# .. in path is not allowed for higher security
      openwebmailerror("Invalid config file path $configfile");
   }
   open(CONFIG, $configfile) or
      openwebmailerror("Couldn't open config file $configfile");
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
            if ($key ne "" && $value ne "" ) {
               ${$r_config_raw}{$key}=$value;
            }
         }
      }
   }
   close(CONFIG);

   # copy config_raw to config
   %{$r_config}=%{$r_config_raw};
   # resolv %var% in hash config
   foreach $key (keys %{$r_config}) {
      for (my $i=0; $i<5; $i++) {
        last if (${$r_config}{$key} !~ s/\%([\w\d_]+)\%/${$r_config}{$1}/msg);
      }
   }

   # processing yes/no
   foreach $key (qw(
      smtpauth use_hashedmailspools use_dotlockfile dbmopen_haslock
      create_homedir use_homedirspools use_homedirfolders
      auth_withdomain deliver_use_GMT savedsuid_support
      case_insensitive_login stay_ssl_afterlogin
      enable_rootlogin enable_domainselectmenu
      enable_changepwd enable_strictpwd enable_setfromemail
      session_multilogin session_checksameip session_checkcookie
      auto_createrc
      enable_about about_info_software about_info_protocol
      about_info_server about_info_client about_info_scriptfilename
      xmailer_has_version xoriginatingip_has_userid
      enable_setforward enable_strictforward
      enable_autoreply enable_strictfoldername enable_stationery
      enable_calendar enable_webdisk enable_sshterm
      enable_pop3 delpop3mail_by_default delpop3mail_hidden
      getmail_from_pop3_authserver domainnames_override cutfolders_ifoverquota
      webdisk_readonly webdisk_lsmailfolder webdisk_lshidden webdisk_lsunixspec
      webdisk_lssymlink webdisk_allow_symlinkouthome webdisk_allow_thumbnail
      default_autopop3
      default_reparagraphorigmsg default_backupsentmsg
      default_confirmmsgmovecopy default_viewnextaftermsgmovecopy
      default_moveoldmsgfrominbox forced_moveoldmsgfrominbox
      default_hideinternal symboliclink_mbox
      default_filter_fakedsmtp default_filter_fakedfrom
      default_filter_fakedexecontenttype
      default_disablejs default_disableembcgi
      default_showimgaslink default_regexmatch
      default_usefixedfont default_usesmileicon
      default_abook_usedefaultfilter
      default_calendar_showemptyhours
      default_calendar_reminderforglobal
      default_webdisk_confirmmovecopy
      default_webdisk_confirmdel default_webdisk_confirmcompress
   )) {
      if (${$r_config}{$key} =~ /yes/i || ${$r_config}{$key} == 1) {
         ${$r_config}{$key}=1;
      } else {
         ${$r_config}{$key}=0;
      }
   }

   # processing auto
   if ( ${$r_config}{'domainnames'} eq 'auto' ) {
      if ($ENV{'HTTP_HOST'}=~/[A-Za-z]\./) {
         $value=$ENV{'HTTP_HOST'}; $value=~s/:\d+$//;	# remove port number
      } else {
         $value=`/bin/hostname`;
         $value=~s/^\s+//; $value=~s/\s+$//;
      }
      ${$r_config}{'domainnames'}=$value;
   }
   if ( ${$r_config}{'default_timeoffset'} eq 'auto' ) {
      ${$r_config}{'default_timeoffset'}=gettimeoffset();
   }

   # processing list
   foreach $key (qw(
      domainnames spellcheck_dictionaries
      allowed_serverdomain
      allowed_clientdomain allowed_clientip
      allowed_receiverdomain disallowed_pop3servers
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
      'ow_usersdir', 'ow_sessionsdir',
      'vacationinit', 'vacationpipe', 'spellcheck',
      'global_addressbook', 'global_filterbook', 'global_calendarbook'
   ) {
      (${$r_config}{$key} =~ /^(.+)$/) && (${$r_config}{$key}=$1);
   }
   foreach my $domain ( @{${$r_config}{'domainnames'}} ) {
      ($domain =~ /^(.+)$/) && ($domain=$1);
   }

   return 0;
}
##################### END READCONF #######################

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
      my ($metainfo);

      if (!$config{'dbmopen_haslock'}) {
         filelock("$virdb$config{'dbm_ext'}", LOCK_SH) or return;
      }
      dbmopen (%DB, "$virdb$config{'dbmopen_ext'}", undef);
      $metainfo=$DB{'METAINFO'};
      dbmclose(%DB);
      filelock("$virdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

      return if ( $metainfo eq metainfo($virfile) );
   }

   writelog("update $virdb");

   unlink("$virdb$config{'dbm_ext'}",
          "$virdb.rev$config{'dbm_ext'}",);

   dbmopen(%DB, "$virdb$config{'dbmopen_ext'}", 0644);
   dbmopen(%DBR, "$virdb.rev$config{'dbmopen_ext'}", 0644);
   if (!$config{'dbmopen_haslock'}) {
      if (!filelock("$virdb$config{'dbm_ext'}", LOCK_EX) ||
          !filelock("$virdb.rev$config{'dbm_ext'}", LOCK_EX) ) {
         filelock("$virdb$config{'dbm_ext'}", LOCK_UN);
         filelock("$virdb.rev$config{'dbm_ext'}", LOCK_UN);
         dbmclose(%DB);
         dbmclose(%DBR);
      }
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

   filelock("$virdb.rev$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   dbmclose(%DBR);
   filelock("$virdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   dbmclose(%DB);
   return;
}

sub get_user_by_virtualuser {
   my ($vu, $virdb)=@_;
   my %DB=();
   my $u='';

   if ( -f "$virdb$config{'dbm_ext'}" && !-z "$virdb$config{'dbm_ext'}" ) {
      if (!$config{'dbmopen_haslock'}) {
         filelock("$virdb$config{'dbm_ext'}", LOCK_SH) or return($u);
      }
      dbmopen (%DB, "$virdb$config{'dbmopen_ext'}", undef);
      $u=$DB{$vu};
      dbmclose(%DB);
      filelock("$virdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   }
   return($u);
}

sub get_virtualuser_by_user {
   my ($user, $virdbr)=@_;
   my %DBR=();
   my $vu='';

   if ( -f "$virdbr$config{'dbm_ext'}" && !-z "$virdbr$config{'dbm_ext'}" ) {
      if (!$config{'dbmopen_haslock'}) {
         filelock("$virdbr$config{'dbm_ext'}", LOCK_SH) or return($vu);
      }
      dbmopen (%DBR, "$virdbr$config{'dbmopen_ext'}", undef);
      $vu=$DBR{$user};
      dbmclose(%DBR);
      filelock("$virdbr$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
   }
   return($vu);
}

sub get_domain_user_userinfo {
   my $loginname=$_[0];
   my ($domain, $user, $realname, $uid, $gid, $homedir);
   my ($l, $u);

   if ($loginname=~/^(.*)\@(.*)$/) {
      ($user, $domain)=($1, lc($2));
   } else {
      if($config{'auth_domain'} ne 'auto') {
         ($user, $domain)=($loginname, lc($config{'auth_domain'}));
      } else {
         my $httphost=$ENV{'HTTP_HOST'}; $httphost=~s/:\d+$//;        # remove port number
         ($user, $domain)=($loginname, lc($httphost));
      }
   }
   my $default_realname=$user;

   my $virtname=$config{'virtusertable'};
   $virtname=~s!/!.!g; $virtname=~s/^\.+//;

   $l="$user\@$domain";
   $u=get_user_by_virtualuser($l, "$config{'ow_etcdir'}/$virtname");
   if ($u eq "") {
      my $d=$domain;
      if ($d=~s/^(mail|webmail|www|web)\.//) {
         $l="$user\@$d";
         $u=get_user_by_virtualuser($l, "$config{'ow_etcdir'}/$virtname");
      } else {
         $l="$user\@mail.$d";
         $u=get_user_by_virtualuser($l, "$config{'ow_etcdir'}/$virtname");
      }
   }
   if ($u eq "" && $loginname!~/\@/) {
      $l=$user;
      $u=get_user_by_virtualuser($l, "$config{'ow_etcdir'}/$virtname");
   }

   if ($u ne "") {
      $loginname=$l;
      if ($u=~/^(.*)\@(.*)$/) {
         ($user, $domain)=($1, lc($2));
      } else {
         my $httphost=$ENV{'HTTP_HOST'}; $httphost=~s/:\d+$//;	# remove port number
         ($user, $domain)=($u, lc($httphost));
      }
   }

   if ($config{'auth_withdomain'}) {
      ($realname, $uid, $gid, $homedir)=get_userinfo("$user\@$domain");
   } else {
      ($realname, $uid, $gid, $homedir)=get_userinfo($user);
   }
   if ($config{'default_realname'} ne 'auto') {
      $realname=$config{'default_realname'}
   } else {
      $realname=$default_realname if ($realname eq "");
   }

   if ($uid ne "") {
      return($loginname, $domain, $user, $realname, $uid, $gid, $homedir);
   } else {
      return($loginname, "", "", "", "", "", "");
   }
}
##################### END VIRTUALUSER related ################

##################### GET_DEFAULTEMAILS, GET_USERFROM ################
sub get_defaultemails {
   my ($loginname, $user)=@_;
   my @emails=();

   if ($config_raw{'default_fromemails'} eq "auto") {
      my $virtname=$config{'virtusertable'};
      $virtname=~s!/!.!g; $virtname=~s/^\.+//;
      my $vu=get_virtualuser_by_user($user, "$config{'ow_etcdir'}/$virtname.rev");
      if ($vu ne "") {
         foreach my $name (str2list($vu,0)) {
            if ($name=~/^(.*)\@(.*)$/) {
               next if ($1 eq "");	# skip whole @domain mapping
               if ($config{'domainnames_override'}) {
                  my $purename=$1;
                  foreach my $host (@{$config{'domainnames'}}) {
                     push(@emails,  "$purename\@$host");
                  }
               } else {
                  push(@emails, $name);
               }
            } else {
               foreach my $host (@{$config{'domainnames'}}) {
                  push(@emails, "$name\@$host");
               }
            }
         }
      } else {
         my $name=$loginname;
         $name=$1 if ($loginname =~ /^(.+)\@/ );
         foreach my $host (@{$config{'domainnames'}}) {
            push(@emails, "$name\@$host");
         }
      }
   } else {
      push(@emails, @{$config{'default_fromemails'}});
   }
   return(@emails);
}

sub get_userfrom {
   my ($loginname, $user, $realname, $frombook)=@_;
   my %from=();

   # get default fromemail
   my @defaultemails=get_defaultemails($loginname, $user);
   foreach (@defaultemails) {
      $from{$_}=$realname;
   }

   # get user defined fromemail
   if (open (FROMBOOK, $frombook)) {
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
##################### END GET_DEFAULTEMAILS GET_USERFROM ################

###################### READPREFS #########################
# error message is hardcoded with english
# since $prefs{'language'} has not been initialized before this routine
sub readprefs {
   my (%prefshash, $key, $value);

   # read .openwebmailrc
   if ( -f "$folderdir/.openwebmailrc" ) {
      open (RC, "$folderdir/.openwebmailrc") or
         openwebmailerror("Couldn't open $folderdir/.openwebmailrc!");
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
         openwebmailerror("Couldn't open $signaturefile!");
      while (<SIGNATURE>) {
         $prefshash{"signature"} .= $_;
      }
      close (SIGNATURE);
   }

   # get default value from config for err/undefined/empty prefs entries

   # validate email with defaultemails if setfromemail is not allowed
   if (!$config{'enable_setfromemail'} || $prefshash{'email'} eq "") {
      my @defaultemails=get_defaultemails($loginname, $user);
      my $valid=0;
      foreach (@defaultemails) {
         if ($prefshash{'email'} eq $_) {
            $valid=1; last;
         }
      }
      if (! $valid) {
         $prefshash{'email'}=$defaultemails[0];
      }
   }

   # all rc entries are disallowed to be empty
   foreach $key (@openwebmailrcitem) {
      if ( !defined($prefshash{$key}) || $prefshash{$key} eq "" ) {
          $prefshash{$key}=$config{'default_'.$key} if (defined($config{'default_'.$key}));
      }
   }

   # signature allowed to be empty but not undefined
   foreach $key ( 'signature') {
      $prefshash{$key}=$config{'default_'.$key} if (!defined($prefshash{$key}));
   }

   # remove / and .. from variables that will be used in require statement for security
   $prefshash{'language'}=~s|/||g;
   $prefshash{'language'}=~s|\.\.||g;

   # entries related to ondisk dir or file
   $prefshash{'language'}=$config{'default_language'} if (!defined($languagenames{$prefshash{'language'}}));
   $prefshash{'style'}=$config{'default_style'} if (!-f "$config{'ow_stylesdir'}/$prefshash{'style'}");
   $prefshash{'iconset'}=$config{'default_iconset'} if (!-d "$config{'ow_htmldir'}/images/iconsets/$prefshash{'iconset'}");

   $prefshash{'refreshinterval'}=$config{'min_refreshinterval'} if ($prefshash{'refreshinterval'} < $config{'min_refreshinterval'});
   $prefshash{'charset'}=$languagecharsets{$prefshash{'language'}} if ($prefshash{'charset'} eq "auto");

   return \%prefshash;
}
##################### END READPREFS ######################

###################### READSTYLE #########################
# error message is hardcoded with english
# since $prefs{'language'} has not been initialized before this routine
# This routine must be called after readstyle
# since it references $prefs{'bgurl'}
sub readstyle {
   my ($key,$value);
   my $stylefile = $prefs{'style'} || 'Default';
   my %stylehash;

   if (!-f "$config{'ow_stylesdir'}/$stylefile") {
      $stylefile = 'Default';
   }
   open (STYLE,"$config{'ow_stylesdir'}/$stylefile") or
      openwebmailerror("Couldn't open $config{'ow_stylesdir'}/$stylefile!");
   while (<STYLE>) {
      if (/###STARTSTYLESHEET###/) {
         $stylehash{"css"} = '';
         while (<STYLE>) {
            $stylehash{"css"} .= $_;
         }
      } else {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         $stylehash{"$key"} = $value;
      }
   }
   close (STYLE);

   $stylehash{"css"}=~ s/\@\@\@BG_URL\@\@\@/$prefs{'bgurl'}/g;
   $stylehash{"css"}=~ s/\@\@\@FONTSIZE\@\@\@/$prefs{'fontsize'}/g;
   $stylehash{"css"}=~ s/\@\@\@MEDFONTSIZE\@\@\@/$medfontsize{$prefs{'fontsize'}}/g;
   if ($prefs{'usefixedfont'}) {
      $stylehash{"css"}=~ s/\@\@\@FIXEDFONT\@\@\@/"Courier New",/g;
   } else {
      $stylehash{"css"}=~ s/\@\@\@FIXEDFONT\@\@\@//g;
   }
   return \%stylehash;
}
##################### END READSTYLE ######################

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
   $template =~ s/\@\@\@HELP_LINK\@\@\@/$url/g;

   $url=$config{'start_url'};
   if (cookie("openwebmail-ssl")) {
      $url="https://$ENV{'HTTP_HOST'}$url" if ($url!~m!^https?://!i);
   }
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

#################### READTEMPLATE ###########################
sub readtemplate {
   my $templatename=$_[0];
   my $content;

   open (T, "$config{'ow_templatesdir'}/$prefs{'language'}/$templatename") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_templatesdir'}/$prefs{'language'}/$templatename!");
   while (<T>) { $content .= $_; }
   close (T);
   return($content);
}
#################### END READTEMPLATE ###########################

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
         my ($pop3host, $pop3user, $pop3passwd, $pop3lastid, $pop3del, $enable)
							=split(/\@\@\@/, $_);
         ${$r_accounts}{"$pop3host\@\@\@$pop3user"} = "$pop3host\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3lastid\@\@\@$pop3del\@\@\@$enable";
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
     print POP3BOOK $_ . "\n";
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

############## VERIFYSESSION ########################
sub verifysession {
   openwebmailerror("Session ID $lang_err{'has_illegal_chars'}") unless
      (($thissession =~ /^([\w\.\-\%\@]+)$/) && ($thissession = $1));

   if ( (-M "$config{'ow_sessionsdir'}/$thissession") > $prefs{'sessiontimeout'}/60/24
     || !(-e "$config{'ow_sessionsdir'}/$thissession")) {

      my $delfile="$config{'ow_sessionsdir'}/$thissession";
      ($delfile =~ /^(.+)$/) && ($delfile = $1);  # untaint ...
      unlink ($delfile) if ( -e "$delfile");

      my $html=readtemplate("sessiontimeout.template");
      $html = applystyle($html);

      printheader();
      print $html;
      printfooter(1);

      writelog("session error - session $thissession timeout access attempt");
      writehistory("session error - session $thissession timeout access attempt");
      exit 0;
   }

   my $clientip=get_clientip();
   my $clientcookie=cookie("$user-sessionid");
   if ( -e "$config{'ow_sessionsdir'}/$thissession" ) {
      open (SESSION, "$config{'ow_sessionsdir'}/$thissession");
      my $cookie = <SESSION>; chomp $cookie;
      my $ip = <SESSION>; chomp $ip;
      close (SESSION);

      if ( $config{'session_checkcookie'} &&
           $clientcookie ne $cookie ) { 
         writelog("session error - request doesn't have proper cookie, access denied!");
         writehistory("session error - request doesn't have proper cookie, access denied !");
         openwebmailerror("$lang_err{'sess_cookieerr'}");
      }
      if ( $config{'session_checksameip'} &&
           $clientip ne $ip) { 
         writelog("session error - request doesn't come from the same ip, access denied!");
         writehistory("session error - request doesn't com from the same ip, access denied !");
         openwebmailerror("$lang_err{'sess_iperr'}");
      }
   }

   my $session_noupdate=param('session_noupdate');
   if (!$session_noupdate) {
      # extend the session lifetime only if not auto-refresh/timeoutwarning
      open (SESSION, "> $config{'ow_sessionsdir'}/$thissession") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}/$thissession!");
      print SESSION "$clientcookie\n$clientip\n";
      close (SESSION);
   }
   return 1;
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
sub getfolders {
   my ($r_folders, $r_usage)=@_;
   my @delfiles=();
   my @userfolders;
   my $totalsize = 0;
   my $filename;

   my @fdirs=($folderdir);		# start with root folderdir
   while (my $fdir=pop(@fdirs)) {
      opendir (FOLDERDIR, "$fdir") or
    	 openwebmailerror("$lang_err{'couldnt_open'} $fdir!");

      while (defined($filename = readdir(FOLDERDIR))) {
         ($filename =~ /^(.+)$/) && ($filename = $1);   # untaint data from readdir
         next if ( $filename eq "." || $filename eq ".." );
         if (-d "$fdir/$filename" && $filename!~/^\./) { # recursive into non dot dir
            push(@fdirs,"$fdir/$filename");
            next;
         }

         # find internal file that are stale
         if ( $filename=~/^\.(.*)\.db$/ ||
              $filename=~/^\.(.*)\.dir$/ ||
              $filename=~/^\.(.*)\.pag$/ ||
              $filename=~/^(.*)\.lock$/ ||
              ($filename=~/^\.(.*)\.cache$/ &&
               $filename ne ".search.cache" &&
               $filename ne ".webdisk.cache")
            ) {
            if ($1 ne $user &&
                $1 ne 'address.book' &&
                $1 ne 'filter.book' &&
                ! -f "$folderdir/$1" ) {
               # dbm or cache whose folder doesn't exist
               push (@delfiles, "$folderdir/$filename");
               next;
            }
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
         openwebmailerror("$lang_err{'couldnt_close'} $folderdir!");
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
      chown ($uuid, $ugid, $spoolfile);
   }

   if ($config{'folderquota'}) {
      ${$r_usage}=int($totalsize*1000/($config{'folderquota'}*1024))/10;
   } else {
      ${$r_usage}=0;
   }

   return;
}
################ END GETFOLDERS ##################

#################### GETMESSAGE ###########################
sub getmessage {
   my ($messageid, $mode) = @_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();
   my $r_messageblock;
   my %message = ();

   filelock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
   if (update_headerdb($headerdb, $folderfile)<0) {
      filelock($folderfile, LOCK_UN);
      openwebmailerror("$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
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

      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");

      if (!$config{'dbmopen_haslock'}) {
         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX) or
            openwebmailerror("$lang_err{'couldnt_lock'} $headerdb$config{'dbm_ext'}");
      }
      my %HDB;
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", 0600);
      $HDB{'METAINFO'}="ERR";
      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
      # forced reindex since metainfo = ERR
      if (update_headerdb($headerdb, $folderfile)<0) {
         filelock($folderfile, LOCK_UN);
         openwebmailerror("$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
      }

      open($folderhandle, "$folderfile");
      $r_messageblock=get_message_block($messageid, $headerdb, $folderhandle);
      close($folderhandle);

      filelock($folderfile, LOCK_UN);

      return \%message if (${$r_messageblock} eq "" );
   }

   my ($currentheader, $currentbody, $r_currentattachments, $currentfrom, $currentdate,
       $currentsubject, $currentid, $currenttype, $currentto, $currentcc, $currentbcc,
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
   $currentstatus = '';
   $currentpriority = '';
   $currentinreplyto = $currentreferences = '';

   my $lastline = 'NONE';
   my @smtprelays=();
   foreach (split(/\n/, $currentheader)) {
      if (/^\s/) {
         s/^\s+/ /;
         if    ($lastline eq 'FROM') { $currentfrom .= $_ }
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
sub getinfomessageids {
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $index_complete=0;

   # do new indexing in background if folder > 10 M && empty db
   if ( (stat("$headerdb$config{'dbm_ext'}"))[7]==0 &&
        (stat($folderfile))[7] >= 10485760 ) {
      $|=1; 				# flush all output
      $SIG{CHLD} = sub { wait; $index_complete=1 if ($?==0) };	# handle zombie
      if ( fork() == 0 ) {		# child
         close(STDOUT);
         close(STDIN);
         filelock($folderfile, LOCK_SH|LOCK_NB) or exit 1;
         update_headerdb($headerdb, $folderfile);
         filelock($folderfile, LOCK_UN);
         exit 0;
      }

      for (my $i=0; $i<120; $i++) {	# wait index to complete for 120 seconds
         sleep 1;
         last if ($index_complete==1);
      }
      if ($index_complete==0) {
         openwebmailerror("$folderfile $lang_err{'under_indexing'}");
      }
   } else {	# do indexing directly if small folder
      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
      if (update_headerdb($headerdb, $folderfile)<0) {
         filelock($folderfile, LOCK_UN);
         openwebmailerror("$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
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
      my $folderhandle=FileHandle->new();
      my ($totalsize, $new, $r_haskeyword, $r_messageids, $r_messagedepths);
      my @messageids=();
      my @messagedepths=();

      ($totalsize, $new, $r_messageids, $r_messagedepths)=get_info_messageids_sorted($headerdb, $sort, "$headerdb.cache", $prefs{'hideinternal'});

      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
      open($folderhandle, $folderfile);
      ($totalsize, $new, $r_haskeyword)=search_info_messages_for_keyword($keyword, $searchtype, $headerdb, $folderhandle, "$folderdir/.search.cache", $prefs{'hideinternal'}, $prefs{'regexmatch'});
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

################# CUTFOLDERS ############################
sub cutfolders {
   my @folders=@_;
   return 0 if ($config{'folderquota'}==0);	# quota disabled?
   my $availablequota=$config{'folderquota'}*1024;
   my ($total_foldersize, $user_foldersize)=(0,0);
   my (@userfolders, %foldersize, %folderfile, %headerdb);

   foreach my $f (@folders) {
      ($folderfile{$f},$headerdb{$f})=get_folderfile_headerdb($user, $f);
      $foldersize{$f} = (-s "$folderfile{$f}") + (-s "$headerdb{$f}$config{'dbm_ext'}");
      if ($f ne 'INBOX' &&
          $f ne 'saved-messages' &&
          $f ne 'sent-mail' &&
          $f ne 'saved-drafts' &&
          $f ne 'mail-trash') {
         push (@userfolders, $f);
         $user_foldersize+=$foldersize{$f};
      }
      $total_foldersize+=$foldersize{$f};
   }
   return 0 if ($total_foldersize < $availablequota);

   # empty folders
   foreach my $f ('mail-trash', 'saved-drafts') {	
      next if ( (-s "$folderfile{$f}")==0 );

      filelock($folderfile{$f}, LOCK_SH|LOCK_NB) or return -1;
      open (F, ">$folderfile{$f}") or return -2; close (F);
      my $ret=update_headerdb($headerdb{$f}, $folderfile{$f});
      filelock($folderfile{$f}, LOCK_UN);
      return -3 if ($ret<0);

      $total_foldersize -= $foldersize{$f};
      $foldersize{$f} = (-s "$folderfile{$f}") + (-s "$headerdb{$f}$config{'dbm_ext'}");
      $availablequota -= $foldersize{$f};
      return 0 if ($total_foldersize < $availablequota);
   }

   # set 90% availablequota as cut edge
   $availablequota=$availablequota*0.9;
   # cut folders
   my @cutfolders=('sent-mail', 'saved-messages');

   # put @userfolders to cutlist if it occupies more than 33% of quota
   if ($user_foldersize > $availablequota*0.33) {
      push (@cutfolders, sort(@userfolders));
   } else {
      $total_foldersize -= $user_foldersize;
      $availablequota -= $user_foldersize;
   }
   # put INBOX to cutlist if it occupies more than 33% of quota
   if ($foldersize{'INBOX'} > $availablequota*0.33) {
      push (@cutfolders, 'INBOX');
   } else {
      $total_foldersize -= $foldersize{'INBOX'};
      $availablequota -= $foldersize{'INBOX'};
   }

   for (my $i=0; $i<3; $i++) {
      # cal percent for size exceeding availablequota
      my $cutpercent=($total_foldersize-$availablequota)/$total_foldersize;
      $cutpercent=0.1 if ($cutpercent<0.1);
      foreach my $f (@cutfolders) {
         next if ( (-s "$folderfile{$f}")==0 );

         my $ret;
         if ($f eq 'sent-mail') {
            $ret=cutfolder($folderfile{$f}, $headerdb{$f}, $cutpercent+0.1);
         } else {
            $ret=cutfolder($folderfile{$f}, $headerdb{$f}, $cutpercent);
         }
         if ($ret<0) {
            writelog("cutfolder error - folder $f ret=$ret");
            writehistory("cutfolder error - folder $f ret=$ret");
            next;
         }

         my $origsize=$foldersize{$f};
         $total_foldersize -= $foldersize{$f};
         $foldersize{$f} = (-s "$folderfile{$f}") + (-s "$headerdb{$f}$config{'dbm_ext'}");
         $total_foldersize += $foldersize{$f};

         writehistory(sprintf("cutfolder - $f from %dk to %dk", $origsize/1024, $foldersize{$f}/1024));

         return 0 if ($total_foldersize < $availablequota);
      }
   }

   writelog("cutfolders error - still quota($config{'folderquota'} kb) exceeded");
   writehistory("cutfolders error - still quota($config{'folderquota'} kb) exceeded");
   return -5;
}

sub cutfolder {				# reduce folder size by $cutpercent
   my ($folderfile, $headerdb, $cutpercent) = @_;
   my (@delids, $delsize, %HDB);

   filelock($folderfile, LOCK_SH|LOCK_NB) or return -1;

   return -2 if (update_headerdb($headerdb, $folderfile)<0);

   my ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_date($headerdb, 0);

   if (!$config{'dbmopen_haslock'}) {
      filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) or return -3;
   }
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
   foreach my $id  (reverse @{$r_messageids}) {
      push(@delids, $id);
      $delsize += (split(/@@@/, $HDB{$id}))[$_SIZE];
      last if ($delsize > $totalsize*$cutpercent);
   }
   dbmclose (%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

   my $counted=operate_message_with_ids("delete", \@delids, $folderfile, $headerdb);

   filelock($folderfile, LOCK_UN);

   return($counted);
}
################# END CUTFOLDERS ########################

################# FILTERMESSAGE ###########################
sub filtermessage {
   my ($filtered, $r_filtered)=mailfilter($user, 'INBOX', $folderdir, \@validfolders, $prefs{'regexmatch'},
					$prefs{'filter_repeatlimit'}, $prefs{'filter_fakedsmtp'},
        				$prefs{'filter_fakedfrom'}, $prefs{'filter_fakedexecontenttype'});
   if ($filtered > 0) {
      my $dststr;
      foreach my $destination (sort keys %{$r_filtered}) {
         next if ($destination eq '_ALL' || $destination eq 'INBOX');
         $dststr .= ", " if ($dststr ne "");
         $dststr .= $destination;
         $dststr .= "(${$r_filtered}{$destination})" if (${$r_filtered}{$destination} ne $filtered);
      }
      writelog("filtermsg - filter $filtered msgs from INBOX to $dststr");
      writehistory("filtermsg - filter $filtered msgs from INBOX to $dststr");
   } elsif ($filtered == -1 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.check!");
   } elsif ($filtered == -2 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
   } elsif ($filtered == -3 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} .filter.book$config{'dbm_ext'}!");
   } elsif ($filtered == -4 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} INBOX!");
   } elsif ($filtered == -5 ) {
      openwebmailerror("$lang_err{'couldnt_open'} INBOX!");
   } elsif ($filtered == -6 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} INBOX folder index!");
   } elsif ($filtered == -7 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} mail-trash!");
   } elsif ($filtered == -8 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.check!");
   } elsif ($filtered == -9 ) {
      openwebmailerror("mailfilter I/O error!");
   }
   return($filtered, $r_filtered);
}
################# END FILTERMESSAGE #######################

##################### WRITELOG ############################
sub writelog {
   my ($logaction)=$_[0];
   return if ( ($config{'logfile'} eq 'no') || ( -l "$config{'logfile'}" ) );

   my $timestamp = localtime();
   my $loggeduser = $loginname || 'UNKNOWNUSER';
   my $loggedip = get_clientip();

   open (LOGFILE,">>$config{'logfile'}") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'logfile'}!");
   print LOGFILE "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
   close (LOGFILE);

   return;
}
#################### END WRITELOG #########################

################## WRITEHISTORY ####################
sub writehistory {
   my ($logaction)=$_[0];
   my $timestamp = localtime();
   my $loggeduser = $loginname || 'UNKNOWNUSER';
   my $loggedip = get_clientip();

   if ( -f "$folderdir/.history.log" ) {
      my ($start, $end, $buff);

      filelock("$folderdir/.history.log", LOCK_EX) or
         openwebmailerror("$lang_err{'couldnt_lock'} $folderdir/.history.log");
      open (HISTORYLOG,"+< $folderdir/.history.log") or
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.history.log");
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
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.history.log");
      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
      close(HISTORYLOG);
   }

   return 0;
}

################ END WRITEHISTORY ##################

##################### PRINTHEADER/PRINTFOOTER #########################
# $headerprinted is set to 1 once printheader is called and seto 0 until
# printfooter is called. This variable is used to not print header again
# in openwebmailerror
my $headerprinted=0;

sub printheader {
   my @headers=();

   if (!$headerprinted) {
      $headerprinted = 1;

      my $html=readtemplate("header.template");
      $html = applystyle($html);

      $html =~ s/\@\@\@ICO_LINK\@\@\@/$config{'ico_url'}/g;
      $html =~ s/\@\@\@BG_URL\@\@\@/$prefs{'bgurl'}/g;
      $html =~ s/\@\@\@CHARSET\@\@\@/$prefs{'charset'}/g;

      my $info;
      if ($user) {
         $info=qq|$prefs{'email'} -|;
         $info=qq|$prefs{'email'} ($folderusage%) -| if ($config{'folderquota'});
      }
      $info .= " ". dateserial2str(add_dateserial_timeoffset(gmtime2dateserial(),$prefs{'timeoffset'}), $prefs{'dateformat'}). " -";
      $html =~ s/\@\@\@USERINFO\@\@\@/$info/g;

      push(@headers, -charset=>$prefs{'charset'}) if ($CGI::VERSION>=2.57);
      push(@headers, -pragma=>'no-cache');
      push(@headers, @_);
      print header(@headers);
      print $html;
   }
}

sub printfooter {
   my ($mode, $jscode)=@_;
   my $html = '';

   $headerprinted = 0;

   if ($mode==2) {	# read in timeout check jscript
      $html=readtemplate("footer.js.template");
      my $remainingseconds= 365*24*60*60;	# default timeout = 1 year
      if ($thissession ne "") { 	# if this is a session
         my $sessionage=(-M "$config{'ow_sessionsdir'}/$thissession");
         if ($sessionage ne "") {	# if this session is valid
            $remainingseconds= ($prefs{'sessiontimeout'}/60/24-$sessionage)
				*24*60*60 - (time()-$^T);
         }
      }
      $html =~ s/\@\@\@REMAININGSECONDS\@\@\@/$remainingseconds/g;
      $html =~ s/\@\@\@JSCODE\@\@\@/$jscode/g;
   }

   if ($mode>=1) {	# print footer
      $html.=readtemplate("footer.template");
      $html = applystyle($html);
      $html =~ s/\@\@\@USEREMAIL\@\@\@/$prefs{'email'}/g;
   }

   if ($mode==0) {	# null footer
      $html=qq|</body></html>\n|;
   }

   print $html;
}
################# END PRINTHEADER/PRINTFOOTER #########################

##################### OPENWEBMAILERROR ##########################
sub openwebmailerror {
   my $mailgid=getgrnam('mail');

   if (defined($ENV{'HTTP_HOST'})) {	# in CGI mode
      # load prefs if possible, or use default value
      my $background = $style{"background"}||"#FFFFFF";
      my $css = $style{"css"}||"";
      my $fontface = $style{"fontface"}||"Arial, Helvetica";
      my $titlebar = $style{"titlebar"}||"#002266";
      my $titlebar_text = $style{"titlebar_text"}||"#FFFFFF";
      my $window_light = $style{"window_light"}||"#EEEEEE";

      if (!$headerprinted) {
         $headerprinted = 1;
         $background =~ s/"//g;

         if ( $CGI::VERSION>=2.57) {
            print header(-pragma=>'no-cache',
                         -charset=>$prefs{'charset'});
         } else {
            print header(-pragma=>'no-cache');
         }
         print start_html(-"title"=>"$config{'name'}",
                          -BGCOLOR=>"$background",
                          -BACKGROUND=>$prefs{'bgurl'});
         print qq|<style type="text/css">|,
               $css,
               qq|</style>|,
               qq|<font face=$fontface>\n|;
      }
      print qq|<br><br><br><br><br><br><br>|,
            qq|<table border="0" align="center" width="40%" cellpadding="1" cellspacing="1">|,
            qq|<tr><td bgcolor=$titlebar>\n|,
            qq|<font color=$titlebar_text face=$fontface size="3"><b>$config{'name'} ERROR</b></font>\n|,
            qq|</td></tr>|,
            qq|<tr><td align="center" bgcolor=$window_light><br>\n|;

      print @_, qq|<br><br>\n|;
#      print qq|<font color=$window_light size=-2>euid=$>, egid=$), mailgid=$mailgid</font><br>\n|;

      print qq|</td></tr>|,
            qq|</table>\n|,
            qq|<p align="center"><font size="-1"><br>|,
            qq|$config{'page_footer'}<br>|,
            qq|</font></font></p></body></html>|;

      $headerprinted = 0;
      exit 0;

   } else { # command mode
      print join(" ",@_), " (euid=$>, egid=$), mailgid=$mailgid)\n";
      exit 1;
   }
}
################### END OPENWEBMAILERROR #######################

###################### AUTOCLOSEWINDOW ##########################
sub autoclosewindow {
   my ($title, $msg, $time, $jscode)=@_;
   $time=8 if ($time<3);

   if (defined($ENV{'HTTP_HOST'})) {	# in CGI mode
      printheader();
      my $html=readtemplate("autoclose.template");
      $html = applystyle($html);

      $html =~ s/\@\@\@MSGTITLE\@\@\@/$title/g;
      $html =~ s/\@\@\@MSG\@\@\@/$msg/g;
      $html =~ s/\@\@\@TIME\@\@\@/$time/g;
      $html =~ s/\@\@\@JSCODE\@\@\@/$jscode/g;

      my $temphtml = button(-name=>"okbutton",
                            -value=>$lang_text{'ok'},
                            -onclick=>'autoclose();',
                            -override=>'1');
      $html =~ s/\@\@\@OKBUTTON\@\@\@/$temphtml/g;

      print $html;
      printfooter(2);
      exit 0;
   } else {
      print "$title - $msg\n";
      exit 0;
   }
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
         $link=~s/\.(gif|jpg|png)$//i;
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
}
################### END SET_EUID_EGID_UMASK ###############

########################## METAINFO #########################
# return a string composed by the modify time & size of a file
sub metainfo {
   if (-e $_[0]) {
      # dev, ino, mode, nlink, uid, gid, rdev, size, atime, mtime, ctime, blksize, blocks
      my @l=stat($_[0]);
      return("mtime=$l[9] size=$l[7]");
   } else {
      return("");
   }
}

######################## END METAINFO #######################

#################### GET_CLIENTIP #############################
sub get_clientip {
   my $clientip;
   if (defined $ENV{'HTTP_X_FORWARDED_FOR'} &&
      $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^10\./ &&
      $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^172\.[1-3][0-9]\./ &&
      $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^192\.168\./ &&
      $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^127\.0\./ ) {
      $clientip=(split(/,/,$ENV{'HTTP_X_FORWARDED_FOR'}))[0];
   } elsif (defined $ENV{'REMOTE_ADDR'} ) {
      $clientip=$ENV{'REMOTE_ADDR'};
   } else {
      $clientip="127.0.0.1";
   }
   return $clientip;
}
#################### END GET_CLIENTIP #########################

#################### GET_PROTOCOL #########################
sub get_protocol {
   if ($config{'http_protocol'} eq 'auto') {
      if ($ENV{'HTTPS'}=~/on/i ||
#         $ENV{'HTTP_REFERER'}=~/^https/i ||
          $ENV{'SERVER_PORT'}==443 ) {
         return("https");
      } else {
         return("http");
      }
   } else {
      return($config{'http_protocol'});
   }
}
#################### END GET_PROTOCOL #########################

#################### GETTIMEOFFSET #########################
sub gettimeoffset {
   my $t=time();
   my @g=gmtime($t);
   my @l=localtime($t);
   my $gserial=sprintf("%04d%02d%02d%02d%02d%02d", $g[5], $g[4], $g[3], $g[2], $g[1]);
   my $lserial=sprintf("%04d%02d%02d%02d%02d%02d", $l[5], $l[4], $l[3], $l[2], $l[1]);
   my $offset;

   if ( $lserial gt $gserial ) {
      my ($hour, $min)=($l[2]-$g[2], $l[1]-$g[1]);
      if ($min<0) { $min+=60; $hour--; }
      if ($hour<0) { $hour+=24; }
      $offset=sprintf("+%02d%02d", $hour, $min);
   } elsif ( $lserial lt $gserial ) {
      my ($hour, $min)=($g[2]-$l[2], $g[1]-$l[1]);
      if ($min<0) { $min+=60; $hour--; }
      if ($hour<0) { $hour+=24; }
      $offset=sprintf("-%02d%02d", $hour, $min);
   } else {
      $offset="+0000";
   }
   return($offset);
}
#################### END GETTIMEOFFSET #########################

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
################## END TIMEOFFSET2SECONDS ######################

#################### ADD_DATESERIAL_TIMEOFFSET #########################
sub add_dateserial_timeoffset {
   my ($dateserial, $timeoffset)=@_;
   $dateserial=~/^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)$/;
   my ($y, $m, $d, $hour, $min, $sec)=($1,$2,$3, $4,$5,$6);

   if ($timeoffset=~/^([+\-]?)(\d\d)(\d\d)$/) {
      my ($sign, $houroffset, $minoffset)=($1, $2, $3);
      my @mday=(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
      $mday[1]++ if ( $y%400==0 || ($y%100!=0 && $y%4==0) ); # leap year
      if ($sign eq "-") {
         $min-=$minoffset;
         $hour-=$houroffset;
         if ($min  < 0 ) { $min +=60; $hour--; }
         if ($hour < 0 ) { $hour+=24; $d--; }
         if ($d    < 1 ) {
            $m--;
            if ($m < 1) { $m+=12; $y--; }
            $d+=$mday[$m-1];
         }
      } else {
         $min+=$minoffset;
         $hour+=$houroffset;
         if ($min  >= 60 )          { $min -=60; $hour++; }
         if ($hour >= 24 )          { $hour-=24; $d++; }
         if ($d    >  $mday[$m-1] ) { $d-=$mday[$m-1]; $m++; }
         if ($m    >  12 )          { $m-=12; $y++; }
      }
   }
   return(sprintf("%04d%02d%02d%02d%02d%02d", $y, $m, $d, $hour, $min, $sec));
}
#################### END ADD_DATESERIAL_TIMEOFFSET #########################

#################### LOCALTIME2DATESERIAL #########################
sub localtime2dateserial {
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime;
   return(sprintf("%4d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec));
}
#################### END LOCALTIME2DATESERIAL #########################

#################### GMTIME2DATESERIAL #########################
sub gmtime2dateserial {
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =gmtime;
   return(sprintf("%4d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec));
}
#################### END LOCALTIME2DATESERIAL #########################

##################### WEEKDAY_OF_DATESERIAL ####################
# we use 0001/01/01 as start base, it is monday
sub dateserial2daydiff {
   my $dateserial=$_[0];
   $dateserial=~/(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;
   my ($year, $mon, $mday, $hour, $min, $sec)=($1, $2, $3, $4, $5, $6);
   my @mdaybase=(0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);

   my $daydiff=($year-1)*365+int(($year-1)/4)-int(($year-1)/100)+int(($year-1)/400);
   $daydiff+=$mdaybase[$mon-1]+$mday -1;
   $daydiff++ if ( $mon>2 && ($year%400==0 || ($year%100!=0 && $year%4==0)) ); # leap year
   return($daydiff);
}

sub wdaynum_of_dateserial {
   my $daydiff=dateserial2daydiff($_[0]);
   return(($daydiff+1) % 7);
}
################### END WEEKDAY_OF_DATESERIAL ####################

################## DELIMITER2DATESERIAL #######################
sub delimiter2dateserial {	# return dateserial of GMT
   my ($delimiter, $deliver_use_GMT)=@_;

   # extract date from the 'From ' line, it must be in this form
   # From tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
   # From tung@turtle.ee.ncku.edu.tw Mon Aug 20 18:24 CST 2001
   # From nsb@thumper.bellcore.com   Wed Mar 11 16:27:37 EST 1992
   if ($delimiter =~ /(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d+):(\d+):?(\d*)\s+([A-Z]{3,4}\d?\s+)?(\d\d+)/) {
      my ($wdaystr, $monstr, $mday, $hour, $min, $sec, $zone, $year)
					=($1, $2, $3, $4, $5, $6, $7, $8);
      if ($year<50) {	# 2 digit year
         $year+=2000;
      } elsif ($year<=1900) {
         $year+=1900;
      }
      my $mon=$months{$monstr};

      my $dateserial=sprintf("%4d%02d%02d%02d%02d%02d", $year, $mon, $mday, $hour, $min, $sec);

      if (!$deliver_use_GMT) {
         # we don't trust the zone abbreviation in delimiter line because it is not unique.
         # see http://www.worldtimezone.com/wtz-names/timezonenames.html for detail
         my $timeoffset=gettimeoffset();
         $timeoffset=~s/\+/-/ || $timeoffset=~s/\-/+/;	# switch +/-
         $dateserial=add_dateserial_timeoffset($dateserial, $timeoffset);
      }
      return($dateserial);
   } else {
      return("");
   }
}
################## END DELIMITER2DATESERIAL #######################

#################### DATEFIELD2DATESERIAL #####################
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

   my $dateserial=sprintf("%04d%02d%02d%02d%02d%02d", $year,$mon,$mday, $hour,$min,$sec);
   if ($timeoffset ne "" && $timeoffset ne "+0000") {
      $timeoffset=~s/\+/-/ || $timeoffset=~s/\-/+/;	# switch +/-
      $dateserial=add_dateserial_timeoffset($dateserial, $timeoffset);
   }
   return($dateserial);
}
#################### END DATEFIELD2DATESERIAL #####################

#################### DATESERIAL2DELIMITER #####################
sub dateserial2delimiter {
   my ($dateserial, $timeoffset)=@_;
   $dateserial=add_dateserial_timeoffset($dateserial, $timeoffset);

   $dateserial=~/(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;
   my ($year, $mon, $mday, $hour, $min, $sec)=($1, $2, $3, $4, $5, $6);
   my $wday=wdaynum_of_dateserial($dateserial);

   # From tung@turtle.ee.ncku.edu.tw Fri Jun 22 14:15:33 2001
   return(sprintf("%3s %3s %2d %02d:%02d:%02d %4d",
              $wdaystr[$wday], $monthstr[$mon-1],$mday, $hour,$min,$sec, $year));
}
#################### END DATESERIAL2DELIMITER #####################

#################### DATESERIAL2DATEFIELD #####################
sub dateserial2datefield {
   my ($dateserial, $timeoffset)=@_;
   $dateserial=add_dateserial_timeoffset($dateserial, $timeoffset);

   $dateserial=~/(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;
   my ($year, $mon, $mday, $hour, $min, $sec)=($1, $2, $3, $4, $5, $6);
   my $wday=wdaynum_of_dateserial($dateserial);

   #Date: Wed, 9 Sep 1998 19:30:17 +0800 (CST)
   return(sprintf("%3s, %d %3s %4d %02d:%02d:%02d %s",
              $wdaystr[$wday], $mday,$monthstr[$mon-1],$year, $hour,$min,$sec, $timeoffset));
}
#################### END DATESERIAL2DATEFIELD #####################

##################### DATESERIAL2STR #######################
sub dateserial2str {
   my ($serial, $format)=@_;
   my $str;

   return $serial if ( $serial !~ /^(\d\d\d\d)(\d\d)(\d\d)(\d\d)?(\d\d)?(\d\d)?$/ );

   if ( $format eq "mm/dd/yyyy") {
      $str="$2/$3/$1";
   } elsif ( $format eq "dd/mm/yyyy") {
      $str="$3/$2/$1";
   } elsif ( $format eq "yyyy/mm/dd") {
      $str="$1/$2/$3";

   } elsif ( $format eq "mm-dd-yyyy") {
      $str="$2-$3-$1";
   } elsif ( $format eq "dd-mm-yyyy") {
      $str="$3-$2-$1";
   } elsif ( $format eq "yyyy-mm-dd") {
      $str="$1-$2-$3";

   } elsif ( $format eq "mm.dd.yyyy") {
      $str="$2.$3.$1";
   } elsif ( $format eq "dd.mm.yyyy") {
      $str="$3.$2.$1";
   } elsif ( $format eq "yyyy.mm.dd") {
      $str="$1.$2.$3";

   } else {
      $str="$2/$3/$1";
   }

   if ($6 ne "") {
      if ( $prefs{'hourformat'} eq "12") {
         my ($hour, $ampm)=hour24to12($4);
         $str.=sprintf(" %02d:$5:$6 $ampm", $hour);
      } else {
         $str.=" $4:$5:$6";
      }
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
   if (length($dlname)>45) {   # IE6 go crazy if fname longer than 45, tricky!
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
   my $ext=lc($_[0]);

   return("text/plain")			if ($ext =~ /(asc|te?xt|cc?|h|cpp|asm|pas|f77|lst|sh|pl)$/);
   return("text/xml")			if ($ext =~ /(xml|xsl)$/);
   return("text/html")			if ($ext =~ /html?$/);
   return("text/richtext")		if ($ext =~ /rtx$/);
   return("text/sgml")			if ($ext =~ /sgml?$/);
   return("text/vnd.wap.wml")		if ($ext =~ /wml$/);
   return("text/vnd.wap.wmlscript")	if ($ext =~ /wmls$/);
   return("text/$1")			if ($ext =~ /(css|rtf)$/);

   return("model/vrml")			if ($ext =~ /(wrl|vrml)$/);

   return("image/jpeg")			if ($ext =~ /(jpg|jpe|jpeg)$/);
   return("image/tiff")			if ($ext =~ /tiff?$/);
   return("image/x-cmu-raster")		if ($ext =~ /ras$/);
   return("image/x-portable-anymap")	if ($ext =~ /pnm$/);
   return("image/x-portable-bitmap")	if ($ext =~ /pbm$/);
   return("image/x-portable-grayma")	if ($ext =~ /pgm$/);
   return("image/x-portable-pixmap")	if ($ext =~ /ppm$/);
   return("image/x-rgb")		if ($ext =~ /rgb$/);
   return("image/x-xbitmap")		if ($ext =~ /xbm$/);
   return("image/x-xpixmap")		if ($ext =~ /xpm$/);
   return("image/$1")			if ($ext =~ /(bmp|gif|ief|png|psp)$/);

   return("video/mpeg")			if ($ext =~ /(mpeg?|mpg|mp2)$/);
   return("video/quicktime")		if ($ext =~ /(mov|qt)$/);
   return("video/x-msvideo")		if ($ext =~ /(avi|wav|dl|fli)$/);

   return("audio/basic")		if ($ext =~ /(au|snd)$/);
   return("audio/midi")			if ($ext =~ /(midi?|kar)$/);
   return("audio/mpeg")			if ($ext =~ /(mp[23]|mpga)$/);
   return("audio/x-mpegurl")		if ($ext =~ /m3u$/);
   return("audio/x-aiff")		if ($ext =~ /aif[fc]?$/);
   return("audio/x-pn-realaudio")	if ($ext =~ /ra?m$/);
   return("audio/x-realaudio")		if ($ext =~ /ra$/);
   return("audio/x-wav")		if ($ext =~ /wav$/);

   return("application/msword") 	if ($ext =~ /doc$/);
   return("application/x-mspowerpoint") if ($ext =~ /ppt$/);
   return("application/x-msexcel") 	if ($ext =~ /xls$/);
   return("application/x-msvisio")	if ($ext =~ /visio$/);

   return("application/postscript")	if ($ext =~ /(ps|eps|ai)$/);
   return("application/mac-binhex40")	if ($ext =~ /hqx$/);
   return("application/xhtml+xml")	if ($ext =~ /(xhtml|xht)$/);
   return("application/x-javascript")	if ($ext =~ /js$/);
   return("application/x-vcard")	if ($ext =~ /vcf$/);
   return("application/x-shockwave-flash") if ($ext =~ /swf$/);
   return("application/x-texinfo")	if ($ext =~ /(texinfo|texi)$/);
   return("application/x-troff")	if ($ext =~ /(tr|roff)$/);
   return("application/x-troff-$1")     if ($ext =~ /(man|me|ms)$/);
   return("application/x-$1")		if ($ext=~ /(dvi|latex|shar|tar|tcl|tex)$/);
   return("application/$1")		if ($ext =~ /(pdf|zip)$/);

   return("application/octet-stream");
}

sub contenttype2ext {
   my $contenttype=$_[0];
   my ($class, $ext, $dummy)=split(/[\/\s;,]+/, $contenttype);

   return("txt") if ($contenttype eq "N/A");
   return("mp3") if ($contenttype=~m!audio/mpeg!i);
   return("au")  if ($contenttype=~m!audio/x\-sun!i);
   return("ra")  if ($contenttype=~m!audio/x\-realaudio!i);

   $ext=~s/^x-//i;
   return(lc($ext))  if length($ext) <=4;

   return("txt") if ($class =~ /text/i);
   return("msg") if ($class =~ /message/i);

   return("doc") if ($ext =~ /msword/i);
   return("ppt") if ($ext =~ /powerpoint/i);
   return("xls") if ($ext =~ /excel/i);
   return("vsd") if ($ext =~ /visio/i);
   return("vcf") if ($ext =~ /vcard/i);
   return("tar") if ($ext =~ /tar/i);
   return("zip") if ($ext =~ /zip/i);
   return("avi") if ($ext =~ /msvideo/i);
   return("mov") if ($ext =~ /quicktime/i);
   return("swf") if ($ext =~ /shockwave-flash/i);
   return("hqx") if ($ext =~ /mac-binhex40/i);
   return("ps")  if ($ext =~ /postscript/i);
   return("js")  if ($ext =~ /javascript/i);
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
# check hidden, symboliclink, outhome symboliclink, unix specific files
sub verify_vpath {
   my ($rootpath, $vpath)=@_;

   my $realpath="$rootpath/$vpath";
   my $filename=$vpath; $filename=~s|.*/||;

   if (!$config{'webdisk_lsmailfolder'}) {
      my $vpath2=fullpath2vpath($realpath, $folderdir);
      if ($vpath2) {
         return "$lang_err{'access_denied'} ($vpath is a mailfolder file)\n";
      }
   }
   if (!$config{'webdisk_lshidden'} && $filename=~/^\./) {
      return "$lang_err{'access_denied'} ($vpath is a hidden file)\n";
   }
   if (-l $realpath) {
      if (!$config{'webdisk_lssymlink'}) {
         return "$lang_err{'access_denied'} ($vpath is a symbolic link)\n";
      }
      if (!$config{'webdisk_allow_symlinkouthome'}) {
         my $vpath2=fullpath2vpath(readlink($realpath), $homedir);
         if (!$vpath2) {
            return "$lang_err{'access_denied'} ($vpath is symbolic linked to dir/file outside homedir)\n";
         }
      }
   }
   if (!$config{'webdisk_lsunixspec'} && (-e $realpath && !-d _ && !-f _)) {
      return "$lang_err{'access_denied'} ($vpath is a unix specific file)\n";
   }
   return;
}
########################## END VERIFYVPATH ##########################

########################## EXECUTE ##############################
# Since we call open3 with @cmd array,
# perl will call execvp() directly without shell interpretation.
# this is much secure than system()
use vars qw(*cmdOUT *cmdIN *cmdERR);
sub execute {
   my @cmd=@_;
   my ($childpid, $stdout, $stderr);
   my $mypid=$$;
   $|=1;			# flush CGI related output in parent

   eval {
      $childpid = open3(\*cmdIN, \*cmdOUT, \*cmdERR, @cmd);
   };
   if ($@) {			# open3 return err only in child
      if ($$!=$mypid){ 		# child
         print STDERR $@;	# pass $@ to parent through stderr pipe
         exit 9;		# terminated
      }
   }

   while (1) {
      my ($rin, $rout, $ein, $eout, $buf)=('','','','','');
      my ($n, $o, $e)=(0,1,1);

      vec($rin, fileno(\*cmdOUT), 1) = 1;
      vec($rin, fileno(\*cmdERR), 1) = 1;
      $ein=$rin;

      $n=select($rout=$rin, undef, $eout=$ein, 30);
      last if ($n<0);	# read err => child dead?
      last if ($n==0);	# timeout

      if (vec($rout,fileno(\*cmdOUT),1)) {
         $o=sysread(\*cmdOUT, $buf, 16384);
         $stdout.=$buf if ($o>0);
      }
      if (vec($rout,fileno(\*cmdERR),1)) {
         $e=sysread(\*cmdERR, $buf, 16384);
         $stderr.=$buf if ($e>0);
      }
      last if ($n>0 && $o==0 && $e==0);
   }
   $childpid=wait();

   $|=0;
   return($stdout, $stderr, $?>>8, $?&255);
}
########################## END EXECUTE ##########################

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
       $_[0] eq "he.CP1255" || $_[0] eq "he.ISO8859-8" ) { # hebrew
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
   $year+=1900; $mon++;
   $today=sprintf("%4d%02d%02d", $year, $mon, $mday);
   $time=sprintf("%02d%02d%02d",$hour,$min, $sec);

   open(Z, ">> /tmp/openwebmail.debug");

   # unbuffer mode
   select(Z); $| = 1;
   select(STDOUT);

   print Z "$today $time ", join(" ",@msg), "\n";
   close(Z);
   chmod(0666, "/tmp/openwebmail.debug");
}

################## END LOG_TIME (for profiling) ##################

1;
