#!/usr/bin/suidperl -T
#
# openwebmail-saprefs.pl - spamassassin user_prefs file config
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

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err);	# defined in lang/xy
use vars qw(%lang_satestfields %lang_satesttypes %lang_satestheaderattrs);

# local globals
use vars qw($folder $messageid);
use vars qw($sort $page);
use vars qw($prefs_caller);
use vars qw($escapedmessageid $escapedfolder);
use vars qw($urlparmstr $formparmstr);

########## MAIN ##################################################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop

userenv_init();

if (!$config{'enable_webmail'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$folder = ow::tool::unescapeURL(param('folder')) || 'INBOX';
$page = param('page') || 1;
$sort = param('sort') || $prefs{'sort'} || 'date_rev';
$messageid=param('message_id') || '';
$prefs_caller = param('prefs_caller')||'';

$escapedfolder=ow::tool::escapeURL($folder);
$escapedmessageid=ow::tool::escapeURL($messageid);

$urlparmstr=qq|sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;sort=$sort&amp;page=$page&amp;prefs_caller=$prefs_caller|;
$formparmstr=ow::tool::hiddens(sessionid=>$thissession,
                               folder=>$escapedfolder,
                               message_id=>$messageid,
                               sort=>$sort,
                               page=>$page,
                               prefs_caller=>$prefs_caller);

my $action = param('action')||'';
writelog("debug - request saprefs begin, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ($action eq "edittest") {
   edittest();
} elsif ($action eq "addtest") {
   modtest("add");
} elsif ($action eq "deletetest") {
   modtest("delete");

} elsif ($action eq "editwhitelist") {
   editlist("whitelist");
} elsif ($action eq "addwhitelist") {
   modlist("add", "whitelist");
} elsif ($action eq "deletewhitelist") {
   modlist("delete", "whitelist");

} elsif ($action eq "editblacklist") {
   editlist("blacklist");
} elsif ($action eq "addblacklist") {
   modlist("add", "blacklist");
} elsif ($action eq "deleteblacklist") {
   modlist("delete", "blacklist");

} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request saprefs end, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## EDITADDRESSES #########################################
sub edittest {
   my ($html, $temphtml);
   $html = applystyle(readtemplate("sa_edittest.template"));

   if ( param('prefs_caller') ) {
      my $prefs_caller=param('prefs_caller');
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}",
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   } else {
      my $folderstr=$lang_folders{$folder}||f2u($folder);
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $folderstr",
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;$urlparmstr"|);
   }

   $temphtml .= "&nbsp;\n";

   $temphtml .= iconlink("satest.gif", $lang_text{'sa_edittest'}, qq|href="$config{'ow_cgiurl'}/openwebmail-saprefs.pl?action=edittest&amp;$urlparmstr"|).
                iconlink("sawhitelist.gif", $lang_text{'sa_editwhitelist'}, qq|href="$config{'ow_cgiurl'}/openwebmail-saprefs.pl?action=editwhitelist&amp;$urlparmstr"|).
                iconlink("sablacklist.gif", $lang_text{'sa_editblacklist'}, qq|href="$config{'ow_cgiurl'}/openwebmail-saprefs.pl?action=editblacklist&amp;$urlparmstr"|);

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-saprefs.pl",
                          -name=> 'addtest').
               ow::tool::hiddens(action=>'addtest').
               $formparmstr;
   $html =~ s/\@\@\@STARTADDTESTFORM\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'testname',
                         -size=>'45',
                         -override=>'1');
   $html =~ s/\@\@\@TESTNAMEFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'testdesc',
                         -size=>'60',
                         -override=>'1');
   $html =~ s/\@\@\@TESTDESCFIELD\@\@\@/$temphtml/g;


   $temphtml = popup_menu(-name=>'testtype',
                          -values=>['header', 'body', 'uri', 'rawbody', 'full'],
                          -labels=>\%lang_satesttypes,
                          -default=>'header',
                          -onchange=>'sethheaderdivvisibility();',
                          -override=>'1')."&nbsp;";
   $html =~ s/\@\@\@TESTTYPEMENU\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'testheaderattr',
                         -size=>'15',
                         -override=>'1');
   $html =~ s/\@\@\@HEADERATTRFIELD\@\@\@/$temphtml/g;

   $temphtml = popup_menu(-name=>'testheaderattr_sel',
                          -values=>['ALL', 'Subject', 'From', 'To', 'Cc', 'ToCc', 'MESSAGEID', 'USERDEFINE'],
                          -labels=>\%lang_satestheaderattrs,
                          -default=>'USERDEFINE',
                          -onchange=>'setheaderattrfield();',
                          -override=>'1');
   $html =~ s/\@\@\@HEADERATTRMENU\@\@\@/$temphtml/g;


   $temphtml = popup_menu(-name=>'testop',
                          -values=>['=~', '!~'],
                          -labels=>{ '=~' => $lang_text{'include'}, '!~' => $lang_text{'exclude'} },
                          -default=>'=~',
                          -override=>'1');
   $html =~ s/\@\@\@OPMENU\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'pattern',
                         -size=>'45',
                         -override=>'1');
   $html =~ s/\@\@\@PATTERNFIELD\@\@\@/$temphtml/g;

   $temphtml = checkbox(-name=>'ignorecase',
                        -value=>'1',
                        -label=>'');
   $html =~ s/\@\@\@IGNORECASECHECKBOX\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'singleline',
                        -value=>'1',
                        -label=>'');
   $html =~ s/\@\@\@SINGLELINECHECKBOX\@\@\@/$temphtml/;

   my @scores;
   my @a;
   for (my $i=0.1; $i<1;  $i+=0.1) { push(@a,$i) };
   for (my $i=1.5; $i<11; $i+=0.5) { push(@a,$i) };
   push (@a, 11..20, 30,40,50,100,200);
   for (@a) { push(@scores, $_, $_*-1) }; push(@scores, 0);
   @scores=sort {$b <=> $a} @scores;
   $temphtml = popup_menu(-name=>'score',
                          -values=>\@scores,
                          -default=>0,
                          -override=>'1');
   $html =~ s/\@\@\@SCOREMENU\@\@\@/$temphtml/g;

   $temphtml = submit(-name=>$lang_text{'addmod'},
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/g;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;


   my $saprefsfile="$homedir/.spamassassin/user_prefs";
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from)=read_saprefs($saprefsfile);

   my @testnames= sort (keys %{$r_rules});

   $temphtml = '';
   my $i=0;
   foreach my $testname (@testnames) {
      # modification on these records are not supported

      my %test=%{${$r_rules}{$testname}};

      next if ($test{type} eq 'meta' ||
               defined $test{ifunset} ||
               defined $test{tflags});

      my (%esc, %js);
      foreach (qw(desc headerattr pattern)) {
         $esc{$_}=ow::htmltext::str2html($test{$_});
         $js{$_}=$test{$_};
         $js{$_}=~s/\\/\\\\/g; $js{$_}=~s/'/\\'/g;
      }
      my $ignorecase=0; $ignorecase=1 if ($test{modifier}=~/i/);
      my $singleline=0; $singleline=1 if ($test{modifier}=~/s/);
      my $score;
      if (defined ${$test{score}}[0]) {
         $score=${$test{score}}[0];
      } else {
         $score=1;				# default 1 for no score test
         $score=0.01 if ($testname=~/^T_/);	# default 0.01 if test is for testing only
      }
      my $testhtml=qq|<table width="100%" cellspacing="0" cellpadding="0">\n|.
                   qq|<tr><td width="15%">$lang_satestfields{'name'}&nbsp;</td><td>$testname</td></tr>\n|.
                   qq|<tr><td>$lang_satestfields{'desc'}&nbsp;</td><td>$esc{desc}</td></tr>\n|.
                   qq|<tr><td>$lang_satestfields{'type'}&nbsp;</td><td>$test{type} $esc{headerattr} $test{op}</td></tr>\n|.
                   qq|<tr><td>$lang_satestfields{'expression'}&nbsp;</td>|.
                   qq|<td>/$esc{pattern}/$test{modifier}</td></tr>\n|.
                   qq|<tr><td>$lang_satestfields{'score'}&nbsp;</td><td>$score</td></tr>\n|.
                   qq|</table>\n|;


      my ($tr_bgcolorstr, $td_bgcolorstr);
      if ($prefs{'uselightbar'}) {
         $tr_bgcolorstr=qq|bgcolor=$style{tablerow_light} |.
                        qq|onMouseOver='this.style.backgroundColor=$style{tablerow_hicolor};' |.
                        qq|onMouseOut='this.style.backgroundColor=$style{tablerow_light};' |;
         $td_bgcolorstr='';
      } else {
         $tr_bgcolorstr='';
         $td_bgcolorstr=qq|bgcolor=|.($style{"tablerow_dark"},$style{"tablerow_light"})[$i%2];
      }
      $tr_bgcolorstr.=qq|onClick="update('$testname', '$js{desc}', '$test{type}', '$js{headerattr}', '$test{op}', '$js{pattern}', $ignorecase, $singleline, $score)" |;

      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-saprefs.pl").
                   ow::tool::hiddens(action=>'deletetest',
                                     testname=>$testname).
                   $formparmstr;
      $temphtml.=qq|<tr $tr_bgcolorstr><td bgcolor=$style{'columnheader'} align="center">|.($i+1).qq|</td><td $td_bgcolorstr>$testhtml</td>|.
                 qq|<td align="center" $td_bgcolorstr>|.
                 submit(-name=>$lang_text{'delete'},
                        -class=>"medtext").
                 qq|</td></tr>|.
                 end_form().qq|\n|;
      $i++;
   }

   $html =~ s/\@\@\@TESTS\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITADDRESSES #####################################

########## MODTEST ############################################
sub modtest {
   my $mode = shift;
   my $testname = param('testname')||''; $testname=~s/^\s*//; $testname=~s/\s*$//;
   return edittest() if ($testname eq '');

   my %test;
   my $saprefsfile="$homedir/.spamassassin/user_prefs";
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from)=read_saprefs($saprefsfile);

   if ($mode eq 'add') {
      $test{type}=param('testtype'); $test{type}=~s/^\s*//; $test{type}=~s/\s*$//;
      $test{pattern}=param('pattern'); $test{pattern}=~s/^\s*//; $test{pattern}=~s/\s*$//;

      # remove / / outside th pattern
      $test{pattern}=~s!^/(.*)/$!$1!;
      # ensure all / are properly escaped
      $test{pattern}=~s!\\/!/!g; $test{pattern}=~s!/!\\/!g;

      if ($test{type} ne '' && $test{pattern} ne '' && ow::tool::is_regex($test{pattern})) {
         $test{desc}=param('testdesc') if (param('testdesc') ne '');
         if ($test{type} eq 'header') {
            $test{headerattr}=param('testheaderattr')||'ALL';
            $test{op}=param('testop')||'=~';
         }
         $test{modifier}='';
         $test{modifier}.='i' if (param('ignorecase')==1);
         $test{modifier}.='s' if (param('singleline')==1);
         $test{score}=[ sprintf("%4.2f", param('score')) ];

         ${$r_rules}{$testname}=\%test;
         write_saprefs($saprefsfile, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   } elsif ($mode eq 'delete') {
      if (defined ${$r_rules}{$testname}) {
         delete ${$r_rules}{$testname};
         write_saprefs($saprefsfile, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   }

   return edittest();
}
########## END MODTEST ########################################

########## EDITWHITELIST #########################################
sub editlist {
   my ($listtype)=@_;

   return edittest() if ($listtype ne 'whitelist' && $listtype ne 'blacklist');

   my ($html, $temphtml);
   $html = applystyle(readtemplate("sa_edit".$listtype.".template"));

   if ( param('prefs_caller') ) {
      my $prefs_caller=param('prefs_caller');
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'userprefs'}",
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparmstr"|);
   } else {
      my $folderstr=$lang_folders{$folder}||f2u($folder);
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $folderstr",
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;$urlparmstr"|);
   }

   $temphtml .= "&nbsp;\n";

   $temphtml .= iconlink("satest.gif", $lang_text{'sa_edittest'}, qq|href="$config{'ow_cgiurl'}/openwebmail-saprefs.pl?action=edittest&amp;$urlparmstr"|).
                iconlink("sawhitelist.gif", $lang_text{'sa_editwhitelist'}, qq|href="$config{'ow_cgiurl'}/openwebmail-saprefs.pl?action=editwhitelist&amp;$urlparmstr"|).
                iconlink("sablacklist.gif", $lang_text{'sa_editblacklist'}, qq|href="$config{'ow_cgiurl'}/openwebmail-saprefs.pl?action=editblacklist&amp;$urlparmstr"|);

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-saprefs.pl",
                          -name=> 'addlist').
               ow::tool::hiddens(action=>'add'.$listtype).
               $formparmstr;
   $html =~ s/\@\@\@STARTADDLISTFORM\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'email',
                         -default=>'',
                         -size=>'60',
                         -override=>'1');
   $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name=>$lang_text{'add'},
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   my $saprefsfile="$homedir/.spamassassin/user_prefs";
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from)=read_saprefs($saprefsfile);

   my @list;
   if ($listtype eq 'whitelist') {
      @list=sort (keys %{$r_whitelist_from});
   } else {
      @list=sort (keys %{$r_blacklist_from});
   }

   $temphtml = '';
   my $i=0;
   foreach my $email (@list) {
      next if ($email=~/[^\d\w_\@\%\*\!\&\.#]/);

      my ($tr_bgcolorstr, $td_bgcolorstr);

      if ($prefs{'uselightbar'}) {
         $tr_bgcolorstr=qq|bgcolor=$style{tablerow_light} |.
                        qq|onMouseOver='this.style.backgroundColor=$style{tablerow_hicolor};' |.
                        qq|onMouseOut='this.style.backgroundColor=$style{tablerow_light};' |;
         $td_bgcolorstr='';
      } else {
         $tr_bgcolorstr='';
         $td_bgcolorstr=qq|bgcolor=|.($style{"tablerow_dark"},$style{"tablerow_light"})[$i%2];
      }
      $tr_bgcolorstr.=qq|onClick="document.addlist.email.value='$email';" |;

      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-saprefs.pl").
                   ow::tool::hiddens(action=>'delete'.$listtype,
                                     email=>$email).
                   $formparmstr;
      $temphtml.=qq|<tr $tr_bgcolorstr><td $td_bgcolorstr>&nbsp;$email</td>|.
                 qq|<td align="center" $td_bgcolorstr>|.
                 submit(-name=>$lang_text{'delete'},
                        -class=>"medtext").
                 qq|</td></tr>|.
                 end_form();
      $i++;
   }
   $html =~ s/\@\@\@EMAILS\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITLIST #####################################

########## MODWHITELIST ##########################################
sub modlist {
   my ($mode, $listtype) = @_;
   return edittest() if ($listtype ne 'whitelist' && $listtype ne 'blacklist');

   my $email = param('email') || ''; $email=~s/^\s*//; $email=~s/\s*$//;
   return editlist($listtype) if ($email eq '' || $email=~/[^\d\w_\@\%\*\!\&\.#]/);

   my $saprefsfile="$homedir/.spamassassin/user_prefs";
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from)=read_saprefs($saprefsfile);

   my $r_list;
   if ($listtype eq 'whitelist') {
      $r_list=$r_whitelist_from;
   } else {
      $r_list=$r_blacklist_from;
   }

   if ($mode eq 'add') {
      if (!defined  ${$r_list}{$email}) {
         ${$r_list}{$email}=1;
         write_saprefs($saprefsfile, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   } elsif ($mode eq 'delete') {
      if (defined  ${$r_list}{$email}) {
         delete ${$r_list}{$email};
         write_saprefs($saprefsfile, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   }

   return editlist($listtype);
}
########## END MODWHITELIST #####################################

########## READ/WRITE_SA_PREFS ##################################
sub read_saprefs {
   my ($file)=@_;
   my (@lines, @datas, %rules, %whitelist_from, %blacklist_from);

   ow::filelock::lock($file, LOCK_SH);
   if (!sysopen(F, $file, O_RDONLY)) {
      ow::filelock::lock($file, LOCK_UN);
      return(\@datas, \%rules, \%whitelist_from, \%blacklist_from);
   }
   while(<F>) {
      s/\s*$//;
      push(@lines, $_);
   }
   close(F);

   for (my $i=0; $i<=$#lines; $i++) {
      my $line=$lines[$i];

      # ruleset related lines
      if ($line=~/^(score|describe|tflags|header|uri|body|full|rawbody|meta)\s/) {
         while (defined $lines[$i+1] && $lines[$i+1]=~/^ /) {
            $i++; $line.=$lines[$i]; $line=~s/\s*$//;
         }

         my ($key, $testname, $value);
         ($key, $testname, $value)=split(/\s+/, $line, 3);

         if ($key eq 'score') {
            $rules{$testname}{score}=[split(/\s+/, $value)];

         } elsif ($key eq 'describe') {
            $rules{$testname}{desc}=$value;

         } elsif ($key eq 'tflags') {
            $rules{$testname}{tflags}=[split(/\s+/, $value)];

         } elsif ($key=~/^(header|uri|body|full|rawbody|meta)$/) {
            $rules{$testname}{type}=$key;

            if ($key eq 'meta') {
               $rules{$testname}{expression}=$value;
            } else {
               my ($headerattr, $op, $pattern);
               if ($key eq 'header') {
                  ($headerattr, $op, $pattern)=split(/\s+/, $value, 3);
                  $rules{$testname}{headerattr}=$headerattr;
                  $rules{$testname}{op}=$op;
               } else {
                  $pattern=$value;
               }
               $rules{$testname}{ifunset}=$1 if ($pattern=~s/\s*\[\s*if-unset:\s(.*)\]$//);
               $rules{$testname}{modifier}=$1 if ($pattern=~s!/([oigms]+)$!/!);
               $pattern=~s!^\s*/!!; $pattern=~s!/\s*$!!;
               $rules{$testname}{pattern}=$pattern;
            }
         }
      } elsif ($line=~/^whitelist_from\s/) {
         my @list=split(/\s+/, $line); shift @list;
         foreach (@list) { $whitelist_from{$_}=1 }

      } elsif ($line=~/^blacklist_from\s/) {
         my @list=split(/\s+/, $line); shift @list;
         foreach (@list) { $blacklist_from{$_}=1 }

      } else {
         push(@datas, $line);
      }
   }

   close(F);
   ow::filelock::lock($file, LOCK_UN);

   return(\@datas, \%rules, \%whitelist_from, \%blacklist_from);
}

sub write_saprefs {
   my ($file, $r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from)=@_;

   my @p=split(/\//, $file); pop @p;
   my $dir=join('/', @p);
   mkdir ($dir, 0700) if (!-d $dir);

   ow::filelock::lock($file, LOCK_EX|LOCK_NB);
   if (!sysopen(F, $file, O_WRONLY|O_TRUNC|O_CREAT)) {
      ow::filelock::lock($file, LOCK_UN);
      return -1;
   }

   my $data=join("\n", @{$r_datas});
   $data=~s/\n\n+/\n\n/g;
   print F $data;

   my $s;
   my @list=sort (keys %{$r_whitelist_from});
   foreach my $email (@list) {
      if (length($s)+length($email)>60) {
         print F "whitelist_from $s\n";
         $s='';
      }
      $s.=" " if ($s ne '');
      $s.=$email;
   }
   print F "whitelist_from $s\n" if ($s ne '');
   print F "\n";

   $s='';
   @list=sort (keys %{$r_blacklist_from});
   foreach my $email (@list) {
      if (length($s)+length($email)>60) {
         print F "blacklist_from $s\n";
         $s='';
      }
      $s.=" " if ($s ne '');
      $s.=$email;
   }
   print F "blacklist_from $s\n" if ($s ne '');
   print F "\n";

   my @testnames=sort { $a cmp $b } keys %{$r_rules};
   foreach my $testname (@testnames) {
      my %test=%{${$r_rules}{$testname}};
      if (defined $test{type}) {
         if ($test{type} eq 'meta') {
            print "meta $testname\t\t$test{expression}\n";
         } else {
            my $pattern='/'.$test{pattern}.'/';
            $pattern.=$test{modifier} if (defined $test{modifier});
            $pattern.=" [if-unset: $test{ifunset}]" if (defined $test{ifunset});
            if ($test{type} eq 'header') {
               print F "header\t\t$testname\t\t$test{headerattr} $test{op} $pattern\n";
            } else {
               print F "$test{type}\t\t$testname\t\t$pattern\n";
            }
         }
      }

      if (defined $test{score}) {
         print F "score\t\t$testname\t\t".join(' ', @{$test{score}})."\n";
      }
      if (defined $test{tflags}) {
         print F "tflags\t\t$testname\t\t".join(' ', @{$test{tflags}})."\n";
      }
      if (defined $test{desc}) {
         print F "describe\t$testname\t\t$test{desc}\n";
      }
      print F "\n";
   }

   close(F);
   ow::filelock::lock($file, LOCK_UN);

   return 0;
}
########## END READ/WRITE_SA_PREFS ##############################
