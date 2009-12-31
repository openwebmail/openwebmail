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

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config $thissession $user %prefs);

# extern vars
use vars qw($htmltemplatefilters);                           # defined in ow-shared.pl
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM
            $_RECVDATE $_DATE $_FROM $_TO $_SUBJECT
            $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES); # defined in maildb.pl
use vars qw(%lang_folders %lang_text %lang_err);             # defined in lang/xy

# local globals
use vars qw($folder);
use vars qw(%placeorder);

%placeorder = (
   from        => 1,
   to          => 2,
   subject     => 3,
   date        => 4,
   header      => 5,
   all         => 6,
   attfilename => 7,
   textcontent => 8,
);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

if (!$config{enable_webmail} || !$config{enable_advsearch}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{advsearch} $lang_err{access_denied}");
}

$folder     = param('folder') || 'INBOX';
my $action  = param('action') || '';

writelog("debug - request advsearch begin, action=$action - " .__FILE__.":". __LINE__) if $config{debug_request};

$action eq 'advsearch' ? advsearch() : openwebmailerror(__FILE__, __LINE__, "Action $lang_err{has_illegal_chars}");

writelog("debug - request advsearch end, action=$action - " .__FILE__.":". __LINE__) if ($config{debug_request});

openwebmail_requestend();


# BEGIN SUBROUTINES

sub advsearch {
   my $localtime = ow::datetime::time_gm2local(time(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
   my ($current_year, $current_month, $current_day) = (ow::datetime::seconds2array($localtime))[5, 4, 3];
   $current_year += 1900;
   $current_month++;

   # build the folders list
   my @folders = param('folders');
   for (my $i = 0; $i <= $#folders; $i++) {
      $folders[$i] = safefoldername(ow::tool::unescapeURL($folders[$i]));
   }
   my $foldersloop = [];
   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);
   for(my $i = 0; $i <= $#validfolders; $i++) {
      my $currfolderstr = (defined($lang_folders{$validfolders[$i]})) ?
                          $lang_folders{$validfolders[$i]}            :
                          f2u($validfolders[$i]);
      push(@{$foldersloop}, {
                              currfolder    => $validfolders[$i],
                              currfolderstr => $currfolderstr,
                              checked       => scalar(grep(/\Q$validfolders[$i]\E/, @folders)),
                              tr            => (($i + 1) % 4 == 0)
                            }
          );
   }

   # build the date selections - depends on user's dateformat
   my $datefmtstr    = $prefs{dateformat};
   my $datesep       = ($datefmtstr =~ /([^ymd])/)[0] || '-';
   my @dateformat    = split(/\Q$datesep\E/, $datefmtstr);
   my $dateselloop   = [];
   for (my $i = 1; $i <= 2; $i++) {
      for (my $j = 0; $j <= 2; $j++) {
         if ($dateformat[$j] eq 'yyyy') {
            my $selected = $i == 1 ? 1990 : $current_year;
            $selected    = param("year$i") || $selected;
            push(@{$dateselloop}, {
                                    datesep      => $j == 2 ? '' : $datesep,
                                    firstdatesel => $i == 1,
                                    dateselname  => "year$i",
                                    selloop      => [
                                                      map {{
                                                             option   => $_,
                                                             selected => $_ eq $selected ? 1 : 0,
                                                          }} (1990..$current_year)
                                                    ],
                                  }
                 );
         } elsif ($dateformat[$j] eq 'mm') {
             my $selected = $i == 1 ? 1 : $current_month;
             $selected    = param("month$i") || $selected;
             push(@{$dateselloop}, {
                                     datesep      => $j == 2 ? '' : $datesep,
                                     firstdatesel => $i == 1,
                                     dateselname  => "month$i",
                                     selloop      => [
                                                       map {{
                                                              option   => $_,
                                                              selected => $_ eq $selected ? 1 : 0,
                                                           }} (1..12)
                                                     ],
                                   }
                 );
         } elsif ($dateformat[$j] eq 'dd') {
             my $selected = $i == 1 ? 1 : $current_day;
             $selected    = param("day$i") || $selected;
             push(@{$dateselloop}, {
                                     datesep      => $j == 2 ? '' : $datesep,
                                     firstdatesel => $i == 1,
                                     dateselname  => "day$i",
                                     selloop      => [
                                                       map {{
                                                              option   => $_,
                                                              selected => $_ eq $selected ? 1 : 0,
                                                           }} (1..31)
                                                     ],
                                    }
                 );
         }
      }
   }

   # build the filters selection
   my @search = ();
   for (my $i = 0; $i <= 2; $i++) {
      my $text = param('searchtext' . $i);
      $text =~ s/^\s+//;
      $text =~ s/\s+$//;

      push(@search, {
                      where => param('where'.$i) || '',
                      type  => param('type'.$i)  || '',
                      text  => $text || ''
                    }
          );
   }

   my $resline = param('resline') || $prefs{msgsperpage} || 10;

   my $filtersloop = [];
   for (my $i = 0; $i <= 2; $i++) {
      my $where   = ${$search[$i]}{where} || 'subject';
      my $type    = ${$search[$i]}{type}  || 'contains';
      push(@{$filtersloop}, {
                               firstfiltersloop  => $i == 0 ? 1 : 0,
                               lastfiltersloop   => $i == 2 ? 1 : 0,
                               n                 => $i,
                               resline           => $resline,
                               text              => $search[$i]{text},
                               where             => [
                                                      map {{
                                                             option   => $_,
                                                             $_       => 1,
                                                             selected => $_ eq $where ? 1 : 0,
                                                          }} qw(from to subject date attfilename header textcontent all)
                                                    ],
                               type              => [
                                                      map {{
                                                             option   => $_,
                                                             $_       => 1,
                                                             selected => $_ eq $type ? 1 : 0,
                                                          }} qw(contains notcontains is isnot startswith endswith regexp)
                                                    ],
                            }
          );
   }

   # build the result list
   my ($startserial, $endserial, $seconds) = ('','','');

   if (defined param('year1')) {
      $seconds = ow::datetime::array2seconds(0, 0, 0, param('day1'), param('month1') - 1, param('year1') - 1900);
   } else {
      $seconds = ow::datetime::array2seconds(0, 0, 0, 1, 0, 90); # 1990/1/1
   }
   $startserial = ow::datetime::gmtime2dateserial(ow::datetime::time_local2gm(
                    $seconds, $prefs{timeoffset}, $prefs{daylighsaving}, $prefs{timezone}));

   if (defined param('year2')) {
      $seconds = ow::datetime::array2seconds(59, 59, 23, param('day2'), param('month2') - 1, param('year2') - 1900);
   } else {
      $seconds = ow::datetime::array2seconds(59, 59, 23, $current_day, $current_month - 1, $current_year - 1900);
   }
   $endserial = ow::datetime::gmtime2dateserial(ow::datetime::time_local2gm(
                  $seconds, $prefs{timeoffset}, $prefs{daylighsaving}, $prefs{timezone}));

   my $resultsloop = [];
   my $totalsize   = 0;
   my $totalfound  = 0;
   if ($startserial =~ m/^\d{14}$/ && $endserial =~ m/^\d{14}$/ && $startserial lt $endserial) {
      my $r_result = search_folders($startserial, $endserial, \@search, \@folders, dotpath('search.cache'));

      $totalfound = scalar @{$r_result};

      my $r_abookemailhash = {};
      $r_abookemailhash = get_abookemailhash() if $totalfound > 0;

      for (my $i = 0; $i < $totalfound; $i++) {
         last if $i > $resline;
         my $r_msg   = $r_result->[$i];
         my $r_attr  = $r_msg->{attr};
         $totalsize += $r_attr->[$_SIZE];

         # convert from message charset to current user charset
         my $msgcharset = $r_attr->[$_CHARSET];
         if ($msgcharset eq '' && $prefs{charset} eq 'utf-8') {
            # assume msg is from sender using same language as the recipient's browser
            $msgcharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{available_locales})))[6];
         }

         my $folder  = $r_msg->{folder};
         my $datestr = ow::datetime::dateserial2str($r_attr->[$_DATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                                    $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone});

         my ($from, $to, $subject) = iconv('utf-8', $prefs{charset}, $r_attr->[$_FROM], $r_attr->[$_TO], $r_attr->[$_SUBJECT]);
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

         my ($to_name, $to_address) = (join(",", @namelist), join(",", @addrlist));
         $to_name    = substr($to_name, 0, 29)    . '...' if length($to_name) > 32;
         $to_address = substr($to_address, 0, 61) . '...' if length($to_address) > 64;

         $subject    = substr($subject, 0, 64)    . "..." if length($subject) > 67;
         $subject    =~ s/^\s+$//; # empty spaces-only subjects

         push (@{$resultsloop}, {
                                   # standard params
                                   use_texticon         => $prefs{iconset} =~ m/^Text\./ ? 1 : 0,
                                   url_html             => $config{ow_htmlurl},
                                   url_cgi              => $config{ow_cgiurl},
                                   iconset              => $prefs{iconset},
                                   sessionid            => $thissession,

                                   # results
                                   odd                  => $i % 2 > 0 ? 1 : 0,
                                   folder               => $folder,
                                   folderstr            => $lang_folders{$folder} || f2u($folder),
                                   datestr              => $datestr,
                                   contactinaddressbook => $config{enable_addressbook} && defined $r_abookemailhash->{$from_address},
                                   from                 => $from,
                                   from_address         => $from_address,
                                   from_name            => $from_name,
                                   to                   => $to,
                                   to_address           => $to_address,
                                   to_name              => $to_name,
                                   headers              => $prefs{headers} || 'simple',
                                   message_id           => $r_msg->{msgid},
                                   msgcharset           => $msgcharset,
                                   subject              => $subject,
                                   sizestr              => lenstr($r_attr->[$_SIZE], 0),
                                }
              );
      }
   }

   $totalsize = lenstr($totalsize, 1) if $totalsize > 0;

   # build showall parameters
   my $showallloop = [];
   if ($totalfound > $resline) {
      for (my $i = 0; $i <= 2; $i++) {
         push (@{$showallloop}, { name  => "where$i",      value => $search[$i]{where} });
         push (@{$showallloop}, { name  => "type$i",       value => $search[$i]{type}  });
         push (@{$showallloop}, { name  => "searchtext$i", value => $search[$i]{text}  });
      }

      push (@{$showallloop}, { name => $_, value => param($_) })
        for qw(year1 month1 day1 year2 month2 day2 daterange);

      push (@{$showallloop}, { name => 'folders', value => $_ })
        for @folders;

      push (@{$showallloop}, { name => 'resline', value => $totalfound });
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("advsearch.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   my $daterange = param('daterange') || 'all';
   my $allbox    = param('allbox');
   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      use_texticon    => $prefs{iconset} =~ m/^Text\./ ? 1 : 0,
                      url_html        => $config{ow_htmlurl},
                      url_cgi         => $config{ow_cgiurl},
                      iconset         => $prefs{iconset},
                      sessionid       => $thissession,
                      folder          => $folder,
                      folderstr       => $lang_folders{$folder} || f2u($folder),

                      # advsearch.tmpl
                      allbox          => $allbox,
                      selectedfolders => scalar @folders,
                      totalfound      => $totalfound,
                      totalsizestr    => $totalsize,
                      daterange       => [
                                           map {{
                                                  option   => $_,
                                                  $_       => 1,
                                                  selected => $_ eq $daterange ? 1 : 0
                                               }} qw(all today oneweek twoweeks onemonth threemonths sixmonths oneyear)
                                         ],
                      dateselloop     => $dateselloop,
                      foldersloop     => $foldersloop,
                      filtersloop     => $filtersloop,
                      resultsloop     => $resultsloop,
                      showallloop     => $showallloop,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );


   httpprint([], [$template->output]);
}

sub search_folders {
   my ($startserial, $endserial, $r_search, $r_folders, $cachefile) = @_;

   my $cache_metainfo = '';
   my $r_result       = ();

   my $metainfo = $startserial . '@@@' . $endserial . '@@@';
   foreach my $search (@{$r_search}) {
      if ($search->{text} ne '') {
         $metainfo .= join('@@@', $search->{where}, $search->{type}, $search->{text});
      }
   }
   $metainfo .= '@@@' . join('@@@', @{$r_folders});

   $cachefile = ow::tool::untaint($cachefile);
   ow::filelock::lock($cachefile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($cachefile));

   if (-e $cachefile) {
      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} " . f2u($cachefile) . "! ($!)");
      $cache_metainfo = <CACHE>;
      close(CACHE);

      chomp($cache_metainfo);
   }

   if ($cache_metainfo ne $metainfo) {
      sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} " . f2u($cachefile) . "! ($!)");

      print CACHE $metainfo, "\n";

      $r_result = search_folders2($startserial, $endserial, $r_search, $r_folders);

      print CACHE scalar @{$r_result}, "\n";

      foreach (@{$r_result}) {
         my $r_msg = $_;
         print CACHE join('@@@', $r_msg->{folder}, $r_msg->{msgid}, @{$r_msg->{attr}}), "\n";
      }

      close(CACHE);
   } else {
      my @result = ();
      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} " . f2u($cachefile) . "! ($!)");
      $_ = <CACHE>;             # read the first line, which is a bogus startserial to endserial line
      my $totalfound = <CACHE>; # read the next line, which contains the totalfound count
      while (<CACHE>) {
         chomp;
         my ($folder, $messageid, @attr) = split(/\@\@\@/);
         push(@result, {
                          folder => $folder,
                          msgid  => $messageid,
                          attr   => \@attr
                        }
             );
      }
      close(CACHE);

      $r_result = \@result;
   }

   ow::filelock::lock($cachefile, LOCK_UN);

   return($r_result);
}

sub search_folders2 {
   my ($startserial, $endserial, $r_search, $r_folders) = @_;

   my @validsearch = ();
   my @result      = ();

   # put faster search in front
   foreach my $search (sort { $placeorder{$a->{where}} <=>  $placeorder{$b->{where}} } @{$r_search}) {
      push(@validsearch, $search) if $search->{text} ne '';
   }

   # search for the messageid in selected folder, return @result
   foreach my $foldertosearch (@{$r_folders}) {
      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldertosearch);

      next if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB));

      if (!update_folderindex($folderfile, $folderdb) < 0) {
         writelog("db error - Couldn't update index db $folderdb");
         writehistory("db error - Couldn't update index db $folderdb");
         ow::filelock::lock($folderfile, LOCK_UN);
         next;
      }
      my $r_messageids = get_messageids_sorted_by_sentdate($folderdb, 1);

      my (%FDB, %status);

      ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db " . f2u($folderdb));

      sysopen(FOLDER, $folderfile, O_RDONLY) or # used in TEXTCONTENT search
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} " . f2u($folderfile) . "! ($!)");

      foreach my $messageid (@{$r_messageids}) {
         # begin the search
         my ($block, $header, $body, $r_attachments) = ('','','',());
         my @attr = string2msgattr($FDB{$messageid});
         my $msgcharset = $attr[$_CHARSET];
         if ($msgcharset eq '' && $prefs{charset} eq 'utf-8') {
            # assume msg is from sender using same language as the recipient's browser
            $msgcharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{available_locales})))[6];
         }

         # skip this msg if is not within date range
         next if $attr[$_DATE] lt $startserial || $attr[$_DATE] gt $endserial;

         my $total_matched = 0;
         foreach my $search (@validsearch) {
            last if $total_matched == scalar @validsearch;

            my $is_matched = 0;
            my ($where, $type, $keyword) = ($search->{where}, $search->{type}, $search->{text});

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

                  $is_matched = is_matched($type, $keyword, $data);
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

                  $is_matched = is_matched($type, $keyword, $header);
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

                        $body = (iconv($msgcharset, $prefs{charset}, $body))[0];

                        $is_matched = is_matched($type, $keyword, $body);
                        last if $is_matched;
                     }

                     # check attachments
                     foreach my $r_attachment (@{$r_attachments}) {
                        if ($r_attachment->{'content-type'} =~ m/^text/i || $r_attachment->{'content-type'} eq 'N/A') {
                           # read all for text/plain. text/html
                           my $charset = $r_attachment->{charset} || $msgcharset;

                           my $content = ow::mime::decode_content(${$r_attachment->{r_content}}, $r_attachment->{'content-transfer-encoding'});

                           $content = (iconv($charset, $prefs{charset}, $content))[0];

                           $is_matched = is_matched($type, $keyword, $content);
                           last if $is_matched;
                        }
                     }

                     last if $is_matched;
                  }

                  # check attfilename
                  if ($where eq 'attfilename') {
                     foreach my $r_attachment (@{$r_attachments}) {
                        my $charset  = $r_attachment->{filenamecharset} || $r_attachment->{charset} || $msgcharset;
                        my $filename = (iconv($charset, $prefs{charset}, $r_attachment->{filename}))[0];

                        $is_matched = is_matched($type, $keyword, $filename);
                        last if $is_matched;
                     }

                     last if $is_matched;
                  }
               }

               last if $is_matched; # should no need here but just in case ...
            }

            last unless $is_matched; # this seach failed, stop continuing
            $total_matched++;
         }

         # generate messageid table line result if found
         if ($total_matched == scalar @validsearch) {
            push(@result, {
                            folder => $foldertosearch,
                            msgid  => $messageid,
                            attr   => \@attr,
                          }
                );
         }
      }

      ow::dbm::close(\%FDB, $folderdb);
      close(FOLDER);
      ow::filelock::lock($folderfile, LOCK_UN);
   } # end foldertosearch loop

   @result = sort { $b->{attr}[$_DATE] cmp $a->{attr}[$_DATE] } @result;

   return(\@result)
}

sub is_matched {
   # test a string to see if it matches a provided keyword
   # base the test on defined types
   my ($type, $keyword, $string) = @_;

   return ($type eq 'contains'       && $string =~ m/\Q$keyword\E/im)
          || ($type eq 'notcontains' && $string !~ m/\Q$keyword\E/im)
          || ($type eq 'is'          && $string =~ m/^\Q$keyword\E$/im)
          || ($type eq 'isnot'       && $string !~ m/^\Q$keyword\E$/im)
          || ($type eq 'startswith'  && $string =~ m/^\Q$keyword\E/im)
          || ($type eq 'endswith'    && $string =~ m/\Q$keyword\E$/im)
          || ($type eq 'regexp'      && $string =~ m/$keyword/im && ow::tool::is_regex($keyword))
          ? 1 : 0;
}

