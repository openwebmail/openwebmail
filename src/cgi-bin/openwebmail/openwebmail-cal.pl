#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2008, The OpenWebMail Project
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

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/htmltext.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/lunar.pl";
require "shares/iconv.pl";
require "shares/iconv-chinese.pl";
require "shares/calbook.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config);
use vars qw($thissession);
use vars qw(%prefs);

# extern vars
use vars qw($htmltemplatefilters); # defined in ow-shared.pl
use vars qw(%lang_folders %lang_text %lang_err);	# defined in lang/xy
use vars qw(%lang_month %lang_wday_abbrev %lang_wday %lang_order); # defined in lang/xy

# local globals
use vars qw($folder $sort $msgdatetype $page $longpage $keyword $searchtype);
use vars qw($messageid);
use vars qw(@slottime);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(__FILE__, __LINE__, "$lang_text{'calendar'} $lang_err{'access_denied'}") if !$config{'enable_calendar'};

my $action   = param('action') || '';

$folder      = param('folder') || 'INBOX';
$sort        = param('sort') || $prefs{sort} || 'date_rev';
$msgdatetype = param('msgdatetype') || $prefs{msgdatetype};
$page        = param('page') || 1;
$longpage    = param('longpage') || 0;
$searchtype  = param('searchtype') || 'subject';
$keyword     = param('keyword') || '';
$messageid   = param('message_id') ||'';

# init global @slottime
@slottime=();
for my $h (0..23) {
   for (my $m=0; $m<60 ; $m=$m+$prefs{'calendar_interval'}) {
      push(@slottime, sprintf("%02d%02d", $h, $m));
   }
}
push(@slottime, "2400");

# event background colors
my %eventcolors=( '1a'=>'b0b0e0', '1b'=>'b0e0b0', '1c'=>'b0e0e0',
                  '1d'=>'e0b0b0', '1e'=>'e0b0e0', '1f'=>'e0e0b0',
                  '2a'=>'9090f8', '2b'=>'90f890', '2c'=>'90f8f8',
                  '2d'=>'f89090', '2e'=>'f890f8', '2f'=>'f8f890');

my $year=param('year')||'';
my $month=param('month')||'';
my $day=param('day')||'';
if (defined param('daybutton')) {
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
my $dayfreq=param('dayfreq')||'thisdayonly';
my $thisandnextndays=param('thisandnextndays')||0;
my $ndays=param('ndays')||0;
my $monthfreq=param('monthfreq')||0;
my $everyyear=param('everyyear')||0;
my $eventcolor=param('eventcolor')||'none';
my $eventreminder=param('eventreminder');

writelog("debug - request cal begin, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
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
            $link, $email, $eventcolor, $eventreminder);
   dayview($year, $month, $day);
} elsif ($action eq "caldel") {
   del_item($index);
   if (defined param('callist')) {
      listview($year);
   } else {
      dayview($year, $month, $day);
   }
} elsif ($action eq "calupdate") {
   update_item($index,
               $year, $month, $day,
               $string,
               $starthour, $startmin, $startampm,
               $endhour, $endmin, $endampm,
               $dayfreq,
               $thisandnextndays, $ndays, $monthfreq, $everyyear,
               $link, $email, $eventcolor, $eventreminder);

   if (defined param('callist')) {
      listview($year);
   } else {
      dayview($year, $month, $day);
   }
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request cal end, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## YEARVIEW ##############################################
sub yearview {
   my $year = $_[0];

#  Common to all views

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($localtime))[5,4,3];

   $current_year += 1900; 
   my $min_year = $current_year - 30;
   my $max_year = $current_year + 30;

   $year = $current_year    if (!$year);
   $year = $max_year        if ($year > $max_year); 
   $year = $min_year        if ($year < $min_year);
   
   $current_month++;

   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++      if ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0));

   my (%items, %indexes);
   my $calbookfile = dotpath('calendar.book');

   if (readcalbook($calbookfile, \%items, \%indexes, 0) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'locale'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

#  End Common to all views

   my $prev_year = $year - 1;
   my $next_year = $year + 1;

   my @accesskey = qw(0 1 2 3 4 5 6 7 8 9 0 J Q);
   my $weeknr = 1;

   my $monthsloop = [];

   for my $month (1..12) {

      my $daysloop = [];
      my @days = set_days_in_month($year, $month, $days_in_month[$month]);

      my @eventstr;

      for my $w (0..5) {
         for my $d (0..6) {
            my $day = $days[$w][$d] || 0;
            if ($day) {
               my $wdaynum = ($prefs{'calendar_weekstart'} + $w) % 7;
               my $dow     = $ow::datetime::wday_en[$wdaynum % 7];
               my $date    = sprintf("%04d%02d%02d", $year, $month, $day);
               my $date2   = sprintf("%04d,%02d,%02d,%s", $year, $month, $day, $dow);
               my @indexlist = ();
               foreach ($date, '*') {
                  next if (!defined $indexes{$_});
                  foreach my $index (@{$indexes{$_}}) {
                     if ($date  =~ /$items{$index}{'idate'}/
                         || $date2 =~ /$items{$index}{'idate'}/
                         || ow::datetime::easter_match($year, $month, $day, $items{$index}{'idate'})) {
                        push(@indexlist, $index);
                     }
                  }
               }
               @indexlist = sort { $items{$a}{'starthourmin'} <=> $items{$b}{'starthourmin'}
                                 || $items{$a}{'endhourmin'} <=> $items{$b}{'endhourmin'}
                                 || $b <=> $a } @indexlist;

               @eventstr = ();
               for my $index (@indexlist) {
                  push(@eventstr, (iconv($items{$index}{'charset'}, $prefs{'charset'}, $items{$index}{'string'}))[0]);
               }
            }
            push(@{$daysloop}, { url_cgi       => $config{ow_cgiurl},
                                 sessionid     => $thissession,
                                 message_id    => $messageid,
                                 folder        => $folder,
                                 year          => $year,          
                                 month         => $month,
                                 day           => $day,
                                 today         => ($year == $current_year && $month == $current_month && $day == $current_day) ? 1 : 0,
                                 weeknr        => (($d == 0) && ($days[$w][0] || $days[$w][6])) ? $weeknr : 0,
                                 eventstr      => join(" / ", @eventstr),
                                 newrow        => $d == 6 ? 1 : 0,
                              });
            $weeknr++ if ($d == 6 && $day);
         }
      }

      push(@{$monthsloop}, { url_cgi       => $config{ow_cgiurl},
                             sessionid     => $thissession,
                             message_id    => $messageid,
                             folder        => $folder,
                             uselightbar   => $prefs{'uselightbar'},
                             year          => $year,
                             month         => $month,
                             monthname     => $lang_month{$month},
                             thismonth     => ($year == $current_year && $month == $current_month) ? 1 : 0,
                             accesskey     => $accesskey[$month],
                             newrow        => $month % 4 == 0 ? 1 : 0,
                             wdheadersloop => [
                                                map { my $n = ($prefs{'calendar_weekstart'} + $_) % 7;
                                                      { wdheader    => $lang_wday_abbrev{$n} } 
                                                    } @{[0..6]}
                                              ],
                             daysloop      => $daysloop,
                          });
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_yearview.tmpl"),
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
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./?1:0),
                      url_html                => $config{ow_htmlurl},
                      url_cgi                 => $config{ow_cgiurl},
                      iconset                 => $prefs{iconset},
                      sessionid               => $thissession,
                      message_id              => $messageid,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,

                      # cal_yearview.tmpl
                      enable_preference       => $config{enable_preference},
                      enable_webmail          => $config{enable_webmail},
                      enable_addressbook      => $config{enable_addressbook},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      year                    => $year,
                      month                   => $month,
                      day                     => $current_day,
                      current_year            => $current_year,
                      not_current             => $current_year != $year ? 1 : 0,
                      prev_year               => $prev_year,
                      next_year               => $next_year,
                      monthname               => $lang_month{$current_month},
                      yearselectloop          => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $year ? 1 : 0
                                                       } } @{[$min_year..$max_year]}
                                                 ],
                      monthsloop              => $monthsloop,
                      
                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);

}
########## END YEARVIEW ##########################################

########## MONTHVIEW #############################################
sub monthview {
   my ($year, $month) = @_;

#  Common to all views

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($localtime))[5,4,3];

   $current_year += 1900; 
   my $min_year = $current_year - 30;
   my $max_year = $current_year + 30;

   $year = $current_year    if (!$year);
   $year = $max_year        if ($year > $max_year); 
   $year = $min_year        if ($year < $min_year);
   
   $current_month++;

   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++      if ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0));

   my (%items, %indexes);
   my $calbookfile = dotpath('calendar.book');

   if (readcalbook($calbookfile, \%items, \%indexes, 0) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'locale'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

#  End Common to all views

   $month = $current_month       if (!$month);
   $month = 12                   if ($month > 12); 
   $month = 1                    if ($month < 1);

   my ($prev_year, $prev_month) = $month == 1  ? ($year - 1, 12) : ($year, $month - 1);
   my ($next_year, $next_month) = $month == 12 ? ($year + 1, 1)  : ($year, $month + 1);

   my $daysloop = [];
   my @days = set_days_in_month($year, $month, $days_in_month[$month]);

   for my $w (0..5) {
      for my $d (0..6) {
         my ($lunar, $lunarnew);
         my $day        = $days[$w][$d];
         my $eventcount = 0;
         my $eventsloop = [];

         if ($day) {
            my $t       = ow::datetime::array2seconds(1, 1, 1, $day, $month - 1, $year - 1900);
            my $dow     = $ow::datetime::wday_en[(ow::datetime::seconds2array($t))[6]];
            my $date    = sprintf("%04d%02d%02d", $year, $month, $day);
            my $date2   = sprintf("%04d,%02d,%02d,%s", $year, $month, $day, $dow);
            ($lunar, $lunarnew) = lunar_day($year, $month, $day, $prefs{'charset'});

            my @indexlist = ();
            foreach ($date, '*') {
               next if (!defined $indexes{$_});
               foreach my $index (@{$indexes{$_}}) {
                  if (  $date  =~ /$items{$index}{'idate'}/ 
                     || $date2 =~ /$items{$index}{'idate'}/ 
                     || ow::datetime::easter_match($year, $month, $day, $items{$index}{'idate'})) {
                     push(@indexlist, $index);
                  }
               }
            }
            @indexlist = sort { $items{$a}{'starthourmin'} <=> $items{$b}{'starthourmin'}
                               || $items{$a}{'endhourmin'} <=> $items{$b}{'endhourmin'}
                               || $b <=> $a } @indexlist;
            for my $index (@indexlist) {
               if ($eventcount < $prefs{'calendar_monthviewnumitems'}) {
                  my ($eventtime, 
                      $eventlink, 
                      $eventlinktxt, 
                      $eventemail, 
                      $eventtxt, 
                      $eventcolor,
                      $idate) = parse_event($items{$index}, ($index >= 1E6));

                  push(@{$eventsloop}, { use_texticon  => $prefs{iconset} =~ m/^Text\./ ? 1 : 0,
                                         url_html      => $config{ow_htmlurl},
                                         iconset       => $prefs{iconset},
                                         eventtime     => $eventtime,    
                                         eventlink     => $eventlink,    
                                         eventlinktxt  => $eventlinktxt, 
                                         eventemail    => $eventemail,   
                                         eventtxt      => $eventtxt,     
                                         eventcolor    => $eventcolor
                                       });
               }
               $eventcount++;
            }
         }
         $day = 0 if (!defined($day));
         push(@{$daysloop}, { url_cgi     => $config{ow_cgiurl},
                              sessionid   => $thissession,
                              message_id  => $messageid,
                              folder      => $folder,
                              uselightbar => $prefs{'uselightbar'},
                              day         => $day,
                              month       => $month,
                              year        => $year,
                              daystr      => sprintf("%2d", $day),
                              lunar       => $lunar,
                              lunarnew    => $lunarnew,
                              today       => ($year == $current_year && $month == $current_month && $day == $current_day) ? 1 : 0,
                              newrow      => $d == 6 ? 1 : 0,
                              has_event   => $eventcount,
                              more_events => $eventcount > $prefs{'calendar_monthviewnumitems'} ? 1 : 0,
                              eventsloop  => $eventsloop
                           });
      }
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_monthview.tmpl"),
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
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./?1:0),
                      url_html                => $config{ow_htmlurl},
                      url_cgi                 => $config{ow_cgiurl},
                      iconset                 => $prefs{iconset},
                      sessionid               => $thissession,
                      message_id              => $messageid,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,

                      # cal_monthview.tmpl
                      enable_preference       => $config{enable_preference},
                      enable_webmail          => $config{enable_webmail},
                      enable_addressbook      => $config{enable_addressbook},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      year                    => $year,
                      month                   => $month,
                      day                     => $current_day,
                      current_year            => $current_year,
                      current_month           => $current_month,
                      not_current             => (($current_year != $year) || ($current_month != $month)) ? 1 : 0,
                      prev_year               => $prev_year,
                      prev_month              => $prev_month,
                      next_year               => $next_year,
                      next_month              => $next_month,
                      prev_monthname          => $lang_month{$prev_month}, 
                      next_monthname          => $lang_month{$next_month},
                      current_monthname       => $lang_month{$current_month},
                      monthname               => $lang_month{$month},
                      monthselectloop         => [
                                                   map { {
                                                            option      => $_,
                                                            label       => $lang_month{$_},
                                                            selected    => $_ eq $month ? 1 : 0
                                                       } } @{[1..12]}
                                                 ],
                      yearselectloop          => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $year ? 1 : 0
                                                       } } @{[$min_year..$max_year]}
                                                 ],
                      calheaderloop           => [
                                                   map { my $n = ($prefs{'calendar_weekstart'} + $_) % 7;
                                                       {
                                                            weekday     => $lang_wday{$n},
                                                            saturday    => $n == 6 ? 1 : 0,
                                                            sunday      => $n == 0 ? 1 : 0
                                                       } } @{[0..6]}
                                                 ],
                      daysloop                => $daysloop,
                      
                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);

}
########## END MONTHVIEW #########################################


########## WEEKVIEW ##############################################
sub weekview {
   my ($year, $month, $day) = @_;

#  Common to all views

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($localtime))[5,4,3];

   $current_year  += 1900; 
   my $min_year = $current_year - 30;
   my $max_year = $current_year + 30;

   $year = $current_year    if (!$year);
   $year = $max_year        if ($year > $max_year); 
   $year = $min_year        if ($year < $min_year);

   $current_month++;

   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++      if ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0));

   my (%items, %indexes);
   my $calbookfile = dotpath('calendar.book');

   if (readcalbook($calbookfile, \%items, \%indexes, 0) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'locale'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

#  End Common to all views

   $month = $current_month       if (!$month);
   $month = 12                   if ($month > 12); 
   $month = 1                    if ($month < 1);
   $day = $current_day           if (!$day);
   $day = $days_in_month[$month] if ($day > $days_in_month[$month]); 
   $day = 1                      if ($day < 1);

   my $time = ow::datetime::array2seconds(0, 0, 12, $day, $month - 1, $year - 1900);
   my ($prev_year, $prev_month, $prev_day) = (ow::datetime::seconds2array($time - 86400 * 7))[5,4,3];
   my ($next_year, $next_month, $next_day) = (ow::datetime::seconds2array($time + 86400 * 7))[5,4,3];

   $prev_month++;
   $next_month++;

   $prev_year     += 1900;
   $next_year     += 1900;

   my $wdaynum = (ow::datetime::seconds2array($time))[6];
   my $start_time = $time - 86400 * (($wdaynum + 7 - $prefs{'calendar_weekstart'}) % 7);

   my $daysloop = [];

   for my $d (0..6) {
      my $eventcount = 0;
      my $eventsloop = [];

      my ($year, $month, $day) = (ow::datetime::seconds2array($start_time + $d * 86400))[5,4,3];
      $year += 1900;
      $month++;

      my $t       = ow::datetime::array2seconds(1, 1, 1, $day, $month - 1, $year - 1900);
      my $dow     = $ow::datetime::wday_en[(ow::datetime::seconds2array($t))[6]];
      my $date    = sprintf("%04d%02d%02d", $year, $month, $day);
      my $date2   = sprintf("%04d,%02d,%02d,%s", $year, $month, $day, $dow);
      my ($lunar, $lunarnew) = lunar_day($year, $month, $day, $prefs{'charset'});

      my @indexlist=();
      foreach ($date, '*') {
         next if (!defined $indexes{$_});
         foreach my $index (@{$indexes{$_}}) {
            if (  $date  =~ /$items{$index}{'idate'}/
               || $date2 =~ /$items{$index}{'idate'}/
               || ow::datetime::easter_match($year, $month, $day, $items{$index}{'idate'})) {
               push(@indexlist, $index);
            }
         }
      }
      @indexlist = sort { $items{$a}{'starthourmin'} <=> $items{$b}{'starthourmin'}
                         || $items{$a}{'endhourmin'} <=> $items{$b}{'endhourmin'}
                         || $b <=> $a } @indexlist;
      for my $index (@indexlist) {
         if ($eventcount < $prefs{'calendar_monthviewnumitems'}) {
            my ($eventtime, 
                $eventlink, 
                $eventlinktxt, 
                $eventemail, 
                $eventtxt, 
                $eventcolor,
                $idate) = parse_event($items{$index}, ($index>=1E6));

            push(@{$eventsloop}, { use_texticon  => $prefs{iconset} =~ m/^Text\./ ? 1 : 0,
                                   url_html      => $config{ow_htmlurl},
                                   iconset       => $prefs{iconset},
                                   eventtime     => $eventtime,    
                                   eventlink     => $eventlink,    
                                   eventlinktxt  => $eventlinktxt, 
                                   eventemail    => $eventemail,   
                                   eventtxt      => $eventtxt,     
                                   eventcolor    => $eventcolor
                                 });
         }
         $eventcount++;
      }
      push(@{$daysloop}, { url_cgi     => $config{ow_cgiurl},
                           sessionid   => $thissession,
                           message_id  => $messageid,
                           folder      => $folder,
                           uselightbar => $prefs{'uselightbar'},
                           day         => $day,
                           month       => $month,
                           year        => $year,
                           daystr      => sprintf("%2d", $day),
                           lunar       => $lunar,
                           lunarnew    => $lunarnew,
                           today       => ($year == $current_year && $month == $current_month && $day == $current_day) ? 1 : 0,
                           has_event   => $eventcount,
                           eventsloop  => $eventsloop
                        });
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_weekview.tmpl"),
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
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./?1:0),
                      url_html                => $config{ow_htmlurl},
                      url_cgi                 => $config{ow_cgiurl},
                      iconset                 => $prefs{iconset},
                      sessionid               => $thissession,
                      message_id              => $messageid,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,

                      # cal_weekview.tmpl
                      enable_preference       => $config{enable_preference},
                      enable_webmail          => $config{enable_webmail},
                      enable_addressbook      => $config{enable_addressbook},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      year                    => $year,
                      month                   => $month,
                      current_day             => $current_day,
                      day                     => $day,
                      current_year            => $current_year,
                      current_month           => $current_month,
                      not_current             => (($current_year != $year) || ($current_month != $month) || ($current_day != $day)) ? 1 : 0,
                      min_year                => $min_year,
                      prev_year               => $prev_year,
                      prev_month              => $prev_month,
                      prev_day                => $prev_day,
                      next_year               => $next_year,
                      next_month              => $next_month,
                      next_day                => $next_day,
                      prev_monthname          => $lang_month{$prev_month}, 
                      next_monthname          => $lang_month{$next_month},
                      current_monthname       => $lang_month{$current_month},
                      monthname               => $lang_month{$month},
                      weekstart               => $prefs{'calendar_weekstart'},
                      dayselectloop           => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $day ? 1 : 0
                                                       } } @{[1..$days_in_month[$month]]}
                                                 ],
                      monthselectloop         => [
                                                   map { {
                                                            option      => $_,
                                                            label       => $lang_month{$_},
                                                            selected    => $_ eq $month ? 1 : 0
                                                       } } @{[1..12]}
                                                 ],
                      yearselectloop          => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $year ? 1 : 0
                                                       } } @{[$min_year..$max_year]}
                                                 ],
                      calheaderloop           => [
                                                   map { my $n = ($prefs{'calendar_weekstart'} + $_) % 7;
                                                       {
                                                            weekday     => $lang_wday{$n},
                                                            saturday    => $n == 6 ? 1 : 0,
                                                            sunday      => $n == 0 ? 1 : 0
                                                       } } @{[0..6]}
                                                 ],
                      daysloop                => $daysloop,
                      
                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);

}

########## END WEEKVIEW ##########################################

########## DAYVIEW ###############################################
sub dayview {
   my ($year, $month, $day) = @_;

#  Common to all views

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($localtime))[5,4,3];

   $current_year  += 1900; 
   my $min_year = $current_year - 30;
   my $max_year = $current_year + 30;

   $year = $current_year    if (!$year);
   $year = $max_year        if ($year > $max_year); 
   $year = $min_year        if ($year < $min_year);

   $current_month++;

   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++      if ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0));

   my (%items, %indexes);
   my $calbookfile = dotpath('calendar.book');

   if (readcalbook($calbookfile, \%items, \%indexes, 0) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'locale'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

#  End Common to all views

   $month = $current_month       if (!$month);
   $month = 12                   if ($month > 12); 
   $month = 1                    if ($month < 1);
   $day = $current_day           if (!$day);
   $day = $days_in_month[$month] if ($day > $days_in_month[$month]); 
   $day = 1                      if ($day < 1);

   my $time = ow::datetime::array2seconds(0, 0, 12, $day, $month - 1, $year - 1900);
   my ($prev_year, $prev_month, $prev_day) = (ow::datetime::seconds2array($time - 86400))[5,4,3];
   my ($next_year, $next_month, $next_day) = (ow::datetime::seconds2array($time + 86400))[5,4,3];

   $prev_month++;
   $next_month++;

   $prev_year     += 1900;
   $next_year     += 1900;

   my $t       = ow::datetime::array2seconds(1, 1, 1, $day, $month - 1, $year - 1900);
   my $wdaynum = (ow::datetime::seconds2array($t))[6];
   my $dow     = $ow::datetime::wday_en[$wdaynum];
   my $date    = sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2   = sprintf("%04d,%02d,%02d,%s", $year, $month, $day, $dow);
   my ($lunar, $lunarnew) = lunar_day($year, $month, $day, $prefs{'charset'});

   my $offset = int(($time - ow::datetime::array2seconds(0, 0, 12, $current_day, $current_month - 1, $current_year - 1900)) / 86400);
   $offset = "+$offset" if ($offset >= 0);

   my @hourlist;
   if ($prefs{'hourformat'} == 12) {
      @hourlist = qw(none 1 2 3 4 5 6 7 8 9 10 11 12);
   } else {
      @hourlist = qw(none 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23);
   }

   my $weekorder = int(($day + 6) / 7);
   my %dayfreqlabels = ('thisdayonly'       => $lang_text{'thisday_only'},
                        'thewdayofthismonth'=> $lang_text{'the_wday_of_thismonth'},
                        'everywdaythismonth'=> $lang_text{'every_wday_thismonth'});
   $dayfreqlabels{'thewdayofthismonth'} =~ s/\@\@\@ORDER\@\@\@/$lang_order{$weekorder}/;
   $dayfreqlabels{'thewdayofthismonth'} =~ s/\@\@\@WDAY\@\@\@/$lang_wday{$wdaynum}/;
   $dayfreqlabels{'everywdaythismonth'} =~ s/\@\@\@WDAY\@\@\@/$lang_wday{$wdaynum}/;
   my @dayfreq= $weekorder <= 4 ? ('thisdayonly', 'thewdayofthismonth', 'everywdaythismonth')
                                : ('thisdayonly', 'everywdaythismonth');

   my %monthfreqlabels = ('thismonthonly'         => $lang_text{'thismonth_only'},
                          'everyoddmonththisyear' => $lang_text{'every_oddmonth_thisyear'},
                          'everyevenmonththisyear'=> $lang_text{'every_evenmonth_thisyear'},
                          'everymonththisyear'    => $lang_text{'every_month_thisyear'});
   my @monthfreq = $month % 2 ? ('thismonthonly', 'everyoddmonththisyear', 'everymonththisyear') 
                              : ('thismonthonly', 'everyevenmonththisyear', 'everymonththisyear');

   my @indexlist=();
   foreach ($date, '*') {
      next if (!defined $indexes{$_});
      foreach my $index (@{$indexes{$_}}) {
         if (  $date  =~ /$items{$index}{'idate'}/
            || $date2 =~ /$items{$index}{'idate'}/
            || ow::datetime::easter_match($year, $month, $day, $items{$index}{'idate'})) {
            push(@indexlist, $index);
         }
      }
   }
   @indexlist = sort { $items{$a}{'starthourmin'} <=> $items{$b}{'starthourmin'}
                      || $items{$a}{'endhourmin'} <=> $items{$b}{'endhourmin'}
                      || $b <=> $a } @indexlist;

   # all day events

   my (@allday_indexes, @matrix, %layout, $slotmin, $slotmax, $colmax, );
   build_event_matrix(\%items, \@indexlist,
       \@allday_indexes, \@matrix, \%layout, \$slotmin, \$slotmax, \$colmax);

   my $alldayloop = [];
   my ($bdstylestr, $eventlink, $eventemail, $eventtime);
   my $alterrow = 1;

   for my $index (@allday_indexes) {
      $alterrow = $alterrow ? 0 : 1;
      my ($eventtime, 
          $eventlink, 
          $eventlinktxt, 
          $eventemail, 
          $eventtxt, 
          $eventcolor,
          $idate) = parse_event($items{$index}, ($index >= 1E6));

      push(@{$alldayloop}, {  
                              use_texticon         => ($prefs{iconset} =~ m/^Text\./?1:0),
                              url_html             => $config{ow_htmlurl},
                              url_cgi              => $config{ow_cgiurl},
                              iconset              => $prefs{iconset},
                              sessionid            => $thissession,
                              message_id           => $messageid,
                              folder               => $folder,
                              year                 => $year,
                              month                => $month,
                              day                  => $day,
                              alterrow             => $alterrow,
                              eventtime            => $eventtime,    
                              eventlink            => $eventlink,    
                              eventlinktxt         => $eventlinktxt, 
                              eventemail           => $eventemail,   
                              eventtxt             => $eventtxt,     
                              eventcolor           => $eventcolor,
                              eventindex           => $index,
                              eventmult            => $idate =~ /[\*|,|\|]/ ? 1 : 0,
                              notglobal            => $index < 1E6 ? 1 : 0,
                              colspan              => $colmax + 1,
                           });
   }

   # events with time

   $alterrow = 1;
   my $slotsloop = [];
   my $slots_in_hour = int(60 / ($prefs{'calendar_interval'} || 30) + 0.999999);

   for (my $slot = 0; $slot < $#slottime; $slot++) {
      my $rowminstr = 0;
      if ($slot % $slots_in_hour == 0) {
         # skip too early time slots
         my $is_early = 1;
         for my $i (0 .. $slots_in_hour - 1) {
            if ($slot + $i >= $slotmin
                || $slottime[$slot + $i] ge $prefs{'calendar_starthour'}) {
               $is_early = 0; 
               last;
            }
         }

         if ($is_early) {	# skip $slots_in_hour slots at once
            $slot = $slot + $slots_in_hour - 1;
            next;
         }

         # skip empty time slots
         if (!$prefs{'calendar_showemptyhours'}) {
            my $is_empty = 1;
            for my $col (0 .. $colmax) {
               for my $i (0 .. $slots_in_hour - 1) {
                  if (defined $matrix[$slot + $i][$col] && $matrix[$slot + $i][$col]) {
                     $is_empty=0;
                     last;
                  }
                  last if (!$is_empty);
               }
               last if (!$is_empty);
            }
            if ($is_empty) {	# skip $slots_in_hour slots at once
               $slot = $slot + $slots_in_hour-1;
               next;
            }
         }

         last if ($slot > $slotmax && $slottime[$slot] gt $prefs{'calendar_endhour'});
         
         $alterrow = $alterrow ? 0 : 1;
      } elsif ($slots_in_hour > 3 && ($slot%$slots_in_hour) % 2 == 0) {
         $rowminstr = ($slot % $slots_in_hour) * $prefs{'calendar_interval'};
      }

      my $colsloop = [];

      for my $col (0 .. $colmax) {
        my $r_event;
        my ($eventtime, 
           $eventlink, 
           $eventlinktxt, 
           $eventemail, 
           $eventtxt, 
           $eventcolor,
           $idate) = ('','','','','','','');
         my $starteventcell = 0;
         my $overlappedcell = 0;
         my $index = 0;
         if (defined $matrix[$slot][$col]) {
            $index = $matrix[$slot][$col];
            $r_event = $items{$index};
            if ($slot == $layout{$index}{'startslot'} &&
                $col == $layout{$index}{'startcol'} ) {	# an event started at this cell
                ($eventtime, 
                 $eventlink, 
                 $eventlinktxt, 
                 $eventemail, 
                 $eventtxt, 
                 $eventcolor,
                 $idate) = parse_event($items{$index}, ($index >= 1E6));
               $starteventcell = 1;
            } else {
               $overlappedcell = 1;
            }
         }
         push(@{$colsloop}, {
                              use_texticon         => ($prefs{iconset} =~ m/^Text\./?1:0),
                              url_html             => $config{ow_htmlurl},
                              url_cgi              => $config{ow_cgiurl},
                              iconset              => $prefs{iconset},
                              sessionid            => $thissession,
                              message_id           => $messageid,
                              folder               => $folder,
                              alterrow             => $alterrow,
                              year                 => $year,
                              month                => $month,
                              day                  => $day,
                              width                => int(100 * $layout{$index}{'colspan'} / ($colmax + 1)),
                              rowspan              => $layout{$index}{'rowspan'},
                              colspan              => $layout{$index}{'colspan'},
                              starteventcell       => $starteventcell,
                              overlappedcell       => $overlappedcell,
                              eventtime            => $eventtime,    
                              eventlink            => $eventlink,    
                              eventlinktxt         => $eventlinktxt, 
                              eventemail           => $eventemail,   
                              eventtxt             => $eventtxt,     
                              eventcolor           => $eventcolor,
                              bordercolor          => bordercolor($eventcolor),
                              eventindex           => $index,
                              eventmult            => $idate =~ /[\*|,|\|]/ ? 1 : 0,
                              endhourmin           => ${$r_event}{'endhourmin'},
                              notglobal            => $index < 1E6 ? 1 : 0,
                         });
      }

      push(@{$slotsloop}, {  
                              fullrow              => $slot % $slots_in_hour == 0 ? 1 : 0,
                              rowtimestr           => hourmin2str($slottime[$slot], $prefs{'hourformat'}),
                              rowminstr            => $rowminstr,
                              alterrow             => $alterrow,
                              colsloop             => $colsloop,
                      });
   }

   my $i = 1;

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_dayview.tmpl"),
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
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./?1:0),
                      url_html                => $config{ow_htmlurl},
                      url_cgi                 => $config{ow_cgiurl},
                      iconset                 => $prefs{iconset},
                      sessionid               => $thissession,
                      message_id              => $messageid,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,
                      
                      # cal_dayview.tmpl
                      enable_preference       => $config{enable_preference},
                      enable_webmail          => $config{enable_webmail},
                      enable_addressbook      => $config{enable_addressbook},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      year                    => $year,
                      month                   => $month,
                      current_day             => $current_day,
                      offset                  => $offset,
                      day                     => $day,
                      weekday                 => $lang_wday{$wdaynum},
                      lunar                   => $lunar,
                      lunarnew                => $lunarnew,
                      saturday                => $wdaynum == 6 ? 1 : 0,
                      sunday                  => $wdaynum == 0 ? 1 : 0,
                      current_year            => $current_year,
                      current_month           => $current_month,
                      not_current             => (($current_year != $year) || ($current_month != $month) || ($current_day != $day)) ? 1 : 0,
                      min_year                => $min_year,
                      prev_year               => $prev_year,
                      prev_month              => $prev_month,
                      prev_day                => $prev_day,
                      next_year               => $next_year,
                      next_month              => $next_month,
                      next_day                => $next_day,
                      prev_monthname          => $lang_month{$prev_month}, 
                      next_monthname          => $lang_month{$next_month},
                      current_monthname       => $lang_month{$current_month},
                      monthname               => $lang_month{$month},
                      weekstart               => $prefs{'calendar_weekstart'},
                      noitems                 => $#indexlist < 0 ? 1 : 0,
                      noalldayitems           => $#allday_indexes < 0 ? 1 : 0,
                      colspan                 => $colmax + 1,
                      dayselectloop           => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $day ? 1 : 0
                                                       } } @{[1..$days_in_month[$month]]}
                                                 ],
                      monthselectloop         => [
                                                   map { {
                                                            option      => $_,
                                                            label       => $lang_month{$_},
                                                            selected    => $_ eq $month ? 1 : 0
                                                       } } @{[1..12]}
                                                 ],
                      yearselectloop          => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $year ? 1 : 0
                                                       } } @{[$min_year..$max_year]}
                                                 ],
                      alldayloop              => $alldayloop,
                      slotsloop               => $slotsloop,
                      starthourselectloop     => [ 
                                                   map { {
                                                           option       => $_,
                                                           label        => $_ eq 'none' ? $lang_text{$_} : sprintf("%02d", $_),
                                                           selected     => $_ eq $hourlist[0] ? 1 : 0
                                                       } } @hourlist
                                                 ],
                      startminselectloop      => [
                                                   map { {
                                                           option       => $_,
                                                           label        => sprintf("%02d", $_),
                                                           selected     => $_ eq '0' ? 1 : 0
                                                       } } (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55)
                                                 ],
                      endhourselectloop     => [ 
                                                   map { {
                                                           option       => $_,
                                                           label        => $_ eq 'none' ? $lang_text{$_} : sprintf("%02d", $_),
                                                           selected     => $_ eq $hourlist[0] ? 1 : 0
                                                       } } @hourlist
                                                 ],
                      endminselectloop      => [
                                                   map { {
                                                           option       => $_,
                                                           label        => sprintf("%02d", $_),
                                                           selected     => $_ eq '0' ? 1 : 0
                                                       } } (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55)
                                                 ],
                      dayfreqselectloop     => [
                                                   map { {
                                                           option       => $_,
                                                           label        => $dayfreqlabels{$_},
                                                           selected     => $_ eq $dayfreq[0] ? 1 : 0
                                                       } } @dayfreq
                                                 ],
                      monthfreqselectloop   => [
                                                   map { {
                                                           option       => $_,
                                                           label        => $monthfreqlabels{$_},
                                                           selected     => $_ eq $monthfreq[0] ? 1 : 0
                                                       } } @monthfreq
                                                 ],
                      eventcolorselectloop  => [
                                                   map { {
                                                           option       => $_,
                                                           label        => $_,
                                                           selected     => $_ eq 'none' ? 1 : 0
                                                       } } @{['none', sort keys %eventcolors]}
                                                 ],
                      eventcolorlistloop    => [
                                                   map { {
                                                           eventcolor   => $eventcolors{$_},
                                                           eventcolorkey=> $_,
                                                           eventcolornum=> $i++,
                                                       } } sort keys %eventcolors
                                                 ],

                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);

}

sub build_event_matrix {
   my ($r_items, $r_indexlist,
       $r_allday_indexies, $r_matrix, $r_layout, $r_slotmin, $r_slotmax, $r_colmax)=@_;
   my @matrix_indexies;
   my %slots;
   (${$r_slotmin}, ${$r_slotmax}, ${$r_colmax})=(999999, 0, 0);

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
             ((${$r_event}{'endhourmin'} eq '0' ||
               ${$r_event}{'endhourmin'} eq ${$r_event}{'starthourmin'}) &&
              ${$r_event}{'starthourmin'} ge $slottime[$slot] &&
              ${$r_event}{'starthourmin'} lt $slottime[$slot+1]) ) {
            push(@{$slots{$index}}, $slot);
            ${$r_layout}{$index}{'rowspan'}++;
            ${$r_slotmin}=$slot if ($slot<${$r_slotmin});
            ${$r_slotmax}=$slot if ($slot>${$r_slotmax});
         }
      }

      # find the first available column for this event so all it won't conflict with other event
      my $col=0;
      for ($col=0; ; $col++) {
         my $col_available=1;
         foreach my $slot (@{$slots{$index}}) {
            if (defined ${$r_matrix}[$slot][$col] && ${$r_matrix}[$slot][$col]) {
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
            if (defined ${$r_matrix}[$slot][$col] && ${$r_matrix}[$slot][$col]) {
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
   return;
}

sub bordercolor {
   # take a hex number and calculate a hex number that
   # will be a nice complement to it as a bordercolor
   return "#666666" unless ($_[0]);
   my ($redhex, $greenhex, $bluehex) = $_[0]=~/#(..)(..)(..)/;
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

   return "#$redhex$greenhex$bluehex";
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
########## END DAYVIEW ###########################################

########## LISTVIEW ##############################################
sub listview {
   my $year = $_[0];

#  Common to all views

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($localtime))[5,4,3];

   $current_year += 1900; 
   my $min_year = $current_year - 30;
   my $max_year = $current_year + 30;

   $year = $current_year    if (!$year);
   $year = $max_year        if ($year > $max_year); 
   $year = $min_year        if ($year < $min_year);
   
   $current_month++;

   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++      if ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0));

   my (%items, %indexes);
   my $calbookfile = dotpath('calendar.book');

   if (readcalbook($calbookfile, \%items, \%indexes, 0) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }
   if ($prefs{'calendar_reminderforglobal'}) {
      readcalbook("$config{'global_calendarbook'}", \%items, \%indexes, 1E6);
      if ($prefs{'calendar_holidaydef'} eq 'auto') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'locale'}", \%items, \%indexes, 1E7);
      } elsif ($prefs{'calendar_holidaydef'} ne 'none') {
         readcalbook("$config{'ow_holidaysdir'}/$prefs{'calendar_holidaydef'}", \%items, \%indexes, 1E7);
      }
   }

#  End Common to all views

   my $prev_year = $year - 1;
   my $next_year = $year + 1;

   my @accesskey = qw(0 1 2 3 4 5 6 7 8 9 0 J Q);

   my $tnow = ow::datetime::array2seconds(1, 1, 1, $current_day, $current_month - 1, $current_year - 1900);

   my $daysloop = [];
   for my $month (1..12) {
      for my $day (1..$days_in_month[$month]) {
         my $t       = ow::datetime::array2seconds(1, 1, 1, $day, $month - 1, $year - 1900);
         my $wdaynum = (ow::datetime::seconds2array($t))[6];
         my $dow     = $ow::datetime::wday_en[$wdaynum];
         my $date    = sprintf("%04d%02d%02d", $year, $month, $day);
         my $date2   = sprintf("%04d,%02d,%02d,%s", $year, $month, $day, $dow);
         my $today   = $t == $tnow ? 1 : 0;
         my @indexlist = ();
         foreach ($date, '*') {
            next if (!defined $indexes{$_});
            foreach my $index (@{$indexes{$_}}) {
               if ($date  =~ /$items{$index}{'idate'}/
                   || $date2 =~ /$items{$index}{'idate'}/
                   || ow::datetime::easter_match($year, $month, $day, $items{$index}{'idate'})) {
                  push(@indexlist, $index);
               }
            }
         }
         @indexlist = sort { $items{$a}{'starthourmin'} <=> $items{$b}{'starthourmin'}
                           || $items{$a}{'endhourmin'} <=> $items{$b}{'endhourmin'}
                           || $b <=> $a } @indexlist;
         
         my $eventsloop = [];

         for my $index (@indexlist) {
            my ($eventtime, 
                $eventlink, 
                $eventlinktxt, 
                $eventemail, 
                $eventtxt, 
                $eventcolor,
                $idate) = parse_event($items{$index}, ($index >= 1E6));

            push(@{$eventsloop}, { use_texticon  => $prefs{iconset} =~ m/^Text\./ ? 1 : 0,
                                   url_cgi       => $config{ow_cgiurl},
                                   url_html      => $config{ow_htmlurl},
                                   sessionid     => $thissession,
                                   message_id    => $messageid,
                                   folder        => $folder,
                                   iconset       => $prefs{iconset},
                                   eventtime     => $eventtime,    
                                   eventlink     => $eventlink,    
                                   eventlinktxt  => $eventlinktxt, 
                                   eventemail    => $eventemail,   
                                   eventtxt      => $eventtxt,     
                                   eventcolor    => $eventcolor,
                                   eventindex    => $index,
                                   eventmult     => $idate =~ /[\*|,|\|]/ ? 1 : 0,
                                   notglobal     => $index < 1E6 ? 1 : 0,
                                   year          => $year,
                                   month         => $month,
                                   day           => $day
                                 });
         }
         if ($#{$eventsloop} > -1 || $today) {
            my ($lunar, $lunarnew) = lunar_day($year, $month, $day, $prefs{'charset'});
            push(@{$daysloop}, { url_cgi     => $config{ow_cgiurl},
                                 sessionid   => $thissession,
                                 message_id  => $messageid,
                                 folder      => $folder,
                                 uselightbar => $prefs{'uselightbar'},
                                 day         => $day,
                                 month       => $month,
                                 year        => $year,
                                 accesskey   => $accesskey[$month],
                                 daystr      => sprintf("%02d", $day),
                                 monthstr    => sprintf("%02d", $month),
                                 weekday     => $lang_wday{$wdaynum},
                                 lunar       => $lunar,
                                 lunarnew    => $lunarnew,
                                 today       => $today,
                                 daydiffstr  => $today ? "" : sprintf("%+d", int(($t - $tnow)/86400)),
                                 eventsloop  => $eventsloop
                              });
         }
      }
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_listview.tmpl"),
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
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./?1:0),
                      url_html                => $config{ow_htmlurl},
                      url_cgi                 => $config{ow_cgiurl},
                      iconset                 => $prefs{iconset},
                      sessionid               => $thissession,
                      message_id              => $messageid,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,

                      # cal_listview.tmpl
                      enable_preference       => $config{enable_preference},
                      enable_webmail          => $config{enable_webmail},
                      enable_addressbook      => $config{enable_addressbook},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      year                    => $year,
                      month                   => $current_month,
                      day                     => $current_day,
                      current_year            => $current_year,
                      not_current             => $current_year != $year ? 1 : 0,
                      prev_year               => $prev_year,
                      next_year               => $next_year,
                      monthname               => $lang_month{$current_month},
                      yearselectloop          => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $year ? 1 : 0
                                                       } } @{[$min_year..$max_year]}
                                                 ],
                      daysloop                => $daysloop,
                      
                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);

}
########## END DAYVIEW ##########################################

########## EDIT_ITEM #############################################
# display the edit menu of an event
sub edit_item {
   my ($year, $month, $day, $index)=@_;

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($localtime))[5,4,3];

   $current_year  += 1900; 
   my $min_year = $current_year - 30;
   my $max_year = $current_year + 30;

   my $format12 = $prefs{'hourformat'} == 12 ? 1 : 0;

   my (%items, %indexes);
   my $calbookfile = dotpath('calendar.book');

   if (readcalbook($calbookfile, \%items, \%indexes, 0) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }

   if (!defined $items{$index}) {
      openwebmailerror(__FILE__, __LINE__, "$lang_text{'calendar'} $index $lang_err{'doesnt_exist'}");
      writelog("edit calitem error - item missing, index=$index");
      writehistory("edit calitem error - item missing, index=$index");
   }


   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++      if ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0));
   $day = $days_in_month[$month] if ($day > $days_in_month[$month]); 
   $day = 1 if ($day < 1);

   my @hourlist;
   if ($prefs{'hourformat'} == 12) {
      @hourlist = qw(none 1 2 3 4 5 6 7 8 9 10 11 12);
   } else {
      @hourlist = qw(none 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23);
   }

   my ($starthour, $startmin, $startampm) = ('none', 0, 'am');
   if ($items{$index}{'starthourmin'} =~ /0*(\d+)(\d{2})$/) {
      ($starthour, $startmin) = ($1, $2);
      ($starthour, $startampm) = ow::datetime::hour24to12($starthour) if ($format12);
   }

   my ($endhour, $endmin, $endampm) = ('none', 0, 'am');
   if ($items{$index}{'endhourmin'} =~ /0*(\d+)(\d{2})$/) {
      ($endhour, $endmin) = ($1, $2);
      ($endhour, $endampm) = ow::datetime::hour24to12($endhour) if ($format12);
   }

   # deconstruct the idate
   # An idate has the following format: <years><months><days><dayofweek>
   # An idate can look like:
   #    20030808                            The event occurs on August 8, 2003, This Month, This Day only
   #    (20030808|20030809)                 The event occurs on August 8 and 9, 2003 (or August 8 and Next 1 day)
   #    .*,04,07,.*                         The event occurs on April 7, Every Year
   #    .*,.*,((1[5-9])|(2[0-1])),Tue       The event occurs on the 3rd Tuesday, Every Month, Every Year
   #    2003,.*,.*,Wed                      The event occurs Every Wednesday, Every Week of 2003
   #    2003,.*,11,.*                       The event occurs Every 11th day, Every Month of 2003
   my ($everyyear, $monthfreq, $dayfreq, $dow, $startdate, $enddate, $ndays) = '';

   my $dayfreq_default = "thisdayonly";
   my $thisandnextndays_default = 0;
   my $ndays_default = "";
   my $monthfreq_default = "thismonthonly";
   my $everyyear_default = 0;
   my $linkstr_default = $items{$index}{'link'};
   my $emailstr_default = $items{$index}{'email'};

   if ($items{$index}{'idate'} =~ /,/) { #idate has recurrance in it
       ($everyyear, $monthfreq, $dayfreq, $dow) = split(/,/, $items{$index}{'idate'});
       my %weekorder_day_wild_reversed = ( "0[1-7]" => 1,
                                           "((0[8-9])|(1[0-4]))" => 2,
                                           "((1[5-9])|(2[0-1]))" => 3,
                                           "2[2-8]" => 4);

       if ($weekorder_day_wild_reversed{$dayfreq}) {
          $dayfreq_default = "thewdayofthismonth";
       } elsif ($dayfreq eq '.*') {
          $dayfreq_default = "everywdaythismonth";
       }
       if ($monthfreq eq '(01|03|05|07|09|11)') {
          $monthfreq_default = "everyoddmonththisyear";
       } elsif ($monthfreq eq '(02|04|06|08|10|12)') {
          $monthfreq_default = "everyevenmonththisyear"
       } elsif ($monthfreq eq '.*') {
          $monthfreq_default = "everymonththisyear";
       }
       if ($everyyear eq '.*') {
          $everyyear_default = 1;
       }
   } elsif ($items{$index}{'idate'} =~ /^\(?(\d+)\|?.*?\|?(\d+)?\)?$/) {
       # That regex breaks apart idates like (20030808|20030809)
       $startdate = $1;
       $enddate = $2 || '';
       if ($enddate ne '') { # we have a next Nday recurrance here
          $thisandnextndays_default = 1;
          $ndays_default = $items{$index}{'idate'} =~ tr/|/|/; # count pipes - cheap and easy
       }
   } else {
      openwebmailerror(__FILE__, __LINE__, "Index $index idate $lang_err{'doesnt_exist'}");
      writelog("edit calitem error - idate wrong format, index=$index");
      writehistory("edit calitem error - idate wrong format, index=$index");
   }

   my $t = ow::datetime::array2seconds(1, 1, 1, $day, $month - 1, $year - 1900);
   my $wdaynum = (ow::datetime::seconds2array($t))[6];
   my $weekorder = int(($day + 6) / 7);
   my %dayfreqlabels = ('thisdayonly'       => $lang_text{'thisday_only'},
                        'thewdayofthismonth'=> $lang_text{'the_wday_of_thismonth'},
                        'everywdaythismonth'=> $lang_text{'every_wday_thismonth'});
   $dayfreqlabels{'thewdayofthismonth'} =~ s/\@\@\@ORDER\@\@\@/$lang_order{$weekorder}/;
   $dayfreqlabels{'thewdayofthismonth'} =~ s/\@\@\@WDAY\@\@\@/$lang_wday{$wdaynum}/;
   $dayfreqlabels{'everywdaythismonth'} =~ s/\@\@\@WDAY\@\@\@/$lang_wday{$wdaynum}/;
   my @dayfreq= $weekorder <= 4 ? ('thisdayonly', 'thewdayofthismonth', 'everywdaythismonth')
                                : ('thisdayonly', 'everywdaythismonth');

   my %monthfreqlabels = ('thismonthonly'         => $lang_text{'thismonth_only'},
                          'everyoddmonththisyear' => $lang_text{'every_oddmonth_thisyear'},
                          'everyevenmonththisyear'=> $lang_text{'every_evenmonth_thisyear'},
                          'everymonththisyear'    => $lang_text{'every_month_thisyear'});
   my @monthfreq = $month % 2 ? ('thismonthonly', 'everyoddmonththisyear', 'everymonththisyear') 
                              : ('thismonthonly', 'everyevenmonththisyear', 'everymonththisyear');

   $linkstr_default = "http://" if ($linkstr_default eq "0");
   $emailstr_default = "" if ($emailstr_default eq "0");
   my $i = 1;

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_edit.tmpl"),
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
                      url_html                => $config{ow_htmlurl},
                      url_cgi                 => $config{ow_cgiurl},
                      iconset                 => $prefs{iconset},
                      sessionid               => $thissession,
                      message_id              => $messageid,
                      folder                  => $folder,

                      # cal_edit.tmpl
                      index                   => $index,
                      year                    => $year,
                      month                   => $month,
                      day                     => $day,
                      min_year                => $min_year,
                      weekstart               => $prefs{'calendar_weekstart'},
                      format12                => $format12,
                      startam                 => $startampm eq 'am' ? 1 : 0,
                      endam                   => $endampm eq 'am' ? 1 : 0,
                      thisandnextndays        => $thisandnextndays_default,
                      ndays                   => $ndays_default,
                      everyyear               => $everyyear_default,
                      eventtxt                => (iconv($items{$index}{'charset'}, $prefs{'charset'}, $items{$index}{'string'}))[0],
                      linkstr                 => $linkstr_default,
                      emailstr                => $emailstr_default,
                      eventreminder           => $items{$index}{'eventreminder'},
                      notifyenabled           => $config{'calendar_email_notifyinterval'} > 0 ? 1 : 0,
                      callist                 => defined param('callist') ? 1 : 0,
                      dayselectloop           => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $day ? 1 : 0
                                                       } } @{[1..$days_in_month[$month]]}
                                                 ],
                      monthselectloop         => [
                                                   map { {
                                                            option      => $_,
                                                            label       => $lang_month{$_},
                                                            selected    => $_ eq $month ? 1 : 0
                                                       } } @{[1..12]}
                                                 ],
                      yearselectloop          => [ 
                                                   map { { 
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $year ? 1 : 0
                                                       } } @{[$min_year..$max_year]}
                                                 ],
                      starthourselectloop     => [ 
                                                   map { {
                                                           option       => $_,
                                                           label        => $_ eq 'none' ? $lang_text{$_} : sprintf("%02d", $_),
                                                           selected     => $_ eq $starthour ? 1 : 0
                                                       } } @hourlist
                                                 ],
                      startminselectloop      => [
                                                   map { {
                                                           option       => $_,
                                                           label        => sprintf("%02d", $_),
                                                           selected     => $_ eq $startmin ? 1 : 0
                                                       } } (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55)
                                                 ],
                      endhourselectloop     => [ 
                                                   map { {
                                                           option       => $_,
                                                           label        => $_ eq 'none' ? $lang_text{$_} : sprintf("%02d", $_),
                                                           selected     => $_ eq $endhour ? 1 : 0
                                                       } } @hourlist
                                                 ],
                      endminselectloop      => [
                                                   map { {
                                                           option       => $_,
                                                           label        => sprintf("%02d", $_),
                                                           selected     => $_ eq $endmin ? 1 : 0
                                                       } } (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55)
                                                 ],
                      dayfreqselectloop     => [
                                                   map { {
                                                           option       => $_,
                                                           label        => $dayfreqlabels{$_},
                                                           selected     => $_ eq $dayfreq_default ? 1 : 0
                                                       } } @dayfreq
                                                 ],
                      monthfreqselectloop   => [
                                                   map { {
                                                           option       => $_,
                                                           label        => $monthfreqlabels{$_},
                                                           selected     => $_ eq $monthfreq_default ? 1 : 0
                                                       } } @monthfreq
                                                 ],
                      eventcolorselectloop  => [
                                                   map { {
                                                           option       => $_,
                                                           label        => $_,
                                                           selected     => $_ eq $items{$index}{'eventcolor'} ? 1 : 0
                                                       } } @{['none', sort keys %eventcolors]}
                                                 ],
                      eventcolorlistloop    => [
                                                   map { {
                                                           eventcolor   => $eventcolors{$_},
                                                           eventcolorkey=> $_,
                                                           eventcolornum=> $i++,
                                                       } } sort keys %eventcolors
                                                 ],
                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}
########## END EDIT_ITEM #########################################

########## ADD_ITEM ##############################################
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
       $link, $email, $eventcolor, $eventreminder)=@_;
   my $line;
   return if ($string=~/^\s?$/);

   # check for bad input that would kill our database format
   if ($string =~ /\@\@\@/) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'at_char_not_allowed'}");
   }
   if ($link =~ /\@\@\@/) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'at_char_not_allowed'}");
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

   # fix the day if needed
   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++ if ( ($year%4)==0 && (($year%100)!=0||($year%400)==0) );
   $day=$days_in_month[$month] if ($day>$days_in_month[$month]); $day=1 if ($day<1);

   my $calbookfile=dotpath('calendar.book');

   my ($item_count, %items, %indexes);
   if ( readcalbook($calbookfile, \%items, \%indexes, 0)<0 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }

   my $index = $item_count+19690404;	# avoid collision with old records
   my $t = ow::datetime::array2seconds(1,1,1, $day,$month-1,$year-1900);
   my $dow = $ow::datetime::wday_en[(ow::datetime::seconds2array($t))[6]];

   # construct the idate for this record.
   if ($dayfreq eq 'thisdayonly' && $monthfreq eq 'thismonthonly' && !$everyyear) {
      if ($thisandnextndays && $ndays) {
         if ($ndays !~ /\d+/) {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'badnum_in_days'}: $ndays");
         }
         my $date_wild='(';
         for (my $i=0; $i<=$ndays; $i++) {
            my ($y, $m, $d)=(ow::datetime::seconds2array($t+86400*$i))[5,4,3];
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
   $items{$index}{'charset'}=$prefs{'charset'};
   $items{$index}{'eventreminder'}=$eventreminder;

   if (writecalbook($calbookfile, \%items) <0 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $calbookfile");
   }

   reset_notifycheck_for_newitem($items{$index});

   my $msg="add calitem - index=$index, start=$starthourmin, end=$endhourmin, str=$string";
   writelog($msg);
   writehistory($msg);
}
########## END ADD_ITEM ##########################################

########## DEL_ITEM ##############################################
# delete an item from user calendar
sub del_item {
   my $index=$_[0];

   my $calbookfile=dotpath('calendar.book');
   my (%items, %indexes);
   if ( readcalbook($calbookfile, \%items, \%indexes, 0)<0 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }
   return if (!defined $items{$index});

   delete $items{$index};
   if ( writecalbook($calbookfile, \%items) <0 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $calbookfile");
   }

   my ($s)=iconv($items{$index}{'charset'}, $prefs{'charset'}, $items{$index}{'string'});
   my $msg="delete calitem - index=$index, t=$items{$index}{'starthourmin'}, str=$s";
   writelog($msg);
   writehistory($msg);
}
########## END DEL_ITEM ##########################################

########## UPDATE_ITEM ###########################################
# update an item in user calendar
sub update_item {
   my ($index,
       $year, $month, $day,
       $string,
       $starthour, $startmin, $startampm,
       $endhour, $endmin, $endampm,
       $dayfreq,
       $thisandnextndays, $ndays, $monthfreq, $everyyear,
       $link, $email, $eventcolor, $eventreminder)=@_;
   my $line;

   return if ($string=~/^\s?$/);

   # check for valid input
   if ($string =~ /\@{3}/) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'at_char_not_allowed'}");
   }
   if ($link =~ /\@{3}/) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'at_char_not_allowed'}");
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

   # fix the day if needed
   my @days_in_month = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
   $days_in_month[2]++ if ( ($year%4)==0 && (($year%100)!=0||($year%400)==0) );
   $day=$days_in_month[$month] if ($day>$days_in_month[$month]); $day=1 if ($day<1);

   my $t = ow::datetime::array2seconds(1,1,1, $day,$month-1,$year-1900);
   my $dow = $ow::datetime::wday_en[(ow::datetime::seconds2array($t))[6]];

   # construct the idate for this record.
   my $idate = '';
   if ($dayfreq eq 'thisdayonly' && $monthfreq eq 'thismonthonly' && !$everyyear) {
      if ($thisandnextndays && $ndays) {
         if ($ndays !~ /\d+/) {
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'badnum_in_days'}: $ndays");
         }
         my $date_wild='(';
         for (my $i=0; $i<=$ndays; $i++) {
            my ($y, $m, $d)=(ow::datetime::seconds2array($t+86400*$i))[5,4,3];
            $date_wild.='|' if ($i>0);
            $date_wild.=sprintf("%04d%02d%02d", $y+1900, $m+1, $d);
         }
         $date_wild.=')';
         $idate=$date_wild;
      } else {
         $idate=sprintf("%04d%02d%02d", $year, $month, $day);
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

      $idate="$year_wild,$month_wild,$day_wild,$dow";

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
         $idate="$year_wild,$month_wild,.*,$dow";
      } else {
         my $daystr=sprintf("%02d", $day);
         $idate="$year_wild,$month_wild,$daystr,.*";
      }
   }

   my $calbookfile=dotpath('calendar.book');

   my (%items, %indexes);
   if ( readcalbook($calbookfile, \%items, \%indexes, 0)<0 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $calbookfile");
   }
   if (!defined $items{$index}) {
      openwebmailerror(__FILE__, __LINE__, "$lang_text{'calendar'} $index $lang_err{'doesnt_exist'}");
      writelog("update calitem error - item missing, index=$index");
      writehistory("update calitem error - item missing, index=$index");
   }

   $items{$index}{'starthourmin'}="$starthourmin"; # " is required or "0000" will be treated as 0?
   $items{$index}{'endhourmin'}="$endhourmin";
   $items{$index}{'idate'}="$idate";
   $items{$index}{'string'}=$string;
   $items{$index}{'link'}=$link;
   $items{$index}{'email'}=$email;
   $items{$index}{'eventcolor'}="$eventcolor";
   $items{$index}{'charset'}=$prefs{'charset'};
   $items{$index}{'eventreminder'}=$eventreminder;

   if ( writecalbook($calbookfile, \%items) <0 ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $calbookfile");
   }

   reset_notifycheck_for_newitem($items{$index});

   my $msg="update calitem - index=$index, start=$starthourmin, end=$endhourmin, str=$string";
   writelog($msg);
   writehistory($msg);
}
########## END UPDATE_ITEM #######################################

########## SET_DAYS_IN_MONTH #####################################
# set the day number of each cell in the month calendar
sub set_days_in_month {
   my ($year, $month, $days_in_month) = @_;

   my %wdaynum=qw(Sun 0 Mon 1 Tue 2 Wed 3 Thu 4 Fri 5 Sat 6);
   foreach (keys %wdaynum) {
      $wdaynum{$_}=($wdaynum{$_}+7-$prefs{'calendar_weekstart'})%7;
   }
   my $time = ow::datetime::array2seconds(0,0,12, 1,$month-1,$year-1900);
   my $weekday = ow::datetime::seconds2array($time); $weekday =~ s/^(\w+).*$/$1/;

   my @days;
   my $day_counter = 1;
   for my $x (0..5) {
      for my $y (0..6) {
         if ( ($x>0 || $y>=$wdaynum{$weekday}) &&
              $day_counter<=$days_in_month ) {
            $days[$x][$y] = $day_counter;
            $day_counter++;
         }
      }
   }
   return @days;
}
########## END SET_DAYS_IN_MONTH #################################

########## HOURMIN2STR ###########################################
# convert military time (eg:1700) to timestr (eg:05:00 pm)
sub hourmin2str {
   my ($hourmin, $hourformat) = @_;
   if ($hourmin =~ /(\d+)(\d{2})$/) {
      my ($hour, $min) = ($1, $2);
      $hour =~ s/^0(.+)/$1/;
      if ($hourformat==12) {
         my $ampm;
         ($hour, $ampm)=ow::datetime::hour24to12($hour);
         $hourmin = $lang_text{'calfmt_hourminampm'};
         $hourmin =~ s/\@\@\@HOURMIN\@\@\@/$hour:$min/;
         $hourmin =~ s/\@\@\@AMPM\@\@\@/$lang_text{$ampm}/;
      } else {
         $hourmin = sprintf("%02d", $hour) . ":" . sprintf("%02d", $min);
      }
   }
   return $hourmin;
}
########## END HOURMIN2STR #######################################

########## LUNAR_DAY #############################################
# get big5 lunar str from gregorian date, then convert it to target charset
sub lunar_day {
   my ($year, $month, $day, $charset) = @_;
   my $txt = "";
   my $new = 0;

   if ($prefs{'locale'} =~ m/^(?:zh_TW\.Big5|zh_CN\.GB2312)/) {
      my ($lyear, $lmonth, $lday) = solar2lunar($year, $month, $day);
      $txt = lunar2big5str((solar2lunar($year, $month, $day))[1, 2]);
      if ($txt ne "") {
         $new = ($txt =~ /ªì¤@/ || $txt=~/¤Q¤­/) ? 1 : 0;
         $txt = (iconv('big5', $charset, $txt))[0];
      }
   }
   return($txt, $new);
}
########## END LUNAR_DAY #########################################

########## PARSE_EVENT ###########################################
# parse calendar events to eventsloop variables
sub parse_event {
   my ($r_item, $is_global) = @_;

   my ($eventtime, $eventlink, $eventlinktxt, $eventemail, $eventtxt, $eventcolor);

   if (${$r_item}{'starthourmin'} ne "0") {
      $eventtime = hourmin2str(${$r_item}{'starthourmin'}, $prefs{'hourformat'});
      if (${$r_item}{'endhourmin'} ne "0") {
        $eventtime .= qq|-| . hourmin2str(${$r_item}{'endhourmin'}, $prefs{'hourformat'});
      }
   } else {
      $eventtime = "#";
   }

   $eventlink = 0;
   if (${$r_item}{'link'}) {
      $eventlinktxt = ${$r_item}{'link'}; 
      $eventlink = $eventlinktxt;
      $eventlink =~ s/\%THISSESSION\%/$thissession/;
   }

   $eventemail = ${$r_item}{'email'};

   ($eventtxt) = iconv(${$r_item}{'charset'}, $prefs{'charset'}, ${$r_item}{'string'});
   $eventtxt =~ s/<.*?>//g;
   $eventtxt = substr($eventtxt, 0, 76)."..." if (length($eventtxt)>80);
   $eventtxt = "$eventtxt *" if ($is_global);

   $eventcolor = defined($eventcolors{${$r_item}{'eventcolor'}}) ? "#".$eventcolors{${$r_item}{'eventcolor'}} : 0;

   return($eventtime, 
          $eventlink, 
          $eventlinktxt, 
          $eventemail, 
          $eventtxt, 
          $eventcolor,
          ${$r_item}{'idate'});
}
########## END PARSE_EVENT #######################################

########## RESET_NOTIFYCHECK_FOR_NEWITEM #########################
# reset the lastcheck date in .notify.check
# if any item added with date before the lastcheck date
sub reset_notifycheck_for_newitem {
   my $r_item=$_[0];
   my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($wdaynum, $year, $month, $day, $hour, $min)=(ow::datetime::seconds2array($localtime))[6,5,4,3,2,1];
   $year+=1900; $month++;

   my $dow=$ow::datetime::wday_en[$wdaynum];
   my $date=sprintf("%04d%02d%02d", $year, $month, $day);
   my $date2=sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

   my $notifycheckfile=dotpath('notify.check');

   if ( ${$r_item}{'email'} &&
        ($date=~/${$r_item}{'idate'}/ || $date2=~/${$r_item}{'idate'}/) ) {
      if ( -f $notifycheckfile ) {
         sysopen(NOTIFYCHECK, $notifycheckfile, O_RDONLY) or return -1; # read err
         my $lastcheck=<NOTIFYCHECK>;
         close(NOTIFYCHECK);
         if ($lastcheck=~/$date(\d\d\d\d)/) {
            if (${$r_item}{'starthourmin'} < $1) {
               sysopen(NOTIFYCHECK, $notifycheckfile, O_WRONLY|O_TRUNC|O_CREAT) or return -1; # write err
               print NOTIFYCHECK sprintf("%08d%04d", $date, ${$r_item}{'starthourmin'});
               close(NOTIFYCHECK);
            }
         }
      }
   }
   return 0;
}
########## END RESET_NOTIFYCHECK_FOR_NEWITEM #####################
