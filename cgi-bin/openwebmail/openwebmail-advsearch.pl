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
use HTML::Template 2.9;
use MIME::Base64;
use MIME::QuotedPrint;

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "modules/mailparse.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/getmsgids.pl";
require "shares/adrbook.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config $thissession $user %prefs $icons);

# extern vars
use vars qw($htmltemplatefilters $po);                       # defined in ow-shared.pl
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM
            $_RECVDATE $_DATE $_FROM $_TO $_SUBJECT
            $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES); # defined in maildb.pl

# local globals
use vars qw($folder $messageid $sort $msgdatetype $page $longpage $searchtype $keyword);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(gettext('Access denied: the advanced search module is not enabled.'))
   if !$config{enable_webmail} || !$config{enable_advsearch};

# webmail globals
$folder          = param('folder') || 'INBOX';
$page            = param('page') || 1;
$longpage        = param('longpage') || 0;
$sort            = param('sort') || $prefs{sort} || 'date_rev';
$searchtype      = param('searchtype') || '';
$keyword         = param('keyword') || '';
$msgdatetype     = param('msgdatetype') || $prefs{msgdatetype};
$messageid       = param('message_id') || '';

my $action  = param('action') || '';

writelog("debug_request :: request advsearch begin, action=$action") if $config{debug_request};

$action eq 'advsearch' ? advsearch() : openwebmailerror(gettext('Action has illegal characters.'));

writelog("debug_request :: request advsearch end, action=$action") if $config{debug_request};

openwebmail_requestend();


# BEGIN SUBROUTINES

sub advsearch {
   # build the folders list
   my @folders = param('folders');
   @folders = map { safefoldername(ow::tool::unescapeURL($_)) } @folders;

   my (@validfolders, $inboxusage, $folderusage) = ((),0,0);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   # build the date selections - depends on the users dateformat preference
   my $localtime = ow::datetime::time_gm2local(time(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($localtime))[5, 4, 3];
   $current_year += 1900;
   $current_month++;

   my $min_year = $current_year - 30;
   my $max_year = $current_year + 30;

   my $daterange  = param('daterange')  || 'all';
   my $startyear  = param('startyear')  || $min_year;
   my $startmonth = param('startmonth') || $current_month;
   my $startday   = param('startday')   || $current_day;
   my $endyear    = param('endyear')    || $current_year;
   my $endmonth   = param('endmonth')   || $current_month;
   my $endday     = param('endday')     || $current_day;

   # build the result list
   my $resultlines = param('resultlines') || $prefs{msgsperpage} || 10,

   my $startseconds = ow::datetime::array2seconds(0, 0, 0, $startday, $startmonth - 1, $startyear - 1900);
   my $startserial  = ow::datetime::gmtime2dateserial(ow::datetime::time_local2gm(
                        $startseconds, $prefs{timeoffset}, $prefs{daylighsaving}, $prefs{timezone}));

   my $endseconds = ow::datetime::array2seconds(0, 0, 0, $endday, $endmonth - 1, $endyear - 1900);
   $endseconds   += 86400; # add 24 hours (86400 seconds) so that the end day is included in the search
   my $endserial  = ow::datetime::gmtime2dateserial(ow::datetime::time_local2gm(
                        $endseconds, $prefs{timeoffset}, $prefs{daylighsaving}, $prefs{timezone}));

   openwebmailerror(gettext('The search start date is after the search end date.'))
      if $startserial gt $endserial;

   my $resultsloop = [];
   my $totalsize   = 0;
   my $totalfound  = 0;

   if ($startserial =~ m/^\d{14}$/ && $endserial =~ m/^\d{14}$/ && param('search')) {
      my $search = [
                      map {
                             my $searchtext = param("searchtext_$_") || '';
                             $searchtext =~ s/^\s+//;
                             $searchtext =~ s/\s+$//;

                             {
                                where => param("where_$_") || 'subject',
                                type  => param("type_$_") || 'contains',
                                text  => $searchtext,
                             }
                          } (0..2) # number of filter rows
                   ];

      my $results = search_folders($startserial, $endserial, $search, \@folders);

      $totalfound = scalar @{$results};

      # load the contacts map of email addresses to xowmuids
      # so we can provide quick links to contact information
      my $contacts = {};

      if ($config{enable_addressbook} && $totalfound > 0) {
         foreach my $abookfoldername (get_readable_abookfolders()) {
            my $abookfile = abookfolder2file($abookfoldername);

            # filter based on searchterms and prune based on only_return
            my $thisbook = readadrbook($abookfile, undef, { 'X-OWM-UID' => 1, 'X-OWM-GROUP' => 1, EMAIL => 1 });

            foreach my $xowmuid (keys %{$thisbook}) {
               next if exists $thisbook->{$xowmuid}{'X-OWM-GROUP'};
               next unless exists $thisbook->{$xowmuid}{EMAIL};
               $contacts->{lc($_->{VALUE})} = $xowmuid for @{$thisbook->{$xowmuid}{EMAIL}};
            }
         }
      }

      # prepare the results for display
      for (my $i = 0; $i < $totalfound; $i++) {
         last if $i > $resultlines;
         $totalsize += $results->[$i]{attr}[$_SIZE];

         # convert from message charset to current user charset
         my $messagecharset = $results->[$i]{attr}[$_CHARSET];
         if ($messagecharset eq '' && $prefs{charset} eq 'utf-8') {
            # assume message is from sender using same language as the recipients browser
            $messagecharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{available_locales})))[4];
         }

         my $folder  = $results->[$i]{folder};

         my ($from, $to, $subject) = iconv('utf-8', $prefs{charset}, $results->[$i]{attr}[$_FROM], $results->[$i]{attr}[$_TO], $results->[$i]{attr}[$_SUBJECT]);
         my ($from_name, $from_address) = ow::tool::email2nameaddr($from);

         my @namelist = ();
         my @addrlist = ();
         my @recvlist = ow::tool::str2list($to);
         foreach my $recv (@recvlist) {
            my ($n, $a) = ow::tool::email2nameaddr($recv);
            # if $n or $a has ", $recv may be an incomplete addr
            push(@namelist, $n) if $n !~ m/"/;
            push(@addrlist, $a) if $a !~ m/"/;
         }

         my ($to_name, $to_address) = (join(',', @namelist), join(',', @addrlist));
         $to_name    = substr($to_name, 0, 29)    . '...' if length($to_name) > 32;
         $to_address = substr($to_address, 0, 61) . '...' if length($to_address) > 64;

         my $subject_keyword = $subject;
         $subject_keyword =~ s/^(?:\s*.{1,3}[.\s]*:\s*)+//; # strip leading Re: Fw: R: Res: Ref:
         $subject_keyword =~ s/\[.*?\]:?//g;                # strip leading [listname] type text

         $subject    = substr($subject, 0, 64)    . "..." if length($subject) > 67;
         $subject    =~ s/^\s+$//; # empty spaces-only subjects

         push (@{$resultsloop}, {
                                   # standard params
                                   sessionid            => $thissession,
                                   folder               => $folder,
                                   message_id           => $messageid,
                                   sort                 => $sort,
                                   page                 => $page,
                                   longpage             => $longpage,
                                   url_cgi              => $config{ow_cgiurl},
                                   url_html             => $config{ow_htmlurl},
                                   use_texticon         => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                                   iconset              => $prefs{iconset},
                                   (map { $_, $icons->{$_} } keys %{$icons}),

                                   # results
                                   odd                  => $i % 2 == 0 ? 1 : 0,
                                   is_defaultfolder     => is_defaultfolder($folder) ? 1 : 0,
                                   "foldername_$folder" => $folder,
                                   foldername           => f2u($folder),
                                   date                 => ow::datetime::dateserial2str($results->[$i]{attr}[$_DATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                                                                        $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}),
                                   useminisearchicon    => $prefs{useminisearchicon} ? 1 : 0,
                                   from                 => $from,
                                   from_name            => $from_name,
                                   from_address         => $from_address,
                                   from_xowmuid         => exists $contacts->{lc($from_address)} ? $contacts->{lc($from_address)} : 0,
                                   to                   => $to,
                                   to_address           => $to_address,
                                   to_name              => $to_name,
                                   headers              => $prefs{headers} || 'simple',
                                   message_id           => $results->[$i]{msgid},
                                   messagecharset       => $messagecharset,
                                   subject              => $subject,
                                   subject_keyword      => $subject_keyword,
                                   size                 => lenstr($results->[$i]{attr}[$_SIZE], 0),
                                }
              );
      }
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("advsearch.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

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
                      url_cgi                    => $config{ow_cgiurl},
                      url_html                   => $config{ow_htmlurl},
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      iconset                    => $prefs{iconset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # advsearch.tmpl
                      is_callerfolderdefault     => is_defaultfolder($folder) ? 1 : 0,
                      "callerfoldername_$folder" => 1,
                      callerfoldername           => f2u($folder),
                      allbox                     => param('allbox') || 0,
                      foldersloop                => [
                                                       map {
                                                              my $i = $_;
                                                              {
                                                                 nextrow                        => ($i + 1) % 4 == 0 ? 1 : 0,
                                                                 is_defaultfolder               => is_defaultfolder($validfolders[$i]) ? 1 : 0,
                                                                 "foldername_$validfolders[$i]" => $validfolders[$i],
                                                                 foldername                     => f2u($validfolders[$i]),
                                                                 checked                        => scalar grep { m/^\Q$validfolders[$i]\E$/ } @folders,
                                                              }
                                                           } (0..$#validfolders)
                                                    ],
                      weekstart                  => $prefs{calendar_weekstart},
                      min_year                   => $min_year,
                      max_year                   => $max_year,
                      startdateselectloop        => [
                                                       map {
                                                              $_ eq 'yyyy'
                                                              ? {
                                                                   startyearselectloop => [
                                                                                             map { {
                                                                                                      option      => $_,
                                                                                                      label       => sprintf('%02d', $_),
                                                                                                      selected    => $_ eq $startyear ? 1 : 0
                                                                                                 } } ($min_year..$max_year)
                                                                                          ]
                                                                }
                                                              : $_ eq 'mm'
                                                              ? {
                                                                   startmonthselectloop => [
                                                                                              map { {
                                                                                                       option      => $_,
                                                                                                       label       => sprintf('%02d', $_),
                                                                                                       selected    => $_ eq $startmonth ? 1 : 0
                                                                                                  } } (1..12)
                                                                                           ]
                                                                }
                                                              : {
                                                                   startdayselectloop   => [
                                                                                              map { {
                                                                                                       option      => $_,
                                                                                                       label       => sprintf('%02d', $_),
                                                                                                       selected    => $_ eq $startday ? 1 : 0
                                                                                                  } } (1..ow::datetime::days_in_month($startyear,$startmonth))
                                                                                           ]
                                                                }
                                                           } split(/[^ymd]/, $prefs{dateformat})
                                                    ],
                      enddateselectloop          => [
                                                       map {
                                                              $_ eq 'yyyy'
                                                              ? {
                                                                   endyearselectloop => [
                                                                                           map { {
                                                                                                    option      => $_,
                                                                                                    label       => $_,
                                                                                                    selected    => $_ eq $endyear ? 1 : 0
                                                                                               } } ($min_year..$max_year)
                                                                                        ]
                                                                }
                                                              : $_ eq 'mm'
                                                              ? {
                                                                   endmonthselectloop => [
                                                                                            map { {
                                                                                                     option      => $_,
                                                                                                     label       => sprintf('%02d', $_),
                                                                                                     selected    => $_ eq $endmonth ? 1 : 0
                                                                                                } } (1..12)
                                                                                         ]
                                                                }
                                                              : {
                                                                   enddayselectloop   => [
                                                                                            map { {
                                                                                                     option      => $_,
                                                                                                     label       => sprintf('%02d', $_),
                                                                                                     selected    => $_ eq $endday ? 1 : 0
                                                                                                } } (1..ow::datetime::days_in_month($endyear,$endmonth))
                                                                                         ]
                                                                }
                                                           } split(/[^ymd]/, $prefs{dateformat})
                                                    ],
                      daterange                  => [
                                                       map { {
                                                                "option_$_" => $_,
                                                                selected    => $_ eq $daterange ? 1 : 0
                                                           } } qw(all today oneweek twoweeks onemonth threemonths sixmonths oneyear)
                                                    ],
                      filtersloop                => [
                                                       map {
                                                              my $selected_where = param("where_$_") || 'subject';

                                                              my $selected_type  = param("type_$_") || 'contains';

                                                              my $searchtext = param("searchtext_$_") || '';
                                                              $searchtext =~ s/^\s+//;
                                                              $searchtext =~ s/\s+$//;

                                                              {
                                                                 row         => $_,
                                                                 lastrow     => $_ == 2 ? 1 : 0,
                                                                 whereloop   => [
                                                                                   map { {
                                                                                            "option_$_" => $_,
                                                                                            selected    => $_ eq $selected_where ? 1 : 0,
                                                                                       } } qw(from to subject date attfilename header textcontent all)
                                                                                ],
                                                                 typeloop    => [
                                                                                   map { {
                                                                                            "option_$_" => $_,
                                                                                            selected    => $_ eq $selected_type ? 1 : 0,
                                                                                       } } qw(contains notcontains is isnot startswith endswith regexp)
                                                                                ],
                                                                 searchtext  => $searchtext,
                                                              }
                                                           } (0..2) # number of filter rows
                                                    ],
                      resultlines                => $resultlines,
                      numberselectedfolders      => scalar @folders,
                      showall                    => $totalfound > $resultlines ? 1 : 0,
                      totalfound                 => $totalfound,
                      totalfoundstring           => sprintf(ngettext('%d match found', '%d matches found', $totalfound), $totalfound),
                      totalsize                  => lenstr($totalsize, 1),
                      resultsloop                => $resultsloop,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );


   httpprint([], [$template->output]);
}

sub search_folders {
   my ($startserial, $endserial, $r_search, $r_folders) = @_;

   my $results = [];

   # build the metainfo string of our current search parameters
   my $metainfo = $startserial . '@@@' . $endserial . '@@@';
   foreach my $search (@{$r_search}) {
      $metainfo .= join('@@@', $search->{where}, $search->{type}, $search->{text}) if $search->{text} ne '';
   }
   $metainfo .= '@@@' . join('@@@', @{$r_folders});

   # get the cached metainfo of previous search parameters
   my $cachefile = dotpath('search.cache');

   if (-f $cachefile) {
      ow::filelock::lock($cachefile, LOCK_EX) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($cachefile) . " ($!)");

      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($cachefile) . " ($!)");

      my $cache_metainfo = <CACHE>;

      chomp($cache_metainfo);

      if ($cache_metainfo eq $metainfo) {
         # get the cached results
         my $totalfound = <CACHE>;     # read the next line, which contains the totalfound count
         while (my $line = <CACHE>) {  # read each line of results
            chomp($line);
            my ($folder, $msgid, @attr) = split(/\@\@\@/, $line);
            push(@{$results}, {
                                 folder => $folder,
                                 msgid  => $msgid,
                                 attr   => \@attr,
                              }
                );
         }
      }

      close(CACHE) or
         openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($cachefile) . " ($!)");

      ow::filelock::lock($cachefile, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . ' ' . f2u($cachefile) . " ($!)");
   }

   return $results if scalar @{$results};

   # no matching cache found - perform new search
   $results = search_folders2($startserial, $endserial, $r_search, $r_folders);

   # write the metainfo, totalfound, and attributes to the cache
   ow::filelock::lock($cachefile, LOCK_EX) or
      openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($cachefile) . " ($!)");

   sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($cachefile) . " ($!)");

   print CACHE $metainfo, "\n";                                                             # metainfo
   print CACHE scalar @{$results}, "\n";                                                    # totalfound
   print CACHE join('@@@', $_->{folder}, $_->{msgid}, @{$_->{attr}}), "\n" for @{$results}; # attributes

   close(CACHE) or
      openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($cachefile) . " ($!)");

   ow::filelock::lock($cachefile, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . ' ' . f2u($cachefile) . " ($!)");

   return($results);
}

sub search_folders2 {
   my ($startserial, $endserial, $r_search, $r_folders) = @_;

   # order searches by speed
   my %speed = (
                  from        => 1, # fastest search
                  to          => 2,
                  subject     => 3,
                  date        => 4,
                  header      => 5,
                  all         => 6,
                  attfilename => 7,
                  textcontent => 8, # slowest search
               );

   my @validsearch = grep { $_->{text} ne '' }
                     sort { $speed{$a->{where}} <=> $speed{$b->{where}} }
                     @{$r_search};

   my @results = ();

   return \@results unless scalar @validsearch;

   foreach my $foldertosearch (@{$r_folders}) {
      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertosearch);

      next if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB));

      if (!update_folderindex($folderfile, $folderdb) < 0) {
         writelog("db error - cannot update index db $folderdb");
         writehistory("db error - cannot update index db $folderdb");
         ow::filelock::lock($folderfile, LOCK_UN);
         next;
      }

      my $r_messageids = get_messageids_sorted_by_sentdate($folderdb, 1);

      my (%FDB, %status);

      ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb) . " ($!)");

      sysopen(FOLDER, $folderfile, O_RDONLY) or # used in TEXTCONTENT search
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($folderfile) . " ($!)");

      foreach my $msgid (@{$r_messageids}) {
         # begin the search
         my ($block, $header, $body, $r_attachments) = ('','','',());
         my @attr = string2msgattr($FDB{$msgid});
         my $messagecharset = $attr[$_CHARSET];
         if ($messagecharset eq '' && $prefs{charset} eq 'utf-8') {
            # assume message is from sender using same language as the recipients browser
            $messagecharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{available_locales})))[4];
         }

         # skip this msg if is not within date range
         next if $attr[$_DATE] lt $startserial || $attr[$_DATE] gt $endserial;

         my $total_matched = 0;
         foreach my $search (@validsearch) {
            last if $total_matched == scalar @validsearch;

            my $is_matched = 0;
            my ($where, $type, $searchkeyword) = ($search->{where}, $search->{type}, $search->{text});

            my @placetosearch = $where eq 'all' ? qw(subject from to date header attfilename textcontent) : ($where);

            foreach $where (@placetosearch) {
               if ($where eq 'subject' || $where eq 'from' || $where eq 'to' || $where eq 'date') {
                  # check subject, from, to, date
                  my %index = (
                                subject => $_SUBJECT,
                                from    => $_FROM,
                                to      => $_TO,
                                date    => $_DATE
                              );

                  my $data = (iconv('utf-8', $prefs{charset}, $attr[$index{$where}]))[0];

                  $is_matched = is_matched($type, $searchkeyword, $data);
                  last if $is_matched;
               } elsif ($where eq 'header') {
                  # check header
                  # check de-mimed header first since header in mail folder is raw format.
                  seek(FOLDER, $attr[$_OFFSET], 0);
                  $header = '';
                  while (<FOLDER>) {
                     $header .= $_;
                     last if $_ eq "\n";
                  }
                  $header = decode_mimewords_iconv($header, $prefs{charset});
                  $header =~ s/\n / /g; # handle folding roughly

                  $is_matched = is_matched($type, $searchkeyword, $header);
                  last if $is_matched;
               } elsif ($where eq 'textcontent' || $where eq 'attfilename') {
                  # read and parse message
                  seek(FOLDER, $attr[$_OFFSET], 0);
                  read(FOLDER, $block, $attr[$_SIZE]);
                  ($header, $body, $r_attachments) = ow::mailparse::parse_rfc822block(\$block);

                  # check textcontent: text in body and attachments
                  if ($where eq 'textcontent') {
                     # check body
                     if ($attr[$_CONTENT_TYPE] =~ m/^text/i || $attr[$_CONTENT_TYPE] eq 'N/A') {
                        # read all for text/plain,text/html
                        my ($encoding) = $header =~ m/content-transfer-encoding:\s+([^\s]+)/i;
                        $body = ow::mime::decode_content($body, $encoding);

                        $body = (iconv($messagecharset, $prefs{charset}, $body))[0];

                        $is_matched = is_matched($type, $searchkeyword, $body);
                        last if $is_matched;
                     }

                     # check attachments
                     foreach my $r_attachment (@{$r_attachments}) {
                        if ($r_attachment->{'content-type'} =~ m/^text/i || $r_attachment->{'content-type'} eq 'N/A') {
                           # read all for text/plain. text/html
                           my $charset = $r_attachment->{charset} || $messagecharset;

                           my $content = ow::mime::decode_content(${$r_attachment->{r_content}}, $r_attachment->{'content-transfer-encoding'});

                           $content = (iconv($charset, $prefs{charset}, $content))[0];

                           $is_matched = is_matched($type, $searchkeyword, $content);
                           last if $is_matched;
                        }
                     }

                     last if $is_matched;
                  }

                  # check attfilename
                  if ($where eq 'attfilename') {
                     foreach my $r_attachment (@{$r_attachments}) {
                        my $charset  = $r_attachment->{filenamecharset} || $r_attachment->{charset} || $messagecharset;
                        my $filename = (iconv($charset, $prefs{charset}, $r_attachment->{filename}))[0];

                        $is_matched = is_matched($type, $searchkeyword, $filename);
                        last if $is_matched;
                     }

                     last if $is_matched;
                  }
               }

               last if $is_matched; # should be no need here but just in case ...
            }

            last unless $is_matched;

            $total_matched++;
         }

         # generate messageid table line result if found
         if ($total_matched == scalar @validsearch) {
            push(@results, {
                              folder => $foldertosearch,
                              msgid  => $msgid,
                              attr   => \@attr,
                           }
                );
         }
      }

      ow::dbm::closedb(\%FDB, $folderdb) or
         openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb) . " ($!)");

      close(FOLDER) or
         openwebmailerror(gettext('Cannot close file:') . ' ' . f2u($folderfile) . " ($!)");

      ow::filelock::lock($folderfile, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . ' ' . f2u($folderfile) . " ($!)");
   }

   @results = sort { $b->{attr}[$_DATE] cmp $a->{attr}[$_DATE] } @results;

   return(\@results)
}

sub is_matched {
   # test a string to see if it matches a provided keyword
   # base the test on defined types
   my ($type, $searchkeyword, $string) = @_;

   return (
             $type eq 'contains'        && $string =~ m/\Q$searchkeyword\E/im)
             || ($type eq 'notcontains' && $string !~ m/\Q$searchkeyword\E/im)
             || ($type eq 'is'          && $string =~ m/^\Q$searchkeyword\E$/im)
             || ($type eq 'isnot'       && $string !~ m/^\Q$searchkeyword\E$/im)
             || ($type eq 'startswith'  && $string =~ m/^\Q$searchkeyword\E/im)
             || ($type eq 'endswith'    && $string =~ m/\Q$searchkeyword\E$/im)
             || ($type eq 'regexp'      && $string =~ m/$searchkeyword/im && ow::tool::is_regex($searchkeyword)
          ) ? 1 : 0;
}

