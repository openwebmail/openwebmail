#!/usr/bin/suidperl -T
#
# openwebmail-cal.pl - calendar program
#
# 2003/03/29 jpd@louisiana.edu
#            easter day support
# 2003/02/17 ateslik.AT.users.sourceforge.net
#            rewrite the dayview display
# 2002/07/05 tung@turtle.ee.ncku.edu.tw
#            modified from WebCal version 1.12.
#
# WebCal is available at http://bulldog.tzo.org/webcal/webcal.html/
# and is copyrighted by 2002, Michael Arndt
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
use Time::Local;
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "ow-shared.pl";
require "filelock.pl";
require "lunar.pl";
require "iconv-chinese.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

# extern vars
use vars qw(%lang_folders %lang_text %lang_err);	# defined in lang/xy
use vars qw(%lang_calendar %lang_month %lang_wday_abbrev %lang_wday %lang_order); # defined in lang/xy
use vars qw(@wdaystr);	# defined in ow-shared.pl

# local globals
use vars qw($messageid $escapedmessageid);
use vars qw($miscbuttonsstr);
use vars qw(@slottime);

########################## MAIN ##############################
clearvars();
openwebmail_init();

$messageid = param("message_id");
$escapedmessageid = escapeURL($messageid);

# init global @slottime
@slottime=();
for my $h (0..23) {
   for (my $m=0; $m<60 ; $m=$m+$prefs{'calendar_interval'}) {
      push(@slottime, sprintf("%02d%02d", $h, $m));
   }
}
push(@slottime, "2400");

if ($messageid eq "") {
   $miscbuttonsstr = iconlink("owm.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="M" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
} else {
   $miscbuttonsstr = iconlink("owm.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="M" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
}
if ($config{'enable_webdisk'}) {
   $miscbuttonsstr .= iconlink("webdisk.gif", $lang_text{'webdisk'}, qq|accesskey="E" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=showdir&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
}
if ( $config{'enable_sshterm'} && -r "$config{'ow_htmldir'}/applet/mindterm/mindtermfull.jar" ) {
   $miscbuttonsstr .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ", qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm/ssh.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
}
$miscbuttonsstr .= iconlink("prefs.gif", $lang_text{'userprefs'}, qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;prefs_caller=cal"|);
$miscbuttonsstr .= iconlink("logout.gif", "$lang_text{'logout'} $prefs{'email'}", qq|accesskey="X" href="$config{'ow_cgiurl'}/openwebmail-main.pl?sessionid=$thissession&amp;action=logout"|);

my $action = param("action");
# event background colors
my %eventcolors=( '1a'=>'b0b0e0', '1b'=>'b0e0b0', '1c'=>'b0e0e0',
                  '1d'=>'e0b0b0', '1e'=>'e0b0e0', '1f'=>'e0e0b0',
                  '2a'=>'9090f8', '2b'=>'90f890', '2c'=>'90f8f8',
                  '2d'=>'f89090', '2e'=>'f890f8', '2f'=>'f8f890');

my $year=param('year')||'';
my $month=param('month')||'';
my $day=param('day')||'';
if (defined(param('daybutton'))) {
   $day=param('daybutton'); $day=~s/\s//g;
}

my $index=param('index')||'';
my $string=param('string')||'';
my $starthour=param('starthour')||0;
my $startmin=param('startmin')||0;
my $startampm=param('startampm')||'am';
my $endhour=param('endhour')||0;
my $endmin=param('endmin')||0;
my $endampm=param('endampm')||'am';
my $link=param('link')||'';
my $email=param('email')||'';
my $eventcolor=param('eventcolor')||'none';
my $dayfreq=param('dayfreq')||'thisdayonly';
my $thisandnextndays=param('thisandnextndays')||0;
my $ndays=param('ndays')||0;
my $monthfreq=param('monthfreq')||0;
my $everyyear=param('everyyear')||0;

if (!$config{'enable_calendar'}) {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

if ($action eq "calyear") {
   yearview($year);
} elsif ($action eq "calmonth") {
   monthview($year, $month);
} elsif ($action eq "calweek") {
   weekview($year, $month, $day);
} elsif ($action eq "calday") {
   dayview($year, $month, $day);
} elsif ($action eq "callist") {
   listview($year);
} elsif ($action eq "caledit") {
   edit_item($year, $month, $day, $index);
} elsif ($action eq "caladd") {
   add_item($year, $month, $day,
            $string,
            $starthour, $startmin, $startampm,
            $endhour, $endmin, $endampm,
            $dayfreq,
            $thisandnextndays, $ndays, $monthfreq, $everyyear,
            $link, $email, $eventcolor);
   dayview($year, $month, $day);
} elsif ($action eq "caldel") {
   del_item($index);
   if (defined(param('callist'))) {
      listview($year);
   } else {
      dayview($year, $month, $day);
   }
} elsif ($action eq "calupdate") {
   update_item($index, $string,
               $starthour, $startmin, $startampm,
               $endhour, $endmin, $endampm,
               $link, $email, $eventcolor);
   if (defined(param('callist'))) {
      listview($year);
   } else {
      dayview($year, $month, $day);
   }
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

# back to root if possible, required for setuid under persistent perl
$<=0; $>=0;
########################## END MAIN ##########################

########################## YEARVIEW ##########################
sub yearview {
   my $year=$_[0];
   my $g2l=time();
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$prefs{'timeoffset'})) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime
   }
   $g2l+=timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($current_year, $current_month, $current_day)=(gmtime($g2l))[5,4,3];
   $current_year+=1900; $current_month++;

   my $day;
   $year = $current_year if (!$year);
   $year=2037 if ($year>2037);
   $year=1970 if ($year<1970);

   my ($html, $temphtml);
   $html = readtemplate("yearview.template");
   $html = applystyle($html);

   $temphtml = startform(-name=>"yearform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl") .
               hidden(-name=>'action',
                      -default=>'calyear',
                      -override=>'1').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1').
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1');
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'year',
                         -default=>$year,
                         -size=>'4',
                         -accesskey=>'G',
                         -override=>'1');
   $html =~ s/\@\@\@YEARFIELD\@\@\@/$lang_text{'calfmt_year'}/g;
   $html =~ s/\@\@\@YEAR\@\@\@/ $temphtml /;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = formatted_date($year);
   $html =~ s/\@\@\@CALTITLE\@\@\@/$temphtml/g;

   my $cal_url=qq|$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;|;

   $temphtml  = iconlink("yearview.gif" ,"$lang_calendar{'yearview'} ".formatted_date($year), qq|accesskey="Y" href="|.$cal_url.qq|action=calyear&year=$year"|);
   $temphtml .= iconlink("monthview.gif", "$lang_calendar{'monthview'} ".formatted_date($year, $current_month), qq|accesskey="M" href="|.$cal_url.qq|action=calmonth&year=$year&month=$current_month"|);
   $temphtml .= iconlink("weekview.gif", "$lang_calendar{'weekview'} ".formatted_date($year, $current_month, $current_day), qq|accesskey="W" href="|.$cal_url.qq|action=calweek&year=$year&month=$current_month&day=$current_day"|);
   $temphtml .= iconlink("dayview.gif", "$lang_calendar{'dayview'} ".formatted_date($year, $current_month, $current_day), qq|accesskey="T" href="|.$cal_url.qq|action=calday&year=$year&month=$current_month&day=$current_day"|);
   $temphtml .= iconlink("listview.gif", "$lang_calendar{'listview'} ".formatted_date($year), qq|accesskey="L" href="|.$cal_url.qq|action=callist&year=$year"|);
   if ($year != $current_year) {
      $temphtml .= iconlink("refresh.gif", "$lang_text{'backto'} ".formatted_date($current_year), qq|accesskey="R" href="|.$cal_url.qq|action=calyear&year=$current_year"|);
   }
   $temphtml .= "&nbsp;\n$miscbuttonsstr";
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my $prev_year = $year - 1;
   my $gif="left.gif"; $gif="right.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, formatted_date($prev_year), qq|accesskey="U" href="|.$cal_url.qq|action=calyear&year=$prev_year"|). qq| \n|;
   $html =~ s/\@\@\@PREV_LINK\@\@\@/$temphtml/g;

   my $next_year = $year + 1;
   $gif="right.gif"; $gif="left.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, formatted_date($next_year), qq|accesskey="D" href="|.$cal_url.qq|action=calyear&year=$next_year"|). qq| \n|;
   $html =~ s/\@\@\@NEXT_LINK\@\@\@/$temphtml/g;

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      readcalbook("$config{'ow_holidaysdir'}/$prefs{'language'}", \%items, \%indexes, 1E6);
   }

   my ($easter_month, $easter_day) = gregorian_easter($year); # compute once
   my $week=1;
   for my $month (1..12) {
      my @days = set_days_in_month($year, $month);
      my $bgcolor;

      if ($month==$current_month && $year == $current_year) {
         $bgcolor=qq|bgcolor=$style{'tablerow_light'}|;
      } else {
         $bgcolor=qq|bgcolor=$style{'tablerow_dark'}|;
      }

      $temphtml  = qq|<td valign=top align=center $bgcolor>\n|;

      my @accesskey=qw(0 1 2 3 4 5 6 7 8 9 0 J Q);
      $temphtml .= qq|<table border="0" width="100%"><tr><td align="center">|.
                   qq|<a accesskey="$accesskey[$month]" href="|.$cal_url.qq|action=calmonth&year=$year&month=$month">|.
                   qq|<B>$lang_month{$month}</B></a>|.
                   qq|</td></tr></table>\n|;

      $temphtml .= qq|<table border="0" cellpadding="1" cellspacing="0" width="100%">\n|;
      $temphtml .= qq|<tr align=center><td>$lang_wday_abbrev{'week'}</td>|;
      for (my $i=0; $i<7; $i++) {
         $temphtml.=qq|<td align=center>|.
                    $lang_wday_abbrev{($prefs{'calendar_weekstart'}+$i)%7}.
                    qq|</td>|;
      }
      $temphtml .= qq|</tr>\n|;

      for my $x (0..5) {
         $temphtml .= qq|<tr align=center>|;
         if (($days[$x][0]) || ($days[$x][6])) {
            if ($days[$x][0]) {
               $day = $days[$x][0];
            } else {
               $day = $days[$x][6];
            }
            $temphtml .= qq|<td><a href="|.$cal_url.qq|action=calweek&year=$year&month=$month&day=$day">|.
                         qq|<font color=#c00000>$week</font></a></td>\n|;
         }
         for my $y (0..6) {
            if ($days[$x][$y]) {
               $day = $days[$x][$y];

               my $wdaynum=($prefs{'calendar_weekstart'}+$y)%7;
               my $dow=$wdaystr[$wdaynum%7];
               my $date=sprintf("%04d%02d%02d", $year,$month,$day);
               my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

               my @indexlist=();
               foreach ($date, '*') {
                  next if (!defined($indexes{$_}));
                  foreach my $index (@{$indexes{$_}}) {
                     if ($date =~/$items{$index}{'idate'}/ ||
                         $date2=~/$items{$index}{'idate'}/ ||
                         easter_match($year,$month,$day, $easter_month,$easter_day,
                                      $items{$index}{'idate'}) ) {
                        push(@indexlist, $index);
                     }
                  }
               }
               @indexlist=sort { $items{$a}{'starthourmin'}<=>$items{$b}{'starthourmin'} || 
                                 $items{$a}{'endhourmin'}<=>$items{$b}{'endhourmin'} || 
                                 $b<=>$a } @indexlist;

               my $eventstr="";
               for my $index (@indexlist) {
                  $eventstr.="$items{$index}{'string'} ";
               }
               if ($eventstr) {
                  if ($eventstr!~/"/) {
                     $eventstr=qq|title="$eventstr"|;
                  } else {
                     $eventstr=qq|title='$eventstr'|;
                  }
               }
               if ($day==$current_day && $month==$current_month && $year==$current_year) {
                  $bgcolor=qq|bgcolor=$style{'columnheader'}|;
               } else {
                  $bgcolor="";
               }

               $temphtml .= qq|<td $bgcolor><a href="|.$cal_url.qq|action=calday&year=$year&month=$month&day=$day" $eventstr>|;
               if ($eventstr) {
                  $temphtml .= qq|<b>$days[$x][$y]</b>|;
               } else {
                  $temphtml .= qq|$days[$x][$y]|;
               }
               $temphtml .= qq|</a></td>\n|;

               $week++ if ($y==6 && $week<53);
            } else {
               $temphtml .= qq|<td>&nbsp;</td>|;
            }
         }
         $temphtml .= qq|</tr>\n|;
      }
      $temphtml .= qq|</table></td>\n|;
      $html =~ s/\@\@\@MONTH$month\@\@\@/$temphtml/;
   }

   print htmlheader(), 
         htmlplugin($config{'header_pluginfile'}), 
         $html, 
         htmlplugin($config{'footer_pluginfile'}), 
         htmlfooter(2);
}
######################## END YEARVIEW ########################

########################## MONTHVIEW ##########################
sub monthview {
   my ($year, $month)=@_;
   my $g2l=time();
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$prefs{'timeoffset'})) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime                         
   }
   $g2l+=timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($current_year, $current_month, $current_day)=(gmtime($g2l))[5,4,3];
   $current_year+=1900; $current_month++;

   $year = $current_year if (!$year);
   $month = $current_month if (!$month);
   $year=2037 if ($year>2037);
   $year=1970 if ($year<1970);

   my ($html, $temphtml);
   $html = readtemplate("monthview.template");
   $html = applystyle($html);

   $temphtml = startform(-name=>"yearform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl") .
               hidden(-name=>'action',
                      -default=>'calmonth',
                      -override=>'1').
               hidden(-name=>'month',
                      -default=>$month,
                      -override=>'1').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1').
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1');
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'year',
                         -default=>$year,
                         -size=>'4',
                         -accesskey=>'G',
                         -override=>'1');
   $html =~ s/\@\@\@YEARFIELD\@\@\@/$lang_text{'calfmt_year'}/g;
   $html =~ s/\@\@\@YEAR\@\@\@/ $temphtml /;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = formatted_date($year, $month);
   $html =~ s/\@\@\@CALTITLE\@\@\@/$temphtml/g;

   my $cal_url=qq|$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;|;

   $temphtml  = iconlink("yearview.gif", "$lang_calendar{'yearview'} ".formatted_date($year), qq|accesskey="Y" href="|.$cal_url.qq|action=calyear&year=$year"|);
   $temphtml .= iconlink("monthview.gif", "$lang_calendar{'monthview'} ".formatted_date($year,$month), qq|accesskey="M" href="|.$cal_url.qq|action=calmonth&year=$year&month=$month"|);
   $temphtml .= iconlink("weekview.gif", "$lang_calendar{'weekview'} ".formatted_date($year,$month,$current_day), qq|accesskey="W" href="|.$cal_url.qq|action=calweek&year=$year&month=$month&day=$current_day"|);
   $temphtml .= iconlink("dayview.gif", "$lang_calendar{'dayview'} ".formatted_date($year,$month,$current_day), qq|accesskey="T" href="|.$cal_url.qq|action=calday&year=$year&month=$month&day=$current_day"|);
   $temphtml .= iconlink("listview.gif", "$lang_calendar{'listview'} ".formatted_date($year), qq|accesskey="L" href="|.$cal_url.qq|action=callist&year=$year"|);
   if ($year!=$current_year || $month!=$current_month) {
      $temphtml .= iconlink("refresh.gif", "$lang_text{'backto'} ".formatted_date($current_year,$current_month), qq|accesskey="R" href="|.$cal_url.qq|action=calmonth&year=$current_year&month=$current_month"|);
   }
   $temphtml .= "&nbsp;\n$miscbuttonsstr";
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my ($prev_year, $prev_month)= ($year, $month-1);
   if ($month == 1) {
      ($prev_year, $prev_month) = ($year-1, 12);
   }
   my $gif="left.gif"; $gif="right.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, formatted_date($prev_year,$prev_month), qq|accesskey="U" href="|.$cal_url.qq|action=calmonth&year=$prev_year&month=$prev_month"|). qq| \n|;
   $html =~ s/\@\@\@PREV_LINK\@\@\@/$temphtml/g;

   my ($next_year, $next_month)= ($year, $month+1);
   if ($month == 12) {
      ($next_year, $next_month) = ($year+1, 1);
   }
   $gif="right.gif"; $gif="left.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, formatted_date($next_year,$next_month), qq|accesskey="D" href="|.$cal_url.qq|action=calmonth&year=$next_year&month=$next_month"|). qq| \n|;
   $html =~ s/\@\@\@NEXT_LINK\@\@\@/$temphtml/g;

   for (my $i=0; $i<7; $i++) {
      my $n=($prefs{'calendar_weekstart'}+$i)%7;
      if ($n==0) {	# sunday
         $html =~ s!\@\@\@WEEKDAY$i\@\@\@!<font color=#cc0000>$lang_wday{$n}</font>!;
      } elsif ($n==6) {	# saturday
         $html =~ s!\@\@\@WEEKDAY$i\@\@\@!<font color=#00aa00>$lang_wday{$n}</font>!;
      } else {
         $html =~ s!\@\@\@WEEKDAY$i\@\@\@!$lang_wday{$n}!;
      }
   }

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      readcalbook("$config{'ow_holidaysdir'}/$prefs{'language'}", \%items, \%indexes, 1E6);
   }

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl");
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -value=>$folder,
                       -override=>'1');
   $temphtml .= hidden(-name=>'message_id',
                       -default=>$messageid,
                       -override=>'1');
   $temphtml .= hidden(-name=>'action',
                       -value=>'calday',
                       -override=>'1');
   $temphtml .= hidden(-name=>'year',
                       -value=>$year,
                       -override=>'1');
   $temphtml .= hidden(-name=>'month',
                       -value=>$month,
                       -override=>'1');
   $html =~ s/\@\@\@STARTDAYFORM\@\@\@/$temphtml/;

   my ($easter_month, $easter_day) = gregorian_easter($year); # compute once
   my @days = set_days_in_month($year, $month);
   for my $x ( 0..5 ) {
      for my $y ( 0..6 ) {
         my $bgcolor;
         my $day = $days[$x][$y];
         if ($year==$current_year &&
             $month==$current_month &&
             $day==$current_day) {
            $bgcolor="bgcolor=$style{'tablerow_light'}";
         } elsif ($days[$x][$y]) {
            $bgcolor="bgcolor=$style{'tablerow_dark'}";
         } else {	# else cell is not unused
            $bgcolor="";
         }

         $temphtml = qq|<td valign=top $bgcolor>|.
                     qq|<table width="100%" cellpadding="0" cellspacing="0">\n|;

         if ($days[$x][$y] =~ /\d+/) {
            my $t=timegm 1,1,1,$day,($month-1),($year-1900);
            my $dow=$wdaystr[(gmtime($t))[6]];
            my $date=sprintf("%04d%02d%02d", $year, $month, $day);
            my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);
            my $i=0;

            $temphtml .= qq|<tr><td align="right">|;
            if ($prefs{'charset'} eq "big5" || $prefs{'charset'} eq "gb2312") {
               $temphtml.=lunar_str($year, $month, $day, $prefs{'charset'});
            }
            my $daystr=$days[$x][$y]; $daystr=" ".$daystr if (length($daystr)<2);
            $temphtml .= submit(-name=>'daybutton',
                                -value=>$daystr,
                                -override=>'1').
                         qq|</td></tr>|;

            my @indexlist=();
            foreach ($date, '*') {
               next if (!defined($indexes{$_}));
               foreach my $index (@{$indexes{$_}}) {
                  if ($date =~/$items{$index}{'idate'}/ ||
                      $date2=~/$items{$index}{'idate'}/ ||
                      easter_match($year,$month,$day, $easter_month,$easter_day,
                                   $items{$index}{'idate'}) ) {
                     push(@indexlist, $index);
                  }
               }
            }
            @indexlist=sort { $items{$a}{'starthourmin'}<=>$items{$b}{'starthourmin'} || 
                              $items{$a}{'endhourmin'}<=>$items{$b}{'endhourmin'} || 
                              $b<=>$a } @indexlist;

            $temphtml .= qq|<tr><td>|;
            for my $index (@indexlist) {
               if ($i<$prefs{'calendar_monthviewnumitems'}) {
                  $temphtml .= month_week_item($items{$index}, $cal_url.qq|action=calday&year=$year&month=$month&day=$day|, ($index>=1E6))
               }
               $i++;
            }
            if ($i>$prefs{'calendar_monthviewnumitems'}) {
               $temphtml .= qq|<br><br><font size=-1><a href="|.$cal_url.
                            qq|action=calday&year=$year&month=$month&day=$day">|.
                            qq|$lang_text{'moreitems'}</a></font>\n|;
            }
            $temphtml .= qq|&nbsp;<br>\n| if ($i==0);
            $temphtml .= qq|</td></tr></table></td>\n|;

         } else {
            $temphtml .= qq|<tr><td>$days[$x][$y]</td></tr>|.
                         qq|<tr><td></td></tr></table></td>\n|;
         }

         $html =~ s/\@\@\@DAY$x$y\@\@\@/$temphtml/;
      }
   }

   print htmlheader(), 
         htmlplugin($config{'header_pluginfile'}), 
         $html, 
         htmlplugin($config{'footer_pluginfile'}), 
         htmlfooter(2);
}
######################## END MONTHVIEW ########################

########################## WEEKVIEW ##########################
sub weekview {
   my ($year, $month, $day)=@_;
   my $g2l=time();
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$prefs{'timeoffset'})) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime                         
   }
   $g2l+=timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($current_year, $current_month, $current_day)=(gmtime($g2l))[5,4,3];
   $current_year+=1900; $current_month++;

   $year = $current_year if (!$year);
   $month = $current_month if (!$month);
   $day = $current_day if (!$day);
   $year=2037 if ($year>2037);
   $year=1970 if ($year<1970);

   my ($html, $temphtml);
   $html = readtemplate("weekview.template");
   $html = applystyle($html);

   $temphtml = startform(-name=>"yearform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl") .
               hidden(-name=>'action',
                      -default=>'calweek',
                      -override=>'1').
               hidden(-name=>'month',
                      -default=>$month,
                      -override=>'1').
               hidden(-name=>'day',
                      -default=>$day,
                      -override=>'1').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1').
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1');
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'year',
                         -default=>$year,
                         -size=>'4',
                         -override=>'1');
   $html =~ s/\@\@\@YEARFIELD\@\@\@/$lang_text{'calfmt_year'}/g;
   $html =~ s/\@\@\@YEAR\@\@\@/ $temphtml /;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = formatted_date($year, $month, $day);
   $html =~ s/\@\@\@CALTITLE\@\@\@/$temphtml/g;

   my $cal_url=qq|$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;|;

   $temphtml  = iconlink("yearview.gif", "$lang_calendar{'yearview'} ".formatted_date($year), qq|href="|.$cal_url.qq|action=calyear&year=$year"|). qq| \n|;
   $temphtml .= iconlink("monthview.gif", "$lang_calendar{'monthview'} ".formatted_date($year,$month), qq|href="|.$cal_url.qq|action=calmonth&year=$year&month=$month"|). qq| \n|;
   $temphtml .= iconlink("weekview.gif", "$lang_calendar{'weekview'} ".formatted_date($year,$month,$day), qq|href="|.$cal_url.qq|action=calweek&year=$year&month=$month&day=$day"|). qq| \n|;
   $temphtml .= iconlink("dayview.gif", "$lang_calendar{'dayview'} ".formatted_date($year,$month,$day), qq|href="|.$cal_url.qq|action=calday&year=$year&month=$month&day=$day"|). qq| \n|;
   $temphtml .= iconlink("listview.gif", "$lang_calendar{'listview'} ".formatted_date($year), qq|href="|.$cal_url.qq|action=callist&year=$year"|). qq| \n|;
   if ($year!=$current_year || $month!=$current_month || $day!=$current_day) {
      $temphtml .= iconlink("refresh.gif", "$lang_text{'backto'} $lang_calendar{'weekview'} ".formatted_date($current_year,$current_month,$current_day), qq|href="|.$cal_url.qq|action=calweek&year=$current_year&month=$current_month&day=$current_day"|). qq| \n|;
   }
   $temphtml .= "&nbsp;\n$miscbuttonsstr";
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my $time = timegm("0","0","12", $day, $month-1, $year-1900);

   my ($prev_year, $prev_month, $prev_day)=(gmtime($time-86400*7))[5,4,3];
   $prev_year+=1900; $prev_month++;
   my $gif="left.gif"; $gif="right.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, "$lang_calendar{'weekview'} ".formatted_date($prev_year,$prev_month,$prev_day), qq|href="|.$cal_url.qq|action=calweek&year=$prev_year&month=$prev_month&day=$prev_day"|). qq| \n|;
   $html =~ s/\@\@\@PREV_LINK\@\@\@/$temphtml/g;

   my ($next_year, $next_month, $next_day)=(gmtime($time+86400*7))[5,4,3];
   $next_year+=1900; $next_month++;
   $gif="right.gif"; $gif="left.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, "$lang_calendar{'weekview'} ".formatted_date($next_year,$next_month,$next_day), qq|href="|.$cal_url.qq|action=calweek&year=$next_year&month=$next_month&day=$next_day"|). qq| \n|;
   $html =~ s/\@\@\@NEXT_LINK\@\@\@/$temphtml/g;

   my $wdaynum = (gmtime($time))[6];
   my $start_time = $time - 86400 * (($wdaynum+7-$prefs{'calendar_weekstart'})%7);
   for (my $i=0; $i<7; $i++) {
      my $n=($prefs{'calendar_weekstart'}+$i)%7;
      if ($n==0) {	# sunday
         $html =~ s!\@\@\@WEEKDAY$i\@\@\@!<font color=#cc0000>$lang_wday{$n}</font>!;
      } elsif ($n==6) {	# saturday
         $html =~ s!\@\@\@WEEKDAY$i\@\@\@!<font color=#00aa00>$lang_wday{$n}</font>!;
      } else {
         $html =~ s!\@\@\@WEEKDAY$i\@\@\@!$lang_wday{$n}!;
      }
   }
   my $wdaynum = (gmtime($time))[6];
   my $start_time = $time - 86400 * (($wdaynum+7-$prefs{'calendar_weekstart'})%7);

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      readcalbook("$config{'ow_holidaysdir'}/$prefs{'language'}", \%items, \%indexes, 1E6);
   }

   for my $x (0..6) {
      ($year, $month, $day)=(gmtime($start_time+$x*86400))[5,4,3];
      $year+=1900; $month++;

      my $bgcolor;
      if ($year==$current_year &&
          $month==$current_month &&
          $day==$current_day) {
         $bgcolor="bgcolor=$style{'tablerow_light'}";
      } else {
         $bgcolor="bgcolor=$style{'tablerow_dark'}";
      }

      $temphtml = qq|<td valign=top $bgcolor>|.
                  qq|<table width="100%" cellpadding="0" cellspacing="0">\n|;

      my $daystr=$day; $daystr=" ".$daystr if (length($daystr)<2);
      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl",
                              -name=> "day$day");
      $temphtml .= hidden(-name=>'sessionid',
                          -default=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -value=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>$messageid,
                          -override=>'1');
      $temphtml .= hidden(-name=>'action',
                          -value=>'calday',
                          -override=>'1');
      $temphtml .= hidden(-name=>'year',
                          -value=>$year,
                          -override=>'1');
      $temphtml .= hidden(-name=>'month',
                          -value=>$month,
                          -override=>'1');
      $temphtml .= hidden(-name=>'day',
                          -value=>$day,
                          -override=>'1');
      $temphtml .= qq|<tr><td align="right">|.
                   lunar_str($year, $month, $day, $prefs{'charset'}).
                   submit("$daystr").
                   qq|</td></tr>|.
                   end_form();

      my ($easter_month, $easter_day) = gregorian_easter($year); # compute once

      my $t=timegm 1,1,1,$day,($month-1),($year-1900);
      my $dow=$wdaystr[(gmtime($t))[6]];
      my $date=sprintf("%04d%02d%02d", $year, $month, $day);
      my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);
      my $i=0;

      my @indexlist=();
      foreach ($date, '*') {
         next if (!defined($indexes{$_}));
         foreach my $index (@{$indexes{$_}}) {
            if ($date =~/$items{$index}{'idate'}/ ||
                $date2=~/$items{$index}{'idate'}/ ||
                easter_match($year,$month,$day, $easter_month,$easter_day,
                             $items{$index}{'idate'}) ) {
               push(@indexlist, $index);
            }
         }
      }
      @indexlist=sort { $items{$a}{'starthourmin'}<=>$items{$b}{'starthourmin'} || 
                        $items{$a}{'endhourmin'}<=>$items{$b}{'endhourmin'} || 
                        $b<=>$a } @indexlist;

      $temphtml .= qq|<tr><td valign=bottom>|;
      for my $index (@indexlist) {
         $temphtml .= month_week_item($items{$index}, $cal_url.qq|action=calday&year=$year&month=$month&day=$day|, ($index>=1E6));
         $i++;
      }
      $temphtml .= qq|&nbsp;<br>\n| if ($i==0);
      $temphtml .= qq|</td></tr></table></td>\n|;

      $html =~ s/\@\@\@DAY$x\@\@\@/$temphtml/;
   }

   print htmlheader(), 
         htmlplugin($config{'header_pluginfile'}), 
         $html, 
         htmlplugin($config{'footer_pluginfile'}), 
         htmlfooter(2);
}

# print an item in the month or week view
sub month_week_item {
   my ($r_item, $daylink, $is_global) = @_;

   my ($eventtime, $eventlink, $eventemail);
   if (${$r_item}{'starthourmin'} ne "0") {
      $eventtime = hourmin2str(${$r_item}{'starthourmin'}, $prefs{'hourformat'});
      if (${$r_item}{'endhourmin'} ne "0") {
        $eventtime .= qq|-| . hourmin2str(${$r_item}{'endhourmin'}, $prefs{'hourformat'});
      }
   } else {
      $eventtime="#";
   }
   $eventtime=qq|<font color="#c00000">$eventtime</font>&nbsp;|;

   if (${$r_item}{'link'}) {
      my $link=${$r_item}{'link'}; $link=~s/\%THISSESSION\%/$thissession/;
      $eventlink = qq|&nbsp;|. iconlink("cal-link.gif", "${$r_item}{'link'}", qq|href="$link" target="_blank"|);
   }
   if (${$r_item}{'email'}) {
      $eventemail = qq|&nbsp;|. iconlink("email.gif", "${$r_item}{'email'}", "");
   }

   my $s=${$r_item}{'string'};
   my $nohtml=$s; $nohtml=~ s/<.*?>//g;
   $s=substr($nohtml, 0, 36)."..." if (length($nohtml)>40);
   $s="$s *" if ($is_global);

   my $colorstr='';
   if (defined($eventcolors{${$r_item}{'eventcolor'}})) {
      $colorstr=qq|bgcolor="#$eventcolors{${$r_item}{'eventcolor'}}"|;
   }

   my $temphtml=qq|<table $colorstr cellspacing=1 cellpadding=0 width="100%"><tr><td>|.
                "$eventtime$s$eventlink$eventemail".
                qq|</td></tr></table>|;

   return($temphtml);
}
######################## END WEEKVIEW #########################

########################## DAYVIEW ###########################
sub dayview {
   my ($year, $month, $day)=@_;
   my $g2l=time();
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$prefs{'timeoffset'})) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime                         
   }
   $g2l+=timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($current_year, $current_month, $current_day)=(gmtime($g2l))[5,4,3];
   $current_year+=1900; $current_month++;

   $year = $current_year if (!$year);
   $month = $current_month if (!$month);
   $day = $current_day if (!$day);
   $year=2037 if ($year>2037);
   $year=1970 if ($year<1970);

   my ($html, $temphtml);
   $html = readtemplate("dayview.template");
   $html = applystyle($html);

   $temphtml = startform(-name=>"yearform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl") .
               hidden(-name=>'action',
                      -default=>'calday',
                      -override=>'1').
               hidden(-name=>'month',
                      -default=>$month,
                      -override=>'1').
               hidden(-name=>'day',
                      -default=>$day,
                      -override=>'1').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1').
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1');
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'year',
                         -default=>$year,
                         -size=>'4',
                         -accesskey=>'G',
                         -override=>'1');
   $html =~ s/\@\@\@YEARFIELD\@\@\@/$lang_text{'calfmt_year'}/g;
   $html =~ s/\@\@\@YEAR\@\@\@/ $temphtml /;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   my $cal_url=qq|$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;|;

   $temphtml  = iconlink("yearview.gif", "$lang_calendar{'yearview'} ".formatted_date($year), qq|accesskey="Y" href="|.$cal_url.qq|action=calyear&year=$year"|);
   $temphtml .= iconlink("monthview.gif", "$lang_calendar{'monthview'} ".formatted_date($year,$month), qq|accesskey="M" href="|.$cal_url.qq|action=calmonth&year=$year&month=$month"|);
   $temphtml .= iconlink("weekview.gif", "$lang_calendar{'weekview'} ".formatted_date($year,$month,$day), qq|accesskey="W" href="|.$cal_url.qq|action=calweek&year=$year&month=$month&day=$day"|);
   $temphtml .= iconlink("dayview.gif", "$lang_calendar{'dayview'} ".formatted_date($year,$month,$day), qq|accesskey="T" href="|.$cal_url.qq|action=calday&year=$year&month=$month&day=$day"|);
   $temphtml .= iconlink("listview.gif", "$lang_calendar{'listview'} ".formatted_date($year), qq|accesskey="L" href="|.$cal_url.qq|action=callist&year=$year"|);
   if ($year!=$current_year || $month!=$current_month || $day!=$current_day) {
      $temphtml .= iconlink("refresh.gif", "$lang_text{'backto'} ".formatted_date($current_year,$current_month,$current_day), qq|accesskey="R" href="|.$cal_url.qq|action=calday&year=$current_year&month=$current_month&day=$current_day"|);
   }
   $temphtml .= "&nbsp;\n$miscbuttonsstr";
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my $time = timegm("0","0","12", $day, $month-1, $year-1900);

   my ($prev_year, $prev_month, $prev_day)=(gmtime($time-86400))[5,4,3];
   $prev_year+=1900; $prev_month++;
   my $gif="left.gif"; $gif="right.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, formatted_date($prev_year,$prev_month,$prev_day), qq|accesskey="U" href="|.$cal_url.qq|action=calday&year=$prev_year&month=$prev_month&day=$prev_day"|). qq| \n|;
   $html =~ s/\@\@\@PREV_LINK\@\@\@/$temphtml/g;

   my ($next_year, $next_month, $next_day)=(gmtime($time+86400))[5,4,3];
   $next_year+=1900; $next_month++;
   $gif="right.gif"; $gif="left.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, formatted_date($next_year,$next_month,$next_day), qq|accesskey="D" href="|.$cal_url.qq|action=calday&year=$next_year&month=$next_month&day=$next_day"|). qq| \n|;
   $html =~ s/\@\@\@NEXT_LINK\@\@\@/$temphtml/g;


   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      readcalbook("$config{'ow_holidaysdir'}/$prefs{'language'}", \%items, \%indexes, 1E6);
   }

   my $t=timegm(1, 1, 1, $day, $month-1, $year-1900);
   my $wdaynum=(gmtime($t))[6];

   $temphtml = formatted_date($year, $month, $day, $wdaynum);
   if ($prefs{'charset'} eq "big5" || $prefs{'charset'} eq "gb2312") {
      $temphtml .= qq| &nbsp; |.lunar_str($year, $month, $day, $prefs{'charset'});
   }
   $html =~ s/\@\@\@CALTITLE\@\@\@/$temphtml/g;

   my ($easter_month, $easter_day) = gregorian_easter($year); # compute once

   # Find all indexes that take place today and sort them by starthourmin
   my $dow   = $wdaystr[$wdaynum];
   my $date  = sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2 = sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

   my @indexlist = (); # an index list of how many events occur on this day
   foreach ($date, '*') {
      next if (!defined($indexes{$_}));
      foreach my $index (@{$indexes{$_}}) {
         if ($date =~/$items{$index}{'idate'}/ ||
             $date2=~/$items{$index}{'idate'}/ ||
             easter_match($year,$month,$day, $easter_month,$easter_day,
                          $items{$index}{'idate'}) ) {
            push(@indexlist, $index);
         }
      }
   }
   @indexlist=sort { $items{$a}{'starthourmin'}<=>$items{$b}{'starthourmin'} || 
                     $items{$a}{'endhourmin'}<=>$items{$b}{'endhourmin'} || 
                     $b<=>$a } @indexlist;

   my @bgcolor=($style{"tablerow_light"}, $style{"tablerow_dark"});
   my $colornum=0;
   $temphtml='';

   my (@allday_indexies, @matrix, %layout, $slotmin, $slotmax, $colmax, );
   build_event_matrix(\%items, \@indexlist, 
       \@allday_indexies, \@matrix, \%layout, \$slotmin, \$slotmax, \$colmax);

   $colornum=($colornum+1)%2; # alternate the bgcolor
   $temphtml .= qq|<tr>|.
                qq|<td colspan="2">|.
                  qq|<!-- THE OUTSIDE-MOST TABLE DECLARATION FOR OUR CALENDAR DATA -->|.
                  qq|<table width="100%" cellpadding="0" cellspacing="1" border="0">\n|.
                  qq|<!-- BEGIN LISTING ALL DAY EVENTS -->|.
                  qq|<tr>|.
                  qq|<td width="10%" bgcolor=$style{'columnheader'} align="center" nowrap>$lang_text{'allday'}</td>|.
                  qq|<td width="90%" bgcolor=$style{'columnheader'} colspan="|.($colmax+1).qq|">|.
                  qq|<table width="100%" cellpadding="0" cellspacing="0">\n|; 

   my ($bgcolorstr, $bdstylestr, $eventlink, $eventemail, $eventtime);

   for my $index (@allday_indexies) {
      my $r_event=$items{$index};

      # we do the all day events first because they're the easiest
      ($eventtime, $eventlink, $eventemail) = ('', '', '');

      if (${$r_event}{'eventcolor'} eq "none") {
         $bgcolorstr = qq|bgcolor=$style{'columnheader'}|;
      } else {
         $bgcolorstr = qq|bgcolor="#|. $eventcolors{${$r_event}{'eventcolor'}}. qq|"|;
      }
      if (${$r_event}{'starthourmin'} ne "0") {
         $eventtime = hourmin2str(${$r_event}{'starthourmin'}, $prefs{'hourformat'});
         if (${$r_event}{'endhourmin'} ne "0") {
           $eventtime .= qq|-| . hourmin2str(${$r_event}{'endhourmin'}, $prefs{'hourformat'});
         }
      } else {
         $eventtime = "#";
      }
      $eventtime=qq|<font color="#c00000">$eventtime</font>&nbsp;|;

      if (${$r_event}{'link'}) {
         my $link=${$r_event}{'link'}; $link=~s/\%THISSESSION\%/$thissession/;
         $eventlink = qq|&nbsp;|. iconlink("cal-link.gif", "${$r_event}{'link'}", qq|href="$link" target="_blank"|);
      }
      if (${$r_event}{'email'}) {
         $eventemail = qq|&nbsp;|. iconlink("email.gif", "${$r_event}{'email'}", "");
      }
      my ($jsedit, $jsdel)=('','');
      if (${$r_event}{'idate'} =~ m/[\*|,|\|]/) {
         $jsedit = qq|onclick="return confirm('$lang_text{multieditconf}')"|;
         $jsdel = qq|onclick="return confirm('$lang_text{multidelconf}')"|;
      } else {
         $jsdel = qq|onclick="return confirm('$lang_text{caldelconf}')"|;
      }

      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor[$colornum] valign="top" colspan="|.($colmax+1).qq|">\n|.
                   qq|<table width="100%" cellpadding="2" cellspacing="0"><tr><td $bgcolorstr valign="top" align="left">|;
      if ($index>=1E6) {
         $temphtml .= qq|$eventtime${$r_event}{'string'} *|.
                      $eventlink.$eventemail;
      } else {
         $temphtml .= qq|<a accesskey="E" title="$lang_text{'edit'}" href="$cal_url|.
                      qq|action=caledit&year=$year&month=$month&day=$day&index=$index" $jsedit>|.
                      qq|$eventtime${$r_event}{'string'}</a>|.
                      $eventlink.$eventemail.
                      qq|&nbsp;&nbsp;|. iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="${cal_url}action=caldel&year=$year&month=$month&day=$day&index=$index" $jsdel|);
      }
      $temphtml .= qq|</td></tr></table>|.
                   qq|</td>|.
                   qq|</tr>|;
   }

   if ($#indexlist < 0) {
      $temphtml .=  qq|<tr>|.
                    qq|<td bgcolor=$style{'columnheader'} align=center colspan="|.($colmax+1).qq|">$lang_text{'noitemforthisday'}</td>|.
                    qq|</tr>\n|;
   } elsif ($#allday_indexies < 0) {
      $temphtml .=  qq|<tr>|.
                    qq|<td bgcolor=$style{'columnheader'} align=center colspan="|.($colmax+1).qq|">&nbsp;</td>|.
                    qq|</tr>\n|;
   }

   $temphtml .= qq|</table>|.
                qq|</td>|.
                qq|</tr>|.
                qq|<!--END OF ALL DAY LISTINGS-->|;


   $temphtml .= qq|<!--START EVENT MATRIX-->|;

   my $slots_in_hour=int(60/($prefs{'calendar_interval'}||30)+0.999999);

   for (my $slot = 0; $slot < $#slottime; $slot++) {
      if ($slot % $slots_in_hour==0) {

         # skip too earily time slots
         my $is_earily=1;
         for my $i (0..$slots_in_hour-1) {
            if ($slot+$i >= $slotmin || 
                $slottime[$slot+$i] ge $prefs{'calendar_starthour'}) {
               $is_earily=0; last;
            }
         }
         if ($is_earily) {
            $slot=$slot+$slots_in_hour-1; next;		# skip $slots_in_hour slots at once
         }

         # skip empty time slots
         if (!$prefs{'calendar_showemptyhours'}) {
            my $is_empty=1;
            for my $col (0..$colmax) {
               for my $i (0..$slots_in_hour-1) {
                  if ( defined($matrix[$slot+$i][$col]) && $matrix[$slot+$i][$col] ) {
                     $is_empty=0; last;
                  }
                  last if (!$is_empty);
               }
               last if (!$is_empty);
            }
            if ($is_empty) {
               $slot=$slot+$slots_in_hour-1; next;	# skip $slots_in_hour slots at once
            }
         }

         last if ($slot > $slotmax && $slottime[$slot] gt $prefs{'calendar_endhour'});
 
         # start html for a full row
         $colornum  = ($colornum+1)%2; # alternate the bgcolor
         $temphtml .= qq|<tr>|.
                      qq|<td width="10%" bgcolor=$bgcolor[$colornum] align="right" valign=top nowrap>|.
                      hourmin2str($slottime[$slot], $prefs{'hourformat'}).
                      qq|</td>|;
      } else {
         my $s="&nbsp;";
         if ($slots_in_hour>3 && ($slot%$slots_in_hour)%2==0) {
            $s=qq|<font color=#c0c0c0>|.
               (($slot%$slots_in_hour)*$prefs{'calendar_interval'}).
               qq|</font>|;
         }
         # start html for non hour row
         $temphtml .= qq|<tr>|.
                      qq|<td width="10%" bgcolor=$bgcolor[$colornum] valign="top" align="right">|.
                      $s.
                      qq|</td>|;
      }

      for my $col (0..$colmax) {
         if (defined($matrix[$slot][$col])) {
            my $index=$matrix[$slot][$col];
            my $r_event=$items{$index};

            if ($slot==$layout{$index}{'startslot'} &&
                $col==$layout{$index}{'startcol'} ) {	# an event started at this cell
               ($eventtime, $eventlink, $eventemail) = ('', '', '');

               if (${$r_event}{'eventcolor'} ne "none") {
                  $bgcolorstr = qq|bgcolor="#|. $eventcolors{${$r_event}{'eventcolor'}}. qq|"|;
                  if (${$r_event}{'endhourmin'} ne '0') {
                     $bdstylestr = qq|style="border-width: 1px; border-style: solid; border-color: #|.
                                   bordercolor($eventcolors{${$r_event}{'eventcolor'}}).
                                   qq|;"|;
                  } else {
                     $bdstylestr = '';
                  }
               } else {
                  $bgcolorstr = qq|bgcolor=$bgcolor[$colornum]|;
                  if (${$r_event}{'endhourmin'} ne '0') {
                     $bdstylestr = qq|style="border-width: 1px; border-style: solid; border-color: #666666;"|;
                  } else {
                     $bdstylestr = '';
                  }
               }

               $eventtime = hourmin2str(${$r_event}{'starthourmin'}, $prefs{'hourformat'});
               if (${$r_event}{'endhourmin'} ne "0") {
                  $eventtime .= qq|-| . hourmin2str(${$r_event}{'endhourmin'}, $prefs{'hourformat'});
               }
               $eventtime=qq|<font color="#c00000">$eventtime</font>&nbsp;|;

               if (${$r_event}{'link'}) {
                  my $link=${$r_event}{'link'}; $link=~s/\%THISSESSION\%/$thissession/;
                  $eventlink = qq|&nbsp;|. iconlink("cal-link.gif", "${$r_event}{'link'}", qq|href="$link" target="_blank"|);
               }
               if (${$r_event}{'email'}) {
                  $eventemail = qq|&nbsp;|. iconlink("email.gif", "${$r_event}{'email'}", "");
               }
               my ($jsedit, $jsdel)=('','');
               if (${$r_event}{'idate'} =~ m/[\*|,|\|]/) {
                  $jsedit = qq|onclick="return confirm('$lang_text{multieditconf}')"|;
                  $jsdel = qq|onclick="return confirm('$lang_text{multidelconf}')"|;
               } else {
                  $jsdel = qq|onclick="return confirm('$lang_text{caldelconf}')"|;
               }
               $temphtml .= qq|<td $bgcolorstr $bdstylestr valign="top" width="|.
                            int(100 * $layout{$index}{'colspan'}/($colmax+1)).
                            qq|%" rowspan="$layout{$index}{'rowspan'}" colspan="$layout{$index}{'colspan'}">|;
               if ($index > 1E6) {
                  $temphtml .=qq|$eventtime ${$r_event}{'string'} *|.
                              $eventlink.$eventemail;
               } else {
                  $temphtml .= qq|<a accesskey="E" title="$lang_text{'edit'}" href="$cal_url|.
                               qq|action=caledit&year=$year&month=$month&day=$day&index=$index" $jsedit>|.
                               qq|$eventtime ${$r_event}{'string'}</a>|.
                               $eventlink.$eventemail.
                               qq|&nbsp;&nbsp;|. iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="${cal_url}action=caldel&year=$year&month=$month&day=$day&index=$index" $jsdel|);
               }
               $temphtml .= qq|</td>|;
            } else {
               # event in this cell has been drawed, nothing to do
            }
            
         } else {
            # no event in this cell
            $temphtml .= qq|<td bgcolor=$bgcolor[$colornum]>&nbsp;</td>|;
         }
      }      
      $temphtml .= qq|</tr>|;
   }

   $temphtml .= qq|</table></td></tr>\n|;


   $html =~ s/\@\@\@CALENDARITEMS\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl",
                         -name=>'AddItemForm');
   $temphtml .= hidden(-name=>'sessionid',
                       -value=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -value=>$folder,
                       -override=>'1');
   $temphtml .= hidden(-name=>'message_id',
                       -default=>$messageid,
                       -override=>'1');
   $temphtml .= hidden(-name=>'action',
                       -value=>'caladd',
                       -override=>'1');
   $temphtml .= hidden(-name=>'year',
                       -value=>$year,
                       -override=>'1');
   $temphtml .= hidden(-name=>'month',
                       -value=>$month,
                       -override=>'1');
   $temphtml .= hidden(-name=>'day',
                       -value=>$day,
                       -override=>'1');
   $html =~ s/\@\@\@STARTADDITEMFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'string',
                         -default=>'',
                         -size=>'32',
                         -accesskey=>'I',
                         -override=>'1');
   $html =~ s/\@\@\@STRINGFIELD\@\@\@/$temphtml/;

   my @hourlist;
   if ($prefs{'hourformat'}==12) {
      @hourlist=qw(none 12 1 2 3 4 5 6 7 8 9 10 11);
   } else {
      @hourlist=qw(none 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23);
   }
   my %numlabels=( none=>$lang_text{'none'},
                   0=>'00', 1=>'01', 2=>'02', 3=>'03', 4=>'04',
                   5=>'05', 6=>'06', 7=>'07', 8=>'08', 9=>'09');
   my $temphtml2;

   $temphtml = $lang_text{'calfmt_hourminampm'};
   $temphtml2 = popup_menu(-name=>'starthour',
                           -values=>\@hourlist,
                           -default=>'none',
                           -labels=>\%numlabels);
   $temphtml2 .= " <B>:</B> ";
   $temphtml2 .= popup_menu(-name=>'startmin',
                            -values=>[0,5,10,15,20,25,30,35,40,45,50,55],
                            -default=>0,
                            -labels=>\%numlabels);
   $temphtml =~ s/\@\@\@HOURMIN\@\@\@/$temphtml2/;
   if ($prefs{'hourformat'}==12) {
      $temphtml2 = popup_menu(-name=>'startampm',
                              -values=>['am','pm'],
                              -default=>'am',
                              -labels=>{ am=>$lang_text{'am'}, pm=>$lang_text{'pm'} } );
   } else {
      $temphtml2 ="";
   }
   $temphtml =~ s/\@\@\@AMPM\@\@\@/$temphtml2/;
   $html =~ s/\@\@\@STARTHOURMINMENU\@\@\@/$temphtml/;

   $temphtml = $lang_text{'calfmt_hourminampm'};
   $temphtml2 = popup_menu(-name=>'endhour',
                           -values=>\@hourlist,
                           -default=>'none',
                           -labels=>\%numlabels);
   $temphtml2 .= " <B>:</B> ";
   $temphtml2 .= popup_menu(-name=>'endmin',
                            -values=>[0,5,10,15,20,25,30,35,40,45,50,55],
                            -default=>0,
                            -labels=>\%numlabels);
   $temphtml =~ s/\@\@\@HOURMIN\@\@\@/$temphtml2/;
   if ($prefs{'hourformat'}==12) {
      $temphtml2 = popup_menu(-name=>'endampm',
                              -values=>['am','pm'],
                              -default=>'am',
                              -labels=>{ am=>$lang_text{'am'}, pm=>$lang_text{'pm'} } );
   } else {
      $temphtml2 ="";
   }
   $temphtml =~ s/\@\@\@AMPM\@\@\@/$temphtml2/;
   $html =~ s/\@\@\@ENDHOURMINMENU\@\@\@/$temphtml/;

   my %wdaynum = qw (Sun 0 Mon 1 Tue 2 Wed 3 Thu 4 Fri 5 Sat 6);
   my $weekorder=int(($day+6)/7);
   my %dayfreqlabels = ('thisdayonly'       =>$lang_text{'thisday_only'},
                        'thewdayofthismonth'=>$lang_text{'the_wday_of_thismonth'},
                        'everywdaythismonth'=>$lang_text{'every_wday_thismonth'});
   $dayfreqlabels{'thewdayofthismonth'}=~s/\@\@\@ORDER\@\@\@/$lang_order{$weekorder}/;
   $dayfreqlabels{'thewdayofthismonth'}=~s/\@\@\@WDAY\@\@\@/$lang_wday{$wdaynum{$dow}}/;
   $dayfreqlabels{'everywdaythismonth'}=~s/\@\@\@WDAY\@\@\@/$lang_wday{$wdaynum{$dow}}/;

   if ($weekorder<=4) {
      $temphtml .= hidden(-name=>'weekorder',
                          -value=>$weekorder,
                          -override=>'1');
      $temphtml = popup_menu(-name=>'dayfreq',
                             -values=>['thisdayonly', 'thewdayofthismonth', 'everywdaythismonth'],
                             -labels=>\%dayfreqlabels);
   } else {
      $temphtml = popup_menu(-name=>'dayfreq',
                             -values=>['thisdayonly', 'everywdaythismonth'],
                             -labels=>\%dayfreqlabels);
   }
   $html =~ s/\@\@\@FREQMENU\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'thisandnextndays',
                        -value=>'1',
                        -checked=>0,
                        -label=>'');
   $html =~ s/\@\@\@THISANDNEXTNDAYSCHECKBOX\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'ndays',
                         -default=>'',
                         -size=>'2',
                         -override=>'1');
   $html =~ s/\@\@\@NDAYSFIELD\@\@\@/$temphtml/;

   my %monthfreqlabels = ('thismonthonly'         =>$lang_text{'thismonth_only'},
                          'everyoddmonththisyear' =>$lang_text{'every_oddmonth_thisyear'},
                          'everyevenmonththisyear'=>$lang_text{'every_evenmonth_thisyear'},
                          'everymonththisyear'    =>$lang_text{'every_month_thisyear'});
   my @monthfreq =('thismonthonly');
   if ($month%2==1) {
      push(@monthfreq, 'everyoddmonththisyear');
   } else {
      push(@monthfreq, 'everyevenmonththisyear');
   }
   push(@monthfreq, 'everymonththisyear');
   $temphtml = popup_menu(-name=>'monthfreq',
                          -values=>\@monthfreq,
                          -labels=>\%monthfreqlabels);
   $html =~ s/\@\@\@MONTHFREQMENU\@\@\@/$temphtml/g;

   $temphtml = checkbox(-name=>'everyyear',
                        -value=>'1',
                        -checked=>0,
                        -label=>'');
   $html =~ s/\@\@\@EVERYYEARCHECKBOX\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'link',
                         -default=>'http://',
                         -size=>'32',
                         -override=>'1');
   $html =~ s/\@\@\@LINKFIELD\@\@\@/$temphtml/;

   if ($config{'calendar_email_notifyinterval'} > 0 ) {
      $html =~ s/\@\@\@EMAILSTART\@\@\@//;
      $html =~ s/\@\@\@EMAILEND\@\@\@//;
      $temphtml = textfield(-name=>'email',
                            -default=>'',
                            -size=>'32',
                            -override=>'1');
      $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;
   } else {
      $html =~ s/\@\@\@EMAILSTART\@\@\@/<!--/;
      $html =~ s/\@\@\@EMAILEND\@\@\@/-->/;
      $html =~ s/\@\@\@EMAILFIELD\@\@\@//;
   }

   $temphtml = popup_menu(-name=>'eventcolor',
                          -values=>['none', sort keys %eventcolors],
                          -default=>'none',
                          -labels=>{ none => $lang_text{'none'} },
                          -override=>'1');
   $html =~ s/\@\@\@EVENTCOLORMENU\@\@\@/$temphtml/;

   $temphtml = qq|<table height=25>|;
   foreach (sort keys %eventcolors) {
      $temphtml .= qq|<td width=14 align=center bgcolor="#$eventcolors{$_}">|.
                   qq|<a onclick="JavaScript:document.AddItemForm.eventcolor.value='$_'">$_</a></td>\n|;
   }
   $temphtml .= qq|<td width=14 align=center">|.
                qq|<a onclick="JavaScript:document.AddItemForm.eventcolor.value='none'">--</a></td>\n|;
   $temphtml .= qq|</tr></table>|;
   $html =~ s/\@\@\@COLORTABLE\@\@\@/$temphtml/;

   $temphtml = submit(-name=>"savebutton",
                      -accesskey=>'I',
                      -value=>"$lang_text{'save'}");
   $html =~ s/\@\@\@SUBMITBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   print htmlheader(), 
         htmlplugin($config{'header_pluginfile'}), 
         $html, 
         htmlplugin($config{'footer_pluginfile'}), 
         htmlfooter(2);
}

sub build_event_matrix {
   my ($r_items, $r_indexlist, 
       $r_allday_indexies, $r_matrix, $r_layout, $r_slotmin, $r_slotmax, $r_colmax)=@_;
   my @matrix_indexies;
   my %slots;
   (${$r_slotmin}, ${$r_slotmax}, ${$r_colmax})=(24, 0, 0);

   # split the events into two lists: all day events, and not all day events.
   foreach my $index (@{$r_indexlist}) {
      my $r_event=${$r_items}{$index};
      if ( (${$r_event}{'starthourmin'} gt ${$r_event}{'endhourmin'} && ${$r_event}{'endhourmin'} ne '0') ||
           (${$r_event}{'starthourmin'} eq '0' && ${$r_event}{'endhourmin'} eq '0') ) {
          push(@{$r_allday_indexies}, $index);
      } else {
          push(@matrix_indexies, $index);
      }
   }

   foreach my $index (@matrix_indexies) {
      my $r_event=${$r_items}{$index};
      next if (${$r_event}{'endhourmin'} ne '0' &&
               ${$r_event}{'starthourmin'} gt ${$r_event}{'endhourmin'});
      # find all slots of this event
      for (my $slot = 0; $slot < $#slottime; $slot++) {
         if ((${$r_event}{'endhourmin'}   gt $slottime[$slot] && 
              ${$r_event}{'starthourmin'} lt $slottime[$slot+1]) ||
             (${$r_event}{'endhourmin'}   eq '0' && 
              ${$r_event}{'starthourmin'} ge $slottime[$slot] &&
              ${$r_event}{'starthourmin'} lt $slottime[$slot+1]) ) {
            push(@{$slots{$index}}, $slot);
            ${$r_layout}{$index}{'rowspan'}++;
            ${$r_slotmin}=$slot if ($slot<${$r_slotmin});
            ${$r_slotmax}=$slot if ($slot>${$r_slotmax});
         }
      }

      # find the fisrt available column for this event so all it won't conflict with other event
      my $col=0;
      for ($col=0; ; $col++) {
         my $col_available=1;
         foreach my $slot (@{$slots{$index}}) {
            if (defined(${$r_matrix}[$slot][$col]) && ${$r_matrix}[$slot][$col]) {
               $col_available=0; last;
            }
         }
         last if ($col_available);
      }
      ${$r_layout}{$index}{'colspan'}=1;

      foreach my $slot (@{$slots{$index}}) {
         ${$r_matrix}[$slot][$col]=$index;
      }
      ${$r_layout}{$index}{'startslot'}=${$slots{$index}}[0];
      ${$r_layout}{$index}{'startcol'}=$col;
      ${$r_colmax}=$col if ($col>${$r_colmax});
   }

   # try to enlarge this event to other columns
   foreach my $index (@matrix_indexies) {
      my $extensible=1;
      foreach my $slot (@{$slots{$index}}) {
         for my $col (${$r_layout}{$index}{'startcol'}+1..${$r_colmax}) {
            if (defined(${$r_matrix}[$slot][$col]) && ${$r_matrix}[$slot][$col]) {
               $extensible=0; last;
            }
         }
         last if ($extensible==0);
      }
      if ($extensible) {
         for my $col (${$r_layout}{$index}{'startcol'}+1..${$r_colmax}) {
            foreach my $slot (@{$slots{$index}}) {
               ${$r_matrix}[$slot][$col]=$index;
            }
            ${$r_layout}{$index}{'colspan'}++;
         }
      }
   }         
}
 
sub bordercolor {
   # take a hex number and calculate a hex number that
   # will be a nice complement to it as a bordercolor
   my ($redhex, $greenhex, $bluehex) = $_[0] =~ m/(..)(..)(..)/;
   my ($r, $g, $blue) = (sprintf("%d", hex($redhex)), sprintf("%d", hex($greenhex)), sprintf("%d", hex($bluehex)));
   my ($h, $s, $v) = rgb2hsv($r, $g, $blue);

   # adjust to get our new hsv bordercolor
   if ($s > .5) { $s -= .15; $v += 30; } else { $s += .15; $v -= 30; };
   $s = 0 if ($s < 0);
   $s = 1 if ($s > 1);
   $v = 0 if ($v < 0);
   $v = 255 if ($v > 255);

   ($r, $g, $blue) = hsv2rgb($h, $s, $v);
   ($redhex, $greenhex, $bluehex) = (sprintf("%02x", $r), sprintf("%02x", $g), sprintf("%02x", $blue));

   return "$redhex$greenhex$bluehex";
}

sub rgb2hsv {
   # based off reference code at http://www.cs.rit.edu/~ncs/color/t_convert.html
   my ($r, $g, $blue) = @_;
   my ($h, $s, $v, $min, $max, $delta);

   ($min, $max) = (sort { $a <=> $b } ($r,$g,$blue))[0,-1];
   return(-1, 0, 0) if ($max==0); # r g b are all 0

   $delta = $max - $min;

   $v = $max;
   $s = $delta / $max;
   if ($r == $max) {
      $h = ($g - $blue) / $delta;
   } elsif ($g == $max) {
      $h = 2 + ($blue - $r) / $delta;
   } else {
      $h = 4 + ($r - $g) / $delta;
   }

   $h *= 60;
   $h += 360 if ($h < 0);

   return ($h, $s, $v);
}

sub hsv2rgb {
   # based off reference code at http://www.cs.rit.edu/~ncs/color/t_convert.html 
   my ($h, $s, $v) = @_;
   my ($i, $f, $p, $q, $t, $r, $g, $blue);

   return ($v, $v, $v) if ($s == 0); # achromatic

   $h /= 60; # sector 0 to 5
   $i = int($h);
   $f = $h - $i;
   $p = $v * (1 - $s);
   $q = $v * (1 - $s * $f);
   $t = $v * (1 - $s * (1 - $f));

   if ($i == 0) {
      ($r, $g, $blue) = ($v, $t, $p);
   } elsif ($i == 1) {
      ($r, $g, $blue) = ($q, $v, $p);
   } elsif ($i == 2) {
      ($r, $g, $blue) = ($p, $v, $t);
   } elsif ($i == 3) {
      ($r, $g, $blue) = ($p, $q, $v);
   } elsif ($i == 4) {
      ($r, $g, $blue) = ($t, $p, $v);
   } else {
      ($r, $g, $blue) = ($v, $p, $q);
   }

   return ($r, $g, $blue);
}
######################## END DAYVIEW #########################

######################## LISTVIEW #########################
sub listview {
   my $year=$_[0];
   my $g2l=time();
   if ($prefs{'daylightsaving'} eq "on" ||
       ($prefs{'daylightsaving'} eq "auto" && is_dst($g2l,$prefs{'timeoffset'})) ) {
      $g2l+=3600; # plus 1 hour if is_dst at this gmtime                         
   }
   $g2l+=timeoffset2seconds($prefs{'timeoffset'}); # trick makes gmtime($g2l) return localtime in timezone of timeoffsset
   my ($current_year, $current_month, $current_day)=(gmtime($g2l))[5,4,3];
   $current_year+=1900; $current_month++;

   $year = $current_year if (!$year);
   $year=2037 if ($year>2037);
   $year=1970 if ($year<1970);

   my ($html, $temphtml);
   $html = readtemplate("listview.template");
   $html = applystyle($html);

   $temphtml = startform(-name=>"yearform",
			 -action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl") .
               hidden(-name=>'action',
                      -default=>'callist',
                      -override=>'1').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1').
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1');
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'year',
                         -default=>$year,
                         -size=>'4',
                         -accesskey=>'G',
                         -override=>'1');
   $html =~ s/\@\@\@YEARFIELD\@\@\@/$lang_text{'calfmt_year'}/g;
   $html =~ s/\@\@\@YEAR\@\@\@/ $temphtml /;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = formatted_date($year);
   $html =~ s/\@\@\@CALTITLE\@\@\@/$temphtml/g;

   my $cal_url=qq|$config{'ow_cgiurl'}/openwebmail-cal.pl?sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;|;

   $temphtml  = iconlink("yearview.gif" ,"$lang_calendar{'yearview'} ".formatted_date($year), qq|accesskey="Y" href="|.$cal_url.qq|action=calyear&year=$year"|);
   $temphtml .= iconlink("monthview.gif", "$lang_calendar{'monthview'} ".formatted_date($year, $current_month), qq|accesskey="M" href="|.$cal_url.qq|action=calmonth&year=$year&month=$current_month"|);
   $temphtml .= iconlink("weekview.gif", "$lang_calendar{'weekview'} ".formatted_date($year, $current_month, $current_day), qq|accesskey="W" href="|.$cal_url.qq|action=calweek&year=$year&month=$current_month&day=$current_day"|);
   $temphtml .= iconlink("dayview.gif", "$lang_calendar{'dayview'} ".formatted_date($year, $current_month, $current_day), qq|accesskey="T" href="|.$cal_url.qq|action=calday&year=$year&month=$current_month&day=$current_day"|);
   $temphtml .= iconlink("listview.gif", "$lang_calendar{'listview'} ".formatted_date($year), qq|accesskey="L" href="|.$cal_url.qq|action=callist&year=$year"|);
   if ($year != $current_year) {
      $temphtml .= iconlink("refresh.gif", "$lang_text{'backto'} ".formatted_date($current_year), qq|accesskey="R" href="|.$cal_url.qq|action=callist&year=$current_year"|);
   }
   $temphtml .= "&nbsp;\n$miscbuttonsstr";
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   my $prev_year = $year - 1;
   my $gif="left.gif"; $gif="right.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, formatted_date($prev_year), qq|accesskey="U" href="|.$cal_url.qq|action=callist&year=$prev_year"|). qq| \n|;
   $html =~ s/\@\@\@PREV_LINK\@\@\@/$temphtml/g;

   my $next_year = $year + 1;
   $gif="right.gif"; $gif="left.gif" if (is_RTLmode($prefs{'language'}));
   $temphtml=iconlink($gif, formatted_date($next_year), qq|accesskey="D" href="|.$cal_url.qq|action=callist&year=$next_year"|). qq| \n|;
   $html =~ s/\@\@\@NEXT_LINK\@\@\@/$temphtml/g;

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      readcalbook("$config{'ow_holidaysdir'}/$prefs{'language'}", \%items, \%indexes, 1E6);
   }

   my $t0 = timegm(1,1,1, $current_day, $current_month-1, $current_year-1900);
   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   if ((($year % 4) == 0) && ((($year % 100) != 0) || (($year % 400) == 0))) {
      $days_in_month[2]++;
   }
   my @accesskey=qw(0 1 2 3 4 5 6 7 8 9 0 J Q);

   my ($easter_month, $easter_day) = gregorian_easter($year); # compute once
   $temphtml="";
   for my $month (1..12) {
      for my $day (1..$days_in_month[$month]) {
         my $t=timegm 1,1,1,$day,($month-1),($year-1900);
         my $wdaynum=(gmtime($t))[6];
         my $dow=$wdaystr[$wdaynum];
         my $date=sprintf("%04d%02d%02d", $year, $month, $day);
         my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

         my @indexlist=();
         foreach ($date, '*') {
            next if (!defined($indexes{$_}));
            foreach my $index (@{$indexes{$_}}) {
               if ($date =~/$items{$index}{'idate'}/ ||
                   $date2=~/$items{$index}{'idate'}/ ||
                   easter_match($year,$month,$day, $easter_month,$easter_day,
                                $items{$index}{'idate'}) ) {
                  push(@indexlist, $index);
               }
            }
         }
         @indexlist=sort { $items{$a}{'starthourmin'}<=>$items{$b}{'starthourmin'} || 
                           $items{$a}{'endhourmin'}<=>$items{$b}{'endhourmin'} || 
                           $b<=>$a } @indexlist;

         my $dayhtml="";
         for my $index (@indexlist) {
            $dayhtml .= listview_item($index, \%items, $cal_url, "&year=$year&month=$month&day=$day&index=$index&callist=1", ($index>=1E6))
         }

         my $bgcolor;
         if ($year==$current_year && $month==$current_month && $day==$current_day) {
            $bgcolor="bgcolor=$style{'tablerow_light'}";
         } else {
            $bgcolor="bgcolor=$style{'tablerow_dark'}";
         }

         if ($dayhtml ne "" || $t==$t0) {
            my $daydiffstr=int(($t-$t0)/86400);
            $daydiffstr="+$daydiffstr" if ($daydiffstr>0);
            $dayhtml = qq|<tr><td>&nbsp;</td></tr>| if ($dayhtml eq "");
            $temphtml .= qq|<tr>|.
                         qq|<td $bgcolor nowrap>|.
                         qq|<a accesskey="$accesskey[$month]" href="|.$cal_url.qq|action=calday&year=$year&month=$month&day=$day"><b>|.
                            sprintf("%02d/%02d",$month,$day).qq|</b></a>|;
            if ($prefs{'charset'} eq "big5" || $prefs{'charset'} eq "gb2312") {
               $temphtml .= qq| &nbsp |.lunar_str($year, $month, $day, $prefs{'charset'});
            }
            $temphtml .= qq|</td>|.
                         qq|<td $bgcolor>|.
                         qq|<a href="|.$cal_url.qq|action=calweek&year=$year&month=$month">|.
                         qq|$lang_wday{$wdaynum}</a>|.
                         qq|</td>|.
                         qq|<td $bgcolor align="right" nowrap>$daydiffstr &nbsp;</td>|.
                         qq|<td $bgcolor><table width="100%" cellspacing="0" cellpadding="2">$dayhtml</table></td>|.
                         qq|</tr>\n|;
         }
      } # day loop end
   } # month loop end
   $html=~s/\@\@\@ITEMLIST\@\@\@/$temphtml/;

   print htmlheader(), 
         htmlplugin($config{'header_pluginfile'}), 
         $html, 
         htmlplugin($config{'footer_pluginfile'}), 
         htmlfooter(2);
}

# print an item in the listview
sub listview_item {
   my ($index, $r_items, $cal_url, $cgi_parm, $is_global) = @_;
   my $r_item=${$r_items}{$index};
   my $temphtml;

   my $colorstr='';
   if (defined($eventcolors{${$r_item}{'eventcolor'}})) {
      $colorstr=qq|bgcolor="#$eventcolors{${$r_item}{'eventcolor'}}"|;
   }

   my ($eventtime, $eventlink, $eventemail);
   if (${$r_item}{'starthourmin'} ne "0") {
      $eventtime = hourmin2str(${$r_item}{'starthourmin'}, $prefs{'hourformat'});
      if (${$r_item}{'endhourmin'} ne "0") {
        $eventtime .= qq|-| . hourmin2str(${$r_item}{'endhourmin'}, $prefs{'hourformat'});
      }
   } else {
      $eventtime="#";
   }
   $eventtime=qq|<font color="#c00000">$eventtime</font>&nbsp;|;
   if (${$r_item}{'link'}) {
      my $link=${$r_item}{'link'}; $link=~s/\%THISSESSION\%/$thissession/;
      $eventlink = qq|&nbsp;|. iconlink("cal-link.gif", "${$r_item}{'link'}", qq|href="$link" target="_blank"|);
   }
   if (${$r_item}{'email'}) {
      $eventemail = qq|&nbsp;|. iconlink("email.gif", "${$r_item}{'email'}", "");
   }
   my ($jsedit, $jsdel)=('','');
   if (${$r_item}{'idate'} =~ m/[\*|,|\|]/) {
      $jsedit = qq|onclick="return confirm('$lang_text{multieditconf}')"|;
      $jsdel = qq|onclick="return confirm('$lang_text{multidelconf}')"|;
   } else {
      $jsdel = qq|onclick="return confirm('$lang_text{caldelconf}')"|;
   }

   my $s=${$r_item}{'string'};
   my $nohtml=$s; $nohtml=~ s/<.*?>//g;
   $s=substr($nohtml, 0, 56)."..." if (length($nohtml)>60);

   if ($is_global) {
      $temphtml.=qq|<td $colorstr width="120" nowrap>$eventtime</td>\n|.
                 qq|<td $colorstr>$s *|.
                 $eventlink.$eventemail.
                 qq|</td>\n|;
   } else {
      $temphtml.=qq|<td $colorstr width="120" nowrap>$eventtime</td>\n|.
                 qq|<td $colorstr><a title="$lang_text{'edit'}" href="$cal_url|.qq|action=caledit$cgi_parm" $jsedit>$s</a>|.
                 $eventlink.$eventemail.
                 qq|&nbsp;&nbsp;|. iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="${cal_url}action=caldel&index=$index$cgi_parm" $jsdel|).
                 qq|</td>\n|;
   }
   $temphtml=qq|<tr $colorstr>$temphtml</tr>|;
   return($temphtml);
}
######################## END LISTVIEW #########################

######################## EDIT_ITEM #########################
# display the edit menu of an event
sub edit_item {
   my ($year, $month, $day, $index)=@_;

   my ($html, $temphtml);
   $html = readtemplate("editcalendar.template");
   $html = applystyle($html);

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   if (! defined($items{$index}) ) {
      openwebmailerror("$lang_text{'calendar'} $index $lang_err{'doesnt_exist'}");
      writelog("edit calitem error - item missing, index=$index");
      writehistory("edit calitem error - item missing, index=$index");
   }

   $temphtml = formatted_date($year, $month, $day);
   $html =~ s/\@\@\@DATE\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl",
                         -name=>'editcalendar');
   $temphtml .= hidden(-name=>'sessionid',
                       -value=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -value=>$folder,
                       -override=>'1');
   $temphtml .= hidden(-name=>'message_id',
                       -default=>$messageid,
                       -override=>'1');
   $temphtml .= hidden(-name=>'action',
                       -value=>'calupdate',
                       -override=>'1');
   $temphtml .= hidden(-name=>'year',
                       -value=>$year,
                       -override=>'1');
   $temphtml .= hidden(-name=>'month',
                       -value=>$month,
                       -override=>'1');
   $temphtml .= hidden(-name=>'day',
                       -value=>$day,
                       -override=>'1');
   $temphtml .= hidden(-name=>'index',
                       -value=>$index,
                       -override=>'1');
   if (defined(param('callist'))) {
      $temphtml .= hidden(-name=>'callist',
                          -value=>1,
                          -override=>'1');
   }
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'string',
                         -default=>$items{$index}{'string'},
                         -size=>'32',
                         -override=>'1');
   $html =~ s/\@\@\@STRINGFIELD\@\@\@/$temphtml/;

   my @hourlist;
   if ($prefs{'hourformat'}==12) {
      @hourlist=qw(none 1 2 3 4 5 6 7 8 9 10 11 12);
   } else {
      @hourlist=qw(none 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23);
   }
   my %numlabels=( none=>$lang_text{'none'},
                   0=>'00', 1=>'01', 2=>'02', 3=>'03', 4=>'04',
                   5=>'05', 6=>'06', 7=>'07', 8=>'08', 9=>'09');
   my $temphtml2;

   my ($starthour, $startmin, $startampm)=('none', 0, 'am');
   if ($items{$index}{'starthourmin'} =~ /0*(\d+)(\d{2})$/) {
      ($starthour, $startmin)=($1, $2);
      ($starthour, $startampm)=hour24to12($starthour) if ($prefs{'hourformat'}==12);
   }

   $temphtml = $lang_text{'calfmt_hourminampm'};
   $temphtml2 = popup_menu(-name=>'starthour',
                          -values=>\@hourlist,
                          -default=>$starthour,
                          -labels=>\%numlabels);
   $temphtml2 .= "<B>:</B>";
   $temphtml2 .= popup_menu(-name=>'startmin',
                           -values=>[0,5,10,15,20,25,30,35,40,45,50,55],
                           -default=>$startmin,
                           -labels=>\%numlabels);
   $temphtml =~ s/\@\@\@HOURMIN\@\@\@/$temphtml2/;
   if ($prefs{'hourformat'}==12) {
      $temphtml2 = popup_menu(-name=>'startampm',
                              -values=>['am','pm'],
                              -default=>$startampm,
                              -labels=>{ am=>$lang_text{'am'}, pm=>$lang_text{'pm'} } );
   } else {
      $temphtml2 = '';
   }
   $temphtml =~ s/\@\@\@AMPM\@\@\@/$temphtml2/;
   $html =~ s/\@\@\@STARTHOURMINMENU\@\@\@/$temphtml/;

   my ($endhour, $endmin, $endampm)=('none', 0, 'am');
   if ($items{$index}{'endhourmin'} =~ /0*(\d+)(\d{2})$/) {
      ($endhour, $endmin)=($1, $2);
      ($endhour, $endampm)=hour24to12($endhour) if ($prefs{'hourformat'}==12);
   }

   $temphtml = $lang_text{'calfmt_hourminampm'};
   $temphtml2 = popup_menu(-name=>'endhour',
                           -values=>\@hourlist,
                           -default=>$endhour,
                           -labels=>\%numlabels);
   $temphtml2 .= "<B>:</B>";
   $temphtml2 .= popup_menu(-name=>'endmin',
                            -values=>[0,5,10,15,20,25,30,35,40,45,50,55],
                            -default=>$endmin,
                            -labels=>\%numlabels);
   $temphtml =~ s/\@\@\@HOURMIN\@\@\@/$temphtml2/;
   if ($prefs{'hourformat'}==12) {
      $temphtml2 = popup_menu(-name=>'endampm',
                              -values=>['am','pm'],
                              -default=>$endampm,
                              -labels=>{ am=>$lang_text{'am'}, pm=>$lang_text{'pm'} } );
   } else {
      $temphtml2 = '';
   }
   $temphtml =~ s/\@\@\@AMPM\@\@\@/$temphtml2/;
   $html =~ s/\@\@\@ENDHOURMINMENU\@\@\@/$temphtml/;

   my $linkstr=$items{$index}{'link'};
   $linkstr="" if ($linkstr eq "0");
   $temphtml = textfield(-name=>'link',
                         -default=>$linkstr,
                         -size=>'32',
                         -override=>'1');
   $html =~ s/\@\@\@LINKFIELD\@\@\@/$temphtml/;

   my $emailstr=$items{$index}{'email'};
   $emailstr="" if ($emailstr eq "0");

   if ($config{'calendar_email_notifyinterval'} > 0 ) {
      $html =~ s/\@\@\@EMAILSTART\@\@\@//;
      $html =~ s/\@\@\@EMAILEND\@\@\@//;
      $temphtml = textfield(-name=>'email',
                            -default=>$emailstr,
                            -size=>'32',
                            -override=>'1');
      $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;
   } else {
      $temphtml = hidden(-name=>'email',
                         -value=>$emailstr,
                         -override=>'1');
      $html =~ s/\@\@\@EMAILSTART\@\@\@/$temphtml<!--/;
      $html =~ s/\@\@\@EMAILEND\@\@\@/-->/;
      $html =~ s/\@\@\@EMAILFIELD\@\@\@//;
   }

   $temphtml = qq|<table><tr>|;
   $temphtml .= qq|<td>|.popup_menu(-name=>'eventcolor',
                                    -values=>['none', sort keys %eventcolors],
                                    -default=>$items{$index}{'eventcolor'},
                                    -labels=>{ none=> $lang_text{'none'} } ).qq|</td>|;
   foreach (sort keys %eventcolors) {
      $temphtml .= qq|<td width=14 align=center bgcolor="#$eventcolors{$_}">|.
                   qq|<a onclick="JavaScript:document.editcalendar.eventcolor.value='$_'">$_</a></td>|;
   }
   $temphtml .= qq|<td width=14 align=center>|.
                qq|<a onclick="JavaScript:document.editcalendar.eventcolor.value='none'">--</a></td>|;
   $temphtml .= qq|</tr></table>|;
   $html =~ s/\@\@\@EVENTCOLORMENU\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'save'}");
   $html =~ s/\@\@\@SUBMITBUTTON\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-cal.pl",
                         -name=>'cancelform');
   $temphtml .= hidden(-name=>'sessionid',
                       -value=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -value=>$folder,
                       -override=>'1');
   $temphtml .= hidden(-name=>'message_id',
                       -default=>$messageid,
                       -override=>'1');
   $temphtml .= hidden(-name=>'year',
                       -value=>$year,
                       -override=>'1');
   if (defined(param('callist'))) {
      $temphtml .= hidden(-name=>'action',
                          -value=>'callist',
                          -override=>'1');
   } else {
      $temphtml .= hidden(-name=>'month',
                          -value=>$month,
                          -override=>'1');
      $temphtml .= hidden(-name=>'day',
                          -value=>$day,
                          -override=>'1');
      $temphtml .= hidden(-name=>'action',
                          -value=>'calday',
                          -override=>'1');
   }
   $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'cancel'}");
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   print htmlheader(), $html, htmlfooter(2);
}
######################## END EDIT_ITEM #########################

######################## ADD_ITEM #########################
# add an item to user calendar
sub add_item {
   my ($year, $month, $day,
       $string,
       $starthour, $startmin, $startampm,
       $endhour, $endmin, $endampm,
       $dayfreq,
       $thisandnextndays, $ndays,
       $monthfreq,
       $everyyear,
       $link, $email, $eventcolor)=@_;
   my $line;
   return if ($string=~/^\s?$/);

   # check for bad input that would kill our database format
   if ($string =~ /\@\@\@/) {
      openwebmailerror("$lang_err{'pipe_char_not_allowed'}");
   }
   if ($link =~ /\@\@\@/) {
      openwebmailerror("$lang_err{'pipe_char_not_allowed'}");
   }
   # check for bad input that would confuse our database format
   if ($string =~ /\@$/) {
      $string=$string." ";
   } elsif ($string =~ /^\@/) {
      $string=" ".$string;
   }
   if ($link =~ /\@$/) {
      $link=$link." ";
   } elsif ($link =~ /^\@/) {
      $link=" ".$link;
   }
   $link=~s/\Q$thissession\E/\%THISSESSION\%/;
   $link=0 if ($link !~ m!://[^\s]+!);
   $email=0 if ($email !~ m![^\s@]+@[^\s@]+!);

   # translate time format to military time.
   my $starthourmin=0;
   my $endhourmin=0;
   if ($starthour =~ /\d+/) {
      if ($prefs{'hourformat'}==12) {
         $starthour+=12 if ($startampm eq "pm" && $starthour< 12);
         $starthour=0   if ($startampm eq "am" && $starthour==12);
      }
      $starthourmin = sprintf("%02d%02d", $starthour,$startmin);
   }
   if ($endhour =~ /\d+/) {
      if ($prefs{'hourformat'}==12) {
         $endhour+=12 if ($endampm eq "pm" && $endhour< 12);
         $endhour=0   if ($endampm eq "am" && $endhour==12);
      }
      $endhourmin = sprintf("%02d%02d", $endhour,$endmin);
   }

   my ($item_count, %items, %indexes);
   if ( ($item_count=readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)) <0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }

   my $index = $item_count+19690404;	# avoid collision with old records
   my $t = timegm(1,1,1,$day, $month-1, $year-1900);
   my $dow = $wdaystr[(gmtime($t))[6]];
   my $records = "";

   # construct the record.
   if ($dayfreq eq 'thisdayonly' && $monthfreq eq 'thismonthonly' && !$everyyear) {
      if ($thisandnextndays && $ndays) {
         if ($ndays !~ /\d+/) {
            openwebmailerror("$lang_err{'badnum_in_days'}: $ndays");
         }
         my $date_wild='(';
         for (my $i=0; $i<=$ndays; $i++) {
            my ($y, $m, $d)=(gmtime($t+86400*$i))[5,4,3];
            my $date=sprintf("%04d%02d%02d", $y+1900, $m+1, $d);
            $date_wild.='|' if ($i>0);
            $date_wild.=sprintf("%04d%02d%02d", $y+1900, $m+1, $d);
         }
         $date_wild.=')';
         $items{$index}{'idate'}=$date_wild;
      } else {
         $items{$index}{'idate'}=sprintf("%04d%02d%02d", $year, $month, $day);
      }

   } elsif ($dayfreq eq 'thewdayofthismonth') {
      my $year_wild=sprintf("%04d", $year);
      my $month_wild=sprintf("%02d", $month);
      my $day_wild=sprintf("%02d", $day);

      $year_wild = ".*" if ($everyyear);
      if ($monthfreq eq 'everyoddmonththisyear') {
         $month_wild="(01|03|05|07|09|11)";
      } elsif ($monthfreq eq 'everyevenmonththisyear') {
         $month_wild="(02|04|06|08|10|12)";
      } elsif ($monthfreq eq 'everymonththisyear') {
         $month_wild = ".*";
      }
      my %weekorder_day_wild= ( 1 => "0[1-7]",
                                2 => "((0[8-9])|(1[0-4]))",
                                3 => "((1[5-9])|(2[0-1]))",
                                4 => "2[2-8]" );
      my $weekorder=int(($day+6)/7);
      $day_wild=$weekorder_day_wild{$weekorder} if ($weekorder_day_wild{$weekorder} ne "");

      $items{$index}{'idate'}="$year_wild,$month_wild,$day_wild,$dow";

   } else { # everywdaythismonth and else...
      my $year_wild=sprintf("%04d", $year);
      my $month_wild=sprintf("%02d", $month);

      $year_wild = ".*" if ($everyyear);
      if ($monthfreq eq 'everyoddmonththisyear') {
         $month_wild="(01|03|05|07|09|11)";
      } elsif ($monthfreq eq 'everyevenmonththisyear') {
         $month_wild="(02|04|06|08|10|12)";
      } elsif ($monthfreq eq 'everymonththisyear') {
         $month_wild = ".*";
      }

      if ($dayfreq eq 'everywdaythismonth') {
         $items{$index}{'idate'}="$year_wild,$month_wild,.*,$dow";
      } else {
         my $daystr=sprintf("%02d", $day);
         $items{$index}{'idate'}="$year_wild,$month_wild,$daystr,.*";
      }
   }

   $items{$index}{'starthourmin'}="$starthourmin"; # " is required or "0000" will be treated as 0?
   $items{$index}{'endhourmin'}="$endhourmin";
   $items{$index}{'string'}=$string;
   $items{$index}{'link'}=$link;
   $items{$index}{'email'}=$email;
   $items{$index}{'eventcolor'}=$eventcolor;

   if ( writecalbook("$folderdir/.calendar.book", \%items) <0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }

   reset_notifycheck_for_newitem($items{$index});

   my $msg="add calitem - start=$starthourmin, end=$endhourmin, str=$string";
   writelog($msg);
   writehistory($msg);
}
######################## END ADD_ITEM #########################

######################## DEL_ITEM #########################
# delete an item from user calendar
sub del_item {
   my $index=$_[0];

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   return if (! defined($items{$index}) );

   my $msg="delete calitem - index=$index, t=$items{$index}{'starthourmin'}, str=$items{$index}{'string'}";
   delete $items{$index};
   if ( writecalbook("$folderdir/.calendar.book", \%items) <0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   writelog($msg);
   writehistory($msg);
}
######################## END DEL_ITEM #########################

######################## UPDATE_ITEM #########################
# update an item in user calendar
sub update_item {
   my ($index, $string,
       $starthour, $startmin, $startampm,
       $endhour, $endmin, $endampm,
       $link, $email, $eventcolor)=@_;
   my $line;

   return if ($string=~/^\s?$/);

   # check for valid input
   if ($string =~ /\@{3}/) {
      openwebmailerror("$lang_err{'at_char_not_allowed'}");
   }
   if ($link =~ /\@{3}/) {
      openwebmailerror("$lang_err{'at_char_not_allowed'}");
   }
   # check for bad input that would confuse our database format
   if ($string =~ /\@$/) {
      $string=$string." ";
   } elsif ($string =~ /^\@/) {
      $string=" ".$string;
   }
   if ($link =~ /\@$/) {
      $link=$link." ";
   } elsif ($link =~ /^\@/) {
      $link=" ".$link;
   }
   $link=~s/\Q$thissession\E/\%THISSESSION\%/;
   $link=0 if ($link !~ m!://[^\s]+!);
   $email=0 if ($email !~ m![^\s@]+@[^\s@]+!);

   # translate time format to military time.
   my $starthourmin=0;
   my $endhourmin=0;
   if ($starthour =~ /\d+/) {
      if ($prefs{'hourformat'}==12) {
         $starthour+=12 if ($startampm eq "pm" && $starthour< 12);
         $starthour=0   if ($startampm eq "am" && $starthour==12);
      }
      $starthourmin = sprintf("%02d%02d", $starthour,$startmin);
   }
   if ($endhour =~ /\d+/) {
      if ($prefs{'hourformat'}==12) {
         $endhour+=12 if ($endampm eq "pm" && $endhour< 12);
         $endhour=0   if ($endampm eq "am" && $endhour==12);
      }
      $endhourmin = sprintf("%02d%02d", $endhour,$endmin);
   }

   my (%items, %indexes);
   if ( readcalbook("$folderdir/.calendar.book", \%items, \%indexes, 0)<0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }
   if (! defined($items{$index}) ) {
      openwebmailerror("$lang_text{'calendar'} $index $lang_err{'doesnt_exist'}");
      writelog("update calitem error - item missing, index=$index");
      writehistory("update calitem error - item missing, index=$index");
   }

   $items{$index}{'starthourmin'}="$starthourmin"; # " is required or "0000" will be treated as 0?
   $items{$index}{'endhourmin'}="$endhourmin";
   $items{$index}{'string'}=$string;
   $items{$index}{'link'}=$link;
   $items{$index}{'email'}=$email;
   $items{$index}{'eventcolor'}=$eventcolor;

   if ( writecalbook("$folderdir/.calendar.book", \%items) <0 ) {
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.calendar.book");
   }

   reset_notifycheck_for_newitem($items{$index});

   my $msg="update calitem - index=$index, start=$starthourmin, end=$endhourmin, str=$string";
   writelog($msg);
   writehistory($msg);
}
######################## END UPDATE_ITEM #########################

######################## SET_DAYS_IN_MONTH #########################
# set the day number of each cell in the month calendar
sub set_days_in_month {
   my ($year, $month) = @_;

   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   if ((($year % 4) == 0) && ((($year % 100) != 0) || (($year % 400) == 0))) {
      $days_in_month[2]++;
   }

   my %wdaynum=qw(Sun 0 Mon 1 Tue 2 Wed 3 Thu 4 Fri 5 Sat 6);
   foreach (keys %wdaynum) {
      $wdaynum{$_}=($wdaynum{$_}+7-$prefs{'calendar_weekstart'})%7;
   }
   my $time = timegm("0","0","12","1",$month-1,$year-1900);
   my $weekday = gmtime($time); $weekday =~ s/^(\w+).*$/$1/;

   my @days;
   my $day_counter = 1;
   for my $x (0..5) {
      for my $y (0..6) {
         if ( ($x>0 || $y>=$wdaynum{$weekday}) &&
              $day_counter<=$days_in_month[$month] ) {
            $days[$x][$y] = $day_counter;
            $day_counter++;
         }
      }
   }
   return @days;
}
######################## END SET_DAYS_IN_MONTH #########################

######################## HOURMIN2STR #########################
# convert military time (eg:1700) to timestr (eg:05:00 pm)
sub hourmin2str {
   my ($hourmin, $hourformat) = @_;
   if ($hourmin =~ /(\d+)(\d{2})$/) {
      my ($hour, $min) = ($1, $2);
      $hour =~ s/^0(.+)/$1/;
      if ($hourformat==12) {
         my $ampm;
         ($hour, $ampm)=hour24to12($hour);
         $hourmin = $lang_text{'calfmt_hourminampm'};
         $hourmin =~ s/\@\@\@HOURMIN\@\@\@/$hour:$min/;
         $hourmin =~ s/\@\@\@AMPM\@\@\@/$lang_text{$ampm}/;
      } else {
         $hourmin = sprintf("%02d", $hour) . ":" . sprintf("%02d", $min);
      }
   }
   return $hourmin;
}
######################## END HOURMIN2STR #########################

######################## FORMATTED_DATE #########################
# convert date to language dependent str based on the format
sub formatted_date {
   my ($year, $month, $day, $wday)=@_;
   my $fmtstr;
   if (defined($wday)) {
      $fmtstr=$lang_text{'calfmt_yearmonthdaywday'};
   } elsif (defined($day)) {
      $fmtstr=$lang_text{'calfmt_yearmonthday'};
   } elsif (defined($month)) {
      $fmtstr=$lang_text{'calfmt_yearmonth'};
   } elsif (defined($year)) {
      $fmtstr=$lang_text{'calfmt_year'};
   } else {
      return("");
   }
   $fmtstr=~s/\@\@\@YEAR\@\@\@/$year/ if ($year);
   $fmtstr=~s/\@\@\@MONTH_STR\@\@\@/$lang_month{$month}/ if ($month);
   $fmtstr=~s/\@\@\@DAY\@\@\@/$day/ if ($day);

   if (defined($wday)) {
      my $wdaystr=$lang_wday{$wday};
      if ($wday==0) {
         $wdaystr=qq|<font color=#cc0000>$wdaystr</font>|; # sunday
      } elsif ($wday==6) {
         $wdaystr=qq|<font color=#00aa00>$wdaystr</font>|; #saturday
      }
      $fmtstr=~s/\@\@\@WEEKDAY_STR\@\@\@/&nbsp;$wdaystr&nbsp;/;
   }

   return($fmtstr);
}
######################## END FORMATTED_DATE #########################

########################## LUNAR_MONTHDAY #############################
# convert gregorian date to lunar str in big5
sub lunar_str {
   my ($year, $month, $day, $charset)=@_;
   my $str="";
   if ($charset eq "big5" || $charset eq "gb2312") {
      $str=(solar2lunar($year, $month, $day))[1];
      if ($str ne "") {
         my $color="";
         $color=qq|color="#aaaaaa"| if ($str!~/ªì¤@/ && $str!~/¤Q¤­/);
         $str=b2g($str) if ($charset eq "gb2312");
         $str=qq|<font size=1 $color>$str</font>|;
      }
   }
   return($str);
}
######################## END LUNAR_MONTHDAY ###########################

###################### RESET_NOTIFYCHECK_FOR_NEWITEM #################
# reset the lastcheck date in .notify.check
# if any item added with date before the lastcheck date
sub reset_notifycheck_for_newitem {
   my $r_item=$_[0];
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

   if ( ${$r_item}{'email'} &&
        ($date=~/${$r_item}{'idate'}/ || $date2=~/${$r_item}{'idate'}/) ) {
      if ( -f "$folderdir/.notify.check" ) {
         open (NOTIFYCHECK, "$folderdir/.notify.check" ) or return -1; # read err
         my $lastcheck=<NOTIFYCHECK>;
         close (NOTIFYCHECK);
         if ($lastcheck=~/$date(\d\d\d\d)/) {
            if (${$r_item}{'starthourmin'} < $1) {
               open (NOTIFYCHECK, ">$folderdir/.notify.check" ) or return -1; # write err
               print NOTIFYCHECK sprintf("%08d%04d", $date, ${$r_item}{'starthourmin'});
               truncate(NOTIFYCHECK, tell(NOTIFYCHECK));
               close (NOTIFYCHECK);
            }
         }
      }
   }
   return 0;
}
################### END RESET_NOTIFYCHECK_FOR_NEWITEM ################
