#!/usr/bin/suidperl -T
#
# openwebmail-prefs.pl - preference configuration, book editing program
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(.*?)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^([^\s]*)/) { $SCRIPT_DIR=$1; }
}
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

$ENV{PATH} = ""; # no PATH should be needed
$ENV{ENV} = "";      # no startup script for sh
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "ow-shared.pl";
require "filelock.pl";
require "mime.pl";
require "iconv.pl";
require "htmltext.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

# extern vars
use vars qw($persistence_count);
use vars qw(%languagenames %languagecharsets @openwebmailrcitem); # defined in ow-shared.pl
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err
	    %lang_onofflabels %lang_sortlabels
            %lang_disableemblinklabels  %lang_msgformatlabels
            %lang_withoriglabels %lang_receiptlabels
            %lang_ctrlpositionlabels %lang_sendpositionlabels
            %lang_abookbuttonpositionlabels
	    %lang_timelabels %lang_wday);	# defined in lang/xy
use vars qw(%charset_convlist);			# defined in iconv.pl
use vars qw(%fontsize);				# defined in ow-shared.pl

# local globals
use vars qw($sort $page);
use vars qw($messageid $escapedmessageid);
use vars qw($userfirsttime $prefs_caller);
use vars qw($urlparmstr $formparmstr);

########################## MAIN ##############################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop
$SIG{CHLD}=sub { wait }; 	# prevent zombie

userenv_init();

$page = param("page") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';
$messageid=param("message_id") || '';
$escapedmessageid=escapeURL($messageid);

$userfirsttime = param("userfirsttime") || 0;
$prefs_caller= param("prefs_caller");	# passed from the caller

$urlparmstr=qq|&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;sort=$sort&amp;page=$page&amp;userfirsttime=$userfirsttime&amp;prefs_caller=$prefs_caller|;
$formparmstr=hidden(-name=>'sessionid',
                    -default=>$thissession,
                    -override=>'1') .
             hidden(-name=>'folder',
                    -default=>$folder,
                    -override=>'1').
             hidden(-name=>'message_id',
                    -default=>$messageid,
                    -override=>'1').
             hidden(-name=>'sort',
                    -default=>$sort,
                    -override=>'1') .
             hidden(-name=>'page',
                    -default=>$page,
                    -override=>'1').
             hidden(-name=>'userfirsttime',
                    -default=>$userfirsttime,
                    -override=>'1').
             hidden(-name=>'prefs_caller',
                    -default=>$prefs_caller,
                    -override=>'1');

my $action = param("action");
if ($action eq "about" && $config{'enable_about'}) {
   about();
} elsif ($action eq "userfirsttime") {
   userfirsttime();
} elsif ($action eq "editprefs") {
   editprefs();
} elsif ($action eq "saveprefs") {
   saveprefs();
} elsif ($action eq "editpassword" && $config{'enable_changepwd'}) {
   editpassword();
} elsif ($action eq "changepassword" && $config{'enable_changepwd'}) {
   changepassword();
} elsif ($action eq "viewhistory" && $config{'enable_history'}) {
   viewhistory();
} elsif ($action eq "editfroms" && $config{'enable_setfrom'} ) {
   editfroms();
} elsif ($action eq "addfrom") {
   modfrom("add");
} elsif ($action eq "deletefrom") {
   modfrom("delete");
} elsif ($action eq "editpop3" && $config{'enable_pop3'}) {
   editpop3();
} elsif ($action eq "addpop3" && $config{'enable_pop3'}) {
   modpop3("add");
} elsif ($action eq "deletepop3" && $config{'enable_pop3'}) {
   modpop3("delete");
} elsif ($action eq "editfilter") {
   editfilter();
} elsif ($action eq "addfilter") {
   modfilter("add");
} elsif ($action eq "deletefilter") {
   modfilter("delete");
} elsif (param('delstatbutton') && $config{'enable_stationery'}) {
   delstat();
} elsif ((param('editstatbutton')||$action eq "editstat") && $config{'enable_stationery'}) {
   editstat();
} elsif ($action eq "clearstat" && $config{'enable_stationery'}) {
   clearstat();
} elsif ($action eq "addstat" && $config{'enable_stationery'}) {
   addstat();
} elsif ($action eq "timeoutwarning") {
   timeoutwarning();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}

openwebmail_requestend();
###################### END MAIN ##############################

########################### ABOUT ##############################
sub about {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("about.template"));

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = '';
   if ($config{'about_info_software'}) {
      my $os=`/bin/uname -srm`;
      $os=`/usr/bin/uname -srm` if ( -f "/usr/bin/uname");
      my $flag;
      $flag.='Persistence' if ($persistence_count>0);
      $flag.=', HTTP Compression' if (cookie("openwebmail-httpcompress") &&
                                     $ENV{'HTTP_ACCEPT_ENCODING'}=~/\bgzip\b/ &&
                                     has_zlib());
      $flag="( $flag )" if ($flag);

      $temphtml.= qq|<tr><td colspan=2 bgcolor=$style{'columnheader'}><B>SOFTWARE</B></td></tr>\n|;
      $temphtml.= attr_html('OS'     , $os).
                  attr_html('PERL'   , "$^X $]").
                  attr_html('WebMail', "$config{'name'} $config{'version'} $config{'releasedate'} $flag");
   }
   if ($config{'about_info_protocol'}) {
      $temphtml.= qq|<tr><td colspan=2 bgcolor=$style{'columnheader'}><B>PROTOCOL</B></td></tr>\n|;
      foreach my $attr ( qw(SERVER_PROTOCOL HTTP_CONNECTION HTTP_KEEP_ALIVE) ) {
         $temphtml.= attr_html($attr, $ENV{$attr}) if (defined($ENV{$attr}));
      }
   }
   if ($config{'about_info_server'}) {
      $temphtml.= qq|<tr><td colspan=2 bgcolor=$style{'columnheader'}><B>SERVER</B></td></tr>\n|;
      foreach my $attr ( qw(HTTP_HOST SCRIPT_NAME) ) {
         $temphtml.= attr_html($attr, $ENV{$attr}) if (defined($ENV{$attr}));
      }
      if ($config{'about_info_scriptfilename'}) {
         $temphtml.= attr_html('SCRIPT_FILENAME', $ENV{'SCRIPT_FILENAME'}) if (defined($ENV{'SCRIPT_FILENAME'}));
      }
      foreach my $attr ( qw(SERVER_NAME SERVER_ADDR SERVER_PORT SERVER_SOFTWARE) ) {
         $temphtml.= attr_html($attr, $ENV{$attr}) if (defined($ENV{$attr}));
      }
   }
   if ($config{'about_info_client'}) {
      $temphtml.= qq|<tr><td colspan=2 bgcolor=$style{'columnheader'}><B>CLIENT</B></td></tr>\n|;
      foreach my $attr ( qw(REMOTE_ADDR REMOTE_PORT HTTP_X_FORWARDED_FOR HTTP_VIA HTTP_USER_AGENT HTTP_ACCEPT_ENCODING HTTP_ACCEPT_LANGUAGE) ) {
         $temphtml.= attr_html($attr, $ENV{$attr}) if (defined($ENV{$attr}));
      }
   }
   $html =~ s/\@\@\@INFORECORDS\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(1)]);
}

sub attr_html {
   my $temphtml = qq|<tr>|.
                  qq|<td bgcolor=$style{'window_dark'}>$_[0]</td>|.
                  qq|<td bgcolor=$style{'window_dark'}>$_[1]</td>|.
                  qq|</tr>|;
   return($temphtml);
}
######################### END ABOUT ##########################

##################### FIRSTTIMEUSER ################################
sub userfirsttime {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("userfirsttime.template"));

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl");
   $temphtml .= hidden(-name=>'action',
                      -default=>'editprefs',
                      -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'userfirsttime',
                       -default=>'1',
                       -override=>'1');
   $temphtml .= submit("$lang_text{'continue'}");
   $temphtml .= end_form();
   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
################### END FIRSTTIMEUSER ##############################

#################### EDITPREFS ###########################
sub editprefs {
   if (param('language') =~ /^([\d\w\.\-_]+)$/ ) {
      my $language=$1;
      if ( -f "$config{'ow_langdir'}/$language" ) {
         $prefs{'language'}=$language;
         $prefs{'charset'}=$languagecharsets{$language};
         readlang($language);
      }
   }

   my ($html, $temphtml);
   $html = applystyle(readtemplate("prefs.template"));

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                          -name=>'prefsform').
               hidden(-name=>'action',
                      -default=>'saveprefs',
                      -override=>'1').
               $formparmstr;
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

   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, "$folderdir/.from.book");

   if ($userfrom{$prefs{'email'}}) {
      $temphtml = $userfrom{$prefs{'email'}};
   } else {
      $temphtml = "&nbsp;";
   }
   $html =~ s/\@\@\@REALNAME\@\@\@/$temphtml/;

   $temphtml = '';
   if (!$userfirsttime) {
      if ($prefs_caller eq "cal") {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'calendar'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=calmonth&amp;$urlparmstr"|);
      } elsif ($prefs_caller eq "webdisk") {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'webdisk'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=showdir&amp;$urlparmstr"|);
      } elsif ($prefs_caller eq "read") {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;$urlparmstr"|);
      } else {
         $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;$urlparmstr"|);
      }
      $temphtml .= qq|&nbsp;\n|;
   }

   if ($config{'enable_setfrom'}) {
      $temphtml .= iconlink("editfroms.gif", $lang_text{'editfroms'}, qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfroms&amp;$urlparmstr"|);
   }
   if ($config{'enable_stationery'}) {
      $temphtml .= iconlink("editst.gif", $lang_text{'editstat'}, qq|accesskey="S" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editstat&amp;$urlparmstr"|);
   }
   if ($config{'enable_pop3'}) {
      $temphtml .= iconlink("pop3setup.gif", $lang_text{'pop3book'}, qq|accesskey="G" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&amp;$urlparmstr"|);
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
   if ($config{'enable_about'}) {
      $temphtml .= iconlink("info.gif", $lang_text{'about'}, qq|accesskey="I" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=about&amp;$urlparmstr"|);
   }

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;


   my $defaultlanguage=$prefs{'language'};
   my $defaultcharset=$prefs{'charset'}||$languagecharsets{$prefs{'language'}};
   my $defaultsendcharset=$prefs{'sendcharset'}||'sameascomposing';
   if (param('language') =~ /^([\d\w\.\-_]+)$/ ) {
      $defaultlanguage=$1;
      $defaultcharset=$languagecharsets{$1};
      if ($defaultlanguage =~ /^ja_JP/ ) {
         $defaultsendcharset='iso-2022-jp';
      } else {
         $defaultsendcharset='sameascomposing';
      }
   }

   my @availablelanguages = sort {
                                 $languagenames{$a} cmp $languagenames{$b}
                                 } keys(%languagenames);
   $temphtml = popup_menu(-name=>'language',
                          -values=>\@availablelanguages,
                          -default=>$defaultlanguage,
                          -labels=>\%languagenames,
                          -onChange=>"javascript:if (this.value != null) { window.location.href='$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr&amp;language='+this.value; }",
                          -accesskey=>'1',
                          -override=>'1');
   $html =~ s/\@\@\@LANGUAGEMENU\@\@\@/$temphtml/;

   my %tmpset=reverse %languagecharsets;
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
                          -override=>'1').
               qq|&nbsp;|. iconlink("earth.gif", $lang_text{'tzmap'}, qq|href="$config{'ow_htmlurl'}/images/timezone.jpg" target="_timezonemap"|). qq|\n|;
   $html =~ s/\@\@\@TIMEOFFSETMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'daylightsaving',
                          -values=>[ 'auto', 'on', 'off' ],
                          -labels=>\%lang_onofflabels,
                          -default=>$prefs{'daylightsaving'},
                          -override=>'1');
   $html =~ s/\@\@\@DAYLIGHTSAVINGMENU\@\@\@/$temphtml/;

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
   if ($config{'enable_editfrom'}) {
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

      $html =~ s/\@\@\@FORWARDSTART\@\@\@//;
      $html =~ s/\@\@\@FORWARDEND\@\@\@//;
   } else {
      $html =~ s/\@\@\@FORWARDADDRESS\@\@\@/not available/;
      $html =~ s/\@\@\@KEEPLOCALCOPY\@\@\@/not available/;
      $html =~ s/\@\@\@FORWARDSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@FORWARDEND\@\@\@/-->/;
   }

   if ($config{'enable_autoreply'}) {
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

      $html =~ s/\@\@\@AUTOREPLYSTART\@\@\@//;
      $html =~ s/\@\@\@AUTOREPLYEND\@\@\@//;

   } else {
      $html =~ s/\@\@\@AUTOREPLYCHECKBOX\@\@\@/not available/;
      $html =~ s/\@\@\@AUTOREPLYSUBJECT\@\@\@/not available/;
      $html =~ s/\@\@\@AUTOREPLYTEXT\@\@\@/not available/;

      $html =~ s/\@\@\@AUTOREPLYSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@AUTOREPLYEND\@\@\@/-->/;
   }

   $temphtml = textarea(-name=>'signature',
                        -default=>$prefs{'signature'},
                        -rows=>'5',
                        -columns=>$prefs{'editcolumns'}||'78',
                        -wrap=>'hard',
                        -override=>'1');
   $html =~ s/\@\@\@SIGAREA\@\@\@/$temphtml/;


   # Get a list of valid style files
   my @styles;
   opendir (STYLESDIR, "$config{'ow_stylesdir'}") or
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
                          -override=>'1');
   $html =~ s/\@\@\@STYLEMENU\@\@\@/$temphtml/;

   # Get a list of valid iconset
   my @iconsets;
   opendir (ICONSETSDIR, "$config{'ow_htmldir'}/images/iconsets") or
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
                          -override=>'1');
   $html =~ s/\@\@\@ICONSETMENU\@\@\@/$temphtml/;

   # Get a list of valid background images
   my @backgrounds;
   opendir (BACKGROUNDSDIR, "$config{'ow_htmldir'}/images/backgrounds") or
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

   my ($background, $bgurl);
   if ( $prefs{'bgurl'}=~m!$config{'ow_htmlurl'}/images/backgrounds/([\w\d\.\-_]+)! ) {
      $background=$1; $bgurl="";
   } else {
      $background="USERDEFINE"; $bgurl=$prefs{'bgurl'};
   }

   $temphtml = popup_menu(-name=>'background',
                          -values=>\@backgrounds,
                          -labels=>{ 'USERDEFINE'=>"--$lang_text{'userdef'}--" },
                          -default=>$background,
                          -onChange=>"JavaScript:document.prefsform.bgurl.value='';",
                          -override=>'1');
   $html =~ s/\@\@\@BACKGROUNDMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'bgrepeat',
                        -value=>'1',
                        -checked=>$prefs{'bgrepeat'},
                        -label=>'');
   $html =~ s/\@\@\@BGREPEATCHECKBOX\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'bgurl',
                         -default=>$bgurl,
                         -size=>'35',
                         -override=>'1');
   $html =~ s/\@\@\@BGURLFIELD\@\@\@/$temphtml/;

   my @fontsize=sort { ($a=~/px$/ - $b=~/px$/) || $a <=> $b } keys %fontsize;
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
                          -override=>'1');
   $html =~ s/\@\@\@FONTSIZEMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'dateformat',
                          -values=>['mm/dd/yyyy', 'dd/mm/yyyy', 'yyyy/mm/dd',
                                      'mm-dd-yyyy', 'dd-mm-yyyy', 'yyyy-mm-dd',
                                      'mm.dd.yyyy', 'dd.mm.yyyy', 'yyyy.mm.dd'],
                          -default=>$prefs{'dateformat'},
                          -override=>'1');
   $html =~ s/\@\@\@DATEFORMATMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'hourformat',
                          -values=>[12, 24],
                          -default=>$prefs{'hourformat'},
                          -override=>'1');
   $html =~ s/\@\@\@HOURFORMATMENU\@\@\@/$temphtml/;


   $temphtml = popup_menu(-name=>'ctrlposition_folderview',
                          -values=>['top', 'bottom'],
                          -default=>$prefs{'ctrlposition_folderview'} || 'bottom',
                          -labels=>\%lang_ctrlpositionlabels,
                          -override=>'1');
   $html =~ s/\@\@\@CTRLPOSITIONFOLDERVIEWMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'msgsperpage',
                          -values=>[8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,50,100,500,1000],
                          -default=>$prefs{'msgsperpage'},
                          -override=>'1');
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
                          -override=>'1');
   $html =~ s/\@\@\@FIELDORDERMENU\@\@\@/$temphtml/;

   # since there is already sort param inherited from outside prefs form,
   # so the prefs form pass the sort param as msgsort
   $temphtml = popup_menu(-name=>'msgsort',
                          -values=>['date','date_rev','sender','sender_rev',
                                      'size','size_rev','subject','subject_rev',
                                      'status'],
                          -default=>$prefs{'sort'},
                          -labels=>\%lang_sortlabels,
                          -override=>'1');
   $html =~ s/\@\@\@SORTMENU\@\@\@/$temphtml/;


   $temphtml = checkbox(-name=>'confirmmsgmovecopy',
                        -value=>'1',
                        -checked=>$prefs{'confirmmsgmovecopy'},
                        -label=>'');
   $html =~ s/\@\@\@CONFIRMMSGMOVECOPY\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'defaultdestination',
                          -values=>['saved-messages','mail-trash', 'DELETE'],
                          -default=>$prefs{'defaultdestination'} || 'mail-trash',
                          -labels=>\%lang_folders,
                          -accesskey=>'4',
                          -override=>'1');
   $html =~ s/\@\@\@DEFAULTDESTINATIONMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'smartdestination',
                        -value=>'1',
                        -checked=>$prefs{'smartdestination'},
                        -label=>'');
   $html =~ s/\@\@\@SMARTDESTINATION\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'viewnextaftermsgmovecopy',
                        -value=>'1',
                        -checked=>$prefs{'viewnextaftermsgmovecopy'},
                        -label=>'');
   $html =~ s/\@\@\@VIEWNEXTAFTERMSGMOVECOPY\@\@\@/$temphtml/;

   if ($config{'enable_pop3'}) {
      $temphtml = checkbox(-name=>'autopop3',
                           -value=>'1',
                           -checked=>$prefs{'autopop3'},
                           -label=>'');
      $html =~ s/\@\@\@AUTOPOP3CHECKBOX\@\@\@/$temphtml/;
      $html =~ s/\@\@\@AUTOPOP3START\@\@\@//;
      $html =~ s/\@\@\@AUTOPOP3END\@\@\@//;
   } else {
      $html =~ s/\@\@\@AUTOPOP3CHECKBOX\@\@\@/not available/;
      $html =~ s/\@\@\@AUTOPOP3START\@\@\@/<!--/;
      $html =~ s/\@\@\@AUTOPOP3END\@\@\@/-->/;
   }

   if ($config{'forced_moveoldmsgfrominbox'}) {
      $html =~ s/\@\@\@MOVEOLDCHECKBOX\@\@\@/not available/;
      $html =~ s/\@\@\@MOVEOLDSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@MOVEOLDEND\@\@\@/-->/;
   } else {
      $temphtml = checkbox(-name=>'moveoldmsgfrominbox',
                           -value=>'1',
                           -checked=>$prefs{'moveoldmsgfrominbox'},
                           -label=>'');
      $html =~ s/\@\@\@MOVEOLDMSGFROMINBOX\@\@\@/$temphtml/;
      $html =~ s/\@\@\@MOVEOLDSTART\@\@\@//;
      $html =~ s/\@\@\@MOVEOLDEND\@\@\@//;
   }


   $temphtml = popup_menu(-name=>'ctrlposition_msgread',
                          -values=>['top', 'bottom'],
                          -default=>$prefs{'ctrlposition_msgread'} || 'bottom',
                          -labels=>\%lang_ctrlpositionlabels,
                          -override=>'1');
   $html =~ s/\@\@\@CTRLPOSITIONMSGREADMENU\@\@\@/$temphtml/;

   my %headerlabels = ('simple'=>$lang_text{'simplehead'},
                       'all'=>$lang_text{'allhead'} );
   $temphtml = popup_menu(-name=>'headers',
                          -values=>['simple','all'],
                          -default=>$prefs{'headers'} || 'simple',
                          -labels=>\%headerlabels,
                          -override=>'1');
   $html =~ s/\@\@\@HEADERSMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'usefixedfont',
                  -value=>'1',
                  -checked=>$prefs{'usefixedfont'},
                  -accesskey=>'3',
                  -label=>'');
   $html =~ s/\@\@\@USEFIXEDFONT\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'usesmileicon',
                  -value=>'1',
                  -checked=>$prefs{'usesmileicon'},
                  -label=>'');
   $html =~ s/\@\@\@USESMILEICON\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'disablejs',
                  -value=>'1',
                  -checked=>$prefs{'disablejs'},
                  -label=>'');
   $html =~ s/\@\@\@DISABLEJS\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'disableemblink',
                          -values=>['none', 'cgionly', 'all'],
                          -default=>$prefs{'disableemblink'},
                          -labels=>\%lang_disableemblinklabels,
                          -override=>'1');
   $html =~ s/\@\@\@DISABLEEMBLINKMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'showimgaslink',
                  -value=>'1',
                  -checked=>$prefs{'showimgaslink'},
                  -label=>'');
   $html =~ s/\@\@\@SHOWIMGASLINK\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'sendreceipt',
                          -values=>['ask', 'yes', 'no'],
                          -default=>$prefs{'sendreceipt'} || 'ask',
                          -labels=>\%lang_receiptlabels,
                          -accesskey=>'5',
                          -override=>'1');
   $html =~ s/\@\@\@SENDRECEIPTMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'msgformat',
                          -values=>['auto', 'text', 'html', 'both'],
                          -default=>$prefs{'msgformat'},
                          -labels=>\%lang_msgformatlabels,
                          -override=>'1');
   $html =~ s/\@\@\@MSGFORMATMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'editcolumns',
                          -values=>[60,62,64,66,68,70,72,74,76,78,80,82,84,86,88,90,100,110,120],
                          -default=>$prefs{'editcolumns'},
                          -override=>'1');
   $html =~ s/\@\@\@EDITCOLUMNSMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'editrows',
                          -values=>[10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,50,60,70,80],
                          -default=>$prefs{'editrows'},
                          -override=>'1');
   $html =~ s/\@\@\@EDITROWSMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'sendbuttonposition',
                          -values=>['before', 'after', 'both'],
                          -default=>$prefs{'sendbuttonposition'} || 'before',
                          -labels=>\%lang_sendpositionlabels,
                          -override=>'1');
   $html =~ s/\@\@\@SENDBUTTONPOSITIONMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'reparagraphorigmsg',
                        -value=>'1',
                        -checked=>$prefs{'reparagraphorigmsg'},
                        -label=>'');
   $html =~ s/\@\@\@REPARAGRAPHORIGMSG\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'replywithorigmsg',
                          -values=>['at_beginning', 'at_end', 'none'],
                          -default=>$prefs{'replywithorigmsg'} || 'at_beginning',
                          -labels=>\%lang_withoriglabels,
                          -override=>'1');
   $html =~ s/\@\@\@REPLYWITHORIGMSGMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'backupsentmsg',
                        -value=>'1',
                        -checked=>$prefs{'backupsentmsg'},
                        -label=>'');
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
                          -override=>'1');
   $html =~ s/\@\@\@SENDCHARSETMENU\@\@\@/$temphtml/;


   if ($config{'enable_smartfilters'}) {
      $html =~ s/\@\@\@FILTERSTART\@\@\@//;
      $html =~ s/\@\@\@FILTEREND\@\@\@//;

      my (%FTDB, $matchcount, $matchdate);
      if (!$config{'dbmopen_haslock'}) {
         filelock("$folderdir/.filter.book$config{'dbm_ext'}", LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderdir/.filter.book$config{'dbm_ext'}");
      }
      dbmopen (%FTDB, "$folderdir/.filter.book$config{'dbmopen_ext'}", 0600);

      $temphtml = popup_menu(-name=>'filter_repeatlimit',
                             -values=>['0','5','10','20','30','40','50','100'],
                             -default=>$prefs{'filter_repeatlimit'},
                             -accesskey=>'6',
                             -override=>'1');
      ($matchcount, $matchdate)=split(":", $FTDB{"filter_repeatlimit"});
      if ($matchdate) {
         $matchdate=dateserial2str($matchdate, $prefs{'timeoffset'}, $prefs{'dateformat'});
         $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
      }
      $html =~ s/\@\@\@FILTERREPEATLIMIT\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'filter_fakedsmtp',
                           -value=>'1',
                           -checked=>$prefs{'filter_fakedsmtp'},
                           -label=>'');
      ($matchcount, $matchdate)=split(":", $FTDB{"filter_fakedsmtp"});
      if ($matchdate) {
         $matchdate=dateserial2str($matchdate, $prefs{'timeoffset'}, $prefs{'dateformat'});
         $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
      }
      $html =~ s/\@\@\@FILTERFAKEDSMTP\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'filter_fakedfrom',
                           -value=>'1',
                           -checked=>$prefs{'filter_fakedfrom'},
                           -label=>'');
      ($matchcount, $matchdate)=split(":", $FTDB{"filter_fakedfrom"});
      if ($matchdate) {
         $matchdate=dateserial2str($matchdate, $prefs{'timeoffset'}, $prefs{'dateformat'});
         $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
      }
      $html =~ s/\@\@\@FILTERFAKEDFROM\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'filter_fakedexecontenttype',
                           -value=>'1',
                           -checked=>$prefs{'filter_fakedexecontenttype'},
                           -label=>'');
      ($matchcount, $matchdate)=split(":", $FTDB{"filter_fakedexecontenttype"});
      if ($matchdate) {
         $matchdate=dateserial2str($matchdate, $prefs{'timeoffset'}, $prefs{'dateformat'});
         $temphtml .= "&nbsp;(<a title='$matchdate'>$lang_text{'filtered'}: $matchcount</a>)";
      }
      $html =~ s/\@\@\@FILTERFAKEDEXECONTENTTYPE\@\@\@/$temphtml/;

      dbmclose(%FTDB);
      filelock("$folderdir/.filter.book$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

   } else {
      $html =~ s/\@\@\@FILTERSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@FILTEREND\@\@\@/-->/;
   }

   my @pvalues=(300,320,340,360,380,400,420,440,460,480,500,600,700,800,900,1000);
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
                          -override=>'1');
   $html =~ s/\@\@\@ABOOKWIDTHMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'abook_height',
                          -values=>\@pvalues,
                          -labels=>\%plabels,
                          -default=>$prefs{'abook_height'},
                          -override=>'1');
   $html =~ s/\@\@\@ABOOKHEIGHTMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'abook_buttonposition',
                          -values=>['before', 'after', 'both'],
                          -default=>$prefs{'abook_buttonposition'} || 'before',
                          -labels=>\%lang_abookbuttonpositionlabels,
                          -override=>'1');
   $html =~ s/\@\@\@ABOOKBUTTONPOSITIONMENU\@\@\@/$temphtml/;

   $temphtml = "$lang_text{'enable'}&nbsp;";
   $temphtml .= checkbox(-name=>'abook_defaultfilter',
                  -value=>'1',
                  -checked=>$prefs{'abook_defaultfilter'},
                  -label=>'');
   $temphtml .= "&nbsp;";
   my %searchtypelabels = ('name'=>$lang_text{'name'},
                           'email'=>$lang_text{'email'},
                           'note'=>$lang_text{'note'},
                           'all'=>$lang_text{'all'});
   $temphtml .= popup_menu(-name=>'abook_defaultsearchtype',
                           -default=>$prefs{'abook_defaultsearchtype'} || 'name',
                           -values=>['name', 'email', 'note', 'all'],
                           -labels=>\%searchtypelabels);
   $temphtml .= textfield(-name=>'abook_defaultkeyword',
                          -default=>$prefs{'abook_defaultkeyword'},
                          -size=>'16',
                          -override=>'1');
   $html =~ s/\@\@\@ABOOKDEFAULTFILTER\@\@\@/$temphtml/;


   if ($config{'enable_calendar'}) {
      $html =~ s/\@\@\@CALENDARSTART\@\@\@//;
      $html =~ s/\@\@\@CALENDAREND\@\@\@//;

      # Get a list of valid holiday files
      my @holidays;
      opendir (HOLIDAYSDIR, "$config{'ow_holidaysdir'}") or
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
                             -accesskey=>'2',
                             -override=>'1');
      $html =~ s/\@\@\@HOLIDAYDEFMENU\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'calendar_monthviewnumitems',
                             -values=>[3, 4, 5, 6, 7, 8, 9, 10],
                             -default=>$prefs{'calendar_monthviewnumitems'},
                             -accesskey=>'7',
                             -override=>'1');
      $html =~ s/\@\@\@MONTHVIEWNUMITEMSMENU\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'calendar_weekstart',
                             -values=>[1, 2, 3, 4, 5, 6, 0],
                             -labels=>\%lang_wday,
                             -default=>$prefs{'calendar_weekstart'},
                             -override=>'1');
      $html =~ s/\@\@\@WEEKSTARTMENU\@\@\@/$temphtml/;

      my @militaryhours;
      for (my $i=0; $i<24; $i++) {
         push(@militaryhours, sprintf("%02d00", $i));
      }
      $temphtml = popup_menu(-name=>'calendar_starthour',
                             -values=>\@militaryhours,
                             -default=>$prefs{'calendar_starthour'},
                             -override=>'1');
      $html =~ s/\@\@\@STARTHOURMENU\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'calendar_endhour',
                             -values=>\@militaryhours,
                             -default=>$prefs{'calendar_endhour'},
                             -override=>'1');
      $html =~ s/\@\@\@ENDHOURMENU\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'calendar_interval',
                             -values=>[5, 10, 15, 20, 30, 45, 60, 90, 120],
                             -default=>$prefs{'calendar_interval'},
                             -override=>'1');
      $html =~ s/\@\@\@INTERVALMENU\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'calendar_showemptyhours',
                           -value=>'1',
                           -checked=>$prefs{'calendar_showemptyhours'},
                           -label=>'');
      $html =~ s/\@\@\@SHOWEMPTYHOURSCHECKBOX\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'calendar_reminderdays',
                             -values=>[0, 1, 2, 3, 4, 5, 6 ,7, 14, 21, 30, 60],
                             -labels=>{ 0=>$lang_text{'none'} },
                             -default=>$prefs{'calendar_reminderdays'},
                             -override=>'1');
      $html =~ s/\@\@\@REMINDERDAYSMENU\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'calendar_reminderforglobal',
                              -value=>'1',
                              -checked=>$prefs{'calendar_reminderforglobal'},
                              -label=>'');
      $html =~ s/\@\@\@REMINDERFORGLOBALCHECKBOX\@\@\@/$temphtml/;

   } else {
      $html =~ s/\@\@\@CALENDARSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@CALENDAREND\@\@\@/-->/;
   }


   if ($config{'enable_webdisk'}) {
      $html =~ s/\@\@\@WEBDISKSTART\@\@\@//;
      $html =~ s/\@\@\@WEBDISKEND\@\@\@//;

      $temphtml = popup_menu(-name=>'webdisk_dirnumitems',
                             -values=>[10,12,14,16,18,20,22,24,26,28,30, 40, 50, 60, 70, 80, 90, 100, 150, 200, 500, 1000, 5000],
                             -default=>$prefs{'webdisk_dirnumitems'},
                             -accesskey=>'8',
                             -override=>'1');
      $html =~ s/\@\@\@DIRNUMITEMSMENU\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'webdisk_confirmmovecopy',
                           -value=>'1',
                           -checked=>$prefs{'webdisk_confirmmovecopy'},
                           -label=>'');
      $html =~ s/\@\@\@CONFIRMFILEMOVECOPY\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'webdisk_confirmdel',
                           -value=>'1',
                           -checked=>$prefs{'webdisk_confirmdel'},
                           -label=>'');
      $html =~ s/\@\@\@CONFIRMFILEDEL\@\@\@/$temphtml/;

      $temphtml = checkbox(-name=>'webdisk_confirmcompress',
                           -value=>'1',
                           -checked=>$prefs{'webdisk_confirmcompress'},
                           -label=>'');
      $html =~ s/\@\@\@CONFIRMFILECOMPRESS\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'webdisk_fileeditcolumns',
                             -values=>[80,82,84,86,88,90,92,94,96,98,100,110,120,160,192,256,512,1024,2048],
                             -default=>$prefs{'webdisk_fileeditcolumns'},
                             -override=>'1');
      $html =~ s/\@\@\@FILEEDITCOLUMNSMENU\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>'webdisk_fileeditrows',
                             -values=>[10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,50,60,70,80],
                             -default=>$prefs{'webdisk_fileeditrows'},
                             -override=>'1');
      $html =~ s/\@\@\@FILEEDITROWSMENU\@\@\@/$temphtml/;

   } else {
      $html =~ s/\@\@\@WEBDISKSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@WEBDISKEND\@\@\@/-->/;
   }


   $temphtml = checkbox(-name=>'regexmatch',
                  -value=>'1',
                  -checked=>$prefs{'regexmatch'},
                  -accesskey=>'8',
                  -label=>'');
   $html =~ s/\@\@\@REGEXMATCH\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'hideinternal',
                  -value=>'1',
                  -checked=>$prefs{'hideinternal'},
                  -label=>'');
   $html =~ s/\@\@\@HIDEINTERNAL\@\@\@/$temphtml/;

   my @intervals;
   foreach my $value (3, 5, 10, 20, 30, 60, 120, 180) {
      push(@intervals, $value) if ($value>=$config{'min_refreshinterval'});
   }
   $temphtml = popup_menu(-name=>'refreshinterval',
                          -values=>\@intervals,
                          -default=>$prefs{'refreshinterval'},
                          -labels=>\%lang_timelabels,
                          -override=>'1');
   $html =~ s/\@\@\@REFRESHINTERVALMENU\@\@\@/$temphtml/;

   # Get a list of new mail sound
   my @sounds;
   opendir (SOUNDDIR, "$config{'ow_htmldir'}/sounds") or
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
                          -override=>'1');
   my $soundurl="$config{'ow_htmlurl'}/sounds/";
   $temphtml .= "&nbsp;". iconlink("sound.gif", $lang_text{'testsound'}, qq|onclick="playsound('$soundurl', document.prefsform.newmailsound[document.prefsform.newmailsound.selectedIndex].value);"|);
   $html =~ s/\@\@\@NEWMAILSOUNDMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'newmailwindowtime',
                          -values=>[0, 3, 5, 7, 10, 20, 30, 60, 120, 300, 600],
                          -default=>$prefs{'newmailwindowtime'},
                          -override=>'1');
   $html =~ s/\@\@\@NEWMAILWINDOWTIMEMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'dictionary',
                          -values=>$config{'spellcheck_dictionaries'},
                          -default=>$prefs{'dictionary'},
                          -override=>'1');
   $html =~ s/\@\@\@DICTIONARYMENU\@\@\@/$temphtml/;

   my %dayslabels = ('0'=>$lang_text{'delatlogout'},'999999'=>$lang_text{'forever'} );
   $temphtml = popup_menu(-name=>'trashreserveddays',
                          -values=>[0,1,2,3,4,5,6,7,14,21,30,60,90,180,999999],
                          -default=>$prefs{'trashreserveddays'},
                          -labels=>\%dayslabels,
                          -override=>'1');
   $html =~ s/\@\@\@RESERVEDDAYSMENU\@\@\@/$temphtml/;

   $temphtml = popup_menu(-name=>'sessiontimeout',
                          -values=>[10,30,60,120,180,360,720,1440],
                          -default=>$prefs{'sessiontimeout'},
                          -labels=>\%lang_timelabels,
                          -override=>'1');
   $html =~ s/\@\@\@SESSIONTIMEOUTMENU\@\@\@/$temphtml/;


   $temphtml = submit(-name=>"savebutton",
                      -accesskey=>'W',
                      -value=>"$lang_text{'save'}");
   $html =~ s/\@\@\@SAVEBUTTON\@\@\@/$temphtml/;

   # show cancel button if !userfirsttime
   if ( !$userfirsttime) {
      if ($prefs_caller eq "cal") {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl");
         $temphtml .= hidden(-name=>'action',
                             -default=>'calmonth',
                             -override=>'1');
      } elsif ($prefs_caller eq "webdisk") {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl");
         $temphtml .= hidden(-name=>'action',
                             -default=>'showdir',
                             -override=>'1');
      } elsif ($prefs_caller eq "read") {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl");
         $temphtml .= hidden(-name=>'action',
                             -default=>'readmessage',
                             -override=>'1');
      } else {
         $temphtml  = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl");
         $temphtml .= hidden(-name=>'action',
                             -default=>'listmessages',
                             -override=>'1');
      }
      $temphtml .= $formparmstr;
      $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;

      $temphtml = submit(-name=>"cancelbutton",
                         -accesskey=>'Q',
                         -value=>"$lang_text{'cancel'}");
      $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;
   } else {
      $html =~ s/\@\@\@STARTCANCELFORM\@\@\@//;
      $html =~ s/\@\@\@CANCELBUTTON\@\@\@//;
   }

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
#################### END EDITPREFS ###########################

###################### SAVEPREFS #########################
sub saveprefs {
   if (! -d "$folderdir" ) {
      mkdir ("$folderdir", oct(700)) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_dir'} $folderdir ($!)");
   }
   if ($config{'enable_strictforward'} &&
       param("forwardaddress") =~ /[&;\`\<\>\(\)\{\}]/) {
      openwebmailerror(__FILE__, __LINE__, "$lang_text{'forward'} $lang_text{'email'} $lang_err{'has_illegal_chars'}");
   }

   my %rcitem_yn=qw(
      bgrepeat 1
      confirmmsgmovecopy 1
      smartdestination 1
      viewnextaftermsgmovecopy 1
      autopop3 1
      moveoldmsgfrominbox 1
      usefixedfont 1
      usesmileicon 1
      disablejs 1
      showimgaslink 1
      reparagraphorigmsg 1
      backupsentmsg 1
      filter_fakedsmtp 1
      filter_fakedfrom 1
      filter_fakedexecontenttype 1
      abook_defaultfilter 1
      calendar_showemptyhours 1
      calendar_reminderforglobal 1
      webdisk_confirmmovecopy 1
      webdisk_confirmdel 1
      webdisk_confirmcompress 1
      regexmatch 1
      hideinternal 1
   );

   my (%newprefs, $key, $value);

   foreach $key (@openwebmailrcitem) {
      $value = param("$key");
      if ($key eq 'bgurl') {
         my $background=param("background");
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
         foreach my $currlanguage (sort keys %languagenames) {
            if ($value eq $currlanguage) {
               $newprefs{$key}=$value; last;
            }
         }
      } elsif ($key eq 'sort') {
         # since there is already sort param inherited from outside prefs form,
         # so the prefs form pass the sort param as msgsort
         $newprefs{$key}=param("msgsort");
      } elsif ($key eq 'dictionary') {
         foreach my $currdictionary (@{$config{'spellcheck_dictionaries'}}) {
            if ($value eq $currdictionary) {
               $newprefs{$key}=$value; last;
            }
         }
      } elsif ($key eq 'filter_repeatlimit') {
         # if repeatlimit changed, redo filtering may be needed
         if ( $value != $prefs{'filter_repeatlimit'} ) {
            unlink("$folderdir/.filter.check");
         }
         $newprefs{$key}=$value;
      } elsif ( defined($rcitem_yn{$key}) ) {
         $value=0 if ($value eq '');
         $newprefs{$key}=$value;
      } else {
         $newprefs{$key}=$value;
      }
   }

   if ( ($newprefs{'filter_fakedsmtp'} && !$prefs{'filter_fakedsmtp'} ) ||
        ($newprefs{'filter_fakedfrom'} && !$prefs{'filter_fakedfrom'} ) ||
        ($newprefs{'filter_fakedexecontenttype'} && !$prefs{'filter_fakedexecontenttype'} ) ) {
      unlink("$folderdir/.filter.check");
   }
   if ($newprefs{'trashreserveddays'} ne $prefs{'trashreserveddays'} ) {
      unlink("$folderdir/.trash.check");
   }

   $value = param("signature") || '';
   $value =~ s/\r\n/\n/g;
   if (length($value) > 500) {  # truncate signature to 500 chars
      $value = substr($value, 0, 500);
   }
   $newprefs{'signature'}=$value;

   my $forwardaddress=param("forwardaddress");
   my $keeplocalcopy=param("keeplocalcopy")||0;
   my $autoreply=param("autoreply")||0;
   my $autoreplysubject=param("autoreplysubject");
   my $autoreplytext=param("autoreplytext");
   $autoreply=0 if (!$config{'enable_autoreply'});

   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, "$folderdir/.from.book");

   # save .forward file
   writedotforward($autoreply, $keeplocalcopy, $forwardaddress, keys %userfrom);

   # save .vacation.msg
   if ($config{'enable_autoreply'}) {
      writedotvacationmsg($autoreply, $autoreplysubject, $autoreplytext, $newprefs{'signature'}, 
				$newprefs{'email'}, $userfrom{$newprefs{'email'}} );
   }

   # save .signature
   my $signaturefile="$folderdir/.signature";
   if ( -f "$folderdir/.signature" ) {
      $signaturefile="$folderdir/.signature";
   } elsif ( -f "$homedir/.signature" ) {
      $signaturefile="$homedir/.signature";
   }
   open (SIGNATURE,">$signaturefile") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $signaturefile! ($!)");
   print SIGNATURE $newprefs{'signature'};
   close (SIGNATURE) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $signaturefile! ($!)");
   chown($uuid, (split(/\s+/,$ugid))[0], $signaturefile) if ($signaturefile eq "$homedir/.signature");

   # save .openwebmailrc
   open (RC, ">$folderdir/.openwebmailrc") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.openwebmailrc! ($!)");
   foreach my $key (@openwebmailrcitem) {
      print RC "$key=$newprefs{$key}\n";
   }
   close (RC) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.openwebmailrc! ($!)");

   %prefs = readprefs();
   %style = readstyle($prefs{'style'});
   readlang($prefs{'language'});

   my ($html, $temphtml);
   $html = applystyle(readtemplate("prefssaved.template"));

   if ($prefs_caller eq "cal") {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl");
      $temphtml .= hidden(-name=>'action',
                          -default=>'calmonth',
                          -override=>'1');
   } elsif ($prefs_caller eq "webdisk") {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-webdisk.pl");
      $temphtml .= hidden(-name=>'action',
                          -default=>'showdir',
                          -override=>'1');
   } elsif ($prefs_caller eq "read") {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl");
      $temphtml .= hidden(-name=>'action',
                          -default=>'readmessage',
                          -override=>'1');
   } else {
      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl");
      $temphtml .= hidden(-name=>'action',
                          -default=>'listmessages',
                          -override=>'1');
   }
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1') .
                hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1').
                hidden(-name=>'message_id',
                       -default=>$messageid,
                       -override=>'1').
                hidden(-name=>'sort',
                       -default=>$prefs{'sort'},	# use new prefs instead of orig $sort
                       -override=>'1') .
                hidden(-name=>'page',
                       -default=>$page,
                       -override=>'1');
   $html =~ s/\@\@\@STARTSAVEDFORM\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'continue'}");
   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
##################### END SAVEPREFS ######################

###################### R/W DOTFORWARD/DOTVACATIONMSG ##################
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
         push(@forwards, qq!| "$config{'vacationpipe'} $aliasparm $vacationuser"!);
      } else {
         push(@forwards, qq!| "$config{'vacationpipe'} -j $vacationuser"!);
      }
   }

   if ($keeplocalcopy) {
      if ($config{'auth_module'} eq 'auth_vdomain.pl') {
         push(@forwards, vdomain_userspool($user,$homedir));
      } else {
         push(@forwards, "\\$user");
      }
   }

   open(FOR, ">$homedir/.forward") || return -1;
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
         # set enviro's for vacation program
         $ENV{'USER'}=$user;
         $ENV{'LOGNAME'}=$user;
         $ENV{'HOME'}=$homedir;
         $<=$>;		# drop ruid by setting ruid = euid
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

   open(MSG, ">$homedir/.vacation.msg") || return -2;
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
   my @forwards=();
   foreach ( split(/[,;\n\r]+/, $forwardtext) ) {
      s/^\s+//; s/\s+$//;
      next if ( /^$/ );
      if (/$config{'vacationpipe'}/) { $autoreply=1; }
      elsif ( is_selfemail($_) ) { $keeplocalcopy=1; }
      else { push(@forwards, $_); }
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
###################### END R/W DOTFORWARD/DOTVACATIONMSG ##################

##################### EDITPASSWORD #######################
sub editpassword {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("chpwd.template"));

   my $chpwd_url="$config{'ow_cgiurl'}/openwebmail-prefs.pl";
   if (cookie("openwebmail-ssl")) {	# backto SSL
      $chpwd_url="https://$ENV{'HTTP_HOST'}$chpwd_url" if ($chpwd_url!~s!^https?://!https://!i);
   }
   $temphtml = startform(-name=>"passwordform",
			 -action=>$chpwd_url).
               hidden(-name=>'action',
                      -default=>'changepassword',
                      -override=>'1').
               $formparmstr;
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   # display virtual or user, but actually not used, chnagepassword grab user from sessionid
   $temphtml = textfield(-name=>'loginname',
                         -default=>$loginname,
                         -size=>'10',
                         -disabled=>1,
                         -override=>'1');
   $html =~ s/\@\@\@USERIDFIELD\@\@\@/$temphtml/;

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
               hidden(-name=>'action',
                      -default=>'editprefs',
                      -override=>'1') .
               $formparmstr.
               submit("$lang_text{'cancel'}").
               end_form();
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $html =~ s/\@\@\@PASSWDMINLEN\@\@\@/$config{'passwd_minlen'}/g;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
##################### END EDITPASSWORD #######################

##################### CHANGEPASSWORD #######################
sub changepassword {
   my $oldpassword=param("oldpassword");
   my $newpassword=param("newpassword");
   my $confirmnewpassword=param("confirmnewpassword");

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
      $>=0; $<=$>;			# set ruid/euid to root before change passwd
      if ($config{'auth_withdomain'}) {
         ($errorcode, $errormsg)=change_userpassword(\%config, "$user\@$domain", $oldpassword, $newpassword);
      } else {
         ($errorcode, $errormsg)=change_userpassword(\%config, $user, $oldpassword, $newpassword);
      }
      $<=$origruid; $>=$origeuid;	# fall back to original ruid/euid

      if ($errorcode==0) {
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
   $temphtml = startform(-action=>"$url") .
               hidden(-name=>'action',
                      -default=>'editprefs',
                      -override=>'1') .
               $formparmstr.
               submit("$lang_text{'backto'} $lang_text{'userprefs'}").
               end_form();
   $html =~ s/\@\@\@CONTINUEBUTTON\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
##################### END CHANGEPASSWORD #######################

##################### LOGINHISTORY #######################
sub viewhistory {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("history.template"));

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml="";
   open (HISTORYLOG, "$folderdir/.history.log");

   my $bgcolor = $style{"tablerow_light"};
   while (<HISTORYLOG>) {
      chomp($_);
      $_=~/^(.*?) - \[(\d+)\] \((.*?)\) (.*)$/;

      my $record;
      my ($timestamp, $pid, $ip, $misc)=($1, $2, $3, $4);
      my ($u, $event, $desc, $desc2)=split(/ \- /, $misc, 4);
      foreach my $field ($timestamp, $ip, $u, $event, $desc) {
         if ($event=~/error/i) {
            $record.=qq|<td bgcolor=$bgcolor align="center"><font color="#cc0000"><b>$field</font></b></td>\n|;
         } elsif ($event=~/warning/i) {
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
##################### END LOGINHISTORY #######################

#################### EDITFROMS ###########################
sub editfroms {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("editfroms.template"));

   my $frombooksize = ( -s "$folderdir/.from.book" ) || 0;
   my $freespace = int($config{'maxbooksize'} - ($frombooksize/1024) + .5);
   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, "$folderdir/.from.book");

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace $lang_sizes{'kb'}/;

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                         -name=>'newfrom') .
                  hidden(-name=>'action',
                         -value=>'addfrom',
                         -override=>'1').
               $formparmstr;
   $html =~ s/\@\@\@STARTFROMFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'realname',
                         -default=>'',
                         -size=>'20',
                         -override=>'1');
   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'email',
                         -default=>'',
                         -size=>'30',
                         -override=>'1');
   $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;

   if ($config{'enable_setfromemail'}) {
      $temphtml = submit(-name=>"$lang_text{'addmod'}",
                         -class=>"medtext");
   } else {
      $temphtml = submit(-name=>"$lang_text{'modify'}",
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
                   qq|<td bgcolor=$bgcolor><a href="Javascript:Update('$r','$e')">$email</a></td>|;
      $temphtml .= qq|<td bgcolor=$bgcolor align="center">|;

      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl").
                   hidden(-name=>'action',
                          -value=>'deletefrom',
                          -override=>'1') .
                   hidden(-name=>'email',
                          -value=>$email,
                          -override=>'1') .
                   $formparmstr .
                   submit(-name=>"$lang_text{'delete'}",
                          -class=>"medtext");

      $temphtml .= '</td></tr>'. end_form();

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }
   $html =~ s/\@\@\@FROMS\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
################### END EDITFROMS ########################

################### MODFROM ##############################
sub modfrom {
   my $mode = shift;
   my $realname = param("realname") || '';
   my $email = param("email") || '';

   $realname =~ s/://;
   $realname =~ s/^\s*//; # strip beginning and trailing spaces from hash key
   $realname =~ s/\s*$//;
   $email =~ s/[#&=\?]//g;

   if ($email) {
      my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, "$folderdir/.from.book");

      if ($mode eq 'delete') {
         delete $userfrom{$email};
      } else {
         if ( (-s "$folderdir/.from.book") >= ($config{'maxbooksize'} * 1024) ) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'} <a href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editfroms&amp;$urlparmstr">$lang_err{'back'}</a>$lang_err{'tryagain'}|);
         }
         if (defined($userfrom{$email}) || $config{'enable_setfromemail'}) {
            $userfrom{$email} = $realname;
         }
      }

      open (FROMBOOK, ">$folderdir/.from.book" ) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.from.book! ($!)");
      foreach $email (sort_emails_by_domainnames($config{'domainnames'}, keys %userfrom)) {
         print FROMBOOK "$email\@\@\@$userfrom{$email}\n";
      }
      close (FROMBOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.from.book! ($!)");
   }

   editfroms();
}
################## END MODFROM ###########################

#################### EDITPOP3 ###########################
sub editpop3 {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("editpop3.template"));

   my %accounts;
   my $pop3booksize = ( -s "$folderdir/.pop3.book" ) || 0;
   my $freespace = int($config{'maxbooksize'} - ($pop3booksize/1024) + .5);

   if (readpop3book("$folderdir/.pop3.book", \%accounts) <0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.pop3.book!");
   }

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace $lang_sizes{'kb'}/;

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   $temphtml .= "&nbsp;\n";
   $temphtml .= iconlink("pop3.gif", $lang_text{'retr_pop3s'}, qq|accesskey="G" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=retrpop3s&amp;$urlparmstr"|). qq| \n|;
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                         -name=>'newpop3') .
               hidden(-name=>'action',
                      -value=>'addpop3',
                      -override=>'1').
               $formparmstr;
   $html =~ s/\@\@\@STARTPOP3FORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'pop3host',
                         -default=>'',
                         -size=>'24',
			 -onChange=>"JavaScript:document.newpop3.pop3passwd.value='';",
                         -override=>'1');
   $html =~ s/\@\@\@HOSTFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'pop3port',
                         -default=>'110',
                         -size=>'4',
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
   if ($config{'delpop3mail_hidden'}) {
      $temphtml = hidden(-name=>'pop3del', -value=>$config{'delpop3mail_by_default'});
      $html =~ s/\@\@\@DELCHECKBOX\@\@\@/$temphtml/;
      $html =~ s/\@\@\@DELPOP3STRSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@DELPOP3STREND\@\@\@/-->/;
   } else {
      $temphtml = checkbox(-name=>'pop3del',
                           -value=>'1',
                           -checked=>$config{'delpop3mail_by_default'},
                           -label=>'');
      $html =~ s/\@\@\@DELCHECKBOX\@\@\@/$temphtml/;
      $html =~ s/\@\@\@DELPOP3STRSTART\@\@\@//;
      $html =~ s/\@\@\@DELPOP3STREND\@\@\@//;
   }

   $temphtml = checkbox(-name=>'enable',
                  -value=>'1',
                  -checked=>'checked',
                  -label=>'');
   $html =~ s/\@\@\@ENABLECHECKBOX\@\@\@/$temphtml/;

   $temphtml = submit(-name=>"$lang_text{'addmod'}",
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   foreach (sort values %accounts) {
      my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $enable) = split(/\@\@\@/, $_);

      $temphtml .= qq|<tr>\n|.
      		   qq|<td bgcolor=$bgcolor><a href="Javascript:Update('$pop3host','$pop3port','$pop3user','******','$pop3del','$enable')">$pop3host</a></td>\n|.
      		   qq|<td bgcolor=$bgcolor>$pop3port</td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor><a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=retrpop3&pop3user=$pop3user&pop3host=$pop3host&pop3port=$pop3port&pop3user=$pop3user&$urlparmstr">$pop3user</a></td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor>\*\*\*\*\*\*</td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor>\n|;

      if ($config{'delpop3mail_hidden'}) {
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

      $temphtml .= qq|<td bgcolor=$bgcolor align="center">|;

      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl");
      $temphtml .= hidden(-name=>'action',
                          -value=>'deletepop3',
                          -override=>'1');
      $temphtml .= hidden(-name=>'pop3host',
                          -value=>$pop3host,
                          -override=>'1');
      $temphtml .= hidden(-name=>'pop3port',
                          -value=>$pop3port,
                          -override=>'1');
      $temphtml .= hidden(-name=>'pop3user',
                          -value=>$pop3user,
                          -override=>'1');
      $temphtml .= $formparmstr;
      $temphtml .= submit(-name=>"$lang_text{'delete'}",
                          -class=>"medtext");

      $temphtml .= '</td></tr>';
      $temphtml .= end_form();

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }
   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
################### END EDITPOP3 ########################

################### MODPOP3 ##############################
sub modpop3 {
   my $mode = shift;
   my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $enable);
   $pop3host = param("pop3host") || '';
   $pop3port = param("pop3port") || '110';
   $pop3user = param("pop3user") || '';
   $pop3passwd = param("pop3passwd") || '';
   $pop3del = param("pop3del") || 0;
   $enable = param("enable") || 0;

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

   if ( ($pop3host && $pop3user && $pop3passwd)
     || (($mode eq 'delete') && $pop3host && $pop3user) ) {
      my %accounts;

      if (readpop3book("$folderdir/.pop3.book", \%accounts) <0) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.pop3.book!");
      }

      if ($mode eq 'delete') {
         delete $accounts{"$pop3host:$pop3port\@\@\@$pop3user"};
      } else {
         if ( (-s "$folderdir/.pop3.book") >= ($config{'maxbooksize'} * 1024) ) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'} <a href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editpop3&amp;$urlparmstr">$lang_err{'back'}</a> $lang_err{'tryagain'}|);
         }
         foreach ( @{$config{'disallowed_pop3servers'}} ) {
            if ($pop3host eq $_) {
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'disallowed_pop3'} $pop3host");
            }
         }
         $pop3port=110 if ($pop3port!~/^\d+$/);
         if ( defined($accounts{"$pop3host:$pop3port\@\@\@$pop3user"}) &&
              $pop3passwd eq "******") {
            $pop3passwd=(split(/\@\@\@/, $accounts{"$pop3host:$pop3port\@\@\@$pop3user"}))[3];
         }
         $accounts{"$pop3host:$pop3port\@\@\@$pop3user"}="$pop3host\@\@\@$pop3port\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable";
      }

      if (writepop3book("$folderdir/.pop3.book", \%accounts)<0) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.pop3.book!");
      }

      # rmove unused pop3 uidl db 
      if (opendir (FOLDERDIR, $folderdir)) {
         my @delfiles;
         while (defined(my $filename = readdir(FOLDERDIR))) {
            if ( $filename=~/\.uidl\.(.*)\.(?:db|dir|pag)$/) {
               $_=$1; /^(.*)\@(.*):(.*)$/;
               ($pop3user, $pop3host, $pop3port)=($1, $2, $3);
               if (!defined($accounts{"$pop3host:$pop3port\@\@\@$pop3user"})) {
                  ($filename =~ /^(.+)$/) && ($filename = $1);   # untaint
                  push (@delfiles, "$folderdir/$filename");
               }
            }
         }
         closedir (FOLDERDIR);
         unlink(@delfiles);
      }
   }
   editpop3();
}
################## END MODPOP3 ###########################

#################### EDITFILTER ###########################
sub editfilter {
   my @filterrules=();
   my @globalfilterrules=();

   my ($html, $temphtml);
   $html = applystyle(readtemplate("editfilter.template"));

   my $filterbooksize = ( -s "$folderdir/.filter.book" ) || 0;
   my $freespace = int($config{'maxbooksize'} - ($filterbooksize/1024) + .5);
   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace $lang_sizes{'kb'}/;

   if ($prefs_caller eq "cal") {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'calendar'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=calmonth&amp;$urlparmstr"|);
   } elsif ($prefs_caller eq "webdisk") {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'webdisk'}", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=showdir&amp;$urlparmstr"|);
   } elsif ($prefs_caller eq "read") {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;$urlparmstr"|);
   } else {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;$urlparmstr"|);
   }

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                         -name=>'newfilter') .
                  hidden(-name=>'action',
                         -value=>'addfilter',
                         -override=>'1') .
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
   $temphtml = popup_menu(-name=>'rules',
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

   my @movefolders=@validfolders;
   push(@movefolders, 'DELETE');
   foreach (@movefolders) {
      if ( defined($lang_folders{$_}) ) {
          $labels{$_} = $lang_folders{$_};
      } else {
         $labels{$_} = $_;
      }
   }
   $temphtml = popup_menu(-name=>'destination',
                          -values=>[@movefolders],
                          -default=>'mail-trash',
                          -labels=>\%labels);
   $html =~ s/\@\@\@FOLDERMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'enable',
                        -value=>'1',
                        -checked=>"checked",
                        -label=>'');
   $html =~ s/\@\@\@ENABLECHECKBOX\@\@\@/$temphtml/;

   $temphtml = submit(-name=>"$lang_text{'addmod'}",
                      -accesskey=>'A',
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   if ( -f "$folderdir/.filter.book" ) {
      open (FILTER,"$folderdir/.filter.book") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.filter.book! ($!)");
      while (<FILTER>) {
         chomp($_);
         push (@filterrules, $_) if(/^\d+\@\@\@/); # add valid rules only (Filippo Dattola)
      }
      close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.filter.book! ($!)");
   }
   if ( $config{'global_filterbook'} ne "" && -f "$config{'global_filterbook'}" ) {
      if ( open (FILTER, "$config{'global_filterbook'}") ) {
         while (<FILTER>) {
            chomp($_);
            push (@globalfilterrules, $_);
         }
         close (FILTER);
      }
   }

   $temphtml = '';
   my %FTDB;
   my $bgcolor = $style{"tablerow_dark"};
   if (!$config{'dbmopen_haslock'}) {
      filelock("$folderdir/.filter.book$config{'dbm_ext'}", LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderdir/.filter.book$config{'dbm_ext'}");
   }
   dbmopen(%FTDB, "$folderdir/.filter.book$config{'dbmopen_ext'}", undef);

   for (my $i=0; $i<=$#filterrules; $i++) {
      my ($priority, $rules, $include, $text, $op, $destination, $enable) = split(/\@\@\@/, $filterrules[$i]);
      my ($matchcount, $matchdate)=split(":", $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"});

      $temphtml .= "<tr>\n";
      if ($matchdate) {
         $matchdate=dateserial2str($matchdate, $prefs{'timeoffset'}, $prefs{'dateformat'});
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
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$rules}</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$include}</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center><a $accesskeystr href="Javascript:Update('$priority','$rules','$include','$jstext','$op','$destination','$enable')">$text</a></td>\n|;
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
      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl");
      $temphtml .= "<td bgcolor=$bgcolor align=center>";
      $temphtml .= hidden(-name=>'action',
                          -value=>'deletefilter',
                          -override=>'1');
      $temphtml .= hidden(-name=>'rules',
                          -value=>$rules,
                          -override=>'1');
      $temphtml .= hidden(-name=>'include',
                          -value=>$include,
                          -override=>'1');
      $temphtml .= hidden(-name=>'text',
                          -value=>$text,
                          -override=>'1');
      $temphtml .= hidden(-name=>'destination',
                          -value=>$destination,
                          -override=>'1');
      $temphtml .= submit(-name=>"$lang_text{'delete'}",
                          -class=>"medtext");
      $temphtml .= $formparmstr;
      $temphtml .= "</td></tr>";
      $temphtml .= end_form();
      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   if ($#globalfilterrules >= 0) {
      $temphtml .= qq|<tr><td colspan="9">&nbsp;</td></tr>\n|;
      $temphtml .= qq|<tr><td colspan="9" bgcolor=$style{columnheader}><B>$lang_text{globalfilterrule}</B> ($lang_text{readonly})</td></tr>\n|;
   }
   $bgcolor = $style{"tablerow_dark"};

   for (my $i=0; $i<=$#globalfilterrules; $i++) {
      my ($priority, $rules, $include, $text, $op, $destination, $enable) = split(/\@\@\@/, $globalfilterrules[$i]);
      my ($matchcount, $matchdate)=split(":", $FTDB{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"});

      $temphtml .= "<tr>\n";
      if ($matchdate) {
         $matchdate=dateserial2str($matchdate, $prefs{'timeoffset'}, $prefs{'dateformat'});
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
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$rules}</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center>$lang_text{$include}</td>\n|.
                   qq|<td bgcolor=$bgcolor align=center><a $accesskeystr href="Javascript:Update('$priority','$rules','$include','$jstext','$op','$destination','$enable')">$text</a></td>\n|.
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

   dbmclose(%FTDB);
   filelock("$folderdir/.filter.book$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

   $html =~ s/\@\@\@FILTERRULES\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
################### END EDITFILTER ########################

################### MODFILTER ##############################
sub modfilter {
   ## get parameters ##
   my $mode = shift;
   my ($priority, $rules, $include, $text, $op, $destination, $enable);
   $priority = param("priority") || '';
   $rules = param("rules") || '';
   $include = param("include") || '';
   $text = param("text") || '';
   $op = param("op") || 'move';
   $destination = safefoldername(param("destination")) || '';
   $enable = param("enable") || 0;

   ## add mode -> can't have null $rules, null $text, null $destination ##
   ## delete mode -> can't have null $filter ##
   if( ($rules && $include && $text && $destination && $priority) ||
       (($mode eq 'delete') && ($rules && $include && $text && $destination)) ) {
      my %filterrules;
      if ( -f "$folderdir/.filter.book" ) {
         if ($mode ne 'delete' &&
             (-s "$folderdir/.filter.book") >= ($config{'maxbooksize'}*1024) ) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'} <a href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editaddresses&amp;$urlparmstr">$lang_err{'back'}</a>$lang_err{'tryagain'}|);
         }
         # read personal filter and update it
         filelock("$folderdir/.filter.book", LOCK_EX|LOCK_NB) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.filter.book!");
         open (FILTER,"+<$folderdir/.filter.book") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.filter.book! ($!)");
         while(<FILTER>) {
            my ($epriority,$erules,$einclude,$etext,$eop,$edestination,$eenable);
            my $line=$_; chomp($line);
            ($epriority,$erules,$einclude,$etext,$eop,$edestination,$eenable) = split(/\@\@\@/, $line);
            $filterrules{"$erules\@\@\@$einclude\@\@\@$etext\@\@\@$edestination"}="$epriority\@\@\@$erules\@\@\@$einclude\@\@\@$etext\@\@\@$eop\@\@\@$edestination\@\@\@$eenable";
         }
         if ($mode eq 'delete') {
            delete $filterrules{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"};
         } else {
            $text =~ s/\@\@/\@\@ /; $text =~ s/\@$/\@ /;
            $filterrules{"$rules\@\@\@$include\@\@\@$text\@\@\@$destination"}="$priority\@\@\@$rules\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable";
         }
         seek (FILTER, 0, 0) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_seek'} $folderdir/.filter.book! ($!)");

         foreach (sort values %filterrules) {
            print FILTER "$_\n";
         }
         truncate(FILTER, tell(FILTER));
         close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.filter.book! ($!)");
         filelock("$folderdir/.filter.book", LOCK_UN);

         # read global filter into hash %filterrules
         open (FILTER,"$config{'global_filterbook'}") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $config{'global_filterbook'}! ($!)");
         while(<FILTER>) {
            my ($epriority,$erules,$einclude,$etext,$eop,$edestination,$eenable);
            my $line=$_; chomp($line);
            ($epriority,$erules,$einclude,$etext,$eop,$edestination,$eenable) = split(/\@\@\@/, $line);
            $filterrules{"$erules\@\@\@$einclude\@\@\@$etext\@\@\@$edestination"}="$epriority\@\@\@$erules\@\@\@$einclude\@\@\@$etext\@\@\@$eop\@\@\@$edestination\@\@\@$eenable";
         }
         close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'global_filterbook'}! ($!)");

         # remove stale entries in filterrule db by checking %filterrules
         if (!$config{'dbmopen_haslock'}) {
            filelock("$folderdir/.filter.book$config{'dbm_ext'}", LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.filter.book$config{'dbm_ext'}");
         }
         my (%FTDB, @keys);
         dbmopen (%FTDB, "$folderdir/.filter.book$config{'dbmopen_ext'}", 0600);
         @keys=keys %FTDB;
         foreach my $key (@keys) {
           if ( ! defined($filterrules{$key}) &&
                $key ne "filter_fakedsmtp" &&
                $key ne "filter_fakedfrom" &&
                $key ne "filter_fakedexecontenttype" ) {
              delete $FTDB{$key};
           }
         }
         dbmclose(%FTDB);
         filelock("$folderdir/.filter.book$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

      } else {
         open (FILTER, ">$folderdir/.filter.book" ) or
                  openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.filter.book! ($!)");
         print FILTER "$priority\@\@\@$rules\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable\n";
         close (FILTER) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.filter.book! ($!)");
      }

      ## remove .filter.check ##
      unlink("$folderdir/.filter.check");
   }
   if ( param('message_id') ) {
      my $searchtype = param("searchtype") || 'subject';
      my $keyword = param("keyword") || '';
      my $escapedkeyword = escapeURL($keyword);
      print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&sessionid=$thissession&page=$page&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&message_id=$escapedmessageid");
   } else {
      editfilter();
   }
}
################## END MODFILTER ###########################

#################### EDITSTAT ###########################
sub editstat {
   my (%stationery, $name, $content);

   my ($html, $temphtml);
   $html = applystyle(readtemplate("editstationery.template"));

   if ( -f "$folderdir/.stationery.book" ) {
      open (STATBOOK,"$folderdir/.stationery.book") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.stationery.book! ($!)");
      while (<STATBOOK>) {
         ($name, $content) = split(/\@\@\@/, $_, 2);
         chomp($name); chomp($content);
         $stationery{$name} = unescapeURL($content);
      }
      close (STATBOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.stationery.book! ($!)");
   }

   if ($prefs_caller eq "") {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;$urlparmstr"|);
   } else {
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}", qq|accesskey="F" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   }
   $temphtml .= "&nbsp;\n";
   $temphtml .= iconlink("clearst.gif", "$lang_text{'clearstat'}", qq|accesskey="Z" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=clearstat&amp;$urlparmstr" onclick="return confirm('$lang_text{'clearstat'}?')"|). qq| \n|;
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   foreach my $key (sort keys %stationery) {
      my ($name2, $content2)=($key, $stationery{$key});
      $content2=substr($content2, 0, 100)."..." if (length($content2)>105);
      $content2=str2html($content2);
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor>$name2</a></td>|.
                   qq|<td bgcolor=$bgcolor>$content2</td>|.
                   qq|<td bgcolor=$bgcolor nowrap>|;

      $temphtml .= startform(-action=>"$config{'ow_cgiurl'}/openwebmail-prefs.pl",
                             -name=>'stationery') .
                   hidden(-name=>'action',
                          -value=>'editstat',
                          -override=>'1') .
                   hidden(-name=>'statname',
                          -value=>$name2,
                          -override=>'1').
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
                         -name=>'stationery') .
               hidden(-name=>'action',
                      -value=>'addstat',
                      -override=>'1').
               $formparmstr;
   $html =~ s/\@\@\@STARTSTATFORM\@\@\@/$temphtml/;

   # load the stat for edit only if editstat button is clicked
   my $statname;
   $statname=unescapeURL(param('statname')) if (defined(param('editstatbutton')));

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
################### END EDITSTAT ########################

################### DELSTAT ##############################
sub delstat {
   my $statname = param('statname') || '';
   if ($statname) {
      my %stationery;
      my ($name,$content);
      if ( -f "$folderdir/.stationery.book" ) {
         filelock("$folderdir/.stationery.book", LOCK_EX|LOCK_NB) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.stationery.book!");
         open (STATBOOK,"+<$folderdir/.stationery.book") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.stationery.book! ($!)");
         while (<STATBOOK>) {
            ($name, $content) = split(/\@\@\@/, $_, 2);
            chomp($name); chomp($content);
            $stationery{"$name"} = $content;
         }
         delete $stationery{$statname};

         seek (STATBOOK, 0, 0) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_seek'} $folderdir/.stationery.book! ($!)");

         foreach (sort keys %stationery) {
            ($name,$content)=($_, $stationery{$_});
            $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
            print STATBOOK "$name\@\@\@$content\n";
         }
         truncate(STATBOOK, tell(STATBOOK));
         close (STATBOOK) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.stationery.book! ($!)");
         filelock("$folderdir/.stationery.book", LOCK_UN);
      }
   }

   editstat();
}
################## END DELSTAT ###########################

################## CLEARSTAT ###########################
sub clearstat {
   if ( -f "$folderdir/.stationery.book" ) {
      unlink("$folderdir/.stationery.book") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.stationery.book! ($!)");
   }
   writelog("clear stationery");
   writehistory("clear stationery");

   editstat();
}
################## END CLEARSTAT ###########################

################## ADDSTAT ###########################
sub addstat {
   my $newname = param('statname') || '';
   my $newcontent = param('statbody') || '';
   my (%stationery, $name, $content);

   if($newname ne '' && $newcontent ne '') {
      # save msg to file stationery
      # load the stationery first and save after, if exist overwrite
      if ( -f "$folderdir/.stationery.book" ) {
         filelock("$folderdir/.stationery.book", LOCK_EX|LOCK_NB) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.stationery.book!");
         open (STATBOOK,"+<$folderdir/.stationery.book") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.stationery.book! ($!)");
         while (<STATBOOK>) {
            ($name, $content) = split(/\@\@\@/, $_, 2);
            chomp($name); chomp($content);
            $stationery{"$name"} = $content;
         }
         $stationery{"$newname"} = escapeURL($newcontent);

         seek (STATBOOK, 0, 0) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_seek'} $folderdir/.stationery.book! ($!)");

         foreach (sort keys %stationery) {
            ($name,$content)=($_, $stationery{$_});
            $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
            print STATBOOK "$name\@\@\@$content\n";
         }
         truncate(STATBOOK, tell(STATBOOK));
         close (STATBOOK) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.stationery.book! ($!)");
         filelock("$folderdir/.stationery.book", LOCK_UN);
      } else {
         open (STATBOOK,">$folderdir/.stationery.book") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir/.stationery.book! ($!)");
         print STATBOOK "$newname\@\@\@".escapeURL($newcontent)."\n";
         close (STATBOOK) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $folderdir/.stationery.book! ($!)");
      }
   }

   editstat();
}
################## END ADDSTAT ###########################

#################### TIMEOUTWARNING ########################
sub timeoutwarning {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("timeoutwarning.template"));
   $html =~ s/\@\@\@USEREMAIL\@\@\@/$prefs{'email'}/g;
   httpprint([], [htmlheader(), $html, htmlfooter(0)]);
}
#################### END TIMEOUTWARNING ########################
