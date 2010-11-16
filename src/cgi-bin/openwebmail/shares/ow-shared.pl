
#                              The BSD License
#
#  Copyright (c) 2009-2010, The OpenWebMail Project
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

# routines shared by openwebmail*.pl

use strict;
use warnings;

use lib 'lib';
use Fcntl qw(:DEFAULT :flock);
use HTML::Template 2.9;
use OWM::PO;

# extern vars used by caller openwebmail-xxx.pl files
use vars qw($SCRIPT_DIR);
use vars qw($persistence_count);
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($default_logindomain $loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %icontext);
use vars qw($quotausage $quotalimit);
use vars qw($htmltemplatefilters $po);

# globals constants
use vars qw(%is_config_option);
use vars qw(@openwebmailrcitem);
use vars qw($_vars_used);
use vars qw(%_rawconfcache);
use vars qw(%_is_dotpath);
use vars qw(%_is_defaultfolder %_is_defaultabookfolder %_folder_config);

require "modules/htmltext.pl";

$persistence_count = 0;

%_is_defaultfolder = (
                        # folders
                        'INBOX'          => 1,
                        'saved-messages' => 2,
                        'sent-mail'      => 3,
                        'saved-drafts'   => 4,
                        'mail-trash'     => 5,
                        'spam-mail'      => 6,
                        'virus-mail'     => 7,

                        # actions
                        'LEARNSPAM'      => 8,
                        'LEARNHAM'       => 9,
                        'MARKASREAD'     => 10,
                        'MARKASUNREAD'   => 11,
                        'DELETE'         => 12,
                        'FORWARD'        => 13,
                     );

%_is_defaultabookfolder = (
                             # folders
                             'ALL'       => 1,
                             'global'    => 2,
                             'ldapcache' => 3,

                             # actions
                             'DELETE'    => 12,
                          );

%_folder_config = (
                     'sent-mail'    => 'enable_backupsent',
                     'saved-drafts' => 'enable_savedraft',
                     'spam-mail'    => 'has_spamfolder_by_default',
                     'virus-mail'   => 'has_virusfolder_by_default',
                  );


# define the files that may exist in $USER/.openwebmail
%_is_dotpath = (
                     root => {
                                'autologin.check'  => 1,
                                'history.log'      => 1,
                                'openwebmailrc'    => 1,
                                'release.date'     => 1,
                             },
                  webmail => {
                                'address.book'     => 1,
                                'filter.book'      => 1,
                                'filter.check'     => 1,
                                'filter.folderdb'  => 1,
                                'filter.pid'       => 1,
                                'filter.ruledb'    => 1,
                                'from.book'        => 1,
                                'search.cache'     => 1,
                                'signature'        => 1,
                                'stationery.book'  => 1,
                                'trash.check'      => 1,
                             },
                  webaddr => {
                                'catagories.cache' => 1,
                             },
                   webcal => {
                                'calendar.book'    => 1,
                                'notify.check'     => 1,
                             },
                  webdisk => {
                                'webdisk.cache'    => 1,
                             },
                     pop3 => {
                                'authpop3.book'    => 1,
                                'pop3.book'        => 1,
                                'pop3.check'       => 1,
                             },
               );

# define all config option parameter possibilities
%is_config_option = (
                       yesno => {  # yes no type config options
                                   abook_globaleditable               => 1,
                                   about_info_client                  => 1,
                                   about_info_protocol                => 1,
                                   about_info_scriptfilename          => 1,
                                   about_info_server                  => 1,
                                   about_info_software                => 1,
                                   auth_withdomain                    => 1,
                                   authpop3_delmail                   => 1,
                                   authpop3_getmail                   => 1,
                                   authpop3_usessl                    => 1,
                                   auto_createrc                      => 1,
                                   cache_userinfo                     => 1,
                                   case_insensitive_login             => 1,
                                   create_syshomedir                  => 1,
                                   debug_fork                         => 1,
                                   debug_maildb                       => 1,
                                   debug_mailfilter                   => 1,
                                   debug_request                      => 1,
                                   default_abook_collapse             => 1,
                                   default_abook_defaultfilter        => 1,
                                   default_autopop3                   => 1,
                                   default_backupsentmsg              => 1,
                                   default_backupsentoncurrfolder     => 1,
                                   default_bgrepeat                   => 1,
                                   default_blockimages                => 1,
                                   default_calendar_reminderforglobal => 1,
                                   default_calendar_showemptyhours    => 1,
                                   default_calendar_showlunar         => 1,
                                   default_categorizedfolders         => 1,
                                   default_confirmmsgmovecopy         => 1,
                                   default_disableembcode             => 1,
                                   default_disablejs                  => 1,
                                   default_filter_badaddrformat       => 1,
                                   default_filter_fakedexecontenttype => 1,
                                   default_filter_fakedfrom           => 1,
                                   default_filter_fakedsmtp           => 1,
                                   default_hideinternal               => 1,
                                   default_moveoldmsgfrominbox        => 1,
                                   default_readwithmsgcharset         => 1,
                                   default_regexmatch                 => 1,
                                   default_reparagraphorigmsg         => 1,
                                   default_showhtmlastext             => 1,
                                   default_showimgaslink              => 1,
                                   default_sigbeforeforward           => 1,
                                   default_smartdestination           => 1,
                                   default_usefixedfont               => 1,
                                   default_uselightbar                => 1,
                                   default_useminisearchicon          => 1,
                                   default_usesmileicon               => 1,
                                   default_viewnextaftermsgmovecopy   => 1,
                                   default_webdisk_confirmcompress    => 1,
                                   default_webdisk_confirmdel         => 1,
                                   default_webdisk_confirmmovecopy    => 1,
                                   delfile_ifquotahit                 => 1,
                                   deliver_use_gmt                    => 1,
                                   delmail_ifquotahit                 => 1,
                                   domainnames_override               => 1,
                                   enable_about                       => 1,
                                   enable_addressbook                 => 1,
                                   enable_advsearch                   => 1,
                                   enable_autoreply                   => 1,
                                   enable_backupsent                  => 1,
                                   enable_calendar                    => 1,
                                   enable_changepwd                   => 1,
                                   enable_domainselectmenu            => 1,
                                   enable_editfrombook                => 1,
                                   enable_globalfilter                => 1,
                                   enable_history                     => 1,
                                   enable_ldap_abook                  => 1,
                                   enable_learnspam                   => 1,
                                   enable_loadfrombook                => 1,
                                   enable_pop3                        => 1,
                                   enable_preference                  => 1,
                                   enable_saprefs                     => 1,
                                   enable_savedraft                   => 1,
                                   enable_setforward                  => 1,
                                   enable_smartfilter                 => 1,
                                   enable_spamcheck                   => 1,
                                   enable_spellcheck                  => 1,
                                   enable_sshterm                     => 1,
                                   enable_stationery                  => 1,
                                   enable_strictfoldername            => 1,
                                   enable_strictforward               => 1,
                                   enable_strictpwd                   => 1,
                                   enable_strictvirtuser              => 1,
                                   enable_urlattach                   => 1,
                                   enable_userfilter                  => 1,
                                   enable_userfolders                 => 1,
                                   enable_vdomain                     => 1,
                                   enable_viruscheck                  => 1,
                                   enable_webdisk                     => 1,
                                   enable_webmail                     => 1,
                                   error_with_debuginfo               => 1,
                                   forced_moveoldmsgfrominbox         => 1,
                                   forced_ssl_login                   => 1,
                                   frombook_for_realname_only         => 1,
                                   has_spamfolder_by_default          => 1,
                                   has_virusfolder_by_default         => 1,
                                   iconv_error_labels                 => 1,
                                   pop3_delmail_by_default            => 1,
                                   pop3_delmail_hidden                => 1,
                                   pop3_usessl_by_default             => 1,
                                   session_checkcookie                => 1,
                                   session_checksameip                => 1,
                                   session_count_display              => 1,
                                   session_multilogin                 => 1,
                                   smartfilter_bypass_goodmessage     => 1,
                                   smtpauth                           => 1,
                                   spamcheck_include_report           => 1,
                                   stay_ssl_afterlogin                => 1,
                                   symboliclink_mbox                  => 1,
                                   use_hashedmailspools               => 1,
                                   use_homedirspools                  => 1,
                                   use_syshomedir                     => 1,
                                   use_syshomedir_for_dotdir          => 1,
                                   viruscheck_include_report          => 1,
                                   webdisk_allow_chmod                => 1,
                                   webdisk_allow_gzip                 => 1,
                                   webdisk_allow_listarchive          => 1,
                                   webdisk_allow_symlinkcreate        => 1,
                                   webdisk_allow_symlinkout           => 1,
                                   webdisk_allow_tar                  => 1,
                                   webdisk_allow_thumbnail            => 1,
                                   webdisk_allow_unace                => 1,
                                   webdisk_allow_unarj                => 1,
                                   webdisk_allow_unbzip2              => 1,
                                   webdisk_allow_ungzip               => 1,
                                   webdisk_allow_unlzh                => 1,
                                   webdisk_allow_unrar                => 1,
                                   webdisk_allow_untar                => 1,
                                   webdisk_allow_untnef               => 1,
                                   webdisk_allow_unzip                => 1,
                                   webdisk_allow_zip                  => 1,
                                   webdisk_lshidden                   => 1,
                                   webdisk_lsmailfolder               => 1,
                                   webdisk_lssymlink                  => 1,
                                   webdisk_lsunixspec                 => 1,
                                   webdisk_readonly                   => 1,
                                },
                        none => {  # none type config options
                                   allowed_autologinip                => 1,
                                   allowed_clientdomain               => 1,
                                   allowed_clientip                   => 1,
                                   allowed_receiverdomain             => 1,
                                   allowed_rootloginip                => 1,
                                   allowed_serverdomain               => 1,
                                   b2g_map                            => 1,
                                   default_abook_defaultkeyword       => 1,
                                   default_abook_defaultsearchtype    => 1,
                                   default_bgurl                      => 1,
                                   default_categorizedfolders_fs      => 1,
                                   default_realname                   => 1,
                                   footer_pluginfile                  => 1,
                                   g2b_map                            => 1,
                                   header_pluginfile                  => 1,
                                   ldap_abook_container               => 1,
                                   localusers                         => 1,
                                   logfile                            => 1,
                                   lunar_map                          => 1,
                                   vdomain_mailbox_command            => 1,
                                   webmail_middle_pluginfile          => 1,
                                },
                        auto => {  # auto type config options
                                   auth_domain                        => 1,
                                   default_autoreplysubject           => 1,
                                   default_calendar_holidaydef        => 1,
                                   default_daylightsaving             => 1,
                                   default_fromemails                 => 1,
                                   default_locale                     => 1,
                                   default_msgformat                  => 1,
                                   default_timeoffset                 => 1,
                                   domainnames                        => 1,
                                   domainselectmenu_list              => 1,
                                },
                        list => {  # list type config options
                                   allowed_autologinip                => 1,
                                   allowed_clientdomain               => 1,
                                   allowed_clientip                   => 1,
                                   allowed_receiverdomain             => 1,
                                   allowed_rootloginip                => 1,
                                   allowed_serverdomain               => 1,
                                   default_fromemails                 => 1,
                                   domainnames                        => 1,
                                   domainselectmenu_list              => 1,
                                   localusers                         => 1,
                                   pop3_disallowed_servers            => 1,
                                   smtpserver                         => 1,
                                   spellcheck_dictionaries            => 1,
                                   vdomain_admlist                    => 1,
                                   vdomain_postfix_aliases            => 1,
                                   vdomain_postfix_virtual            => 1,
                                },
                     untaint => {  # untaint path config options
                                   auth_module                        => 1,
                                   authpop3_port                      => 1,
                                   authpop3_server                    => 1,
                                   default_locale                     => 1,
                                   domainnames                        => 1,
                                   global_calendarbook                => 1,
                                   global_filterbook                  => 1,
                                   homedirfolderdirname               => 1,
                                   homedirspoolname                   => 1,
                                   logfile                            => 1,
                                   mailspooldir                       => 1,
                                   ow_addressbooksdir                 => 1,
                                   ow_cgidir                          => 1,
                                   ow_etcdir                          => 1,
                                   ow_htmldir                         => 1,
                                   ow_langdir                         => 1,
                                   ow_mapsdir                         => 1,
                                   ow_layoutsdir                      => 1,
                                   ow_sessionsdir                     => 1,
                                   ow_sitesconfdir                    => 1,
                                   ow_usersconfdir                    => 1,
                                   ow_usersdir                        => 1,
                                   smtpserver                         => 1,
                                   spellcheck                         => 1,
                                   vacationinit                       => 1,
                                   vacationpipe                       => 1,
                                   vdomain_postfix_aliases            => 1,
                                   vdomain_postfix_postalias          => 1,
                                   vdomain_postfix_postmap            => 1,
                                   vdomain_postfix_virtual            => 1,
                                   vdomain_vmpop3_mailpath            => 1,
                                   vdomain_vmpop3_pwdname             => 1,
                                   vdomain_vmpop3_pwdpath             => 1,
                                   virtusertable                      => 1,
                                   zonetabfile                        => 1,
                                },
                     require => {  # require type config options
                                   auth_module                        => 1,
                                   default_locale                     => 1,
                                },
                    );

# set type for DEFAULT_ options (the forced defaults for default_ options)
foreach my $opttype ('yesno', 'none', 'list') {
   foreach my $optname (keys %{$is_config_option{$opttype}}) {
      $is_config_option{$opttype}{$optname} = 1 if $optname =~ s/^default_/DEFAULT_/;
   }
}

# define all user configurable options
@openwebmailrcitem = qw(
                          abook_addrperpage
                          abook_buttonposition
                          abook_collapse
                          abook_defaultfilter
                          abook_defaultkeyword
                          abook_defaultsearchtype
                          abook_height
                          abook_listviewfieldorder
                          abook_sort
                          abook_width
                          autocc
                          autopop3
                          autopop3wait
                          backupsentmsg
                          backupsentoncurrfolder
                          bgfilterthreshold
                          bgfilterwait
                          bgrepeat
                          bgurl
                          blockimages
                          calendar_defaultview
                          calendar_endhour
                          calendar_holidaydef
                          calendar_interval
                          calendar_monthviewnumitems
                          calendar_reminderdays
                          calendar_reminderforglobal
                          calendar_showemptyhours
                          calendar_showlunar
                          calendar_starthour
                          calendar_weekstart
                          categorizedfolders
                          categorizedfolders_fs
                          charset
                          confirmmsgmovecopy
                          ctrlposition_folderview
                          ctrlposition_msgread
                          dateformat
                          daylightsaving
                          defaultdestination
                          dictionary
                          disableembcode
                          disableemblink
                          disablejs
                          editcolumns
                          editrows
                          email
                          fieldorder
                          filter_badaddrformat
                          filter_fakedexecontenttype
                          filter_fakedfrom
                          filter_fakedsmtp
                          filter_repeatlimit
                          fontsize
                          fscharset
                          headers
                          hideinternal
                          hourformat
                          iconset
                          language
                          layout
                          locale
                          mailsentwindowtime
                          moveoldmsgfrominbox
                          msgdatetype
                          msgformat
                          msgsperpage
                          newmailsound
                          newmailwindowtime
                          readwithmsgcharset
                          refreshinterval
                          regexmatch
                          reparagraphorigmsg
                          replyto
                          replywithorigmsg
                          searchtype
                          sendbuttonposition
                          sendcharset
                          sendreceipt
                          sessiontimeout
                          showhtmlastext
                          showimgaslink
                          sigbeforeforward
                          smartdestination
                          sort
                          spamcheck_maxsize
                          spamcheck_source
                          spamcheck_threshold
                          spamvirusreserveddays
                          style
                          timeoffset
                          timezone
                          trashreserveddays
                          usefixedfont
                          uselightbar
                          useminisearchicon
                          usesmileicon
                          viewnextaftermsgmovecopy
                          viruscheck_maxsize
                          viruscheck_minbodysize
                          viruscheck_source
                          webdisk_confirmcompress
                          webdisk_confirmdel
                          webdisk_confirmmovecopy
                          webdisk_dirnumitems
                          webdisk_fileeditcolumns
                          webdisk_fileeditrows
                       );

# load the configuration for this site
load_owconf(\%config_raw, "$SCRIPT_DIR/etc/defaults/openwebmail.conf");
read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/openwebmail.conf") if -f "$SCRIPT_DIR/etc/openwebmail.conf";

# load the default locale language strings
$po = loadlang($config{default_locale});

$htmltemplatefilters = [
                          # translate strings identified with gettext('') using the po file for this locale
                          { sub => sub { my $text_aref = shift; s#(gettext\(["'](.+?)["']\))#gettext($2)#ige for @{$text_aref} },
                            format => 'array' },
                          # remove any space at the start of a line if it is immediately before a tmpl tag
                          { sub => sub { my $text_aref = shift; s#^[\t ]+(</?tmpl_[^>]+>)#$1#gi for @{$text_aref} },
                            format => 'array' },
                          # cluster <a> closing and opening links to avoid unintentional gaps between images
                          { sub => sub { my $text_ref = shift; $$text_ref =~ s#(</a>(?:&nbsp;|</tmpl_[^>]+>)?)(\s+)(<a href)#$1$3#sgi },
                            format => 'scalar' },
                          # remove any \n and \r following a tmpl tag
                          { sub => sub { my $text_ref = shift; $$text_ref =~ s#(</?tmpl_[^>]+>)[\r\n]+#$1#sgi },
                            format => 'scalar' },
                       ];

sub openwebmail_requestbegin {
   # routine used at the beginning of every CGI request
   # init euid/egid to nobody to drop uid www as early as possible
   my $nobodygid = getgrnam('nobody') || 65534;
   my $nobodyuid = getpwnam('nobody') || 65534;

   # $< Real user id of process.
   # $> Effective user id of process.
   # $( Real group id of process.
   # $) Effective group id of process.
   #
   # From perlvar: a value assigned to $) must also be a space-separated list of numbers. The first number
   # is used to set the effective gid, and the rest (if any) are passed to setgroups(). To get the effect of
   # an empty list for setgroups(), just repeat the new effective gid; that is, to force an effective gid of 5
   # and an effectively empty setgroups() list, say
   #
   #  $) = "5 5"

   if ($> == 0) {
     $< = $nobodyuid;
     $( = $nobodygid;
     $) = "$nobodygid $nobodygid";
   }

   # ow::tool::zombie_cleaner();          # clear pending zombies
   openwebmail_clearall() if $_vars_used; # clear global
   $_vars_used = 1;
   $SIG{PIPE} = \&openwebmail_exit;       # for user stop
   $SIG{TERM} = \&openwebmail_exit;       # for user stop
}

sub openwebmail_requestend {
   # routine used at the end of every CGI request
   ow::tool::zombie_cleaner();            # clear pending zombies
   openwebmail_clearall() if $_vars_used; # clear global
   $_vars_used = 0;
   $persistence_count++;

   my $nobodygid = getgrnam('nobody') || 65534;
   my $nobodyuid = getpwnam('nobody') || 65534;

   # back euid to root if possible, required for setuid under persistent perl
   $> = 0;

   if ($> == 0) {
     $< = $nobodyuid;
     $( = $nobodygid;
     $) = "$nobodygid $nobodygid";
   }
}

sub openwebmail_clearall {
   # clear opentable in filelock.pl
   ow::filelock::closeall() if defined %ow::filelock::opentable;

   # chdir back to openwebmail cgidir
   chdir($config{ow_cgidir}) if exists $config{ow_cgidir} && -d $config{ow_cgidir};

   # clear global variables for persistent perl
   undef %SIG                 if defined %SIG;
   undef %config              if defined %config;
   undef %config_raw          if defined %config_raw;
   undef $thissession         if defined $thissession;
   undef %icontext            if defined %icontext;

   undef $default_logindomain if defined $default_logindomain;
   undef $loginname           if defined $loginname;
   undef $logindomain         if defined $logindomain;
   undef $loginuser           if defined $loginuser;

   undef $domain              if defined $domain;
   undef $user                if defined $user;
   undef $userrealname        if defined $userrealname;
   undef $uuid                if defined $uuid;
   undef $ugid                if defined $ugid;
   undef $homedir             if defined $homedir;
   undef %prefs               if defined %prefs;
   undef $po                  if defined $po;

   undef $quotausage          if defined $quotausage;
   undef $quotalimit          if defined $quotalimit;
}

sub userenv_init {
   # userenv_init: initializes user globals and switches euid to the user
   if ($config{smtpauth}) {	# load smtp auth user/pass
      read_owconf(\%config, \%config_raw, "$SCRIPT_DIR/etc/smtpauth.conf");
      if ($config{smtpauth_username} eq '' || $config{smtpauth_password} eq '') {
         openwebmailerror(gettext('The SMTP username or password are not properly defined:') . " $SCRIPT_DIR/etc/smtpauth.conf");
      }
   }

   if (!defined param('sessionid')) {
      # delayed response for non localhost
      sleep $config{loginerrordelay} if ow::tool::clientip() ne '127.0.0.1';
      openwebmailerror(gettext('Access denied: the session id is not properly defined.'));
   }
   $thissession = param('sessionid') || '';
   $thissession =~ s!\.\.+!!g;  # remove ..

   # sessionid format: loginname+domain-session-0.xxxxxxxxxx
   if ($thissession =~ /^([\w\.\-\%\@]+)\*([\w\.\-]*)\-session\-(0\.\d+)$/) {
      local $1; 				# fix perl $1 taintness propagation bug
      $thissession = $1."*".$2."-session-".$3;	# untaint
      ($loginname, $default_logindomain) = ($1, $2); # param from sessionid
   } else {
      openwebmailerror(gettext('Illegal characters in session id:') . " $thissession");
   }

   ($logindomain, $loginuser) = login_name2domainuser($loginname, $default_logindomain);

   if (!is_localuser("$loginuser\@$logindomain") &&  -f "$config{ow_sitesconfdir}/$logindomain") {
      read_owconf(\%config, \%config_raw, "$config{ow_sitesconfdir}/$logindomain");
   }

   # setuid is required if spool is located in system dir
   if ($> != 0 && ($config{mailspooldir} eq '/var/mail' || $config{mailspooldir} eq '/var/spool/mail')) {
      print header();
      print gettext('This script must be setuid root:') . " $0";
      openwebmail_exit(0);
   }
   ow::auth::load($config{auth_module});

   $user = '';
   # try userinfo cached in session file first
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
	= split(/\@\@\@/, (sessioninfo($thissession))[2]) if $config{cache_userinfo};

   # use userinfo from auth server if user is root or null
   ($domain, $user, $userrealname, $uuid, $ugid, $homedir)
	= get_domain_user_userinfo($logindomain, $loginuser) if $user eq '' || $uuid == 0 || $ugid =~ m/\b0\b/;

   if ($user eq '') {
      sleep $config{loginerrordelay}; # delayed response
      openwebmailerror(gettext('User does not exist:') . " $loginuser\@$logindomain");
   }

   if (!matchlist_fromhead('allowed_rootloginip', ow::tool::clientip())) {
      if ($user eq 'root' || $uuid == 0) {
         sleep $config{loginerrordelay}; # delayed response
         writelog("userinfo error - possible root hacking attempt");
         openwebmailerror(gettext('Sorry, root login is disabled for security.'));
      }
   }

   # load user config
   my $userconf = "$config{ow_usersconfdir}/$user";
   $userconf = "$config{ow_usersconfdir}/$domain/$user" if $config{auth_withdomain};
   read_owconf(\%config, \%config_raw, $userconf) if -f $userconf;

   # override auto guessing domainanmes if loginname has domain or domainselectmenu enabled
   if (${$config_raw{domainnames}}[0] eq 'auto' && ($loginname =~ m/\@/ || $config{enable_domainselectmenu})) {
      $config{domainnames} = [ $logindomain ];
   }

   # override realname if defined in config
   if ($config{default_realname} ne 'auto') {
      $userrealname = $config{default_realname};
   }

   if (!$config{use_syshomedir}) {
      $homedir = "$config{ow_usersdir}/" . ($config{auth_withdomain} ? "$domain/$user" : $user);
   }

   $user    = ow::tool::untaint($user);
   $uuid    = ow::tool::untaint($uuid);
   $ugid    = ow::tool::untaint($ugid);
   $homedir = ow::tool::untaint($homedir);

   umask(0077);

   if ($> == 0) {
      # switch to uuid:mailgid if script is setuid root
      # for better compatibility with other mail progs
      my $mailgid = getgrnam('mail');
      ow::suid::set_euid_egids($uuid, $ugid, $mailgid);
      openwebmailerror(gettext('Setting effective group id to "mail" failed:') . " mail($mailgid)")
        unless $) =~ m/\b$mailgid\b/; # group mail does not exist?
   }

   %prefs = readprefs();
   $po    = loadlang($prefs{locale});
   charset((ow::lang::localeinfo($prefs{locale}))[4]) if $CGI::VERSION >= 2.58; # setup charset of CGI module

   verifysession();

   if ($prefs{iconset} =~ m/^Text\./) {
      ($prefs{iconset} =~ m/^([\w\d\.\-_]+)$/) && ($prefs{iconset} = $1);
      my $icontext = ow::tool::untaint("$config{ow_htmldir}/images/iconsets/$prefs{iconset}/icontext");
      delete $INC{$icontext};
      require $icontext;
   }

   if ($config{quota_module} ne 'none') {
      ow::quota::load($config{quota_module});

      my $ret    = '';
      my $errmsg = '';
      ($ret, $errmsg, $quotausage, $quotalimit) = ow::quota::get_usage_limit(\%config, $user, $homedir, 0);
      if ($ret == -1) {
         writelog("quota error - $config{quota_module}, ret $ret, $errmsg");
         openwebmailerror(gettext('Quota usage limit parameter format error.'));
      } elsif ($ret < 0) {
         writelog("quota error - $config{quota_module}, ret $ret, $errmsg");
         openwebmailerror(gettext('Quota system error.'));
      }
      $quotalimit = $config{quota_limit} if $quotalimit < 0;
   } else {
      ($quotausage, $quotalimit) = (0,0);
   }

   # set env for external programs
   $ENV{HOME} = $homedir;
   $ENV{USER} = $ENV{LOGNAME} = $user;
   chdir($homedir);

   return;
}

sub login_name2domainuser {
   my ($loginname, $default_logindomain) = @_;

   my ($logindomain, $loginuser) = ();

   if ($loginname =~ m#^(.+)\@(.+)$#) {
      ($loginuser, $logindomain) = ($1, $2);
   } else {
      $loginuser   = $loginname;
      $logindomain = $default_logindomain || $ENV{HTTP_HOST} || ow::tool::hostname();
      $logindomain =~ s#:\d+$##; # remove port number
   }

   $loginuser   = lc($loginuser) if ($config{'case_insensitive_login'});

   $logindomain = lc(safedomainname($logindomain));
   $logindomain = $config{domainname_equiv}{map}{$logindomain}
      if (exists $config{domainname_equiv}{map}{$logindomain} && defined $config{domainname_equiv}{map}{$logindomain});

   return ($logindomain, $loginuser);
}

sub read_owconf {
   # read openwebmail.conf into a hash with %symbol% resolved
   # the hash is 'called by reference' since we want to do 'untaint' on it
   my ($r_config, $r_config_raw, $configfile) = @_;

   # load up the config file if we have one
   load_owconf($r_config_raw, $configfile) if defined $configfile && -f $configfile;

   # make sure there are default values for array/hash references
   if (!defined $r_config_raw->{domainname_equiv}){
      $r_config_raw->{domainname_equiv} = { map => {}, list => {} };
   }

   foreach my $key (keys %{$is_config_option{list}}) {
      # We do not set the default value for DEFAULT_ options, or else the default_ options would be overriden.
      # DEFAULT_ options should be set only if they appear in config file
      $r_config_raw->{$key} = [] if !defined $r_config_raw->{$key} && $key !~ m/^DEFAULT_/;
   }

   # copy config_raw to config so we do not modify config_raw
   %{$r_config} = %{$r_config_raw};

   # resolve %var% in hash config
   # note, no substitutions to domainname_equiv or yes/no items
   # should the exclusion include other types??
   foreach my $key (keys %{$r_config}) {
      next if $key eq 'domainname_equiv' || (exists $is_config_option{yesno}{$key} && $is_config_option{yesno}{$key});
      if ($is_config_option{list}{$key}) {
         foreach (@{$r_config->{$key}}) {
            $_ = fmt_subvars($key, $_, $r_config, $configfile);
         }
      } else {
         $r_config->{$key} = fmt_subvars($key, $r_config->{$key}, $r_config, $configfile);
      }
   }

   # cleanup auto values with server or client side runtime enviroment
   # since result may differ for different clients, this could not be done in load_owconf()
   foreach my $key (keys %{$is_config_option{auto}}) {
      if (exists $is_config_option{list}{$key} && $is_config_option{list}{$key}) {
         next if $r_config->{$key}[0] ne 'auto';

         if ($key eq 'domainnames') {
            my $value = '';

            if (exists $ENV{HTTP_HOST} && defined $ENV{HTTP_HOST} && $ENV{HTTP_HOST} =~ m/[A-Za-z]\./) {
               $value = $ENV{HTTP_HOST};
               $value =~ s/:\d+$//; # remove port number
            } else {
               $value = ow::tool::hostname();
            }

            $r_config->{$key} = [$value];
         }
      } else {
         next if $r_config->{$key} ne 'auto';
         if ($key eq 'default_timeoffset') {
            $r_config->{$key} = ow::datetime::gettimeoffset();
         } elsif ($key eq 'default_locale') {
            $r_config->{$key} = ow::lang::guess_browser_locale(available_locales());
         }
      }
   }

   # set options that refer to other options
   $r_config->{default_bgurl} = "$r_config->{ow_htmlurl}/images/backgrounds/Transparent.gif" if $r_config->{default_bgurl} eq '';
   $r_config->{default_abook_defaultsearchtype} = 'name' if $r_config->{default_abook_defaultsearchtype} eq '';
   $r_config->{domainselectmenu_list} = $r_config->{domainnames} if $r_config->{domainselectmenu_list}[0] eq 'auto';

   # untaint pathname variable defined in openwebmail.conf
   foreach my $key ( keys %{$is_config_option{untaint}} ) {
      if (exists $is_config_option{list}{$key} && $is_config_option{list}{$key}) {
         foreach (@{$r_config->{$key}}) {
            $_ = ow::tool::untaint($_);
         }
      } else {
         $r_config->{$key} =ow::tool::untaint($r_config->{$key});
      }
   }

   # add system wide vars to minimize disk access lookups
   $r_config->{available_locales} = available_locales();

   return;
}

sub load_owconf {
   # load ow conf file and merge with an existing hash
   my ($r_config_raw, $configfile) = @_;

   my $t = 0;
   $t = -M $configfile if $configfile !~ /openwebmail\.conf\.default$/;

   if (!defined $_rawconfcache{$configfile}{t} || $_rawconfcache{$configfile}{t} ne $t) {
      $_rawconfcache{$configfile}{t} = $t;
      $_rawconfcache{$configfile}{c} = _load_owconf($configfile);
   }

   foreach (keys %{$_rawconfcache{$configfile}{c}}) {
      $r_config_raw->{$_} = $_rawconfcache{$configfile}{c}->{$_};

      # remove DEFAULT_ restriction when default_ is overridden
      delete $r_config_raw->{'DEFAULT_'.$1} if $_ =~ m/^default_(.*)/;
   }

   return;
}

sub _load_owconf {
   # load ow conf file into a new hash, return ref of the new hash
   # so the hash can be cached to speedup later access
   my $configfile = shift;
   openwebmailerror(gettext('Invalid path for configuation file:') . " $configfile") if $configfile =~ m/\.\./;

   my %conf = ();
   my ($ret, $err) = ow::tool::load_configfile($configfile, \%conf);
   openwebmailerror(gettext('Cannot open file:') . " $configfile ($err)") if $ret < 0;

   # data stru/value formatting
   foreach my $key (keys %conf) {
      # the option lookup key should be all lowercase so that DEFAULT_
      # options get handled the same as default_ options without having
      # to specify DEFAULT_option_name in the is_config_option hash
      my $lckey = lc($key);

      # turn ow_htmlurl from / to null to avoid // in url
      $conf{$key} = '' if $key eq 'ow_htmlurl' and $conf{$key} eq '/';

      # set exact 'auto'
      $conf{$key} = 'auto'
        if exists $is_config_option{auto}{$key} && $is_config_option{auto}{$key} && $conf{$key} =~ m/^auto$/i;

      # clean up yes/no params
      $conf{$key} = fmt_yesno($conf{$key})
        if exists $is_config_option{yesno}{$lckey} && $is_config_option{yesno}{$lckey};

      # remove / and .. from variables that will be used in require statement for security
      $conf{$key} = fmt_require($conf{$key})
        if exists $is_config_option{require}{$lckey} && $is_config_option{require}{$lckey};

      # clean up none
      $conf{$key} = fmt_none($conf{$key})
        if exists $is_config_option{none}{$lckey} && $is_config_option{none}{$lckey};

      # format hash or list data stru
      if ($key eq 'domainname_equiv') {
         my %equiv    = ();
         my %equivlist= ();
         foreach (split(/\n/, $conf{$key})) {
            s/^[:,\s]+//;
            s/[:,\s]+$//;
            my ($dst, @srclist) = split(/[:,\s]+/);
            $equivlist{$dst} = \@srclist;
            foreach my $src (@srclist) {
               $equiv{$src} = $dst if $src && $dst;
            }
         }

         $conf{$key}= {
                         map  => \%equiv,     # src -> dst
                         list => \%equivlist, # dst <= srclist
                      };
      } elsif ($key eq 'revision') {
         # convert the SVN revision to only a number
         $conf{$key} =~ s#[^\d]+##g;
      } elsif ($is_config_option{list}{$lckey}){
         my $value = $conf{$key};
         $value =~ s/\s//g;

         my @list = split(/,+/, $value);
         $conf{$key} = \@list;
      }
   }

   return \%conf;
}

sub fmt_subvars {
   # substitute %var% values
   # Important: Do not mess with $_ in here!
   my ($key, $value, $r_config, $configfile)=@_;

   my $iterate = 5;

   $iterate-- while $iterate and $value =~ s/\%([\w\d_]+)\%/${$r_config}{$1}/msg;

   openwebmailerror(gettext('A %var% style configuration variable is too recursive:') . " $key $configfile") if $iterate == 0;

   return $value;
}

sub fmt_yesno {
   # translate yes/no text into 1/0 (true/false)
   return 1 if $_[0] =~ m/y(es)?/i || $_[0] eq '1';
   return 0;
}

sub fmt_none {
   # blank out a none value
   return '' if $_[0] =~ m/^(none|""|'')$/i;
   return $_[0];
}

sub fmt_require {
   # remove / and .. for variables used in require statements for security
   $_ = $_[0];
   s#(/|\.\.)##g;
   return $_;
}

sub matchlist_all {
   my ($listname)=@_;
   return 1 if (!defined $config{$listname});

   foreach my $token (@{$config{$listname}}) {
      return 1 if (lc($token) eq 'all');
   }
   return 0;
}

sub matchlist_exact {
   my ($listname, $value) = @_;
   $value = lc($value);
   return 1 if (!defined $config{$listname});

   foreach (@{$config{$listname}}) {
      my $token = lc($_);
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

sub available_locales {
   my $available_locales = {};

   # make sure we have the language
   opendir(LANGDIR, $config{ow_langdir}) || openwebmailerror(gettext('Cannot open directory:') . " $config{ow_langdir} ($!)");
   $available_locales->{$_}++ for map { m/(.+)\.po$/; $1 } grep { !m/^\.+/ && !m#[/\\]# && m/(.+)\.po$/ && -f "$config{ow_langdir}/$_" } readdir(LANGDIR);
   closedir(LANGDIR) || openwebmailerror(gettext('Cannot close directory:') . " $config{ow_langdir} ($!)");

   return $available_locales;
}

sub readprefs {
   my %prefshash = ();

   if (defined $user && $user ne '') {
      my $rcfile = dotpath('openwebmailrc');

      if (-f $rcfile) {
         # read .openwebmailrc
         # ps: prefs entries are kept as pure strings to make the following things easier
         #     1. copy default from $config{default...}
         #     2. store prefs value back to openwebmailrc file
         sysopen(RC, $rcfile, O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $rcfile ($!)");
         while (<RC>) {
            my ($key, $value) = split(/=/, $_);
            chomp($value);
            if ($key eq 'style') {
               $value =~ s/^\.//g;  # In case someone gets a bright idea...
            }
            $prefshash{$key} = $value;
         }
         close(RC);
      }

      # read .signature
      $prefshash{signature} = '';

      my $signaturefile = dotpath('signature');

      $signaturefile = "$homedir/.signature" if defined $homedir && !-f $signaturefile &&  -f "$homedir/.signature";

      if (-f $signaturefile) {
         sysopen(SIGNATURE, $signaturefile, O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $signaturefile ($!)");

         $prefshash{signature} .= $_ while <SIGNATURE>;

         close(SIGNATURE);
      }

      $prefshash{signature} =~ s/\s+$/\n/;
   }

   # get default value from config for err/undefined/empty prefs entries

   # validate email with defaultemails if frombook is limited to change realname only
   if ($config{frombook_for_realname_only} || (defined $prefshash{email} && $prefshash{email} eq '')) {
      my @defaultemails = get_defaultemails();
      my $valid = 0;

      foreach (@defaultemails) {
         if (defined $prefshash{email} && $prefshash{email} eq $_) {
            $valid = 1;
            last;
         }
      }

      $prefshash{email} = $defaultemails[0] if !$valid;
   }

   # all rc entries are disallowed to be empty
   foreach my $key (@openwebmailrcitem) {
      if (defined $config{'DEFAULT_'.$key}) {
         $prefshash{$key} = $config{'DEFAULT_'.$key};
      } elsif ((!defined $prefshash{$key} || $prefshash{$key} eq '') && defined $config{'default_'.$key}) {
         $prefshash{$key} = $config{'default_'.$key};
      }
   }

   # signature allowed to be empty but not undefined
   foreach my $key ('signature') {
      if (defined $config{'DEFAULT_'.$key}) {
         $prefshash{$key} = $config{'DEFAULT_'.$key};
      } elsif (!defined $prefshash{$key} && defined $config{'default_'.$key}) {
         $prefshash{$key} = $config{'default_'.$key};
      }
   }

   # remove / and .. from variables that will be used in require statement for security
   $prefshash{locale}  =~ s#/##g;
   $prefshash{locale}  =~ s#\.\.##g;
   $prefshash{iconset} =~ s#/##g;
   $prefshash{iconset} =~ s#\.\.##g;

   # adjust bgurl in case the OWM has been reinstalled in different place
   if (
        $prefshash{bgurl} =~ m#^(/.+)/images/backgrounds/(.*)$#
        && $1 ne $config{ow_htmlurl}
        && -f "$config{ow_htmldir}/images/backgrounds/$2"
      ) {
      $prefshash{bgurl} = "$config{ow_htmlurl}/images/backgrounds/$2";
   }

   # force layout for mobile devices
   # $prefshash{layout} = 'iphone' if $ENV{HTTP_USER_AGENT} =~ m/iphone/i;

   # entries related to on-disk directory or file
   $prefshash{layout}  = $config{default_layout}  unless -d "$config{ow_layoutsdir}/$prefshash{layout}";
   $prefshash{style}   = $config{default_style}   unless -f "$config{ow_layoutsdir}/$prefshash{layout}/styles/$prefshash{style}.css";
   $prefshash{iconset} = $config{default_iconset} unless -d "$config{ow_htmldir}/images/iconsets/$prefshash{iconset}";
   $prefshash{locale}  = $config{default_locale}  unless -f "$config{ow_langdir}/$prefshash{locale}.po";

   $prefshash{refreshinterval} = $config{min_refreshinterval} if $prefshash{refreshinterval} < $config{min_refreshinterval};

   # rentries related to spamcheck or viruscheck limit
   $prefshash{viruscheck_source}  = 'pop3' if $prefshash{viruscheck_source} eq 'all' && $config{viruscheck_source_allowed} eq 'pop3';
   $prefshash{spamcheck_source}   = 'pop3' if $prefshash{spamcheck_source} eq 'all' && $config{spamcheck_source_allowed} eq 'pop3';
   $prefshash{viruscheck_maxsize} = $config{viruscheck_maxsize_allowed} if $prefshash{viruscheck_maxsize} > $config{viruscheck_maxsize_allowed};
   $prefshash{spamcheck_maxsize}  = $config{spamcheck_maxsize_allowed} if $prefshash{spamcheck_maxsize} > $config{spamcheck_maxsize_allowed};

   # rentries related to addressbook
   if ($prefshash{abook_listviewfieldorder} !~ m#(fullname|prefix|first|middle|last|suffix|email)#) {
     $prefshash{abook_listviewfieldorder} = $config{default_abook_listviewfieldorder};
   }

   return %prefshash;
}

sub get_template {
   my $templatename = shift;

   my $layout = $prefs{layout} || $config{default_layout};

   my $templatefile = "$config{ow_layoutsdir}/$layout/templates/$templatename";

   return (
            -f $templatefile
            ? $templatefile
            : $templatename eq 'error.tmpl'
              ? die 'error.tmpl does not exist. No error messages can be displayed.'
              : openwebmailerror(gettext('The requested template file does not exist:') . " $templatefile ($!)")
          );
}

sub verifysession {
   my $sessionfile = ow::tool::untaint("$config{ow_sessionsdir}/$thissession");
   my $now         = time();
   my $modifyage   = $now - (stat($sessionfile))[9];
   if ($modifyage > $prefs{sessiontimeout} * 60) {
      unlink($sessionfile) if -f $sessionfile;

      my $start_url = $config{start_url};
      $start_url    = "https://$ENV{HTTP_HOST}$start_url" if $start_url !~ s#^https?://#https://#i;

      my $template = HTML::Template->new(
                                           filename          => get_template('sessiontimeout.tmpl'),
                                           filter            => $htmltemplatefilters,
                                           die_on_bad_params => 0,
                                           loop_context_vars => 0,
                                           global_vars       => 0,
                                           cache             => 1,
                                        );

      $template->param( start_url => $start_url );

      httpprint([], [$template->output]);

      writelog("session error - session $thissession timeout access attempt");
      writehistory("session error - session $thissession timeout access attempt");

      openwebmail_exit(0);
   }

   my $client_sessionkey = cookie("ow-sessionkey-$domain-$user");

   my ($sessionkey, $ip, $userinfo) = sessioninfo($thissession);
   if ($config{session_checkcookie} && $client_sessionkey ne $sessionkey) {
      writelog("session error - request does not contain the proper sessionid cookie, access denied!");
      writehistory("session error - request does not contain the proper sessionid cookie, access denied!");
      openwebmailerror(gettext('Access denied: your request did not contain the proper session id cookie.') . qq|&nbsp;<br><a href="$config{ow_cgiurl}/openwebmail.pl">| . gettext('Login again?') . qq|</a>|, "passthrough");
   }

   if ($config{session_checksameip} && ow::tool::clientip() ne $ip) {
      writelog("session error - request does not come from the same ip, access denied!");
      writehistory("session error - request does not com from the same ip, access denied!");
      openwebmailerror(gettext('Access denied: your request did not come from the same ip address that initiated this session.') . qq|&nbsp;<br><a href="$config{ow_cgiurl}/openwebmail.pl">| . gettext('Login again?') . qq|</a>|, "passthrough");
   }

   # no_update is set to 1 if auto-refresh/timeoutwarning
   my $session_noupdate = param('session_noupdate') || 0;
   if (!$session_noupdate) {
      # update the session timestamp with now-1,
      # the -1 is for nfs, utime is actually the nfs rpc setattr()
      # since nfs server current time will be used if setattr() is issued with nfs client's current time.
      utime ($now - 1, $now - 1,  $sessionfile) or
         openwebmailerror(gettext('Cannot update timestamp on file:') . " $sessionfile ($!)");
   }
   return 1;
}

sub sessioninfo {
   my $sessionid  = shift;
   my $sessionkey = '';
   my $userinfo   = '';
   my $ip         = '';

   openwebmailerror(gettext('Session ID does not exist:') . qq|<br>$sessionid<br><a href="$config{ow_cgiurl}/openwebmail.pl">| . gettext('Login again?') . qq|</a>|, "passthrough")
     unless -e "$config{ow_sessionsdir}/$sessionid";

   if (! sysopen(F, "$config{ow_sessionsdir}/$sessionid", O_RDONLY)) {
      writelog("session error - could not open $config{ow_sessionsdir}/$sessionid ($@)");
      openwebmailerror(gettext('Cannot open file:') . " $config{ow_sessionsdir}/$sessionid");
   }

   $sessionkey = <F>;
   chomp $sessionkey;

   $ip = <F>;
   chomp $ip;

   $userinfo = <F>;
   chomp $userinfo;
   close(F);

   return ($sessionkey, $ip, $userinfo);
}

sub update_virtuserdb {
   # update index db of virtusertable
   my (%DB, %DBR, $metainfo) = ();

   # convert file name and path into a simple file name
   my $virtname = $config{virtusertable};
   $virtname =~ s#/#.#g;  # remove slashes
   $virtname =~ s#^\.+##; # remove leading dots

   my $virtdb = ow::tool::untaint(("$config{ow_mapsdir}/$virtname"));

   if (! -e $config{virtusertable}) {
      ow::dbm::unlinkdb($virtdb) if ow::dbm::existdb($virtdb);
      ow::dbm::unlinkdb("$virtdb.rev") if ow::dbm::existdb("$virtdb.rev");
      return;
   }

   $metainfo = ow::tool::metainfo($config{virtusertable});

   if (ow::dbm::existdb($virtdb)) {
      ow::dbm::opendb(\%DB, $virtdb, LOCK_SH) or return;
      my $dbmetainfo=$DB{'METAINFO'};
      ow::dbm::closedb(\%DB, $virtdb);
      return if ( $dbmetainfo eq $metainfo );
   }

   writelog("update $virtdb");

   ow::dbm::opendb(\%DB, $virtdb, LOCK_EX, 0644) or return;
   my $ret = ow::dbm::opendb(\%DBR, "$virtdb.rev", LOCK_EX, 0644);
   if (!$ret) {
      ow::dbm::closedb(\%DB, $virtdb);
      return;
   }
   %DB  = ();	# ensure the virdb is empty
   %DBR = ();

   # parse the virtusertable
   sysopen(VIRT, $config{virtusertable}, O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:' . " $config{virtusertable} ($!)"));

   while (my $line = <VIRT>) {
      $line =~ s/^\s+//;                   # remove leading whitespace
      $line =~ s/\s+$//;                   # remove trailing whitespace
      $line =~ s/#.*$//;                   # remove comment lines
      $line =~ s/(.*?)\@(.*?)%1/$1\@$2$1/; # resolve %1 in virtusertable: user@domain.com %1@example.com

      next unless defined $line && $line ne '';

      my ($vu, $u) = split(/[\s\t]+/, $line);
      next if !defined $vu || $vu eq '' || !defined $u || $u eq '';
      next if $vu =~ m/^@/; # ignore entries for whole domain mapping

      $DB{$vu} = $u;
      $DBR{$u} = defined $DBR{$u} ? ",$vu" : "$vu";
   }

   close(VIRT) or
      openwebmailerror(gettext('Cannot close file:' . " $config{virtusertable} ($!)"));

   $DB{METAINFO} = $metainfo;

   ow::dbm::closedb(\%DBR, "$virtdb.rev") or
      openwebmailerror(gettext('Cannot close db:' . " $virtdb.rev"));

   ow::dbm::closedb(\%DB, $virtdb) or
      openwebmailerror(gettext('Cannot close db:' . " $virtdb"));

   ow::dbm::chmoddb(0644, $virtdb, "$virtdb.rev");

   return;
}

sub get_user_by_virtualuser {
   my $virtualuser = shift;

   # convert file name and path into a simple file name
   my $virtname = $config{virtusertable};
   $virtname =~ s#/#.#g;
   $virtname =~ s#^\.+##;

   my $virtdb = ow::tool::untaint(("$config{ow_mapsdir}/$virtname"));

   my %DB = ();
   my $username = '';

   if (ow::dbm::existdb($virtdb)) {
      ow::dbm::opendb(\%DB, $virtdb, LOCK_SH) or return $username;
      $username = $DB{$virtualuser};
      ow::dbm::closedb(\%DB, $virtdb);
   }

   return $username;
}

sub get_virtualuser_by_user {
   my $username = shift;

   # convert file name and path into a simple file name
   my $virtname = $config{virtusertable};
   $virtname =~ s#/#.#g;
   $virtname =~ s#^\.+##;

   my $virtdb_reverse = ow::tool::untaint(("$config{ow_mapsdir}/$virtname.rev"));

   my %DBR = ();
   my $virtualuser = '';

   if (ow::dbm::existdb($virtdb_reverse)) {
      ow::dbm::opendb(\%DBR, $virtdb_reverse, LOCK_SH) or return $virtualuser;
      $virtualuser = $DBR{$username};
      ow::dbm::closedb(\%DBR, $virtdb_reverse);
   }

   return $virtualuser;
}

sub get_domain_user_userinfo {
   my ($logindomain, $loginuser) = @_;
   my ($domain, $user, $realname, $uid, $gid, $homedir) = ();

   $user = get_user_by_virtualuser($loginuser) || '';

   if ($user eq '') {
      my @domainlist = ($logindomain);

      if (exists $config{domain_equiv}{list}{$logindomain} && defined @{$config{domain_equiv}{list}{$logindomain}}) {
         push(@domainlist, @{$config{domain_equiv}{list}{$logindomain}});
      }

      foreach (@domainlist) {
         $user = get_user_by_virtualuser("$loginuser\@$_") || '';
         last if $user ne '';
      }
   }

   if ($user=~/^(.*)\@(.*)$/) {
      ($user, $domain)=($1, lc($2));
   } else {
      if ($user eq '') {
         if ($config{enable_strictvirtuser}) {
            # if the loginuser is mapped in virtusertable by any vuser,
            # then one of the vuser should be used instead of loginname for login
            my $vu = get_virtualuser_by_user($loginuser);
            return('', '', '', '', '', '') if $vu ne '';
         }
         $user = $loginuser;
      }
      if ($config{auth_domain} ne 'auto') {
         $domain = lc($config{auth_domain});
      } else {
         $domain = $logindomain;
      }
   }

   my ($errcode, $errmsg);
   if ($config{auth_withdomain}) {
      ($errcode, $errmsg, $realname, $uid, $gid, $homedir) = ow::auth::get_userinfo(\%config, "$user\@$domain");
   } else {
      ($errcode, $errmsg, $realname, $uid, $gid, $homedir) = ow::auth::get_userinfo(\%config, $user);
   }
   writelog("userinfo error - $config{auth_module}, ret $errcode, $errmsg") if ($errcode != 0);

   $realname = $loginuser if $realname eq '';
   if ($uid ne '') {
      return($domain, $user, $realname, $uid, $gid, $homedir);
   } else {
      return('', '', '', '', '', '');
   }
}

sub get_defaultemails {
   return @{$config{default_fromemails}} if $config{default_fromemails}->[0] ne 'auto';

   my %emails = ();

   my @defaultdomains = @{$config{domainnames}};

   my $virtualuser = get_virtualuser_by_user($user) || '';

   if ($virtualuser ne '') {
      foreach my $name (ow::tool::str2list($virtualuser)) {
         if ($name =~ m/^(.*)\@(.*)$/) {
            my $purename = $1;
            next if $purename eq '';              # skip whole @domain mapping
            if ($config{domainnames_override}) {  # override the domainname found in virtual table
               foreach my $host (@defaultdomains) {
                  $emails{"$purename\@$host"} = 1;
               }
            } else {
               $emails{$name} = 1;
            }
         } else {
            foreach my $host (@defaultdomains) {
               $emails{"$name\@$host"} = 1;
            }
         }
      }
   } else {
      foreach my $host (@defaultdomains) {
         $emails{"$loginuser\@$host"} = 1 if defined $loginuser && $loginuser ne '';
      }
   }

   return keys %emails;
}

sub get_userfroms {
   # return a hash of all of the from addresses this user has
   my $froms = {};

   my $realname = defined $config{DEFAULT_realname} ? $config{DEFAULT_realname} : $userrealname;

   # get default from email addresses
   my @defaultemails = get_defaultemails();
   $froms->{$_} = $realname for @defaultemails;

   # get user defined from email addresses
   my $frombook = dotpath('from.book');

   if ($config{enable_loadfrombook} && sysopen(FROMBOOK, $frombook, O_RDONLY)) {
      while (my $line = <FROMBOOK>) {
         my ($frombook_email, $frombook_realname) = split(/\@\@\@/, $line, 2);

         chomp($frombook_realname);

         $frombook_realname = $config{DEFAULT_realname} if defined $config{DEFAULT_realname};

         if (!$config{frombook_for_realname_only} || exists $froms->{$frombook_email}) {
             $froms->{$frombook_email} = $frombook_realname;
         }
      }

      close(FROMBOOK);
   }

   return $froms;
}

sub sort_emails_by_domainnames {
   my $r_domainnames = shift;
   my @email = sort(@_);

   my @result = ();
   foreach my $domain (@{$r_domainnames}) {
      for (my $i=0; $i<=$#email; $i++) {
         if ($email[$i] =~ m/\@$domain$/) {
            push(@result, $email[$i]);
            $email[$i]='';
         }
      }
   }
   for (my $i=0; $i<=$#email; $i++) {
      push(@result, $email[$i]) if ($email[$i] ne '');
   }

   return(@result);
}

sub is_http_compression_enabled {
   if (cookie("ow-httpcompress")
       && $ENV{HTTP_ACCEPT_ENCODING} =~ /\bgzip\b/
       && ow::tool::has_module('Compress/Zlib.pm')) {
      return 1;
   } else {
      return 0;
   }
}

sub httpprint {
   my ($r_headers, $r_htmls) = @_;

   if (is_http_compression_enabled()) {
      my $zhtml = Compress::Zlib::memGzip(join('',@{$r_htmls}));
      if ($zhtml ne '') {
         print httpheader(
                             @{$r_headers},
                             '-Content-Length'  =>length $zhtml,
                             '-Content-Encoding'=>'gzip',
                             '-Vary'            =>'Accept-Encoding',
                         ), $zhtml;
         return;
      }
   }

   my $len = 0;
   $len += length for @{$r_htmls};

   print httpheader(@{$r_headers}, '-Content-Length'=>$len), @{$r_htmls};
   return;
}

sub httpheader {
   my %headers = @_;
   $headers{'-charset'} = $prefs{charset} if ($CGI::VERSION>=2.57);
   if (!defined $headers{'-Cache-Control'} && !defined $headers{'-Expires'} ) {
      $headers{'-Pragma'}        = 'no-cache';
      $headers{'-Cache-Control'} = 'no-cache,no-store';
   }
   return (header(%headers));
}

sub get_header {
   # extra_info is an optional custom message, typically used
   # to put the unread messages count in the titlebar
   my ($headertemplatefile, $extra_info) = @_;

   my $showaltstyles = 0;
   if (defined $extra_info && $extra_info eq 'showaltstyles') {
      $showaltstyles = 1;
      $extra_info = '';
   }

   my $quotausagebytes          = 0;
   my $quotausagepercentoflimit = 0;
   if (defined $user && $user && $config{quota_module} ne 'none' && defined $quotausage && $quotausage =~ m/^\d+$/) {
      $quotausagebytes          = lenstr($quotausage * 1024, 1);
      $quotausagepercentoflimit = int($quotausage * 1000 / $quotalimit) / 10 if $quotalimit;
   }

   my $timenow = time();
   my $timedatestring = ow::datetime::dateserial2str(
                                                      ow::datetime::gmtime2dateserial($timenow),
                                                      $prefs{timeoffset},
                                                      $prefs{daylightsaving},
                                                      $prefs{dateformat},
                                                      $prefs{hourformat},
                                                      $prefs{timezone}
                                                    );

   my $timeoffset = $prefs{timeoffset};
   if ($prefs{daylightsaving} eq 'on' || ($prefs{daylightsaving} eq 'auto' && ow::datetime::is_dst($timenow, $prefs{timeoffset}, $prefs{timezone}))) {
      $timeoffset = ow::datetime::seconds2timeoffset(ow::datetime::timeoffset2seconds($prefs{timeoffset})+3600);
   }

   my $mode = '(';
   $mode   .= '+' if $persistence_count > 0;
   $mode   .= 'z' if is_http_compression_enabled();
   $mode   .= ')';
   $mode    = '' if $mode eq '()';

   my $titleinfo = join(' - ', grep { defined && $_ } (
                                                         $extra_info,
                                                         ((defined $user && $user) ? $prefs{email} : ''),
                                                         ((defined $user && $user && $config{quota_module} ne 'none')
                                                         ? $quotausagebytes . ($quotausagepercentoflimit ? "($quotausagepercentoflimit\%)" : '') : ''),
                                                         "$timedatestring $timeoffset",
                                                         $prefs{locale},
                                                         $config{name} . ($mode ? ' ' . $mode : ''),
                                                      ));

   my $helpdir = "$config{ow_htmldir}/help";
   my $helpurl = "$config{ow_htmlurl}/help";

   if (-d "$helpdir/$prefs{locale}") {
      # choose help in the correct locale if available
      $helpurl = "$helpurl/$prefs{locale}";
   } else {
      # choose help in the correct language if available
      my $language = substr($prefs{locale}, 0, 2);

      my $firstmatch = '';
      if (-d $helpdir) {
         opendir(HELPDIR, $helpdir) or
           openwebmailerror(gettext('Cannot open directory:') . ' ' . f2u($helpdir) . " ($!)");

         $firstmatch = (map { "$helpurl/$_" } grep { !m/^\.+/ && m/^$language/ } readdir(HELPDIR))[0] || '';

         closedir(HELPDIR) or
           openwebmailerror(gettext('Cannot close directory:') . ' ' . f2u($helpdir) . " ($!)");
      }

      # ...or default to en_US.UTF-8
      $helpurl = $firstmatch || "$helpurl/en_US.UTF-8";
   }

   # Get a list of valid style files
   my $stylesurl = "$config{ow_layoutsurl}/$prefs{layout}/styles";
   my $stylesdir = "$config{ow_layoutsdir}/$prefs{layout}/styles";

   opendir(STYLESDIR, $stylesdir) or
      openwebmailerror(gettext('Cannot open directory:') . " $stylesdir ($!)");

   my @styles = sort grep { -f "$stylesdir/$_" && s/^([^.]+)\.css$/$1/i } readdir(STYLESDIR);

   closedir(STYLESDIR) or
      openwebmailerror(gettext('Cannot close directory:') . " $stylesdir ($!)");

   # build the template
   my $template = HTML::Template->new(
                                      filename          => get_template($headertemplatefile),
                                      filter            => $htmltemplatefilters,
                                      die_on_bad_params => 0,
                                      loop_context_vars => 0,
                                      global_vars       => 0,
                                      cache             => 1,
                                     );


   $template->param(
                      charset            => $prefs{charset},
                      titleinfo          => $titleinfo,
                      url_ico            => $config{ico_url},
                      url_help           => $helpurl,
                      url_bg             => $prefs{bgurl},
                      url_styles         => $stylesurl,
                      stylesheet         => -f "$stylesdir/$prefs{style}.css" ? "$prefs{style}.css" : 'default.css',
                      showaltstyles      => $showaltstyles,
                      stylesheetsloop    => [
                                               map { {
                                                        url_styles => $stylesurl,
                                                        stylesheet => $_ . '.css',
                                                   } } @styles
                                            ],
                      diagnostics        => "$$:$persistence_count",
                      bgrepeat           => $prefs{bgrepeat},
                      fontsize           => $prefs{fontsize},
                      languagedirection  => $ow::lang::RTL{$prefs{locale}} ? 'rtl' : 'ltr',
                      headerpluginoutput => htmlplugin($config{header_pluginfile}, $config{header_pluginfile_charset}, $prefs{charset}),
                   );

   return $template->output;
}

sub get_footer {
   my $footertemplatefile = shift;

   my $remainingseconds = 0;
   if (defined $thissession && $thissession && -f "$config{ow_sessionsdir}/$thissession") {
      $remainingseconds = 365 * 86400; # default timeout = 1 year
      my $ftime= (stat("$config{ow_sessionsdir}/$thissession"))[9];
      $remainingseconds = ($ftime + $prefs{sessiontimeout} * 60 - time()) if $ftime;
   }

   my $helpdir = "$config{ow_htmldir}/help";
   my $helpurl = "$config{ow_htmlurl}/help";
   if ( -d "$helpdir/$prefs{locale}" ) {
      # choose help in the correct locale if available
      $helpurl = "$helpurl/$prefs{locale}";
   } else {
      # choose help in the correct language if available
      my $language = substr($prefs{locale}, 0, 2);

      my $firstmatch = undef;
      if (-d $helpdir) {
         opendir(HELPDIR, $helpdir) or
           openwebmailerror(gettext('Cannot open directory:') . ' ' . f2u($helpdir) . " ($!)");

         $firstmatch = (map { "$helpurl/$_" } grep { !m/^\.+/ && m/^$language/ } readdir(HELPDIR))[0] || undef;

         closedir(HELPDIR) or
           openwebmailerror(gettext('Cannot close directory:') . ' ' . f2u($helpdir) . " ($!)");
      }

      # ...or default to en_US.UTF-8
      $helpurl = $firstmatch || "$helpurl/en_US.UTF-8";
   }

   # build the template
   my $template = HTML::Template->new(
                                      filename          => get_template($footertemplatefile),
                                      filter            => $htmltemplatefilters,
                                      die_on_bad_params => 0,
                                      loop_context_vars => 0,
                                      global_vars       => 0,
                                      cache             => 1,
                                     );


   $template->param(
                      programname        => $config{name},
                      programversion     => $config{version},
                      remainingseconds   => $remainingseconds,
                      url_help           => $helpurl,
                      url_cgi            => $config{ow_cgiurl},
                      sessionid          => $thissession,
                      footerpluginoutput => htmlplugin($config{footer_pluginfile}, $config{footer_pluginfile_charset}, $prefs{charset}),
                   );

   return ($template->output);
}

sub htmlplugin {
   # TODO: this is terrible. No error checking, no reporting at all. The more I think
   # about third party piping as a built-in the less I like it. It should be the job
   # of experienced coders to drop pipe data into the output
   my ($file, $fromcharset, $tocharset) = @_;
   if ($file ne '' && open(F, $file)) { # $file is defined in config file, which may be a pipe
      local $/ = undef;
      my $html = <F>; # slurp
      close(F);
      if (defined $html && $html) {
         $html =~ s/\%THISSESSION\%/$thissession/;
         $html = (iconv($fromcharset, $tocharset, $html))[0];
         return $html;
      } else {
         return '';
      }
   }
}

sub openwebmailerror {
   # this subroutine must not rely on any other subroutines that issue errors
   my ($message, $passthrough) = @_;

   my ($package, $file, $linenumber) = caller;

   ($file) = $file =~ m/[\\\/]([^\\\/]+)$/ if defined $file && $file;

   my $template = HTML::Template->new(
                                        filename          => get_template('error.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # error.tmpl
                      url_styles      => -d "$config{ow_layoutsurl}/$prefs{layout}/styles"
                                         ? "$config{ow_layoutsurl}/$prefs{layout}/styles"
                                         : "$config{ow_layoutsurl}/classic/styles",
                      stylesheet      => -f "$config{ow_layoutsdir}/$prefs{layout}/styles/$prefs{style}.css"
                                         ? "$prefs{style}.css"
                                         : 'default.css',
                      programname     => $config{name},
                      programversion  => $config{version},
                      programrevision => $config{revision},
                      message_unknown => length($message) < 5 ? 1 : 0,
                      message         => $passthrough ? $message : ow::htmltext::str2html($message),
                      passthrough     => $passthrough ? 1 : 0,
                      file            => $file,
                      linenumber      => $linenumber,
                      pid             => $$,
                      ruid            => $<,
                      euid            => $>,
                      egid            => $),
                      mailgid         => getgrnam('mail') || '',
                      stacktrace      => $config{error_with_debuginfo}
                                         ? join('', map { s/^\s*//gm; $_ } ow::tool::stacktrace())
                                         : 0,
                      url_help        => -d "$config{ow_htmlurl}/help/$prefs{locale}"
                                         ? "$config{ow_htmlurl}/help/$prefs{locale}"
                                         : "$config{ow_htmlurl}/help/en_US.UTF-8",
                   );

   httpprint([], [$template->output]);

   autologin_rm(); # disable next autologin for specific ip/browser/user

   openwebmail_exit(1);
}

sub autoclosewindow {
   my ($title, $message, $seconds, $refresh_dirform) = @_;

   $seconds = 5 if !defined $seconds || $seconds < 3;

   my $template = HTML::Template->new(
                                        filename          => get_template('autoclose.tmpl'),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # autoclose.tmpl
                      message_title   => $title,
                      message         => $message,
                      seconds         => $seconds,
                      refresh_dirform => $refresh_dirform,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);

   openwebmail_exit(0);
}

sub writelog {
   my $logmessage = shift;

   return if !$config{logfile} || -l $config{logfile};

   my $timestamp  = localtime();

   my $loggedip   = ow::tool::clientip();

   my $loggeduser = $loginuser || 'UNKNOWNUSER';
   $loggeduser .= "\@$logindomain" if $config{auth_withdomain};
   $loggeduser .= "($user)" if defined $user && $user && $loginuser ne $user;

   my ($package, $filename, $line) = caller;

   ($filename) = $filename =~ m/[\\\/]([^\\\/]+)$/ if defined $filename && $filename;

   my $caller = (defined $filename && $filename ? $filename : '') .
                (defined $line && $line ? ":$line" : '');
   $caller = 'unknown caller' unless $caller;

   sysopen(LOGFILE, $config{logfile}, O_WRONLY|O_APPEND|O_CREAT) or
     openwebmailerror(gettext('Cannot open file:') . " $config{logfile} ($!)");

   seek(LOGFILE, 0, 2); # seek to tail

   print LOGFILE "$timestamp - [$$] ($loggedip) $loggeduser - $logmessage [[$caller]]\n"; # log

   close(LOGFILE) or
     openwebmailerror(gettext('Cannot close file:') . " $config{logfile} ($!)");

   return;
}

sub writehistory {
   my $historymessage = shift;

   return unless $config{enable_history};

   my $timestamp  = localtime();

   my $loggedip   = ow::tool::clientip();

   my $loggeduser = $loginuser || 'UNKNOWNUSER';
   $loggeduser .= "\@$logindomain" if $config{auth_withdomain};
   $loggeduser .= "($user)" if defined $user && $user && $loginuser ne $user;

   my $historyfile = dotpath('history.log');

   if (-f $historyfile) {
      ow::filelock::lock($historyfile, LOCK_EX) or
         openwebmailerror(gettext('Cannot lock file:') . " $historyfile ($!)");

      my $end   = (stat($historyfile))[7];
      my $start = $end - int($config{maxbooksize} * 1024 * 0.8);

      if ($end > ($config{maxbooksize} * 1024) ) {
         sysopen(HISTORYLOG, $historyfile, O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $historyfile ($!)");

         seek(HISTORYLOG, $start, 0);

         $_ = <HISTORYLOG>;

         $start += length($_);

         my $buff = '';

         read(HISTORYLOG, $buff, $end - $start);

         close(HISTORYLOG) or
            openwebmailerror(gettext('Cannot close file:') . " $historyfile ($!)");

         sysopen(HISTORYLOG, $historyfile, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(gettext('Cannot open file:') . " $historyfile ($!)");

         print HISTORYLOG $buff;
      } else {
         sysopen(HISTORYLOG, $historyfile, O_WRONLY|O_APPEND|O_CREAT) or
            openwebmailerror(gettext('Cannot open file:') . " $historyfile ($!)");

         seek(HISTORYLOG, $end, 0); # seek to tail
      }

      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $historymessage\n"; # log

      close(HISTORYLOG) or
         openwebmailerror(gettext('Cannot close file:') . " $historyfile ($!)");

      ow::filelock::lock($historyfile, LOCK_UN);

   } else {
      sysopen(HISTORYLOG, $historyfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $historyfile ($!)");

      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $historymessage\n"; # log

      close(HISTORYLOG) or
         openwebmailerror(gettext('Cannot close file:') . " $historyfile ($!)");
   }

   return 0;
}

sub decode_mimewords_iconv {
   # decode mimewords and iconv to the requested charset
   # mimeword example: =?CHARSET?(B|Q)?...?=
   my ($string, $tocharset) = @_;
   my @decoded_strings = ow::mime::decode_mimewords($string);

   my $result = '';
   foreach my $decoded_array (@decoded_strings) {
      my $decoded_string  = $decoded_array->[0];
      my $decoded_charset = $decoded_array->[1];
      $result .= (iconv($decoded_charset, $tocharset, $decoded_string))[0];
   }

   return $result;
}

sub update_authpop3book {
   my ($authpop3book, $domain, $user, $password) = @_;

   $authpop3book = ow::tool::untaint($authpop3book);
   if ($config{authpop3_getmail}) {
      my $login = $user;
      $login .= "\@$domain" if $config{auth_withdomain};

      my %accounts = ();
      $accounts{"$config{authpop3_server}:$config{authpop3_port}\@\@\@$login"} =
        join('@@@', $config{authpop3_server}, $config{authpop3_port}, $config{authpop3_usessl}, $login, $password, $config{authpop3_delmail}, 1);
      writepop3book($authpop3book, \%accounts);
   } else {
      unlink($authpop3book);
   }
}

sub safedomainname {
   my $domainname = shift;
   $domainname =~ s#\.\.+##g;
   $domainname =~ s#[^A-Za-z\d\_\-\.]##g; # safe chars only
   return $domainname;
}

sub safefoldername {
   my $foldername = shift;

   # dangerous char for path interpretation
   $foldername =~ s!\.\.+!!g;
   # $foldername =~ s!/!!g; # comment out because of sub folder

   # dangerous char at string begin/tail for perl file open
   $foldername =~ s!^\s*[\|\<\>]+!!g;
   $foldername =~ s![\|\<\>]+\s*$!!g;

   # all dangerous char within foldername
   if ($config{enable_strictfoldername}) {
      $foldername =~ s![\s\`\|\<\>/;&]+!_!g;
   }

   return $foldername;
}

sub is_safefoldername {
   # used before create folder
   my $foldername = shift;

   return 0 if (
                  $foldername =~ m#\.\.+#
                  || $foldername =~ m#^\s*[\|\<\>]+#
                  || $foldername =~ m#[\|\<\>]+\s*$#
               );

   if ($config{enable_strictfoldername}) {
      return 0 if $foldername =~ m#[\s\`\|\<\>/;&]+#;
   }

   return 1;
}

sub safedlname {
   my $dlname = shift;
   $dlname =~ s|/$||;
   $dlname =~ s|^.*/||; # unix path
   if (length($dlname) > 45) { # IE6 goes crazy if fname longer than 45, tricky!
      $dlname =~ m/^(.*)(\.[^\.]*)$/;
      $dlname = substr($1, 0, 45-length($2)) . $2;
   }
   $dlname =~ s|_*\._*|\.|g;
   $dlname =~ s|__+|_|g;
   return($dlname);
}

sub safexheaders {
   my $headers = shift;
   my $xheaders = '';

   foreach my $header (split("\n", $headers)) {
      $header =~ s/^\s*//; # strip leading whitespace
      $header =~ s/\s*$//; # strip trailing whitespace
      $xheaders .= "X-$1: $2\n" if $header =~ m/^[Xx]\-([\w\d\-_]+):\s*(.*)$/;
   }

   my $clientip = ow::tool::clientip();
   $xheaders =~ s/\@\@\@CLIENTIP\@\@\@/$clientip/g;

   my $userid = $loginuser;
   $userid .= "\@$logindomain" if $config{auth_withdomain};
   $xheaders =~ s/\@\@\@USERID\@\@\@/$userid/g;

   return $xheaders;
}

sub path2array {
   my $path = shift;

   my @p = ();

   foreach my $dir (split(/\//, $path)) {
      next if !defined $dir || $dir eq '.' || $dir eq '';

      if ($dir eq '..') {
         pop(@p); # remove ..
      } else {
         push(@p, $dir);
      }
   }

   return(@p);
}

sub absolute_vpath {
   my ($base, $vpath) = @_;
   $vpath = "$base/$vpath" unless $vpath =~ m|^/|;
   return('/' . join('/', path2array($vpath)));
}

sub fullpath2vpath {
   my ($realpath, $rootpath) = @_;

   my @p = path2array($realpath);

   foreach my $r (path2array($rootpath)) {
      my $part = shift(@p) || '';
      return if $r ne $part;
   }

   return('/' . join('/', @p));
}

sub verify_vpath {
   # given a path to a resource, verify that the resource is allowed to be accessed
   my ($rootpath, $vpath) = @_;

   my $filename = $vpath;
   $filename =~ s|.*/||;

   openwebmailerror(gettext('Access to hidden files has been disabled.'))
      if !$config{webdisk_lshidden} && $filename =~ m/^\./;

   my ($retcode, $realpath) = resolv_symlink("$rootpath/$vpath");

   # $retcode < 0 = more than 20 link resolutions to the actual file
   openwebmailerror(gettext('The symbolic link is too complex to be accessed.'))
      if $retcode < 0;

   if (-l "$rootpath/$vpath") {
      openwebmailerror(gettext('Access to symbolic links has been disabled.'))
         unless $config{webdisk_lssymlink};

      if (!$config{webdisk_allow_symlinkout}) {
         openwebmailerror(gettext('The requested file or directory is outside of the webdisk system and cannot be accessed.'))
            if fullpath2vpath($realpath, (resolv_symlink($rootpath))[1]) eq '';
      }
   }

   my $ow_sessionsdir_vpath = fullpath2vpath($realpath, (resolv_symlink($config{ow_sessionsdir}))[1]) || '';
   my $logfile_vpath = fullpath2vpath($realpath, (resolv_symlink($config{logfile}))[1]) || '';

   if ($ow_sessionsdir_vpath ne '') {
      writelog('webdisk error - attempt to hack sessions dir!');
      openwebmailerror(gettext('Access to the sessions directory is not allowed.'));
   }

   if ($config{logfile}) {
      if ($logfile_vpath ne '') {
         writelog('webdisk error - attempt to hack log file!');
         openwebmailerror(gettext('Access to the log file is not allowed.'));
      }
   }

   openwebmailerror(gettext('Access to mail folder files has been disabled.'))
      if !$config{webdisk_lsmailfolder} && is_under_dotdir_or_folderdir($realpath);

   openwebmailerror(gettext('Access to special unix file types has been disabled.'))
      if !$config{webdisk_lsunixspec} && (-e $realpath && !-d _ && !-f _);

   return 1;
}

sub resolv_symlink {
   my $link = shift;

   my @p      = path2array($link);
   my $i      = 0;
   my $path   = '';
   my $path0  = '';
   my %mapped = ();

   while(defined($_ = shift(@p)) && $i < 20) {
      $path0 = $path;
      $path .= "/$_";
      if (-l $path) {
         $path = readlink($path);
         if ($path =~ m|^/|) {
            unshift(@p, path2array($path));
            $path = '';
         } elsif ($path =~ m|\.\.|) {
            unshift(@p, path2array("$path0/$path"));
            $path = '';
         } else {
            unshift(@p, path2array($path));
            $path = $path0;
         }
         $i++;
      }
   }

   if ($i >= 20) {
      return(-1, $link);
   } else {
      return(0, $path);
   }
}

sub is_localuser {
   my $testuser = shift;

   foreach my $localuser (@{$config{localusers}}) {
      return 1 if $localuser eq $testuser;
   }

   return 0;
}

sub is_vdomain_adm {
   my $vdomainuser = shift;

   if (defined @{$config{vdomain_admlist}}) {
      foreach my $adm (@{$config{vdomain_admlist}}) {
         return 1 if $vdomainuser eq $adm;
      }
   }

   return 0;
}

sub vdomain_userspool {
   my ($vuser, $vhomedir) = @_;
   my $dest = '';
   my $spool = ow::tool::untaint("$config{vdomain_vmpop3_mailpath}/$domain/$vuser");

   if ($config{vdomain_mailbox_command}) {
      $dest = qq!| "$config{vdomain_mailbox_command}"!;
      $dest =~ s/<domain>/$domain/g;
      $dest =~ s/<user>/$vuser/g;
      $dest =~ s/<homedir>/$vhomedir/g;
      $dest =~ s/<spoolfile>/$spool/g;
   } else {
      $dest = $spool;
   }

   return $dest;
}

sub lenstr {
   my ($len, $bytestr) = @_;

   if ($len >= 1048576) {
      $len = int($len / 1048576 * 10 + 0.5) / 10 . ' ' . gettext('MB');
   } elsif ($len >= 2048) {
      $len = int(($len / 1024) + 0.5) . ' ' . gettext('KB');
   } else {
      $len = sprintf(ngettext('%d Byte', '%d Bytes', $len), $len) if $bytestr;
   }

   return $len;
}

sub dotpath {
   # return the path of files within openwebmail dot dir (~/.openwebmail/)
   # passing global $domain, $user, $homedir as parameters
   return _dotpath(shift, $domain, $user, $homedir);
}

sub _dotpath {
   # This _ version of routine is used by dotpath() and openwebmail-vdomain.pl
   # When vdomain adm has to determine dotpath for vusers,
   # the param of vuser($vdomain, $vuser, $vhomedir) will be passed
   # instead of the globals($domain, $user, $homedir), which are param of vdomain adm himself
   my ($name, $domain, $user, $homedir) = @_;

   $name = '' unless defined $name && $name ne '';

   my $dotdir = '';

   if ($config{use_syshomedir_for_dotdir}) {
      $dotdir = "$homedir/$config{homedirdotdirname}";
   } else {
      my $owuserdir = "$config{ow_usersdir}/" .
                      (($config{auth_withdomain} && defined $domain) ? "$domain/$user" : $user);

      $dotdir = "$owuserdir/$config{homedirdotdirname}";
   }

   return (ow::tool::untaint($dotdir))                 if $name eq '/';
   return (ow::tool::untaint("$dotdir/$name"))         if exists $_is_dotpath{root}{$name};
   return (ow::tool::untaint("$dotdir/webmail/$name")) if exists $_is_dotpath{webmail}{$name} || $name =~ m/^filter\.book/;
   return (ow::tool::untaint("$dotdir/webaddr/$name")) if exists $_is_dotpath{webaddr}{$name};
   return (ow::tool::untaint("$dotdir/webcal/$name"))  if exists $_is_dotpath{webcal}{$name};
   return (ow::tool::untaint("$dotdir/webdisk/$name")) if exists $_is_dotpath{webdisk}{$name};
   return (ow::tool::untaint("$dotdir/pop3/$name"))    if exists $_is_dotpath{pop3}{$name} || $name =~ m/^uidl\./;

   $name =~ s#^/+##;
   return (ow::tool::untaint("$dotdir/$name"));
}

sub find_and_move_dotdir {
   # move .openwebmail to right location automatically
   # if option use_syshomedir_for_dotdir is changed from yes(default) to no
   my ($syshomedir, $owuserdir) = @_;

   my $dotdir_in_syshome = $config{use_syshomedir} && $config{use_syshomedir_for_dotdir};
   my $syshomedotdir     = ow::tool::untaint("$syshomedir/$config{homedirdotdirname}");
   my $owuserdotdir      = ow::tool::untaint("$owuserdir/$config{homedirdotdirname}");

   my $src = '';
   my $dst = '';

   if ($dotdir_in_syshome && -d $owuserdotdir && !-d $syshomedotdir) {
      ($src, $dst) = ($owuserdotdir, $syshomedotdir);
   } elsif (!$dotdir_in_syshome && -d $syshomedotdir && !-d $owuserdotdir) {
      ($src, $dst) = ($syshomedotdir, $owuserdotdir);
   } else {
      return;
   }

   # TODO: rewrite this in portable perl. Dependant switches.
   # TODO: System calls. No error reporting or checking. YUCK.
   # try 'mv' first, then 'cp+rm'
   if (system(ow::tool::findbin('mv'), '-f', $src, $dst) == 0 or
         (system(ow::tool::findbin('cp'), '-Rp', $src, $dst) == 0 and system(ow::tool::findbin('rm'), '-Rf', $src) == 0)) {
      writelog("move dotdir - $src -> $dst");
   }
}

sub check_and_create_dotdir {
   my $dotdir = shift;

   foreach  ('/', 'db', keys %_is_dotpath) {
      next if $_ eq 'root';
      my $p = ow::tool::untaint($dotdir);
      $p .= "/$_" if $_ ne '/';
      if (!-d $p) {
         mkdir($p, 0700) or
            openwebmailerror(gettext('Cannot create directory:') . " $p ($!)");
         writelog("create dir - $p, euid=$>, egid=$)");
      }
   }
}

sub is_under_dotdir_or_folderdir {
   my $file = shift;

   my $spoolfile = (get_folderpath_folderdb($user, 'INBOX'))[0];

   foreach (dotpath('/'), "$homedir/$config{homedirfolderdirname}", $spoolfile) {
      my $p = (resolv_symlink($_))[1];
      return 1 if fullpath2vpath($file, $p) ne '';
   }

   return 0;
}

sub autologin_add {
   # we store ip and browsername in autologin db,
   # so a user may have different autologin settings on different computer
   # or even different browsers on same computer
   my $agentip = $ENV{HTTP_USER_AGENT} . ow::tool::clientip();
   my $autologindb = dotpath('autologin.check');

   my (%DB, $timestamp);

   return 0 if (!ow::dbm::opendb(\%DB, $autologindb, LOCK_EX));

   $timestamp = time();

   foreach my $key (%DB) {
      delete $DB{$key} if $timestamp - $DB{$key} > 86400 * 7;
   }

   $DB{$agentip} = $timestamp;
   ow::dbm::closedb(\%DB, $autologindb);
   return 1;
}

sub autologin_rm {
   my $agentip = $ENV{HTTP_USER_AGENT} . ow::tool::clientip();
   my $autologindb = dotpath('autologin.check');

   my %DB;

   return 0 unless ow::dbm::existdb($autologindb);
   return 0 unless ow::dbm::opendb(\%DB, $autologindb, LOCK_EX);
   delete $DB{$agentip};
   ow::dbm::closedb(\%DB, $autologindb);
   return 1;
}

sub autologin_check {
   my $agentip = $ENV{HTTP_USER_AGENT} . ow::tool::clientip();
   my $autologindb = dotpath('autologin.check');

   my (%DB, $timestamp);

   return 0 unless ow::dbm::existdb($autologindb);
   return 0 unless ow::dbm::opendb(\%DB, $autologindb, LOCK_EX);
   $DB{$agentip} = $timestamp = time() if defined $DB{$agentip};
   ow::dbm::closedb(\%DB, $autologindb);
   return 1 if $timestamp ne '';
}

sub get_defaultfolders {
   my @f = ();
   foreach (
              grep { $_is_defaultfolder{$_} < 8 }
              sort { $_is_defaultfolder{$a} <=> $_is_defaultfolder{$b} }
              keys %_is_defaultfolder
           ) {
      next if defined $_folder_config{$_} && !$config{$_folder_config{$_}};
      push(@f, $_);
   }
   return(@f);
}

sub is_defaultfolder {
   return 0 if exists $_folder_config{$_[0]} && !$config{$_folder_config{$_[0]}};
   return 1 if exists $_is_defaultfolder{$_[0]} && $_is_defaultfolder{$_[0]};
   return 0;
}

sub is_defaultabookfolder {
   return 1 if exists $_is_defaultabookfolder{$_[0]} && $_is_defaultabookfolder{$_[0]};
   return 0;
}

sub getfolders {
   # return list of valid folders and size of INBOX and other folders
   my ($r_folders, $r_inboxusage, $r_folderusage) = @_;

   my @userfolders = ();
   my $totalsize   = 0;

   my $spoolfile = (get_folderpath_folderdb($user, 'INBOX'))[0];
   my $folderdir = "$homedir/$config{homedirfolderdirname}";

   my (@fdirs, $fdir, @folderfiles, $filename);
   @fdirs = ($folderdir); # start with root folderdir

   while ($fdir = pop(@fdirs)) {
      opendir(FOLDERDIR, $fdir) or
    	 openwebmailerror(gettext('Cannot open directory:') . ' ' . f2u($fdir) . " ($!)");

      @folderfiles = readdir(FOLDERDIR);

      closedir(FOLDERDIR) or
         openwebmailerror(gettext('Cannot close directory:') . ' ' . f2u($folderdir) . " ($!)");

      foreach $filename (@folderfiles) {
         next if substr($filename,0,1) eq '.' || $filename =~ m/\.lock$/;

         if (-d "$fdir/$filename" && $config{enable_userfolders}) { # recursive into non dot dir
            push(@fdirs, "$fdir/$filename");
            next;
         }

         # do not count spoolfile in folder finding
         next if ("$fdir/$filename" eq $spoolfile);

         # distingush default folders and user folders
         if (is_defaultfolder($filename) && $fdir eq $folderdir) {
            $totalsize += (-s "$folderdir/$filename");
         } else {
            if ($config{enable_userfolders}) {
               $totalsize += (-s "$folderdir/$filename");
               push(@userfolders, substr("$fdir/$filename", length($folderdir) + 1));
            }
         }

      }
   }

   @{$r_folders} = get_defaultfolders();
   push(@{$r_folders}, sort(@userfolders));

   ${$r_inboxusage}  = 0;
   ${$r_inboxusage}  = (-s $spoolfile) / 1024 if -f $spoolfile;
   ${$r_folderusage} = $totalsize / 1024; # unit=k
   return;
}

sub get_folderpath_folderdb {
   my ($username, $foldername) = @_;

   my ($folderfile, $folderdb);

   if ($foldername eq 'INBOX') {
      if ($config{use_homedirspools}) {
         $folderfile = "$homedir/$config{homedirspoolname}";
      } elsif ($config{use_hashedmailspools}) {
         $folderfile = "$config{mailspooldir}/" . substr($username,0,1) . "/" . substr($username,1,1) . "/$username";
      } else {
         $folderfile = "$config{mailspooldir}/$username";
      }
      $folderdb = dotpath('db') . "/$username";
   } elsif ($foldername eq 'DELETE') {
      $folderfile = $folderdb = '';
   } else {
      $folderdb = $foldername;
      $folderdb =~ s!/!#!g;
      $folderdb = dotpath('db') . "/$folderdb";

      $folderfile = "$homedir/$config{homedirfolderdirname}/$foldername";
   }

   return(ow::tool::untaint($folderfile), ow::tool::untaint($folderdb));
}

sub del_staledb {
   # remove stale folder index db/cache/lock file
   my ($user, $r_folders) = @_;

   my $dbdir = dotpath('db');

   my %is_valid = ();
   foreach my $foldername (@{$r_folders}) {
      my $dbname = (get_folderpath_folderdb($user, $foldername))[1];
      $dbname =~ s#^$dbdir/##;
      $is_valid{$dbname} = 1;
   }

   my @delfiles = ();

   opendir(DBDIR, $dbdir) or
      openwebmailerror(gettext('Cannot open directory:') . ' ' . f2u($dbdir) . " ($!)");

   my @dbfiles = readdir(DBDIR);

   closedir(DBDIR) or
      openwebmailerror(gettext('Cannot close directory:') . ' ' . f2u($dbdir) . " ($!)");

   foreach my $filename (@dbfiles) {
      next if $filename =~ m/^\.\.?/;

      my $purename = $filename;
      $purename =~ s/\.(lock|cache|db|dir|pag|db\.lock|dir\.lock|pag\.lock)$//;
      if (!$is_valid{$purename}) {
         push(@delfiles, ow::tool::untaint("$dbdir/$filename"));
      }
   }

   if (scalar @delfiles > 0) {
      writelog("del staledb - " . join(", ", @delfiles));
      unlink(@delfiles);
   }
}

sub get_user_abookfolders {
   my $webaddrdir = dotpath('webaddr');

   opendir(WEBADDR, $webaddrdir) or
      openwebmailerror(gettext('Cannot open directory:') . " $webaddrdir ($!)");

   my @books = sort { $a cmp $b }
               grep {
                      m/^[^.]/
                      && !m/^categories\.cache$/
                      && !-f "$config{ow_addressbooksdir}/$_"
                      && -r "$webaddrdir/$_"
                    }
               readdir(WEBADDR);

   closedir(WEBADDR) or
      openwebmailerror(gettext('Cannot close directory:') . " $webaddrdir ($!)");

   return @books;
}

sub get_global_abookfolders {
   opendir(WEBADDR, $config{ow_addressbooksdir}) or
      openwebmailerror(gettext('Cannot open directory:') . " $config{ow_addressbooksdir} ($!)");

   my @books = sort { $a cmp $b }
               grep {
                      m/^[^.]/
                      && (
                           -r "$config{ow_addressbooksdir}/$_"
                           || (m/^ldapcache$/ && $config{enable_ldap_abook})
                         )
                    }
               readdir(WEBADDR);

   closedir(WEBADDR) or
      openwebmailerror(gettext('Cannot close directory:') . " $config{ow_addressbooksdir} ($!)");

   return @books;
}

sub get_readable_abookfolders {
   my @userbooks   = get_user_abookfolders();
   my @globalbooks = get_global_abookfolders();
   return(@userbooks, @globalbooks);
}

sub abookfolder2file {
   # given a folder name, return the full path to the folder file
   my $abookfoldername = shift;

   if ($abookfoldername eq 'ALL') {
      return '/nonexistent';
   } elsif (is_abookfolder_global($abookfoldername)) {
      return ow::tool::untaint("$config{ow_addressbooksdir}/$abookfoldername");
   } else {
      my $webaddrdir = dotpath('webaddr');
      return ow::tool::untaint("$webaddrdir/$abookfoldername");
   }
}

sub is_abookfolder_global {
   my $abookfoldername = shift;
   return 0 unless defined $abookfoldername;
   return 1 if $abookfoldername =~ m/^(?:global|ldapcache)$/;
   return 1 if -f "$config{ow_addressbooksdir}/$abookfoldername";
   return 0;
}

sub f2u {
   # convert string from filesystem charset to userprefs charset
   my $string = shift;
   my $localecharset = (ow::lang::localeinfo($prefs{locale}))[4];
   return (iconv($prefs{fscharset}, $localecharset, $string))[0];
}

sub u2f {
   # convert string from userprefs charset to filesystem charset
   my $string = shift;
   my $localecharset = (ow::lang::localeinfo($prefs{locale}))[4];
   return (iconv($localecharset, $prefs{fscharset}, $string))[0];
}

sub loadlang {
   my $localename = shift;

   if (-f "$config{ow_langdir}/$localename.po") {
      return OWM::PO->new(file => "$config{ow_langdir}/$localename.po");
   } else {
      return OWM::PO->new(file => "$config{ow_langdir}/en_US.UTF-8.po");
   }
}

sub gettext  {
   my $msgstr = shift;

   my $result = '';

   if ($msgstr =~ s/\\n/\n/g) {
      $result = defined $po->msgstr($msgstr) ? $po->msgstr($msgstr) : "$msgstr";
      $result =~ s/\n/\\n/g;
   } else {
      $result = defined $po->msgstr($msgstr) ? $po->msgstr($msgstr) : "$msgstr";
   }

   return $result;
}

sub ngettext { defined $po->msgstr($_[0], $_[-1]) ? $po->msgstr($_[0], $_[-1]) : "[$_[0]]" }

sub openwebmail_exit {
   openwebmail_requestend();
   my $exitcode = shift;
   $exitcode = 1 if $exitcode !~ m/^\d+$/; # user stop (PIPE or TERM)
   exit $exitcode;
}

1;
