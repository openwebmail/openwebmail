#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2009-2014, The OpenWebMail Project
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
use warnings FATAL => 'all';

use vars qw($SCRIPT_DIR);

if (-f '/etc/openwebmail_path.conf') {
   my $pathconf = '/etc/openwebmail_path.conf';
   open(F, $pathconf) or die "Cannot open $pathconf: $!";
   my $pathinfo = <F>;
   close(F) or die "Cannot close $pathconf: $!";
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die 'SCRIPT_DIR cannot be set' if $SCRIPT_DIR eq '';
push (@INC, $SCRIPT_DIR);
push (@INC, "$SCRIPT_DIR/lib");

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH} = '/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load non-OWM libraries
use Fcntl qw(:DEFAULT :flock);
use CGI 3.31 qw(-private_tempfiles :cgi charset);
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
use vars qw(%config $thissession %prefs $icons);

# extern vars
use vars qw($htmltemplatefilters $po); # defined in ow-shared.pl

# local globals
use vars qw($folder $sort $msgdatetype $page $longpage $keyword $searchtype $messageid);
use vars qw($events $index);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(gettext('Access denied: the calendar module is not enabled.')) unless $config{enable_calendar};

($events, $index) = open_calendars();

my $action     = param('action') || '';

$folder        = param('folder') || 'INBOX';
$sort          = param('sort') || $prefs{sort} || 'date_rev';
$msgdatetype   = param('msgdatetype') || $prefs{msgdatetype};
$page          = param('page') || 1;
$longpage      = param('longpage') || 0;
$searchtype    = param('searchtype') || 'subject';
$keyword       = param('keyword') || '';
$messageid     = param('message_id') ||'';

writelog("debug_request :: request cal begin, action=$action") if $config{debug_request};

$action eq 'calyear'   ? viewyear()  :
$action eq 'calmonth'  ? viewmonth() :
$action eq 'calday'    ? viewday()   :
$action eq 'calweek'   ? viewweek()  :
$action eq 'callist'   ? viewlist()  :
$action eq 'caledit'   ? edit()      :
$action eq 'caladdmod' ? addmod()    :
$action eq 'caldel'    ? del()       :
openwebmailerror(gettext('Action has illegal characters.'));

writelog("debug_request :: request cal end, action=$action") if $config{debug_request};

openwebmail_requestend();


# BEGIN SUBROUTINES

sub open_calendars {
   # populate the events and indexes hashes with
   # all of the calendar events for this user
   my $calbookfile = dotpath('calendar.book');

   my (%events, %index) = (),();

   # open the user calendar
   openwebmailerror(gettext('Cannot read calendar file:') . " $calbookfile ($!)")
     if readcalbook($calbookfile, \%events, \%index, 0) < 0;

   # open the global and holiday calendars
   if ($prefs{calendar_reminderforglobal}) {
      openwebmailerror(gettext('Cannot read calendar file:') . " $config{global_calendarbook} ($!)")
         if readcalbook($config{global_calendarbook}, \%events, \%index, 1E6) < 0;

      if ($prefs{calendar_holidaydef} eq 'auto') {
         openwebmailerror(gettext('Cannot read calendar file:') . " $config{ow_holidaysdir}/$prefs{locale} ($!)")
            if readcalbook("$config{ow_holidaysdir}/$prefs{locale}", \%events, \%index, 1E7) < 0;
      } elsif ($prefs{calendar_holidaydef} ne 'none') {
         openwebmailerror(gettext('Cannot read calendar file:') . " $config{ow_holidaysdir}/$prefs{calendar_holidaydef} ($!)")
            if readcalbook("$config{ow_holidaysdir}/$prefs{calendar_holidaydef}", \%events, \%index, 1E7) < 0;
      }
   }

   return (\%events, \%index);
}

sub viewyear {
   my $dates = dates(param('year'));

   my $yearloop    = [];
   my $yearlooprow = 0;

   foreach my $month_this_year (1..12) {
      my @days_of_month_matrix = days_of_month_matrix($dates->{year}, $month_this_year);

      my $monthloop = [];

      # get the events for each day this month
      foreach my $row (0..$#days_of_month_matrix) {
         foreach my $col (0..6) {
            my $day_this_month = $days_of_month_matrix[$row][$col] || 0;

            if ($day_this_month) {
               push(@{$monthloop->[$row]{columns}}, {
                                                       # standard params
                                                       use_texticon => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                                       url_html     => $config{ow_htmlurl},
                                                       url_cgi      => $config{ow_cgiurl},
                                                       iconset      => $prefs{iconset},
                                                       (map { $_, $icons->{$_} } keys %{$icons}),
                                                       sessionid    => $thissession,
                                                       message_id   => $messageid,
                                                       folder       => $folder,
                                                       sort         => $sort,
                                                       msgdatetype  => $msgdatetype,
                                                       page         => $page,
                                                       longpage     => $longpage,
                                                       searchtype   => $searchtype,
                                                       keyword      => $keyword,

                                                       year         => $dates->{year},
                                                       month        => $month_this_year,
                                                       day          => $day_this_month,
                                                       is_today     => (
                                                                         $dates->{year} == $dates->{current_year}
                                                                         && $month_this_year == $dates->{current_month}
                                                                         && $day_this_month == $dates->{current_day}
                                                                       ) ? 1 : 0,
                                                       eventstr     => $day_this_month
                                                                       ? join (' / ',
                                                                           map  {
                                                                                  (iconv($events->{$_}{charset}, $prefs{charset}, $events->{$_}{string}))[0]
                                                                                } indexes($dates->{year},$month_this_year,$day_this_month)
                                                                              )
                                                                       : '',
                                                    }
                   );
            } else {
               push(@{$monthloop->[$row]{columns}}, { is_empty => 1 });
            }
         }
      }

      # label each row of the month with the week number
      unshift(@{$monthloop->[$_]{columns}}, {
                                               # standard params
                                               use_texticon  => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                               url_html      => $config{ow_htmlurl},
                                               url_cgi       => $config{ow_cgiurl},
                                               iconset       => $prefs{iconset},
                                               (map { $_, $icons->{$_} } keys %{$icons}),
                                               sessionid     => $thissession,
                                               message_id    => $messageid,
                                               folder        => $folder,
                                               sort          => $sort,
                                               msgdatetype   => $msgdatetype,
                                               page          => $page,
                                               longpage      => $longpage,
                                               searchtype    => $searchtype,
                                               keyword       => $keyword,

                                               is_rowlabel   => 1,
                                               year          => $dates->{year},
                                               month         => $month_this_year,
                                               weekofyearday => $days_of_month_matrix[$_][0] || $days_of_month_matrix[$_][6],
                                               weekofyear    => ow::datetime::week_of_year(
                                                                                            $dates->{year},
                                                                                            $month_this_year,
                                                                                            $days_of_month_matrix[$_][0]
                                                                                            || $days_of_month_matrix[$_][6],
                                                                                            $prefs{calendar_weekstart}
                                                                                          ),
                                            }
             ) for (0..$#days_of_month_matrix);

      # label each column of the month with the abbreviated day
      unshift(@{$monthloop}, {
                               columns => [
                                            { is_collabel => 1, collabel => gettext('WK') },
                                            map {
                                                  {
                                                    is_collabel => 1,
                                                    collabel    => $dates->{lang}{wday_abbrev}[(($prefs{calendar_weekstart} + $_) % 7)],
                                                  }
                                                } (0..6)
                                          ]
                             }
             );

      # label the entire month with the monthname
      unshift(@{$monthloop}, {
                               columns => [
                                            {
                                               # standard params
                                               use_texticon  => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                               url_html      => $config{ow_htmlurl},
                                               url_cgi       => $config{ow_cgiurl},
                                               iconset       => $prefs{iconset},
                                               (map { $_, $icons->{$_} } keys %{$icons}),
                                               sessionid     => $thissession,
                                               message_id    => $messageid,
                                               folder        => $folder,
                                               sort          => $sort,
                                               msgdatetype   => $msgdatetype,
                                               page          => $page,
                                               longpage      => $longpage,
                                               searchtype    => $searchtype,
                                               keyword       => $keyword,

                                               is_monthlabel => 1,
                                               colspan       => 8,
                                               year          => $dates->{year},
                                               month         => $month_this_year,
                                               monthname     => $dates->{lang}{month}[$month_this_year],
                                            }
                                          ]
                             }
             );

      # add this month to the year loop
      push(@{$yearloop->[$yearlooprow]{columns}}, {
                                                     # standard params
                                                     use_texticon     => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                                     url_html         => $config{ow_htmlurl},
                                                     url_cgi          => $config{ow_cgiurl},
                                                     iconset          => $prefs{iconset},
                                                     (map { $_, $icons->{$_} } keys %{$icons}),
                                                     sessionid        => $thissession,
                                                     message_id       => $messageid,
                                                     folder           => $folder,
                                                     sort             => $sort,
                                                     msgdatetype      => $msgdatetype,
                                                     page             => $page,
                                                     longpage         => $longpage,
                                                     searchtype       => $searchtype,
                                                     keyword          => $keyword,

                                                     uselightbar      => $prefs{uselightbar},
                                                     year             => $dates->{year},
                                                     month            => $month_this_year,
                                                     monthname        => $dates->{lang}{month}[$month_this_year],
                                                     is_current_month => (
                                                                           $dates->{year} == $dates->{current_year}
                                                                           && $month_this_year == $dates->{current_month}
                                                                         ) ? 1 : 0,
                                                     month_accesskey  => ((qw(0 1 2 3 4 5 6 7 8 9 0 J Q))[$month_this_year]),
                                                     monthloop        => $monthloop,
                                                  }
          );

      $yearlooprow++ if $month_this_year % 4 == 0;
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_yearview.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template     => get_header($config{header_template_file}),

                      # standard params
                      use_texticon        => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html            => $config{ow_htmlurl},
                      url_cgi             => $config{ow_cgiurl},
                      iconset             => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),
                      sessionid           => $thissession,
                      message_id          => $messageid,
                      folder              => $folder,
                      sort                => $sort,
                      msgdatetype         => $msgdatetype,
                      page                => $page,
                      longpage            => $longpage,
                      searchtype          => $searchtype,
                      keyword             => $keyword,

                      # standard calendar dates
                      %{$dates},

                      # cal_yearview.tmpl
                      cal_caller          => 'calyear',
                      enable_preference   => $config{enable_preference},
                      enable_webmail      => $config{enable_webmail},
                      enable_addressbook  => $config{enable_addressbook},
                      enable_webdisk      => $config{enable_webdisk},
                      enable_sshterm      => $config{enable_sshterm},
                      yearselectloop      => [
                                               map { {
                                                       option      => $_,
                                                       label       => $_,
                                                       selected    => $_ eq $dates->{year} ? 1 : 0
                                                   } } ($dates->{min_year}..$dates->{max_year})
                                             ],
                      yearloop            => $yearloop,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub viewmonth {
   my $dates = dates(param('year'), param('month'));

   my @days_of_month_matrix = days_of_month_matrix($dates->{year}, $dates->{month});

   my $monthloop = [];

   # populate the month with all the events
   foreach my $row (0..$#days_of_month_matrix) {
      foreach my $col (0..6) {
         my $day_this_month = $days_of_month_matrix[$row][$col] || 0;

         if ($day_this_month) {
            my @thisday_events = events($dates->{year}, $dates->{month}, $day_this_month);

            my $more_events = 0;
            if (scalar @thisday_events >= $prefs{calendar_monthviewnumitems}) {
               $more_events = 1;
               pop @thisday_events while scalar @thisday_events > $prefs{calendar_monthviewnumitems};
            }

            my ($lunar_string, $lunar_isnew) = lunar_string($dates->{year}, $dates->{month}, $day_this_month);

            # add this day to the month loop
            push(@{$monthloop->[$row]{columns}}, {
                                                    # standard params
                                                    use_texticon  => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                                    url_html      => $config{ow_htmlurl},
                                                    url_cgi       => $config{ow_cgiurl},
                                                    iconset       => $prefs{iconset},
                                                    (map { $_, $icons->{$_} } keys %{$icons}),
                                                    sessionid     => $thissession,
                                                    message_id    => $messageid,
                                                    folder        => $folder,
                                                    sort          => $sort,
                                                    msgdatetype   => $msgdatetype,
                                                    page          => $page,
                                                    longpage      => $longpage,
                                                    searchtype    => $searchtype,
                                                    keyword       => $keyword,

                                                    cal_caller    => 'calmonth',
                                                    uselightbar   => $prefs{uselightbar},
                                                    year          => $dates->{year},
                                                    month         => $dates->{month},
                                                    day           => $day_this_month,
                                                    lunar         => $lunar_string,
                                                    lunarnew      => $lunar_isnew,
                                                    is_today      => (
                                                                       $dates->{year} == $dates->{current_year}
                                                                       && $dates->{month} == $dates->{current_month}
                                                                       && $day_this_month == $dates->{current_day}
                                                                     ) ? 1 : 0,
                                                    dayeventsloop => \@thisday_events,
                                                    more_events   => $more_events,
                                                  }
                );
         } else {
            # no day here - add an empty cell
            push(@{$monthloop->[$row]{columns}}, { is_empty => 1 });
         }
      }
   }

   # label each row of the month with its week number
   unshift(@{$monthloop->[$_]{columns}}, {
                                             # standard params
                                             use_texticon  => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                             url_html      => $config{ow_htmlurl},
                                             url_cgi       => $config{ow_cgiurl},
                                             iconset       => $prefs{iconset},
                                             (map { $_, $icons->{$_} } keys %{$icons}),
                                             sessionid     => $thissession,
                                             message_id    => $messageid,
                                             folder        => $folder,
                                             sort          => $sort,
                                             msgdatetype   => $msgdatetype,
                                             page          => $page,
                                             longpage      => $longpage,
                                             searchtype    => $searchtype,
                                             keyword       => $keyword,

                                             is_rowlabel   => 1,
                                             labeltext     => ow::datetime::week_of_year($dates->{year},$dates->{month},$days_of_month_matrix[$_][0] || $days_of_month_matrix[$_][6],$prefs{calendar_weekstart}),
                                             uselightbar   => $prefs{uselightbar},
                                             year          => $dates->{year},
                                             month         => $dates->{month},
                                             dayinrow      => $days_of_month_matrix[$_][0] || $days_of_month_matrix[$_][6],
                                          }
          ) for (0..$#days_of_month_matrix);

   # create a column label row with the columns date and day information
   unshift(@{$monthloop}, {
                             columns => [
                                          {
                                            is_collabel => 1,
                                            labeltext   => gettext('WK'),
                                          },
                                          map {
                                                my $weekday_number = ($prefs{calendar_weekstart} + $_) % 7;
                                                {
                                                  is_collabel => 1,
                                                  labeltext   => $dates->{lang}{wday}[$weekday_number],
                                                  is_saturday => $weekday_number == 6 ? 1 : 0,
                                                  is_sunday   => $weekday_number == 0 ? 1 : 0
                                                }
                                              } (0..6)
                                        ]
                          }
          );

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_monthview.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template     => get_header($config{header_template_file}),

                      # standard params
                      use_texticon        => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html            => $config{ow_htmlurl},
                      url_cgi             => $config{ow_cgiurl},
                      iconset             => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),
                      sessionid           => $thissession,
                      message_id          => $messageid,
                      folder              => $folder,
                      sort                => $sort,
                      msgdatetype         => $msgdatetype,
                      page                => $page,
                      longpage            => $longpage,
                      searchtype          => $searchtype,
                      keyword             => $keyword,

                      # standard calendar dates
                      %{$dates},

                      # cal_monthview.tmpl
                      cal_caller          => 'calmonth',
                      enable_preference   => $config{enable_preference},
                      enable_webmail      => $config{enable_webmail},
                      enable_addressbook  => $config{enable_addressbook},
                      enable_webdisk      => $config{enable_webdisk},
                      enable_sshterm      => $config{enable_sshterm},
                      monthselectloop     => [
                                               map { {
                                                       option      => $_,
                                                       label       => $dates->{lang}{month}[$_],
                                                       selected    => $_ eq $dates->{month} ? 1 : 0
                                                   } } @{[1..12]}
                                             ],
                      yearselectloop      => [
                                               map { {
                                                       option      => $_,
                                                       label       => $_,
                                                       selected    => $_ eq $dates->{year} ? 1 : 0
                                                   } } ($dates->{min_year}..$dates->{max_year})
                                             ],
                      monthloop           => $monthloop,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub viewday {
   my $dates = dates(param('year'), param('month'), param('day'));

   my @thisday_events = events($dates->{year}, $dates->{month}, $dates->{day});

   # create 24 hour matrix grid of the events
   my $matrix = matrix_24h(@thisday_events);

   $matrix = matrix_trim_empty_hour_rows($matrix);
   $matrix = matrix_labelrows($matrix);

   $matrix->[0]{columns}[1]{no_events} = 1 unless scalar @thisday_events;

   # calculate the offset in days from today
   my $thisymdtime = ow::datetime::array2seconds(0, 0, 12, $dates->{day}, $dates->{month} - 1, $dates->{year} - 1900);
   my $currenttime = ow::datetime::array2seconds(0, 0, 12, $dates->{current_day}, $dates->{current_month} - 1, $dates->{current_year} - 1900);
   my $daysfromtoday = int(($thisymdtime - $currenttime) / 86400);
   $daysfromtoday = "+$daysfromtoday" if $daysfromtoday >= 0;

   # prepare the form elements for the "add calendar event" form
   my $weekday_number = ow::datetime::weekday_number($dates->{year},$dates->{month},$dates->{day});

   my @hourlist = ('none', ($prefs{hourformat} == 12 ? (1..12) : (0..23)));

   my $weekorder = int(($dates->{day} + 6) / 7);

   my $eventcolorselectloop = [];
   foreach my $eventcolor (qw(1a 1b 1c 1d 1e 1f 2a 2b 2c 2d 2e 2f none)) {
      push(@{$eventcolorselectloop}, {
                                        option        => $eventcolor,
                                        label         => $eventcolor eq 'none' ? '--' : $eventcolor,
                                        selected      => 12,
                                        selectedindex => $#{$eventcolorselectloop} + 1,
                                     }
          )
   }

   my ($lunar_string, $lunar_isnew) = lunar_string($dates->{year}, $dates->{month}, $dates->{day});

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_dayview.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );
   $template->param(
                      # header.tmpl
                      header_template         => get_header($config{header_template_file}),

                      # standard params
                      use_texticon            => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html                => $config{ow_htmlurl},
                      url_cgi                 => $config{ow_cgiurl},
                      iconset                 => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),
                      sessionid               => $thissession,
                      message_id              => $messageid,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,

                      # standard calendar dates
                      %{$dates},

                      # cal_dayview.tmpl
                      cal_caller              => 'calday',
                      enable_preference       => $config{enable_preference},
                      enable_webmail          => $config{enable_webmail},
                      enable_addressbook      => $config{enable_addressbook},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      weekstart               => $prefs{calendar_weekstart},
                      is_weekend              => $weekday_number == 6 || $weekday_number == 0 ? 1 : 0,
                      daysfromtoday           => $daysfromtoday,
                      lunar                   => $lunar_string,
                      lunarnew                => $lunar_isnew,
                      matrix                  => $matrix,
                      dayselectloop           => [
                                                   map { {
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $dates->{day} ? 1 : 0
                                                       } } (1..ow::datetime::days_in_month($dates->{year},$dates->{month}))
                                                 ],
                      monthselectloop         => [
                                                   map { {
                                                            option      => $_,
                                                            label       => $dates->{lang}{month}[$_],
                                                            selected    => $_ eq $dates->{month} ? 1 : 0
                                                       } } (1..12)
                                                 ],
                      yearselectloop          => [
                                                   map { {
                                                            option      => $_,
                                                            label       => $_,
                                                            selected    => $_ eq $dates->{year} ? 1 : 0
                                                       } } ($dates->{min_year}..$dates->{max_year})
                                                 ],
                      is_12hourformat         => $prefs{hourformat} == 12 ? 1 : 0,
                      starthourselectloop     => [
                                                   map { {
                                                           option       => $_,
                                                           label        => $_ eq 'none' ? gettext('none') : sprintf("%02d", $_),
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
                      endhourselectloop       => [
                                                   map { {
                                                           option       => $_,
                                                           label        => $_ eq 'none' ? gettext('none') : sprintf("%02d", $_),
                                                           selected     => $_ eq $hourlist[0] ? 1 : 0
                                                       } } @hourlist
                                                 ],
                      endminselectloop        => [
                                                   map { {
                                                           option       => $_,
                                                           label        => sprintf("%02d", $_),
                                                           selected     => $_ eq '0' ? 1 : 0
                                                       } } (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55)
                                                 ],
                      dayfreqselectloop       => [
                                                   map { {
                                                           "option_$_"  => $_,
                                                           ordinal_num  => $weekorder == 1 ? gettext('1st') :
                                                                           $weekorder == 2 ? gettext('2nd') :
                                                                           $weekorder == 3 ? gettext('3rd') :
                                                                           $weekorder == 4 ? gettext('4th') :
                                                                           gettext('last'),
                                                           weekday      => $dates->{lang}{wday}[$weekday_number],
                                                       } } $weekorder <= 4
                                                           ? qw(thisdayonly thewdayofthismonth everywdaythismonth)
                                                           : qw(thisdayonly everywdaythismonth)
                                                 ],
                      monthfreqselectloop     => [
                                                   map { {
                                                           "option_$_"  => $_,
                                                       } } (
                                                              'thismonthonly',
                                                              ($dates->{month} % 2 ? 'everyoddmonththisyear' : 'everyevenmonththisyear'),
                                                              'everymonththisyear'
                                                           )
                                                 ],
                      eventcolorselectloop    => $eventcolorselectloop,

                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub viewweek {
   my $dates = dates(param('year'), param('month'), param('day'));

   my $time = ow::datetime::array2seconds(0, 0, 12, $dates->{day}, $dates->{month} - 1, $dates->{year} - 1900);
   my $weekstart_time = $time - 86400 * ((ow::datetime::weekday_number($dates->{year},$dates->{month},$dates->{day}) + 7 - $prefs{calendar_weekstart}) % 7);

   my @days            = ();
   my $maxallday       = 0;
   my $firsteventstart = $prefs{calendar_starthour};
   my $lasteventfinish = $prefs{calendar_endhour};

   # process each day of this week
   foreach my $col (0..6) {
      my ($week_year, $week_month, $week_day) = (ow::datetime::seconds2array($weekstart_time + $col * 86400))[5,4,3];

      $week_year += 1900;
      $week_month++;

      my @thisday_events = events($week_year, $week_month, $week_day);

      my ($lunar_string, $lunar_isnew) = lunar_string($week_year, $week_month, $week_day);

      # create 24 hour matrix grid of this days events
      my $matrix = matrix_24h(@thisday_events);

      # make sure the first column of the first row notes the year, month, day this day of
      # the matrix covers, even if there is no event in the first column of the first row
      $matrix->[0]{columns}[0]{year}      = $week_year;
      $matrix->[0]{columns}[0]{month}     = $week_month;
      $matrix->[0]{columns}[0]{day}       = $week_day;
      $matrix->[0]{columns}[0]{lunar}     = $lunar_string;
      $matrix->[0]{columns}[0]{lunar_new} = $lunar_isnew;
      $matrix->[0]{columns}[0]{is_today}  = (
                                              $week_year == $dates->{current_year}
                                              && $week_month == $dates->{current_month}
                                              && $week_day == $dates->{current_day}
                                            ) ? 1 : 0;

      $maxallday       = $matrix->[0]{allday_count} if $matrix->[0]{allday_count} > $maxallday;
      $firsteventstart = $matrix->[0]{firsteventstart} if $matrix->[0]{firsteventstart} < $firsteventstart;
      $lasteventfinish = $matrix->[0]{lasteventfinish} if $matrix->[0]{lasteventfinish} > $lasteventfinish;

      push(@days, $matrix);
   }

   my $week_matrix = [];

   # create new allday rows as needed until each
   # day matrix has the same number of rows
   for(my $daycol = 0; $daycol < @days; $daycol++) {
      while ($days[$daycol][0]{allday_count} < $maxallday) {
         splice(@{$days[$daycol]},$days[$daycol][0]{allday_count},0,{ time => 'allday' });
         foreach my $col (0..$#{$days[$daycol][0]{columns}}) {
            foreach my $key (keys %{$days[$daycol][0]{columns}[$col]}) {
               next unless $key =~ m#(?:colspan|rowspan|skip)#;
               $days[$daycol][$days[$daycol][0]{allday_count}]{columns}[$col]{$key} = $days[$daycol][0]{columns}[$col]{$key};
            }
         }
         $days[$daycol][0]{allday_count}++;
      }
   }

   # join the days together into the final week matrix
   for(my $daycol = 0; $daycol < @days; $daycol++) {
      foreach my $row (0..$#{$days[$daycol]}) {
         push(@{$week_matrix->[$row]{columns}}, @{$days[$daycol][$row]{columns}});
         $week_matrix->[$row]{time} = $days[$daycol][$row]{time};
      }
   }

   $week_matrix->[0]{allday_count}    = $maxallday;
   $week_matrix->[0]{firsteventstart} = $firsteventstart;
   $week_matrix->[0]{lasteventfinish} = $lasteventfinish;

   $week_matrix = matrix_trim_empty_hour_rows($week_matrix);
   $week_matrix = matrix_labelrows($week_matrix);
   $week_matrix = matrix_labelcols($week_matrix, $dates);

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_weekview.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );
   $template->param(
                      # header.tmpl
                      header_template    => get_header($config{header_template_file}),

                      # standard params
                      use_texticon       => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html           => $config{ow_htmlurl},
                      url_cgi            => $config{ow_cgiurl},
                      iconset            => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),
                      sessionid          => $thissession,
                      message_id         => $messageid,
                      folder             => $folder,
                      sort               => $sort,
                      msgdatetype        => $msgdatetype,
                      page               => $page,
                      longpage           => $longpage,
                      searchtype         => $searchtype,
                      keyword            => $keyword,

                      # standard calendar dates
                      %{$dates},

                      # cal_weekview.tmpl
                      cal_caller         => 'calweek',
                      enable_preference  => $config{enable_preference},
                      enable_webmail     => $config{enable_webmail},
                      enable_addressbook => $config{enable_addressbook},
                      enable_webdisk     => $config{enable_webdisk},
                      enable_sshterm     => $config{enable_sshterm},
                      week_matrix        => $week_matrix,
                      weekstart          => $prefs{calendar_weekstart},
                      dayselectloop      => [
                                              map { {
                                                      option      => $_,
                                                      label       => $_,
                                                      selected    => $_ eq $dates->{day} ? 1 : 0
                                                  } } (1..ow::datetime::days_in_month($dates->{year},$dates->{month}))
                                            ],
                      monthselectloop    => [
                                              map { {
                                                      option      => $_,
                                                      label       => $dates->{lang}{month}[$_],
                                                      selected    => $_ eq $dates->{month} ? 1 : 0
                                                  } } (1..12)
                                            ],
                      yearselectloop     => [
                                              map { {
                                                      option      => $_,
                                                      label       => $_,
                                                      selected    => $_ eq $dates->{year} ? 1 : 0
                                                  } } ($dates->{min_year}..$dates->{max_year})
                                            ],

                      # footer.tmpl
                      footer_template    => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub viewlist {
   my $dates = dates(param('year'));

   my $daysloop = [];

   foreach my $month_this_year (1..12) {
      foreach my $day_this_month (1..ow::datetime::days_in_month($dates->{year},$month_this_year)) {
         my @thisday_events = events($dates->{year}, $month_this_year, $day_this_month);

         my $is_today = (
                          $dates->{year} == $dates->{current_year}
                          && $month_this_year == $dates->{current_month}
                          && $day_this_month == $dates->{current_day}
                        ) ? 1 : 0;

         my $time = ow::datetime::array2seconds(1, 1, 1, $day_this_month, $month_this_year - 1, $dates->{year} - 1900);
         my $current_time = ow::datetime::array2seconds(1, 1, 1, $dates->{current_day}, $dates->{current_month} - 1, $dates->{current_year} - 1900);
         my $dayoffset_from_current = $is_today ? 0 : sprintf("%+d", int(($time - $current_time)/86400));

         if (scalar @thisday_events > 0 || $is_today) {
            my ($lunar_string, $lunar_isnew) = lunar_string($dates->{year}, $dates->{month}, $day_this_month);

            push(@{$daysloop}, {
                                 # standard params
                                 use_texticon    => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                 url_html        => $config{ow_htmlurl},
                                 url_cgi         => $config{ow_cgiurl},
                                 iconset         => $prefs{iconset},
                                 (map { $_, $icons->{$_} } keys %{$icons}),
                                 sessionid       => $thissession,
                                 message_id      => $messageid,
                                 folder          => $folder,
                                 sort            => $sort,
                                 msgdatetype     => $msgdatetype,
                                 page            => $page,
                                 longpage        => $longpage,
                                 searchtype      => $searchtype,
                                 keyword         => $keyword,

                                 year            => $dates->{year},
                                 month           => $month_this_year,
                                 monthname       => $dates->{lang}{month}[$month_this_year],
                                 day             => $day_this_month,
                                 dayname         => $dates->{lang}{wday}[ow::datetime::weekday_number($dates->{year},$month_this_year,$day_this_month)],
                                 daypadded       => sprintf("%02d",$day_this_month),
                                 uselightbar     => $prefs{uselightbar},
                                 lunar           => $lunar_string,
                                 lunarnew        => $lunar_isnew,
                                 is_today        => $is_today,
                                 eventsloop      => \@thisday_events,
                                 month_accesskey => ((qw(0 1 2 3 4 5 6 7 8 9 0 J Q))[$month_this_year]),
                                 dayoffset_from_current => $dayoffset_from_current,
                              }
                );
         }
      }
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_listview.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );
   $template->param(
                      # header.tmpl
                      header_template    => get_header($config{header_template_file}),

                      # standard params
                      use_texticon       => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html           => $config{ow_htmlurl},
                      url_cgi            => $config{ow_cgiurl},
                      iconset            => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),
                      sessionid          => $thissession,
                      message_id         => $messageid,
                      folder             => $folder,
                      sort               => $sort,
                      msgdatetype        => $msgdatetype,
                      page               => $page,
                      longpage           => $longpage,
                      searchtype         => $searchtype,
                      keyword            => $keyword,

                      # standard calendar dates
                      %{$dates},

                      # cal_listview.tmpl
                      cal_caller         => 'callist',
                      enable_preference  => $config{enable_preference},
                      enable_webmail     => $config{enable_webmail},
                      enable_addressbook => $config{enable_addressbook},
                      enable_webdisk     => $config{enable_webdisk},
                      enable_sshterm     => $config{enable_sshterm},
                      yearselectloop     => [
                                              map { {
                                                option   => $_,
                                                label    => $_,
                                                selected => $_ eq $dates->{year} ? 1 : 0
                                              } } ($dates->{min_year}..$dates->{max_year})
                                            ],
                      daysloop           => $daysloop,

                      # footer.tmpl
                      footer_template    => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub events {
   # return an array of hashes of the events occuring on a given year, month, day
   my ($year, $month, $day) = @_;

   my @thisday_events = ();

   foreach my $eventid (indexes($year, $month, $day)) {
      my ($eventtime, $eventlink, $eventlinktxt, $eventemail, $eventtxt, $eventcolor, $idate) = parse_event($eventid);

      push(@thisday_events, {
                               # standard params
                               use_texticon => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                               url_html     => $config{ow_htmlurl},
                               url_cgi      => $config{ow_cgiurl},
                               iconset      => $prefs{iconset},
                               (map { $_, $icons->{$_} } keys %{$icons}),
                               sessionid    => $thissession,
                               message_id   => $messageid,
                               folder       => $folder,
                               sort         => $sort,
                               msgdatetype  => $msgdatetype,
                               page         => $page,
                               longpage     => $longpage,
                               searchtype   => $searchtype,
                               keyword      => $keyword,

                               cal_caller   => param('cal_caller') || param('action') || $prefs{calendar_defaultview},
                               year         => $year,
                               month        => $month,
                               day          => $day,
                               eventtime    => $eventtime,
                               eventlink    => $eventlink,
                               eventlinktxt => $eventlinktxt,
                               eventemail   => $eventemail,
                               eventtxt     => $eventtxt,
                               eventcolor   => $eventcolor,
                               eventid      => $eventid,
                               is_multi     => $idate =~ /[\*|,|\|]/ ? 1 : 0,
                               is_global    => $eventid < 1E6 ? 0 : 1,
                               starthourmin => $events->{$eventid}{starthourmin},
                               endhourmin   => $events->{$eventid}{endhourmin},
                            }
          );
   }

   return @thisday_events;
}

sub indexes {
   # return a list of the event indexes occuring on a given year, month, and day
   my ($year, $month, $day) = @_;

   my ($date, $date2) = ow::datetime::yyyymmdd($year, $month, $day);

   my @thisday_indexes = sort {
                                $events->{$a}{starthourmin} <=> $events->{$b}{starthourmin}
                                || $events->{$a}{endhourmin} <=> $events->{$b}{endhourmin}
                                || $events->{$a}{string} cmp $events->{$b}{string}
                                || $b <=> $a
                              }
                         grep {
                                defined $events->{$_}{string}
                                &&
                                (
                                  $date =~ m/$events->{$_}{idate}/
                                  || $date2 =~ m/$events->{$_}{idate}/
                                  || ow::datetime::easter_match($year, $month, $day, $events->{$_}{idate})
                                )
                              } @{$index->{$date}}, @{$index->{'*'}}; # recurring events = '*'

   return @thisday_indexes;
}

sub dates {
   # return a complete collection of dates for a given year and/or month and/or day
   my $current_time = ow::datetime::time_gm2local(time(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($current_time))[5,4,3];

   $current_year += 1900;
   $current_month++;

   my $min_year = $current_year - 30;
   my $max_year = $current_year + 30;

   my $year  = shift || $current_year;
   my $month = shift || $current_month;
   my $day   = shift || $current_day;

   $year = $max_year if $year > $max_year;
   $year = $min_year if $year < $min_year;

   $month = 12 if $month > 12;
   $month = 1  if $month < 1;

   $day = 1 if $day < 1;
   $day = ow::datetime::days_in_month($year,$month) if $day > ow::datetime::days_in_month($year,$month);

   my $time = ow::datetime::array2seconds(0, 0, 12, $day, $month - 1, $year - 1900);

   # calculate all the previous and nexts
   my $prev_year = $year - 1;
   my $next_year = $year + 1;

   my ($prevmonth_year, $prevmonth_month) = $month == 1  ? ($prev_year, 12) : ($year, $month - 1);
   my ($nextmonth_year, $nextmonth_month) = $month == 12 ? ($next_year, 1)  : ($year, $month + 1);

   my ($prevday_year, $prevday_month, $prevday_day) = (ow::datetime::seconds2array($time - 86400))[5,4,3];
   my ($nextday_year, $nextday_month, $nextday_day) = (ow::datetime::seconds2array($time + 86400))[5,4,3];

   $prevday_year += 1900;
   $nextday_year += 1900;

   $prevday_month++;
   $nextday_month++;

   # calculate all the weeks information
   my $currentweekstart_time = $current_time - 86400 * ((ow::datetime::weekday_number($current_year,$current_month,$current_day) + 7 - $prefs{calendar_weekstart}) % 7);
   my ($currentweekstart_year, $currentweekstart_month, $currentweekstart_day) = (ow::datetime::seconds2array($currentweekstart_time))[5,4,3];
   my ($currentweekstop_year, $currentweekstop_month, $currentweekstop_day) = (ow::datetime::seconds2array($currentweekstart_time + 6 * 86400))[5,4,3];

   $currentweekstart_year += 1900;
   $currentweekstop_year  += 1900;

   $currentweekstart_month++;
   $currentweekstop_month++;

   my $weekstart_time = $time - 86400 * ((ow::datetime::weekday_number($year,$month,$day) + 7 - $prefs{calendar_weekstart}) % 7);
   my ($weekstart_year, $weekstart_month, $weekstart_day) = (ow::datetime::seconds2array($weekstart_time))[5,4,3];
   my ($weekstop_year, $weekstop_month, $weekstop_day) = (ow::datetime::seconds2array($weekstart_time + 6 * 86400))[5,4,3];

   $weekstart_year += 1900;
   $weekstop_year  += 1900;

   $weekstart_month++;
   $weekstop_month++;

   my ($prevweekstart_year, $prevweekstart_month, $prevweekstart_day) = (ow::datetime::seconds2array($weekstart_time - 7 * 86400))[5,4,3];
   my ($prevweekstop_year, $prevweekstop_month, $prevweekstop_day) = (ow::datetime::seconds2array($weekstart_time - 86400))[5,4,3];

   $prevweekstart_year += 1900;
   $prevweekstop_year  += 1900;

   $prevweekstart_month++;
   $prevweekstop_month++;

   my ($nextweekstart_year, $nextweekstart_month, $nextweekstart_day) = (ow::datetime::seconds2array($weekstart_time + 7 * 86400))[5,4,3];
   my ($nextweekstop_year, $nextweekstop_month, $nextweekstop_day) = (ow::datetime::seconds2array($weekstart_time + 13 * 86400))[5,4,3];

   $nextweekstart_year += 1900;
   $nextweekstop_year  += 1900;

   $nextweekstart_month++;
   $nextweekstop_month++;

   my $lang = {
                 month       => [
                                   '',
                                   gettext('January'),
                                   gettext('February'),
                                   gettext('March'),
                                   gettext('April'),
                                   gettext('May'),
                                   gettext('June'),
                                   gettext('July'),
                                   gettext('August'),
                                   gettext('September'),
                                   gettext('October'),
                                   gettext('November'),
                                   gettext('December')
                                ],
                 wday        => [
                                   gettext('Sunday'),
                                   gettext('Monday'),
                                   gettext('Tuesday'),
                                   gettext('Wednesday'),
                                   gettext('Thursday'),
                                   gettext('Friday'),
                                   gettext('Saturday')
                                ],
                 wday_abbrev => [
                                   map { s/'//g; $_ }
                                   split(/,/, gettext("'S','M','T','W','T','F','S'"))
                                ],
              };

   # return the collection
   return {
             lang                       => $lang,
             min_year                   => $min_year,
             max_year                   => $max_year,
             year                       => $year,
             month                      => $month,
             monthname                  => $lang->{month}[$month],
             day                        => $day,
             dayname                    => $lang->{wday}[ow::datetime::weekday_number($year,$month,$day)],
             prev_year                  => $prev_year,
             next_year                  => $next_year,
             prevmonth_year             => $prevmonth_year,
             prevmonth_month            => $prevmonth_month,
             prevmonth_monthname        => $lang->{month}[$prevmonth_month],
             nextmonth_year             => $nextmonth_year,
             nextmonth_month            => $nextmonth_month,
             nextmonth_monthname        => $lang->{month}[$nextmonth_month],
             prevday_year               => $prevday_year,
             prevday_month              => $prevday_month,
             prevday_monthname          => $lang->{month}[$prevday_month],
             prevday_day                => $prevday_day,
             prevday_dayname            => $lang->{wday}[ow::datetime::weekday_number($prevday_year,$prevday_month,$prevday_day)],
             nextday_year               => $nextday_year,
             nextday_month              => $nextday_month,
             nextday_monthname          => $lang->{month}[$nextday_month],
             nextday_day                => $nextday_day,
             nextday_dayname            => $lang->{wday}[ow::datetime::weekday_number($nextday_year,$nextday_month,$nextday_day)],
             current_year               => $current_year,
             current_month              => $current_month,
             current_monthname          => $lang->{month}[$current_month],
             current_day                => $current_day,
             current_dayname            => $lang->{wday}[ow::datetime::weekday_number($current_year,$current_month,$current_day)],
             current_weekofyear         => ow::datetime::week_of_year($current_year,$current_month,$current_day,$prefs{calendar_weekstart}),
             is_current_year            => $year == $current_year ? 1 : 0,
             is_current_month           => $month == $current_month ? 1 : 0,
             is_current_day             => $day == $current_day ? 1 : 0,
             is_current                 => ($year == $current_year && $month == $current_month && $day == $current_day) ? 1 : 0,
             weekofyear                 => ow::datetime::week_of_year($year,$month,$day,$prefs{calendar_weekstart}),
             weekstart_year             => $weekstart_year,
             weekstart_month            => $weekstart_month,
             weekstart_monthname        => $lang->{month}[$weekstart_month],
             weekstart_day              => $weekstart_day,
             weekstart_dayname          => $lang->{wday}[ow::datetime::weekday_number($weekstart_year,$weekstart_month,$weekstart_day)],
             weekstop_year              => $weekstop_year,
             weekstop_month             => $weekstop_month,
             weekstop_monthname         => $lang->{month}[$weekstop_month],
             weekstop_day               => $weekstop_day,
             weekstop_dayname           => $lang->{wday}[ow::datetime::weekday_number($weekstop_year,$weekstop_month,$weekstop_day)],
             prevweekofyear             => ow::datetime::week_of_year($prevweekstart_year,$prevweekstart_month,$prevweekstart_day,$prefs{calendar_weekstart}),
             prevweekstart_year         => $prevweekstart_year,
             prevweekstart_month        => $prevweekstart_month,
             prevweekstart_monthname    => $lang->{month}[$prevweekstart_month],
             prevweekstart_day          => $prevweekstart_day,
             prevweekstart_dayname      => $lang->{wday}[ow::datetime::weekday_number($prevweekstart_year,$prevweekstart_month,$prevweekstart_day)],
             prevweekstop_year          => $prevweekstop_year,
             prevweekstop_month         => $prevweekstop_month,
             prevweekstop_monthname     => $lang->{month}[$prevweekstop_month],
             prevweekstop_day           => $prevweekstop_day,
             prevweekstop_dayname       => $lang->{wday}[ow::datetime::weekday_number($prevweekstop_year,$prevweekstop_month,$prevweekstop_day)],
             nextweekofyear             => ow::datetime::week_of_year($nextweekstart_year,$nextweekstart_month,$nextweekstart_day,$prefs{calendar_weekstart}),
             nextweekstart_year         => $nextweekstart_year,
             nextweekstart_month        => $nextweekstart_month,
             nextweekstart_monthname    => $lang->{month}[$nextweekstart_month],
             nextweekstart_day          => $nextweekstart_day,
             nextweekstart_dayname      => $lang->{wday}[ow::datetime::weekday_number($nextweekstart_year,$nextweekstart_month,$nextweekstart_day)],
             nextweekstop_year          => $nextweekstop_year,
             nextweekstop_month         => $nextweekstop_month,
             nextweekstop_monthname     => $lang->{month}[$nextweekstop_month],
             nextweekstop_day           => $nextweekstop_day,
             nextweekstop_dayname       => $lang->{wday}[ow::datetime::weekday_number($nextweekstop_year,$nextweekstop_month,$nextweekstop_day)],
             currentweekofyear          => ow::datetime::week_of_year($current_year,$current_month,$current_day,$prefs{calendar_weekstart}),
             currentweekstart_year      => $currentweekstart_year,
             currentweekstart_month     => $currentweekstart_month,
             currentweekstart_monthname => $lang->{month}[$currentweekstart_month],
             currentweekstart_day       => $currentweekstart_day,
             currentweekstart_dayname   => $lang->{wday}[ow::datetime::weekday_number($currentweekstart_year,$currentweekstart_month,$currentweekstart_day)],
             currentweekstop_year       => $currentweekstop_year,
             currentweekstop_month      => $currentweekstop_month,
             currentweekstop_monthname  => $lang->{month}[$currentweekstop_month],
             currentweekstop_day        => $currentweekstop_day,
             currentweekstop_dayname    => $lang->{wday}[ow::datetime::weekday_number($currentweekstop_year,$currentweekstop_month,$currentweekstop_day)],
             is_current_week            => ($year == $current_year
                                            && ow::datetime::week_of_year($year,$month,$day,$prefs{calendar_weekstart})
                                            == ow::datetime::week_of_year($current_year,$current_month,$current_day,$prefs{calendar_weekstart})) ? 1 : 0,
          };
}

sub days_of_month_matrix {
   # returns a matrix of the days of the month for the requested year
   # the matrix is a data structure like: $days{$row}{$col} = $day_of_month
   my ($year, $month) = @_;

   my %weekday_ordering = qw(Sun 0 Mon 1 Tue 2 Wed 3 Thu 4 Fri 5 Sat 6);

   # re-order the weekdays per the users preferences (Wed 0 Thu 1 Fri 2 etc)
   %weekday_ordering = map { $_ => ($weekday_ordering{$_} + 7 - $prefs{calendar_weekstart}) % 7 } keys %weekday_ordering;

   # figure out weekday_today
   my $time = ow::datetime::array2seconds(0,0,12,1,$month - 1,$year - 1900);
   my $weekday_today = ow::datetime::seconds2array($time); # returns string like Thu Jan 1 12:00:00 2009
   $weekday_today =~ s/(\w+).*$/$1/; # remove everything except the weekday "Thu"

   my @day_of_month_matrix = ();

   my $day_of_month = 1;

   foreach my $row (0..5) {
      foreach my $col (0..6) {
         if (($row > 0 || $col >= $weekday_ordering{$weekday_today}) && $day_of_month <= ow::datetime::days_in_month($year, $month)) {
            $day_of_month_matrix[$row][$col] = $day_of_month;
            $day_of_month++;
         }
      }
   }

   return @day_of_month_matrix;
}

sub matrix_24h {
   # layout a list of events for a given day into a 24 hour matrix grid
   my @thisday_events = @_;

   my $matrix_rows = int(((23.99999 * 60) / $prefs{calendar_interval}));

   # initialize the matrix grid
   my $matrix = [
                  map { { columns => [], time => sprintf("%02d%02d",(int($_ / 60),int($_ % 60))) } }
                  map { $_ * $prefs{calendar_interval} } (0..$matrix_rows)
                ];

   my $firsteventstart = $prefs{calendar_starthour};
   my $lasteventfinish = $prefs{calendar_endhour};

   # populate the matrix grid with the events
   foreach my $event (@thisday_events) {
      my $start = $event->{starthourmin};
      my $end   = $event->{endhourmin};
      my $rows  = int(duration_minutes($start, $end) / $prefs{calendar_interval} + 0.99999);
      $event->{rowspan} = $rows || 1;
      if ($rows == 0) {
         unshift(@{$matrix}, { columns => [$event], time => 'allday' } );
      } else {
         my $col = 0;
         my $allday_rows = $#{$matrix} - $matrix_rows;
         my $startrow = int(duration_minutes('0000', $start) / $prefs{calendar_interval}) + $allday_rows;
         my $endrow   = $startrow + $rows - 1;
         if (defined $end && (($endrow + 1 - $allday_rows) * $prefs{calendar_interval}) < duration_minutes('0000', $end)) {
            $endrow++;
            $event->{rowspan}++;
         }
         $col++ while (scalar grep { defined $matrix->[$_]{columns}[$col] } ($startrow..$endrow));
         $matrix->[$startrow]{columns}[$col] = $event;
         $matrix->[$endrow--]{columns}[$col] = {} until $endrow == $startrow;
         $firsteventstart = $start if $start < $firsteventstart;
         $lasteventfinish = $end if $end > $lasteventfinish;
      }
   }

   # force a single row for allday events if there are no allday events
   my $allday_count = scalar grep { $_->{time} eq 'allday' } @{$matrix};
   unshift(@{$matrix}, { columns => [], time => 'allday' } ) if $allday_count == 0;

   # remember stats for this matrix
   $matrix->[0]{allday_count}    = $allday_count ? $allday_count : 1;
   $matrix->[0]{firsteventstart} = $firsteventstart;
   $matrix->[0]{lasteventfinish} = $lasteventfinish;

   # what is the max colspan of our matrix?
   my $maxcolspan = (reverse sort map { scalar @{$_->{columns}} } grep { ref($_->{columns}) eq 'ARRAY' } @{$matrix})[0] || 1;

   # extend the colspan of each cell in the matrix grid as much as possible
   for(my $row = 0; $row < scalar @{$matrix}; $row++) {
      for(my $col = 0; $col < $maxcolspan; $col++) {
         my $startcol = $col;
         if (not defined $matrix->[$row]{columns}[$col]) {
            while ($col+1 < $maxcolspan && not defined $matrix->[$row]{columns}[$col+1]) {
               $col++;
               $matrix->[$row]{columns}[$col]{skip}++;
            }
            $matrix->[$row]{columns}[$startcol]{colspan} = $col - $startcol + 1;
            $matrix->[$row]{columns}[$startcol]{rowspan} = 1;
         } else {
            if (exists $matrix->[$row]{columns}[$col]{eventtxt}) {
               my @eventrows = ($row..($row + $matrix->[$row]{columns}[$startcol]{rowspan} - 1));
               while ($col+1 < $maxcolspan) {
                  my $allclear = 1;
                  foreach my $eventrow (@eventrows) {
                     $allclear = 0 && last if defined $matrix->[$eventrow]{columns}[$col+1];
                  }
                  if ($allclear) {
                     $matrix->[$_]{columns}[$col+1]{skip}++ for @eventrows;
                     $col++;
                  } else {
                     last;
                  }
               }
               $matrix->[$row]{columns}[$startcol]{colspan} = $col - $startcol + 1;
            } else {
               $matrix->[$row]{columns}[$startcol]{skip}++;
            }
         }
      }
   }

   return $matrix;
}

sub matrix_trim_empty_hour_rows {
   # remove empty hour rows from a given matrix
   # the given matrix should have no row or column labels
   my $matrix = shift;

   for(my $row = 0; $row < @{$matrix}; $row++) {
      if ($matrix->[$row]{time} ne 'allday') {
         my $startrow = $row;

         my ($starthour, $startmin) = $matrix->[$row]{time} =~ m/^(\d{2})(\d{2})/;

         my $is_empty_hour = 1;

         # is this an empty hour row?
         if ($row > $matrix->[0]{allday_count} && $matrix->[$row-1]{time} =~ m/^$starthour/) {
            $is_empty_hour = 0;               # the previous row of this hour is still there
         } else {
            while ($row < @{$matrix}) {       # this is the beginning of this hour
               my $totalcolspan = 0;
               foreach my $col (0..$#{$matrix->[$row]{columns}}) {
                  last if exists $matrix->[$row]{columns}[$col]{eventtxt};
                  $totalcolspan += $matrix->[$row]{columns}[$col]{colspan} if exists $matrix->[$row]{columns}[$col]{colspan};
               }
               $is_empty_hour = 0 && last if $totalcolspan != scalar @{$matrix->[0]{columns}};
               last unless defined $matrix->[$row+1] && $matrix->[$row+1]{time} =~ m/^$starthour/;
               $row++;
            }
         }

         if ($is_empty_hour) {
            if (
                 $matrix->[$startrow]{time} >=
                 ($matrix->[0]{firsteventstart} < $prefs{calendar_starthour} ? $matrix->[0]{firsteventstart} : $prefs{calendar_starthour})
                 &&
                 $matrix->[$row]{time} <=
                 ($matrix->[0]{lasteventfinish} > $prefs{calendar_endhour} ? $matrix->[0]{lasteventfinish} : $prefs{calendar_endhour})
               ) {
               if (!$prefs{calendar_showemptyhours}) {
                  # remove this empty hour row
                  splice(@{$matrix},$startrow,$row-$startrow+1);
                  $row = $startrow-1;
                  next;
               }
            } else {
               # remove this empty hour row
               splice(@{$matrix},$startrow,$row-$startrow+1);
               $row = $startrow-1;
               next;
            }
         }

         $row = $startrow;
      }
   }

   return $matrix;
}

sub matrix_labelrows {
   # add row labels to a given matrix based on the
   # time information already provided in the matix
   my $matrix = shift;

   my $rowdark = 1;

   for(my $row = 0; $row < @{$matrix}; $row++) {
      if ($matrix->[$row]{time} eq 'allday') {
         # add a column for all our labels
         # add the allday row label to this row
         unshift(
                  @{$matrix->[$row]{columns}},
                  (
                    $row == 0
                    ? {
                        rowdark => 1,
                        colspan => 1,
                        rowspan => $matrix->[0]{allday_count},
                        timelabel => gettext('All Day'),
                        is_timelabel_allday => 1,
                      }
                    : { skip => 1 }
                  )
                );
      } else {
         my ($starthour, $startmin) = $matrix->[$row]{time} =~ m/^(\d{2})(\d{2})/;

         unless (exists $matrix->[$row]{columns}[0]{timelabel}) {
            my ($lasthour) = $matrix->[$row-1]{time} =~ m/^(\d{2})/ if $row > $matrix->[0]{allday_count};
            $rowdark = $rowdark ? 0 : 1 if (
                                            $row == $matrix->[0]{allday_count}
                                            ||
                                            (
                                              $row > $matrix->[0]{allday_count}
                                              && $matrix->[$row]{time} !~ m/^$lasthour/
                                            )
                                           );

            my $timelabel = $matrix->[$row-1]{time} !~ m/^$starthour/
                            ? hourmin2str($matrix->[$row]{time},$prefs{hourformat})
                            : $matrix->[$row-1]{time} =~ m/^$starthour/
                              ? defined $matrix->[$row+1]
                                ? $matrix->[$row+1]{time} =~ m/^$starthour/
                                  ? $matrix->[$row-1]{columns}[0]{timelabel} eq '' ? $startmin : ''
                                  : ''
                                : $matrix->[$row-1]{columns}[0]{timelabel} eq '' ? $startmin : ''
                              : '';

            # add the time label to this row
            unshift(
                     @{$matrix->[$row]{columns}},
                     {
                       colspan   => 1,
                       rowspan   => 1,
                       timelabel => $timelabel,
                       is_timelabel_hour   => $timelabel eq $startmin ? 0 : 1,
                       is_timelabel_minute => $timelabel eq $startmin ? 1 : 0,
                     }
                   );
         }
      }

      # set the rowdark key to determine the shading on all the columns of this row
      for(my $col = 0; $col < @{$matrix->[$row]{columns}}; $col++) {
         $matrix->[$row]{columns}[$col]{rowdark} = $rowdark
           unless (exists $matrix->[$row]{columns}[$col]{skip} || exists $matrix->[$row]{columns}[$col]{eventtxt});
      }
   }

   return $matrix;
}

sub matrix_labelcols {
   # label the columns of a given matrix using the year, month,
   # and day information already provided by the matrix
   my $matrix = shift;
   my $dates  = shift;

   # add a new row for our column labels
   unshift(@{$matrix}, { columns => [] });

   # populate our column labels
   for(my $col = 0; $col < @{$matrix->[1]{columns}}; $col++) {
      if (exists $matrix->[1]{columns}[$col]{timelabel}) {
         # do not label the rowlabel column
         $matrix->[0]{columns}[$col] = { colspan => 1, rowspan => 1 };
      } else {
         if (exists $matrix->[1]{columns}[$col]{colspan}) {
            my $weekday_number = ow::datetime::weekday_number(
                                                               $matrix->[1]{columns}[$col]{year},
                                                               $matrix->[1]{columns}[$col]{month},
                                                               $matrix->[1]{columns}[$col]{day},
                                                             );
            $matrix->[0]{columns}[$col] = {
                                            # standard params
                                            use_texticon         => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                            url_html             => $config{ow_htmlurl},
                                            url_cgi              => $config{ow_cgiurl},
                                            iconset              => $prefs{iconset},
                                            (map { $_, $icons->{$_} } keys %{$icons}),
                                            sessionid            => $thissession,
                                            message_id           => $messageid,
                                            folder               => $folder,
                                            sort                 => $sort,
                                            msgdatetype          => $msgdatetype,
                                            page                 => $page,
                                            longpage             => $longpage,
                                            searchtype           => $searchtype,
                                            keyword              => $keyword,

                                            cal_caller           => param('action') || $prefs{calendar_defaultview},
                                            colspan              => $matrix->[1]{columns}[$col]{colspan},
                                            rowspan              => 1,
                                            timelabel            => $dates->{lang}{wday}[$weekday_number],
                                            is_timelabel_weekday => 1,
                                            is_saturday          => $weekday_number == 6 ? 1 : 0,
                                            is_sunday            => $weekday_number == 0 ? 1 : 0,
                                            is_today             => $matrix->[1]{columns}[$col]{is_today},
                                            weekday_year         => $matrix->[1]{columns}[$col]{year},
                                            weekday_month        => $matrix->[1]{columns}[$col]{month},
                                            weekday_monthname    => $dates->{lang}{month}[$matrix->[1]{columns}[$col]{month}],
                                            weekday_day          => $matrix->[1]{columns}[$col]{day},
                                            weekday_lunar        => $matrix->[1]{columns}[$col]{lunar},
                                            weekday_lunar_new    => $matrix->[1]{columns}[$col]{lunar_new},
                                          };
         } else {
            $matrix->[0]{columns}[$col]{skip} = 1;
         }
      }
   }

   return $matrix;
}

sub parse_event {
   # parse and process calendar events to separate variables
   my $eventid = shift;

   my ($eventtime, $eventlink, $eventlinktxt, $eventemail, $eventtxt, $eventcolor) = ('','','','','','');

   if ($events->{$eventid}{starthourmin} ne "0") {
      $eventtime = hourmin2str($events->{$eventid}{starthourmin}, $prefs{hourformat});
      if ($events->{$eventid}{endhourmin} ne "0") {
        $eventtime .= qq| - | . hourmin2str($events->{$eventid}{endhourmin}, $prefs{hourformat});
      }
   } else {
      $eventtime = "#";
   }

   if ($events->{$eventid}{link}) {
      $eventlinktxt = $events->{$eventid}{link};
      $eventlink = $eventlinktxt;
      $eventlink =~ s/\%THISSESSION\%/$thissession/;
   }

   $eventemail = $events->{$eventid}{email};

   ($eventtxt) = iconv($events->{$eventid}{charset}, $prefs{charset}, $events->{$eventid}{string});
   $eventtxt =~ s/<.*?>//g;
   $eventtxt = substr($eventtxt, 0, 76) . "..." if length($eventtxt) > 80;
   $eventtxt = "$eventtxt *" if $eventid >= 1E6; # global eventids are numbered >= 1E6

   $eventcolor = defined $events->{$eventid}{eventcolor} && $events->{$eventid}{eventcolor} ne 'none' ? $events->{$eventid}{eventcolor} : 0;

   return($eventtime, $eventlink, $eventlinktxt, $eventemail, $eventtxt, $eventcolor, $events->{$eventid}{idate});
}

sub edit {
   my $dates = dates(param('year'), param('month'), param('day'));

   my $eventid = param('eventid') || '';

   my $starthour       = 'none';
   my $startmin        = 0;
   my $startampm       = 'am';
   my $endhour         = 'none';
   my $endmin          = 0;
   my $endampm         = 'am';
   my $eventtxt        = '';
   my $everyyear       = 0;
   my $monthfreq       = 'thismonthonly';
   my $dayfreq         = 'thisdayonly';
   my $dayofweek       = '';
   my $startdate       = 0;
   my $enddate         = 0;
   my $thisandnextdays = 0;
   my $nextdays        = 0;
   my $linkstring      = 'http://';
   my $emailstring     = '';
   my $eventcolor      = 'none';

   # deconstruct the idate to establish the edit form settings
   # see the open_calendars sub for more information on idates
   if ($eventid) {
      if ($events->{$eventid}{starthourmin} =~ m/0*(\d+)(\d{2})$/) {
         ($starthour, $startmin)  = ($1, $2);
         ($starthour, $startampm) = ow::datetime::hour24to12($starthour) if $prefs{hourformat} == 12;
      }

      if ($events->{$eventid}{endhourmin} =~ m/0*(\d+)(\d{2})$/) {
         ($endhour, $endmin)  = ($1, $2);
         ($endhour, $endampm) = ow::datetime::hour24to12($endhour) if $prefs{hourformat} == 12;
      }

      $eventtxt = (iconv($events->{$eventid}{charset}, $prefs{charset}, $events->{$eventid}{string}))[0];

      if ($events->{$eventid}{idate} =~ m/,/) {
          # idate has recurrance in it - deconstruct the recurrance
          ($everyyear, $monthfreq, $dayfreq, $dayofweek) = split(/,/, $events->{$eventid}{idate});
          my %weekorder_day_wild_reversed = (
                                              "0[1-7]"              => 1,
                                              "((0[8-9])|(1[0-4]))" => 2,
                                              "((1[5-9])|(2[0-1]))" => 3,
                                              "2[2-8]"              => 4,
                                            );

          $dayfreq = exists $weekorder_day_wild_reversed{$dayfreq} ? 'thewdayofthismonth' :
                     $dayfreq eq '.*' ? 'everywdaythismonth' : $dayfreq;

          $monthfreq = $monthfreq eq '(01|03|05|07|09|11)' ? 'everyoddmonththisyear'  :
                       $monthfreq eq '(02|04|06|08|10|12)' ? 'everyevenmonththisyear' :
                       $monthfreq eq '.*' ? 'everymonththisyear' : $monthfreq;

          $everyyear = $everyyear eq '.*' ? 1 : 0;
      } elsif ($events->{$eventid}{idate} =~ m/^\(?(\d+)\|?.*?\|?(\d+)?\)?$/) {
          # idates is like (20030808|20030809)
          $startdate = $1;
          $enddate   = $2 || '';
          if ($enddate) {
             # we have a nextdays recurrance here
             $thisandnextdays = 1;
             $nextdays = $events->{$eventid}{idate} =~ tr/|/|/; # count pipes - cheap and easy

             # set the dates to the startdate of this event, so we don't move
             # the event by using the date we came into the edit form with.
             my ($startyear, $startmonth, $startday) = $startdate =~ m/^(\d{4})(\d{2})(\d{2})$/;
             $dates = dates(int $startyear, int $startmonth, int $startday);
          }
      } else {
         openwebmailerror(gettext('Illegal event idate format:') . " $eventid");
         writelog("edit calitem error - idate wrong format, eventid=$eventid");
         writehistory("edit calitem error - idate wrong format, eventid=$eventid");
      }

      $linkstring  = $events->{$eventid}{link} || 'http://';

      $emailstring = $events->{$eventid}{email} || '';

      $eventcolor  = $events->{$eventid}{eventcolor} || 'none';
   }

   my @hourlist = ('none', ($prefs{hourformat} == 12 ? (1..12) : (0..23)));

   my $weekday_number = ow::datetime::weekday_number($dates->{year},$dates->{month},$dates->{day});
   my $weekorder = int(($dates->{day} + 6) / 7);

   my $eventcolorselectloop = [];
   foreach my $option (qw(1a 1b 1c 1d 1e 1f 2a 2b 2c 2d 2e 2f none)) {
      push(@{$eventcolorselectloop}, {
                                        option        => $option,
                                        label         => $option eq 'none' ? '--' : $option,
                                        selected      => $eventcolor eq $option ? 1 : 0,
                                        selectedindex => $#{$eventcolorselectloop} + 1,
                                     }
          )
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("cal_edit.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template      => get_header($config{header_template_file}),

                      # standard params
                      use_texticon         => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html             => $config{ow_htmlurl},
                      url_cgi              => $config{ow_cgiurl},
                      iconset              => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),
                      sessionid            => $thissession,
                      message_id           => $messageid,
                      folder               => $folder,
                      sort                 => $sort,
                      msgdatetype          => $msgdatetype,
                      page                 => $page,
                      longpage             => $longpage,
                      searchtype           => $searchtype,
                      keyword              => $keyword,

                      # standard calendar dates
                      %{$dates},

                      # cal_edit.tmpl
                      cal_caller           => param('cal_caller') || $prefs{calendar_defaultview},
                      eventid              => $eventid,
                      weekstart            => $prefs{calendar_weekstart},
                      is_hourformat12      => $prefs{hourformat} == 12 ? 1 : 0,
                      startam              => $startampm eq 'am' ? 1 : 0,
                      endam                => $endampm eq 'am' ? 1 : 0,
                      thisandnextdays      => $thisandnextdays,
                      nextdays             => $nextdays,
                      everyyear            => $everyyear,
                      eventtxt             => $eventtxt,
                      linkstring           => $linkstring,
                      emailstring          => $emailstring,
                      eventreminder        => $eventid ? $events->{$eventid}{eventreminder} : 1,
                      notifyenabled        => $config{calendar_email_notifyinterval} > 0 ? 1 : 0,
                      dayselectloop        => [
                                                map { {
                                                        option   => $_,
                                                        label    => $_,
                                                        selected => $_ eq $dates->{day} ? 1 : 0
                                                    } } (1..ow::datetime::days_in_month($dates->{year}, $dates->{month}))
                                              ],
                      monthselectloop      => [
                                                map { {
                                                        option   => $_,
                                                        label    => $dates->{lang}{month}[$_],
                                                        selected => $_ eq $dates->{month} ? 1 : 0
                                                    } } (1..12)
                                              ],
                      yearselectloop       => [
                                                map { {
                                                        option   => $_,
                                                        label    => $_,
                                                        selected => $_ eq $dates->{year} ? 1 : 0
                                                    } } ($dates->{min_year}..$dates->{max_year})
                                              ],
                      starthourselectloop  => [
                                                map { {
                                                        option   => $_,
                                                        label    => $_ eq 'none' ? gettext('none') : sprintf("%02d", $_),
                                                        selected => $_ eq $starthour ? 1 : 0
                                                    } } @hourlist
                                              ],
                      startminselectloop   => [
                                                map { {
                                                        option   => $_,
                                                        label    => sprintf("%02d", $_),
                                                        selected => $_ eq $startmin ? 1 : 0
                                                    } } (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55)
                                              ],
                      endhourselectloop    => [
                                                map { {
                                                        option   => $_,
                                                        label    => $_ eq 'none' ? gettext('none') : sprintf("%02d", $_),
                                                        selected => $_ eq $endhour ? 1 : 0
                                                    } } @hourlist
                                              ],
                      endminselectloop     => [
                                                 map { {
                                                         option   => $_,
                                                        label    => sprintf("%02d", $_),
                                                        selected => $_ eq $endmin ? 1 : 0
                                                    } } (0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55)
                                              ],
                      dayfreqselectloop    => [
                                                 map { {
                                                         "option_$_" => $_,
                                                         ordinal_num => $weekorder == 1 ? gettext('1st') :
                                                                        $weekorder == 2 ? gettext('2nd') :
                                                                        $weekorder == 3 ? gettext('3rd') :
                                                                        $weekorder == 4 ? gettext('4th') :
                                                                        gettext('last'),
                                                         weekday     => $dates->{lang}{wday}[$weekday_number],
                                                         selected    => $_ eq $dayfreq ? 1 : 0
                                                     } } $weekorder <= 4
                                                         ? qw(thisdayonly thewdayofthismonth everywdaythismonth)
                                                         : qw(thisdayonly everywdaythismonth)
                                              ],
                      monthfreqselectloop  => [
                                                 map { {
                                                         "option_$_" => $_,
                                                         selected    => $_ eq $monthfreq ? 1 : 0
                                                     } } (
                                                            'thismonthonly',
                                                            ($dates->{month} % 2 ? 'everyoddmonththisyear' : 'everyevenmonththisyear'),
                                                            'everymonththisyear'
                                                         )
                                              ],
                      eventcolorselectloop => $eventcolorselectloop,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub addmod {
   # add or modify a user calendar event
   my $dates = dates(param('year'), param('month'), param('day'));

   my $eventid         = param('eventid')         || 0;
   my $string          = param('string')          || '';
   my $starthour       = param('starthour')       || 0;
   my $startmin        = param('startmin')        || 0;
   my $startampm       = param('startampm')       || 'am';
   my $endhour         = param('endhour')         || 0;
   my $endmin          = param('endmin')          || 0;
   my $endampm         = param('endampm')         || 'am';
   my $link            = param('link')            || '';
   my $email           = param('email')           || '';
   my $dayfreq         = param('dayfreq')         || 'thisdayonly';
   my $thisandnextdays = param('thisandnextdays') || 0;
   my $nextdays        = param('nextdays')        || 0;
   my $monthfreq       = param('monthfreq')       || 0;
   my $everyyear       = param('everyyear')       || 0;
   my $eventcolor      = param('eventcolor')      || 'none';
   my $eventreminder   = param('eventreminder')   || 0;
   my $cal_caller      = param('cal_caller')      || $prefs{calendar_defaultview};

   if ($string !~ m/^\s*$/) {
      # check for input that would corrupt our @@@ separated flatfile database format
      openwebmailerror(gettext('The @@@ character sequence is not allowed in event strings or links.'))
         if $string =~ m/\@\@\@/ || $link =~ m/\@\@\@/;

      $string =~ s#\@$#\@ #; # do not allow trailing @ signs
      $string =~ s#^\@# \@#; # do not allow leading @ signs
      $link   =~ s#\@$#\@ #; # do not allow trailing @ signs
      $link   =~ s#^\@# \@#; # do not allow leading @ signs

      $link =~ s#\Q$thissession\E#\%THISSESSION\%#;

      $link  = 0 if $link !~ m#://[^\s]+#;
      $email = 0 if $email !~ m#[^\s@]+@[^\s@]+#;

      # convert time format to military time.
      if ($prefs{hourformat} == 12) {
         if ($starthour =~ m/^\d+$/) {
            $starthour += 12 if $startampm eq "pm" && $starthour < 12;
            $starthour = 0   if $startampm eq "am" && $starthour == 12;
         }

         if ($endhour =~ m/^\d+$/) {
            $endhour += 12 if $endampm eq "pm" && $endhour < 12;
            $endhour = 0   if $endampm eq "am" && $endhour == 12;
         }
      }

      my $starthourmin = $starthour =~ m/^\d+$/ ? sprintf("%02d%02d",$starthour,$startmin) : 0; # 0 != 0000; 0 == None
      my $endhourmin   = $endhour =~ m/^\d+$/   ? sprintf("%02d%02d",$endhour,$endmin)     : 0; # 0 != 0000; 0 == None

      openwebmailerror(gettext('The event start time occurs after the event end time.'))
        if $endhourmin =~ m/^\d{4}$/ && $starthourmin =~ m/^\d{4}$/ && $starthourmin > $endhourmin;

      my $time = ow::datetime::array2seconds(1,1,1, $dates->{day},$dates->{month} - 1,$dates->{year} - 1900);
      my $dayofweek = $ow::datetime::wday_en[(ow::datetime::seconds2array($time))[6]];

      my $stopwarnings = $ow::datetime::wday_en[0]; # use var again to eliminate warnings

      # construct the idate for this record.
      my $idate = '';
      if ($dayfreq eq 'thisdayonly' && $monthfreq eq 'thismonthonly' && !$everyyear) {
         if ($thisandnextdays && $nextdays) {
            openwebmailerror(gettext('The nextdays value must be numeric.')) if $nextdays !~ /\d+/;
            my @nextdates = map {
                                  my ($y,$m,$d) = (ow::datetime::seconds2array($time + 86400 * $_))[5,4,3];
                                  sprintf("%04d%02d%02d",$y+1900,$m+1,$d)
                                } (0..$nextdays);
            $idate = '(' . join('|',@nextdates) . ')'; # (20090420|20090421|20090422)
         } else {
            $idate = sprintf("%04d%02d%02d", $dates->{year}, $dates->{month}, $dates->{day});
         }
      } elsif ($dayfreq eq 'thewdayofthismonth') {
         my $year_wild  = $everyyear ? '.*' : sprintf("%04d", $dates->{year});

         my $month_wild = $monthfreq eq 'everyoddmonththisyear'  ? '(01|03|05|07|09|11)' :
                          $monthfreq eq 'everyevenmonththisyear' ? '(02|04|06|08|10|12)' :
                          $monthfreq eq 'everymonththisyear'     ? '.*' : sprintf("%02d", $dates->{month});

         my %weekorder_day_wild = (
                                    1 => '0[1-7]',
                                    2 => '((0[8-9])|(1[0-4]))',
                                    3 => '((1[5-9])|(2[0-1]))',
                                    4 => '2[2-8]',
                                  );

         my $weekorder = int(($dates->{day} + 6) / 7);

         my $day_wild = exists $weekorder_day_wild{$weekorder} ? $weekorder_day_wild{$weekorder} : sprintf("%02d", $dates->{day});

         $idate = "$year_wild,$month_wild,$day_wild,$dayofweek"; # .*,12,25,Wed or .*,.*,0[1-7],Wed
      } else {
         # everywdaythismonth and everything else...
         my $year_wild  = $everyyear ? '.*' : sprintf("%04d", $dates->{year});

         my $month_wild = $monthfreq eq 'everyoddmonththisyear'  ? '(01|03|05|07|09|11)' :
                          $monthfreq eq 'everyevenmonththisyear' ? '(02|04|06|08|10|12)' :
                          $monthfreq eq 'everymonththisyear'     ? '.*' : sprintf("%02d", $dates->{month});

         $idate = $dayfreq eq 'everywdaythismonth'
                  ? "$year_wild,$month_wild,.*,$dayofweek"
                  : "$year_wild,$month_wild," . sprintf("%02d", $dates->{day}) . ",.*";
      }

      my ($date, $date2) = ow::datetime::yyyymmdd($dates->{year}, $dates->{month}, $dates->{day});

      if (defined $eventid && $eventid =~ m/^\d+$/ && exists $events->{$eventid}) {
         if ($idate ne $events->{$eventid}{idate}) {
            # remove the eventid from the in-memory index for the dates on which it used to occur
            my $oldkey = $events->{$eventid}{idate} =~ m/[^\d]/ ? '*' : $events->{$eventid}{idate};
            @{$index->{$oldkey}} = grep { $_ != $eventid } @{$index->{$oldkey}};

            # add the eventid to the in-memory index for its new dates
            push(@{$index->{($idate =~ m/[^\d]/ ? '*' : $date)}},$eventid);
         }
      } else {
         $eventid++ while exists $events->{$eventid} || $eventid < 1;    # determine a new unique eventid
         push(@{$index->{($idate =~ m/[^\d]/ ? '*' : $date)}},$eventid); # add it to our in-memory index for this date
      }

      my $calbookfile = dotpath('calendar.book');

      # read the events from the user calbook
      my $user_events = {};
      my $user_index  = {};

      openwebmailerror(gettext('Cannot read calendar file:') . " $calbookfile ($!)")
        if readcalbook($calbookfile, $user_events, $user_index, 0) < 0;

      # add/update the event
      $user_events->{$eventid}{starthourmin}  = "$starthourmin"; # quotes preserve padding on 0000 miltary time
      $user_events->{$eventid}{endhourmin}    = "$endhourmin";   # quotes preserve padding on 0000 miltary time
      $user_events->{$eventid}{idate}         = $idate;
      $user_events->{$eventid}{string}        = $string;
      $user_events->{$eventid}{link}          = $link;
      $user_events->{$eventid}{email}         = $email;
      $user_events->{$eventid}{eventcolor}    = $eventcolor;
      $user_events->{$eventid}{charset}       = $prefs{charset};
      $user_events->{$eventid}{eventreminder} = $eventreminder;

      $events->{$eventid} = $user_events->{$eventid};            # update our in-memory global events hash

      # and save out the book
      openwebmailerror(gettext('Cannot write calendar file:') . " $calbookfile ($!)")
        if writecalbook($calbookfile, $user_events) < 0;

      my $msg = "add calitem - eventid=$eventid, start=$starthourmin, end=$endhourmin, str=$string";
      writelog($msg);
      writehistory($msg);

      # reset the lastcheck datetimestamp in the user's .notifycheck file
      my $notifycheckfile = dotpath('notify.check');

      if ($events->{$eventid}{email} && ($date =~ m/$events->{$eventid}{idate}/ || $date2 =~ m/$events->{$eventid}{idate}/)) {
         if (-f $notifycheckfile) {
            sysopen(FILEREAD, $notifycheckfile, O_RDONLY)
              or writelog("cannot open for read $notifycheckfile : $!");
            my $lastcheck = <FILEREAD>; # should be a one line timestamp like: 200904212400
            close(FILEREAD);

            if (defined $lastcheck && $lastcheck =~ m/$date(\d\d\d\d)/) {
               if ($events->{$eventid}{starthourmin} < $1) {
                  sysopen(FILEWRITE, $notifycheckfile, O_WRONLY|O_TRUNC|O_CREAT)
                    or writelog("cannot open for write $notifycheckfile : $!");
                  print FILEWRITE sprintf("%08d%04d",$date,$events->{$eventid}{starthourmin});
                  close(FILEWRITE);
               }
            }
         }
      }
   }

   $cal_caller eq 'calyear'  ? viewyear()  :
   $cal_caller eq 'calmonth' ? viewmonth() :
   $cal_caller eq 'calweek'  ? viewweek()  :
   $cal_caller eq 'calday'   ? viewday()   :
   $cal_caller eq 'callist'  ? viewlist()  :
   openwebmailerror(gettext('Caller has illegal characters.'));
}

sub del {
   # delete an event from the user's calendar
   my $eventid = param('eventid') || '';

   if ($eventid && exists $events->{$eventid}) {
      my ($eventtxt) = iconv($events->{$eventid}{charset}, $prefs{charset}, $events->{$eventid}{string});
      my $msg = "delete calitem - eventid=$eventid, starthourmin=$events->{$eventid}{starthourmin}, eventtxt=$eventtxt";

      my $calbookfile = dotpath('calendar.book');

      # read the events from this calbook only
      my ($user_events, $user_index) = ({},{});
      openwebmailerror(gettext('Cannot read calendar file:') . " $calbookfile ($!)")
        if readcalbook($calbookfile, $user_events, $user_index, 0) < 0;

      # make the change
      delete $user_events->{$eventid};

      # and save it out
      openwebmailerror(gettext('Cannot write calendar file:') . " $calbookfile ($!)")
        if writecalbook($calbookfile, $user_events) < 0;

      writelog($msg);
      writehistory($msg);

      # update our in-memory hash of all events
      delete $events->{$eventid};
   }

   my $cal_caller = param('cal_caller') || $prefs{calendar_defaultview};
   $cal_caller eq 'calyear'  ? viewyear()  :
   $cal_caller eq 'calmonth' ? viewmonth() :
   $cal_caller eq 'calweek'  ? viewweek()  :
   $cal_caller eq 'calday'   ? viewday()   :
   $cal_caller eq 'callist'  ? viewlist()  :
   openwebmailerror(gettext('Caller has illegal characters.'));
}

sub duration_minutes {
   # returns the duration in minutes between two military times
   my ($start, $end) = @_;

   return 0 unless defined $start;
   return 0 unless $start =~ m/\d{4}$/;
   my ($starthour, $startmin) = $start =~ m/(\d+)(\d{2})$/;

   $end = sprintf('%02d', ($starthour + int(($startmin + $prefs{calendar_interval}) / 60))) .
          sprintf('%02d', (($startmin + $prefs{calendar_interval}) % 60))
          unless defined $end && $end =~ m/\d{4}$/;
   my ($endhour, $endmin) = $end =~ m/(\d+)(\d{2})$/;

   return $start > $end ? 0 : (($endhour * 60 + $endmin) - ($starthour * 60 + $startmin));
}

sub hourmin2str {
   # converts military time (eg:1700) to a time string (eg:05:00 pm)
   my ($hourmin, $hourformat) = @_;

   if ($hourmin =~ /(\d+)(\d{2})$/) {
      my ($hour, $min) = (int($1), $2);
      if ($hourformat == 12) {
         my $ampm = '';
         ($hour, $ampm) = ow::datetime::hour24to12($hour);

         my $hourstring = gettext('<tmpl_var hour escape="none">:<tmpl_var min escape="none"><tmpl_var ampm escape="none">');

         my $template = HTML::Template->new(scalarref => \$hourstring);
         $template->param(
                            hour => $hour,
                            min  => $min,
                            ampm => $ampm eq 'am' ? gettext('am') : gettext('pm'),
                         );

         $hourmin = $template->output;
      } else {
         $hourmin = sprintf("%02d", $hour) . ':' . sprintf("%02d", $min);
      }
   }

   return $hourmin;
}

sub lunar_string {
   # create a lunar calendar string for a given solar year, month, and day
   my ($year, $month, $day) = @_;

   my $lang = {
                 lunar_month => [
                                   '', # lunarmonth is not 0 index based
                                   gettext('Primens'),
                                   gettext('Apricomens'),
                                   gettext('Peacimens'),
                                   gettext('Plumens'),
                                   gettext('Guavamens'),
                                   gettext('Lotumens'),
                                   gettext('Orchimens'),
                                   gettext('Osmanthumens'),
                                   gettext('Chrysanthemens'),
                                   gettext('Benimens'),
                                   gettext('Hiemens'),
                                   gettext('Lamens'),
                                ],
              };

   my $lunar_string = '';
   my $lunar_isnew  = 0;

   if ($prefs{calendar_showlunar}) {
      my ($lunaryear, $lunarmonth, $lunarday) = solar2lunar($year, $month, $day);

      $lunar_string = defined $lunarmonth && defined $lunarday
                      ? $lunarmonth =~ m/^\+(\d+)/
                        ? gettext('intercalary') . $lang->{lunar_month}[int($1)] . int($lunarday)
                        : $lang->{lunar_month}[$lunarmonth] . int($lunarday)
                      : '';

      $lunar_isnew = $lunarday =~ m/^(?:01|15)$/ ? 1 : 0;
   }

   return($lunar_string, $lunar_isnew);
}

#                       OPENWEBMAIL CALENDAR DATA STRUCTURES
#
# %index: a hash of arrays of all the event id numbers that take place each day.
#         The hash key '*' stores all of the recurring events.
# %index = (
#            20030220 => [
#                          10, # an event number
#                          11, # another event number
#                        ],
#                   * => [
#                          1,  # a recurring event number (* is the key for recurring events)
#                        ],
#          );
#
# %events: each item contains information about the event that takes place.
# %events = (
#            10 => {
#                    email        => 0,
#                    starthourmin => 0, # all day event
#                    endhourmin   => 0,
#                    eventcolor   => '2a',
#                    link         => 0,
#                    string       => 'a friends birthday',
#                    idate        => 20030220,
#                  },
#            11 => {
#                    email        => 'test@example.com',
#                    starthourmin => 1900,
#                    endhourmin   => 2200,
#                    eventcolor   => '1e',
#                    link         => 'http://yahoo.com',
#                    string       => 'birthday dinner',
#                    idate        => 20030220,
#                  },
#             1 => {
#                    email        => 0,
#                    starthourmin => 0600,
#                    endhourmin   => 0800,
#                    eventcolor   => '1a',
#                    link         => 'http://exercise.com',
#                    string       => 'morning workout',
#                    idate        => '.*,.*,.*,.*', # recurring
#                  }
#          );
#
# IDATE FORMATS:
#    <years><months><days><dayofweek>
#    20030808                            The event occurs on August 8, 2003, This Month, This Day only
#    (20030808|20030809)                 The event occurs on August 8 & 9, 2003 (or August 8 and Next 1 day)
#    .*,04,07,.*                         The event occurs on April 7, Every Year
#    .*,.*,((1[5-9])|(2[0-1])),Tue       The event occurs on the 3rd Tuesday, Every Month, Every Year
#    2003,.*,.*,Wed                      The event occurs Every Wednesday, Every Week of 2003
#    2003,.*,11,.*                       The event occurs Every 11th day, Every Month of 2003

