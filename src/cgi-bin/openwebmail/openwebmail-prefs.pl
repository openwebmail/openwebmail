#!/usr/bin/suidperl -T
#
# openwebmail-prefs.pl - preference configuration, book editing program
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1 }
if ($SCRIPT_DIR eq '' && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { $SCRIPT_DIR=$1 }
}
if ($SCRIPT_DIR eq '') { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

foreach (qw(ENV BASH_ENV CDPATH IFS TERM)) {delete $ENV{$_}}; $ENV{PATH}='/bin:/usr/bin'; # secure ENV
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "modules/htmltext.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/pop3book.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw($persistence_count);
use vars qw(@openwebmailrcitem); # defined in ow-shared.pl
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err
            %lang_calendar %lang_onofflabels %lang_sortlabels
            %lang_disableemblinklabels %lang_msgformatlabels
            %lang_withoriglabels %lang_receiptlabels
            %lang_ctrlpositionlabels %lang_sendpositionlabels
            %lang_checksourcelabels
            %lang_abookbuttonpositionlabels %lang_abooksortlabels
	    %lang_timelabels %lang_wday);	# defined in lang/xy
use vars qw(%charset_convlist);			# defined in iconv.pl
use vars qw(%fontsize %is_config_option);	# defined in ow-shared.pl

# local globals
use vars qw($folder $messageid);
use vars qw($sort $page);
use vars qw($userfirsttime $prefs_caller);
use vars qw($urlparmstr $formparmstr);
use vars qw($escapedfolder $escapedmessageid);

# const globals
use vars qw(%op_order %ruletype_order %folder_order);	# filterrule prefered order, the smaller one is prefered
%op_order=(
   copy   => 0,
   move   => 1,
   delete => 2,
);
%ruletype_order=(
   from        => 0,
   to          => 1,
   subject     => 2,
   header      => 3,
   smtprelay   => 4,
   attfilename => 5,
   textcontent => 6
);
%folder_order=(		# folders not listed have order 0
   INBOX        => -1,
   DELETE       => 1,
   'virus-mail' => 2,
   'spam-mail'  => 3,
   'mail-trash' => 4
);

########## MAIN ##################################################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop
$SIG{CHLD}='IGNORE';		# prevent zombie

userenv_init();

$folder = param('folder') || 'INBOX';
$messageid=param('message_id') || '';
$page = param('page') || 1;
$sort = param('sort') || $prefs{'sort'} || 'date';
$userfirsttime = param('userfirsttime')||0;

$prefs_caller = param('prefs_caller')||'';	# passed from the caller
$prefs_caller='main' if ($prefs_caller eq '' && $config{'enable_webmail'});
$prefs_caller='cal' if ($prefs_caller eq '' && $config{'enable_calendar'});
$prefs_caller='webdisk' if ($prefs_caller eq '' && $config{'enable_webdisk'});

$escapedfolder=ow::tool::escapeURL($folder);
$escapedmessageid=ow::tool::escapeURL($messageid);

$urlparmstr=qq|&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;sort=$sort&amp;page=$page&amp;userfirsttime=$userfirsttime&amp;prefs_caller=$prefs_caller|;
$formparmstr=ow::tool::hiddens(sessionid=>$thissession,
                               folder=>$folder,
                               message_id=>$messageid,
                               sort=>$sort,
                               page=>$page,
                               userfirsttime=>$userfirsttime,
                               prefs_caller=>$prefs_caller);

my $action = param('action')||'';
if ($action eq "about" && $config{'enable_about'}) {
   about();
} elsif ($action eq "userfirsttime") {
   userfirsttime();
} elsif ($action eq "timeoutwarning") {
   timeoutwarning();
} elsif ($action eq "editprefs" && $config{'enable_preference'}) {
   editprefs();
} elsif ($action eq "saveprefs" && $config{'enable_preference'}) {
   saveprefs();
} elsif ($action eq "editpassword" && $config{'enable_changepwd'}) {
   editpassword();
} elsif ($action eq "changepassword" && $config{'enable_changepwd'}) {
   changepassword();
} elsif ($action eq "viewhistory" && $config{'enable_history'}) {
   viewhistory();
} elsif ($config{'enable_webmail'}) {
   if ($action eq "editfroms" && $config{'enable_editfrombook'}) {
      editfroms();
   } elsif ($action eq "addfrom" && $config{'enable_editfrombook'}) {
      modfrom("add");
   } elsif ($action eq "deletefrom" && $config{'enable_editfrombook'}) {
      modfrom("delete");
   } elsif ($action eq "editpop3" && $config{'enable_pop3'}) {
      editpop3();
   } elsif ($action eq "addpop3" && $config{'enable_pop3'}) {
      modpop3("add");
   } elsif ($action eq "deletepop3" && $config{'enable_pop3'}) {
      modpop3("delete");
   } elsif ($action eq "editfilter" && $config{'enable_userfilter'}) {
      editfilter();
   } elsif ($action eq "addfilter" && $config{'enable_userfilter'}) {
      modfilter("add");
   } elsif ($action eq "deletefilter" && $config{'enable_userfilter'}) {
      modfilter("delete");
   } elsif (param('delstatbutton') && $config{'enable_stationery'}) {
      delstat();
   } elsif ((param('editstatbutton')||$action eq "editstat") && $config{'enable_stationery'}) {
      editstat();
   } elsif ($action eq "clearstat" && $config{'enable_stationery'}) {
      clearstat();
   } elsif ($action eq "addstat" && $config{'enable_stationery'}) {
      addstat();
   } else {
      openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
   }
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}

openwebmail_requestend();
########## END MAIN ##############################################

########## ABOUT #################################################
sub about {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("about.template"));

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   if ($config{'about_info_software'}) {
      templateblock_enable($html, 'INFOSOFTWARE');
      my $os=`/bin/uname -srm`; $os=`/usr/bin/uname -srm` if ( -f "/usr/bin/uname");
      my $flag; $flag.='Persistence' if ($persistence_count>0);
      if (is_http_compression_enabled()) {
         $flag.=', ' if ($flag ne '');
         $flag.='HTTP Compression';
      }
      $flag="( $flag )" if ($flag);
      $temphtml = attr_html('OS'     , $os).
                  attr_html('PERL'   , "$^X $]").
                  attr_html('WebMail', "$config{'name'} $config{'version'} $config{'releasedate'} $flag");
      $html=~s/\@\@\@INFOSOFTWARE\@\@\@/$temphtml/;
   } else {
      templateblock_disable($html, 'INFOSOFTWARE');
   }

   if ($config{'about_info_protocol'}) {
      templateblock_enable($html, 'INFOPROTOCOL');
      $temphtml = '';
      foreach my $attr ( qw(SERVER_PROTOCOL HTTP_CONNECTION HTTP_KEEP_ALIVE) ) {
         $temphtml.= attr_html($attr, $ENV{$attr}) if (defined($ENV{$attr}));
      }
      $html=~s/\@\@\@INFOPROTOCOL\@\@\@/$temphtml/;
   } else {
      templateblock_disable($html, 'INFOPROTOCOL');
   }

   if ($config{'about_info_server'}) {
      templateblock_enable($html, 'INFOSERVER');
      $temphtml = '';
      foreach my $attr ( qw(HTTP_HOST SCRIPT_NAME) ) {
         $temphtml.= attr_html($attr, $ENV{$attr}) if (defined($ENV{$attr}));
      }
      if ($config{'about_info_scriptfilename'}) {
         $temphtml.= attr_html('SCRIPT_FILENAME', $ENV{'SCRIPT_FILENAME'}) if (defined($ENV{'SCRIPT_FILENAME'}));
      }
      foreach my $attr ( qw(SERVER_NAME SERVER_ADDR SERVER_PORT SERVER_SOFTWARE) ) {
         $temphtml.= attr_html($attr, $ENV{$attr}) if (defined($ENV{$attr}));
      }
      $html=~s/\@\@\@INFOSERVER\@\@\@/$temphtml/;
   } else {
      templateblock_disable($html, 'INFOSERVER');
   }

   if ($config{'about_info_client'}) {
      templateblock_enable($html, 'INFOCLIENT');
      $temphtml = '';
      foreach my $attr ( qw(REMOTE_ADDR REMOTE_PORT HTTP_CLIENT_IP
                            HTTP_X_FORWARDED_FOR HTTP_VIA
                            HTTP_USER_AGENT HTTP_ACCEPT_ENCODING HTTP_ACCEPT_LANGUAGE) ) {
         $temphtml.= attr_html($attr, $ENV{$attr}) if (defined($ENV{$attr}));
      }
      $html=~s/\@\@\@INFOCLIENT\@\@\@/$temphtml/;
   } else {
      templateblock_disable($html, 'INFOCLIENT');
   }

   httpprint([], [htmlheader(), $html, htmlfooter(1)]);
}

sub attr_html {
   my $temphtml = qq|<tr>|.
                  qq|<td bgcolor=$style{'window_dark'}>$_[0]</td>|.
                  qq|<td bgcolor=$style{'window_dark'}>$_[1]</td>|.
                  qq|</tr>\n|;
   return($temphtml);
}
########## END ABOUT #############################################

########## FIRSTTIMEUSER #########################################
sub userfirsttime {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("userfirsttime.template"));

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl").
               ow::tool::hiddens(action=>'editprefs',
                                 sessionid=>$thissession,
                                 userfirsttime=>'1').
               submit("$lang_text{'continue'}").
               end_form();
   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END FIRSTTIMEUSER #####################################

########## EDITPREFS #############################################
sub editprefs {
   if (param('language') =~ /^([\d\w\.\-_]+)$/ ) {
      my $language=$1;
      if ( -f "$config{'ow_langdir'}/$language" ) {
         $prefs{'language'}=$language;
         $prefs{'charset'}=$ow::lang::languagecharsets{$language};
         loadlang($language);
      }
   }

   my ($html, $temphtml);
   $html = applystyle(readtemplate("prefs.template"));

   if ($userfirsttime) {	# simple prefs menu, most items become hidden
      templateblock_disable($html, 'FULLPREFS');
      $html =~ s/\@\@\@DESCWIDTH\@\@\@/width="40%"/;

      my (%is_firsttimercitem, %hiddenvalue);
      foreach (qw(language charset timeoffset daylightsaving email replyto signature)) { $is_firsttimercitem{$_}=1 }
      foreach (@openwebmailrcitem) {
         next if ($is_firsttimercitem{$_});
         if ($_ eq 'bgurl') {
            my ($background, $bgurl)=($prefs{'bgurl'}, '');
            if ($background !~ s!$config{'ow_htmlurl'}/images/backgrounds/!!) {
               ($background, $bgurl)=('USERDEFINE', $prefs{'bgurl'});
            }
            @hiddenvalue{'background', 'bgurl'}=($background, $bgurl);
         } else {
            $hiddenvalue{$_}=$prefs{$_};
         }
      }
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                             -name=>'prefsform').
                  ow::tool::hiddens(action=>'saveprefs').
                  ow::tool::hiddens(%hiddenvalue).
                  $formparmstr;

   } else {			# full prefs menu
      templateblock_enable($html, 'FULLPREFS');
      $html =~ s/\@\@\@DESCWIDTH\@\@\@//;

      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                             -name=>'prefsform').
                  ow::tool::hiddens(action=>'saveprefs').
                  $formparmstr;
   }
   $html =~ s/\@\@\@STARTPREFSFORM\@\@\@/$temphtml/;

   if ($config{'quota_module'} ne "none") {
      $temphtml='';
      my $overthreshold=($quotalimit>0 && $quotausage/$quotalimit>$config{'quota_threshold'}/100);
      if ($config{'quota_threshold'}==0 || $overthreshold) {
         $temphtml = "$lang_text{'quotausage'}: ".lenstr($quotausage*1024,1);
      }
      if ($overthreshold) {
         $temphtml.=" (".(int($quotausage*1000/$quotalimit)/10)."%) ";
      }
   } else {
      $temphtml="&nbsp;";
   }
   $html =~ s/\@\@\@QUOTAUSAGE\@\@\@/$temphtml/;

   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, dotpath('from.book'));

   if ($userfrom{$prefs{'email'}}) {
      $temphtml = $userfrom{$prefs{'email'}};
   } else {
      $temphtml = "&nbsp;";
   }
   $html =~ s/\@\@\@REALNAME\@\@\@/$temphtml/;

   $temphtml = '';
   if (!$userfirsttime) {
      if ($prefs_caller eq "cal") {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'calendar'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=$prefs{'calendar_defaultview'}&amp;$urlparmstr"|);
      } elsif ($prefs_caller eq "webdisk") {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'webdisk'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=showdir&amp;$urlparmstr"|);
      } elsif ($prefs_caller eq "read") {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder), qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;$urlparmstr"|);
      } elsif ($prefs_caller eq "addrlistview") {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'addressbook'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;$urlparmstr"|);
      } else {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder), qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;$urlparmstr"|);
      }
      $temphtml .= qq|&nbsp;\n|;

      if ($config{'enable_webmail'}) {
         if ($config{'enable_editfrombook'}) {
            $temphtml .= iconlink("editfroms.gif", $lang_text{'editfroms'}, qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfroms&amp;$urlparmstr"|);
         }
         if ($config{'enable_stationery'}) {
            $temphtml .= iconlink("editst.gif", $lang_text{'editstat'}, qq|accesskey="S" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editstat&amp;$urlparmstr"|);
         }
         if ($config{'enable_pop3'}) {
            $temphtml .= iconlink("pop3setup.gif", $lang_text{'pop3book'}, qq|accesskey="G" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&amp;$urlparmstr"|);
         }
      }
      $temphtml .= qq|&nbsp;\n|;

      if ( $config{'enable_changepwd'}) {
         $temphtml .= iconlink("chpwd.gif", $lang_text{'changepwd'}, qq|accesskey="P" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpassword&amp;$urlparmstr"|);
      }
      if ( $config{'enable_vdomain'} ) {
         if (is_vdomain_adm($user)) {
            $temphtml .= iconlink("vdusers.gif", $lang_text{'vdomain_usermgr'}, qq|accesskey="P" href="$config{'ow_cgiurl'}/openwebmail-vdomain.pl?action=display_vuserlist&amp;$urlparmstr"|);
         }
      }
      if ($config{'enable_history'}) {
         $temphtml .= iconlink("history.gif", $lang_text{'viewhistory'}, qq|accesskey="V" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=viewhistory&amp;$urlparmstr"|);
      }
   }

   if ($config{'enable_about'}) {
      $temphtml .= iconlink("info.gif", $lang_text{'about'}, qq|accesskey="I" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=about&amp;$urlparmstr"|);
   }
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;


   my $defaultlanguage=$prefs{'language'};
   my $defaultcharset=$prefs{'charset'}||$ow::lang::languagecharsets{$prefs{'language'}};
   my $defaultsendcharset=$prefs{'sendcharset'}||'sameascomposing';
   if (param('language') =~ /^([\d\w\.\-_]+)$/ ) {
      $defaultlanguage=$1;
      $defaultcharset=$ow::lang::languagecharsets{$1};
      if ($defaultlanguage =~ /^ja_JP/ ) {
         $defaultsendcharset='iso-2022-jp';
      } else {
         $defaultsendcharset='sameascomposing';
      }
   }

   my @availablelanguages = sort {
                                 $ow::lang::languagenames{$a} cmp $ow::lang::languagenames{$b}
                                 } keys(%ow::lang::languagenames);
   $temphtml = popup_menu(-name=>'language',
                          -values=>\@availablelanguages,
                          -default=>$defaultlanguage,
                          -labels=>\%ow::lang::languagenames,
                          -onChange=>"javascript:if (this.value != null) { window.location.href='$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr&amp;language='+this.value; }",
                          -accesskey=>'1',
                          -override=>'1',
                          defined($config_raw{'DEFAULT_language'})?('-disabled'=>'1'):());
   $html =~ s/\@\@\@LANGUAGEMENU\@\@\@/$temphtml/;

   my %tmpset=reverse %ow::lang::languagecharsets;
   my @charset=sort keys %tmpset;
   $temphtml = popup_menu(-name=>'charset',
                          -values=>\@charset,
                          -default=>$defaultcharset,
                          -override=>'1');
   $html =~ s/\@\@\@CHARSETMENU\@\@\@/$temphtml/;

   my @timeoffsets=qw( -1200 -1100 -1000 -0900 -0800 -0700
                       -0600 -0500 -0400 -0330 -0300 -0230 -0200 -0100
                       +0000 +0100 +0200 +0300 +0330 +0400 +0500 +0530 +0600 +0630
                       +0700 +0800 +0900 +0930 +1000 +1030 +1100 +1200 +1300 );
   $temphtml = popup_menu(-name=>'timeoffset',
                          -values=>\@timeoffsets,
                          -default=>$prefs{'timeoffset'},
                          -override=>'1',
                          defined($config_raw{'DEFAULT_timeoffset'})?('-disabled'=>'1'):()).
               qq|&nbsp;|. iconlink("earth.gif", $lang_text{'tzmap'}, qq|href="$config{'ow_htmlurl'}/images/timezone.jpg" target="_timezonemap"|). qq|\n|;
   $html =~ s/\@\@\@TIMEOFFSETMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'daylightsaving',
                         -values=>[ 'auto', 'on', 'off' ],
                         -labels=>\%lang_onofflabels,
                         -default=>$prefs{'daylightsaving'},
                         -override=>'1',
                         defined($config_raw{'DEFAULT_daylightsaving'})?('-disabled'=>'1'):());
   $html =~ s/\@\@\@DAYLIGHTSAVINGMENU\@\@\@/$temphtml/;

   if ($config{'enable_webmail'}) {
      templateblock_enable($html, 'WEBMAIL');
      my @fromemails=sort_emails_by_domainnames($config{'domainnames'}, keys %userfrom);
      my %fromlabels;
      foreach (@fromemails) {
         if ($userfrom{$_}) {
            $fromlabels{$_}=qq|"$userfrom{$_}" <$_>|;
         } else {
            $fromlabels{$_}=qq|$_|;
         }
      }
      $temphtml = popup_menu(-name=>'email',
                             -values=>\@fromemails,
                             -labels=>\%fromlabels,
                             -default=>$prefs{'email'},
                             -override=>'1');
      if ($config{'enable_editfrombook'}) {
         $temphtml .= "&nbsp;".iconlink("editfroms.s.gif", $lang_text{'editfroms'}, qq|href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfroms&amp;$urlparmstr"|). qq| \n|;
      }
      $html =~ s/\@\@\@FROMEMAILMENU\@\@\@/$temphtml/;

      $temphtml = textfield(-name=>'replyto',
                            -default=>$prefs{'replyto'} || '',
                            -size=>'40',
                            -override=>'1');
      $html =~ s/\@\@\@REPLYTOFIELD\@\@\@/$temphtml/;

      # read .forward, also see if autoforwarding is on
      my ($autoreply, $keeplocalcopy, @forwards)=readdotforward();
      if ($config{'enable_setforward'}) {
         templateblock_enable($html, 'FORWARD');
         my $forwardaddress='';
         $forwardaddress = join(",", @forwards) if ($#forwards >= 0);
         $temphtml = textfield(-name=>'forwardaddress',
                               -default=>$forwardaddress,
                               -size=>'30',
                               -override=>'1');
         $html =~ s/\@\@\@FORWARDADDRESS\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'keeplocalcopy',
                              -value=>'1',
                              -checked=>$keeplocalcopy,
                              -label=>'');
         $html =~ s/\@\@\@KEEPLOCALCOPY\@\@\@/$temphtml/;
      } else {
         templateblock_disable($html, 'FORWARD');
      }

      if ($config{'enable_autoreply'}) {
         templateblock_enable($html, 'AUTOREPLY');
         # whether autoreply active or not is determined by
         # if .forward is set to call vacation program, not in .openwebmailrc
         my ($autoreplysubject, $autoreplytext)=readdotvacationmsg();

         $temphtml = checkbox(-name=>'autoreply',
                              -value=>'1',
                              -checked=>$autoreply,
                              -label=>'');
         $html =~ s/\@\@\@AUTOREPLYCHECKBOX\@\@\@/$temphtml/;

         $temphtml = textfield(-name=>'autoreplysubject',
                               -default=>$autoreplysubject,
                               -size=>'40',
                               -override=>'1');
         $html =~ s/\@\@\@AUTOREPLYSUBJECT\@\@\@/$temphtml/;

         $temphtml = textarea(-name=>'autoreplytext',
                              -default=>$autoreplytext,
                              -rows=>'5',
                              -columns=>$prefs{'editcolumns'}||'78',
                              -wrap=>'hard',
                              -override=>'1');
         $html =~ s/\@\@\@AUTOREPLYTEXT\@\@\@/$temphtml/;
      } else {
         templateblock_disable($html, 'AUTOREPLY');
         $html =~ s/\@\@\@AUTOREPLYCHECKBOX\@\@\@/not available/;
         $html =~ s/\@\@\@AUTOREPLYSUBJECT\@\@\@/not available/;
         $html =~ s/\@\@\@AUTOREPLYTEXT\@\@\@/not available/;
      }

      $temphtml = textarea(-name=>'signature',
                           -default=>$prefs{'signature'},
                           -rows=>'5',
                           -columns=>$prefs{'editcolumns'}||'78',
                           -wrap=>'hard',
                           -override=>'1',
                           defined($config_raw{'DEFAULT_signature'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@SIGAREA\@\@\@/$temphtml/;
   } else {
      templateblock_disable($html, 'WEBMAIL');
   }

   if (!$userfirsttime) {
      # Get a list of valid style files
      my @styles;
      opendir(STYLESDIR, "$config{'ow_stylesdir'}") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_stylesdir'} directory for reading! ($!)");
      while (defined(my $currstyle = readdir(STYLESDIR))) {
         if ($currstyle =~ /^([^\.].*)$/) {
            push (@styles, $1);
         }
      }
      @styles = sort(@styles);
      closedir(STYLESDIR) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'ow_stylesdir'}! ($!)");

      $temphtml = popup_menu(-name=>'style',
                             -values=>\@styles,
                             -default=>$prefs{'style'},
                             -accesskey=>'2',
                             -override=>'1',
                             defined($config_raw{'DEFAULT_style'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@STYLEMENU\@\@\@/$temphtml/;

      # Get a list of valid iconset
      my @iconsets;
      opendir(ICONSETSDIR, "$config{'ow_htmldir'}/images/iconsets") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_htmldir'}/images/iconsets directory for reading! ($!)");
      while (defined(my $currset = readdir(ICONSETSDIR))) {
         if (-d "$config{'ow_htmldir'}/images/iconsets/$currset" && $currset =~ /^([^\.].*)$/) {
            push (@iconsets, $1);
         }
      }
      @iconsets = sort(@iconsets);
      closedir(ICONSETSDIR) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'ow_htmldir'}/images/iconsets! ($!)");

      $temphtml = popup_menu(-name=>'iconset',
                             -values=>\@iconsets,
                             -default=>$prefs{'iconset'},
                             -override=>'1',
                             defined($config_raw{'DEFAULT_iconset'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@ICONSETMENU\@\@\@/$temphtml/;

      # Get a list of valid background images
      my @backgrounds;
      opendir(BACKGROUNDSDIR, "$config{'ow_htmldir'}/images/backgrounds") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_htmldir'}/images/backgrounds directory for reading! ($!)");
      while (defined(my $currbackground = readdir(BACKGROUNDSDIR))) {
         if ($currbackground =~ /^([^\.].*)$/) {
            push (@backgrounds, $1);
         }
      }
      closedir(BACKGROUNDSDIR) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'ow_htmldir'}/images/backgrounds! ($!)");
      @backgrounds = sort(@backgrounds);
      push(@backgrounds, "USERDEFINE");

      my ($background, $bgurl)=($prefs{'bgurl'}, '');
      if ($background !~ s!$config{'ow_htmlurl'}/images/backgrounds/!!) {
         ($background, $bgurl)=('USERDEFINE', $prefs{'bgurl'});
      }
      $temphtml = popup_menu(-name=>'background',
                             -values=>\@backgrounds,
                             -labels=>{ 'USERDEFINE'=>"--$lang_text{'userdef'}--" },
                             -default=>$background,
                             -onChange=>"JavaScript:document.prefsform.bgurl.value='';",
                             -override=>'1',
                             defined($config_raw{'DEFAULT_bgurl'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@BACKGROUNDMENU\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'bgrepeat',
                           -value=>'1',
                           -checked=>$prefs{'bgrepeat'},
                           -label=>'',
                           defined($config_raw{'DEFAULT_bgrepeat'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@BGREPEATCHECKBOX\@\@\@/$temphtml/;

      $temphtml = textfield(-name=>'bgurl',
                            -default=>$bgurl,
                            -size=>'35',
                            -override=>'1',
                            defined($config_raw{'DEFAULT_bgurl'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@BGURLFIELD\@\@\@/$temphtml/;

      my @fontsize=sort { ($a=~/px$/ - $b=~/px$/) || $a<=>$b } keys %fontsize;
      my %fontsizelabels;
      foreach (@fontsize) {
         $fontsizelabels{$_}=$_;
         $fontsizelabels{$_}=~s/pt/ $lang_text{'point'}/;
         $fontsizelabels{$_}=~s/px/ $lang_text{'pixel'}/;
      }
      $temphtml = popup_menu(-name=>'fontsize',
                             -values=>\@fontsize,
                             -default=>$prefs{'fontsize'},
                             -labels=>\%fontsizelabels,
                             -override=>'1',
                             defined($config_raw{'DEFAULT_font'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@FONTSIZEMENU\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'dateformat',
                             -values=>['mm/dd/yyyy', 'dd/mm/yyyy', 'yyyy/mm/dd',
                                         'mm-dd-yyyy', 'dd-mm-yyyy', 'yyyy-mm-dd',
                                         'mm.dd.yyyy', 'dd.mm.yyyy', 'yyyy.mm.dd'],
                             -default=>$prefs{'dateformat'},
                             -override=>'1',
                             defined($config_raw{'DEFAULT_dateformat'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@DATEFORMATMENU\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'hourformat',
                             -values=>[12, 24],
                             -default=>$prefs{'hourformat'},
                             -override=>'1',
                             defined($config_raw{'DEFAULT_hourformat'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@HOURFORMATMENU\@\@\@/$temphtml/;


      if ($config{'enable_webmail'}) {
         $temphtml = popup_menu(-name=>'ctrlposition_folderview',
                                -values=>['top', 'bottom'],
                                -default=>$prefs{'ctrlposition_folderview'} || 'bottom',
                                -labels=>\%lang_ctrlpositionlabels,
                                -accesskey=>'3',
                                -override=>'1',
                                defined($config_raw{'DEFAULT_ctrlposition_folderview'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@CTRLPOSITIONFOLDERVIEWMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'msgsperpage',
                                -values=>[8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,50,100,500,1000],
                                -default=>$prefs{'msgsperpage'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_msgsperpage'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@HEADERSPERPAGE\@\@\@/$temphtml/;

         my %orderlabels = (
            'date from subject size' =>
            "$lang_text{'date'}, $lang_text{'from'}, $lang_text{'subject'}, $lang_text{'size'}",
            'date subject from size' =>
            "$lang_text{'date'}, $lang_text{'subject'}, $lang_text{'from'}, $lang_text{'size'}",
            'subject from date size' =>
            "$lang_text{'subject'}, $lang_text{'from'}, $lang_text{'date'}, $lang_text{'size'}",
            'from subject date size' =>
            "$lang_text{'from'}, $lang_text{'subject'}, $lang_text{'date'}, $lang_text{'size'}"
            );
         my @ordervalues=sort keys(%orderlabels);
         $temphtml = popup_menu(-name=>'fieldorder',
                                -default=>$prefs{'fieldorder'},
                                -values=>\@ordervalues,
                                -labels=>\%orderlabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_fieldorder'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@FIELDORDERMENU\@\@\@/$temphtml/;

         # since there is already sort param inherited from outside prefs form,
         # so the prefs form pass the sort param as msgsort
         $temphtml = popup_menu(-name=>'msgsort',
                                -values=>['date','date_rev','sender','sender_rev',
                                            'size','size_rev','subject','subject_rev',
                                            'status'],
                                -default=>$prefs{'sort'},
                                -labels=>\%lang_sortlabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_msgsort'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SORTMENU\@\@\@/$temphtml/;

         $temphtml = iconlink("search.s.gif", '', '');
         $html =~ s/\@\@\@MINISEARCHICON\@\@\@/$temphtml/;
         $temphtml = checkbox(-name=>'useminisearchicon',
                              -value=>'1',
                              -checked=>$prefs{'useminisearchicon'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_useminisearchicon'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@USEMINISEARCHICONCHECKBOX\@\@\@/$temphtml/;


         $temphtml = checkbox(-name=>'confirmmsgmovecopy',
                              -value=>'1',
                              -checked=>$prefs{'confirmmsgmovecopy'},
                              -accesskey=>'4',
                              -label=>'',
                              defined($config_raw{'DEFAULT_confirmmsgmovecopy'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@CONFIRMMSGMOVECOPY\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'defaultdestination',
                                -values=>['saved-messages','mail-trash', 'DELETE'],
                                -default=>$prefs{'defaultdestination'} || 'mail-trash',
                                -labels=>\%lang_folders,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_defaultdestination'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@DEFAULTDESTINATIONMENU\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'smartdestination',
                              -value=>'1',
                              -checked=>$prefs{'smartdestination'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_smartdestination'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SMARTDESTINATION\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'viewnextaftermsgmovecopy',
                              -value=>'1',
                              -checked=>$prefs{'viewnextaftermsgmovecopy'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_viewnextaftermsgmovecopy'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@VIEWNEXTAFTERMSGMOVECOPY\@\@\@/$temphtml/;

         if ($config{'enable_pop3'}) {
            templateblock_enable($html, 'AUTOPOP3');
            $temphtml = checkbox(-name=>'autopop3',
                                 -value=>'1',
                                 -checked=>$prefs{'autopop3'},
                                 -label=>'',
                                 defined($config_raw{'DEFAULT_autopop3'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@AUTOPOP3CHECKBOX\@\@\@/$temphtml/;
            $temphtml = popup_menu(-name=>'autopop3wait',
                                   -values=>[0,1,2,3,4,5,6,7,8,9,10,15,20,25,30],
                                   -default=>$prefs{'autopop3wait'},
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_autopop3wait'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@AUTOPOP3WAITMENU\@\@\@/$temphtml/;
         } else {
            templateblock_disable($html, 'AUTOPOP3');
         }

         $temphtml = popup_menu(-name=>'bgfilterwait',
                                -values=>[5,10,15,20,25,30,35,40,45,50,55,60,90,120],
                                -default=>$prefs{'bgfilterwait'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_bgfilterwait'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@BGFILTERWAITMENU\@\@\@/$temphtml/;

         if ($config{'forced_moveoldmsgfrominbox'}) {
            templateblock_disable($html, 'MOVEOLD');
         } else {
            templateblock_enable($html, 'MOVEOLD');
            $temphtml = checkbox(-name=>'moveoldmsgfrominbox',
                                 -value=>'1',
                                 -checked=>$prefs{'moveoldmsgfrominbox'},
                                 -label=>'',
                                 defined($config_raw{'DEFAULT_moveoldmsgfrominbox'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@MOVEOLDMSGFROMINBOX\@\@\@/$temphtml/;
         }


         $temphtml = popup_menu(-name=>'ctrlposition_msgread',
                                -values=>['top', 'bottom'],
                                -default=>$prefs{'ctrlposition_msgread'} || 'bottom',
                                -labels=>\%lang_ctrlpositionlabels,
                                -accesskey=>'5',
                                -override=>'1',
                                defined($config_raw{'DEFAULT_ctrlposition_msgread'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@CTRLPOSITIONMSGREADMENU\@\@\@/$temphtml/;

         my %headerlabels = ('simple'=>$lang_text{'simplehead'},
                             'all'=>$lang_text{'allhead'} );
         $temphtml = popup_menu(-name=>'headers',
                                -values=>['simple','all'],
                                -default=>$prefs{'headers'} || 'simple',
                                -labels=>\%headerlabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_headers'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@HEADERSMENU\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'usefixedfont',
                              -value=>'1',
                              -checked=>$prefs{'usefixedfont'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_usefixedfont'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@USEFIXEDFONT\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'usesmileicon',
                              -value=>'1',
                              -checked=>$prefs{'usesmileicon'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_usesmileicon'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@USESMILEICON\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'disablejs',
                              -value=>'1',
                              -checked=>$prefs{'disablejs'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_disablejs'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@DISABLEJS\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'disableembcode',
                              -value=>'1',
                              -checked=>$prefs{'disableembcode'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_disableembcode'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@DISABLEEMBCODE\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'disableemblink',
                                -values=>['none', 'cgionly', 'all'],
                                -default=>$prefs{'disableemblink'},
                                -labels=>\%lang_disableemblinklabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_disableemblink'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@DISABLEEMBLINKMENU\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'showhtmlastext',
                              -value=>'1',
                              -checked=>$prefs{'showhtmlastext'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_showhtmlastext'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SHOWHTMLASTEXT\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'showimgaslink',
                              -value=>'1',
                              -checked=>$prefs{'showimgaslink'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_showimgaslink'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SHOWIMGASLINK\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'sendreceipt',
                                -values=>['ask', 'yes', 'no'],
                                -default=>$prefs{'sendreceipt'} || 'ask',
                                -labels=>\%lang_receiptlabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_sendreceipt'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SENDRECEIPTMENU\@\@\@/$temphtml/;


         $temphtml = popup_menu(-name=>'msgformat',
                                -values=>['auto', 'text', 'html', 'both'],
                                -default=>$prefs{'msgformat'},
                                -labels=>\%lang_msgformatlabels,
                                -accesskey=>'6',
                                -override=>'1',
                                defined($config_raw{'DEFAULT_msgformat'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@MSGFORMATMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'editcolumns',
                                -values=>[60,62,64,66,68,70,72,74,76,78,80,82,84,86,88,90,100,110,120],
                                -default=>$prefs{'editcolumns'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_editcolumns'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@EDITCOLUMNSMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'editrows',
                                -values=>[10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,50,60,70,80],
                                -default=>$prefs{'editrows'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_editrows'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@EDITROWSMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'sendbuttonposition',
                                -values=>['before', 'after', 'both'],
                                -default=>$prefs{'sendbuttonposition'} || 'before',
                                -labels=>\%lang_sendpositionlabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_sendbuttonposition'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SENDBUTTONPOSITIONMENU\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'reparagraphorigmsg',
                              -value=>'1',
                              -checked=>$prefs{'reparagraphorigmsg'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_reparagraphorigmsg'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@REPARAGRAPHORIGMSG\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'replywithorigmsg',
                                -values=>['at_beginning', 'at_end', 'none'],
                                -default=>$prefs{'replywithorigmsg'} || 'at_beginning',
                                -labels=>\%lang_withoriglabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_replywithorigmsg'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@REPLYWITHORIGMSGMENU\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'backupsentmsg',
                              -value=>'1',
                              -checked=>$prefs{'backupsentmsg'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_backupsentmsg'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@BACKUPSENTMSG\@\@\@/$temphtml/;

         my %ctlabels=( 'sameascomposing' => $lang_text{'samecharset'} );
         my @ctlist=('sameascomposing', $prefs{charset});
         foreach my $ct (@{$charset_convlist{$prefs{charset}}}) {
            push(@ctlist, $ct) if (is_convertable($prefs{charset}, $ct));
         }
         $temphtml = popup_menu(-name=>'sendcharset',
                                -values=>\@ctlist,
                                -labels=>\%ctlabels,
                                -default=>$defaultsendcharset,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_sendcharset'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SENDCHARSETMENU\@\@\@/$temphtml/;


         if ($config{'enable_viruscheck'}) {
            templateblock_enable($html, 'VIRUSCHECK');

            my @source=('none');
            if ($config{'viruscheck_source_allowed'} eq 'pop3') {
               @source=('none', 'pop3');
            } elsif ($config{'viruscheck_source_allowed'} eq 'all') {
               @source=('none', 'pop3', 'all');
            }
            $temphtml = popup_menu(-name=>'viruscheck_source',
                                   -values=> \@source,
                                   -labels=> \%lang_checksourcelabels,
                                   -default=>$prefs{'viruscheck_source'},
                                   -accesskey=>'7',
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_viruscheck_source'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@VIRUSCHECKSOURCEMENU\@\@\@/$temphtml/;

            my (@maxsize, $defmaxsize);
            foreach my $n (250, 500, 1000, 2000, 3000, 4000, 5000, 10000, 20000, 50000) {
               if ($n <= $config{'viruscheck_maxsize_allowed'}) {
                  push(@maxsize, $n);
                  $defmaxsize=$n if ($n <= $prefs{'viruscheck_maxsize'});
               }
            }
            $temphtml = popup_menu(-name=>'viruscheck_maxsize',
                                   -values=> \@maxsize,
                                   -default=> $defmaxsize
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_viruscheck_maxsize'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@VIRUSCHECKMAXSIZEMENU\@\@\@/$temphtml/;

            $temphtml = popup_menu(-name=>'viruscheck_minbodysize',
                                   -values=> [0, 0.5, 1, 1.5, 2],
                                   -default=>$prefs{'viruscheck_minbodysize'},
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_viruscheck_minbodysize'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@VIRUSCHECKMINBODYSIZEMENU\@\@\@/$temphtml/;

         } else {
            templateblock_disable($html, 'VIRUSCHECK');
         }


         if ($config{'enable_spamcheck'}) {
            templateblock_enable($html, 'SPAMCHECK');

            my @source=('none');
            if ($config{'spamcheck_source_allowed'} eq 'pop3') {
               @source=('none', 'pop3');
            } elsif ($config{'spamcheck_source_allowed'} eq 'all') {
               @source=('none', 'pop3', 'all');
            }
            $temphtml = popup_menu(-name=>'spamcheck_source',
                                   -values=> \@source,
                                   -labels=> \%lang_checksourcelabels,
                                   -default=>$prefs{'spamcheck_source'},
                                   -accesskey=>'7',
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_spamcheck_source'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@SPAMCHECKSOURCEMENU\@\@\@/$temphtml/;

            my (@maxsize, $defmaxsize);
            foreach my $n (100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000) {
               if ($n <= $config{'spamcheck_maxsize_allowed'}) {
                  push(@maxsize, $n);
                  $defmaxsize=$n if ($n <= $prefs{'spamcheck_maxsize'});
               }
            }
            $temphtml = popup_menu(-name=>'spamcheck_maxsize',
                                   -values=> \@maxsize,
                                   -default=> $defmaxsize
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_spamcheck_maxsize'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@SPAMCHECKMAXSIZEMENU\@\@\@/$temphtml/;

            $temphtml = popup_menu(-name=>'spamcheck_threshold',
                                   -values=> [5..30],
                                   -default=>$prefs{'spamcheck_threshold'},
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_spamcheck_threshold'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@SPAMCHECKTHRESHOLDMENU\@\@\@/$temphtml/;

         } else {
            templateblock_disable($html, 'SPAMCHECK');
         }


         if ($config{'enable_smartfilter'}) {
            templateblock_enable($html, 'FILTER');

            my $filterruledb=dotpath('filter.ruledb');
            my (%FILTERRULEDB, $matchcount, $matchdate);
            ow::dbm::open(\%FILTERRULEDB, $filterruledb, LOCK_SH) or
                  openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} db $filterruledb");

            $temphtml = popup_menu(-name=>'filter_repeatlimit',
                                   -values=>['0','5','10','20','30','40','50','100'],
                                   -default=>$prefs{'filter_repeatlimit'},
                                   -accesskey=>'7',
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_filter_repeatlimit'})?('-disabled'=>'1'):());
            ($matchcount, $matchdate)=split(":", $FILTERRULEDB{"filter_repeatlimit"});
            if ($matchdate) {
               $matchdate=ow::datetime::dateserial2str($matchdate,
                                           $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                           $prefs{'dateformat'}, $prefs{'hourformat'});
               $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
            }
            $html =~ s/\@\@\@FILTERREPEATLIMIT\@\@\@/$temphtml/;

            $temphtml = checkbox(-name=>'filter_badaddrformat',
                                 -value=>'1',
                                 -checked=>$prefs{'filter_badaddrformat'},
                                 -label=>'',
                                 defined($config_raw{'DEFAULT_filter_badaddrformat'})?('-disabled'=>'1'):());
            ($matchcount, $matchdate)=split(":", $FILTERRULEDB{'filter_badaddrformat'});
            if ($matchdate) {
               $matchdate=ow::datetime::dateserial2str($matchdate,
                                           $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                           $prefs{'dateformat'}, $prefs{'hourformat'});
               $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
            }
            $html =~ s/\@\@\@FILTERBADADDRFORMAT\@\@\@/$temphtml/;

            $temphtml = checkbox(-name=>'filter_fakedsmtp',
                                 -value=>'1',
                                 -checked=>$prefs{'filter_fakedsmtp'},
                                 -label=>'',
                                 defined($config_raw{'DEFAULT_filter_fakedsmtp'})?('-disabled'=>'1'):());
            ($matchcount, $matchdate)=split(":", $FILTERRULEDB{'filter_fakedsmtp'});
            if ($matchdate) {
               $matchdate=ow::datetime::dateserial2str($matchdate,
                                           $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                           $prefs{'dateformat'}, $prefs{'hourformat'});
               $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
            }
            $html =~ s/\@\@\@FILTERFAKEDSMTP\@\@\@/$temphtml/;

            $temphtml = checkbox(-name=>'filter_fakedfrom',
                                 -value=>'1',
                                 -checked=>$prefs{'filter_fakedfrom'},
                                 -label=>'',
                                 defined($config_raw{'DEFAULT_filter_fakedfrom'})?('-disabled'=>'1'):());
            ($matchcount, $matchdate)=split(":", $FILTERRULEDB{'filter_fakedfrom'});
            if ($matchdate) {
               $matchdate=ow::datetime::dateserial2str($matchdate,
                                           $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                           $prefs{'dateformat'}, $prefs{'hourformat'});
               $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
            }
            $html =~ s/\@\@\@FILTERFAKEDFROM\@\@\@/$temphtml/;

            $temphtml = checkbox(-name=>'filter_fakedexecontenttype',
                                 -value=>'1',
                                 -checked=>$prefs{'filter_fakedexecontenttype'},
                                 -label=>'',
                                 defined($config_raw{'DEFAULT_filter_fakedexecontenttype'})?('-disabled'=>'1'):());
            ($matchcount, $matchdate)=split(":", $FILTERRULEDB{'filter_fakedexecontenttype'});
            if ($matchdate) {
               $matchdate=ow::datetime::dateserial2str($matchdate,
                                           $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                           $prefs{'dateformat'}, $prefs{'hourformat'});
               $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
            }
            $html =~ s/\@\@\@FILTERFAKEDEXECONTENTTYPE\@\@\@/$temphtml/;

            ow::dbm::close(\%FILTERRULEDB, $filterruledb);

         } else {
            templateblock_disable($html, 'FILTER');
         }
      }

      if ($config{'enable_addressbook'}) {
         templateblock_enable($html, 'WEBADDR');

         my @pvalues=(300,320,340,360,380,400,420,440,460,480,500,520,540,560,580,600,700,800,900,1000);
         my %plabels;
         foreach (@pvalues) {
            $plabels{$_}="$_ $lang_text{'pixel'}";
         }
         push (@pvalues, 'max');
         $plabels{'max'}=$lang_text{'max'};

         $temphtml = popup_menu(-name=>'abook_width',
                                -values=>\@pvalues,
                                -labels=>\%plabels,
                                -default=>$prefs{'abook_width'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_abook_width'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ABOOKWIDTHMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'abook_height',
                                -values=>\@pvalues,
                                -labels=>\%plabels,
                                -default=>$prefs{'abook_height'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_abook_height'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ABOOKHEIGHTMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'abook_buttonposition',
                                -values=>['before', 'after', 'both'],
                                -default=>$prefs{'abook_buttonposition'} || 'before',
                                -labels=>\%lang_abookbuttonpositionlabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_abook_buttonposition'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ABOOKBUTTONPOSITIONMENU\@\@\@/$temphtml/;

         $temphtml = "$lang_text{'enable'}&nbsp;";
         $temphtml .= checkbox(-name=>'abook_defaultfilter',
                               -value=>'1',
                               -checked=>$prefs{'abook_defaultfilter'},
                               -label=>'',
                               defined($config_raw{'DEFAULT_abook_defaultfilter'})?('-disabled'=>'1'):());
         $temphtml .= "&nbsp;";


         my @searchchoices = qw(fullname email phone note categories);

         # build the labels from the choices
         my %searchtypelabels = ();
         $searchtypelabels{"$_"} = $lang_text{"abook_listview_$_"} for @searchchoices;

         $temphtml .= popup_menu(-name=>'abook_defaultsearchtype',
                                 -default=>$prefs{'abook_defaultsearchtype'} || 'fullname',
                                 -values=>\@searchchoices,
                                 -labels=>\%searchtypelabels,
                                 -override=>'1',
                                 defined($config_raw{'DEFAULT_abook_defaultsearchtype'})?('-disabled'=>'1'):());
         $temphtml .= textfield(-name=>'abook_defaultkeyword',
                                -default=>$prefs{'abook_defaultkeyword'},
                                -size=>'16',
                                -override=>'1',
                                defined($config_raw{'DEFAULT_abook_defaultkeyword'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ABOOKDEFAULTFILTER\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'abook_addrperpage',
                                -values=>[8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,50,100,500,1000],
                                -default=>$prefs{'abook_addrperpage'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_abook_addrperpage'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ABOOKADDRSPERPAGE\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'abook_collapse',
                              -value=>'1',
                              -checked=>$prefs{'abook_collapse'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_abook_collapse'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ABOOKADDRCOLLAPSE\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'abook_sort',
                                -values=>[qw(fullname fullname_rev
                                             prefix   prefix_rev
                                             first    first_rev
                                             middle   middle_rev
                                             last     last_rev
                                             suffix   suffix_rev
                                             email    email_rev
                                             phone    phone_rev)],
                                -default=>$prefs{'abook_sort'},
                                -labels=>\%lang_abooksortlabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_abook_sort'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ABOOKADDRSORTORDER\@\@\@/$temphtml/;


         my @choices = qw(fullname prefix first middle last suffix email phone note none);

         # build the labels from the choices
         my %addrfieldorderlabels = ();
         $addrfieldorderlabels{"$_"} = $lang_text{"abook_listview_$_"} for @choices;

         $temphtml = popup_menu(-name=>'abook_listviewfieldorder',
                                -default=>$prefs{'abook_listviewfieldorder'}[0] || 'none',
                                -values=>\@choices,
                                -labels=>\%addrfieldorderlabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_abook_listviewfieldorder'})?('-disabled'=>'1'):());

         $temphtml .= popup_menu(-name=>'abook_listviewfieldorder',
                                 -default=>$prefs{'abook_listviewfieldorder'}[1] || 'none',
                                 -values=>\@choices,
                                 -labels=>\%addrfieldorderlabels,
                                 -override=>'1',
                                 defined($config_raw{'DEFAULT_abook_listviewfieldorder'})?('-disabled'=>'1'):());

         $temphtml .= popup_menu(-name=>'abook_listviewfieldorder',
                                 -default=>$prefs{'abook_listviewfieldorder'}[2] || 'none',
                                 -values=>\@choices,
                                 -labels=>\%addrfieldorderlabels,
                                 -override=>'1',
                                 defined($config_raw{'DEFAULT_abook_listviewfieldorder'})?('-disabled'=>'1'):());

         $temphtml .= popup_menu(-name=>'abook_listviewfieldorder',
                                 -default=>$prefs{'abook_listviewfieldorder'}[3] || 'none',
                                 -values=>\@choices,
                                 -labels=>\%addrfieldorderlabels,
                                 -override=>'1',
                                 defined($config_raw{'DEFAULT_abook_listviewfieldorder'})?('-disabled'=>'1'):());

         $temphtml .= popup_menu(-name=>'abook_listviewfieldorder',
                                 -default=>$prefs{'abook_listviewfieldorder'}[4] || 'none',
                                 -values=>\@choices,
                                 -labels=>\%addrfieldorderlabels,
                                 -override=>'1',
                                 defined($config_raw{'DEFAULT_abook_listviewfieldorder'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ABOOKLISTVIEWFIELDORDERMENU\@\@\@/$temphtml/;
      } else {
         templateblock_disable($html, 'WEBADDR');
      }

      if ($config{'enable_calendar'}) {
         templateblock_enable($html, 'CALENDAR');

         my %calendarview_labels=(
            calyear  => $lang_calendar{'yearview'},
            calmonth => $lang_calendar{'monthview'},
            calweek  => $lang_calendar{'weekview'},
            calday   => $lang_calendar{'dayview'},
            callist  => $lang_calendar{'listview'}
         );
         $temphtml = popup_menu(-name=>'calendar_defaultview',
                                -values=>['calyear', 'calmonth', 'calweek', 'calday', 'callist'],
                                -labels=>\%calendarview_labels,
                                -default=>$prefs{'calendar_defaultview'},
                                -accesskey=>'8',
                                -override=>'1',
                                defined($config_raw{'DEFAULT_calendar_defaultview'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@DEFAULTVIEWMENU\@\@\@/$temphtml/;

         # Get a list of valid holiday files
         my @holidays;
         opendir(HOLIDAYSDIR, "$config{'ow_holidaysdir'}") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_holidaysdir'} directory for reading! ($!)");
         while (defined(my $currholiday = readdir(HOLIDAYSDIR))) {
            if ($currholiday =~ /^([^\.].*)$/) {
               push (@holidays, $1);
            }
         }
         closedir(HOLIDAYSDIR) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'ow_holidaysdir'}! ($!)");
         @holidays = ('auto', sort(@holidays), 'none');

         $temphtml = popup_menu(-name=>'calendar_holidaydef',
                                -values=>\@holidays,
                                -labels=>{ 'auto'=>$lang_text{'autosel'},
                                           'none'=>$lang_text{'none'} },
                                -default=>$prefs{'calendar_holidaydef'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_calendar_holidaydef'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@HOLIDAYDEFMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'calendar_monthviewnumitems',
                                -values=>[3, 4, 5, 6, 7, 8, 9, 10],
                                -default=>$prefs{'calendar_monthviewnumitems'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_calendar_monthviewnumitems'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@MONTHVIEWNUMITEMSMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'calendar_weekstart',
                                -values=>[1, 2, 3, 4, 5, 6, 0],
                                -labels=>\%lang_wday,
                                -default=>$prefs{'calendar_weekstart'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_calendar_weekstart'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@WEEKSTARTMENU\@\@\@/$temphtml/;

         my @militaryhours;
         for (my $i=0; $i<24; $i++) {
            push(@militaryhours, sprintf("%02d00", $i));
         }
         $temphtml = popup_menu(-name=>'calendar_starthour',
                                -values=>\@militaryhours,
                                -default=>$prefs{'calendar_starthour'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_calendar_starthour'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@STARTHOURMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'calendar_endhour',
                                -values=>\@militaryhours,
                                -default=>$prefs{'calendar_endhour'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_calendar_endhour'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@ENDHOURMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'calendar_interval',
                                -values=>[5, 10, 15, 20, 30, 45, 60, 90, 120],
                                -default=>$prefs{'calendar_interval'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_calendar_interval'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@INTERVALMENU\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'calendar_showemptyhours',
                              -value=>'1',
                              -checked=>$prefs{'calendar_showemptyhours'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_calendar_showemptyhours'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SHOWEMPTYHOURSCHECKBOX\@\@\@/$temphtml/;

         if ($config{'enable_webmail'}) {
            templateblock_enable($html, 'REMINDER');
            $temphtml = popup_menu(-name=>'calendar_reminderdays',
                                   -values=>[0, 1, 2, 3, 4, 5, 6 ,7, 14, 21, 30, 60],
                                   -labels=>{ 0=>$lang_text{'none'} },
                                   -default=>$prefs{'calendar_reminderdays'},
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_calendar_reminderdays'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@REMINDERDAYSMENU\@\@\@/$temphtml/;

            $temphtml = checkbox(-name=>'calendar_reminderforglobal',
                                 -value=>'1',
                                 -checked=>$prefs{'calendar_reminderforglobal'},
                                 -label=>'',
                                 defined($config_raw{'DEFAULT_calendar_reminderforglobal'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@REMINDERFORGLOBALCHECKBOX\@\@\@/$temphtml/;
         } else {
            templateblock_disable($html, 'REMINDER');
         }

      } else {
         templateblock_disable($html, 'CALENDAR');
      }


      if ($config{'enable_webdisk'}) {
         templateblock_enable($html, 'WEBDISK');
         $temphtml = popup_menu(-name=>'webdisk_dirnumitems',
                                -values=>[10,12,14,16,18,20,22,24,26,28,30, 40, 50, 60, 70, 80, 90, 100, 150, 200, 500, 1000, 5000],
                                -default=>$prefs{'webdisk_dirnumitems'},
                                -accesskey=>'9',
                                -override=>'1',
                                defined($config_raw{'DEFAULT_webdisk_dirnumitems'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@DIRNUMITEMSMENU\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'webdisk_confirmmovecopy',
                              -value=>'1',
                              -checked=>$prefs{'webdisk_confirmmovecopy'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_webdisk_confirmmovecopy'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@CONFIRMFILEMOVECOPY\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'webdisk_confirmdel',
                              -value=>'1',
                              -checked=>$prefs{'webdisk_confirmdel'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_webdisk_confirmdel'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@CONFIRMFILEDEL\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'webdisk_confirmcompress',
                              -value=>'1',
                              -checked=>$prefs{'webdisk_confirmcompress'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_webdisk_confirmcompress'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@CONFIRMFILECOMPRESS\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'webdisk_fileeditcolumns',
                                -values=>[80,82,84,86,88,90,92,94,96,98,100,110,120,160,192,256,512,1024,2048],
                                -default=>$prefs{'webdisk_fileeditcolumns'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_webdisk_fileeditcolumns'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@FILEEDITCOLUMNSMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'webdisk_fileeditrows',
                                -values=>[10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,50,60,70,80],
                                -default=>$prefs{'webdisk_fileeditrows'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_webdisk_fileeditrows'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@FILEEDITROWSMENU\@\@\@/$temphtml/;

      } else {
         templateblock_disable($html, 'WEBDISK');
      }


      $temphtml = checkbox(-name=>'uselightbar',
                           -value=>'1',
                           -checked=>$prefs{'uselightbar'},
                           -label=>'',
                           defined($config_raw{'DEFAULT_uselightbar'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@USELIGHTBARCHECKBOX\@\@\@/$temphtml/;

      if ($config{'enable_webmail'}) {
         $temphtml = checkbox(-name=>'regexmatch',
                              -value=>'1',
                              -checked=>$prefs{'regexmatch'},
                              -accesskey=>'0',
                              -label=>'',
                              defined($config_raw{'DEFAULT_regexmatch'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@REGEXMATCH\@\@\@/$temphtml/;

         $temphtml = checkbox(-name=>'hideinternal',
                              -value=>'1',
                              -checked=>$prefs{'hideinternal'},
                              -label=>'',
                              defined($config_raw{'DEFAULT_hideinternal'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@HIDEINTERNAL\@\@\@/$temphtml/;

         # Get a list of new mail sound
         my @sounds;
         opendir(SOUNDDIR, "$config{'ow_htmldir'}/sounds") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'ow_htmldir'}/sounds directory for reading! ($!)");
         while (defined(my $currsnd = readdir(SOUNDDIR))) {
            if (-f "$config{'ow_htmldir'}/sounds/$currsnd" && $currsnd =~ /^([^\.].*)$/) {
               push (@sounds, $1);
            }
         }
         closedir(SOUNDDIR) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'ow_htmldir'}/sounds! ($!)");

         @sounds = sort(@sounds);
         unshift(@sounds, 'NONE');

         $temphtml = popup_menu(-name=>'newmailsound',
                                -labels=>{ 'NONE'=>$lang_text{'none'} },
                                -values=>\@sounds,
                                -default=>$prefs{'newmailsound'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_newmailsound'})?('-disabled'=>'1'):());
         my $soundurl="$config{'ow_htmlurl'}/sounds/";
         $temphtml .= "&nbsp;". iconlink("sound.gif", $lang_text{'testsound'}, qq|onclick="playsound('$soundurl', document.prefsform.newmailsound[document.prefsform.newmailsound.selectedIndex].value);"|);
         $html =~ s/\@\@\@NEWMAILSOUNDMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'newmailwindowtime',
                                -values=>[0, 3, 5, 7, 10, 20, 30, 60, 120, 300, 600],
                                -default=>$prefs{'newmailwindowtime'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_newmailwindowtime'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@NEWMAILWINDOWTIMEMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'mailsentwindowtime',
                                -values=>[0, 3, 5, 7, 10, 20, 30],
                                -default=>$prefs{'mailsentwindowtime'},
                                -override=>'1',
                                defined($config_raw{'DEFAULT_mailsentwindowtime'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@MAILSENTWINDOWTIMEMENU\@\@\@/$temphtml/;

         if ($config{'enable_spellcheck'}) {
            templateblock_enable($html, 'SPELLCHECK');
            $temphtml = popup_menu(-name=>'dictionary',
                                   -values=>$config{'spellcheck_dictionaries'},
                                   -default=>$prefs{'dictionary'},
                                   -override=>'1',
                                   defined($config_raw{'DEFAULT_dictionary'})?('-disabled'=>'1'):());
            $html =~ s/\@\@\@DICTIONARYMENU\@\@\@/$temphtml/;
         } else {
            templateblock_disable($html, 'SPELLCHECK');
         }

         my %dayslabels = ('0'=>$lang_text{'delatlogout'},'999999'=>$lang_text{'forever'} );
         $temphtml = popup_menu(-name=>'trashreserveddays',
                                -values=>[0,1,2,3,4,5,6,7,14,21,30,60,90,180,999999],
                                -default=>$prefs{'trashreserveddays'},
                                -labels=>\%dayslabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_trashreserveddays'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@TRASHRESERVEDDAYSMENU\@\@\@/$temphtml/;

         $temphtml = popup_menu(-name=>'spamvirusreserveddays',
                                -values=>[0,1,2,3,4,5,6,7,14,21,30,60,90,180,999999],
                                -default=>$prefs{'spamvirusreserveddays'},
                                -labels=>\%dayslabels,
                                -override=>'1',
                                defined($config_raw{'DEFAULT_spamvirusreserveddays'})?('-disabled'=>'1'):());
         $html =~ s/\@\@\@SPAMVIRUSRESERVEDDAYSMENU\@\@\@/$temphtml/;
      }

      my @intervals;
      foreach my $value (3, 5, 10, 20, 30, 60, 120, 180) {
         push(@intervals, $value) if ($value>=$config{'min_refreshinterval'});
      }
      $temphtml = popup_menu(-name=>'refreshinterval',
                             -values=>\@intervals,
                             -default=>$prefs{'refreshinterval'},
                             -labels=>\%lang_timelabels,
                             -override=>'1',
                             defined($config_raw{'DEFAULT_refreshinterval'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@REFRESHINTERVALMENU\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'sessiontimeout',
                             -values=>[10,30,60,120,180,360,720,1440],
                             -default=>$prefs{'sessiontimeout'},
                             -labels=>\%lang_timelabels,
                             -override=>'1',
                             defined($config_raw{'DEFAULT_sessiontimeout'})?('-disabled'=>'1'):());
      $html =~ s/\@\@\@SESSIONTIMEOUTMENU\@\@\@/$temphtml/;

      # cancel button
      if ($prefs_caller eq "cal") {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl").
                      ow::tool::hiddens(action=>$prefs{'calendar_defaultview'});
      } elsif ($prefs_caller eq "webdisk") {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl").
                      ow::tool::hiddens(action=>'showdir');
      } elsif ($prefs_caller eq "read") {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl").
                      ow::tool::hiddens(action=>'readmessage');
      } elsif ($prefs_caller eq "addrlistview") {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                      ow::tool::hiddens(action=>'addrlistview');
      } else {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl").
                      ow::tool::hiddens(action=>'listmessages');
      }
      $temphtml .= $formparmstr;
      $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;
      $temphtml = submit(-name=>'cancelbutton',
                         -accesskey=>'Q',
                         -value=>$lang_text{'cancel'});
      $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;
   }

   $temphtml = submit(-name=>'savebutton',
                      -accesskey=>'W',
                      -value=>$lang_text{'save'});
   $html =~ s/\@\@\@SAVEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITPREFS #########################################

########## SAVEPREFS #############################################
# if any param is not passed from the prefs form,
# this routine will use old value will be used instead,
# so we can use incomplete prefs form
sub saveprefs {
   # create dir under ~/.openwebmail/
   check_and_create_dotdir(dotpath('/'));

   if ($config{'enable_strictforward'} &&
       param('forwardaddress') =~ /[&;\`\<\>\(\)\{\}]/) {
      openwebmailerror(__FILE__, __LINE__, "$lang_text{'forward'} $lang_text{'email'} $lang_err{'has_illegal_chars'}");
   }

   my (%newprefs, $key, $value, @value);

   foreach $key (@openwebmailrcitem) {
      if ( defined($is_config_option{'list'}{"default_$key"}) ) {
         @value = param($key);
         foreach my $index (0..$#value) {
            $value[$index] =~ s/\.\.+//g;
            $value[$index] =~ s/[=\n\/\`\|\<\>;]//g; # remove dangerous char
         }
         $newprefs{$key} = join(",",@value);
         next;
      } else {
         $value = param($key);
      }

      if ($key eq 'bgurl') {
         my $background=param('background');
         if ($background eq "USERDEFINE") {
            $newprefs{$key}=$value if ($value ne "");
         } else {
            $newprefs{$key}="$config{'ow_htmlurl'}/images/backgrounds/$background";
         }
         next;
      } elsif ($key eq 'dateformat') {
         $newprefs{$key}=$value;
         next;
      }

      $value =~ s/\.\.+//g;
      $value =~ s/[=\n\/\`\|\<\>;]//g; # remove dangerous char
      if ($key eq 'language') {
         foreach my $currlanguage (sort keys %ow::lang::languagenames) {
            if ($value eq $currlanguage) {
               $newprefs{$key}=$value; last;
            }
         }
      } elsif ($key eq 'sort') {
         # since there is already sort param inherited from outside prefs form,
         # so the prefs form pass the sort param as msgsort
         $newprefs{$key}=param('msgsort')||'date';
      } elsif ($key eq 'dictionary') {
         foreach my $currdictionary (@{$config{'spellcheck_dictionaries'}}) {
            if ($value eq $currdictionary) {
               $newprefs{$key}=$value; last;
            }
         }
      } elsif ($key eq 'filter_repeatlimit') {
         # if repeatlimit changed, redo filtering may be needed
         if ( $value != $prefs{'filter_repeatlimit'} ) {
            unlink(dotpath('filter.check'));
         }
         $newprefs{$key}=$value;
      } elsif (defined($is_config_option{'yesno'}{"default_$key"}) ) {
         $value=0 if ($value eq '');
         $newprefs{$key}=$value;
      } else {
         $newprefs{$key}=$value;
      }
   }

   if ( ($newprefs{'filter_fakedsmtp'} && !$prefs{'filter_fakedsmtp'} ) ||
        ($newprefs{'filter_fakedfrom'} && !$prefs{'filter_fakedfrom'} ) ||
        ($newprefs{'filter_fakedexecontenttype'} && !$prefs{'filter_fakedexecontenttype'} ) ) {
      unlink(dotpath('filter.check'));
   }
   if ($newprefs{'trashreserveddays'} ne $prefs{'trashreserveddays'} ) {
      unlink(dotpath('trash.check'));
   }

   $value = param('signature') || '';
   $value =~ s/\r\n/\n/g;
   if (length($value) > 500) {  # truncate signature to 500 chars
      $value = substr($value, 0, 500);
   }
   $newprefs{'signature'}=$value;

   my $forwardaddress=param('forwardaddress')||'';
   my $keeplocalcopy=param('keeplocalcopy')||0;
   my $autoreply=param('autoreply')||0;
   my $autoreplysubject=param('autoreplysubject')||'';
   my $autoreplytext=param('autoreplytext')||'';
   $autoreply=0 if (!$config{'enable_autoreply'});

   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, dotpath('from.book'));

   # save .forward file
   writedotforward($autoreply, $keeplocalcopy, $forwardaddress, keys %userfrom);

   # save .vacation.msg
   if ($config{'enable_autoreply'}) {
      writedotvacationmsg($autoreply, $autoreplysubject, $autoreplytext, $newprefs{'signature'},
				$newprefs{'email'}, $userfrom{$newprefs{'email'}} );
   }

   # save .signature
   my $signaturefile=dotpath('signature');
   if ( !-f $signaturefile && -f "$homedir/.signature" ) {
      $signaturefile="$homedir/.signature";
   }
   open (SIGNATURE,">$signaturefile") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $signaturefile! ($!)");
   print SIGNATURE $newprefs{'signature'};
   close (SIGNATURE) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $signaturefile! ($!)");
   chown($uuid, (split(/\s+/,$ugid))[0], $signaturefile) if ($signaturefile eq "$homedir/.signature");

   # save .openwebmailrc
   my $rcfile=dotpath('openwebmailrc');
   open (RC, ">$rcfile") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $rcfile! ($!)");
   foreach my $key (@openwebmailrcitem) {
      print RC "$key=$newprefs{$key}\n";
   }
   close (RC) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $rcfile! ($!)");

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   loadlang($prefs{'language'});

   my ($html, $temphtml);
   $html = applystyle(readtemplate("prefssaved.template"));

   if ($prefs_caller eq "cal") {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl").
                   ow::tool::hiddens(action=>$prefs{'calendar_defaultview'});
   } elsif ($prefs_caller eq "webdisk") {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl").
                   ow::tool::hiddens(action=>'showdir');
   } elsif ($prefs_caller eq "read") {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl").
                   ow::tool::hiddens(action=>'readmessage');
   } elsif ($prefs_caller eq "addrlistview") {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                   ow::tool::hiddens(action=>'addrlistview');
   } else {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl").
                   ow::tool::hiddens(action=>'listmessages');
   }
   $temphtml .= ow::tool::hiddens(sessionid=>$thissession,
                                  folder=>$folder,
                                  message_id=>$messageid,
                                  sort=>$prefs{'sort'},	# use new prefs instead of orig $sort
                                  page=>$page);
   $html =~ s/\@\@\@STARTSAVEDFORM\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'continue'}");
   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END SAVEPREFS #########################################

########## R/W DOTFORWARD/DOTVACATIONMSG #########################
sub readdotforward {
   my $forwardtext;

   if (open(FOR, "$homedir/.forward")) {
      local $/; undef $/; $forwardtext=<FOR>; # read whole file at once
      close(FOR);
   }

   # get flags and forward list with selfemail and vacationpipe removed
   my ($autoreply, $keeplocalcopy, @forwards)=splitforwardtext($forwardtext, 0, 0);
   $keeplocalcopy=0 if ($#forwards<0);
   return ($autoreply, $keeplocalcopy, @forwards);
}

sub writedotforward {
   my ($autoreply, $keeplocalcopy, $forwardtext, @userfrom) = @_;
   my @forwards=();

   # don't allow forward to self (avoid mail loops!)
   # splitforwardtext will remove self emails
   ($autoreply, $keeplocalcopy, @forwards)=splitforwardtext( $forwardtext, $autoreply, $keeplocalcopy );

   # if no other forwards, keeplocalcopy is required
   # only if autoreply is on or if this is a virtual user
   if ($#forwards<0) {
      if ( $autoreply or $config{'auth_module'} eq 'auth_vdomain.pl') {
         $keeplocalcopy=1;
      } else {
         $keeplocalcopy=0
      }
   }

   # nothing enabled, clean .forward
   if (!$autoreply && !$keeplocalcopy && $#forwards<0 ) {
      unlink("$homedir/.forward");
      return 0;
   }

   if ($autoreply) {
      # if this user has multiple fromemail or be mapped from another loginname
      # then use -a with vacation.pl to add these aliases for to: and cc: checking
      my $aliasparm="";
      foreach (sort_emails_by_domainnames($config{'domainnames'}, @userfrom)) {
         $aliasparm .= "-a $_ ";
      }
      $aliasparm .= "-a $loginname " if ($loginname ne $user);

      my $vacationuser = $user;
      if ($config{'auth_module'} eq 'auth_vdomain.pl') {
         $vacationuser = "-p$homedir nobody";
      }
      if (length("xxx$config{'vacationpipe'} $aliasparm $vacationuser")<250) {
         push(@forwards, qq!"| $config{'vacationpipe'} $aliasparm $vacationuser"!);
      } else {
         push(@forwards, qq!"| $config{'vacationpipe'} -j $vacationuser"!);
      }
   }

   if ($keeplocalcopy) {
      if ($config{'auth_module'} eq 'auth_vdomain.pl') {
         push(@forwards, vdomain_userspool($user,$homedir));
      } else {
         push(@forwards, "\\$user");
      }
   }

   open(FOR, ">$homedir/.forward") or return -1;
   print FOR join("\n", @forwards), "\n";
   close FOR;
   chown($uuid, (split(/\s+/,$ugid))[0], "$homedir/.forward");
   chmod(0600, "$homedir/.forward");
}

sub readdotvacationmsg {
   my ($subject, $text)=("", "");

   if (open(MSG, "$homedir/.vacation.msg")) {
      my $inheader=1;
      while (<MSG>) {
         chomp($_);
         if ($inheader==0) {
            $text.="$_\n";
            next;
         }
         if (/^Subject:\s*(.*)/i) {
            $subject=$1;
         } elsif (/^[A-Za-z0-9\-]+: /i) {
            next;
         } else {
            $inheader=0;
            $text.="$_\n";
         }
      }
      close MSG;
   }

   $subject = $config{'default_autoreplysubject'} if ($subject eq "");
   $subject =~ s/\s/ /g;
   $subject =~ s/^\s+//;
   $subject =~ s/\s+$//;

   # remove signature
   my $s=$prefs{'signature'};
   $s =~ s/\r\n/\n/g;
   my $i=rindex($text, $s);

   $text=substr($text, 0, $i) if ($i>0);

   $text= $config{'default_autoreplytext'} if ($text eq "");
   $text =~ s/\r\n/\n/g;
   $text =~ s/^\s+//s;
   $text =~ s/\s+$//s;

   return($subject, $text);
}

sub writedotvacationmsg {
   my ($autoreply, $subject, $text, $signature, $email, $userfrom)=@_;

   my $from;
   if ($userfrom) {
      $from=qq|"$userfrom" <$email>|;
   } else {
      $from=$email;
   }

   if ($autoreply) {
      local $|=1; # flush all output
      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);
         ow::suid::drop_ruid_rgid();
         # set enviro's for vacation program
         $ENV{'USER'}=$user;
         $ENV{'LOGNAME'}=$user;
         $ENV{'HOME'}=$homedir;
         delete $ENV{'GATEWAY_INTERFACE'};
         my @cmd;
         foreach (split(/\s/, $config{'vacationinit'})) {
            /^(.*)$/ && push(@cmd, $1); # untaint all argument
         }
         exec(@cmd);
         exit 0; # should never reach here
      }
   }

   $subject =~ s/\s/ /g;
   $subject =~ s/^\s+//;
   $subject =~ s/\s+$//;
   $subject = $config{'default_autoreplysubject'} if ($subject eq "");

   $text =~ s/\r\n/\n/g;
   $text =~ s/^\s+//s;
   $text =~ s/\s+$//s;
   $text = $config{'default_autoreplytext'} if ($text eq "");

   if (length($text) > 500) {  # truncate to 500 chars
      $text = substr($text, 0, 500);
   }

   open(MSG, ">$homedir/.vacation.msg") or return -2;
   print MSG "From: $from\n".
             "Subject: $subject\n\n".
             "$text\n\n".
             $signature;		# append signature
   close MSG;
   chown($uuid, (split(/\s+/,$ugid))[0], "$homedir/.vacation.msg");
}

sub splitforwardtext {
   my ($forwardtext, $autoreply, $keeplocalcopy)=@_;
   # remove self email and vacation from forward list
   # set keeplocalcopy if self email found
   # set autoreply if vacation found
   my $vacation_bin=(split(/\s+/,$config{'vacationpipe'}))[0];
   my @forwards=();
   foreach my $name ( split(/[,;\n\r]+/, $forwardtext) ) {
      $name=~s/^\s+//; $name=~s/\s+$//;
      next if ( $name=~/^$/ );
      if ($name=~/$vacation_bin/) { $autoreply=1; }
      elsif ( is_selfemail($name) ) { $keeplocalcopy=1; }
      else { push(@forwards, $name); }
   }
   return ($autoreply, $keeplocalcopy, @forwards);
}

sub is_selfemail {
   my ($email)=@_;
   if ( $email=~/$user\@(.+)/i ) {
      foreach ( @{$config{'domainnames'}} ) {
         return 1 if (lc($1) eq lc($_));
      }
   }
   return 1 if ($email eq "\\$user" || $email eq $user);
   return 1 if ($config{'auth_module'} eq 'auth_vdomain.pl' and $email eq vdomain_userspool($user,$homedir));
   return 0;
}
########## END R/W DOTFORWARD/DOTVACATIONMSG #####################

########## EDITPASSWORD ##########################################
sub editpassword {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("chpwd.template"));

   my $chpwd_url="$config{'ow_cgiurl'}/openwebmail-prefs.pl";
   if (cookie("openwebmail-ssl")) {	# backto SSL
      $chpwd_url="https://$ENV{'HTTP_HOST'}$chpwd_url" if ($chpwd_url!~s!^https?://!https://!i);
   }
   $temphtml = startform(-name=>'passwordform',
			 -action=>$chpwd_url).
               ow::tool::hiddens(action=>'changepassword').
               $formparmstr;
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   # display virtual or user, but actually not used, chnagepassword grab user from sessionid
   $temphtml = textfield(-name=>'loginname',
                         -default=>$loginname,
                         -size=>'10',
                         -disabled=>1,
                         -override=>'1');
   $html =~ s/\@\@\@LOGINNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'oldpassword',
                              -default=>'',
                              -size=>'10',
                              -override=>'1');
   $html =~ s/\@\@\@OLDPASSWORDFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'newpassword',
                              -default=>'',
                              -size=>'10',
                              -override=>'1');
   $html =~ s/\@\@\@NEWPASSWORDFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'confirmnewpassword',
                              -default=>'',
                              -size=>'10',
                              -override=>'1');
   $html =~ s/\@\@\@CONFIRMNEWPASSWORDFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name=> $lang_text{'changepwd'},
                      -onClick=>"return changecheck()");
   $html =~ s/\@\@\@CHANGEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl") .
               ow::tool::hiddens(action=>'editprefs').
               $formparmstr.
               submit("$lang_text{'cancel'}").
               end_form();
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $html =~ s/\@\@\@PASSWDMINLEN\@\@\@/$config{'passwd_minlen'}/g;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITPASSWORD ######################################

########## CHANGEPASSWORD ########################################
sub changepassword {
   my $oldpassword=param('oldpassword');
   my $newpassword=param('newpassword');
   my $confirmnewpassword=param('confirmnewpassword');

   my ($html, $temphtml);
   if ( length($newpassword) < $config{'passwd_minlen'} ) {
      $html = readtemplate("chpwdfailed.template");
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$lang_err{'pwd_tooshort'}/;
      $html =~ s/\@\@\@PASSWDMINLEN\@\@\@/$config{'passwd_minlen'}/;
   } elsif ( $config{'enable_strictpwd'} &&
             ($newpassword=~/^\d+$/ || $newpassword=~/^[A-Za-z]+$/) ) {
      $html = readtemplate("chpwdfailed.template");
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$lang_err{'pwd_toosimple'}/;
   } elsif ( $newpassword ne $confirmnewpassword ) {
      $html = readtemplate("chpwdfailed.template");
      $html =~ s/\@\@\@ERRORMSG\@\@\@/$lang_err{'pwd_confirmmismatch'}/;
   } else {
      my ($origruid, $origeuid)=($<, $>);
      my ($errorcode, $errormsg);
      if ($config{'auth_withdomain'}) {
         ($errorcode, $errormsg)=ow::auth::change_userpassword(\%config, "$user\@$domain", $oldpassword, $newpassword);
      } else {
         ($errorcode, $errormsg)=ow::auth::change_userpassword(\%config, $user, $oldpassword, $newpassword);
      }
      if ($errorcode==0) {
         # update authpop3book since it will be used to fetch mail from remote pop3 in this active session
         if ($config{'auth_module'} eq 'auth_ldap_vpopmail.pl') {
            update_authpop3book(dotpath('authpop3.book'), $domain, $user, $newpassword);
         }
         writelog("change password");
         writehistory("change password");
         $html = readtemplate("chpwdok.template");
      } else {
         writelog("change password error - $config{'auth_module'}, ret $errorcode, $errormsg");
         writehistory("change password error - $config{'auth_module'}, ret $errorcode, $errormsg");
         my $webmsg='';
         if ($errorcode==-1) {
            $webmsg=$lang_err{'func_notsupported'};
         } elsif ($errorcode==-2) {
            $webmsg=$lang_err{'param_fmterr'};
         } elsif ($errorcode==-3) {
            $webmsg=$lang_err{'auth_syserr'};
         } elsif ($errorcode==-4) {
            $webmsg=$lang_err{'pwd_incorrect'};
         } else {
            $webmsg="Unknow error code $errorcode";
         }
         $html = readtemplate("chpwdfailed.template");
         $html =~ s/\@\@\@ERRORMSG\@\@\@/$webmsg/;
      }
   }

   $html = applystyle($html);

   my $url="$config{'ow_cgiurl'}/openwebmail-prefs.pl";
   if ( !$config{'stay_ssl_afterlogin'} &&	# leave SSL
        ($ENV{'HTTPS'}=~/on/i || $ENV{'SERVER_PORT'}==443) ) {
      $url="http://$ENV{'HTTP_HOST'}$url" if ($url!~s!^https?://!http://!i);
   }
   $temphtml = startform(-action=>$url) .
               ow::tool::hiddens(action=>'editprefs').
               $formparmstr.
               submit("$lang_text{'backto'} $lang_text{'userprefs'}").
               end_form();
   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END CHANGEPASSWORD ####################################

########## LOGINHISTORY ##########################################
sub viewhistory {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("history.template"));

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml="";

   my $historyfile=dotpath('history.log');
   open (HISTORYLOG, $historyfile);

   my $bgcolor = $style{"tablerow_light"};
   while (<HISTORYLOG>) {
      chomp($_);
      $_=~/^(.*?) - \[(\d+)\] \((.*?)\) (.*)$/;

      my $record;
      my ($timestamp, $pid, $ip, $misc)=($1, $2, $3, $4);
      my ($u, $event, $desc, $desc2)=split(/ \- /, $misc, 4);
      $desc=ow::htmltext::str2html($desc);
      foreach my $field ($timestamp, $ip, $u, $event, $desc) {
         if ($event=~/error/i) {
            $record.=qq|<td bgcolor=$bgcolor align="center"><font color="#cc0000"><b>$field</font></b></td>\n|;
         } elsif ($event=~/warning/i || $desc=~/(?:spam|virus) .* found/i) {
            $record.=qq|<td bgcolor=$bgcolor align="center"><font color="#0000cc"><b>$field</font></b></td>\n|;
         } else {
            $record.=qq|<td bgcolor=$bgcolor align="center">$field</td>\n|;
         }
      }
      $temphtml = '<tr>' . $record . '</tr>' . $temphtml;

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }
   close(HISTORYLOG);
   $html =~ s/\@\@\@LOGINHISTORY\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END LOGINHISTORY ######################################

########## EDITFROMS #############################################
sub editfroms {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("editfroms.template"));

   my $frombookfile=dotpath('from.book');
   my $frombooksize = ( -s $frombookfile ) || 0;
   my $freespace = int($config{'maxbooksize'} - ($frombooksize/1024) + .5);
   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, $frombookfile);

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace $lang_sizes{'kb'}/;

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                         -name=>'newfrom').
               ow::tool::hiddens(action=>'addfrom').
               $formparmstr;
   $html =~ s/\@\@\@STARTFROMFORM\@\@\@/$temphtml/;

   if (defined($config{'DEFAULT_realname'})) {
      $temphtml = textfield(-name=>'realname',
                            -default=>$config{'DEFAULT_realname'},
                            -size=>'20',
                            -disabled=>'1',
                            -override=>'1');
   } else {
      $temphtml = textfield(-name=>'realname',
                            -default=>'',
                            -size=>'20',
                            -override=>'1');
   }
   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'email',
                         -default=>'',
                         -size=>'30',
                         -override=>'1');
   $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;

   if ($config{'frombook_for_realname_only'}) {
      $temphtml = submit(-name=>$lang_text{'modify'},
                         -class=>"medtext");
   } else {
      $temphtml = submit(-name=>$lang_text{'addmod'},
                         -class=>"medtext");
   }
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   my $bgcolor = $style{"tablerow_dark"};
   my ($email, $realname);

   $temphtml = '';
   foreach $email (sort_emails_by_domainnames($config{'domainnames'}, keys %userfrom)) {
      $realname=$userfrom{$email};

      my ($r, $e)=($realname, $email);
      $r=~s/'/\\'/; $e=~s/'/\\'/;	# escape ' for javascript
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor>$realname</td>|.
                   qq|<td bgcolor=$bgcolor><a href="Javascript:Update('$r','$e')">$email</a></td>|.
                   qq|<td bgcolor=$bgcolor align="center">|.
                   start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl").
                   ow::tool::hiddens(action=>'deletefrom',
                                     email=>$email).
                   $formparmstr .
                   submit(-name=>$lang_text{'delete'},
                          -class=>"medtext").
                   qq|</td></tr>|.
                   end_form();

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }
   $html =~ s/\@\@\@FROMS\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITFROMS #########################################

########## MODFROM ###############################################
sub modfrom {
   my $mode = shift;
   my $realname = param('realname') || '';
   my $email = param('email') || '';
   $realname =~ s/^\s*//; $realname =~ s/\s*$//;
   $email =~ s/[\<\>\[\]\\,;:\`\"\s]//g;

   my $frombookfile=dotpath('from.book');

   if ($email) {
      my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, $frombookfile);

      if ($mode eq 'delete') {
         delete $userfrom{$email};
      } else {
         if ( (-s $frombookfile) >= ($config{'maxbooksize'} * 1024) ) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'} <a href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfroms&amp;$urlparmstr">$lang_err{'back'}</a>$lang_err{'tryagain'}|);
         }
         if (!$config{'frombook_for_realname_only'} || defined($userfrom{$email}) ) {
            $userfrom{$email} = $realname;
         }
      }

      open (FROMBOOK, ">$frombookfile" ) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $frombookfile! ($!)");
      foreach $email (sort_emails_by_domainnames($config{'domainnames'}, keys %userfrom)) {
         print FROMBOOK "$email\@\@\@$userfrom{$email}\n";
      }
      close (FROMBOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $frombookfile! ($!)");
   }

   editfroms();
}
########## END MODFROM ###########################################

########## EDITPOP3 ##############################################
sub editpop3 {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("editpop3.template"));

   my $is_ssl_supported=ow::tool::has_module('IO/Socket/SSL.pm');

   my %accounts;
   my $pop3bookfile = dotpath('pop3.book');
   my $pop3booksize = ( -s $pop3bookfile ) || 0;
   my $freespace = int($config{'maxbooksize'} - ($pop3booksize/1024) + .5);

   if (readpop3book($pop3bookfile, \%accounts) <0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $pop3bookfile!");
   }

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace $lang_sizes{'kb'}/;

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   $temphtml .= "&nbsp;\n";
   $temphtml .= iconlink("pop3.gif", $lang_text{'retr_pop3s'}, qq|accesskey="G" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=pop3fetches&amp;$urlparmstr"|). qq| \n|;
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                         -name=>'newpop3').
               ow::tool::hiddens(action=>'addpop3').
               $formparmstr;
   $html =~ s/\@\@\@STARTPOP3FORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'pop3host',
                         -default=>'',
                         -size=>'24',
			 -onChange=>"JavaScript:document.newpop3.pop3passwd.value='';",
                         -override=>'1');
   $html =~ s/\@\@\@HOSTFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'pop3port',
                         -default=>$config{'pop3_usessl_by_default'} ?  '995' : '110',
                         -size=>'4',
                         -onChange=>"JavaScript:document.newpop3.pop3passwd.value='';",
                         -override=>'1');
   $html =~ s/\@\@\@PORTFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'pop3user',
                         -default=>'',
                         -size=>'16',
			 -onChange=>"JavaScript:document.newpop3.pop3passwd.value='';",
                         -override=>'1');
   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = password_field(-name=>'pop3passwd',
                         -default=>'',
                         -size=>'8',
                         -override=>'1');
   $html =~ s/\@\@\@PASSFIELD\@\@\@/$temphtml/;

   # if hidden, disable user to change this option
   if ($config{'pop3_delmail_hidden'}) {
      templateblock_disable($html, 'DELPOP3STR');
      $temphtml = ow::tool::hiddens(pop3del=>$config{'pop3_delmail_by_default'});
      $html =~ s/\@\@\@DELCHECKBOX\@\@\@/$temphtml/;
   } else {
      templateblock_enable($html, 'DELPOP3STR');
      $temphtml = checkbox(-name=>'pop3del',
                           -value=>'1',
                           -checked=>$config{'pop3_delmail_by_default'},
                           -label=>'');
      $html =~ s/\@\@\@DELCHECKBOX\@\@\@/$temphtml/;
   }

   if ($is_ssl_supported) {
      templateblock_enable($html, 'USEPOP3SSL');
      $temphtml = checkbox(-name=>'pop3ssl',
                           -value=>'1',
                           -checked=>$config{'pop3_usessl_by_default'},
                           -label=>'',
                           -onClick=>'ssl();');
      $html =~ s/\@\@\@USEPOP3SSLCHECKBOX\@\@\@/$temphtml/;
   } else {
     templateblock_disable($html, 'USEPOP3SSL');
     $temphtml = ow::tool::hiddens(pop3ssl=>'0');
     $html =~ s/\@\@\@USEPOP3SSLCHECKBOX\@\@\@/$temphtml/;
   }

   $temphtml = checkbox(-name=>'enable',
                  -value=>'1',
                  -checked=>'checked',
                  -label=>'');
   $html =~ s/\@\@\@ENABLECHECKBOX\@\@\@/$temphtml/;

   $temphtml = submit(-name=>$lang_text{'addmod'},
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   foreach (sort values %accounts) {
      my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del, $enable) = split(/\@\@\@/, $_);

      $temphtml .= qq|<tr>\n|.
      		   qq|<td bgcolor=$bgcolor><a href="Javascript:Update('$pop3host','$pop3port','$pop3ssl','$pop3user','******','$pop3del','$enable')">$pop3host</a></td>\n|.
      		   qq|<td bgcolor=$bgcolor>$pop3port</td>\n|;

      $temphtml .= qq|<td align="center" bgcolor=$bgcolor>\n|;
      if ($is_ssl_supported) {
         if ( $pop3ssl == 1) {
            $temphtml .= $lang_text{'yes'};
         } else {
            $temphtml .= $lang_text{'no'};
         }
      } else {
         $temphtml .= "&nbsp;";
      }
      $temphtml .= "</td>";

      $temphtml .= qq|<td align="center" bgcolor=$bgcolor><a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=pop3fetch&pop3user=$pop3user&pop3host=$pop3host&pop3port=$pop3port&pop3user=$pop3user&$urlparmstr">$pop3user</a></td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor>\*\*\*\*\*\*</td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor>\n|;

      if ($config{'pop3_delmail_hidden'}) {
      	 $temphtml .= "&nbsp;";
      } else {
         if ( $pop3del == 1) {
       	    $temphtml .= $lang_text{'delete'};
         } else {
      	    $temphtml .= $lang_text{'reserve'};
         }
      }
      $temphtml .= qq|</td><td align="center" bgcolor=$bgcolor>\n|;
      if ( $enable == 1) {
      	 $temphtml .= $lang_text{'enable'};
      } else {
      	 $temphtml .= $lang_text{'disable'};
      }
      $temphtml .= "</td>";

      $temphtml .= qq|<td bgcolor=$bgcolor align="center">|.
                   start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl").
                   ow::tool::hiddens(action=>'deletepop3',
                                     pop3host=>$pop3host,
                                     pop3port=>$pop3port,
                                     pop3user=>$pop3user).
                   $formparmstr.
                   submit(-name=>$lang_text{'delete'},
                          -class=>"medtext").
                   qq|</td></tr>|.
                   end_form();

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }
   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITPOP3 ##########################################

########## MODPOP3 ###############################################
sub modpop3 {
   my $mode = shift;
   my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del, $enable);
   $pop3host = param('pop3host') || '';
   $pop3port = param('pop3port') || '110';
   $pop3ssl = param('pop3ssl') || 0;
   $pop3user = param('pop3user') || '';
   $pop3passwd = param('pop3passwd') || '';
   $pop3del = param('pop3del') || 0;
   $enable = param('enable') || 0;

   # strip beginning and trailing spaces from hash key
   $pop3host =~ s/^\s*//;
   $pop3host =~ s/\s*$//;
   $pop3host =~ s/[#&=\?]//g;

   $pop3port =~ s/^\s*//;
   $pop3port =~ s/\s*$//;

   $pop3user =~ s/^\s*//;
   $pop3user =~ s/\s*$//;
   $pop3user =~ s/[#&=\?]//g;

   $pop3passwd =~ s/^\s*//;
   $pop3passwd =~ s/\s*$//;

   my $pop3bookfile = dotpath('pop3.book');

   if ( ($pop3host && $pop3user && $pop3passwd)
     || (($mode eq 'delete') && $pop3host && $pop3user) ) {
      my %accounts;

      if (readpop3book($pop3bookfile, \%accounts) <0) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $pop3bookfile!");
      }

      if ($mode eq 'delete') {
         delete $accounts{"$pop3host:$pop3port\@\@\@$pop3user"};
      } else {
         if ( (-s $pop3bookfile) >= ($config{'maxbooksize'} * 1024) ) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'} <a href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&amp;$urlparmstr">$lang_err{'back'}</a> $lang_err{'tryagain'}|);
         }
         foreach ( @{$config{'pop3_disallowed_servers'}} ) {
            if ($pop3host eq $_) {
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'disallowed_pop3'} $pop3host");
            }
         }
         $pop3port=110 if ($pop3port!~/^\d+$/);
         if ( defined($accounts{"$pop3host:$pop3port\@\@\@$pop3user"}) &&
              $pop3passwd eq "******") {
            $pop3passwd=(split(/\@\@\@/, $accounts{"$pop3host:$pop3port\@\@\@$pop3user"}))[4];
         }
         $accounts{"$pop3host:$pop3port\@\@\@$pop3user"}="$pop3host\@\@\@$pop3port\@\@\@$pop3ssl\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable";
      }

      if (writepop3book($pop3bookfile, \%accounts)<0) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $pop3bookfile!");
      }

      # rmove unused pop3 uidl db
      if (opendir(POP3DIR, dotpath('pop3'))) {
         my @delfiles;
         while (defined(my $filename = readdir(POP3DIR))) {
            if ( $filename=~/uidl\.(.*)\.(?:db|dir|pag)$/) {
               $_=$1; /^(.*)\@(.*):(.*)$/;
               ($pop3user, $pop3host, $pop3port)=($1, $2, $3);
               if (!defined($accounts{"$pop3host:$pop3port\@\@\@$pop3user"})) {
                  push (@delfiles, ow::tool::untaint(dotpath($filename)));
               }
            }
         }
         closedir(POP3DIR);
         unlink(@delfiles);
      }
   }
   editpop3();
}
########## END MODPOP3 ###########################################

########## EDITFILTER ############################################
sub editfilter {
   my @filterrules=();
   my @globalfilterrules=();

   my ($html, $temphtml);
   $html = applystyle(readtemplate("editfilter.template"));

   my $filterbookfile = dotpath('filter.book');
   my $filterruledb = dotpath('filter.ruledb');

   my $filterbooksize = ( -s $filterbookfile ) || 0;
   my $freespace = int($config{'maxbooksize'} - ($filterbooksize/1024) + .5);
   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace $lang_sizes{'kb'}/;

   if ($prefs_caller eq "cal") {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'calendar'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=$prefs{'calendar_defaultview'}&amp;$urlparmstr"|);
   } elsif ($prefs_caller eq "webdisk") {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'webdisk'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=showdir&amp;$urlparmstr"|);
   } elsif ($prefs_caller eq "read") {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder), qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;$urlparmstr"|);
   } else {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder), qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;$urlparmstr"|);
   }

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                         -name=>'newfilter').
               ow::tool::hiddens(action=>'addfilter').
               $formparmstr;
   $html =~ s/\@\@\@STARTFILTERFORM\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFILTERFORM\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'priority',
                          -values=>['01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20'],
                          -default=>'10');
   $html =~ s/\@\@\@PRIORITYMENU\@\@\@/$temphtml/;

   my %labels = ('from'=>$lang_text{'from'},
                        'to'=>$lang_text{'to'},
                        'subject'=>$lang_text{'subject'},
                        'smtprelay'=>$lang_text{'smtprelay'},
                        'header'=>$lang_text{'header'},
                        'textcontent'=>$lang_text{'textcontent'},
                        'attfilename'=>$lang_text{'attfilename'});
   $temphtml = popup_menu(-name=>'ruletype',
                          -values=>['from', 'to', 'subject', 'smtprelay', 'header', 'textcontent' ,'attfilename'],
                          -default=>'subject',
                          -labels=>\%labels);
   $html =~ s/\@\@\@RULEMENU\@\@\@/$temphtml/;

   my %labels = ('include'=>$lang_text{'include'},
                        'exclude'=>$lang_text{'exclude'});
   $temphtml = popup_menu(-name=>'include',
                          -values=>['include', 'exclude'],
                          -labels=>\%labels);
   $html =~ s/\@\@\@INCLUDEMENU\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'text',
                         -default=>'',
                         -size=>'26',
                         -accesskey=>'I',
                         -override=>'1');
   $html =~ s/\@\@\@TEXTFIELD\@\@\@/$temphtml/;

   my %labels = ('move'=>$lang_text{'move'},
                 'copy'=>$lang_text{'copy'});
   $temphtml = popup_menu(-name=>'op',
                          -values=>['move', 'copy'],
                          -labels=>\%labels);
   $html =~ s/\@\@\@OPMENU\@\@\@/$temphtml/;

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);
   foreach (@validfolders, 'DELETE') {
      if ( defined($lang_folders{$_}) ) {
          $labels{$_} = $lang_folders{$_};
      } else {
         $labels{$_} = $_;
      }
   }
   $temphtml = popup_menu(-name=>'destination',
                          -values=>[@validfolders, 'DELETE'],
                          -default=>'mail-trash',
                          -labels=>\%labels);
   $html =~ s/\@\@\@FOLDERMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'enable',
                        -value=>'1',
                        -checked=>"checked",
                        -label=>'');
   $html =~ s/\@\@\@ENABLECHECKBOX\@\@\@/$temphtml/;

   $temphtml = submit(-name=>$lang_text{'addmod'},
                      -accesskey=>'A',
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   my ($_PRIORITY, $_RULETYPE, $_INCLUDE, $_TEXT, $_OP, $_DESTINATION, $_ENABLE, $_REGEX_TEXT)=(0,1,2,3,4,5,6,7);

   ## get @filterrules ##
   if ( -f $filterbookfile ) {
      open (FILTER, $filterbookfile) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $filterbookfile! ($!)");
      while (<FILTER>) {
         chomp($_);
         if (/^\d+\@\@\@/) { # add valid rule only (Filippo Dattola)
            my @rule=split(/\@\@\@/);
            next if (!is_defaultfolder($rule[$_DESTINATION]) && !$config{'enable_userfolders'});
            push(@filterrules, \@rule);
         }
      }
      close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $filterbookfile! ($!)");
   }
   @filterrules=sort {
                     ${$a}[$_PRIORITY]                   <=> ${$b}[$_PRIORITY]                   or
                     $op_order{${$a}[$_OP]}              <=> $op_order{${$b}[$_OP]}              or
                     $ruletype_order{${$a}[$_RULETYPE]}  <=> $ruletype_order{${$b}[$_RULETYPE]}  or
                     $folder_order{${$a}[$_DESTINATION]} <=> $folder_order{${$b}[$_DESTINATION]}
                     } @filterrules;

   if ( $config{'enable_globalfilter'} && -f "$config{'global_filterbook'}" ) {
      if ( open (FILTER, "$config{'global_filterbook'}") ) {
         while (<FILTER>) {
            chomp($_);
            if (/^\d+\@\@\@/) { # add valid rule only (Filippo Dattola)
               my @rule=split(/\@\@\@/);
               next if (!is_defaultfolder($rule[$_DESTINATION]) && !$config{'enable_userfolders'});
               push(@globalfilterrules, \@rule);
            }
         }
         close (FILTER);
      }
   }
   @globalfilterrules=sort {
                     ${$a}[$_PRIORITY]                   <=> ${$b}[$_PRIORITY]                   or
                     $op_order{${$a}[$_OP]}              <=> $op_order{${$b}[$_OP]}              or
                     $ruletype_order{${$a}[$_RULETYPE]}  <=> $ruletype_order{${$b}[$_RULETYPE]}  or
                     $folder_order{${$a}[$_DESTINATION]} <=> $folder_order{${$b}[$_DESTINATION]}
                     } @globalfilterrules;

   $temphtml = '';
   my %FILTERRULEDB;
   my $bgcolor = $style{"tablerow_dark"};
   ow::dbm::open(\%FILTERRULEDB, $filterruledb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} db $filterruledb");

   for (my $i=0; $i<=$#filterrules; $i++) {
      my ($priority, $ruletype, $include, $text, $op, $destination, $enable) = @{$filterrules[$i]};
      my ($matchcount, $matchdate)=split(":", $FILTERRULEDB{"$ruletype\@\@\@$include\@\@\@$text\@\@\@$destination"});

      $temphtml .= "<tr>\n";
      if ($matchdate) {
         $matchdate=ow::datetime::dateserial2str($matchdate,
                                     $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                     $prefs{'dateformat'}, $prefs{'hourformat'});
         $temphtml .= "<td bgcolor=$bgcolor align=center><a title='$matchdate'>$matchcount</a></font></td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>0</font></td>\n";
      }
      my $jstext = $text; $jstext=~s/\\/\\\\/g; $jstext=~s/'/\\'/g; $jstext=~s/"/!QUOT!/g;
      my $accesskeystr=$i%10+1;
      if ($accesskeystr == 10) {
         $accesskeystr=qq|accesskey="0"|;
      } elsif ($accesskeystr < 10) {
         $accesskeystr=qq|accesskey="$accesskeystr"|;
      }
      $temphtml .= qq|<td bgcolor=$bgcolor align=center>$priority</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$ruletype}</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$include}</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center><a $accesskeystr href="Javascript:Update('$priority','$ruletype','$include','$jstext','$op','$destination','$enable')">|.ow::htmltext::str2html($text).qq|</a></td>\n|;
      if ($destination eq 'INBOX') {
         $temphtml .= "<td bgcolor=$bgcolor align=center>-----</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{$op}</td>\n";
      }
      if (defined($lang_folders{$destination})) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_folders{$destination}</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$destination</td>\n";
      }
      if ($enable == 1) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'enable'}</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'disable'}</td>\n";
      }
      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl").
                   qq|<td bgcolor=$bgcolor align=center>|.
                   ow::tool::hiddens(action=>'deletefilter',
                                     ruletype=>$ruletype,
                                     include=>$include,
                                     text=>$text,
                                     destination=>$destination).
                   submit(-name=>$lang_text{'delete'},
                          -class=>"medtext").
                   $formparmstr.
                   qq|</td></tr>|.
                   end_form();
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   if ($#globalfilterrules >= 0) {
      $temphtml .= qq|<tr><td colspan="9">&nbsp;</td></tr>\n|.
                   qq|<tr><td colspan="9" bgcolor=$style{columnheader}><B>$lang_text{globalfilterrule}</B> ($lang_text{readonly})</td></tr>\n|;
   }
   $bgcolor = $style{"tablerow_dark"};

   for (my $i=0; $i<=$#globalfilterrules; $i++) {
      my ($priority, $ruletype, $include, $text, $op, $destination, $enable) = @{$globalfilterrules[$i]};
      my ($matchcount, $matchdate)=split(":", $FILTERRULEDB{"$ruletype\@\@\@$include\@\@\@$text\@\@\@$destination"});

      $temphtml .= "<tr>\n";
      if ($matchdate) {
         $matchdate=ow::datetime::dateserial2str($matchdate,
                                     $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                     $prefs{'dateformat'}, $prefs{'hourformat'});
         $temphtml .= "<td bgcolor=$bgcolor align=center><a title='$matchdate'>$matchcount</a></font></td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>0</font></td>\n";
      }
      my $jstext = $text; $jstext=~s/\\/\\\\/g; $jstext=~s/'/\\'/g; $jstext=~s/"/!QUOT!/g;
      my $accesskeystr=$i%10+1;
      if ($accesskeystr == 10) {
         $accesskeystr=qq|accesskey="0"|;
      } elsif ($accesskeystr < 10) {
         $accesskeystr=qq|accesskey="$accesskeystr"|;
      }
      $temphtml .= qq|<td bgcolor=$bgcolor align=center>$priority</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$ruletype}</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$include}</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center><a $accesskeystr href="Javascript:Update('$priority','$ruletype','$include','$jstext','$op','$destination','$enable')">|.ow::htmltext::str2html($text).qq|</a></td>\n|.
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$op}</td>\n|;
      if (defined($lang_folders{$destination})) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_folders{$destination}</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$destination</td>\n";
      }
      if ($enable == 1) {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'enable'}</td>\n";
      } else {
         $temphtml .= "<td bgcolor=$bgcolor align=center>$lang_text{'disable'}</td>\n";
      }
      $temphtml .= "<td bgcolor=$bgcolor align=center>";
      $temphtml .= "-----";
      $temphtml .= "</td>";
      $temphtml .= "</tr>";
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   ow::dbm::close(\%FILTERRULEDB, $filterruledb);

   $html =~ s/\@\@\@FILTERRULES\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITFILTER ########################################

########## MODFILTER #############################################
sub modfilter {
   ## get parameters ##
   my $mode = shift;
   my ($priority, $ruletype, $include, $text, $op, $destination, $enable);
   $priority = param('priority') || '';
   $ruletype = param('ruletype') || '';
   $include = param('include') || '';
   $text = param('text') || '';
   $op = param('op') || 'move';
   $destination = safefoldername(param('destination')) || '';
   $enable = param('enable') || 0;

   my $filterbookfile = dotpath('filter.book');
   my $filterruledb = dotpath('filter.ruledb');

   ## add mode -> can't have null $ruletype, null $text, null $destination ##
   ## delete mode -> can't have null $filter ##
   if( ($ruletype && $include && $text && $destination && $priority) ||
       (($mode eq 'delete') && ($ruletype && $include && $text && $destination)) ) {
      my %filterrules;
      if ( -f $filterbookfile ) {
         if ($mode ne 'delete' &&
             (-s $filterbookfile) >= ($config{'maxbooksize'}*1024) ) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'} <a href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editaddresses&amp;$urlparmstr">$lang_err{'back'}</a>$lang_err{'tryagain'}|);
         }
         # read personal filter and update it
         ow::filelock::lock($filterbookfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $filterbookfile!");
         open (FILTER,$filterbookfile) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $filterbookfile! ($!)");
         while(<FILTER>) {
            my ($epriority,$eruletype,$einclude,$etext,$eop,$edestination,$eenable);
            my $line=$_; chomp($line);
            ($epriority,$eruletype,$einclude,$etext,$eop,$edestination,$eenable) = split(/\@\@\@/, $line);
            $filterrules{"$eruletype\@\@\@$einclude\@\@\@$etext\@\@\@$edestination"}="$epriority\@\@\@$eruletype\@\@\@$einclude\@\@\@$etext\@\@\@$eop\@\@\@$edestination\@\@\@$eenable";
         }
         if ($mode eq 'delete') {
            delete $filterrules{"$ruletype\@\@\@$include\@\@\@$text\@\@\@$destination"};
         } else {
            $text =~ s/\@\@/\@\@ /; $text =~ s/\@$/\@ /;
            $filterrules{"$ruletype\@\@\@$include\@\@\@$text\@\@\@$destination"}="$priority\@\@\@$ruletype\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable";
         }
         close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $filterbookfile! ($!)");

         open (FILTER,">$filterbookfile") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $filterbookfile! ($!)");
         print FILTER join("\n", sort values %filterrules)."\n";
         close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $filterbookfile! ($!)");
         ow::filelock::lock($filterbookfile, LOCK_UN);

         # read global filter into hash %filterrules
         if ( $config{'global_filterbook'} ne "" && -f "$config{'global_filterbook'}" ) {
            open (FILTER,"$config{'global_filterbook'}") or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'global_filterbook'}! ($!)");
            while(<FILTER>) {
               my ($epriority,$eruletype,$einclude,$etext,$eop,$edestination,$eenable);
               my $line=$_; chomp($line);
               ($epriority,$eruletype,$einclude,$etext,$eop,$edestination,$eenable) = split(/\@\@\@/, $line);
               $filterrules{"$eruletype\@\@\@$einclude\@\@\@$etext\@\@\@$edestination"}="$epriority\@\@\@$eruletype\@\@\@$einclude\@\@\@$etext\@\@\@$eop\@\@\@$edestination\@\@\@$eenable";
            }
            close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'global_filterbook'}! ($!)");
         }

         # remove stale entries in filterrule db by checking %filterrules
         my (%FILTERRULEDB, @keys);
         ow::dbm::open(\%FILTERRULEDB, $filterruledb, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} db $filterbookfile");
         @keys=keys %FILTERRULEDB;
         foreach my $key (@keys) {
           if ( ! defined($filterrules{$key}) &&
                $key ne "filter_badaddrformat" &&
                $key ne "filter_fakedexecontenttype" &&
                $key ne "filter_fakedfrom" &&
                $key ne "filter_fakedsmtp" &&
                $key ne "filter_repeatlimit") {
              delete $FILTERRULEDB{$key};
           }
         }
         ow::dbm::close(\%FILTERRULEDB, $filterruledb);
      } else {
         open (FILTER, ">$filterbookfile" ) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $filterbookfile! ($!)");
         print FILTER "$priority\@\@\@$ruletype\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable\n";
         close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $filterbookfile! ($!)");
      }

      ## remove .filter.check ##
      unlink(dotpath('filter.check'));
   }
   if ( param('message_id') ) {
      my $searchtype = param('searchtype') || 'subject';
      my $keyword = param('keyword') || '';
      my $escapedkeyword = ow::tool::escapeURL($keyword);
      print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&sessionid=$thissession&page=$page&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&message_id=$escapedmessageid");
   } else {
      editfilter();
   }
}
########## END MODFILTER #########################################

########## EDITSTAT ##############################################
sub editstat {
   my %stationery=();

   my ($html, $temphtml);
   $html = applystyle(readtemplate("editstationery.template"));

   my $statbookfile=dotpath('stationery.book');
   if ( -f $statbookfile ) {
      my ($stat,$err)=read_stationarybook($statbookfile,\%stationery);
      openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);
   }

   if ($prefs_caller eq "") {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder), qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;$urlparmstr"|);
   } else {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder), qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   }
   $temphtml .= "&nbsp;\n";
   $temphtml .= iconlink("clearst.gif", "$lang_text{'clearstat'}", qq|accesskey="Z" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=clearstat&amp;$urlparmstr" onclick="return confirm('$lang_text{'clearstat'}?')"|). qq| \n|;
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   foreach my $key (sort keys %stationery) {
      my ($name2, $content2)=($key, $stationery{$key});
      $content2=substr($content2, 0, 100)."..." if (length($content2)>105);
      $content2=ow::htmltext::str2html($content2);
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor>$name2</a></td>|.
                   qq|<td bgcolor=$bgcolor>$content2</td>|.
                   qq|<td bgcolor=$bgcolor nowrap>|;

      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                             -name=>'stationery').
                   ow::tool::hiddens(action=>'editstat',
                                     statname=>$name2).
                   $formparmstr.
                   submit(-name=>'editstatbutton',
                          -value=>$lang_text{'edit'}).
                   submit(-name=>'delstatbutton',
                          -value=>$lang_text{'delete'});

      $temphtml .= '</td>'.end_form().'</tr>';

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }
   $html =~ s/\@\@\@STATIONERY\@\@\@/$temphtml/;

   # compose new stationery form
   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                         -name=>'stationery').
               ow::tool::hiddens(action=>'addstat').
               $formparmstr;
   $html =~ s/\@\@\@STARTSTATFORM\@\@\@/$temphtml/;

   # load the stat for edit only if editstat button is clicked
   my $statname;
   $statname=ow::tool::unescapeURL(param('statname')) if (defined(param('editstatbutton')));

   $temphtml = textfield(-name=>'statname',
                         -default=>$statname,
                         -size=>'66',
                         -override=>'1');
   $html =~ s/\@\@\@STATNAME\@\@\@/$temphtml/;

   $temphtml = textarea(-name=>'statbody',
                        -default=>$stationery{$statname},
                        -rows=>'5',
                        -columns=>$prefs{'editcolumns'}||'78',
                        -wrap=>'hard',
                        -override=>'1');
   $html =~ s/\@\@\@STATBODY\@\@\@/$temphtml/;

   $temphtml = submit(-name=>$lang_text{'savestat'});
   $html =~ s/\@\@\@SAVESTATBUTTON\@\@\@/$temphtml/;
   $temphtml = end_form();
   $html =~ s/\@\@\@ENDSTATFORM\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITSTAT ##########################################

########## DELSTAT ###############################################
sub delstat {
   my $statname = param('statname') || '';
   if ($statname) {
      my %stationery;
      my $statbookfile=dotpath('stationery.book');
      if ( -f $statbookfile ) {
         ow::filelock::lock($statbookfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $statbookfile!");
         my ($stat,$err)=read_stationarybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);

         delete $stationery{$statname};

         ($stat,$err)=write_stationarybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);

         ow::filelock::lock($statbookfile, LOCK_UN);
      }
   }

   editstat();
}
########## END DELSTAT ###########################################

########## CLEARSTAT #############################################
sub clearstat {
   my $statbookfile=dotpath('stationery.book');

   if ( -f $statbookfile ) {
      unlink($statbookfile) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $statbookfile! ($!)");
   }
   writelog("clear stationery");
   writehistory("clear stationery");

   editstat();
}
########## END CLEARSTAT #########################################

########## ADDSTAT ###############################################
sub addstat {
   my $newname = param('statname') || '';
   my $newcontent = param('statbody') || '';
   my %stationery=();

   if($newname ne '' && $newcontent ne '') {
      # save msg to file stationery
      # load the stationery first and save after, if exist overwrite
      my $statbookfile=dotpath('stationery.book');
      if ( -f $statbookfile ) {
         ow::filelock::lock($statbookfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $statbookfile!");

         my ($stat,$err)=read_stationarybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);

         $stationery{"$newname"} = $newcontent;

         ($stat,$err)=write_stationarybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);

         ow::filelock::lock($statbookfile, LOCK_UN);
      } else {
         $stationery{"$newname"} = $newcontent;
         my ($stat,$err)=write_stationarybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);
      }
   }

   editstat();
}
########## END ADDSTAT ###########################################

########## TIMEOUTWARNING ########################################
sub timeoutwarning {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("timeoutwarning.template"));
   $html =~ s/\@\@\@USEREMAIL\@\@\@/$prefs{'email'}/g;
   httpprint([], [htmlheader(), $html, htmlfooter(0)]);
}
########## END TIMEOUTWARNING ####################################

########## READ_STATIONARYBOOK ######################################
# Read the stationary book file (assumes locking has been done elsewhere)
sub read_stationarybook {
   my ($file, $r_stationary)=@_;
   my ($stat,$err)=(0);

   # read openwebmail addressbook
   if ( open(STATBOOK, $file) ) {
      while (<STATBOOK>) {
         my ($name, $content) = split(/\@\@\@/, $_, 2);
         chomp($name); chomp($content);
         $$r_stationary{"$name"} = ow::tool::unescapeURL($content);
      }
      close (STATBOOK) or  ($stat,$err)=(-1, "$lang_err{'couldnt_close'} $file! ($!)");
   } else {
      ($stat,$err)=(-1, "$lang_err{'couldnt_open'} $file! ($!)");
   }

   return ($stat,$err);
}
########## END READ_STATIONARYBOOK ######################################

########## WRITE_STATIONARYBOOK ######################################
# Write the stationary book file (assumes locking has been done elsewhere)
sub write_stationarybook {
   my ($file, $r_stationary)=@_;
   my ($stat,$err, $stationarytowrite)=(0);

   # maybe this should be limited in size some day?
   foreach (sort keys %$r_stationary) {
      my ($name,$content)=($_, ow::tool::escapeURL($$r_stationary{$_}));
      $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
      $stationarytowrite .= "$name\@\@\@$content\n";
   }

   if ( open(STATBOOK, ">$file") ) {
      print STATBOOK $stationarytowrite;
      close (STATBOOK) or  ($stat,$err)=(-1, "$lang_err{'couldnt_close'} $file! ($!)");
   } else {
      ($stat,$err)=(-1, "$lang_err{'couldnt_open'} $file! ($!)");
   }

   return ($stat,$err);
}
########## END WRITE_STATIONARYBOOK ######################################
