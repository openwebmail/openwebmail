#!/usr/bin/perl -T

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

use strict;
use warnings;

use vars qw($SCRIPT_DIR);

if (-f "/etc/openwebmail_path.conf") {
   my $pathconf = "/etc/openwebmail_path.conf";
   open(F, $pathconf) or die("Cannot open $pathconf: $!");
   my $pathinfo = <F>;
   close(F) or die("Cannot close $pathconf: $!");
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die("SCRIPT_DIR cannot be set") if ($SCRIPT_DIR eq '');
push (@INC, $SCRIPT_DIR);

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH}='/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load non-OWM libraries
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :cgi charset);
use CGI::Carp qw(fatalsToBrowser carpout);
use HTML::Template 2.9;

# load the OWM libraries
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
require "shares/statbook.pl";
require "shares/filterbook.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err
            %lang_timezonelabels
            %lang_calendar %lang_onofflabels %lang_sortlabels
            %lang_disableemblinklabels %lang_msgformatlabels
            %lang_withoriglabels %lang_receiptlabels
            %lang_ctrlpositionlabels %lang_sendpositionlabels
            %lang_checksourcelabels %lang_bgfilterthresholdlabels
            %lang_abookbuttonpositionlabels %lang_abooksortlabels
	    %lang_timelabels %lang_wday); # defined in lang/xy
use vars qw(%charset_convlist);           # defined in iconv.pl
use vars qw(%fontsize %is_config_option); # defined in ow-shared.pl
use vars qw(@openwebmailrcitem);          # defined in ow-shared.pl
use vars qw($htmltemplatefilters);        # defined in ow-shared.pl
use vars qw($persistence_count);

# local globals
use vars qw($action $folder $messageid);
use vars qw($sort $page $longpage);
use vars qw($userfirsttime $prefs_caller);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

$action        = param('action') || '';
$folder        = param('folder') || 'INBOX';
$messageid     = param('message_id') || '';
$page          = param('page') || 1;
$longpage      = param('longpage') || 0;
$sort          = param('sort') || $prefs{sort} || 'date_rev';
$userfirsttime = param('userfirsttime') || 0;
$prefs_caller  = param('prefs_caller') || ( $config{enable_webmail}  ? 'main'    :
                                            $config{enable_calendar} ? 'cal'     :
                                            $config{enable_webdisk}  ? 'webdisk' : '');

writelog("debug - request prefs begin, action=$action - " .__FILE__.":". __LINE__) if ($config{debug_request});

$action eq "userfirsttime"                                   ? userfirsttime()     :
$action eq "timeoutwarning"                                  ? timeoutwarning()    :
$action eq "about"           && $config{enable_about}        ? about()             :
$action eq "editprefs"       && $config{enable_preference}   ? editprefs()         :
$action eq "saveprefs"       && $config{enable_preference}   ? saveprefs()         :
$action eq "editpassword"    && $config{enable_changepwd}    ? editpassword()      :
$action eq "changepassword"  && $config{enable_changepwd}    ? changepassword()    :
$action eq "viewhistory"     && $config{enable_history}      ? viewhistory()       :

$config{enable_webmail} ?
   $action eq "editfroms"    && $config{enable_editfrombook} ? editfroms()         :
   $action eq "addfrom"      && $config{enable_editfrombook} ? modfrom("add")      :
   $action eq "deletefrom"   && $config{enable_editfrombook} ? modfrom("delete")   :
   $action eq "editpop3"     && $config{enable_pop3}         ? editpop3()          :
   $action eq "addpop3"      && $config{enable_pop3}         ? modpop3("add")      :
   $action eq "deletepop3"   && $config{enable_pop3}         ? modpop3("delete")   :
   $action eq "editfilter"   && $config{enable_userfilter}   ? editfilter()        :
   $action eq "addfilter"    && $config{enable_userfilter}   ? modfilter("add")    :
   $action eq "deletefilter" && $config{enable_userfilter}   ? modfilter("delete") :
   param('deletestatbutton') && $config{enable_stationery}   ? delstat()           :
   param('editstatbutton')   && $config{enable_stationery}   ? editstat()          :
   $action eq "editstat"     && $config{enable_stationery}   ? editstat()          :
   $action eq "clearstat"    && $config{enable_stationery}   ? clearstat()         :
   $action eq "addstat"      && $config{enable_stationery}   ? addstat()           :
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{has_illegal_chars}")
: openwebmailerror(__FILE__, __LINE__, "Action $lang_err{has_illegal_chars}");

writelog("debug - request prefs end, action=$action - " .__FILE__.":". __LINE__) if ($config{debug_request});

openwebmail_requestend();



# BEGIN SUBROUTINES

sub about {
   my $os = $lang_err{no_uname};
   if (-f "/bin/uname") {
      $os = `/bin/uname -srm`;
   } elsif (-f "/usr/bin/uname") {
      $os = `/usr/bin/uname -srm`;
   }
   chomp($os);

   my ($activelastminute, $activelastfiveminute, $activelastfifteenminute) = get_sessioncount();

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_about.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template         => get_header($config{header_template_file}),

                      # standard params
                      sessionid               => $thissession,
                      folder                  => $folder,
                      message_id              => $messageid,
                      sort                    => $sort,
                      page                    => $page,
                      longpage                => $longpage,
                      userfirsttime           => $userfirsttime,
                      prefs_caller            => $prefs_caller,
                      url_cgi                 => $config{ow_cgiurl},
                      url_html                => $config{ow_htmlurl},
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./?1:0),
                      iconset                 => $prefs{iconset},

                      # prefs_about.tmpl
                      show_softwareinfo       => $config{about_info_software},
                      operatingsystem         => $os,
                      perl_executable         => $^X,
                      perl_version            => $],
                      programname             => $config{name},
                      programversion          => $config{version},
                      programreleasedate      => $config{releasedate},
                      programrevision         => $config{revision},
                      is_persistence          => $persistence_count,
                      is_httpcompression      => is_http_compression_enabled(),
                      show_protocolinfo       => $config{about_info_protocol},
                      server_protocol         => $ENV{SERVER_PROTOCOL},
                      http_connection         => $ENV{HTTP_CONNECTION},
                      http_keep_alive         => $ENV{HTTP_KEEP_ALIVE},
                      show_serverinfo         => $config{about_info_server},
                      http_host               => $ENV{HTTP_HOST},
                      script_name             => $ENV{SCRIPT_NAME},
                      show_scriptfilenameinfo => $config{about_info_scriptfilename},
                      script_filename         => $ENV{SCRIPT_FILENAME},
                      server_name             => $ENV{SERVER_NAME},
                      server_addr             => $ENV{SERVER_ADDR},
                      server_port             => $ENV{SERVER_PORT},
                      server_software         => $ENV{SERVER_SOFTWARE},
                      show_sessioncount       => $config{session_count_display},
                      activelastminute        => $activelastminute,
                      activelastfiveminute    => $activelastfiveminute,
                      activelastfifteenminute => $activelastfifteenminute,
                      show_clientinfo         => $config{about_info_client},
                      remote_addr             => $ENV{REMOTE_ADDR},
                      remote_port             => $ENV{REMOTE_PORT},
                      http_client_ip          => $ENV{HTTP_CLIENT_IP},
                      http_x_forwarded_for    => $ENV{HTTP_X_FORWARDED_FOR},
                      http_via                => $ENV{HTTP_VIA},
                      http_user_agent         => $ENV{HTTP_USER_AGENT},
                      http_accept_encoding    => $ENV{HTTP_ACCEPT_ENCODING},
                      http_accept_language    => $ENV{HTTP_ACCEPT_LANGUAGE},

                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub get_sessioncount {
   my $t = time();
   my @sessioncount = ();

   opendir(SESSIONSDIR, "$config{ow_sessionsdir}") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $config{ow_sessionsdir}! ($!)");

   while (defined(my $sessfile = readdir(SESSIONSDIR))) {
      if ($sessfile =~ /^[\w\.\-\%\@]+\*[\w\.\-]*\-session\-0\.\d+$/) {
         my $modifyage = $t - (stat("$config{ow_sessionsdir}/$sessfile"))[9];
         $sessioncount[0]++ if ($modifyage <= 60);
         $sessioncount[1]++ if ($modifyage <= 300);
         $sessioncount[2]++ if ($modifyage <= 900);
      }
   }

   closedir(SESSIONSDIR);

   return(@sessioncount);
}

sub userfirsttime {
   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_userfirsttime.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      url_cgi         => $config{ow_cgiurl},

                      # prefs_userfirsttime.tmpl
                      programname     => $config{name},

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub editprefs {
   my $paramlanguage = param('language');
   my $paramcharset  = param('charset');

   if (defined $paramlanguage) {
      if ( $paramlanguage =~ /^([_A-Za-z]+)$/ ) {
         # set the prefs page to the selected language and the selected charset, or its first match charset
         my $selected_language = $1;

         $prefs{language} = $selected_language;
         $prefs{locale}   = "$selected_language\.UTF-8";
         if (!exists $config{available_locales}->{$prefs{locale}}) {
            $prefs{locale} = (grep { m/^$selected_language/ } sort keys %{$config{available_locales}})[0]; # first match charset
         }
         $prefs{charset} = (ow::lang::localeinfo($prefs{locale}))[6];

         if (defined $paramcharset) {
            my $selected_charset = uc($paramcharset);
            $selected_charset =~ s/[-_\s]+//g;
            if ( exists $ow::lang::charactersets{$selected_charset} ) {
               my $newlocale = "$selected_language\.$ow::lang::charactersets{$selected_charset}[0]";
               if ( exists $config{available_locales}{$newlocale} ) {
                  $prefs{locale}  = $newlocale;
                  $prefs{charset} = $ow::lang::charactersets{$selected_charset}[1];
               }
            }
         }

         loadlang($prefs{locale});
         charset($prefs{charset}) if ($CGI::VERSION>=2.58); # setup charset of CGI module
      } else {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{param_fmterr} \'language\' $lang_err{has_illegal_chars}");
      }
   }

   # simple prefs menu for first time users
   # all other values in the form are hidden, except the items we want users to update now
   my $hiddenprefsloop = [];
   if ($userfirsttime) {
      my %shownow = ();
      $shownow{$_}++ for qw(language charset timeoffset timezone daylightsaving email replyto signature);

      # add the hiddens to the hiddenprefsloop
      foreach (@openwebmailrcitem) {
         next if $shownow{$_};
         if ($_ eq 'bgurl') {
            my ($background, $bgurl) = ($prefs{bgurl}, '');
            if ($background !~ m#$config{ow_htmlurl}/images/backgrounds/#) {
               ($background, $bgurl) = ('USERDEFINE', $prefs{bgurl});
            }
            push(@{$hiddenprefsloop}, { name => "background", value => $background });
            push(@{$hiddenprefsloop}, { name => "bgurl", value => $bgurl });
         } else {
            push(@{$hiddenprefsloop}, { name => $_, value => $prefs{$_} });
         }
      }
   }

   my $enable_quota       = $config{quota_module} eq 'none'?0:1;
   my $quotashowusage     = 0;
   my $quotaoverthreshold = 0;
   my $quotabytesusage    = 0;
   my $quotapercentusage  = 0;
   if ($enable_quota) {
      $quotaoverthreshold = ($quotalimit > 0 && ($quotausage / $quotalimit) > ($config{quota_threshold} / 100));
      $quotashowusage     = ($quotaoverthreshold || $config{quota_threshold} == 0)?1:0;
      if ($quotashowusage) {
         $quotabytesusage = lenstr($quotausage * 1024, 1);
      }
      if ($quotaoverthreshold) {
         $quotapercentusage = int($quotausage * 1000 / $quotalimit) / 10;
      }
   }

   my $userfroms = get_userfroms();

   my $defaultlanguage    = join("_", (ow::lang::localeinfo($prefs{locale}))[0,2]);
   my $defaultcharset     = (ow::lang::localeinfo($prefs{locale}))[6];
   my $defaultsendcharset = $prefs{sendcharset} || 'sameascomposing';

   if (defined $paramlanguage && $paramlanguage =~ /^([A-Za-z_]+)$/ ) {
      $defaultlanguage = $1;
      my $defaultlocale = "$defaultlanguage\.UTF-8";
      if (!exists $config{available_locales}->{$defaultlocale}) {
         $defaultlocale = (grep { m/^$defaultlanguage/ } sort keys %{$config{available_locales}})[0]; # first match charset
      }
      $defaultcharset = (ow::lang::localeinfo($defaultlocale))[6];
      if ($defaultlanguage =~ /^ja_JP/ ) {
         $defaultsendcharset = 'iso-2022-jp';
      } else {
         $defaultsendcharset = 'sameascomposing';
      }
   }

   my %unique = ();
   my @availablelanguages = grep { !$unique{$_}++ }                            # eliminate duplicates
                             map { join("_",(ow::lang::localeinfo($_))[0,2]) } # en_US
                            sort keys %{$config{available_locales}};

   # TODO: The language code and country code translations should be in the language files, not in ow::lang
   my %langlabels = map { m/^(..)_(..)/; $_, "$ow::lang::languagecodes{$1}/$ow::lang::countrycodes{$2} [$1_$2]" } @availablelanguages;

   my @selectedlanguagecharsets =  map { (ow::lang::localeinfo($_))[6] }
                                  grep { m/^$defaultlanguage/ }
                                  sort keys %{$config{available_locales}}; # all matching charsets

   # if we are using zonetabfile, the selection options look like:
   # '+0100 Africa/Niamey'
   # or else the selection options look like:
   # '+0100'
   # the difference is parsed in the saveprefs subroutine in this file.
   # TODO: right now if the zonetab file is used the country/region names are taken from the zone.tab file.
   # if the the zonetab file is not used the country/region names are taken from the ow::lang package. We
   # will be moving the country/region names to the appropriate language files in the future so that the names
   # will be localised to the chosen language, so we will need to update the zone.tab handling to take the
   # translations of the regions from the language files... or just redo the timehandling completely ;)
   # TODO: You can't switch between using a zonetab file and not using a zonetab file properly because the selected
   # option always matches the timezone of the user prefs, but the timezone is stored differently depending on the
   # mode you are using. So when switching it "forgets" what you had previously selected.
   my @zones = ();
   my $usezonetabfile = 0;
   if (($config{zonetabfile} ne 'no') && (@zones = ow::datetime::makezonelist($config{zonetabfile}))) {
      @zones = sort(@zones);
      $usezonetabfile = 1;
   } else {
      @zones = qw( -1200 -1100 -1000 -0900 -0800 -0700 -0600 -0500 -0400 -0330 -0300 -0230 -0200 -0100
                   +0000 +0100 +0200 +0300 +0330 +0400 +0500 +0530 +0600 +0630 +0700 +0800 +0900 +0930 +1000 +1030 +1100 +1200 +1300 );
   }

   # read .forward, also see if autoforwarding is on
   my ($autoreply, $keeplocalcopy, @forwards) = readdotforward();
   my $forwardaddress = scalar @forwards >= 1?join(",", @forwards):'';

   # whether autoreply active or not is determined by
   # if .forward is set to call vacation program, not in .openwebmailrc
   my ($autoreplysubject, $autoreplytext) = readdotvacationmsg();

   # Get a list of valid style files
   opendir(STYLESDIR, $config{ow_stylesdirtemp}) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $config{ow_stylesdirtemp}! ($!)");
   my @styles = sort grep { s/^([^.][^.]+)\.css$/$1/i } readdir(STYLESDIR);
   closedir(STYLESDIR) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $config{ow_stylesdirtemp}! ($!)");

   # Get a list of valid iconset
   opendir(ICONSETSDIR, "$config{ow_htmldir}/images/iconsets") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $config{ow_htmldir}/images/iconsets! ($!)");
   my @iconsets = sort grep { -d "$config{ow_htmldir}/images/iconsets/$_" && m/^([^\.].*)$/ } readdir(ICONSETSDIR);
   closedir(ICONSETSDIR) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $config{ow_htmldir}/images/iconsets! ($!)");

   # Get a list of valid background images
   opendir(BACKGROUNDSDIR, "$config{ow_htmldir}/images/backgrounds") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $config{ow_htmldir}/images/backgrounds! ($!)");
   my @backgrounds = sort grep { m/^([^\.].*)$/ } readdir(BACKGROUNDSDIR);
   closedir(BACKGROUNDSDIR) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $config{ow_htmldir}/images/backgrounds! ($!)");
   push(@backgrounds, "USERDEFINE");

   my ($defaultbackground, $bgurl) = ($prefs{bgurl}, '');
   # remove the $config{ow_htmlurl}/images/backgrounds/ unless the bg is userdefined
   if ($defaultbackground !~ s#^$config{ow_htmlurl}/images/backgrounds/##) {
      ($defaultbackground, $bgurl) = ('USERDEFINE', $prefs{bgurl});
   }

   my $defaultctrlposition_folderview = $prefs{ctrlposition_folderview} || 'bottom';

   my $defaultmsgdatetype = $prefs{msgdatetype} || 'sentdate';

   my $defaultdefaultdestination = $prefs{defaultdestination} || 'mail-trash';

   my $defaultctrlposition_msgread = $prefs{ctrlposition_msgread} || 'bottom';

   my $defaultheaders = $prefs{headers} || 'simple';

   my $defaultsendreceipt = $prefs{sendreceipt} || 'ask';

   my $defaultsendbuttonposition = $prefs{sendbuttonposition} || 'before';

   my $defaultreplywithorigmsg = $prefs{replywithorigmsg} || 'at_beginning';

   my $selectedlocalecharset = (ow::lang::localeinfo($prefs{locale}))[6];
   my @charsets = ('sameascomposing', $selectedlocalecharset);
   foreach my $charset (@{$charset_convlist{$selectedlocalecharset}}) {
      push(@charsets, $charset) if (is_convertible($selectedlocalecharset, $charset));
   }

   my (@viruscheck_maxsize, $defaultviruscheck_maxsize);
   for (250, 500, 1000, 2000, 3000, 4000, 5000, 10000, 20000, 50000) {
      if ($_ <= $config{viruscheck_maxsize_allowed}) {
         push(@viruscheck_maxsize, $_);
         $defaultviruscheck_maxsize = $_ if ($_ <= $prefs{viruscheck_maxsize});
      }
   }

   my (@spamcheck_maxsize, $defaultspamcheck_maxsize);
   for (100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000) {
      if ($_ <= $config{spamcheck_maxsize_allowed}) {
         push(@spamcheck_maxsize, $_);
         $defaultspamcheck_maxsize = $_ if ($_ <= $prefs{spamcheck_maxsize});
      }
   }

   my $filterruledb = dotpath('filter.ruledb');
   my %FILTERRULEDB = ();
   ow::dbm::open(\%FILTERRULEDB, $filterruledb, LOCK_SH) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db $filterruledb");

   my $filtermatch = {};
   foreach my $filter (qw(filter_repeatlimit filter_badaddrformat filter_fakedsmtp filter_fakedfrom filter_fakedexecontenttype)) {
      if (defined $FILTERRULEDB{$filter}) {
         ($filtermatch->{$filter}{count}, $filtermatch->{$filter}{date}) = split(":", $FILTERRULEDB{$filter});
         if (defined $filtermatch->{$filter}{date} && $filtermatch->{$filter}{date}) {
            $filtermatch->{$filter}{date} = ow::datetime::dateserial2str(
                                                                           $filtermatch->{$filter}{date},
                                                                           $prefs{timeoffset},
                                                                           $prefs{daylightsaving},
                                                                           $prefs{dateformat},
                                                                           $prefs{hourformat},
                                                                           $prefs{timezone},
                                                                        );
         }
      } else {
         $filtermatch->{$filter}{count} = 0;
         $filtermatch->{$filter}{date}  = 0;
      }
   }

   ow::dbm::close(\%FILTERRULEDB, $filterruledb);

   my $defaultabook_buttonposition = $prefs{abook_buttonposition} || 'before';

   my $defaultabook_defaultsearchtype = $prefs{abook_defaultsearchtype} || 'fullname';

   my @fieldorder = split(/\s*[,\s]\s*/, $prefs{abook_listviewfieldorder});
   my $defaultabook_listviewfieldorder0 = $fieldorder[0] || 'none';
   my $defaultabook_listviewfieldorder1 = $fieldorder[1] || 'none';
   my $defaultabook_listviewfieldorder2 = $fieldorder[2] || 'none';
   my $defaultabook_listviewfieldorder3 = $fieldorder[3] || 'none';
   my $defaultabook_listviewfieldorder4 = $fieldorder[4] || 'none';

   # Get a list of valid holiday files
   opendir(HOLIDAYSDIR, $config{ow_holidaysdir}) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $config{ow_holidaysdir}! ($!)");
   my @holidays = grep { !m/^\.+/ } readdir(HOLIDAYSDIR);
   closedir(HOLIDAYSDIR) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $config{ow_holidaysdir}! ($!)");

   my %holidaylabels = map {
                              m/^(..)_(..)\.(.*)/;    # extract parts from holiday file like en_US.ISO8859-1
                              my ($language,$country,$charset) = ($1, $2, uc($3));
                              $charset =~ s#[-_]+##g; # ISO8859-1 -> ISO88591
                              $_, "$ow::lang::countrycodes{$country}/$ow::lang::languagecodes{$language} ($ow::lang::charactersets{$charset}[1])"
                           } @holidays;

   # sort holidays by the label
   @holidays = map { $_ }
               sort { $holidaylabels{$a} cmp $holidaylabels{$b} }
               keys %holidaylabels;

   unshift(@holidays, 'auto');
   $holidaylabels{auto} = $lang_text{autosel};

   push(@holidays, 'none');
   $holidaylabels{none} = $lang_text{none};

   # Get the list of new mail sounds
   opendir(SOUNDDIR, "$config{ow_htmldir}/sounds") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $config{ow_htmldir}/sounds! ($!)");
   my @sounds = sort grep { -f "$config{ow_htmldir}/sounds/$_" && !m/^\.+/ } readdir(SOUNDDIR);
   closedir(SOUNDDIR) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $config{ow_htmldir}/sounds! ($!)");
   unshift(@sounds, 'NONE');

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template                   => get_header($config{header_template_file}, 'showaltstyles'),

                      # standard params
                      sessionid                         => $thissession,
                      folder                            => $folder,
                      message_id                        => $messageid,
                      sort                              => $sort,
                      page                              => $page,
                      longpage                          => $longpage,
                      userfirsttime                     => $userfirsttime,
                      prefs_caller                      => $prefs_caller,
                      url_cgi                           => $config{ow_cgiurl},
                      url_html                          => $config{ow_htmlurl},
                      use_texticon                      => ($prefs{iconset} =~ m/^Text\./?1:0),
                      iconset                           => $prefs{iconset},

                      # prefs.tmpl
                      hiddenprefsloop                   => $hiddenprefsloop,
                      enable_quota                      => $enable_quota,
                      quotashowusage                    => $quotashowusage,
                      quotaoverthreshold                => $quotaoverthreshold,
                      quotabytesusage                   => $quotabytesusage,
                      quotapercentusage                 => $quotapercentusage,
                      userrealname                      => exists $userfroms->{$prefs{email}} ? $userfroms->{$prefs{email}} : 0,
                      caller_calendar                   => $prefs_caller eq 'cal'?1:0,
                      calendardefaultview               => $prefs{calendar_defaultview},
                      caller_webdisk                    => $prefs_caller eq 'webdisk'?1:0,
                      caller_read                       => $prefs_caller eq 'read'?1:0,
                      callerfoldername                  => ($lang_folders{$folder} || f2u($folder)),
                      caller_addrlistview               => $prefs_caller eq 'addrlistview'?1:0,
                      caller_main                       => $prefs_caller eq 'main'?1:0,
                      enable_webmail                    => $config{enable_webmail},
                      enable_editfrombook               => $config{enable_editfrombook},
                      enable_stationery                 => $config{enable_stationery},
                      enable_pop3                       => $config{enable_pop3},
                      enable_saprefs                    => $config{enable_saprefs},
                      enable_changepwd                  => $config{enable_changepwd},
                      vdomainadmin                      => ($config{enable_vdomain} && is_vdomain_adm($user))?1:0,
                      enable_history                    => $config{enable_history},
                      enable_about                      => $config{enable_about},
                      programname                       => $config{name},
                      disablelanguageselect             => defined $config_raw{DEFAULT_locale}?1:0,
                      languageselectloop                => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $langlabels{$_},
                                                                       selected => $_ eq $defaultlanguage?1:0
                                                                  } } sort { $langlabels{$a} cmp $langlabels{$b} } keys %langlabels
                                                           ],
                      disablecharsetselect              => defined $config_raw{DEFAULT_locale}?1:0,
                      charsetselectloop                 => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => ((defined $prefs{charset})?$_ eq $prefs{charset}:$_ eq $defaultcharset)?1:0
                                                                  } } @selectedlanguagecharsets
                                                           ],
                      disabletimezoneselect             => defined $config_raw{DEFAULT_timezone}?1:0,
                      timezoneselectloop                => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $usezonetabfile ? $_ : "$_ - $lang_timezonelabels{$_}",
                                                                       selected => $usezonetabfile ?
                                                                                   ($_ eq "$prefs{timeoffset} $prefs{timezone}"?1:0) :
                                                                                   ($_ eq $prefs{timeoffset}?1:0)
                                                                  } } @zones
                                                           ],
                      disabledstselect                  => defined $config_raw{DEFAULT_daylightsaving}?1:0,
                      dstselectloop                     => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_onofflabels{$_},
                                                                       selected => defined $prefs{daylightsaving} && $_ eq $prefs{daylightsaving}?1:0
                                                                  } } qw(auto on off)
                                                           ],
                      fromemailselectloop               => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => defined $userfroms->{$_} ? qq|"$userfroms->{$_}" <$_>| : $_,
                                                                       selected => defined $prefs{email} && $_ eq $prefs{email} ? 1 : 0,
                                                                  } } sort_emails_by_domainnames($config{domainnames}, keys %{$userfroms})
                                                           ],
                      replyto                           => $prefs{replyto},
                      enable_setforward                 => $config{enable_setforward},
                      forwardaddress                    => $forwardaddress,
                      keeplocalcopy                     => $keeplocalcopy,
                      enable_autoreply                  => $config{enable_autoreply},
                      autoreplychecked                  => $autoreply,
                      autoreplysubject                  => $autoreplysubject,
                      autoreplytext                     => $autoreplytext,
                      textareacolumns                   => ($prefs{editcolumns} || '78'),
                      disablesignature                  => defined $config_raw{DEFAULT_signature}?1:0,
                      signaturetext                     => $prefs{signature},
                      disablestyleselect                => defined $config_raw{DEFAULT_style}?1:0,
                      styleselectloop                   => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => defined $prefs{style} && $_ eq $prefs{style}?1:0
                                                                  } } @styles
                                                           ],
                      disableiconsetselect              => defined $config_raw{DEFAULT_iconset}?1:0,
                      iconsetselectloop                 => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => defined $prefs{iconset} && $_ eq $prefs{iconset}?1:0
                                                                  } } @iconsets
                                                           ],
                      disablebackgroundselect           => defined $config_raw{DEFAULT_bgurl}?1:0,
                      backgroundselectloop              => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ eq 'USERDEFINE'?"--$lang_text{userdef}--":$_,
                                                                       selected => $_ eq $defaultbackground?1:0
                                                                  } } @backgrounds
                                                           ],
                      disablebgurl                      => defined $config_raw{DEFAULT_bgurl}?1:0,
                      bgurl                             => $bgurl,
                      disablebgrepeat                   => defined $config_raw{DEFAULT_bgrepeat}?1:0,
                      bgrepeatchecked                   => $prefs{bgrepeat},
                      disablefontsizeselect             => defined $config_raw{DEFAULT_fontsize}?1:0,
                      fontsizeselectloop                => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ =~ m/(\d+)pt/ ? "$1 $lang_text{point}" :
                                                                                   $_ =~ m/(\d+)px/ ? "$1 $lang_text{pixel}" :
                                                                                   $_,
                                                                       selected => $_ eq $prefs{fontsize}?1:0
                                                                  } } map { $_->[0] }
                                                                     sort { ($a->[0] =~ m/px$/ - $b->[0] =~ m/px$/) || $a->[1] <=> $b->[1] }
                                                                      map { m/(\d+)(p.)/; [$_, $1, $2] } keys %fontsize
                                                           ],
                      disabledateformatselect           => defined $config_raw{DEFAULT_dateformat}?1:0,
                      dateformatselectloop              => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{dateformat}?1:0
                                                                  } } qw(mm/dd/yyyy dd/mm/yyyy yyyy/mm/dd mm-dd-yyyy dd-mm-yyyy yyyy-mm-dd mm.dd.yyyy dd.mm.yyyy yyyy.mm.dd)
                                                           ],
                      disablehourformatselect           => defined $config_raw{DEFAULT_hourformat}?1:0,
                      hourformatselectloop              => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{hourformat}?1:0
                                                                  } } qw(12 24)
                                                           ],
                      disablectrlposselect              => defined $config_raw{DEFAULT_ctrlposition_folderview}?1:0,
                      ctrlposselectloop                 => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_ctrlpositionlabels{$_},
                                                                       selected => $_ eq $defaultctrlposition_folderview?1:0
                                                                  } } qw(top bottom)
                                                           ],
                      disablemsgsperpageselect          => defined $config_raw{DEFAULT_msgsperpage}?1:0,
                      msgsperpageselectloop             => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{msgsperpage}?1:0
                                                                  } } qw(8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 50 100 500 1000)
                                                           ],
                      disablefieldorderselect           => defined $config_raw{DEFAULT_fieldorder}?1:0,
                      fieldorderselectloop              => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => join(', ', map { $lang_text{$_} } split),
                                                                       selected => $_ eq $prefs{fieldorder}?1:0
                                                                  } } ('date from subject size', 'date subject from size', 'subject from date size', 'from subject date size')
                                                           ],
                      disablemsgsortselect              => defined $config_raw{DEFAULT_msgsort}?1:0,
                      msgsortselectloop                 => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_sortlabels{$_},
                                                                       selected => $_ eq $prefs{sort}?1:0
                                                                  } } qw(date date_rev sender sender_rev size size_rev subject subject_rev status)
                                                           ],
                      disablesearchtypeselect           => defined $config_raw{DEFAULT_searchtype}?1:0,
                      searchtypeselectloop              => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_text{$_},
                                                                       selected => $_ eq $prefs{searchtype}?1:0
                                                                  } } qw(from to subject date attfilename header textcontent all)
                                                           ],
                      disablemsgdatetypeselect          => defined $config_raw{DEFAULT_msgdatetype}?1:0,
                      msgdatetypeselectloop             => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_text{$_},
                                                                       selected => $_ eq $defaultmsgdatetype?1:0
                                                                  } } qw(sentdate recvdate)
                                                           ],
                      disableuseminisearchicon          => defined $config_raw{DEFAULT_useminisearchicon}?1:0,
                      useminisearchiconchecked          => $prefs{useminisearchicon},
                      disableconfirmmsgmovecopy         => defined $config_raw{DEFAULT_confirmmsgmovecopy}?1:0,
                      confirmmsgmovecopychecked         => $prefs{confirmmsgmovecopy},
                      disabledefaultdestinationselect   => defined $config_raw{DEFAULT_defaultdestination}?1:0,
                      defaultdestinationselectloop      => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_folders{$_},
                                                                       selected => $_ eq $defaultdefaultdestination?1:0
                                                                  } } qw(saved-messages mail-trash DELETE)
                                                           ],
                      disablesmartdestination           => defined $config_raw{DEFAULT_smartdestination}?1:0,
                      smartdestinationchecked           => $prefs{smartdestination},
                      disableviewnextaftermsgmovecopy   => defined $config_raw{DEFAULT_viewnextaftermsgmovecopy}?1:0,
                      viewnextaftermsgmovecopychecked   => $prefs{viewnextaftermsgmovecopy},
                      disableautopop3                   => defined $config_raw{DEFAULT_autopop3}?1:0,
                      autopop3checked                   => $prefs{autopop3},
                      disableautopop3waitselect         => defined $config_raw{DEFAULT_autopop3wait}?1:0,
                      autopop3waitselectloop            => [
                                                              map { {
                                                                       option     => $_,
                                                                       label      => $_,
                                                                       selected   => $_ eq $prefs{autopop3wait}?1:0
                                                                  } } qw(0 1 2 3 4 5 6 7 8 9 10 15 20 25 30)
                                                           ],
                      disablebgfilterthresholdselect    => defined $config_raw{DEFAULT_bgfilterthreshold}?1:0,
                      bgfilterthresholdselectloop       => [
                                                              map { {
                                                                       option     => $_,
                                                                       label      => $lang_bgfilterthresholdlabels{$_},
                                                                       selected   => $_ eq $prefs{bgfilterthreshold}?1:0
                                                                  } } qw(0 1 20 50 100 200 500)
                                                           ],
                      disablebgfilterwaitselect         => defined $config_raw{DEFAULT_bgfilterwait}?1:0,
                      bgfilterwaitselectloop            => [
                                                              map { {
                                                                       option     => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{bgfilterwait}?1:0
                                                                  } } qw(5 10 15 20 25 30 35 40 45 50 55 60 90 120)
                                                           ],
                      forced_moveoldmsgfrominbox        => $config{forced_moveoldmsgfrominbox},
                      disablemoveoldmsgfrominbox        => defined $config_raw{DEFAULT_moveoldmsgfrominbox}?1:0,
                      moveoldmsgfrominboxchecked        => $prefs{moveoldmsgfrominbox},
                      disablectrlposition_msgreadselect => defined $config_raw{DEFAULT_ctrlposition_msgread}?1:0,
                      ctrlposition_msgreadselectloop    => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_ctrlpositionlabels{$_},
                                                                       selected => $_ eq $defaultctrlposition_msgread?1:0
                                                                  } } qw(top bottom)
                                                           ],
                      disableheadersselect              => defined $config_raw{DEFAULT_headers}?1:0,
                      headersselectloop                 => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_text{$_ . "head"},
                                                                       selected => $_ eq $defaultheaders?1:0
                                                                  } } qw(simple all)
                                                           ],
                      disablereadwithmsgcharset         => defined $config_raw{DEFAULT_readwithmsgcharset}?1:0,
                      readwithmsgcharsetchecked         => $prefs{readwithmsgcharset},
                      disableusefixedfont               => defined $config_raw{DEFAULT_usefixedfont}?1:0,
                      usefixedfontchecked               => $prefs{usefixedfont},
                      disableusesmileicon               => defined $config_raw{DEFAULT_usesmileicon}?1:0,
                      usesmileiconchecked               => $prefs{usesmileicon},
                      disableshowhtmlastext             => defined $config_raw{DEFAULT_showhtmlastext}?1:0,
                      showhtmlastextchecked             => $prefs{showhtmlastext},
                      disableshowimgaslink              => defined $config_raw{DEFAULT_showimgaslink}?1:0,
                      showimgaslinkchecked              => $prefs{showimgaslink},
                      disabledisablejs                  => defined $config_raw{DEFAULT_disablejs}?1:0,
                      disablejschecked                  => $prefs{disablejs},
                      disabledisableembcode             => defined $config_raw{DEFAULT_disableembcode}?1:0,
                      disableembcodechecked             => $prefs{disableembcode},
                      disabledisableemblinkselect       => defined $config_raw{DEFAULT_disableemblink}?1:0,
                      disableemblinkselectloop          => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_disableemblinklabels{$_},
                                                                       selected => $_ eq $prefs{disableemblink}?1:0
                                                                  } } qw(none cgionly all)
                                                           ],
                      disablesendreceiptselect          => defined $config_raw{DEFAULT_sendreceipt}?1:0,
                      sendreceiptselectloop             => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_receiptlabels{$_},
                                                                       selected => $_ eq $defaultsendreceipt?1:0
                                                                  } } qw(ask yes no)
                                                           ],
                      disablemsgformatselect            => defined $config_raw{DEFAULT_msgformat}?1:0,
                      msgformatselectloop               => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_msgformatlabels{$_},
                                                                       selected => $_ eq $prefs{msgformat}?1:0
                                                                  } } qw(auto text html both)
                                                           ],
                      disableeditcolumnsselect          => defined $config_raw{DEFAULT_editcolumns}?1:0,
                      editcolumnsselectloop             => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{editcolumns}?1:0
                                                                  } } qw(60 62 64 66 68 70 72 74 76 78 80 82 84 86 88 90 100 110 120)
                                                           ],
                      disableeditrowsselect             => defined $config_raw{DEFAULT_editrows}?1:0,
                      editrowsselectloop                => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{editrows}?1:0
                                                                  } } qw(10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 50 60 70 80)
                                                           ],
                      disablesendbuttonpositionselect   => defined $config_raw{DEFAULT_sendbuttonposition}?1:0,
                      sendbuttonpositionselectloop      => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_sendpositionlabels{$_},
                                                                       selected => $_ eq $defaultsendbuttonposition?1:0
                                                                  } } qw(before after both)
                                                           ],
                      disablereparagraphorigmsg         => defined $config_raw{DEFAULT_reparagraphorigmsg}?1:0,
                      reparagraphorigmsgchecked         => $prefs{reparagraphorigmsg},
                      disablereplywithorigmsgselect     => defined $config_raw{DEFAULT_replywithorigmsg}?1:0,
                      replywithorigmsgselectloop        => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_withoriglabels{$_},
                                                                       selected => $_ eq $defaultreplywithorigmsg?1:0
                                                                  } } qw(at_beginning at_end none)
                                                           ],
                      disablesigbeforeforward           => defined $config_raw{DEFAULT_sigbeforeforward}?1:0,
                      sigbeforeforwardchecked           => $prefs{sigbeforeforward},
                      disableautocc                     => defined $config_raw{DEFAULT_autocc}?1:0,
                      autocctext                        => $prefs{autocc} || '',
                      enable_backupsent                 => $config{enable_backupsent},
                      disablebackupsentmsg              => defined $config_raw{DEFAULT_backupsentmsg}?1:0,
                      backupsentmsgchecked              => $prefs{backupsentmsg},
                      disablebackupsentoncurrfolder     => defined $config_raw{DEFAULT_backupsentoncurrfolder}?1:0,
                      backupsentoncurrfolderchecked     => $prefs{backupsentoncurrfolder},
                      disablesendcharsetselect          => defined $config_raw{DEFAULT_sendcharset}?1:0,
                      sendcharsetselectloop             => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ eq 'sameascomposing'?$lang_text{sameascomposecharset}:$_,
                                                                       selected => $_ eq $defaultsendcharset?1:0
                                                                  } } @charsets
                                                           ],
                      enable_viruscheck                 => $config{enable_viruscheck},
                      disableviruscheck_sourceselect    => defined $config_raw{DEFAULT_viruscheck_source}?1:0,
                      viruscheck_sourceselectloop       => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_checksourcelabels{$_},
                                                                       selected => $_ eq $prefs{viruscheck_source}?1:0
                                                                  } } $config{viruscheck_source_allowed} eq 'all'  ? qw(none pop3 all) :
                                                                      $config{viruscheck_source_allowed} eq 'pop3' ? qw(none pop3) :
                                                                      qw(none)
                                                           ],
                      disableviruscheck_maxsizeselect   => defined $config_raw{DEFAULT_viruscheck_maxsize}?1:0,
                      viruscheck_maxsizeselectloop      => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $defaultviruscheck_maxsize?1:0
                                                                  } } @viruscheck_maxsize
                                                           ],
                      disableviruscheck_minbodysizeselect => defined $config_raw{DEFAULT_viruscheck_minbodysize}?1:0,
                      viruscheck_minbodysizeselectloop    => [
                                                                map { {
                                                                         option   => $_,
                                                                         label    => $_,
                                                                         selected => $_ eq $prefs{viruscheck_minbodysize}?1:0
                                                                    } } qw(0 0.5 1 1.5 2)
                                                             ],
                      enable_spamcheck                  => $config{enable_spamcheck},
                      disablespamcheck_sourceselect     => defined $config_raw{DEFAULT_spamcheck_source}?1:0,
                      spamcheck_sourceselectloop        => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_checksourcelabels{$_},
                                                                       selected => $_ eq $prefs{spamcheck_source}?1:0
                                                                  } } $config{enable_spamcheck} && $config{spamcheck_source_allowed} eq 'all'  ? qw(none pop3 all) :
                                                                      $config{enable_spamcheck} && $config{spamcheck_source_allowed} eq 'pop3' ? qw(none pop3) :
                                                                      qw(none)
                                                           ],
                      disablespamcheck_maxsizeselect    => defined $config_raw{DEFAULT_spamcheck_maxsize}?1:0,
                      spamcheck_maxsizeselectloop       => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $defaultspamcheck_maxsize?1:0
                                                                  } } @spamcheck_maxsize
                                                           ],
                      disablespamcheck_thresholdselect  => defined $config_raw{DEFAULT_spamcheck_threshold}?1:0,
                      spamcheck_thresholdselectloop     => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{spamcheck_threshold}?1:0
                                                                  } } (5..30)
                                                           ],
                      enable_smartfilter                => $config{enable_smartfilter},
                      disablefilter_repeatlimitselect   => defined $config_raw{DEFAULT_filter_repeatlimit}?1:0,
                      filter_repeatlimitselectloop      => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{filter_repeatlimit}?1:0
                                                                  } } qw(0 5 10 20 30 40 50 100)
                                                           ],
                      filter_repeatlimitmatchcount      => $filtermatch->{filter_repeatlimit}{count},
                      filter_repeatlimitmatchdate       => $filtermatch->{filter_repeatlimit}{date},
                      disablefilter_badaddrformat       => defined $config_raw{DEFAULT_filter_badaddrformat}?1:0,
                      filter_badaddrformatchecked       => $prefs{filter_badaddrformat},
                      filter_badaddrformatmatchcount    => $filtermatch->{filter_badaddrformat}{count},
                      filter_badaddrformatmatchdate     => $filtermatch->{filter_badaddrformat}{date},
                      disablefilter_fakedsmtp           => defined $config_raw{DEFAULT_filter_fakedsmtp}?1:0,
                      filter_fakedsmtpchecked           => $prefs{filter_fakedsmtp},
                      filter_fakedsmtpmatchcount        => $filtermatch->{filter_fakedsmtp}{count},
                      filter_fakedsmtpmatchdate         => $filtermatch->{filter_fakedsmtp}{date},
                      disablefilter_fakedfrom           => defined $config_raw{DEFAULT_filter_fakedfrom}?1:0,
                      filter_fakedfromchecked           => $prefs{filter_fakedfrom},
                      filter_fakedfrommatchcount        => $filtermatch->{filter_fakedfrom}{count},
                      filter_fakedfrommatchdate         => $filtermatch->{filter_fakedfrom}{date},
                      disablefilter_fakedexecontenttype => defined $config_raw{DEFAULT_filter_fakedexecontenttype}?1:0,
                      filter_fakedexecontenttypechecked => $prefs{filter_fakedexecontenttype},
                      filter_fakedexecontenttypematchcount => $filtermatch->{filter_fakedexecontenttype}{count},
                      filter_fakedexecontenttypematchdate => $filtermatch->{filter_fakedexecontenttype}{date},
                      enable_addressbook                => $config{enable_addressbook},
                      disableabook_widthselect          => defined $config_raw{DEFAULT_abook_width}?1:0,
                      abook_widthselectloop             => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ eq 'max'?$lang_text{max}:$_,
                                                                       selected => $_ eq $prefs{abook_width}?1:0
                                                                  } } qw(300 320 340 360 380 400 420 440 460 480 500 520 540 560 580 600 700 800 900 1000 max)
                                                           ],
                      disableabook_heightselect         => defined $config_raw{DEFAULT_abook_height}?1:0,
                      abook_heightselectloop            => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ eq 'max'?$lang_text{max}:$_,
                                                                       selected => $_ eq $prefs{abook_height}?1:0
                                                                  } } qw(300 320 340 360 380 400 420 440 460 480 500 520 540 560 580 600 700 800 900 1000 max)
                                                           ],
                      disableabook_buttonpositionselect => defined $config_raw{DEFAULT_abook_buttonposition}?1:0,
                      abook_buttonpositionselectloop    => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_abookbuttonpositionlabels{$_},
                                                                       selected => $_ eq $defaultabook_buttonposition?1:0
                                                                  } } qw(before after both)
                                                           ],
                      disableabook_defaultfilter        => defined $config_raw{DEFAULT_abook_defaultfilter}?1:0,
                      abook_defaultfilterchecked        => $prefs{abook_defaultfilter},
                      disableabook_defaultsearchtypeselect => defined $config_raw{DEFAULT_abook_defaultsearchtype}?1:0,
                      abook_defaultsearchtypeselectloop => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_text{"abook_listview_$_"},
                                                                       selected => $_ eq $defaultabook_defaultsearchtype?1:0
                                                                  } } qw(fullname email phone note categories)
                                                           ],
                      disableabook_defaultkeyword       => defined $config_raw{DEFAULT_abook_defaultkeyword}?1:0,
                      abook_defaultkeywordtext          => $prefs{abook_defaultkeyword} || '',
                      disableabook_addrperpageselect    => defined $config_raw{DEFAULT_abook_addrperpage}?1:0,
                      abook_addrperpageselectloop       => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{abook_addrperpage}?1:0
                                                                  } } qw(8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 50 100 500 1000)
                                                           ],
                      disableabook_collapse             => defined $config_raw{DEFAULT_abook_collapse}?1:0,
                      abook_collapsechecked             => $prefs{abook_collapse},
                      disableabook_sortselect           => defined $config_raw{DEFAULT_abook_sort}?1:0,
                      abook_sortselectloop              => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_abooksortlabels{$_},
                                                                       selected => $_ eq $prefs{abook_sort}?1:0
                                                                  } } map { ($_,"${_}_rev") } qw(fullname prefix first middle last suffix email phone)
                                                           ],
                      disableabook_listviewfieldorderselect => defined $config_raw{DEFAULT_abook_listviewfieldorder}?1:0,
                      abook_listviewfieldorder0selectloop => [
                                                                map { {
                                                                         option   => $_,
                                                                         label    => $lang_text{"abook_listview_$_"},
                                                                         selected => $_ eq $defaultabook_listviewfieldorder0?1:0
                                                                    } } qw(fullname prefix first middle last suffix email phone note none)
                                                             ],
                      abook_listviewfieldorder1selectloop => [
                                                                map { {
                                                                         option   => $_,
                                                                         label    => $lang_text{"abook_listview_$_"},
                                                                         selected => $_ eq $defaultabook_listviewfieldorder1?1:0
                                                                    } } qw(fullname prefix first middle last suffix email phone note none)
                                                             ],
                      abook_listviewfieldorder2selectloop => [
                                                                map { {
                                                                         option   => $_,
                                                                         label    => $lang_text{"abook_listview_$_"},
                                                                         selected => $_ eq $defaultabook_listviewfieldorder2?1:0
                                                                    } } qw(fullname prefix first middle last suffix email phone note none)
                                                             ],
                      abook_listviewfieldorder3selectloop => [
                                                                map { {
                                                                         option   => $_,
                                                                         label    => $lang_text{"abook_listview_$_"},
                                                                         selected => $_ eq $defaultabook_listviewfieldorder3?1:0
                                                                    } } qw(fullname prefix first middle last suffix email phone note none)
                                                             ],
                      abook_listviewfieldorder4selectloop => [
                                                                map { {
                                                                         option   => $_,
                                                                         label    => $lang_text{"abook_listview_$_"},
                                                                         selected => $_ eq $defaultabook_listviewfieldorder4?1:0
                                                                    } } qw(fullname prefix first middle last suffix email phone note none)
                                                             ],
                      enable_calendar                   => $config{enable_calendar},
                      disablecalendar_defaultviewselect => defined $config_raw{DEFAULT_calendar_defaultview}?1:0,
                      calendar_defaultviewselectloop    => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ eq 'calyear'  ? $lang_calendar{yearview}  :
                                                                                   $_ eq 'calmonth' ? $lang_calendar{monthview} :
                                                                                   $_ eq 'calweek'  ? $lang_calendar{weekview}  :
                                                                                   $_ eq 'calday'   ? $lang_calendar{dayview}   :
                                                                                   $lang_calendar{listview},
                                                                       selected => $_ eq $prefs{calendar_defaultview}?1:0
                                                                  } } qw(calyear calmonth calweek calday callist)
                                                           ],
                      disablecalendar_holidaydefselect  => defined $config_raw{DEFAULT_calendar_holidaydef}?1:0,
                      calendar_holidaydefselectloop     => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $holidaylabels{$_},
                                                                       selected => $_ eq $prefs{calendar_holidaydef}?1:0
                                                                  } } @holidays
                                                           ],
                      disablecalendar_showlunar         => defined $config_raw{DEFAULT_calendar_showlunar}?1:0,
                      calendar_showlunarchecked         => $prefs{calendar_showlunar},
                      disablecalendar_monthviewnumitemsselect => defined $config_raw{DEFAULT_calendar_monthviewnumitems}?1:0,
                      calendar_monthviewnumitemsselectloop => [
                                                                 map { {
                                                                          option   => $_,
                                                                          label    => $_,
                                                                          selected => $_ eq $prefs{calendar_monthviewnumitems}?1:0
                                                                     } } (3..10)
                                                              ],
                      disablecalendar_weekstartselect   => defined $config_raw{DEFAULT_calendar_weekstart}?1:0,
                      calendar_weekstartselectloop      => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_wday{$_},
                                                                       selected => $_ eq $prefs{calendar_weekstart}?1:0
                                                                  } } qw(1 2 3 4 5 6 0)
                                                           ],
                      disablecalendar_starthourselect   => defined $config_raw{DEFAULT_calendar_starthour}?1:0,
                      calendar_starthourselectloop      => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{calendar_starthour}?1:0
                                                                  } } map { sprintf("%02d00", $_) } (0..24) # military time
                                                           ],
                      disablecalendar_endhourselect     => defined $config_raw{DEFAULT_calendar_endhour}?1:0,
                      calendar_endhourselectloop        => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{calendar_endhour}?1:0
                                                                  } } map { sprintf("%02d00", $_) } (0..24) # military time
                                                           ],
                      disablecalendar_intervalselect    => defined $config_raw{DEFAULT_calendar_interval}?1:0,
                      calendar_intervalselectloop       => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{calendar_interval}?1:0
                                                                  } } qw(5 10 15 20 30 45 60 90 120)
                                                           ],
                      disablecalendar_showemptyhours    => defined $config_raw{DEFAULT_calendar_showemptyhours}?1:0,
                      calendar_showemptyhourschecked    => $prefs{calendar_showemptyhours},
                      disablecalendar_reminderdaysselect => defined $config_raw{DEFAULT_calendar_reminderdays}?1:0,
                      calendar_reminderdaysselectloop    => [
                                                               map { {
                                                                        option   => $_,
                                                                        label    => $_,
                                                                        selected => $_ eq $prefs{calendar_reminderdays}?1:0
                                                                   } } qw(0 1 2 3 4 5 6 7 14 21 30 60)
                                                            ],
                      disablecalendar_reminderforglobal => defined $config_raw{DEFAULT_calendar_reminderforglobal}?1:0,
                      calendar_reminderforglobalchecked => $prefs{calendar_reminderforglobal},
                      enable_webdisk                    => $config{enable_webdisk},
                      disablewebdisk_dirnumitemsselect  => defined $config_raw{DEFAULT_webdisk_dirnumitems}?1:0,
                      webdisk_dirnumitemsselectloop     => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{webdisk_dirnumitems}?1:0
                                                                  } } qw(10 12 14 16 18 20 22 24 26 28 30 40 50 60 70 80 90 100 150 200 500 1000 5000)
                                                           ],
                      disablewebdisk_confirmmovecopy    => defined $config_raw{DEFAULT_webdisk_confirmmovecopy}?1:0,
                      webdisk_confirmmovecopychecked    => $prefs{webdisk_confirmmovecopy},
                      disablewebdisk_confirmdel         => defined $config_raw{DEFAULT_webdisk_confirmdel}?1:0,
                      webdisk_confirmdelchecked         => $prefs{webdisk_confirmdel},
                      disablewebdisk_confirmcompress    => defined $config_raw{DEFAULT_webdisk_confirmcompress}?1:0,
                      webdisk_confirmcompresschecked    => $prefs{webdisk_confirmcompress},
                      disablewebdisk_fileeditcolumnsselect => defined $config_raw{DEFAULT_webdisk_fileeditcolumns}?1:0,
                      webdisk_fileeditcolumnsselectloop => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{webdisk_fileeditcolumns}?1:0
                                                                  } } qw(80 82 84 86 88 90 92 94 96 98 100 110 120 160 192 256 512 1024 2048)
                                                           ],
                      disablewebdisk_fileeditrowsselect => defined $config_raw{DEFAULT_webdisk_fileeditrows}?1:0,
                      webdisk_fileeditrowsselectloop    => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{webdisk_fileeditrows}?1:0
                                                                  } } qw(10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 50 60 70 80)
                                                           ],
                      disablefscharsetselect            => defined $config_raw{DEFAULT_fscharset}?1:0,
                      fscharsetselectloop               => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ eq "none" ? $lang_text{none} : $_,
                                                                       selected => $_ eq $prefs{fscharset}?1:0
                                                                  } } ("none", (map { $ow::lang::charactersets{$_}[1] } sort keys %ow::lang::charactersets))
                                                           ],
                      disableuselightbar                => defined $config_raw{DEFAULT_uselightbar}?1:0,
                      uselightbarchecked                => $prefs{uselightbar},
                      disableregexmatch                 => defined $config_raw{DEFAULT_regexmatch}?1:0,
                      regexmatchchecked                 => $prefs{regexmatch},
                      disablehideinternal               => defined $config_raw{DEFAULT_hideinternal}?1:0,
                      hideinternalchecked               => $prefs{hideinternal},
                      disablecategorizedfolders         => defined $config_raw{DEFAULT_categorizedfolders}?1:0,
                      categorizedfolderschecked         => $prefs{categorizedfolders},
                      disablecategorizedfolders_fs      => defined $config_raw{DEFAULT_categorizedfolders_fs}?1:0,
                      categorizedfolders_fstext         => $prefs{categorizedfolders_fs} || '',
                      disablenewmailsoundselect         => defined $config_raw{DEFAULT_newmailsound}?1:0,
                      newmailsoundselectloop            => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ eq 'NONE' ? $lang_text{none} : $_,
                                                                       selected => $_ eq $prefs{newmailsound}?1:0
                                                                  } } @sounds
                                                           ],
                      disablenewmailwindowtimeselect    => defined $config_raw{DEFAULT_newmailwindowtime}?1:0,
                      newmailwindowtimeselectloop       => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{newmailwindowtime}?1:0
                                                                  } } qw(0 3 5 7 10 20 30 60 120 300 600)
                                                           ],
                      disablemailsentwindowtimeselect   => defined $config_raw{DEFAULT_mailsentwindowtime}?1:0,
                      mailsentwindowtimeselectloop      => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{mailsentwindowtime}?1:0
                                                                  } } qw(0 3 5 7 10 20 30)
                                                           ],
                      enable_spellcheck                 => $config{enable_spellcheck},
                      disabledictionaryselect           => defined $config_raw{DEFAULT_dictionary}?1:0,
                      dictionaryselectloop              => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_,
                                                                       selected => $_ eq $prefs{dictionary}?1:0
                                                                  } } @{$config{spellcheck_dictionaries}}
                                                           ],
                      disabletrashreserveddaysselect    => defined $config_raw{DEFAULT_trashreserveddays}?1:0,
                      trashreserveddaysselectloop       => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ == 0 ? $lang_text{delatlogout} :
                                                                                   $_ == 999999 ? $lang_text{forever} :
                                                                                   '',
                                                                       selected => $_ eq $prefs{trashreserveddays}?1:0
                                                                  } } qw(0 1 2 3 4 5 6 7 14 21 30 60 90 180 999999)
                                                           ],
                      enable_spamvirusreserveddays      => $config{has_spamfolder_by_default} || $config{has_virusfolder_by_default},
                      disablespamvirusreserveddaysselect => defined $config_raw{DEFAULT_spamvirusreserveddays}?1:0,
                      spamvirusreserveddaysselectloop   => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $_ == 0 ? $lang_text{delatlogout} :
                                                                                   $_ == 999999 ? $lang_text{forever} :
                                                                                   '',
                                                                       selected => $_ eq $prefs{spamvirusreserveddays}?1:0
                                                                  } } qw(0 1 2 3 4 5 6 7 14 21 30 60 90 180 999999)
                                                           ],
                      disablerefreshintervalselect      => defined $config_raw{DEFAULT_refreshinterval}?1:0,
                      refreshintervalselectloop         => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_timelabels{$_},
                                                                       selected => $_ eq $prefs{refreshinterval}?1:0
                                                                  } } grep { $_ >= $config{min_refreshinterval} } qw(3 5 10 20 30 60 120 180)
                                                           ],
                      disablesessiontimeoutselect       => defined $config_raw{DEFAULT_sessiontimeout}?1:0,
                      sessiontimeoutselectloop          => [
                                                              map { {
                                                                       option   => $_,
                                                                       label    => $lang_timelabels{$_},
                                                                       selected => $_ eq $prefs{sessiontimeout}?1:0
                                                                  } } qw(10 30 60 120 180 360 720 1440)
                                                           ],

                      # footer.tmpl
                      footer_template                   => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub saveprefs {
   # if any param is not passed from the prefs form, this routine will
   # use the old value instead, so we can use incomplete prefs form

   # create dir under ~/.openwebmail/
   check_and_create_dotdir(dotpath('/'));

   if ($config{enable_strictforward} && param('forwardaddress') =~ /[&;\`\<\>\(\)\{\}]/) {
      openwebmailerror(__FILE__, __LINE__, "$lang_text{forward} $lang_text{email} $lang_err{has_illegal_chars}");
   }

   my %newprefs = ();

   foreach my $key (@openwebmailrcitem) {
      if ($key eq 'abook_listviewfieldorder') {
         my @values = param($key);
         foreach my $index (0..$#values) {
            $values[$index] =~ s/\.\.+//g;
            $values[$index] =~ s/[=\n\/\`\|\<\>;]//g; # remove dangerous char
         }
         $newprefs{$key} = join(",",@values);
         next;
      }

      my $value = param($key);

      if ($key eq 'bgurl') {
         my $background = param('background');
         if ($background eq "USERDEFINE") {
            $newprefs{$key} = $value if ($value ne "");
         } else {
            $newprefs{$key} = "$config{ow_htmlurl}/images/backgrounds/$background";
         }
         next;
      } elsif ($key eq 'dateformat' || $key eq 'replyto') {
         $value =~ s/\.\.+//g;
         $value =~ s/[=\n`]//g; # remove dangerous char
         $newprefs{$key} = $value;
         next;
      } elsif (($config{zonetabfile} ne 'no') && ($key eq 'timezone') && ($value =~ /(\S+) (\S+)/)) {
         $newprefs{$key} = $2;
         $newprefs{timeoffset} = $1;
         next;
      }


      $value =~ s/\.\.+//g;
      $value =~ s#[=\n/`|<>;]##g; # remove dangerous char
      if ($key eq 'language') {
         foreach my $availablelanguage (map { m/^(.._..)/; $1 } sort keys %{$config{available_locales}}) {
            if ($value eq $availablelanguage) {
               $newprefs{$key} = $value;
               last;
            }
         }
      } elsif ($key eq 'sort') {
         # there is already a sort param inherited from outside the
         # prefs form, so the prefs form passes the sort param as msgsort
         $newprefs{$key} = param('msgsort') || 'date_rev';
      } elsif ($key eq 'dictionary') {
         foreach my $currdictionary (@{$config{spellcheck_dictionaries}}) {
            if ($value eq $currdictionary) {
               $newprefs{$key} = $value;
               last;
            }
         }
      } elsif ($key eq 'filter_repeatlimit') {
         # if repeatlimit changed, redo filtering may be needed
         if ( $value != $prefs{filter_repeatlimit} ) {
            unlink(dotpath('filter.check'));
         }
         $newprefs{$key} = $value;
      } elsif (defined($is_config_option{yesno}{"default_$key"}) ) {
         $value = 0 if ($value eq '');
         $newprefs{$key} = $value;
      } else {
         $newprefs{$key} = $value;
      }
   }

   # compile the locale
   my $localecharset = uc($newprefs{charset}); # iso-8859-1 -> ISO-8859-1
   $localecharset =~ s/[-_]//g;                # ISO-8859-1 -> ISO88591
   $newprefs{locale} = "$newprefs{language}." . $ow::lang::charactersets{$localecharset}[0];

   if (
         ($newprefs{filter_fakedsmtp} && !$prefs{filter_fakedsmtp})
         || ($newprefs{filter_fakedfrom} && !$prefs{filter_fakedfrom})
         || ($newprefs{filter_fakedexecontenttype} && !$prefs{filter_fakedexecontenttype})
      ) {
      unlink(dotpath('filter.check'));
   }
   if ($newprefs{trashreserveddays} ne $prefs{trashreserveddays}) {
      unlink(dotpath('trash.check'));
   }

   my $value = param('signature') || '';
   $value =~ s/\r\n/\n/g;
   if (length($value) > 500) {  # truncate signature to 500 chars
      $value = substr($value, 0, 500);
   }
   $newprefs{signature} = $value;

   my $forwardaddress   = param('forwardaddress')   || '';
   my $keeplocalcopy    = param('keeplocalcopy')    || 0;
   my $autoreply        = param('autoreply')        || 0;
   my $autoreplysubject = param('autoreplysubject') || '';
   my $autoreplytext    = param('autoreplytext')    || '';
   $autoreply = 0 if !$config{enable_autoreply};

   my $userfroms = get_userfroms();

   # save .forward file
   writedotforward($autoreply, $keeplocalcopy, $forwardaddress, keys %{$userfroms});

   # save .vacation.msg
   if ($config{enable_autoreply}) {
      writedotvacationmsg($autoreply, $autoreplysubject, $autoreplytext, $newprefs{signature}, $newprefs{email}, $userfroms->{$newprefs{email}}, $newprefs{charset});
   }

   # save .signature
   my $signaturefile = dotpath('signature');
   if ( !-f $signaturefile && -f "$homedir/.signature" ) {
      $signaturefile = "$homedir/.signature";
   }
   sysopen(SIGNATURE, $signaturefile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} $signaturefile! ($!)");
   print SIGNATURE $newprefs{signature};
   close(SIGNATURE) or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $signaturefile! ($!)");

   chown($uuid, (split(/\s+/,$ugid))[0], $signaturefile) if ($signaturefile eq "$homedir/.signature");

   # save .openwebmailrc
   my $rcfile = dotpath('openwebmailrc');
   sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} $rcfile! ($!)");
   print RC "$_=" . (exists $newprefs{$_} && defined $newprefs{$_} ? $newprefs{$_} : '') . "\n" for @openwebmailrcitem;
   close(RC) or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $rcfile! ($!)");

   %prefs = readprefs();
   loadlang($prefs{locale});
   charset((ow::lang::localeinfo($prefs{locale}))[6]) if ($CGI::VERSION>=2.58); # setup charset of CGI module

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_saved.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template     => get_header($config{header_template_file}),

                      # standard params
                      sessionid           => $thissession,
                      folder              => $folder,
                      message_id          => $messageid,
                      sort                => $prefs{sort}, # reset
                      page                => $page,
                      longpage            => $longpage,
                      url_cgi             => $config{ow_cgiurl},

                      # prefs_saved.tmpl
                      caller_calendar     => $prefs_caller eq 'cal'?1:0,
                      calendardefaultview => $prefs{calendar_defaultview},
                      caller_webdisk      => $prefs_caller eq 'webdisk'?1:0,
                      caller_read         => $prefs_caller eq 'read'?1:0,
                      caller_addrlistview => $prefs_caller eq 'addrlistview'?1:0,
                      caller_main         => $prefs_caller eq 'main'?1:0,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub readdotforward {
   my $forwardtext = '';

   if (sysopen(FOR, "$homedir/.forward", O_RDONLY)) {
      local $/ = undef;
      $forwardtext = <FOR>;
      close(FOR);
   }

   # get flags and forward list with selfemail and vacationpipe removed
   my ($autoreply, $keeplocalcopy, @forwards) = splitforwardtext($forwardtext, 0, 0);
   $keeplocalcopy = 0 if scalar @forwards == 0;
   return ($autoreply, $keeplocalcopy, @forwards);
}

sub splitforwardtext {
   my ($forwardtext, $autoreply, $keeplocalcopy) = @_;

   # remove self email and vacation from forward list
   # set keeplocalcopy if self email found
   # set autoreply if vacation found
   my $vacation_bin = (split(/\s+/,$config{vacationpipe}))[0];

   my @forwards = ();

   foreach my $name ( split(/[,;\n\r]+/, $forwardtext) ) {
      $name =~ s/^\s+//;
      $name =~ s/\s+$//;
      next if ( $name =~ m/^$/ );

      if ($name =~ m/$vacation_bin/) {
         $autoreply = 1;
      } elsif ( is_selfemail($name) ) {
         $keeplocalcopy = 1;
      } else {
         push(@forwards, $name);
      }
   }

   return ($autoreply, $keeplocalcopy, @forwards);
}

sub is_selfemail {
   my $email = shift;
   if ( $email =~ m/$user\@(.+)/i ) {
      foreach ( @{$config{domainnames}} ) {
         return 1 if (lc($1) eq lc($_));
      }
   }
   return 1 if ($email eq "\\$user" || $email eq $user);
   return 1 if ($config{auth_module} eq 'auth_vdomain.pl' && $email eq vdomain_userspool($user,$homedir));
   return 0;
}

sub writedotforward {
   my ($autoreply, $keeplocalcopy, $forwardtext, @userfrom) = @_;

   my @forwards = ();

   # don't allow forward to self (avoid mail loops!)
   # splitforwardtext will remove self emails
   ($autoreply, $keeplocalcopy, @forwards) = splitforwardtext($forwardtext, $autoreply, $keeplocalcopy);

   # if no other forwards, keeplocalcopy is required
   # only if autoreply is on or if this is a virtual user
   $keeplocalcopy = (($autoreply || $config{auth_module} eq 'auth_vdomain.pl')?1:0) if scalar @forwards == 0;

   # nothing enabled, clean .forward
   if (!$autoreply && !$keeplocalcopy && scalar @forwards == 0 ) {
      unlink("$homedir/.forward");
      return 0;
   }

   if ($autoreply) {
      # if this user has multiple fromemail or be mapped from another loginname
      # then use -a with vacation.pl to add these aliases for to: and cc: checking
      my $aliasparm = "";
      foreach (sort_emails_by_domainnames($config{domainnames}, @userfrom)) {
         $aliasparm .= "-a $_ ";
      }
      $aliasparm .= "-a $loginname " if ($loginname ne $user);

      my $vacationuser = $user;
      if ($config{auth_module} eq 'auth_vdomain.pl') {
         $vacationuser = "-p$homedir nobody";
      }
      if (length("xxx$config{vacationpipe} $aliasparm $vacationuser") < 250) {
         push(@forwards, qq!"| $config{vacationpipe} $aliasparm $vacationuser"!);
      } else {
         push(@forwards, qq!"| $config{vacationpipe} -j $vacationuser"!);
      }
   }

   if ($keeplocalcopy) {
      if ($config{auth_module} eq 'auth_vdomain.pl') {
         push(@forwards, vdomain_userspool($user,$homedir));
      } else {
         push(@forwards, "\\$user");
      }
   }

   sysopen(FORWARD, "$homedir/.forward", O_WRONLY|O_TRUNC|O_CREAT) or return -1;
   print FORWARD join("\n", @forwards), "\n";
   close FORWARD;

   chown($uuid, (split(/\s+/,$ugid))[0], "$homedir/.forward");
   chmod(0600, "$homedir/.forward");
}

sub readdotvacationmsg {
   my ($subject, $text) = ('','');

   if (sysopen(MSG, "$homedir/.vacation.msg", O_RDONLY)) {
      my $inheader = 1;
      while (<MSG>) {
         chomp($_);
         if ($inheader == 0) {
            $text .= "$_\n";
            next;
         }
         if (m/^Subject:\s*(.*)/i) {
            $subject = $1;
         } elsif (m/^[A-Za-z0-9\-]+: /i) {
            next;
         } else {
            $inheader = 0;
            $text .= "$_\n";
         }
      }
      close MSG;
   }

   $subject = $config{default_autoreplysubject} if ($subject eq "");
   $subject =~ s/\s/ /g;
   $subject =~ s/^\s+//;
   $subject =~ s/\s+$//;

   # remove signature
   my $s = $prefs{signature};
   $s =~ s/\r\n/\n/g;

   my $i = rindex($text, $s);

   $text = substr($text, 0, $i) if ($i > 0);

   $text = $config{default_autoreplytext} if ($text eq "");
   $text =~ s/\r\n/\n/g;
   $text =~ s/^\s+//s;
   $text =~ s/\s+$//s;

   return($subject, $text);
}

sub writedotvacationmsg {
   my ($autoreply, $subject, $text, $signature, $email, $userfrom, $charset) = @_;

   my $from;
   if ($userfrom) {
      $from = qq|"$userfrom" <$email>|;
   } else {
      $from = $email;
   }

   # TODO: No error checking, no error reporting here whatsoever. Please fix.
   # TODO: See spamcheck.pl for reference on fork with error reporting.
   # TODO: Also, this process is never killed? it just runs forever?
   if ($autoreply) {
      local $|=1; # flush all output
      if ( fork() == 0 ) {		# child
         writelog("debug - vacationinit autoreply process forked - " .__FILE__.":". __LINE__) if ($config{debug_fork});
         close(STDIN); close(STDOUT); close(STDERR);

         ow::suid::drop_ruid_rgid();
         # set environment variables for vacation program
         $ENV{USER}    = $user;
         $ENV{LOGNAME} = $user;
         $ENV{HOME}    = $homedir;
         delete $ENV{GATEWAY_INTERFACE};
         my @cmd;
         foreach (split(/\s/, $config{vacationinit})) {
            local $1; # fix perl $1 taintness propagation bug
            m/^(.*)$/ && push(@cmd, $1); # untaint all argument
         }
         exec(@cmd);

         exit 0; # should never reach here
      }
   }

   $subject =~ s/\s/ /g;
   $subject =~ s/^\s+//;
   $subject =~ s/\s+$//;
   $subject = $config{default_autoreplysubject} if ($subject eq "");

   $text =~ s/\r\n/\n/g;
   $text =~ s/^\s+//s;
   $text =~ s/\s+$//s;
   $text = $config{default_autoreplytext} if ($text eq "");

   if (length($text) > 500) { # truncate to 500 chars
      $text = substr($text, 0, 500);
   }

   sysopen(MSG, "$homedir/.vacation.msg", O_WRONLY|O_TRUNC|O_CREAT) or return -2;
   print MSG "From: $from\n" .
             "Subject: $subject\n" .
             "Mime-Version: 1.0\n" .
             "Content-Type: text/plain; charset=$charset\n" .
             "Content-Transfer-Encoding: 8bit\n\n" .
             "$text\n\n" .
             $signature; # append signature
   close MSG;
   chown($uuid, (split(/\s+/,$ugid))[0], "$homedir/.vacation.msg");
}

sub editpassword {
   my $url_chpwd = $config{ow_cgiurl};

   # force back to SSL
   $url_chpwd = "https://$ENV{HTTP_HOST}$url_chpwd" if (cookie("ow-ssl") && $url_chpwd !~ s#^https?://#https://#i);

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_editpassword.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      folder          => $folder,
                      message_id      => $messageid,
                      sort            => $sort,
                      page            => $page,
                      longpage        => $longpage,
                      userfirsttime   => $userfirsttime,
                      prefs_caller    => $prefs_caller,
                      url_cgi         => $config{ow_cgiurl},

                      # prefs_editpassword.tmpl
                      url_chpwd       => $url_chpwd,
                      loginnametext   => $loginname,
                      passwd_minlen   => $config{passwd_minlen},

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub changepassword {
   my $oldpassword        = param('oldpassword') || '';
   my $newpassword        = param('newpassword') || '';
   my $confirmnewpassword = param('confirmnewpassword') || '';

   if (length($newpassword) < $config{passwd_minlen}) {
      $lang_err{pwd_tooshort} =~ s#\@\@\@PASSWDMINLEN\@\@\@#$config{passwd_minlen}#i;
      return editpassword_fail($lang_err{pwd_tooshort});
   } elsif ($config{enable_strictpwd} && ($newpassword =~ m/^\d+$/ || $newpassword =~ m/^[A-Za-z]+$/)) {
      # TODO: it would be cool if sysadmins could submit a regex to match a password scheme
      return editpassword_fail($lang_err{pwd_toosimple});
   } elsif ( $newpassword ne $confirmnewpassword ) {
      return editpassword_fail($lang_err{pwd_confirmmismatch});
   } else {
      my ($errorcode, $errormsg) = ();

      if ($config{auth_withdomain}) {
         ($errorcode, $errormsg) = ow::auth::change_userpassword(\%config, "$user\@$domain", $oldpassword, $newpassword);
      } else {
         ($errorcode, $errormsg) = ow::auth::change_userpassword(\%config, $user, $oldpassword, $newpassword);
      }

      if ($errorcode == 0) {
         # update authpop3book since it will be used to fetch mail from remote pop3 in this active session
         if ($config{auth_module} eq 'auth_ldap_vpopmail.pl') {
            update_authpop3book(dotpath('authpop3.book'), $domain, $user, $newpassword);
         }
         writelog("change password");
         writehistory("change password");
      } else {
         writelog("change password error - $config{auth_module}, ret $errorcode, $errormsg");
         writehistory("change password error - $config{auth_module}, ret $errorcode, $errormsg");

         return editpassword_fail(
                                    $errorcode == -1 ? $lang_err{func_notsupported} :
                                    $errorcode == -2 ? $lang_err{param_fmterr}      :
                                    $errorcode == -3 ? $lang_err{auth_syserr}       :
                                    $errorcode == -4 ? $lang_err{pwd_incorrect}     :
                                    "Unknown error code $errorcode"
                                 );
      }
   }

   # password change was successful if we are here
   my $url_afterchpass = $config{ow_cgiurl};
   if ( !$config{stay_ssl_afterlogin} && ($ENV{HTTPS} =~ m/on/i || $ENV{SERVER_PORT} == 443) ) {
      # force back to http://
      $url_afterchpass = "http://$ENV{HTTP_HOST}$url_afterchpass" if ($url_afterchpass !~ s#^https?://#http://#i);
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_editpassword_pass.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      folder          => $folder,
                      message_id      => $messageid,
                      sort            => $sort,
                      page            => $page,
                      longpage        => $longpage,
                      userfirsttime   => $userfirsttime,
                      prefs_caller    => $prefs_caller,

                      # prefs_editpassword_fail.tmpl
                      url_afterchpass => $url_afterchpass,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub editpassword_fail {
   my $errormessage = shift;

   my $url_afterchpass = $config{ow_cgiurl};
   if ( !$config{stay_ssl_afterlogin} && ($ENV{HTTPS} =~ m/on/i || $ENV{SERVER_PORT} == 443) ) {
      # force to http://
      $url_afterchpass = "http://$ENV{HTTP_HOST}$url_afterchpass" if ($url_afterchpass !~ s#^https?://#http://#i);
   }

   my $url_tryagain = $config{ow_cgiurl};
   if (cookie("ow-ssl") && $url_tryagain !~ s#^https?://#https://#i) {
      # force to SSL
      $url_tryagain = "https://$ENV{HTTP_HOST}$url_tryagain";
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_editpassword_fail.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      folder          => $folder,
                      message_id      => $messageid,
                      sort            => $sort,
                      page            => $page,
                      longpage        => $longpage,
                      userfirsttime   => $userfirsttime,
                      prefs_caller    => $prefs_caller,

                      # prefs_editpassword_fail.tmpl
                      errormessage    => $errormessage,
                      url_afterchpass => $url_afterchpass,
                      url_tryagain    => $url_tryagain,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub viewhistory {
   my $historyfile = dotpath('history.log');

   sysopen(HISTORYLOG, $historyfile, O_RDONLY) or
     openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_open} $historyfile! ($!)");

   my $historyloop = [];

   while (<HISTORYLOG>) {
      chomp($_);
      my ($timestamp, $pid, $ip, $misc) = $_ =~ m/^(.*?) - \[(\d+)\] \((.*?)\) (.*)$/;

      # pathnames appearing in the history file are in the filesystem charset,
      # so we must call f2u() before showing them to the user
      my ($u, $event, $desc, $desc2) = split(/ \- /, $misc, 4);
      $desc = f2u($desc);

      push(@{$historyloop}, {
                               is_warning => ((defined $event && $event =~ m/(?:error|warning)/i) || (defined $desc && $desc =~ m/(?:spam|virus) .* found/i))?1:0,
                               timestamp  => $timestamp,
                               ip_address => $ip,
                               username   => $u,
                               event      => $event,
                               desc       => $desc,
                               descshort  => length $desc > 40 ? (substr($desc, 0, 40) . "...") : $desc,
                            }
          );
   }

   close(HISTORYLOG) or
     openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $historyfile! ($!)");

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_viewhistory.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 1,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      folder          => $folder,
                      message_id      => $messageid,
                      sort            => $sort,
                      page            => $page,
                      longpage        => $longpage,
                      userfirsttime   => $userfirsttime,
                      prefs_caller    => $prefs_caller,
                      url_cgi         => $config{ow_cgiurl},
                      url_html        => $config{ow_htmlurl},
                      use_texticon    => ($prefs{iconset} =~ m/^Text\./?1:0),
                      iconset         => $prefs{iconset},

                      # prefs_viewhistory.tmpl
                      historyloop     => $historyloop,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub editfroms {
   my $frombookfile = dotpath('from.book');
   my $userfroms    = get_userfroms();

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_editfroms.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 1,
                                        global_vars       => 1,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      sessionid                  => $thissession,
                      folder                     => $folder,
                      message_id                 => $messageid,
                      sort                       => $sort,
                      page                       => $page,
                      longpage                   => $longpage,
                      userfirsttime              => $userfirsttime,
                      prefs_caller               => $prefs_caller,
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => ($prefs{iconset} =~ m/^Text\./?1:0),
                      iconset                    => $prefs{iconset},

                      # prefs_editfroms.tmpl
                      disablerealname            => defined $config{DEFAULT_realname}?1:0,
                      realnametext               => defined $config{DEFAULT_realname}?$config{DEFAULT_realname}:'',
                      frombook_for_realname_only => $config{frombook_for_realname_only}?1:0,
                      fromsloop                  => [
                                                       map { {
                                                                email    => $_,
                                                                realname => $userfroms->{$_}
                                                           } } sort_emails_by_domainnames($config{domainnames}, keys %{$userfroms})
                                                    ],

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub modfrom {
   my $mode     = shift;

   my $realname = param('realname') || '';
   my $email    = param('email')    || '';

   $realname =~ s/^\s*//;
   $realname =~ s/\s*$//;

   $email =~ s/[<>\[\]\\,;:`"\s]//g;

   my $frombookfile = dotpath('from.book');

   if ($email) {
      my $userfroms = get_userfroms();

      if ($mode eq 'delete') {
         delete $userfroms->{$email};
      } else {
         if ( (-s $frombookfile) >= ($config{maxbooksize} * 1024) ) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{abook_toobig} <a href="| . ow::htmltext::str2html("$config{ow_cgiurl}/openwebmail-prefs.pl?action=editfroms&sessionid=$thissession&folder=$folder&message_id=$messageid&sort=$sort&page=$page&userfirsttime=$userfirsttime&prefs_caller=$prefs_caller") . qq|">$lang_err{back}</a>$lang_err{tryagain}|, "passthrough");

         }
         if (!$config{frombook_for_realname_only} || defined $userfroms->{$email}) {
            $userfroms->{$email} = $realname;
         }
      }

      sysopen(FROMBOOK, $frombookfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} $frombookfile! ($!)");
      foreach $email (sort_emails_by_domainnames($config{domainnames}, keys %{$userfroms})) {
         print FROMBOOK "$email\@\@\@$userfroms->{$email}\n";
      }
      close(FROMBOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $frombookfile! ($!)");
   }

   editfroms();
}

sub editpop3 {
   my $pop3bookfile = dotpath('pop3.book');
   my $pop3booksize = ( -s $pop3bookfile ) || 0;

   my %accounts;
   if (readpop3book($pop3bookfile, \%accounts) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $pop3bookfile!");
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_editpop3.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 1,
                                        global_vars       => 1,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template         => get_header($config{header_template_file}),

                      # standard params
                      sessionid               => $thissession,
                      folder                  => $folder,
                      message_id              => $messageid,
                      sort                    => $sort,
                      page                    => $page,
                      longpage                => $longpage,
                      userfirsttime           => $userfirsttime,
                      prefs_caller            => $prefs_caller,
                      url_cgi                 => $config{ow_cgiurl},
                      url_html                => $config{ow_htmlurl},
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./?1:0),
                      iconset                 => $prefs{iconset},

                      # prefs_editpop3.tmpl
                      freespace               => int($config{maxbooksize} - ($pop3booksize/1024) + .5),
                      pop3_delmail_hidden     => $config{pop3_delmail_hidden},
                      pop3_delmail_by_default => $config{pop3_delmail_by_default},
                      is_ssl_supported        => ow::tool::has_module('IO/Socket/SSL.pm'),
                      pop3_usessl_by_default  => $config{pop3_usessl_by_default},
                      accountsloop            => [
                                                    map {
                                                           my @account = split(/\@\@\@/,$_);
                                                           {
                                                              pop3host   => $account[0],
                                                              pop3port   => $account[1],
                                                              pop3ssl    => $account[2],
                                                              pop3user   => $account[3],
                                                              # don't show passwords in the form
                                                              # pop3passwd => $account[4],
                                                              pop3del    => $account[5],
                                                              enable     => $account[6],
                                                           }
                                                        } sort values %accounts
                                                 ],

                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub modpop3 {
   my $mode = shift;

   my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del, $enable);
   $pop3host   = param('pop3host')   || '';
   $pop3port   = param('pop3port')   || '110';
   $pop3ssl    = param('pop3ssl')    || 0;
   $pop3user   = param('pop3user')   || '';
   $pop3passwd = param('pop3passwd') || '';
   $pop3del    = param('pop3del')    || 0;
   $enable     = param('enable')     || 0;

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

   if ( ($pop3host && $pop3user && $pop3passwd) || (($mode eq 'delete') && $pop3host && $pop3user) ) {
      my %accounts;

      if (readpop3book($pop3bookfile, \%accounts) < 0) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $pop3bookfile!");
      }

      my $thisaccount = "$pop3host:$pop3port\@\@\@$pop3user";

      if ($mode eq 'delete') {
         delete $accounts{$thisaccount};
      } else {
         # add a new pop3 account
         if ( (-s $pop3bookfile) >= ($config{maxbooksize} * 1024) ) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{abook_toobig} <a href="| . ow::htmltext::str2html("$config{ow_cgiurl}/openwebmail-prefs.pl?action=editpop3&sessionid=$thissession&folder=$folder&message_id=$messageid&sort=$sort&page=$page&userfirsttime=$userfirsttime&prefs_caller=$prefs_caller") . qq|">$lang_err{back}</a>$lang_err{tryagain}|, "passthrough");
         }

         foreach ( @{$config{pop3_disallowed_servers}} ) {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{disallowed_pop3} $pop3host") if ($pop3host eq $_);
         }

         $pop3port = 110 if ($pop3port !~ /^\d+$/);

         if (exists $accounts{$thisaccount} && defined $accounts{$thisaccount} && $pop3passwd =~ m#^\*+$#) {
            $pop3passwd = (split(/\@\@\@/, $accounts{$thisaccount}))[4];
         }

         $accounts{$thisaccount} = "$pop3host\@\@\@$pop3port\@\@\@$pop3ssl\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable";
      }

      if (writepop3book($pop3bookfile, \%accounts) < 0) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} $pop3bookfile!");
      }

      # remove unused pop3 uidl db
      if (opendir(POP3DIR, dotpath('pop3'))) {
         my @delfiles;
         while (defined(my $filename = readdir(POP3DIR))) {
            if ( $filename =~ /uidl\.(.*)\.(?:db|dir|pag)$/) {
               ($pop3user, $pop3host, $pop3port) = $1 =~ m/^(.*)\@(.*):(.*)$/;
               unless (exists $accounts{$thisaccount} && defined $accounts{$thisaccount}) {
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

sub editstat {
   my %stationery = ();

   my $statbookfile = dotpath('stationery.book');
   if (-f $statbookfile) {
      my ($ret, $errmsg) = read_stationerybook($statbookfile,\%stationery);
      openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);
   }

   my $folderstr = '';
   if ($prefs_caller eq 'read') {
      $folderstr = $lang_folders{$folder} || f2u($folder);
   }

   # load the stat for edit only if editstat button is clicked
   my ($editstatname, $editstatbody) = ('','');
   if (param('editstatbutton')) {
      $editstatname = param('statname') || '';
      $editstatname = (iconv($stationery{$editstatname}{charset}, $prefs{charset}, $editstatname))[0];
      $editstatbody = (iconv($stationery{$editstatname}{charset}, $prefs{charset}, $stationery{$editstatname}{content}))[0];
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_editstationery.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 1,
                                        global_vars       => 1,
                                        cache             => 1,
                                     );

   # TODO: sync the config option names with the tmpl vars
   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      folder          => $folder,
                      message_id      => $messageid,
                      sort            => $sort,
                      page            => $page,
                      longpage        => $longpage,
                      userfirsttime   => $userfirsttime,
                      prefs_caller    => $prefs_caller,
                      url_cgi         => $config{ow_cgiurl},
                      url_html        => $config{ow_htmlurl},
                      use_texticon    => ($prefs{iconset} =~ m/^Text\./?1:0),
                      use_fixedfont   => $prefs{usefixedfont},
                      iconset         => $prefs{iconset},

                      # prefs_editstationery.tmpl
                      caller_read     => $prefs_caller eq 'read'?1:0,
                      folderstr       => $folderstr,
                      stationeryloop  => [
                                            map {
                                                    my $statname    = (iconv($stationery{$_}{charset}, $prefs{charset}, $_))[0];
                                                    my $statcontent = (iconv($stationery{$_}{charset}, $prefs{charset}, $stationery{$_}{content}))[0];
                                                    $statcontent    = (substr($statcontent, 0, 100) . "...") if length $statcontent > 105;
                                                    {
                                                      statname    => $statname,
                                                      statcontent => $statcontent,
                                                    }
                                                 } sort keys %stationery
                                         ],
                      editstatname    => $editstatname,
                      editstatbody    => $editstatbody,
                      textareacolumns => $prefs{editcolumns} || '78',

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub addstat {
   my $newname    = param('editstatname') || '';
   my $newcontent = param('editstatbody') || '';

   my %stationery = ();

   if($newname ne '' && $newcontent ne '') {
      # save msg to file stationery
      # load the stationery first and save after, if exist overwrite
      my $statbookfile = dotpath('stationery.book');
      if (-f $statbookfile) {
         ow::filelock::lock($statbookfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} $statbookfile!");

         my ($ret, $errmsg) = read_stationerybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);

         $stationery{$newname}{content} = $newcontent;
         $stationery{$newname}{charset} = $prefs{charset};

         ($ret, $errmsg) = write_stationerybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);

         ow::filelock::lock($statbookfile, LOCK_UN);
      } else {
         $stationery{$newname}{content} = $newcontent;
         $stationery{$newname}{charset} = $prefs{charset};

         my ($ret, $errmsg) = write_stationerybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);
      }
   }

   editstat();
}

sub delstat {
   my $statname = param('statname') || '';
   if ($statname) {
      my %stationery;
      my $statbookfile = dotpath('stationery.book');
      if (-f $statbookfile) {
         ow::filelock::lock($statbookfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} $statbookfile!");
         my ($ret, $errmsg) = read_stationerybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);

         delete $stationery{$statname} if exists $stationery{$statname};

         ($ret, $errmsg) = write_stationerybook($statbookfile,\%stationery);
         openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);

         ow::filelock::lock($statbookfile, LOCK_UN);
      }
   }

   editstat();
}

sub clearstat {
   my $statbookfile = dotpath('stationery.book');

   if (-f $statbookfile) {
      unlink($statbookfile) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_delete} $statbookfile! ($!)");
   }
   writelog("clear stationery");
   writehistory("clear stationery");

   editstat();
}

sub editfilter {
   my $filterbookfile = dotpath('filter.book');
   my $filterbooksize = ( -s $filterbookfile ) || 0;

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   my (%filterrules, @sorted_filterrules, %globalfilterrules, @sorted_globalfilterrules);

   if (-f $filterbookfile) {
      my ($ret, $errmsg) = read_filterbook($filterbookfile, \%filterrules);
      openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);
   }
   @sorted_filterrules = sort_filterrules(\%filterrules);

   if ( $config{enable_globalfilter} && -f "$config{global_filterbook}" ) {
      my ($ret, $errmsg) = read_filterbook($config{global_filterbook}, \%globalfilterrules);
      @sorted_globalfilterrules = sort_filterrules(\%globalfilterrules) if ($ret == 0);
   }

   my $filterruledb   = dotpath('filter.ruledb');

   my %FILTERRULEDB;
   ow::dbm::open(\%FILTERRULEDB, $filterruledb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db $filterruledb");

   my $filterrulesloop = [];
   foreach my $key (@sorted_filterrules) {
      my %rule = %{$filterrules{$key}};

      my ($matchcount, $matchdate) = split(":", $FILTERRULEDB{$key});

      if ($matchdate) {
         $matchdate = ow::datetime::dateserial2str(
                                                     $matchdate,
                                                     $prefs{timeoffset},
                                                     $prefs{daylightsaving},
                                                     $prefs{dateformat},
                                                     $prefs{hourformat},
                                                     $prefs{timezone}
                                                  );
      }

      my ($textstr, $deststr) = iconv($rule{charset}, $prefs{charset}, $rule{text}, $rule{dest});

      push(@{$filterrulesloop}, {
                                   matchcount    => $matchcount,
                                   matchdate     => $matchdate,
                                   priority      => $rule{priority},
                                   type          => $rule{type},
                                   typetext      => $lang_text{$rule{type}},
                                   include       => $rule{inc},
                                   includetext   => $lang_text{$rule{inc}},
                                   text          => $textstr,
                                   operation     => $rule{op},
                                   operationtext => $rule{dest} eq 'INBOX'?'-----':$lang_text{$rule{op}},
                                   dest          => $deststr,
                                   desttext      => exists $lang_folders{$rule{dest}}?$lang_folders{$rule{dest}}:$deststr,
                                   enable        => $rule{enable},
                                }
          );
   }

   my $globalrulesloop = [];
   foreach my $key (@sorted_globalfilterrules) {
      my %rule = %{$globalfilterrules{$key}};

      my ($matchcount, $matchdate) = (0,0);

      if (defined $FILTERRULEDB{$key}) {
         ($matchcount, $matchdate) = split(":", $FILTERRULEDB{$key});

         if ($matchdate) {
            $matchdate = ow::datetime::dateserial2str(
                                                        $matchdate,
                                                        $prefs{timeoffset},
                                                        $prefs{daylightsaving},
                                                        $prefs{dateformat},
                                                        $prefs{hourformat},
                                                        $prefs{timezone}
                                                     );
         }
      }

      my ($textstr, $deststr) = iconv($rule{charset}, $prefs{charset}, $rule{text}, $rule{dest});

      push(@{$globalrulesloop}, {
                                   matchcount    => $matchcount,
                                   matchdate     => $matchdate,
                                   priority      => $rule{priority},
                                   type          => $rule{type},
                                   typetext      => $lang_text{$rule{type}},
                                   include       => $rule{inc},
                                   includetext   => $lang_text{$rule{inc}},
                                   text          => $textstr,
                                   operation     => $rule{op},
                                   operationtext => $rule{dest} eq 'INBOX'?'-----':$lang_text{$rule{op}},
                                   dest          => $deststr,
                                   desttext      => exists $lang_folders{$rule{dest}}?$lang_folders{$rule{dest}}:$deststr,
                                   enable        => $rule{enable},
                                }
          );
   }

   ow::dbm::close(\%FILTERRULEDB, $filterruledb);

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_editfilter.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 1,
                                        global_vars       => 1,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template       => get_header($config{header_template_file}),

                      # standard params
                      sessionid             => $thissession,
                      folder                => $folder,
                      message_id            => $messageid,
                      sort                  => $sort,
                      page                  => $page,
                      longpage              => $longpage,
                      userfirsttime         => $userfirsttime,
                      prefs_caller          => $prefs_caller,
                      url_cgi               => $config{ow_cgiurl},
                      url_html              => $config{ow_htmlurl},
                      use_texticon          => ($prefs{iconset} =~ m/^Text\./?1:0),
                      iconset               => $prefs{iconset},

                      # prefs_editfilter.tmpl
                      freespace             => int($config{maxbooksize} - ($filterbooksize/1024) + .5),
                      callerfoldername      => $lang_folders{$folder}||f2u($folder),
                      caller_calendar       => $prefs_caller eq 'cal'?1:0,
                      calendardefaultview   => $prefs{calendar_defaultview},
                      caller_webdisk        => $prefs_caller eq 'webdisk'?1:0,
                      caller_read           => $prefs_caller eq 'read'?1:0,
                      caller_main           => $prefs_caller eq 'main'?1:0,
                      priorityselectloop    => [
                                                  map { {
                                                           option   => $_,
                                                           label    => $_,
                                                           selected => $_ eq 10?1:0
                                                      } } map { sprintf('%02d', $_) } (1..20)
                                               ],
                      ruletypeselectloop    => [
                                                  map { {
                                                           option   => $_,
                                                           label    => $lang_text{$_},
                                                           selected => $_ eq 'subject'?1:0
                                                      } } qw(from to subject smtprelay header textcontent attfilename)
                                               ],
                      includeselectloop     => [
                                                  map { {
                                                           option   => $_,
                                                           label    => $lang_text{$_},
                                                           selected => $_ eq 'include'?1:0
                                                      } } qw(include exclude)
                                               ],
                      operationselectloop   => [
                                                  map { {
                                                           option   => $_,
                                                           label    => $lang_text{$_},
                                                           selected => $_ eq 'move'?1:0
                                                      } } qw(move copy)
                                               ],
                      destinationselectloop => [
                                                  map { {
                                                           option   => $_,
                                                           label    => exists $lang_folders{$_}?$lang_folders{$_}:$_,
                                                           selected => $_ eq 'mail-trash'?1:0
                                                      } } iconv($prefs{fscharset}, $prefs{charset}, @validfolders, 'DELETE')
                                               ],
                      filterrulesloop       => $filterrulesloop,
                      globalrulesloop       => $globalrulesloop,

                      # footer.tmpl
                      footer_template       => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub modfilter {
   my $mode = shift;

   my $priority    = param('priority') || '';
   my $ruletype    = param('ruletype') || '';
   my $include     = param('include') || '';
   my $text        = param('text') || '';
   my $op          = param('op') || 'move';
   my $destination = safefoldername(param('destination')) || '';
   my $enable      = param('enable') || 0;

   my $filterbookfile = dotpath('filter.book');
   my $filterruledb   = dotpath('filter.ruledb');

   # add mode    -> can't have null $ruletype, null $text, or null $destination
   # delete mode -> can't have null $filter
   if (($ruletype && $include && $text && $destination && $priority)
       || (($mode eq 'delete') && ($ruletype && $include && $text && $destination))) {

      my %filterrules;

      if (-f $filterbookfile) {
         if ($mode ne 'delete' && (-s $filterbookfile) >= ($config{maxbooksize}*1024)) {
            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{abook_toobig} <a href="| . ow::htmltext::str2html("$config{ow_cgiurl}/openwebmail-prefs.pl?action=editaddresses&sessionid=$thissession&folder=$folder&message_id=$messageid&sort=$sort&page=$page&longpage=$longpage&userfirsttime=$userfirsttime&prefs_caller=$prefs_caller") . qq|">$lang_err{back}</a>$lang_err{tryagain}|, "passthrough");
         }

         # read personal filter and update it
         ow::filelock::lock($filterbookfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} $filterbookfile!");

         my ($ret, $errmsg) = read_filterbook($filterbookfile, \%filterrules);
         openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);

         if ($mode eq 'delete') {
            $text = ow::tool::unescapeURL($text);
            $destination = ow::tool::unescapeURL($destination);
            my $key = "$ruletype\@\@\@$include\@\@\@$text\@\@\@$destination";
            delete $filterrules{$key};
         } else {
            my $key = "$ruletype\@\@\@$include\@\@\@$text\@\@\@$destination";
            $text =~ s/\@\@/\@\@ /;
            $text =~ s/\@$/\@ /;
            my %rule;
            @rule{qw(priority type inc text op dest enable charset)}
                 = ($priority, $ruletype, $include, $text, $op, $destination, $enable, $prefs{charset});
            $filterrules{$key} = \%rule;
         }

         ($ret, $errmsg) = write_filterbook($filterbookfile, \%filterrules);
         openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);

         ow::filelock::lock($filterbookfile, LOCK_UN);

         # read global filter into hash %filterrules
         if ($config{global_filterbook} ne "" && -f $config{global_filterbook}) {
            ($ret, $errmsg) = read_filterbook($filterbookfile, \%filterrules);
         }

         # remove stale entries in filterrule db by checking %filterrules
         my (%FILTERRULEDB, @keys);
         ow::dbm::open(\%FILTERRULEDB, $filterruledb, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} db $filterbookfile");
         foreach my $key (keys %FILTERRULEDB) {
           if (!defined $filterrules{$key}
               && $key ne "filter_badaddrformat"
               && $key ne "filter_fakedexecontenttype"
               && $key ne "filter_fakedfrom"
               && $key ne "filter_fakedsmtp"
               && $key ne "filter_repeatlimit") {
              delete $FILTERRULEDB{$key};
           }
         }
         ow::dbm::close(\%FILTERRULEDB, $filterruledb);
      } else {
         $text =~ s/\@\@/\@\@ /;
         $text =~ s/\@$/\@ /;
         my %rule;
         @rule{qw(priority type inc text op dest enable charset)}
            = ($priority, $ruletype, $include, $text, $op, $destination, $enable, $prefs{charset});
         my $key = "$ruletype\@\@\@$include\@\@\@$text\@\@\@$destination";
         $filterrules{$key} = \%rule;
         my ($ret, $errmsg) = write_filterbook($filterbookfile, \%filterrules);
         openwebmailerror(__FILE__, __LINE__, $errmsg) if ($ret < 0);
      }

      unlink(dotpath('filter.check'));
   }

   if ( param('message_id') ) {
      my $searchtype     = param('searchtype') || 'subject';
      my $keyword        = param('keyword') || '';
      my $headers        = param('headers') || $prefs{headers} || 'simple';
      my $attmode        = param('attmode') || 'simple';
      my $escapedkeyword = ow::tool::escapeURL($keyword);
      print redirect(-location=>"$config{ow_cgiurl}/openwebmail-read.pl?action=readmessage&sessionid=$thissession&page=$page&longpage=$longpage&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$folder&message_id=$messageid&headers=$headers&attmode=$attmode");
   } else {
      editfilter();
   }
}

sub timeoutwarning {
   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("prefs_timeoutwarning.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template    => get_header($config{header_template_file}),

                      # no standard params used in this template

                      # prefs_timeoutwarning.tmpl
                      useremail          => $prefs{email},

                      # no footer.tmpl in this template
                   );

   httpprint([], [$template->output]);
}
