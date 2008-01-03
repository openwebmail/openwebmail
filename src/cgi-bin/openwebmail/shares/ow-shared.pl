#
# ow-shared.pl - routines shared by openwebmail*.pl
#

use strict;
use Fcntl qw(:DEFAULT :flock);

# extern vars, defined in caller openwebmail-xxx.pl
use vars qw($SCRIPT_DIR);
use vars qw($persistence_count);
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($default_logindomain $loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);
use vars qw(%lang_sizes %lang_text %lang_err);	# defined in lang/xy

# globals constants
use vars qw(%is_config_option);
use vars qw(@openwebmailrcitem);
use vars qw(%fontsize);

require "modules/htmltext.pl";

# yes no type config options
foreach (qw(
   smtpauth use_hashedmailspools use_homedirspools
   use_syshomedir create_syshomedir use_syshomedir_for_dotdir
   auth_withdomain deliver_use_gmt
   error_with_debuginfo debug_request debug_fork debug_mailfilter
   case_insensitive_login forced_ssl_login stay_ssl_afterlogin
   enable_domainselectmenu enable_strictvirtuser
   enable_changepwd enable_strictpwd
   enable_loadfrombook enable_editfrombook frombook_for_realname_only
   session_multilogin session_checksameip session_checkcookie session_count_display
   cache_userinfo
   auto_createrc domainnames_override symboliclink_mbox
   enable_webmail enable_userfolders enable_addressbook enable_spellcheck enable_advsearch
   enable_calendar enable_webdisk enable_sshterm enable_vdomain
   enable_history enable_about about_info_software about_info_protocol
   about_info_server about_info_client about_info_scriptfilename
   enable_preference enable_setforward enable_strictforward
   enable_autoreply enable_strictfoldername
   enable_stationery enable_savedraft enable_backupsent
   enable_globalfilter enable_userfilter enable_smartfilter smartfilter_bypass_goodmessage
   enable_viruscheck enable_spamcheck enable_learnspam enable_saprefs
   has_virusfolder_by_default has_spamfolder_by_default
   enable_pop3 pop3_delmail_by_default pop3_delmail_hidden pop3_usessl_by_default
   authpop3_getmail authpop3_delmail authpop3_usessl
   webdisk_readonly webdisk_lsmailfolder webdisk_lshidden webdisk_lsunixspec webdisk_lssymlink
   webdisk_allow_symlinkcreate webdisk_allow_symlinkout webdisk_allow_thumbnail
   webdisk_allow_untar webdisk_allow_unzip webdisk_allow_unrar
   webdisk_allow_unarj webdisk_allow_unace webdisk_allow_unlzh
   abook_globaleditable enable_ldap_abook
   delmail_ifquotahit delfile_ifquotahit
   default_bgrepeat default_useminisearchicon
   default_confirmmsgmovecopy default_smartdestination
   default_viewnextaftermsgmovecopy default_autopop3
   default_moveoldmsgfrominbox forced_moveoldmsgfrominbox
   default_readwithmsgcharset default_usefixedfont default_usesmileicon
   default_showhtmlastext default_showimgaslink
   default_disablejs default_disableembcode
   default_reparagraphorigmsg default_backupsentmsg default_backupsentoncurrfolder
   default_filter_badaddrformat default_filter_fakedsmtp
   default_filter_fakedfrom default_filter_fakedexecontenttype
   default_abook_defaultfilter default_abook_collapse
   default_calendar_showemptyhours default_calendar_reminderforglobal
   default_webdisk_confirmmovecopy default_webdisk_confirmdel default_webdisk_confirmcompress
   default_uselightbar default_regexmatch default_hideinternal default_categorizedfolders
)) { $is_config_option{'yesno'}{$_}=1}

# none type config options
foreach (qw(
   logfile b2g_map g2b_map lunar_map
   header_pluginfile footer_pluginfile webmail_middle_pluginfile
   allowed_serverdomain allowed_clientdomain allowed_clientip
   allowed_receiverdomain allowed_autologinip allowed_rootloginip
   localusers vdomain_mailbox_command
   ldap_abook_container
   default_realname default_bgurl
   default_abook_defaultkeyword default_abook_defaultsearchtype
   default_categorizedfolders_fs
)) { $is_config_option{'none'}{$_}=1}

# auto type config options
foreach (qw(
   auth_domain domainnames domainselectmenu_list
   default_locale default_msgformat
   default_fromemails default_autoreplysubject
   default_timeoffset default_daylightsaving default_calendar_holidaydef
)) { $is_config_option{'auto'}{$_}=1}

# list type config options
foreach (qw(
   smtpserver domainnames domainselectmenu_list spellcheck_dictionaries
   allowed_serverdomain allowed_clientdomain allowed_clientip
   allowed_receiverdomain allowed_autologinip allowed_rootloginip
   pop3_disallowed_servers localusers
   vdomain_admlist vdomain_postfix_aliases vdomain_postfix_virtual
   default_fromemails
)) { $is_config_option{'list'}{$_}=1}

# untaint path config options
foreach (qw(
    domainnames default_locale
    smtpserver auth_module virtusertable
    mailspooldir homedirspoolname homedirfolderdirname logfile
    ow_cgidir ow_htmldir ow_etcdir
    ow_stylesdir ow_langdir ow_templatesdir ow_mapsdir
    ow_sitesconfdir ow_usersconfdir ow_usersdir ow_sessionsdir
    ow_addressbooksdir
    vacationinit vacationpipe spellcheck
    global_filterbook global_calendarbook
    authpop3_server authpop3_port
    vdomain_vmpop3_pwdpath vdomain_vmpop3_pwdname vdomain_vmpop3_mailpath
    vdomain_postfix_postalias vdomain_postfix_postmap
    vdomain_postfix_aliases vdomain_postfix_virtual zonetabfile
)) { $is_config_option{'untaint'}{$_}=1}

# require type config options
foreach (qw(
   default_locale auth_module
)) { $is_config_option{'require'}{$_}=1}

# set type for DEFAULT_ options (the forced defaults for default_ options)
foreach my $opttype ('yesno', 'none', 'list') {
   foreach my $optname (keys %{$is_config_option{$opttype}}) {
      if ($optname=~s/^default_/DEFAULT_/) {
         $is_config_option{$opttype}{$optname}=1;
      }
   }
}

@openwebmailrcitem=qw(
   locale language charset timeoffset timezone daylightsaving email replyto
   style iconset bgurl bgrepeat fontsize dateformat hourformat
   ctrlposition_folderview msgsperpage fieldorder sort msgdatetype useminisearchicon
   ctrlposition_msgread headers readwithmsgcharset usefixedfont usesmileicon
   disablejs disableembcode disableemblink showhtmlastext showimgaslink sendreceipt
   confirmmsgmovecopy defaultdestination smartdestination
   viewnextaftermsgmovecopy autopop3 autopop3wait
   bgfilterthreshold bgfilterwait moveoldmsgfrominbox
   msgformat editcolumns editrows sendbuttonposition
   reparagraphorigmsg replywithorigmsg autocc backupsentmsg backupsentoncurrfolder sendcharset
   viruscheck_source viruscheck_maxsize viruscheck_minbodysize
   spamcheck_source spamcheck_maxsize spamcheck_threshold
   filter_repeatlimit filter_badaddrformat
   filter_fakedsmtp filter_fakedfrom filter_fakedexecontenttype
   abook_width abook_height abook_buttonposition
   abook_defaultfilter abook_defaultsearchtype abook_defaultkeyword
   abook_addrperpage abook_collapse abook_sort abook_listviewfieldorder
   calendar_defaultview calendar_holidaydef
   calendar_monthviewnumitems calendar_weekstart
   calendar_starthour calendar_endhour calendar_interval calendar_showemptyhours
   calendar_reminderdays calendar_reminderforglobal
   webdisk_dirnumitems webdisk_confirmmovecopy webdisk_confirmdel
   webdisk_confirmcompress webdisk_fileeditcolumns  webdisk_fileeditrows
   fscharset uselightbar regexmatch hideinternal
   categorizedfolders categorizedfolders_fs
   refreshinterval newmailsound newmailwindowtime mailsentwindowtime
   dictionary trashreserveddays spamvirusreserveddays sessiontimeout
);

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

########## CLEARVAR/ENDREQUEST/EXIT ##############################

use vars qw($_vars_used);
sub openwebmail_clearall {
   # clear opentable in filelock.pl
   ow::filelock::closeall() if (defined %ow::filelock::opentable);

   # chdir back to openwebmail cgidir
   chdir($config{'ow_cgidir'}) if ($config{'ow_cgidir'});

   # clear gobal variable for persistent perl
   undef(%SIG)		if (defined %SIG);
   undef(%config)	if (defined %config);
   undef(%config_raw)	if (defined %config_raw);
   undef($thissession)	if (defined $thissession);
   undef(%icontext)	if (defined %icontext);

   undef($default_logindomain) if (defined $default_logindomain);
   undef($loginname)	if (defined $loginname);
   undef($logindomain)	if (defined $logindomain);
   undef($loginuser)	if (defined $loginuser);

   undef($domain)	if (defined $domain);
   undef($user)		if (defined $user);
   undef($userrealname)	if (defined $userrealname);
   undef($uuid)		if (defined $uuid);
   undef($ugid)		if (defined $ugid);
   undef($homedir)	if (defined $homedir);
   undef(%prefs)	if (defined %prefs);

   undef($quotausage)	if (defined $quotausage);
   undef($quotalimit)	if (defined $quotalimit);
}

# routine used at CGI request begin
sub openwebmail_requestbegin {
   # init euid/egid to nobody to drop uid www as early as possible
   if ($>==0) { $<=65534; $(=65534; $)="65534 65534"; }

   # ow::tool::zombie_cleaner();			# clear pending zombies
   openwebmail_clearall() if ($_vars_used);	# clear global
   $_vars_used=1;
   $SIG{PIPE}=\&openwebmail_exit;		# for user stop
   $SIG{TERM}=\&openwebmail_exit;		# for user stop
}

# routine used at CGI request end
sub openwebmail_requestend {
   ow::tool::zombie_cleaner();			# clear pending zombies
   openwebmail_clearall() if ($_vars_used);	# clear global
   $_vars_used=0;
   $persistence_count++;

   # back euid to root if possible, required for setuid under persistent perl
   $>=0; if ($>==0) { $<=65534; $(=65534; $)="65534 65534"; }
}

# routine used at exit
sub openwebmail_exit {
   openwebmail_requestend();
   exit $_[0];
}

########## END CLEARVAR/ENDREQUEST/EXIT ##########################

########## USERENV_INIT ##########################################
# init user globals, switch euid
sub userenv_init {
   load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
   read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if (-f "$SCRIPT_DIR/etc/openwebmail.conf");

   # so %lang... can be displayed with right charset in error msg
   loadlang($config{'default_locale'});

   if ($config{'smtpauth'}) {	# load smtp auth user/pass
      read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/smtpauth.conf");
      if ($config{'smtpauth_username'} eq "" || $config{'smtpauth_password'} eq "") {
         openwebmailerror(__FILE__, __LINE__, "$SCRIPT_DIR/etc/smtpauth.conf $lang_err{'param_fmterr'}");
      }
   }

   if (!defined param('sessionid') ) {
      # delayed response for non localhost
      sleep $config{'loginerrordelay'} if (ow::tool::clientip() ne "127.0.0.1");
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'param_fmterr'}, $lang_err{'access_denied'}");
   }
   $thissession = param('sessionid')||'';
   $thissession =~ s!\.\.+!!g;  # remove ..

   # sessionid format: loginname+domain-session-0.xxxxxxxxxx
   if ($thissession =~ /^([\w\.\-\%\@]+)\*([\w\.\-]*)\-session\-(0\.\d+)$/) {
      local $1; 				# fix perl $1 taintness propagation bug
      $thissession = $1."*".$2."-session-".$3;	# untaint
      ($loginname, $default_logindomain)=($1, $2); # param from sessionid
   } else {
      openwebmailerror(__FILE__, __LINE__, "Session ID $thissession $lang_err{'has_illegal_chars'}");
   }

   ($logindomain, $loginuser)=login_name2domainuser($loginname, $default_logindomain);

   if (!is_localuser("$loginuser\@$logindomain") &&  -f "$config{'ow_sitesconfdir'}/$logindomain") {
      read_owconf(\%config, \%config_raw, "$config{'ow_sitesconfdir'}/$logindomain");
   }
   if ( $>!=0 &&	# setuid is required if spool is located in system dir
       ($config{'mailspooldir'} eq "/var/mail" ||
        $config{'mailspooldir'} eq "/var/spool/mail")) {
      print "Content-type: text/html\n\n'$0' must setuid to root"; openwebmail_exit(0);
   }
   ow::auth::load($config{'auth_module'});

   $user='';
   # try userinfo cached in session file first
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
	=split(/\@\@\@/, (sessioninfo($thissession))[2]) if ($config{'cache_userinfo'});
   # use userinfo from auth server if user is root or null
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
	=get_domain_user_userinfo($logindomain, $loginuser) if ($user eq '' || $uuid==0 || $ugid=~/\b0\b/);

   if ($user eq "") {
      sleep $config{'loginerrordelay'};	# delayed response
      openwebmailerror(__FILE__, __LINE__, "$loginuser@$logindomain $lang_err{'user_not_exist'}!");
   }

   if (!matchlist_fromhead('allowed_rootloginip', ow::tool::clientip())) {
      if ($user eq 'root' || $uuid==0) {
         sleep $config{'loginerrordelay'};	# delayed response
         writelog("userinfo error - possible root hacking attempt");
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'norootlogin'}");
      }
   }

   # load user config
   my $userconf="$config{'ow_usersconfdir'}/$user";
   $userconf="$config{'ow_usersconfdir'}/$domain/$user" if ($config{'auth_withdomain'});
   read_owconf(\%config, \%config_raw, "$userconf") if ( -f "$userconf");

   # override auto guessing domainanmes if loginname has domain or domainselectmenu enabled
   if (${$config_raw{'domainnames'}}[0] eq 'auto' &&
       ($loginname=~/\@/ || $config{'enable_domainselectmenu'})) {
      $config{'domainnames'}=[ $logindomain ];
   }
   # override realname if defined in config
   if ($config{'default_realname'} ne 'auto') {
      $userrealname=$config{'default_realname'}
   }

   if ( !$config{'use_syshomedir'} ) {
      $homedir = "$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/$user":$user);
   }

   $user=ow::tool::untaint($user);
   $uuid=ow::tool::untaint($uuid);
   $ugid=ow::tool::untaint($ugid);
   $homedir=ow::tool::untaint($homedir);

   umask(0077);
   if ( $>==0 ) {			# switch to uuid:mailgid if script is setuid root.
      my $mailgid=getgrnam('mail');	# for better compatibility with other mail progs
      ow::suid::set_euid_egids($uuid, $ugid, $mailgid);
      if ( $)!~/\b$mailgid\b/) { # group mail doesn't exist?
         openwebmailerror(__FILE__, __LINE__, "Set effective gid to mail($mailgid) failed!");
      }
   }

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   loadlang($prefs{'locale'});
   charset((ow::lang::localeinfo($prefs{'locale'}))[6]) if ($CGI::VERSION>=2.58); # setup charset of CGI module

   verifysession();

   if ($prefs{'iconset'}=~ /^Text\./) {
      ($prefs{'iconset'} =~ /^([\w\d\.\-_]+)$/) && ($prefs{'iconset'} = $1);
      my $icontext=ow::tool::untaint("$config{'ow_htmldir'}/images/iconsets/$prefs{'iconset'}/icontext");
      delete $INC{$icontext};
      require $icontext;
   }

   if ($config{'quota_module'} ne "none") {
      ow::quota::load($config{'quota_module'});

      my ($ret, $errmsg);
      ($ret, $errmsg, $quotausage, $quotalimit)=ow::quota::get_usage_limit(\%config, $user, $homedir, 0);
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

   # set env for external programs
   $ENV{'HOME'}=$homedir;
   $ENV{'USER'}=$ENV{'LOGNAME'}=$user;
   chdir($homedir);

   return;
}
########## END USERENV_INIT ######################################

########## LOGINNAME 2 LOGINDOMAIN LOGINUSER #####################
sub login_name2domainuser {
   my ($loginname, $default_logindomain)=@_;
   my ($logindomain, $loginuser);
   if ($loginname=~/^(.+)\@(.+)$/) {
      ($loginuser, $logindomain)=($1, $2);
   } else {
      $loginuser=$loginname;
      $logindomain=$default_logindomain||$ENV{'HTTP_HOST'}||ow::tool::hostname();
      $logindomain=~s/:\d+$//;	# remove port number
   }
   $loginuser=lc($loginuser) if ($config{'case_insensitive_login'});
   $logindomain=lc(safedomainname($logindomain));
   $logindomain=$config{'domainname_equiv'}{'map'}{$logindomain} if (defined $config{'domainname_equiv'}{'map'}{$logindomain});
   return($logindomain, $loginuser);
}
########## END LOGINNAME 2 LOGINDOMAIN LOGINUSER #################

########## READCONF ##############################################
# read openwebmail.conf into a hash with %symbol% resolved
# the hash is 'called by reference' since we want to do 'untaint' on it
sub read_owconf {
   my ($r_config, $r_config_raw, $configfile)=@_;
   my ($key, $value)=("", "");

   # load up the config file if we have one
   load_owconf($r_config_raw, $configfile) if ($configfile);

   # make sure there are default values for array/hash references!!
   if (!defined ${$r_config_raw}{'domainname_equiv'}){
      ${$r_config_raw}{'domainname_equiv'}= { 'map'=>{}, 'list'=>{} };
   }
   foreach $key (keys %{$is_config_option{'list'}}) {
      if (!defined ${$r_config_raw}{$key} && $key!~/^DEFAULT_/) {
         ${$r_config_raw}{$key}=[];
      }
      # NOTE: We don't set defualt value for DEFAULT_ options, or the default_ options will be overriden.
      #       DEFAULT_ options should be set only if they appear in config file
   }

   # copy config_raw to config
   %{$r_config}=%{$r_config_raw};

   # resolve %var% in hash config
   # note, no substitutions to domainname_equiv or yes/no items
   # should the exclusion include other types??
   foreach $key (keys %{$r_config}) {
      next if ($key eq 'domainname_equiv' or $is_config_option{'yesno'}{$key});
      if ( $is_config_option{'list'}{$key} ) {
         foreach ( @{${$r_config}{$key}} ) {
            $_ = fmt_subvars($key, $_, $r_config, $configfile);
         }
      } else {
         ${$r_config}{$key} = fmt_subvars($key, ${$r_config}{$key}, $r_config, $configfile);
      }
   }

   # cleanup auto values with server or client side runtime enviroment
   # since result may differ for different clients, this couldn't be done in load_owconf()
   foreach $key ( keys %{$is_config_option{'auto'}} ) {
      if ($is_config_option{'list'}{$key}) {
         next if (${${$r_config}{$key}}[0] ne 'auto');
         if ($key eq 'domainnames') {
            if ($ENV{'HTTP_HOST'}=~/[A-Za-z]\./) {
               $value=$ENV{'HTTP_HOST'};
               $value=~s/:\d+$//;	# remove port number
            } else {
               $value=ow::tool::hostname();
            }
            ${$r_config}{$key}=[$value];
         }
      } else {
         next if (${$r_config}{$key} ne 'auto');
         if ($key eq 'default_timeoffset') {
            ${$r_config}{$key}=ow::datetime::gettimeoffset();
         } elsif ($key eq 'default_locale') {
            ${$r_config}{$key}=ow::lang::guess_browser_locale(available_locales());
         }
      }
   }
   # set options that refer to other options
   ${$r_config}{'default_bgurl'}="${$r_config}{'ow_htmlurl'}/images/backgrounds/Transparent.gif" if ( ${$r_config}{'default_bgurl'} eq '' );
   ${$r_config}{'default_abook_defaultsearchtype'}="name" if ( ${$r_config}{'default_abook_defaultsearchtype'} eq '' );
   ${$r_config}{'domainselectmenu_list'}=${$r_config}{'domainnames'} if ( ${${$r_config}{'domainselectmenu_list'}}[0] eq 'auto' );

   # untaint pathname variable defined in openwebmail.conf
   foreach $key ( keys %{$is_config_option{'untaint'}} ) {
      if ( $is_config_option{'list'}{$key} ) {
         foreach ( @{${$r_config}{$key}} ) {
            $_=ow::tool::untaint($_);
         }
      } else {
         ${$r_config}{$key} =ow::tool::untaint(${$r_config}{$key});
      }
   }

   # add system wide vars to minimize disk access lookups
   $r_config->{available_locales} = available_locales();

   return;
}

# load ow conf file and merge with an existing hash
use vars qw(%_rawconfcache);
sub load_owconf {
   my ($r_config_raw, $configfile)=@_;

   my $t=0; $t=(-M $configfile) if ($configfile!~/openwebmail\.conf\.default$/);
   if (!defined $_rawconfcache{$configfile}{'t'} ||
       $_rawconfcache{$configfile}{'t'} ne $t ) {
      $_rawconfcache{$configfile}{'t'}=$t;
      $_rawconfcache{$configfile}{'c'}=_load_owconf($configfile);
   }

   foreach (keys %{$_rawconfcache{$configfile}{'c'}}) {
      ${$r_config_raw}{$_}=${$_rawconfcache{$configfile}{'c'}}{$_};
      # remove DEFAULT_ restriction when default_ is overridden
      delete ${$r_config_raw}{'DEFAULT_'.$1} if (/^default_(.*)/);
   }
   return;
}

# load ow conf file into a new hash, return ref of the new hash
# so the hash can be cached to speedup later access
sub _load_owconf {
   my $configfile=$_[0];
   if ($configfile=~/\.\./) {	# .. in path is not allowed for higher security
      openwebmailerror(__FILE__, __LINE__, "Invalid config file path $configfile!");
   }

   my (%conf, $key, $value);
   my ($ret, $err)=ow::tool::load_configfile($configfile, \%conf);
   if ($ret<0) {
      openwebmailerror(__FILE__, __LINE__, "Couldn't open config file $configfile! ($err)");
   }

   # data stru/value formatting
   foreach $key (keys %conf) {
      # the option lookup key should be all lowercase so that DEFAULT_
      # options get handled the same as default_ options without having
      # to specify DEFAULT_option_name in the is_config_option hash
      my $lckey = lc($key);
      # turn ow_htmlurl from / to null to avoid // in url
      $conf{$key}='' if ($key eq 'ow_htmlurl' and $conf{$key} eq '/');
      # set exact 'auto'
      $conf{$key}='auto' if ($is_config_option{'auto'}{$key} && $conf{$key}=~/^auto$/i);
      # clean up yes/no params
      $conf{$key}=fmt_yesno($conf{$key}) if ($is_config_option{'yesno'}{$lckey});
      # remove / and .. from variables that will be used in require statement for security
      $conf{$key}=fmt_require($conf{$key}) if ($is_config_option{'require'}{$lckey});
      # clean up none
      $conf{$key}=fmt_none($conf{$key}) if ($is_config_option{'none'}{$lckey});

      # format hash or list data stru
      if ($key eq 'domainname_equiv') {
         my %equiv=();
         my %equivlist=();
         foreach (split(/\n/, $conf{$key})) {
            s/^[:,\s]+//; s/[:,\s]+$//;
            my ($dst, @srclist)=split(/[:,\s]+/);
            $equivlist{$dst}=\@srclist;
            foreach my $src (@srclist) {
               $equiv{$src}=$dst if ($src && $dst);
            }
         }
         $conf{$key}= { map => \%equiv,		# src -> dst
                        list=> \%equivlist };	# dst <= srclist
      } elsif ($key eq 'revision') {
         # convert the SVN revision to only a number
         $conf{$key} =~ s#[^\d]+##g;
      } elsif ($is_config_option{'list'}{$lckey}){
         $value=$conf{$key}; $value=~s/\s//g;
         my @list=split(/,+/, $value);
         $conf{$key}=\@list;
      }
   }

   return \%conf;
}

# substitute %var% values
# Important: Don't mess with $_ in here!
sub fmt_subvars {
   my ($key, $value, $r_config, $configfile)=@_;

   my $iterate = 5;
   while ($iterate and $value =~ s/\%([\w\d_]+)\%/${$r_config}{$1}/msg) {
      $iterate--;
   }
   openwebmailerror(__FILE__, __LINE__, "Too recursive config file \%var\% expansion, $key $configfile!") if ($iterate == 0);
   return $value;
}
sub fmt_yesno {	# translate yes/no text into 1/0  (true/false)
   return 1 if ($_[0]=~/y(es)?/i || $_[0] eq '1');
   return 0;
}
sub fmt_none {	# blank out a 'none' value
   return '' if ( $_[0]=~/^(none|""|'')$/i );
   return $_[0];
}
sub fmt_require { # remove / and .. for variables used in require statement for security
   $_=$_[0]; s!(/|\.\.)!!g;
   return $_;
}
########## END READCONF ##########################################

########## MATCHLIST_... #########################################
sub matchlist_all {
   my ($listname)=@_;
   return 1 if (!defined $config{$listname});

   foreach my $token (@{$config{$listname}}) {
      return 1 if (lc($token) eq 'all');
   }
   return 0;
}

sub matchlist_exact {
   my ($listname, $value)=($_[0], lc($_[1]));
   return 1 if (!defined $config{$listname});

   foreach (@{$config{$listname}}) {
      my $token=lc($_);
      return 1 if ($token eq 'all' || $token eq $value);
   }
   return 0;
}

sub matchlist_fromhead {
   my ($listname, $value)=($_[0], lc($_[1]));
   return 1 if (!defined $config{$listname});

   foreach (@{$config{$listname}}) {
      my $token=lc($_);
      return 1 if ($token eq 'all' || $value=~/^\Q$token\E/);
   }
   return 0;
}

sub matchlist_fromtail {
   my ($listname, $value)=($_[0], lc($_[1]));
   return 1 if (!defined $config{$listname});

   foreach (@{$config{$listname}}) {
      my $token=lc($_);
      return 1 if ($token eq 'all' || $value=~/\Q$token\E$/);
   }
   return 0;
}
########## END MATCHLIST_... #####################################

################### AVAILABLE LOCALES ##########################
sub available_locales {
   my $available_locales;
   opendir(LANGDIR, "$config{ow_langdir}") or
     openwebmailerror(__FILE__, __LINE__, "Cannot read $config{ow_langdir}! ($!)");
   $available_locales->{$_}++ for grep { !m/^\.+/ && !m#[/\\]# && -f "$config{ow_langdir}/$_" } readdir(LANGDIR);
   closedir(LANGDIR) or
     openwebmailerror(__FILE__, __LINE__, "Cannot close $config{ow_langdir}! ($!)");
   return $available_locales;
}
################# END AVAILABLE LOCALES ########################

########## LOADLANG ##############################################
sub loadlang {
   my $locale = $_[0];
   ow::tool::loadmodule("main", $config{'ow_langdir'}, $locale, ()); # null list, load all symbols
}
########## END LOADLANG ##########################################

########## READPREFS #############################################
sub readprefs {
   my (%prefshash, $key, $value);
   my $rcfile=dotpath('openwebmailrc');

   # read .openwebmailrc
   # ps: prefs entries are kept as pure strings to make the following things easier
   #     1. copy default from $config{default...}
   #     2. store prefs value back to openwebmailrc file
   if ( -f $rcfile ) {
      sysopen(RC, $rcfile, O_RDONLY) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $rcfile! ($!)");
      while (<RC>) {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         if ($key eq 'style') {
            $value =~ s/^\.//g;  ## In case someone gets a bright idea...
         }
         $prefshash{$key} = $value;
      }
      close(RC);
   }

   # read .signature
   my $signaturefile=dotpath('signature');
   if ( !-f $signaturefile &&  -f "$homedir/.signature" ) {
      $signaturefile="$homedir/.signature";
   }
   if (-f $signaturefile) {
      $prefshash{"signature"} = '';
      sysopen(SIGNATURE, $signaturefile, O_RDONLY) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $signaturefile! ($!)");
      while (<SIGNATURE>) {
         $prefshash{"signature"} .= $_;
      }
      close(SIGNATURE);
   }
   $prefshash{"signature"}=~s/\s+$/\n/;

   # get default value from config for err/undefined/empty prefs entries

   # validate email with defaultemails if frombook is limited to change realname only
   if ($config{'frombook_for_realname_only'} || $prefshash{'email'} eq "") {
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
      if (defined $config{'DEFAULT_'.$key}) {
         $prefshash{$key}=$config{'DEFAULT_'.$key};
      } elsif ((!defined $prefshash{$key}||$prefshash{$key} eq '') &&
               defined $config{'default_'.$key} ) {
         $prefshash{$key}=$config{'default_'.$key};
      }
   }
   # signature allowed to be empty but not undefined
   foreach $key ( 'signature') {
      if (defined $config{'DEFAULT_'.$key}) {
         $prefshash{$key}=$config{'DEFAULT_'.$key};
      } elsif (!defined $prefshash{$key} &&
               defined $config{'default_'.$key} ) {
         $prefshash{$key}=$config{'default_'.$key};
      }
   }

   # remove / and .. from variables that will be used in require statement for security
   $prefshash{'locale'}=~s|/||g; $prefshash{'locale'}=~s|\.\.||g;
   $prefshash{'iconset'}=~s|/||g;  $prefshash{'iconset'}=~s|\.\.||g;

   # adjust bgurl in case the OWM has been reinstalled in different place
   if ( $prefshash{'bgurl'}=~m!^(/.+)/images/backgrounds/(.*)$! &&
        $1 ne $config{'ow_htmlurl'} &&
        -f "$config{'ow_htmldir'}/images/backgrounds/$2") {
      $prefshash{'bgurl'}="$config{'ow_htmlurl'}/images/backgrounds/$2";
   }

   # entries related to ondisk dir or file
   $prefshash{'locale'}=$config{'default_locale'} if (!-f "$config{'ow_langdir'}/$prefshash{'locale'}");
   $prefshash{'style'}=$config{'default_style'} if (!-f "$config{'ow_stylesdir'}/$prefshash{'style'}");
   $prefshash{'iconset'}=$config{'default_iconset'} if (!-d "$config{'ow_htmldir'}/images/iconsets/$prefshash{'iconset'}");

   $prefshash{'refreshinterval'}=$config{'min_refreshinterval'} if ($prefshash{'refreshinterval'} < $config{'min_refreshinterval'});

   # rentries related to spamcheck or viruscheck limit
   $prefshash{'viruscheck_source'}='pop3' if ($prefshash{'viruscheck_source'} eq 'all' && $config{'viruscheck_source_allowed'} eq 'pop3');
   $prefshash{'spamcheck_source'}='pop3' if ($prefshash{'spamcheck_source'} eq 'all' && $config{'spamcheck_source_allowed'} eq 'pop3');
   $prefshash{'viruscheck_maxsize'}=$config{'viruscheck_maxsize_allowed'} if ($prefshash{'viruscheck_maxsize'} > $config{'viruscheck_maxsize_allowed'});
   $prefshash{'spamcheck_maxsize'}=$config{'spamcheck_maxsize_allowed'} if ($prefshash{'spamcheck_maxsize'} > $config{'spamcheck_maxsize_allowed'});

   # rentries related to addressbook
   $prefshash{'abook_listviewfieldorder'}=$config{'default_abook_listviewfieldorder'} if ($prefshash{'abook_listviewfieldorder'}!~/(fullname|prefix|first|middle|last|suffix|email)/);
   return %prefshash;
}
########## END READPREFS #########################################

########## READTEMPLATE ##########################################
use vars qw(%_templatecache);
sub readtemplate {
   my ($templatename, $locale)=@_;
   $locale = $prefs{'locale'} if ($locale eq '');

   my $langfile="$config{'ow_templatesdir'}/$locale/$templatename";
   my $commonfile="$config{'ow_templatesdir'}/COMMON/$templatename";

   foreach my $file ($langfile, $commonfile) {
      return $_templatecache{$file} if (defined $_templatecache{$file});
   }
   foreach my $file ($langfile, $commonfile) {
      if (sysopen(T, $file, O_RDONLY)) {
         local $/; undef $/; $_templatecache{$file}=<T>; # read whole file in once
         close(T);
         return $_templatecache{$file};
      }
   }
   openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_templatesdir'}/$locale/$templatename! ($!)");
}
########## END READTEMPLATE ######################################

########## READSTYLE #############################################
# this routine must be called after readprefs
# since it references $prefs{'bgurl'} & prefs{'bgrepeat'}
use vars qw(%_stylecache);
sub readstyle {
   my $stylefile = $_[0] || 'Default';
   $stylefile = 'Default' if (!-f "$config{'ow_stylesdir'}/$stylefile");

   if (!defined $_stylecache{"$config{'ow_stylesdir'}/$stylefile"}) {
      my (%hash, $key, $value);
      sysopen(STYLE, "$config{'ow_stylesdir'}/$stylefile", O_RDONLY) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_stylesdir'}/$stylefile! ($!)");
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
      close(STYLE);
      $_stylecache{"$config{'ow_stylesdir'}/$stylefile"}=\%hash;
   }

   my %stylehash=%{$_stylecache{"$config{'ow_stylesdir'}/$stylefile"}};	# copied from style cache

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
########## END READSTYLE #########################################

########## APPLYSTYLE ############################################
sub applystyle {
   my $template = shift;

   $template =~ s/\@\@\@NAME\@\@\@/$config{'name'}/g;
   $template =~ s/\@\@\@VERSION\@\@\@/$config{'version'}/g;
   $template =~ s/\@\@\@LOGO_URL\@\@\@/$config{'logo_url'}/g;
   $template =~ s/\@\@\@LOGO_LINK\@\@\@/$config{'logo_link'}/g;
   $template =~ s/\@\@\@PAGE_FOOTER\@\@\@/$config{'page_footer'}/g;
   $template =~ s/\@\@\@SESSIONID\@\@\@/$thissession/g;

   my $url;
   my $helpdir = "$config{'ow_htmldir'}/help";
   my $helpurl = "$config{'ow_htmlurl'}/help";
   if ( -d "$helpdir/$prefs{'locale'}" ) {
      # choose help in the correct locale if available
      $url = "$helpurl/$prefs{'locale'}";
   } else {
      # choose help in the correct language if available
      my $language = substr($prefs{'locale'}, 0, 2);

      my $firstmatch = undef;
      if (-d "$helpdir") {
         opendir(HELPDIR, "$helpdir") or
           openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} ".f2u($helpdir)."! ($!)");
         $firstmatch = (map { "$helpurl/$_" } grep { !m/^\.+/ && m/^$language/ } readdir(HELPDIR))[0] || undef;
         closedir(HELPDIR) or
           openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} ".f2u($helpdir)."! ($!)");
      }


      $url = $firstmatch || "$helpurl/en_US.ISO8859-1"; # or default to en_US.ISO8859-1
   }
   $template =~ s#\@\@\@HELP_URL\@\@\@#$url/index.html#g;
   $template =~ s/\@\@\@HELP_TEXT\@\@\@/$lang_text{'help'}/g;

   $url=$config{'start_url'};
   if (cookie("ow-ssl")) {	# backto SSL
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
########## END APPLYSTYLE ########################################

########## VERIFYSESSION #########################################
sub verifysession {
   my $now=time();
   my $sessionfile=ow::tool::untaint("$config{'ow_sessionsdir'}/$thissession");
   my $modifyage=$now-(stat($sessionfile))[9];
   if ( $modifyage > $prefs{'sessiontimeout'}*60) {
      unlink ( $sessionfile) if ( -e  $sessionfile);

      my $html = applystyle(readtemplate("sessiontimeout.template"));
      httpprint([], [htmlheader(), $html, htmlfooter(1)]);

      writelog("session error - session $thissession timeout access attempt");
      writehistory("session error - session $thissession timeout access attempt");

      openwebmail_exit(0);
   }

   my $client_sessionkey=cookie("ow-sessionkey-$domain-$user");

   my ($sessionkey, $ip, $userinfo)=sessioninfo($thissession);
   if ( $config{'session_checkcookie'} &&
        $client_sessionkey ne $sessionkey ) {
      writelog("session error - request doesn't have proper cookie, access denied!");
      writehistory("session error - request doesn't have proper cookie, access denied !");
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'sess_cookieerr'}");
   }
   if ( $config{'session_checksameip'} &&
        ow::tool::clientip() ne $ip) {
      writelog("session error - request doesn't come from the same ip, access denied!");
      writehistory("session error - request doesn't com from the same ip, access denied !");
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'sess_iperr'}");
   }

   # no_update is set to 1 if auto-refresh/timeoutwarning
   my $session_noupdate=param('session_noupdate')||0;
   if (!$session_noupdate) {
      # update the session timestamp with now-1,
      # the -1 is for nfs, utime is actually the nfs rpc setattr()
      # since nfs server current time will be used if setattr() is issued with nfs client's current time.
      utime ($now-1, $now-1,  $sessionfile) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'}  $sessionfile! ($!)");
   }
   return 1;
}

sub sessioninfo {
   my $sessionid=$_[0];
   my ($sessionkey, $ip, $userinfo);

   openwebmailerror(__FILE__, __LINE__, ow::htmltext::str2html("Session ID $sessionid $lang_err{'doesnt_exist'}") . qq|&nbsp;<a href="$config{'ow_cgiurl'}/openwebmail.pl">$lang_text{'loginagain'}?</a>|, "passthrough") unless
      (-e "$config{'ow_sessionsdir'}/$sessionid");

   if ( !sysopen(F, "$config{'ow_sessionsdir'}/$sessionid", O_RDONLY) ) {
      writelog("session error - couldn't open $config{'ow_sessionsdir'}/$sessionid ($@)");
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_sessionsdir'}/$sessionid");
   }
   $sessionkey= <F>; chomp $sessionkey;
   $ip= <F>; chomp $ip;
   $userinfo = <F>; chomp $userinfo;
   close(F);

   return($sessionkey, $ip, $userinfo);
}
########## END VERIFYSESSION #####################################

########## VIRTUALUSER related ###################################
# update index db of virtusertable
sub update_virtuserdb {
   my (%DB, %DBR, $metainfo);

   # convert file name and path into a simple file name
   my $virtname=$config{'virtusertable'};
   $virtname=~s!/!.!g;  # remove slashes
   $virtname=~s/^\.+//; # remove leading dots
   my $virtdb=ow::tool::untaint(("$config{'ow_mapsdir'}/$virtname"));

   if (! -e $config{'virtusertable'}) {
      ow::dbm::unlink($virtdb) if (ow::dbm::exist($virtdb));
      ow::dbm::unlink("$virtdb.rev") if (ow::dbm::exist("$virtdb.rev"));
      return;
   }

   $metainfo=ow::tool::metainfo($config{'virtusertable'});

   if (ow::dbm::exist($virtdb)) {
      ow::dbm::open(\%DB, $virtdb, LOCK_SH) or return;
      my $dbmetainfo=$DB{'METAINFO'};
      ow::dbm::close(\%DB, $virtdb);
      return if ( $dbmetainfo eq $metainfo );
   }

   writelog("update $virtdb");

   ow::dbm::open(\%DB, $virtdb, LOCK_EX, 0644) or return;
   my $ret=ow::dbm::open(\%DBR, "$virtdb.rev", LOCK_EX, 0644);
   if (!$ret) {
      ow::dbm::close(\%DB, $virtdb);
      return;
   }
   %DB=();	# ensure the virdb is empty
   %DBR=();

   # parse the virtusertable
   sysopen(VIRT, $config{'virtusertable'}, O_RDONLY);
   while (<VIRT>) {
      s/^\s+//;                         # remove leading whitespace
      s/\s+$//;                         # remove trailing whitespace
      s/#.*$//;                         # remove comment lines
      s/(.*?)\@(.*?)%1/$1\@$2$1/;       # resolve %1 in virtusertable
                                        # user@domain.com     %1@example.com

      my ($vu, $u)=split(/[\s\t]+/);
      next if ($vu eq "" || $u eq "");
      next if ($vu =~ /^@/);            # ignore entries for whole domain mapping

      $DB{$vu}=$u;
      if (defined $DBR{$u}) {
         $DBR{$u}.=",$vu";
      } else {
         $DBR{$u}.="$vu";
      }
   }
   close(VIRT);

   $DB{'METAINFO'}=$metainfo;

   ow::dbm::close(\%DBR, "$virtdb.rev");
   ow::dbm::close(\%DB, $virtdb);
   ow::dbm::chmod(0644, $virtdb, "$virtdb.rev");
   return;
}

sub get_user_by_virtualuser {
   my %DB=();
   my $u='';

   # convert file name and path into a simple file name
   my $virtname=$config{'virtusertable'}; $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   my $virtdb=ow::tool::untaint(("$config{'ow_mapsdir'}/$virtname"));

   if (ow::dbm::exist($virtdb)) {
      ow::dbm::open(\%DB, $virtdb, LOCK_SH) or return $u;
      $u=$DB{$_[0]};	# $_[0] is virtualuser
      ow::dbm::close(\%DB, $virtdb);
   }
   return($u);
}

sub get_virtualuser_by_user {
   my %DBR=();
   my $vu='';

   # convert file name and path into a simple file name
   my $virtname=$config{'virtusertable'}; $virtname=~s!/!.!g; $virtname=~s/^\.+//;
   my $virtdbr=ow::tool::untaint(("$config{'ow_mapsdir'}/$virtname.rev"));

   if (ow::dbm::exist($virtdbr)) {
      ow::dbm::open(\%DBR, $virtdbr, LOCK_SH) or return $vu;
      $vu=$DBR{$_[0]};	# $_[0] is user
      ow::dbm::close(\%DBR, $virtdbr);
   }
   return($vu);
}

sub get_domain_user_userinfo {
   my ($logindomain, $loginuser)=@_;
   my ($domain, $user, $realname, $uid, $gid, $homedir);

   $user=get_user_by_virtualuser($loginuser);
   if ($user eq "") {
      my @domainlist=($logindomain);
      if (defined @{$config{'domain_equiv'}{'list'}{$logindomain}}) {
         push(@domainlist, @{$config{'domain_equiv'}{'list'}{$logindomain}});
      }
      foreach (@domainlist) {
         $user=get_user_by_virtualuser("$loginuser\@$_");
         last if ($user ne '');
      }
   }

   if ($user=~/^(.*)\@(.*)$/) {
      ($user, $domain)=($1, lc($2));
   } else {
      if ($user eq '') {
         if ($config{'enable_strictvirtuser'}) {
            # if the loginuser is mapped in virtusertable by any vuser,
            # then one of the vuser should be used instead of loginname for login
            my $vu=get_virtualuser_by_user($loginuser);
            return("", "", "", "", "", "") if ($vu ne '');
         }
         $user=$loginuser;
      }
      if ($config{'auth_domain'} ne 'auto') {
         $domain=lc($config{'auth_domain'});
      } else {
         $domain=$logindomain;
      }
   }

   my ($errcode, $errmsg);
   if ($config{'auth_withdomain'}) {
      ($errcode, $errmsg, $realname, $uid, $gid, $homedir)=ow::auth::get_userinfo(\%config, "$user\@$domain");
   } else {
      ($errcode, $errmsg, $realname, $uid, $gid, $homedir)=ow::auth::get_userinfo(\%config, $user);
   }
   writelog("userinfo error - $config{'auth_module'}, ret $errcode, $errmsg") if ($errcode!=0);

   $realname=$loginuser if ($realname eq "");
   if ($uid ne "") {
      return($domain, $user, $realname, $uid, $gid, $homedir);
   } else {
      return("", "", "", "", "", "");
   }
}
########## END VIRTUALUSER related ###############################

########## GET_DEFAULTEMAILS, GET_USERFROM #######################
sub get_defaultemails {
   my ($logindomain, $loginuser, $user)=@_;
   return (@{$config{'default_fromemails'}}) if (${$config{'default_fromemails'}}[0] ne 'auto');

   my %emails=();
   my @defaultdomains=@{$config{'domainnames'}};

   my $vu=get_virtualuser_by_user($user);
   if ($vu ne "") {
      foreach my $name (ow::tool::str2list($vu,0)) {
         if ($name=~/^(.*)\@(.*)$/) {
            next if ($1 eq "");	# skip whole @domain mapping
            if ($config{'domainnames_override'}) {	# override the domainname found in virtual table
               my $purename=$1;
               foreach my $host (@defaultdomains) {
                  $emails{"$purename\@$host"}=1;
               }
            } else {
               $emails{$name}=1;
            }
         } else {
            foreach my $host (@defaultdomains) {
               $emails{"$name\@$host"}=1;
            }
         }
      }
   } else {
      foreach my $host (@defaultdomains) {
         $emails{"$loginuser\@$host"}=1;
      }
   }

   return(keys %emails);
}

sub get_userfrom {
   my ($logindomain, $loginuser, $user, $realname, $frombook)=@_;
   my %from=();
   $realname=$config{'DEFAULT_realname'} if (defined $config{'DEFAULT_realname'});

   # get default fromemail
   my @defaultemails=get_defaultemails($logindomain, $loginuser, $user);
   foreach (@defaultemails) {
      $from{$_}=$realname;
   }

   # get user defined fromemail
   if ($config{'enable_loadfrombook'} && sysopen(FROMBOOK, $frombook, O_RDONLY)) {
      while (<FROMBOOK>) {
         my ($_email, $_realname) = split(/\@\@\@/, $_, 2); chomp($_realname);
         $_realname=$config{'DEFAULT_realname'} if (defined $config{'DEFAULT_realname'});
         if (!$config{'frombook_for_realname_only'} || defined $from{$_email}) {
             $from{"$_email"} = $_realname;
         }
      }
      close(FROMBOOK);
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
      push(@result, $email[$i]) if ($email[$i] ne '');
   }

   return(@result);
}
########## END GET_DEFAULTEMAILS GET_USERFROM ####################

########## HTTPPRINT/HTMLHEADER/HTMLFOOTER #######################
sub is_http_compression_enabled {
   if (cookie("ow-httpcompress") &&
       $ENV{'HTTP_ACCEPT_ENCODING'}=~/\bgzip\b/ &&
       ow::tool::has_module('Compress/Zlib.pm')) {
      return 1;
   } else {
      return 0;
   }
}

sub httpprint {
   my ($r_headers, $r_htmls)=@_;
   if (is_http_compression_enabled()) {
      my $zhtml=Compress::Zlib::memGzip(join('',@{$r_htmls}));
      if ($zhtml ne '') {
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
   $headers{'-charset'} = $prefs{'charset'} if ($CGI::VERSION>=2.57);
   if (!defined $headers{'-Cache-Control'} &&
       !defined $headers{'-Expires'} ) {
      $headers{'-Pragma'}='no-cache';
      $headers{'-Cache-Control'}='no-cache,no-store';
   }
   return (header(%headers));
}

sub htmlheader {
   my $extra_info = $_[0]; # any message in titlebar

   my $html = applystyle(readtemplate("header.template"));
   $html =~ s/\@\@\@DIRECTIVE\@\@\@/$_[0]/g;	# $_[0] is optional html directive

   my $mode;
   $mode.='+' if ($persistence_count>0);
   $mode.='z' if (is_http_compression_enabled());
   $mode="($mode)" if ($mode);

   my $charset = $prefs{'charset'};

   $html =~ s/\@\@\@MODE\@\@\@/$mode/g;
   $html =~ s/\@\@\@ICO_LINK\@\@\@/$config{'ico_url'}/g;
   $html =~ s/\@\@\@BG_URL\@\@\@/$prefs{'bgurl'}/g;
   $html =~ s/\@\@\@CHARSET\@\@\@/$charset/g;

   my $info = $extra_info?"$extra_info - ":"";
   if ($user ne '') {
      $info.=qq|$prefs{'email'} -|;
      if ($config{'quota_module'} ne "none") {
         $info.=qq| |.lenstr($quotausage*1024,1);
         $info.=qq| (|.(int($quotausage*1000/$quotalimit)/10).qq|%)| if ($quotalimit);
         $info.=qq| -|;
      }
   }
   my $t=time();
   $info.= " ".ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial($t),
                               $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                               $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'})." ";
   if ($prefs{'daylightsaving'} eq 'on' ||
       ($prefs{'daylightsaving'} eq 'auto' &&
        ow::datetime::is_dst($t, $prefs{'timeoffset'}, $prefs{'timezone'})) ) {
      $info.=ow::datetime::seconds2timeoffset(ow::datetime::timeoffset2seconds($prefs{'timeoffset'})+3600)." -";
   } else {
      $info.="$prefs{'timeoffset'} -";
   }
   $info.=" $prefs{'locale'} -";
   $html =~ s/\@\@\@USERINFO\@\@\@/$info/g;

   $html = qq|<!-- $$:$persistence_count -->\n|.$html;

   return ($html);
}

sub htmlplugin {
   my ($file, $fromcharset, $tocharset)=@_;
   my $html='';
   if ($file ne '' && open(F, $file) ) {	# $file is defined in config file, which may be a pipe
      local $/; undef $/; $html=<F>;	# no separator, read whole file in once
      close(F);
      $html=~s/\%THISSESSION\%/$thissession/;
      ($html)=iconv($fromcharset, $tocharset, "<center>\n$html</center>\n") if ($html ne '');
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
########## END HTTPPRINT/HTMLHEADER/HTMLFOOTER ###################

########## OPENWEBMAILERROR ######################################
sub openwebmailerror {
   my ($file, $linenum, $msg, $passthrough)=@_;

   $file=~s!.*/!!;

   # to avoid XSS attacks, all output needs to be converted to html entities
   # unless it is told to passthrough unconverted. Passthrough material should
   # already be converted to html entities before arriving here.
   $msg = ow::htmltext::str2html($msg) unless $passthrough;
   $msg="Unknown error $msg at $file:$linenum" if (length($msg)<5);

   my $mailgid=getgrnam('mail');

   my $stackdump='';
   if ($config{'error_with_debuginfo'}) {
      $msg.=qq|<br><font class="medtext">( $file:$linenum, pid=$$, ruid=$<, euid=$>, egid=$), mailgid=$mailgid )</font>\n|;
      $stackdump=ow::tool::stacktrace();
      $stackdump=~s/^\s*//gm;
   }

   if (defined $ENV{'GATEWAY_INTERFACE'}) {	# in CGI mode
      # load prefs if possible, or use default value
      my $background = $style{"background"}||"#FFFFFF"; $background =~ s/"//g;
      my $bgurl=$prefs{'bgurl'}||$config{'default_bgurl'};
      my $locale = ($prefs{'locale'} || $config{'default_locale'});
      my $charset = (ow::lang::localeinfo($locale))[6];
      charset ($charset) if ($CGI::VERSION>=2.58);
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

      $stackdump=qq|<pre>$stackdump</pre>| if ($stackdump ne '');

      my $html = start_html(-title=>"$locale - $config{'name'}",
                            -encoding=>$charset,
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
             qq|<br>$msg<br><br>$stackdump\n|.
             qq|</td></tr>|.
             qq|</table>\n|.
             qq|<p align="center"><br>$config{'page_footer'}<br></p>\n|.
             qq|</body></html>|;
      # for page footer
      $html =~ s!\@\@\@HELP_URL\@\@\@!$config{'ow_htmlurl'}/help/en/index.html!g;
      $html =~ s!\@\@\@HELP_TEXT\@\@\@!Help!g;

      httpprint([], [$html]);

   } else { # command mode
      print "($file:$linenum, pid=$$, ruid=$<, euid=$>, egid=$), mailgid=$mailgid)\n$msg\n$stackdump";
   }

   autologin_rm();	# disable next autologin for specific ip/browser/user
   openwebmail_exit(1);
}
########## END OPENWEBMAILERROR ##################################

########## AUTOCLOSEWINDOW #######################################
sub autoclosewindow {
   my ($title, $msg, $time, $jscode)=@_;
   $time=5 if ($time<3);

   if (defined $ENV{'GATEWAY_INTERFACE'}) {	# in CGI mode
      my ($html, $temphtml);
      $html = applystyle(readtemplate("autoclose.template"));

      $html =~ s/\@\@\@MSGTITLE\@\@\@/$title/g;
      $html =~ s/\@\@\@MSG\@\@\@/$msg/g;
      $html =~ s/\@\@\@TIME\@\@\@/$time/g;
      $html =~ s/\@\@\@JSCODE\@\@\@/$jscode/g;

      $temphtml = button(-name=>'okbutton',
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
########## END AUTOCLOSEWINDOW ###################################

########## WRITELOG/WRITEHISTORY #################################
sub writelog {
   return if (!$config{'logfile'} || -l $config{'logfile'});
   my $timestamp = localtime();
   my $loggedip = ow::tool::clientip();
   my $loggeduser = $loginuser || 'UNKNOWNUSER';
   $loggeduser .= "\@$logindomain" if ($config{'auth_withdomain'});
   $loggeduser .= "($user)" if ($user && $loginuser ne $user);

   if (sysopen(LOGFILE, $config{'logfile'}, O_WRONLY|O_APPEND|O_CREAT)) {
      seek(LOGFILE, 0, 2);	# seek to tail
      print LOGFILE "$timestamp - [$$] ($loggedip) $loggeduser - $_[0]\n";	# log
      close(LOGFILE);
   } else {
      # show log error only if CGI mode
      if (defined $ENV{'GATEWAY_INTERFACE'}) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $config{'logfile'}! ($!)");
      }
   }
   return;
}

sub writehistory {
   return if (!$config{'enable_history'});
   my $timestamp = localtime();
   my $loggedip = ow::tool::clientip();
   my $loggeduser = $loginuser || 'UNKNOWNUSER';
   $loggeduser .= "\@$logindomain" if ($config{'auth_withdomain'});
   $loggeduser .= "($user)" if ($user && $loginuser ne $user);

   my $historyfile=dotpath('history.log');

   if ( -f $historyfile ) {
      ow::filelock::lock($historyfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $historyfile");
      my $end=(stat($historyfile))[7];

      if ( $end > ($config{'maxbooksize'} * 1024) ) {
         my ($start, $buff);
         $start=$end-int($config{'maxbooksize'} * 1024 * 0.8);
         sysopen(HISTORYLOG, $historyfile, O_RDONLY) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $historyfile!($!)");
         seek(HISTORYLOG, $start, 0);
         $_=<HISTORYLOG>;
         $start+=length($_);
         read(HISTORYLOG, $buff, $end-$start);
         close(HISTORYLOG);

         sysopen(HISTORYLOG, $historyfile, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $historyfile!($!)");
         print HISTORYLOG $buff;
      } else {
         sysopen(HISTORYLOG, $historyfile, O_WRONLY|O_APPEND|O_CREAT) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $historyfile!($!)");
         seek(HISTORYLOG, $end, 0);	# seek to tail
      }
      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $_[0]\n";	# log
      close(HISTORYLOG);
      ow::filelock::lock($historyfile, LOCK_UN);

   } else {
      sysopen(HISTORYLOG, $historyfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $historyfile($!)");
      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $_[0]\n";	# log
      close(HISTORYLOG);
   }

   return 0;
}
########## END WRITELOG/WRITEHISTORY #############################

########## DECODE_MIMEWORDS_ICONV ################################
# decode mimewords and do iconv with the charset in =?CHARSET?(B|Q)?...?=
sub decode_mimewords_iconv {
   my @str=ow::mime::decode_mimewords($_[0]);
   my $tocharset=$_[1];
   my $result;
   foreach my $r (@str) {	# r->[0]=decoded str, r->[1]=charset of str
      $result.=(iconv(${$r}[1], $tocharset, ${$r}[0]))[0];
   }
   return $result;
}
########## END DECODE_MIMEWORDS_ICONV ############################

########## UPDATE_AUTHPOP3BOOK ###################################
sub update_authpop3book {
   my ($authpop3book, $domain, $user, $password)=@_;

   $authpop3book=ow::tool::untaint($authpop3book);
   if ($config{'authpop3_getmail'}) {
      my $login=$user; $login .= "\@$domain" if ($config{'auth_withdomain'});
      my %accounts;
      $accounts{"$config{'authpop3_server'}:$config{'authpop3_port'}\@\@\@$login"}
         =join('@@@', $config{'authpop3_server'}, $config{'authpop3_port'}, $config{'authpop3_usessl'},
                      $login, $password, $config{'authpop3_delmail'}, 1);
      writepop3book($authpop3book, \%accounts);
   } else {
      unlink($authpop3book);
   }
}
########## END UPDATE_AUTHPOP3BOOK ###############################

########## SAFE DOMAINNAME/FOLDERNAME/DLNAME/XHEADERS ############
sub safedomainname {
   my $domainname=$_[0];
   $domainname=~s!\.\.+!!g;
   $domainname=~s![^A-Za-z\d\_\-\.]!!g;	# reserve safe char only
   return($domainname);
}

sub safefoldername {
   my $foldername=$_[0];

   # dangerous char for path interpretation
   $foldername =~ s!\.\.+!!g;
   # $foldername =~ s!/!!g;	# comment out because of sub folder

   # dangerous char at string begin/tail for perl file open
   $foldername =~ s!^\s*[\|\<\>]+!!g;
   $foldername =~ s![\|\<\>]+\s*$!!g;

   # all dangerous char within foldername
   if ($config{'enable_strictfoldername'}) {
      $foldername =~ s![\s\`\|\<\>/;&]+!_!g;
   }
   return $foldername;
}

sub is_safefoldername {		# used before create folder
   my $foldername=$_[0];

   return 0 if ($foldername =~ m!\.\.+! ||
                $foldername =~ m!^\s*[\|\<\>]+! ||
                $foldername =~ m![\|\<\>]+\s*$!);
   if ($config{'enable_strictfoldername'}) {
      return 0 if ($foldername =~ m![\s\`\|\<\>/;&]+!);
   }
   return 1;
}

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

sub safexheaders {
   my $xheaders='';
   foreach (split("\n", $_[0])) {
      s/^\s*//; s/\s*//;
      $xheaders.="X-$1: $2\n" if (/^[Xx]\-([\w\d\-_]+):\s*(.*)$/);
   }
   my $clientip=ow::tool::clientip();
   $xheaders=~s/\@\@\@CLIENTIP\@\@\@/$clientip/g;
   my $userid=$loginuser; $userid.="\@$logindomain" if ($config{'auth_withdomain'});
   $xheaders=~s/\@\@\@USERID\@\@\@/$userid/g;

   return $xheaders;
}
########## END SAFE DOMAINNAME/FOLDERNAME/DLNAME/XHEADERS ########

########## VPATH RELATED #########################################
sub path2array {
   my @p=();
   foreach (split(/\//, $_[0])) {	# $_[0] is th epath
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

sub absolute_vpath {
   my ($base, $vpath)=@_;
   $vpath="$base/$vpath" if ($vpath!~m|^/|);
   return('/'.join('/', path2array($vpath)));
}

sub fullpath2vpath {
   my @p=path2array($_[0]);		# $_[0] is realpath
   foreach my $r (path2array($_[1])) {	# $_[1] is rootpath
      return if ($r ne shift(@p));
   }
   return('/'.join('/', @p));
}

# check hidden, symboliclink, out symboliclink, unix specific files
sub verify_vpath {
   my ($rootpath, $vpath)=@_;
   my $filename=$vpath; $filename=~s|.*/||;
   if (!$config{'webdisk_lshidden'} && $filename=~/^\./) {
      return "hidden file";
   }

   my ($retcode, $realpath)=resolv_symlink("$rootpath/$vpath");
   return "too deep symbolic link?" if ($retcode<0);

   if (-l "$rootpath/$vpath") {
      if (!$config{'webdisk_lssymlink'}) {
         return "symbolic link";
      }
      if (!$config{'webdisk_allow_symlinkout'}) {
         if ( fullpath2vpath($realpath, (resolv_symlink($rootpath))[1]) eq "") {
            return "symbolic linked to dir/file outside webdisk";
         }
      }
   }
   if ( fullpath2vpath($realpath, (resolv_symlink($config{'ow_sessionsdir'}))[1]) ne "") {
      writelog("webdisk error - attemp to hack sessions dir!");
      return "system sessions dir";
   }
   if ($config{'logfile'}) {
      if ( fullpath2vpath($realpath, (resolv_symlink($config{'logfile'}))[1]) ne "") {
         writelog("webdisk error - attemp to hack log file!");
         return "system log file";
      }
   }

   if (!$config{'webdisk_lsmailfolder'} && is_under_dotdir_or_folderdir($realpath)) {
      return "mail data file";
   }
   if (!$config{'webdisk_lsunixspec'} && (-e $realpath && !-d _ && !-f _)) {
      return "unix specific file";
   }
   return;
}

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
########## END VPATH... ##########################################

########## IS_LOCALUSER ##########################################
sub is_localuser {
   foreach  ( @{$config{'localusers'}} ) {
      return 1 if ($_ eq $_[0]);	# $_[0] is localuser
   }
   return 0;
}
########## END IS_LOCALUSER ######################################

########## IS_ADM ################################################
sub is_vdomain_adm {
   if (defined @{$config{'vdomain_admlist'}}) {
      foreach my $adm (@{$config{'vdomain_admlist'}}) {
         return 1 if ($_[0] eq $adm);		# $_[0] is the user
      }
   }
   return 0;
}
########## END IS_ADM ############################################

########## VDOMAIN_USERSPOOL #####################################
sub vdomain_userspool {
   my ($vuser, $vhomedir) = @_;
   my $dest;
   my $spool=ow::tool::untaint("$config{'vdomain_vmpop3_mailpath'}/$domain/$vuser");

   if ( $config{'vdomain_mailbox_command'} ) {
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
########## END VUSER_SPOOL #######################################

########## ICONLINK ##############################################
sub iconlink {
   my ($icon, $label, $url)=@_;
   my ($link, $titlestr, $altstr);
   if ($label ne '') {
      $titlestr=qq|title="$label"|;
      $altstr=qq|alt="$label"|;
   }

   if ($prefs{'iconset'} =~ /^Text\./) {
      $link=$icontext{$icon}||"[$icon]"; $link=~s/\.(?:gif|jpg|png)]$/]/i;
      $link="<b>$link</b>";
   } else {
      $link = qq|<IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/$icon" border="0" align="absmiddle" $altstr>|;
   }
   $link = qq|<a $url $titlestr>$link</a>| if ($url ne "");

   return($link);
}
########## END ICONLINK ##########################################

########## LENSTR ################################################
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
########## END LENSTR ############################################

########## TEMPLATEBLOCK ENABLE/DISABLE ##########################
sub templateblock_enable {
   my ($starttag, $endtag)=($_[1].'START', $_[1].'END');
   $_[0]=~s/\@\@\@$starttag\@\@\@\n?//sg;
   $_[0]=~s/\@\@\@$endtag\@\@\@\n?//sg;
}

sub templateblock_disable {
   my ($starttag, $endtag)=($_[1].'START', $_[1].'END');
   $_[0]=~s/\@\@\@$starttag\@\@\@.*?\@\@\@$endtag\@\@\@\n?/$_[2]/sg;
}
########## TEMPLATEBLOCK ENABLE/DISABLE ##########################

########## DOTDIR RELATED ########################################
use vars qw(%_is_dotpath);
foreach (qw(
   openwebmailrc release.date autologin.check history.log
)) { $_is_dotpath{'root'}{$_}=1; }
foreach (qw(
   filter.book filter.check filter.pid filter.ruledb filter.folderdb
   from.book address.book stationery.book
   trash.check search.cache signature
)) { $_is_dotpath{'webmail'}{$_}=1; }
foreach (qw(
   catagories.cache
)) { $_is_dotpath{'webaddr'}{$_}=1; }
foreach (qw(
   calendar.book notify.check
)) { $_is_dotpath{'webcal'}{$_}=1; }
foreach (qw(
   webdisk.cache
)) { $_is_dotpath{'webdisk'}{$_}=1; }
foreach (qw(
   pop3.book pop3.check authpop3.book
)) { $_is_dotpath{'pop3'}{$_}=1; }


# return the path of files within openwebmail dot dir (~/.openwebmail/)
sub dotpath {
   # passing global $domain, $user, $homedir as parameters
   return _dotpath($_[0], $domain, $user, $homedir);
}

# This _ version of routine is used by dotpath() and openwebmail-vdomain.pl
# When vdomain adm has to determine dotpath for vusers,
# the param of vuser($vdomain, $vuser, $vhomedir) will be passed
# instead of the globals($domain, $user, $homedir), which are param of vdomain adm himself
sub _dotpath {
   my ($name, $domain, $user, $homedir)=@_;
   my $dotdir;
   if ($config{'use_syshomedir_for_dotdir'}) {
      $dotdir = "$homedir/$config{'homedirdotdirname'}";
   } else {
      my $owuserdir = "$config{'ow_usersdir'}/".($config{'auth_withdomain'}?"$domain/$user":$user);
      $dotdir = "$owuserdir/$config{'homedirdotdirname'}";
   }
   return(ow::tool::untaint($dotdir)) if ($name eq '/');

   return(ow::tool::untaint("$dotdir/$name"))         if ($_is_dotpath{'root'}{$name});
   return(ow::tool::untaint("$dotdir/webmail/$name")) if ($_is_dotpath{'webmail'}{$name} || $name=~/^filter\.book/);
   return(ow::tool::untaint("$dotdir/webaddr/$name")) if ($_is_dotpath{'webaddr'}{$name});
   return(ow::tool::untaint("$dotdir/webcal/$name"))  if ($_is_dotpath{'webcal'}{$name});
   return(ow::tool::untaint("$dotdir/webdisk/$name")) if ($_is_dotpath{'webdisk'}{$name});
   return(ow::tool::untaint("$dotdir/pop3/$name"))    if ($_is_dotpath{'pop3'}{$name} || $name=~/^uidl\./);

   $name=~s!^/+!!;
   return(ow::tool::untaint("$dotdir/$name"));
}

# move .openwebmail to right location automatically
# if option use_syshomedir_for_dotdir is changed from yes(default) to no
sub find_and_move_dotdir {
   my ($syshomedir, $owuserdir)=@_;

   my $dotdir_in_syshome=$config{'use_syshomedir'} && $config{'use_syshomedir_for_dotdir'};
   my $syshomedotdir=ow::tool::untaint("$syshomedir/$config{'homedirdotdirname'}");
   my $owuserdotdir=ow::tool::untaint("$owuserdir/$config{'homedirdotdirname'}");

   my ($src, $dst);
   if ($dotdir_in_syshome && -d $owuserdotdir && !-d $syshomedotdir) {
      ($src, $dst)=($owuserdotdir, $syshomedotdir);
   } elsif (!$dotdir_in_syshome && -d $syshomedotdir && !-d $owuserdotdir) {
      ($src, $dst)=($syshomedotdir, $owuserdotdir);
   } else {
      return;
   }

   # try 'mv' first, then 'cp+rm'
   if (system(ow::tool::findbin('mv'), '-f', $src, $dst)==0 or
       (system(ow::tool::findbin('cp'), '-Rp', $src, $dst)==0 and
        system(ow::tool::findbin('rm'), '-Rf', $src)==0) ) {
      writelog("move dotdir - $src -> $dst");
   }
}

sub check_and_create_dotdir {
   my $dotdir=$_[0];

   foreach  ('/', 'db', keys %_is_dotpath) {
      next if ($_ eq 'root');
      my $p=ow::tool::untaint($dotdir); $p.="/$_" if ($_ ne '/');
      if (! -d $p) {
         mkdir($p, 0700) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $p ($!)");
         writelog("create dir - $p, euid=$>, egid=$)");
      }
   }
}

sub is_under_dotdir_or_folderdir {
   my $file=$_[0];
   my $spoolfile=(get_folderpath_folderdb($user, 'INBOX'))[0];
   foreach (dotpath('/'), "$homedir/$config{'homedirfolderdirname'}", $spoolfile) {
      my $p=(resolv_symlink($_))[1];
      return 1 if (fullpath2vpath($file, $p) ne "");
   }
   return 0;
}
########## END DOTDIR RELATED ####################################

########## AUTOLOGIN DB related ##################################
# we store ip and browsername in autologin db,
# so a user may have different autologin settings on different computer
# or even different browsers on same computer
sub autologin_add {
   my $agentip=$ENV{'HTTP_USER_AGENT'}.ow::tool::clientip();
   my $autologindb=dotpath('autologin.check');
   my (%DB, $timestamp);

   return 0 if (!ow::dbm::open(\%DB, $autologindb, LOCK_EX));
   $timestamp=time();
   foreach my $key (%DB) {
      delete $DB{$key} if ($timestamp-$DB{$key}>86400*7);
   }
   $DB{$agentip}=$timestamp;
   ow::dbm::close(\%DB, $autologindb);
   return 1;
}

sub autologin_rm {
   my $agentip=$ENV{'HTTP_USER_AGENT'}.ow::tool::clientip();
   my $autologindb=dotpath('autologin.check');
   my %DB;

   return 0 if (!ow::dbm::exist($autologindb));
   return 0 if (!ow::dbm::open(\%DB, $autologindb, LOCK_EX));
   delete $DB{$agentip};
   ow::dbm::close(\%DB, $autologindb);
   return 1;
}

sub autologin_check {
   my $agentip=$ENV{'HTTP_USER_AGENT'}.ow::tool::clientip();
   my $autologindb=dotpath('autologin.check');
   my (%DB, $timestamp);

   return 0 if (!ow::dbm::exist($autologindb));
   return 0 if (!ow::dbm::open(\%DB, $autologindb, LOCK_EX));
   $DB{$agentip}=$timestamp=time() if (defined $DB{$agentip});
   ow::dbm::close(\%DB, $autologindb);
   return 1 if ($timestamp ne '');
}
########## END AUTOLOGIN DB related ##############################

# DEFAULTFOLDERS related #########################################

use vars qw(@_defaultfolders %_is_defaultfolder %_folder_config);
@_defaultfolders=('INBOX', 'saved-messages', 'sent-mail', 'saved-drafts', 'mail-trash', 'spam-mail', 'virus-mail');
foreach (@_defaultfolders, 'LEARNSPAM', 'LEARNHAM', 'DELETE', 'FORWARD') { $_is_defaultfolder{$_}=1 };

%_folder_config=(
   'sent-mail'    => 'enable_backupsent',
   'saved-drafts' => 'enable_savedraft',
   'spam-mail'    => 'has_spamfolder_by_default',
   'virus-mail'   => 'has_virusfolder_by_default',
);

sub get_defaultfolders {
   my @f;
   foreach (@_defaultfolders) {
      next if (defined $_folder_config{$_} && !$config{$_folder_config{$_}});
      push(@f, $_);
   }
   return(@f);
}

sub is_defaultfolder {
   return 0 if (defined $_folder_config{$_[0]} && !$config{$_folder_config{$_[0]}});
   return 1 if ($_is_defaultfolder{$_[0]});
   return 0;
}
# END DEFAULTFOLDERS related #####################################

########## GETFOLDERS ############################################
# return list of valid folders and size of INBOX and other folders
sub getfolders {
   my ($r_folders, $r_inboxusage, $r_folderusage)=@_;
   my @userfolders;
   my $totalsize = 0;

   my $spoolfile=(get_folderpath_folderdb($user, 'INBOX'))[0];

   my $folderdir="$homedir/$config{'homedirfolderdirname'}";

   my (@fdirs, $fdir, @folderfiles, $filename);
   @fdirs=($folderdir);				# start with root folderdir

   while ($fdir=pop(@fdirs)) {
      opendir(FOLDERDIR, "$fdir") or
    	 openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} ".f2u($fdir)."! ($!)");
         @folderfiles=readdir(FOLDERDIR);
      closedir(FOLDERDIR) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} ".f2u($folderdir)."! ($!)");

      foreach $filename (@folderfiles) {
         next if (substr($filename,0,1) eq '.' || $filename =~ /\.lock$/);

         if (-d "$fdir/$filename" && $config{'enable_userfolders'}) { 	# recursive into non dot dir
            push(@fdirs,"$fdir/$filename");
            next;
         }
         # don't count spoolfile in folder finding
         next if ("$fdir/$filename" eq $spoolfile);

         # distingush default folders and user folders
         if (is_defaultfolder($filename) && $fdir eq $folderdir) {
            $totalsize += ( -s "$folderdir/$filename" );
         } else {
            if ($config{'enable_userfolders'}) {
               $totalsize += ( -s "$folderdir/$filename" );
               push(@userfolders, substr("$fdir/$filename",length($folderdir)+1));
            }
         }

      }
   }

   @{$r_folders}=get_defaultfolders();
   push (@{$r_folders}, sort(@userfolders));

   ${$r_inboxusage}=0;
   ${$r_inboxusage}=(-s $spoolfile)/1024 if (-f $spoolfile);
   ${$r_folderusage}=$totalsize/1024;	# unit=k
   return;
}
########## END GETFOLDERS ########################################

########## GET_FOLDERPATH_FOLDERDB ###############################
sub get_folderpath_folderdb {
   my ($username, $foldername)=@_;
   my ($folderfile, $folderdb);

   if ($foldername eq 'INBOX') {
      if ($config{'use_homedirspools'}) {
         $folderfile = "$homedir/$config{'homedirspoolname'}";
      } elsif ($config{'use_hashedmailspools'}) {
         $folderfile = "$config{'mailspooldir'}/".
                       substr($username,0,1)."/".
                       substr($username,1,1)."/$username";
      } else {
         $folderfile = "$config{'mailspooldir'}/$username";
      }
      $folderdb=dotpath('db')."/$username";

   } elsif ($foldername eq 'DELETE') {
      $folderfile = $folderdb ='';

   } else {
      $folderdb =$foldername; $folderdb=~s!/!#!g;
      $folderfile = "$homedir/$config{'homedirfolderdirname'}/$foldername";
      $folderdb=dotpath('db')."/$folderdb";
   }

   return(ow::tool::untaint($folderfile), ow::tool::untaint($folderdb));
}
########## GET_FOLDERPATH_FOLDERDB ###############################

########## DEL_STALEDB ###########################################
# remove stale folder index db/cache/lock file
sub del_staledb {
   my ($user, $r_folders)=@_;

   my $dbdir=dotpath('db');
   my %is_valid;
   foreach my $foldername (@{$r_folders}) {
      my $dbname=(get_folderpath_folderdb($user, $foldername))[1];
      $dbname=~s!^$dbdir/!!;
      $is_valid{$dbname}=1;
   }

   my @delfiles=();
   my (@dbfiles, $filename);

   opendir(DBDIR, $dbdir) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} ".f2u($dbdir)."! ($!)");
      @dbfiles=readdir(DBDIR);
   closedir(DBDIR) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} ".f2u($dbdir)."! ($!)");

   foreach $filename (@dbfiles) {
      next if ($filename eq '.' || $filename eq '..');
      my $purename=$filename;
      $purename=~s/\.(lock|cache|db|dir|pag|db\.lock|dir\.lock|pag\.lock)$//;
      if (!$is_valid{$purename}) {
         push(@delfiles, ow::tool::untaint("$dbdir/$filename"));
      }
   }

   if ($#delfiles>=0) {
      writelog("del staledb - ".join(", ", @delfiles));
      unlink(@delfiles);
   }
}
########## END DEL_STALEDB #######################################

########## GET_ABOOKEMAILHASH ####################################
# this routine gets the EMAIL attributes in abookfiles directly
# to avoid the overhead of vcard parsing
sub get_abookemailhash {
   my (%emails, @userabookfiles, @globalabookfiles);

   my $webaddrdir = dotpath('webaddr');
   if (opendir(D, $webaddrdir)) {
      @userabookfiles = map { "$webaddrdir/$_" }
                        grep { /^[^.]/ && !/^categories\.cache$/ }
                        readdir(D);
      closedir(D);
   }
   if (opendir(D, $config{'ow_addressbooksdir'})) {
      @globalabookfiles = map { "$config{'ow_addressbooksdir'}/$_" }
                          grep { /^[^.]/ }
                          readdir(D);
      closedir(D);
   }

   foreach my $abookfile (@userabookfiles, @globalabookfiles) {
      if (sysopen(F, $abookfile, O_RDONLY)) {
         while (<F>) {
            # stored in lower case for case insensitive lookup
            $emails{lc($2)}=1 if (/^EMAIL(;TYPE=PREF)?:(.+?)\s*$/);
         }
         close(F);
      }
   }

   return(\%emails);
}
########## END GET_ABOOKEMAILHASH ################################

########## F2U/U2F ###############################################
sub f2u { # convert str from filesystem charset to userprefs charset
   my $localecharset = (ow::lang::localeinfo($prefs{'locale'}))[6];
   return (iconv($prefs{'fscharset'}, $localecharset, $_[0]))[0];
}
sub u2f { # convert str from userprefs charset to filesystem charset
   my $localecharset = (ow::lang::localeinfo($prefs{'locale'}))[6];
   return (iconv($localecharset, $prefs{'fscharset'}, $_[0]))[0];
}
########## END F2U/U2F ###########################################

1;
