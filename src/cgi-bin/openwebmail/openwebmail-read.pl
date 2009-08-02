#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2009, The OpenWebMail Project
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
use MIME::Base64;
use MIME::QuotedPrint;

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/htmlrender.pl";
require "modules/htmltext.pl";
require "modules/enriched.pl";
require "modules/mime.pl";
require "modules/tnef.pl";
require "modules/mailparse.pl";
require "modules/spamcheck.pl";
require "modules/viruscheck.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/cut.pl";
require "shares/getmsgids.pl";
require "shares/getmessage.pl";
require "shares/lockget.pl";
require "shares/statbook.pl";
require "shares/filterbook.pl";
require "shares/mailfilter.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw($htmltemplatefilters);                                              # defined in ow-shared.pl
use vars qw(%lang_folders %lang_sizes %lang_wdbutton %lang_text %lang_err);	# defined in lang/xy
use vars qw(%charset_convlist);							# defined in iconv.pl
use vars qw($_SIZE $_HEADERSIZE $_HEADERCHKSUM $_STATUS);			# defined in maildb.pl

# local globals
use vars qw($folder $sort $msgdatetype $page $longpage $keyword $searchtype);
use vars qw(%smilies);

%smilies = (
              ":)"  => "FaceHappy",    ":>"  => "FaceHappy",    ";)"  => "FaceWinking",
              ";>"  => "FaceWinking",  ";("  => "FaceSad",      ";<"  => "FaceSad",
              ":("  => "FaceSad",      ":<"  => "FaceSad",      ">:)" => "FaceDevilish",
              ">;)" => "FaceDevilish", "8)"  => "FaceGrinning", "8>"  => "FaceGrinning",
              ":D"  => "FaceGrinning", ";D"  => "FaceGrinning", "8D"  => "FaceGrinning",
              ":d"  => "FaceTasty",    ";d"  => "FaceTasty",    "8d"  => "FaceTasty",
              ":P"  => "FaceNyah",     ";P"  => "FaceNyah",     "8P"  => "FaceNyah",
              ":p"  => "FaceNyah",     ";p"  => "FaceNyah",     "8p"  => "FaceNyah",
              ":O"  => "FaceStartled", ";O"  => "FaceStartled", "8O"  => "FaceStartled",
              ":o"  => "FaceStartled", ";o"  => "FaceStartled", "8o"  => "FaceStartled",
              ":/"  => "FaceIronic",   ";/"  => "FaceIronic",   "8/"  => "FaceIronic",
              ":\\" => "FaceIronic",   ";\\" => "FaceIronic",   "8\\" => "FaceIronic",
              ":|"  => "FaceStraight", ";|"  => "FaceWry",      "8|"  => "FaceKOed",
              ":X"  => "FaceYukky",    ";X"  => "FaceYukky",
           );



# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(__FILE__, __LINE__, "$lang_text{webmail} $lang_err{access_denied}") if !$config{enable_webmail};

my $action   = param('action') || '';

$folder      = param('folder') || 'INBOX';
$sort        = param('sort') || $prefs{sort} || 'date_rev';
$msgdatetype = param('msgdatetype') || $prefs{msgdatetype};
$page        = param('page') || 1;
$longpage    = param('longpage') || 0;
$searchtype  = param('searchtype') || 'subject';
$keyword     = param('keyword') || '';

writelog("debug - request read begin, action=$action, folder=$folder - " . __FILE__ . ":" . __LINE__) if $config{debug_request};

$action eq 'readmessage'     ? readmessage()      :
$action eq 'rebuildmessage'  ? rebuildmessage()   :
$action eq 'deletenontext'   ? delete_nontext()   :
$action eq 'downloadnontext' ? download_nontext() :
openwebmailerror(__FILE__, __LINE__, "Action $lang_err{has_illegal_chars}");

writelog("debug - request read end, action=$action, folder=$folder - " . __FILE__ . ":" . __LINE__) if $config{debug_request};

openwebmail_requestend();


# BEGIN SUBROUTINES

sub readmessage {
   my $messageid      = shift || param('message_id') || ''; # arg may come from rebuildmessage sub
   my $headers        = param('headers') || $prefs{headers} || 'simple';
   my $attmode        = param('attmode') || 'simple';
   my $receivers      = param('receivers') || 'simple';
   my $printfriendly  = param('printfriendly') || '';
   my $showhtmlastext = param('showhtmlastext') || $prefs{showhtmlastext};
   my $convfrom       = param('convfrom') || '';

   my $orig_inbox_newmessages = 0;
   my $now_inbox_newmessages  = 0;
   my $now_inbox_allmessages  = 0;
   my $inboxsize_k            = 0;
   my $folder_allmessages     = 0;

   my %FDB;

   my $spooldb = (get_folderpath_folderdb($user, 'INBOX'))[1];
   if (ow::dbm::exist($spooldb)) {
      ow::dbm::open(\%FDB, $spooldb, LOCK_SH) or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db $spooldb");
      $orig_inbox_newmessages = $FDB{NEWMESSAGES};
      ow::dbm::close(\%FDB, $spooldb);
   }

   # filter messages in the background and hope junk is removed before displaying to user
   filtermessage($user, 'INBOX', \%prefs) if $folder eq 'INBOX';

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   # check quotas
   my $quotahit_deltype = '';
   if ($quotalimit > 0 && $quotausage > $quotalimit && ($config{delmail_ifquotahit} || $config{delfile_ifquotahit}) ) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get up to date usage
      if ($quotausage > $quotalimit) {
         if ($config{delmail_ifquotahit} && $folderusage > ($quotausage * 0.5)) {
            $quotahit_deltype = 'quotahit_delmail';
            cutfoldermails(($quotausage - ($quotalimit * 0.9)) * 1024, $user, @validfolders);
         } elsif ($config{delfile_ifquotahit}) {
            $quotahit_deltype = 'quotahit_delfile';
            my $webdiskrootdir = $homedir.absolute_vpath("/", $config{webdisk_rootpath});
            cutdirfiles(($quotausage - ($quotalimit * 0.9)) * 1024, $webdiskrootdir);
         }
         $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get up to date usage
      }
   }

   my $enable_quota       = $config{quota_module} eq 'none'?0:1;
   my $quotashowusage     = 0;
   my $quotaoverthreshold = 0;
   my $quotabytesusage    = 0;
   my $quotapercentusage  = 0;
   if ($enable_quota) {
      $quotaoverthreshold = (($quotalimit > 0) && (($quotausage / $quotalimit) > ($config{quota_threshold} / 100)));
      $quotashowusage     = ($quotaoverthreshold || $config{quota_threshold} == 0)?1:0;
      if ($quotashowusage) {
         $quotabytesusage = lenstr($quotausage * 1024, 1);
      }
      if ($quotaoverthreshold) {
         $quotapercentusage = int($quotausage * 1000 / $quotalimit) / 10;
      }
   }

   # Determine this message number, previous, and next message IDs
   my ($totalsize, $newmessages, $r_messageids) = getinfomessageids($user, $folder, $sort, $msgdatetype, $searchtype, $keyword);
   my ($message_num, $messageid_prev, $messageid_next) = (-1, '', '');
   foreach my $i (0..$#{$r_messageids}) {
      if ($r_messageids->[$i] eq $messageid) {
         $message_num    = $i + 1;
         $messageid_prev = $r_messageids->[$i-1] if $i > 0;
         $messageid_next = $r_messageids->[$i+1] if $i < $#{$r_messageids};
         last;
      }
   }

   # determine our page number
   $page = int($message_num / ($prefs{msgsperpage} || 10) + 0.999999) || $page;

   if ($message_num < 0) {
      # no matching message id found to read - go back to messages listing
      # this can occur when the user blocks a smtp relay or email address:
      # the messages get filtered and are no longer in the folder
      my %parms = (
                    page        => $page,
                    sessionid   => $thissession,
                    sort        => $sort,
                    msgdatetype => $msgdatetype,
                    keyword     => $keyword,
                    searchtype  => $searchtype,
                    folder      => $folder,
                  );
      print redirect(-location=>"$config{ow_cgiurl}/openwebmail-main.pl?action=listmessages&" .
                                join('&', map { "$_=" . ow::tool::escapeURL($parms{$_}) } sort keys %parms)
                    );
      return;
   }

   # lets put our single message to display in an array we can loop over in the template
   # In the future this loop will hopefully become a conversation view feature with multiple messages
   my $messagesloop = [
                         getmessage($user, $folder, $messageid),
                      ];

   my $messagecharset = official_charset($messagesloop->[0]{charset});
   my $displaycharset = $prefs{charset};

   if ($convfrom eq '') {
      if ($messagecharset eq $displaycharset) {
         # no conversion needed
         $convfrom = "none.$displaycharset";
      } else {
         if (defined $messagecharset && $messagecharset) {
            if ($prefs{readwithmsgcharset} && ow::lang::is_charset_supported($messagecharset)) {
               # convert the display, not the message
               $displaycharset = $messagecharset;
               $convfrom = "none.$messagecharset";
            } else {
               # convert the message to the display
               $convfrom = $messagecharset if is_convertible($messagecharset, $displaycharset);
            }
         } else {
            # assume the message is from a sender using same language as the users browser
            my $browserlocale = ow::lang::guess_browser_locale($config{available_locales});
            my $browsercharset = (ow::lang::localeinfo($browserlocale))[6];
            $convfrom = $browsercharset if is_convertible($browsercharset, $displaycharset);
         }
      }
      # force display with no conversion despite errors that will occur
      $convfrom = "none.$displaycharset" unless $convfrom;
   }

   if ($convfrom =~ m#^none.(.*)#) {
      my $nativecharset = $1;
      if ($nativecharset ne $prefs{charset}) {
         # user is trying to display the message natively in a charset that is not our
         # display charset, with no conversion. Lets see if we have template pack in our
         # language to match the native charset
         my $nativelocale = $prefs{language} . "." . ow::lang::charset_for_locale($nativecharset);
         if (exists $config{available_locales}->{$nativelocale}) {
            $prefs{locale}  = $nativelocale;
            $prefs{charset} = $nativecharset;
            $displaycharset = $nativecharset;
         } else {
            # fallback to the UTF-8 template pack in our language,
            # eventhough it may not display correctly in the native charset.
            # At least the message will display correctly
            my $utf8locale = "$prefs{language}.UTF-8";
            if (exists $config{available_locales}->{$utf8locale}) {
               $prefs{locale}  = $utf8locale;
               $prefs{charset} = $nativecharset;
               $displaycharset = $nativecharset;
            } else {
               # No UTF-8 in our language?!? Use the English UTF-8 display.
               $prefs{locale}  = "en_US.UTF-8";
               $prefs{charset} = $nativecharset;
               $displaycharset = $nativecharset;
            }
         }
      }
   }

   loadlang($prefs{locale});
   charset($prefs{charset}) if ($CGI::VERSION>=2.58); # setup charset of CGI module

   my $folderselectloop = [];
   foreach my $foldername (@validfolders) {
      my $newmessagesthisfolder = 0;
      my $allmessagesthisfolder = 0;

      # find message count for this folder
      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldername);
      if (ow::dbm::exist($folderdb)) {
         ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db " . f2u($folderdb));

         $allmessagesthisfolder  = $FDB{ALLMESSAGES} - $FDB{ZAPMESSAGES};
         $allmessagesthisfolder -= $FDB{INTERNALMESSAGES} if $prefs{hideinternal};
         $newmessagesthisfolder  = $FDB{NEWMESSAGES};

         # current message is turned from new to old after this read
         $newmessagesthisfolder-- if ($foldername eq $folder && $messagesloop->[0]{status} !~ m/R/i && $newmessagesthisfolder > 0);

         if ($foldername eq 'INBOX') {
            $now_inbox_allmessages = $allmessagesthisfolder;
            $now_inbox_newmessages = $newmessagesthisfolder;
            $inboxsize_k = (-s $folderfile) / 1024;
         } elsif ($foldername eq $folder) {
            $folder_allmessages = $allmessagesthisfolder;
         }

         ow::dbm::close(\%FDB, $folderdb);
      }

      push(@{$folderselectloop}, {
                                    option                => $foldername,
                                    label                 => exists $lang_folders{$foldername}?$lang_folders{$foldername}:f2u($foldername),
                                    selected              => $foldername eq $folder?1:0,
                                    newmessagesthisfolder => $newmessagesthisfolder,
                                    allmessagesthisfolder => $allmessagesthisfolder,
                                 }
          );
   }

   # incoming messages popup
   my $incomingmessagesloop = [];
   if ($prefs{newmailwindowtime} > 0) {
      if ($now_inbox_newmessages > $orig_inbox_newmessages) {
         push(@{$incomingmessagesloop}, {
                                           incomingfolder => $lang_folders{INBOX},
                                           incomingcount  => $now_inbox_newmessages - $orig_inbox_newmessages,
                                        }
             );
      }

      my ($totalfiltered, %filtered) = read_filterfolderdb(1);

      if (defined $totalfiltered && $totalfiltered > 0) {
         foreach my $defaultfolder (get_defaultfolders(), 'DELETE') {
            if (exists $filtered{$defaultfolder} && $filtered{$defaultfolder} > 0) {
               push(@{$incomingmessagesloop}, {
                                                 incomingfolder => $lang_folders{$defaultfolder},
                                                 incomingcount  => $filtered{$defaultfolder},
                                              }
                   );
            }
         }

         foreach my $filteredfolder (sort keys %filtered) {
            next if (is_defaultfolder($filteredfolder));
            push(@{$incomingmessagesloop}, {
                                              incomingfolder => f2u($filteredfolder),
                                              incomingcount  => $filtered{$filteredfolder},
                                           }
                );
         }
      }
   }

   my $charsetselectloop = [];
   my %allsets = ();
   $allsets{$_}++ for grep {!exists $allsets{$_}} ((map { $ow::lang::charactersets{$_}[1] } keys %ow::lang::charactersets), keys %charset_convlist);

   # display the message in the message charset
   # do not convert it to the display charset
   push(@{$charsetselectloop}, {
                                 option   => "none.$messagecharset",
                                 label    => ($messagecharset || $lang_text{none}) . " *",
                                 selected => $convfrom eq "none.$messagecharset"?1:0,
                               }
       );

   if ($messagecharset ne $displaycharset) {
      # display the message in the display charset
      # do not convert it to the display charset
      push(@{$charsetselectloop}, {
                                    option   => "none.$displaycharset",
                                    label    => $displaycharset,
                                    selected => $convfrom eq "none.$displaycharset"?1:0,
                                  }
          );
   }

   foreach my $othercharset (sort keys %allsets) {
      # display the message in any other charset that will convert
      # properly to our display charset, regardless of what the
      # message charset is or if it will convert properly
      if (is_convertible($othercharset, $displaycharset)) {
         push(@{$charsetselectloop}, {
                                        option   => $othercharset,
                                        label    => "$othercharset > $displaycharset",
                                        selected => $convfrom eq $othercharset?1:0,
                                     }
             );
         delete $allsets{$othercharset};
      }
   }

   delete $allsets{$messagecharset};
   delete $allsets{$displaycharset};

   # display message in any remaining other charsets with no conversion
   foreach my $othercharset (sort keys %allsets) {
      push(@{$charsetselectloop}, {
                                    option   => "none.$othercharset",
                                    label    => $othercharset,
                                    selected => $convfrom eq "none.$othercharset"?1:0,
                                  }
          )
   }

   undef %allsets;

   my $stationeryselectloop = [];
   my $statbookfile = dotpath('stationery.book');
   if (-f $statbookfile) {
      my %stationery;
      my ($ret, $errmsg) = read_stationerybook($statbookfile, \%stationery);
      openwebmailerror($errmsg) if ($ret < 0);
      foreach my $stationeryname (sort keys %stationery) {
         push(@{$stationeryselectloop}, {
                                          option   => $stationeryname,
                                          label    => (iconv($stationery{$stationeryname}{charset}, $displaycharset, $stationeryname))[0],
                                          selected => 0,
                                        }
             )
      }
   }

   my @destinationfolders = ();
   if ($quotalimit > 0 && $quotausage >= $quotalimit) {
      push(@destinationfolders,'DELETE');
   } else {
      @destinationfolders = @validfolders;
      push(@destinationfolders, 'LEARNSPAM', 'LEARNHAM') if ($config{enable_learnspam});
      push(@destinationfolders, 'FORWARD', 'DELETE');
   }

   my $destinationdefault = '';
   if ($quotalimit > 0 && $quotausage >= $quotalimit) {
      $destinationdefault = 'DELETE';
   } elsif ($folder =~ m#^(?:mail-trash|spam-mail|virus-mail)$#) {
      $destinationdefault = 'saved-messages';
   } elsif ($folder =~ m#^(?:sent-mail|saved-drafts)$#) {
      $destinationdefault = 'mail-trash';
   } else {
      my $smartdestination = '';
      if ($prefs{smartdestination}) {
         my $subject = (iconv('utf-8', $displaycharset, $messagesloop->[0]{subject}))[0];
         my $from    = (iconv('utf-8', $displaycharset, $messagesloop->[0]{from}))[0];
         $subject    =~ s#\s##g;

         foreach my $foldername (@validfolders) {
            if ($subject =~ m/\Q$foldername\E/i || $from =~ m/\Q$foldername\E/i) {
               $smartdestination = $foldername;
               last;
            }
         }
      }
      $destinationdefault = $smartdestination || $prefs{defaultdestination} || 'mail-trash';
      $destinationdefault = 'mail-trash' if $folder eq $destinationdefault;
   }

   my $is_writeable_abook = 0;
   if ($config{enable_addressbook}) {
      foreach my $dir (dotpath('webaddr'),  $config{ow_addressbooksdir}) {
         opendir(D, $dir) or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $dir ($!)");
         $is_writeable_abook += scalar grep { !m/^\./ && !m/^categories\.cache$/ && -w "$dir/$_" } readdir(D);
         closedir(D);
      }
   }

   # fork a child to do the status update and folderdb update
   # thus the result of readmessage can be returned as soon as possible
   if ($messagesloop->[0]{status} !~ m/R/i) { # msg file doesn't has R flag
      local $| = 1;        # flush all output
      if ( fork() == 0 ) { # child
         close(STDIN);
         close(STDOUT);
         close(STDERR);
         writelog("debug - update msg status process forked - " .__FILE__.":". __LINE__) if ($config{debug_fork});

         my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);
         ow::filelock::lock($folderfile, LOCK_EX) or openwebmail_exit(1);

         # since status in folderdb may have flags not found in msg header
         # we must read the status from folderdb and then update it back
         my @attr = get_message_attributes($messageid, $folderdb);
         update_message_status($messageid, $attr[$_STATUS]."R", $folderdb, $folderfile) if ($#attr > 0);

         ow::filelock::lock($folderfile, LOCK_UN);

         writelog("debug - update msg status process terminated - " .__FILE__.":". __LINE__) if ($config{debug_fork});
         openwebmail_exit(0);
      }
   } elsif (param('db_chkstatus')) { # check and set msg status R flag
      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

      my (%FDB, @attr);
      ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} db " . f2u($folderdb));
      @attr = string2msgattr($FDB{$messageid});
      if ($attr[$_STATUS] !~ m/R/i) {
         $attr[$_STATUS] .= "R";
         $FDB{$messageid} = msgattr2string(@attr);
      }
      ow::dbm::close(\%FDB, $folderdb);
   }

   my $showhtmltexttoggle  = 0;
   my $nontext_attachments = 0;

   # process each message for display
   for (my $i = 0; $i < scalar @{$messagesloop}; $i++) {
      # update the messageid to this specific message!
      # in the future we need to do this for conversation view
      $messageid = $messagesloop->[$i]{'message-id'};

      # to avoid using the HTML::Template global_vars option, we put only the vars we need into
      # each messageloop ourselves. This saves a lot of memory and significantly increases speed.
      $messagesloop->[$i]{sessionid}             = $thissession,
      $messagesloop->[$i]{folder}                = $folder,
      $messagesloop->[$i]{sort}                  = $sort,
      $messagesloop->[$i]{msgdatetype}           = $msgdatetype,
      $messagesloop->[$i]{page}                  = $page,
      $messagesloop->[$i]{longpage}              = $longpage,
      $messagesloop->[$i]{searchtype}            = $searchtype,
      $messagesloop->[$i]{keyword}               = $keyword,
      $messagesloop->[$i]{url_cgi}               = $config{ow_cgiurl},
      $messagesloop->[$i]{url_html}              = $config{ow_htmlurl},
      $messagesloop->[$i]{use_texticon}          = ($prefs{iconset} =~ m/^Text\./?1:0),
      $messagesloop->[$i]{use_fixedfont}         = $prefs{usefixedfont},
      $messagesloop->[$i]{iconset}               = $prefs{iconset},
      # non-standard
      $messagesloop->[$i]{enable_userfilter}     = $config{enable_userfilter};
      $messagesloop->[$i]{enable_addressbook}    = $config{enable_addressbook};
      $messagesloop->[$i]{is_writeable_abook}    = $is_writeable_abook;
      $messagesloop->[$i]{enable_webdisk}        = $config{enable_webdisk};
      $messagesloop->[$i]{is_writeable_webdisk}  = $config{webdisk_readonly}?0:1,
      $messagesloop->[$i]{simpleheaders}         = $headers eq 'simple'?1:0,
      $messagesloop->[$i]{simpleattachments}     = $attmode eq 'simple'?1:0,
      $messagesloop->[$i]{messageid}             = $messageid,
      $messagesloop->[$i]{convfrom}              = $convfrom,
      $messagesloop->[$i]{headers}               = $headers,
      $messagesloop->[$i]{attmode}               = $attmode,
      $messagesloop->[$i]{is_xmaileropenwebmail} = defined $messagesloop->[$i]{'x-mailer'}
                                                   && $messagesloop->[$i]{'x-mailer'} =~ m/^open ?webmail/i?1:0;
      # end global_vars hack

      # ================================================================
      # perform presentation formatting on the message headers as needed
      # ================================================================
      # convert the message charset for processing and presentation
      # header information is always assumed to be encoded utf-7 or utf-8, so convert it from utf-8
      $messagesloop->[$i]{to}         = (iconv('utf-8', $displaycharset, $messagesloop->[$i]{to}))[0];
      $messagesloop->[$i]{from}       = (iconv('utf-8', $displaycharset, $messagesloop->[$i]{from}))[0];
      $messagesloop->[$i]{cc}         = (iconv('utf-8', $displaycharset, $messagesloop->[$i]{cc}))[0];
      $messagesloop->[$i]{bcc}        = (iconv('utf-8', $displaycharset, $messagesloop->[$i]{bcc}))[0];
      $messagesloop->[$i]{subject}    = (iconv('utf-8', $displaycharset, $messagesloop->[$i]{subject}))[0];
      $messagesloop->[$i]{'reply-to'} = (iconv('utf-8', $displaycharset, $messagesloop->[$i]{'reply-to'}))[0];

      if ($headers eq 'all') {
         $messagesloop->[$i]{header} = decode_mimewords_iconv($messagesloop->[$i]{header}, $displaycharset);
         $messagesloop->[$i]{header} = ow::htmltext::text2html($messagesloop->[$i]{header});
         $messagesloop->[$i]{header} =~ s#\n([-\w]+?:)#\n<span class="messageheaderproperty">$1</span>#g;
      } else {
         # simplify headers display
         ($messagesloop->[$i]{fromname}, $messagesloop->[$i]{fromaddress}) = ow::tool::email2nameaddr($messagesloop->[$i]{from});
         ($messagesloop->[$i]{fromfirstname}, $messagesloop->[$i]{fromlastname}) = split(/\s+/, $messagesloop->[$i]{fromname}, 2);

         $messagesloop->[$i]{smtprelay} = '' if !defined $messagesloop->[$i]{smtprelay} || $messagesloop->[$i]{smtprelay} =~ m/^\s*$/;

         foreach my $heading (qw(to cc bcc)) {
            if (exists $messagesloop->[$i]{$heading}
                && defined $messagesloop->[$i]{$heading}
                && length($messagesloop->[$i]{$heading}) > 90
                && $receivers ne 'all') {
               $messagesloop->[$i]{$heading} =~ s#^(.{40,80}(?=[\s,;])).*#$1#; # max 80 characters
               $messagesloop->[$i]{$heading . "_is_longer"} = 1;
            }
         }

         if ($printfriendly ne "yes") {
            $messagesloop->[$i]{status_important}++ if $messagesloop->[$i]{priority} eq 'urgent' || $messagesloop->[$i]{status} =~ m#I#i;
            $messagesloop->[$i]{status_answered}++ if $messagesloop->[$i]{status} =~ m#A#i;
         }
      }


      # =============================================================
      # perform presentation formatting on the message body as needed
      # =============================================================
      # quoted-printable, base64, or uudecode the message body to make it readable
      if ($messagesloop->[$i]{'content-type'} =~ /^text/i && defined $messagesloop->[$i]{'content-transfer-encoding'}) {
         $messagesloop->[$i]{body} =
           $messagesloop->[$i]{'content-transfer-encoding'} =~ m/^base64/i           ? decode_base64($messagesloop->[$i]{body})      :
           $messagesloop->[$i]{'content-transfer-encoding'} =~ m/^quoted-printable/i ? decode_qp($messagesloop->[$i]{body})          :
           $messagesloop->[$i]{'content-transfer-encoding'} =~ m/^x-uuencode/i       ? ow::mime::uudecode($messagesloop->[$i]{body}) :
           $messagesloop->[$i]{body};
      }

      $messagesloop->[$i]{body} = (iconv($convfrom, $displaycharset, $messagesloop->[$i]{body}))[0];

      if ($messagesloop->[$i]{'content-type'} =~ m#^multipart#i) {
         # the message will be in a multipart attachment
         # most modern messages are multipart, and the actual body part is usually not shown
         $messagesloop->[$i]{is_multipart} = 1;
      } elsif ($messagesloop->[$i]{'content-type'} =~ m#^message/partial#i && $messagesloop->[$i]{'content-type'} =~ /;\s*id="(.+?)";?/i) {
         $messagesloop->[$i]{is_partialmessage} = 1;
         $messagesloop->[$i]{partialid} = $1;
      } elsif ($messagesloop->[$i]{'content-type'} =~ m#^text/(html|enriched)#i) {
         my $subtype = $1;
         if ($subtype eq 'enriched') {
            $messagesloop->[$i]{body} = ow::enriched::enriched2html($messagesloop->[$i]{body});
         }
         if ($showhtmlastext) {
            # html -> text -> html = plain text with hot-linked urls for convenience
            $messagesloop->[$i]{body} = ow::htmltext::html2text($messagesloop->[$i]{body});
            $messagesloop->[$i]{body} = ow::htmltext::text2html($messagesloop->[$i]{body});
            # change color for quoted lines
            $messagesloop->[$i]{body} =~ s#^(&gt;.*<br>)$#<span class="quotedtext">$1</span>#img;
            $messagesloop->[$i]{body} =~ s#<a href=#<a class="messagebody" href=#ig;
         } elsif ($subtype eq 'html') {
            # modify html for safe display
            $messagesloop->[$i]{body} = ow::htmlrender::html4nobase($messagesloop->[$i]{body});
            $messagesloop->[$i]{body} = ow::htmlrender::html4noframe($messagesloop->[$i]{body});
            $messagesloop->[$i]{body} = ow::htmlrender::html4link($messagesloop->[$i]{body});
            $messagesloop->[$i]{body} = ow::htmlrender::html4disablejs($messagesloop->[$i]{body}) if $prefs{disablejs};
            $messagesloop->[$i]{body} = ow::htmlrender::html4disableembcode($messagesloop->[$i]{body}) if $prefs{disableembcode};
            $messagesloop->[$i]{body} = ow::htmlrender::html4disableemblink($messagesloop->[$i]{body}, $prefs{disableemblink}, "$config{ow_htmlurl}/images/backgrounds/Transparent.gif");
            $messagesloop->[$i]{body} = ow::htmlrender::html4mailto($messagesloop->[$i]{body}, "$config{ow_cgiurl}/openwebmail-send.pl?action=composemessage&amp;compose_caller=read&amp;message_id=" . ow::tool::escapeURL($messageid) . "&amp;sessionid=" . ow::tool::escapeURL($thissession) . "&amp;folder=" . ow::tool::escapeURL($folder) . "&amp;sort=" . ow::tool::escapeURL($sort) . "&amp;msgdatetype=" . ow::tool::escapeURL($msgdatetype) . "&amp;page=" . ow::tool::escapeURL($page) . "&amp;longpage=" . ow::tool::escapeURL($longpage) . "&amp;searchtype=" . ow::tool::escapeURL($searchtype) . "&amp;keyword=" . ow::tool::escapeURL($keyword));
         }
         # convert html message into a table to safely display inside our interface
         $messagesloop->[$i]{body} = ow::htmlrender::html2table($messagesloop->[$i]{body});

         $showhtmltexttoggle = 1;
      } else {
         # body is other than html (probably plain text)
         # enriched text without a proper content-type is displayed as pure text
         # remove odds space or blank lines
         $messagesloop->[$i]{body} =~ s#(\r?\n){2,}#\n\n#g;
         $messagesloop->[$i]{body} =~ s#^\s+##;
         $messagesloop->[$i]{body} =~ s#\n\s*$#\n#;

         # remove bbs control char
         $messagesloop->[$i]{body} =~ s#\x1b\[(\d|\d\d|\d;\d\d)?m##g if ($messagesloop->[$i]{from} =~ m/bbs/i || $messagesloop->[$i]{body} =~ m/bbs/i);
         if ($prefs{usesmileicon}) {
            $messagesloop->[$i]{body} =~ s#(^|\D)(>?)([:;8])[-^]?([()><|PpDdOoX\\/])([\s<])#$1 SMILY_$smilies{"$2$3$4"}\.png $5#g;
            $messagesloop->[$i]{body} = ow::htmltext::text2html($messagesloop->[$i]{body});
            $messagesloop->[$i]{body} =~ s#SMILY_(.+?\.png)#<img src="$config{ow_htmlurl}/images/smilies/$1" width="12" height="12" border="0">#g;
         } else {
            $messagesloop->[$i]{body} = ow::htmltext::text2html($messagesloop->[$i]{body});
         }
         # change color for quoted lines
         my $class = $prefs{usefixedfont}?'messagebody monospacetext':'messagebody';
         $messagesloop->[$i]{body} =~ s#^(&gt;.*<br>)$#<span class="quotedtext">$1</span>#img;
         $messagesloop->[$i]{body} =~ s#<a href=#<a class="$class" href=#ig;
      }


      # ====================================================================
      # perform presentation formatting on the message attachments as needed
      # ====================================================================
      $messagesloop->[$i]{show_attmode} = (scalar @{$messagesloop->[$i]{attachment}} > 0 || $messagesloop->[$i]{'content-type'} =~ m#^multipart#i)?1:0;

      for (my $n = 0; $n < scalar @{$messagesloop->[$i]{attachment}}; $n++) {
         next unless defined %{$messagesloop->[$i]{attachment}[$n]};

         # skip this attachment if it is being referenced by a cid: or loc: link
         next if $messagesloop->[$i]{attachment}[$n]{referencecount} > 0;

         if ($attmode eq 'simple') {
            # handle case to skip to next text/html attachment
            if ($n + 1 < scalar @{$messagesloop->[$i]{attachment}}
                && defined %{$messagesloop->[$i]{attachment}[$n+1]}
                && ($messagesloop->[$i]{attachment}[$n]{boundary} eq $messagesloop->[$i]{attachment}[$n+1]{boundary}) ) {

               # skip to next text/(html|enriched) attachment in the same alternative group
               if ($messagesloop->[$i]{attachment}[$n]{subtype} =~ m#alternative#i
                   && $messagesloop->[$i]{attachment}[$n+1]{subtype} =~ m#alternative#i
                   && $messagesloop->[$i]{attachment}[$n+1]{'content-type'} =~ m#^text#i
                   && $messagesloop->[$i]{attachment}[$n+1]{filename} =~ m#^Unknown\.#) {
                  next;
               }
               # skip to next attachment if this=Unknown.(txt|enriched) and next=Unknown.(html|enriched)
               if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^text/(?:plain|enriched)#i
                   && $messagesloop->[$i]{attachment}[$n]{filename} =~ m#^Unknown\.#
                   && $messagesloop->[$i]{attachment}[$n+1]{'content-type'} =~ m#^text/(?:html|enriched)#i
                   && $messagesloop->[$i]{attachment}[$n+1]{filename} =~ m#^Unknown\.#) {
                  next;
               }
            }
         }

         # to avoid using the HTML::Template global_vars option, we put the vars we need into each
         # messageloop ourselves. This saves a lot of memory and significantly increases speed.
         $messagesloop->[$i]{attachment}[$n]{sessionid}             = $thissession;
         $messagesloop->[$i]{attachment}[$n]{folder}                = $folder;
         $messagesloop->[$i]{attachment}[$n]{sort}                  = $sort;
         $messagesloop->[$i]{attachment}[$n]{msgdatetype}           = $msgdatetype;
         $messagesloop->[$i]{attachment}[$n]{page}                  = $page;
         $messagesloop->[$i]{attachment}[$n]{longpage}              = $longpage;
         $messagesloop->[$i]{attachment}[$n]{searchtype}            = $searchtype;
         $messagesloop->[$i]{attachment}[$n]{keyword}               = $keyword;
         $messagesloop->[$i]{attachment}[$n]{url_cgi}               = $config{ow_cgiurl};
         $messagesloop->[$i]{attachment}[$n]{url_html}              = $config{ow_htmlurl};
         $messagesloop->[$i]{attachment}[$n]{use_texticon}          = ($prefs{iconset} =~ m/^Text\./?1:0);
         $messagesloop->[$i]{attachment}[$n]{use_fixedfont}         = $prefs{usefixedfont};
         $messagesloop->[$i]{attachment}[$n]{iconset}               = $prefs{iconset};
         # non-standard
         $messagesloop->[$i]{attachment}[$n]{enable_addressbook}    = $config{enable_addressbook};
         $messagesloop->[$i]{attachment}[$n]{is_writeable_abook}    = $is_writeable_abook;
         $messagesloop->[$i]{attachment}[$n]{enable_webdisk}        = $config{enable_webdisk};
         $messagesloop->[$i]{attachment}[$n]{is_writeable_webdisk}  = $config{webdisk_readonly}?0:1;
         $messagesloop->[$i]{attachment}[$n]{simpleheaders}         = $headers eq 'simple'?1:0;
         $messagesloop->[$i]{attachment}[$n]{messageid}             = $messageid;
         $messagesloop->[$i]{attachment}[$n]{convfrom}              = $convfrom;
         $messagesloop->[$i]{attachment}[$n]{headers}               = $headers;
         $messagesloop->[$i]{attachment}[$n]{attmode}               = $attmode;
         # end global_vars hack

         $messagesloop->[$i]{attachment}[$n]{attnumber} = $n;

         $nontext_attachments++ if (defined $messagesloop->[$i]{attachment}[$n]{'content-type'} && $messagesloop->[$i]{attachment}[$n]{'content-type'} !~ m/^text/i);

         my $attcharset = $convfrom;
         # if convfrom eq msgcharset, we will try to get the attcharset from the attheader - it may differ from the msgheader
         # if convfrom ne msgcharset, the user has specified some other charset to interpret the message - use convfrom as attcharset
         if ($convfrom eq lc($messagesloop->[$i]{charset})) {
            $attcharset = lc($messagesloop->[$i]{attachment}[$n]{filenamecharset}) ||
                          lc($messagesloop->[$i]{attachment}[$n]{charset})         ||
                          $convfrom;
         }

         $messagesloop->[$i]{attachment}[$n]{filename} =
            (iconv($attcharset, $displaycharset, $messagesloop->[$i]{attachment}[$n]{filename}))[0];

         $messagesloop->[$i]{attachment}[$n]{'content-description'} =
            (iconv($attcharset, $displaycharset, $messagesloop->[$i]{attachment}[$n]{'content-description'}))[0];

         $messagesloop->[$i]{attachment}[$n]{'content-length'} =
            lenstr($messagesloop->[$i]{attachment}[$n]{'content-length'},1);

         $messagesloop->[$i]{attachment}[$n]{'content-type'} =~ s/^(.+?);.*/$1/g;

         # decode the content if needed
         if (defined $messagesloop->[$i]{attachment}[$n]{'content-transfer-encoding'}) {
            my $encoding = $messagesloop->[$i]{attachment}[$n]{'content-transfer-encoding'};
            my $content  = ${$messagesloop->[$i]{attachment}[$n]{r_content}};

            ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
              $encoding =~ m/^base64$/i           ? decode_base64($content)      :
              $encoding =~ m/^quoted-printable$/i ? decode_qp($content)          :
              $encoding =~ m/^x-uuencode$/i       ? ow::mime::uudecode($content) :
              $content;
         }

         # assume all attachments are misc at first
         $messagesloop->[$i]{attachment}[$n]{is_misc}     = 1;
         $messagesloop->[$i]{attachment}[$n]{is_html}     = 0;
         $messagesloop->[$i]{attachment}[$n]{is_enriched} = 0;
         $messagesloop->[$i]{attachment}[$n]{is_vcard}    = 0;
         $messagesloop->[$i]{attachment}[$n]{is_text}     = 0;
         $messagesloop->[$i]{attachment}[$n]{is_message}  = 0;
         $messagesloop->[$i]{attachment}[$n]{is_image}    = 0;

         # show preview option?
         $messagesloop->[$i]{attachment}[$n]{is_doc} = 1 if $messagesloop->[$i]{attachment}[$n]{filename} =~ m/\.(?:doc|dot)$/i;

         # process text/html attachments
         if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^text/html#i && $attmode eq 'simple') {
            if ($messagesloop->[$i]{attachment}[$n]{filename} =~ m#^Unknown\.# || scalar @{$messagesloop->[$i]{attachment}} == 1) {
               # html_att2table
               $messagesloop->[$i]{attachment}[$n]{is_misc} = 0;
               $messagesloop->[$i]{attachment}[$n]{is_html} = 1;

               # format html for inline display
               if ($showhtmlastext) {
                  # html -> text -> html = plain text with hot-linked urls for convenience
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmltext::html2text(${$messagesloop->[$i]{attachment}[$n]{r_content}});
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmltext::text2html(${$messagesloop->[$i]{attachment}[$n]{r_content}});
                  # change color for quoted lines
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~ s#^(&gt;.*<br>)$#<span class="quotedtext">$1</span>#img;
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~ s#<a href=#<a class="messagebody" href=#ig;
               } else {
                  # modify html for safe display
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmlrender::html4nobase(${$messagesloop->[$i]{attachment}[$n]{r_content}});
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmlrender::html4noframe(${$messagesloop->[$i]{attachment}[$n]{r_content}});
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmlrender::html4link(${$messagesloop->[$i]{attachment}[$n]{r_content}});
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmlrender::html4disablejs(${$messagesloop->[$i]{attachment}[$n]{r_content}}) if $prefs{disablejs};
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmlrender::html4disableembcode(${$messagesloop->[$i]{attachment}[$n]{r_content}}) if $prefs{disableembcode};
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmlrender::html4disableemblink(${$messagesloop->[$i]{attachment}[$n]{r_content}}, $prefs{disableemblink}, "$config{ow_htmlurl}/images/backgrounds/Transparent.gif");

                  # this subroutine detects cid: and loc: links in the html. It then finds the attachment that matches the
                  # cid: or loc: and increments its referencecount so that we don't display that attachment separately. The
                  # link in the html is updated to point to the attachment so it displays inline (via openwebmail-viewatt.pl)
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmlrender::html4attachments(${$messagesloop->[$i]{attachment}[$n]{r_content}}, $messagesloop->[$i]{attachment}, "$config{ow_cgiurl}/openwebmail-viewatt.pl", "action=viewattachment&amp;sessionid=" . ow::tool::escapeURL($thissession) . "&amp;message_id=" . ow::tool::escapeURL($messageid) . "&amp;folder=" . ow::tool::escapeURL($folder));

                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmlrender::html4mailto(${$messagesloop->[$i]{attachment}[$n]{r_content}}, "$config{ow_cgiurl}/openwebmail-send.pl?action=composemessage&amp;compose_caller=read&amp;message_id=" . ow::tool::escapeURL($messageid) . "&amp;sessionid=" . ow::tool::escapeURL($thissession) . "&amp;folder=" . ow::tool::escapeURL($folder) . "&amp;sort=" . ow::tool::escapeURL($sort) . "&amp;msgdatetype=" . ow::tool::escapeURL($msgdatetype) . "&amp;page=" . ow::tool::escapeURL($page) . "&amp;longpage=" . ow::tool::escapeURL($longpage) . "&amp;searchtype=" . ow::tool::escapeURL($searchtype) . "&amp;keyword=" . ow::tool::escapeURL($keyword));
               }

               # convert html message into a table to safely display inside our interface
               ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                  ow::htmlrender::html2table(${$messagesloop->[$i]{attachment}[$n]{r_content}});

               # note the dereference here of the scalar ref into the hash key r_content
               # so that it can be displayed in the templates!
               $messagesloop->[$i]{attachment}[$n]{r_content} =
                  (iconv($attcharset, $displaycharset, ${$messagesloop->[$i]{attachment}[$n]{r_content}}))[0];

               $showhtmltexttoggle = 1;
            }
         }

         # process text/enriched attachments
         if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^text/enriched#i && $attmode eq 'simple') {
            if ($messagesloop->[$i]{attachment}[$n]{filename} =~ m#^Unknown\.# || scalar @{$messagesloop->[$i]{attachment}} == 1) {
               # enriched_att2table
               $messagesloop->[$i]{attachment}[$n]{is_misc}     = 0;
               $messagesloop->[$i]{attachment}[$n]{is_enriched} = 1;

               ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                  ow::enriched::enriched2html(${$messagesloop->[$i]{attachment}[$n]{r_content}});

               if ($showhtmlastext) {
                  # html -> text -> html = plain text with hot-linked urls for convenience
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmltext::html2text(${$messagesloop->[$i]{attachment}[$n]{r_content}});
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmltext::text2html(${$messagesloop->[$i]{attachment}[$n]{r_content}});
                  # change color for quoted lines
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~ s#^(&gt;.*<br>)$#<span class="quotedtext">$1</span>#img;
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~ s#<a href=#<a class="messagebody" href=#ig;
               }

               # convert html message into a table to safely display inside our interface
               ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                  ow::htmlrender::html2table(${$messagesloop->[$i]{attachment}[$n]{r_content}});

               # note the dereference here of the scalar ref into the hash key r_content
               # so that it can be displayed in the templates!
               $messagesloop->[$i]{attachment}[$n]{r_content} =
                  (iconv($attcharset, $displaycharset, ${$messagesloop->[$i]{attachment}[$n]{r_content}}))[0];

               $showhtmltexttoggle = 1;
            }
         }

         # process text/x-vcard or text/directory attachments
         if ($messagesloop->[$i]{attachment}[$n]{filename} =~ m/\.(?:vcard|vcf)$/i && $attmode eq 'simple') {
            if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^text/(?:x?-?vcard|directory)#i
                || $messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^application/octet-stream#i) {
               $messagesloop->[$i]{attachment}[$n]{is_misc}  = 0;
               $messagesloop->[$i]{attachment}[$n]{is_vcard} = 1;
            }
         }

         # process text/... attachments (except html, enriched, x-vcard, or directory)
         if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^text/(?!html|enriched|x?-?vcard|directory)#i && $attmode eq 'simple') {
            if ($messagesloop->[$i]{attachment}[$n]{filename} =~ m#^Unknown\.# || scalar @{$messagesloop->[$i]{attachment}} == 1) {
               # text_att2table
               $messagesloop->[$i]{attachment}[$n]{is_misc} = 0;
               $messagesloop->[$i]{attachment}[$n]{is_text} = 1;

               # remove odds space or blank lines
               ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~ s/(\r?\n){2,}/\n\n/g;
               ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~ s/^\s+//;
               ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~ s/\n\s*$/\n/;
               if ($prefs{'usesmileicon'}) {
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~
                     s/(^|\D)(>?)([:;8])[-^]?([\(\)\>\<\|PpDdOoX\\\/])([\s\<])/$1 SMILY_$smilies{"$2$3$4"}\.png $5/g;
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmltext::text2html(${$messagesloop->[$i]{attachment}[$n]{r_content}});
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~
                     s/SMILY_(.+?\.png)/<img border="0" width="12" height="12" src="$config{'ow_htmlurl'}\/images\/smilies\/$1">/g;
               } else {
                  ${$messagesloop->[$i]{attachment}[$n]{r_content}} =
                     ow::htmltext::text2html(${$messagesloop->[$i]{attachment}[$n]{r_content}});
               }

               ${$messagesloop->[$i]{attachment}[$n]{r_content}} =~ s#<a href=#<a class="messagebody" href=#ig;

               # note the dereference here of the scalar ref into the hash key r_content
               # so that it can be displayed in the templates!
               $messagesloop->[$i]{attachment}[$n]{r_content} =
                  (iconv($attcharset, $displaycharset, ${$messagesloop->[$i]{attachment}[$n]{r_content}}))[0];
            }
         }

         # process message/... attachments (except partial or external-body)
         if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^message/(?!partial|external-body)#i && $attmode eq 'simple') {
            # message_att2table
            $messagesloop->[$i]{attachment}[$n]{is_misc}    = 0;
            $messagesloop->[$i]{attachment}[$n]{is_message} = 1;

            my ($header, $body) = split(/\n\r*\n/, ${$messagesloop->[$i]{attachment}[$n]{r_content}}, 2);

            my %msg;
            $msg{'content-type'} = 'N/A'; # assume msg is simple text

            ow::mailparse::parse_header(\$header, \%msg);
            $attcharset = $1 if ($msg{'content-type'} =~ m#charset="?([^\s"';]*)"?\s?#i);

            $header = simpleheader($header); # from shares/maildb.pl
            $header = ow::htmltext::text2html($header);

            # decode the body if needed
            $body = $msg{'content-transfer-encoding'} =~ m/^base64$/i           ?  decode_base64($body)      :
                    $msg{'content-transfer-encoding'} =~ m/^quoted-printable$/i ?  decode_qp($body)          :
                    $msg{'content-transfer-encoding'} =~ m/^x-uuencode$/i       ?  ow::mime::uudecode($body) :
                    $body;

            if ($msg{'content-type'} =~ m#^text/html#i) { # convert into html table
               $body = ow::htmlrender::html4nobase($body);
               $body = ow::htmlrender::html4disablejs($body) if ($prefs{'disablejs'});
               $body = ow::htmlrender::html4disableembcode($body) if ($prefs{'disableembcode'});
               $body = ow::htmlrender::html4disableemblink($body, $prefs{disableemblink}, "$config{ow_htmlurl}/images/backgrounds/Transparent.gif");
               $body = ow::htmlrender::html2table($body);
            } else {
               $body = ow::htmltext::text2html($body);
               $body =~ s#<a href=#<a class="messagebody" href=#ig;
            }

            ($header, $body) = iconv($attcharset, $displaycharset, $header, $body);

            # header lang_text replacement should be done after iconv
            $header =~ s#Date: #<span class="messageheaderproperty">$lang_text{date}:</span> #i;
            $header =~ s#From: #<span class="messageheaderproperty">$lang_text{from}:</span> #i;
            $header =~ s#Reply-To: #<span class="messageheaderproperty">$lang_text{replyto}:</span> #i;
            $header =~ s#To: #<span class="messageheaderproperty">$lang_text{to}:</span> #i;
            $header =~ s#Cc: #<span class="messageheaderproperty">$lang_text{cc}:</span> #i;
            $header =~ s#Subject: #<span class="messageheaderproperty">$lang_text{subject}:</span> #i;

            # note the message header are keep untouched here in order to make it easy for further parsing
            # also note the dereference here of the scalar ref of r_content in order to display in the templates
            $messagesloop->[$i]{attachment}[$n]{r_content} = qq|<table cellspacing="0" cellpadding="2" border="0" width="100%">\n|.
                                                             qq|<tr>\n|.
                                                             qq|  <td class="windowdark messagebody">\n|.
                                                             qq|$header\n|.
                                                             qq|  </td>\n|.
                                                             qq|</tr>\n|.
                                                             qq|<tr>\n|.
                                                             qq|  <td class="windowlight messagebody">\n|.
                                                             qq|$body\n|.
                                                             qq|  </td>\n|.
                                                             qq|</tr>\n|.
                                                             qq|</table>|;
         }

         # process image/... attachments
         if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^image#i) {
            if ($messagesloop->[$i]{attachment}[$n]{filename} =~ m/\.(?:jpg|jpeg|gif|png|bmp)$/i) {
               unless ($prefs{showimgaslink}) {
                  # image_att2table
                  $messagesloop->[$i]{attachment}[$n]{is_misc}  = 0;
                  $messagesloop->[$i]{attachment}[$n]{is_image} = 1;
               }
            }
         }

         # process application/ms-tnef attachments - convert them into links to download as zip, tar, or tgz files
         if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^application/ms-tnef#i) {
            my @filelist        = ();
            my $archivefilename = '';
            my $tnefbin         = ow::tool::findbin('tnef');

            if ($tnefbin) {
               @filelist = ow::tnef::get_tnef_filelist($tnefbin, $messagesloop->[$i]{attachment}[$n]{r_content});
            }

            if (scalar @filelist == 1) {
               $archivefilename = $filelist[0];
            } elsif (scalar @filelist > 1) {
               my $archivebasefilename = $messagesloop->[$i]{attachment}[$n]{filename};
               $archivebasefilename =~ s#\.[\w\d]{0,4}$##;
               $archivefilename = "$archivebasefilename.zip" if ow::tool::findbin('zip');
               $archivefilename = "$archivebasefilename.tar" if ow::tool::findbin('tar');
               $archivefilename = "$archivebasefilename.tgz" if ow::tool::findbin('tar') && ow::tool::findbin('gzip');
            }

            my $orig_description = $messagesloop->[$i]{attachment}[$n]{'content-description'};
            if ($archivefilename ne '') {
               $messagesloop->[$i]{attachment}[$n]{'content-type'} = ow::tool::ext2contenttype($archivefilename);
               $messagesloop->[$i]{attachment}[$n]{'content-description'} = 'ms-tnef encapsulated data';
               if (scalar @filelist > 0) {
                  $messagesloop->[$i]{attachment}[$n]{'content-description'} .= ': ' . join(', ', @filelist);
               }
            } else {
               $messagesloop->[$i]{attachment}[$n]{'content-description'} = 'unrecognized ms-tnef encapsulated data';
            }

            if ($orig_description ne '') {
               $messagesloop->[$i]{attachment}[$n]{'content-description'} .= ", $orig_description";
            }
         }
      }

      # if this is unread message, confirm to transmit read receipt if requested
      if (defined $messagesloop->[$i]{status} && defined $messagesloop->[$i]{'disposition-notification-to'}) {
         if ($messagesloop->[$i]{status} !~ m#R#i && $messagesloop->[$i]{'disposition-notification-to'} ne '') {
            if ($prefs{sendreceipt} ne 'no') {
               $messagesloop->[$i]{sendreadreceipt} = 1;
               $messagesloop->[$i]{sendreadreceipt_ask} = $prefs{sendreceipt} eq 'ask'?1:0;
            }
         }
      }

      # if current message is new, count as old after this read
      if ($messagesloop->[$i]{status} !~ m/R/i) {
         $orig_inbox_newmessages-- if ($folder eq 'INBOX' && $orig_inbox_newmessages > 0);
         $newmessages-- if ($newmessages > 0);
      }
   }

   # show unread inbox messages count in titlebar
   # TODO: it would be great to move this functionality to the get_header sub
   # so that it can show on every page, not just main_listview
   my $unread_messages_info = '';
   if ($now_inbox_newmessages > 0) {
      $unread_messages_info = "$lang_folders{INBOX}: $now_inbox_newmessages $lang_text{messages} $lang_text{unread}";
   }

   # vars used again here just to surpress warnings
   {
      my $surpress = exists $ow::lang::RTL{$prefs{locale}} ? 1 : 0;
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template(
                                                                          $printfriendly eq 'yes'  ?
                                                                          'read_printmessage.tmpl' :
                                                                          'read_readmessage.tmpl'
                                                                         ),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template         => get_header($config{header_template_file}, $unread_messages_info),

                      # standard params
                      sessionid               => $thissession,
                      folder                  => $folder,
                      sort                    => $sort,
                      msgdatetype             => $msgdatetype,
                      page                    => $page,
                      longpage                => $longpage,
                      searchtype              => $searchtype,
                      keyword                 => $keyword,
                      url_cgi                 => $config{ow_cgiurl},
                      url_html                => $config{ow_htmlurl},
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./ ? 1 : 0),
                      use_fixedfont           => $prefs{usefixedfont},
                      iconset                 => $prefs{iconset},
                      charset                 => $prefs{charset},

                      # read_readmessage.tmpl
                      folderselectloop        => $folderselectloop,
                      textbrowser             => $ENV{HTTP_USER_AGENT} =~ m/(?:lynx|w3m)/i ? 1 : 0,
                      enable_quota            => $enable_quota,
                      quotashowusage          => $quotashowusage,
                      quotaoverthreshold      => $quotaoverthreshold,
                      quotabytesusage         => $quotabytesusage,
                      quotapercentusage       => $quotapercentusage,
                      quotalimit              => $quotalimit,
                      quotaoverlimit          => ($quotalimit > 0 && $quotausage > $quotalimit) ? 1 : 0,
                      spoollimit              => $config{spool_limit},
                      spooloverlimit          => ($config{spool_limit} > 0 && $inboxsize_k > $config{spool_limit}) ? 1 : 0,
                      overlimit               => (($quotalimit > 0 && $quotausage > $quotalimit)
                                                 || ($config{spool_limit} > 0 && $inboxsize_k > $config{spool_limit})) ? 1 : 0,
                      newmessages             => $newmessages,
                      totalmessages           => scalar @{$r_messageids},
                      message_num             => $message_num,
                      firstmessagesize        => lenstr($messagesloop->[0]{size},1),
                      is_folder_saved_drafts  => ($folder eq 'saved-drafts') ? 1 : 0,
                      is_folder_sent_mail     => ($folder eq 'sent-mail') ? 1 : 0,
                      messageid               => $messagesloop->[0]{'message-id'},
                      convfrom                => $convfrom,
                      headers                 => $headers,
                      attmode                 => $attmode,
                      showhtmlastext          => $showhtmlastext,
                      enable_addressbook      => $config{enable_addressbook},
                      enable_calendar         => $config{enable_calendar},
                      calendar_defaultview    => $prefs{calendar_defaultview},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      use_ssh2                => -r "$config{ow_htmldir}/applet/mindterm2/mindterm.jar" ? 1 : 0,
                      use_ssh1                => -r "$config{ow_htmldir}/applet/mindterm/mindtermfull.jar" ? 1 : 0,
                      enable_preference       => $config{enable_preference},

                      enable_saprefs          => $config{enable_saprefs},
                      enable_webmail          => $config{enable_webmail},
                      enable_learnham         => $config{enable_learnspam} && $folder eq 'spam-mail' ? 1 : 0,
                      enable_learnspam        => $config{enable_learnspam} && $folder !~ m#^(?:saved-drafts|sent-mail|spam-mail|virus-mail)$# ? 1 : 0,
                      messageaftermove        => $prefs{viewnextaftermsgmovecopy} ? ($messageid_next || $messageid_prev) : 0,
                      messageid_prev          => $messageid_prev,
                      messageid_next          => $messageid_next,
                      confirmmsgmovecopy      => $prefs{confirmmsgmovecopy} ? 1 : 0,
                      trashfolder             => $folder eq 'mail-trash' ? '' :
                                                 ($quotalimit > 0 && $quotausage >= $quotalimit) ? 'DELETE' : 'mail-trash',
                      is_right_to_left        => $ow::lang::RTL{$prefs{locale}} ? 1 : 0,
                      controlbartop           => $prefs{ctrlposition_msgread} eq 'top' ? 1 : 0,
                      controlbarbottom        => $prefs{ctrlposition_msgread} ne 'top' ? 1 : 0,
                      charsetselectloop       => $charsetselectloop,
                      enable_stationery       => $config{enable_stationery} && $folder !~ m#^(?:saved-drafts|sent-mail)$# ? 1 : 0,
                      stationeryselectloop    => $stationeryselectloop,
                      destinationselectloop   => [
                                                    map { {
                                                             option   => $_,
                                                             label    => exists $lang_folders{$_} ?
                                                                         (iconv($prefs{charset}, $displaycharset, $lang_folders{$_}))[0] :
                                                                         (iconv($prefs{fscharset}, $displaycharset, $_))[0],
                                                             selected => $_ eq $destinationdefault ? 1 : 0
                                                        } } @destinationfolders
                                                 ],
                      messagesloop            => $messagesloop,
                      enable_userfilter       => $config{enable_userfilter},
                      showhtmltexttoggle      => $showhtmltexttoggle,
                      has_nontext_attachments => $nontext_attachments > 1 ? 1 : 0,
                      newmailsound            => $now_inbox_newmessages > $orig_inbox_newmessages &&
                                                 -f "$config{ow_htmldir}/sounds/$prefs{newmailsound}" ? $prefs{newmailsound} : 0,
                      popup_quotahitdelmail   => $quotahit_deltype eq 'quotahit_delmail' ? 1 : 0,
                      popup_quotahitdelfile   => $quotahit_deltype eq 'quotahit_delfile' ? 1 : 0,
                      incomingmessagesloop    => $incomingmessagesloop,
                      newmailwindowtime       => $prefs{newmailwindowtime},
                      newmailwindowheight     => (scalar @{$incomingmessagesloop} * 16) + 70,

                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub rebuildmessage {
   my $partialid = param('partialid') || '';
   my $messageid = param('message_id') || '';
   my $headers   = param('headers') || $prefs{headers} || 'simple';
   my $attmode   = param('attmode') || 'simple';
   my $receivers = param('receivers') || 'simple';
   my $convfrom  = param('convfrom') || '';

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile) . "!");

   my ($errorcode, $rebuildmsgid, @partialmsgids) = rebuild_message_with_partialid($folderfile, $folderdb, $partialid);

   ow::filelock::lock($folderfile, LOCK_UN);

   if ($errorcode == 0) {
      # move partial msgs to trash folder
      my ($trashfile, $trashdb) = get_folderpath_folderdb($user, "mail-trash");
      if ($folderfile ne $trashfile) {
         ow::filelock::lock($trashfile, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} $trashfile");
         my $moved = (operate_message_with_ids("move", \@partialmsgids, $folderfile, $folderdb, $trashfile, $trashdb))[0];
         folder_zapmessages($folderfile, $folderdb) if $moved > 0;
         ow::filelock::lock($trashfile, LOCK_UN);
      }

      readmessage($rebuildmsgid);

      writelog("rebuild message - rebuild $rebuildmsgid in $folder");
      writehistory("rebuild message - rebuild $rebuildmsgid from $folder");
   } else {
      # build the template
      my $template = HTML::Template->new(
                                           filename          => get_template("read_rebuildfailed.tmpl"),
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
                         sort                    => $sort,
                         msgdatetype             => $msgdatetype,
                         page                    => $page,
                         longpage                => $longpage,
                         searchtype              => $searchtype,
                         keyword                 => $keyword,
                         url_cgi                 => $config{ow_cgiurl},

                         # read_rebuildfailed.tmpl
                         messageid               => $messageid,
                         headers                 => $headers,
                         attmode                 => $attmode,
                         receivers               => $receivers,
                         convfrom                => $convfrom,
                         error_no_endpart        => $errorcode == -1?1:0,
                         error_part_missing      => $errorcode == -2?1:0,
                         error_rebuild_format    => $errorcode == -3?1:0,
                         error_rebuild_size      => $errorcode == -4?1:0,

                         # footer.tmpl
                         footer_template         => get_footer($config{footer_template_file}),
                      );
      httpprint([], [$template->output]);
   }
}

sub download_nontext {
   # download all non-text attachments at one time
   # the attachments are bundled into a zip, tgz, or tar file and sent to the user
   my $messageid = param('message_id') || '';

   return readmessage() unless $messageid;

   my $messagesloop = [
                         getmessage($user, $folder, $messageid, 'all'),
                      ];

   my @filelist = ();

   for (my $i = 0; $i < scalar @{$messagesloop}; $i++) {
      # update the messageid to this specific message!
      # in the future we need to do this for conversation view
      $messageid = $messagesloop->[$i]{'message-id'};

      for (my $n = 0; $n < scalar @{$messagesloop->[$i]{attachment}}; $n++) {
         next unless defined %{$messagesloop->[$i]{attachment}[$n]};

         # skip this attachment if it is being referenced by a cid: or loc: link
         next if $messagesloop->[$i]{attachment}[$n]{referencecount} > 0;

         if (defined $messagesloop->[$i]{attachment}[$n]{'content-type'} && $messagesloop->[$i]{attachment}[$n]{'content-type'} !~ m/^text/i) {
            my $content = ${$messagesloop->[$i]{attachment}[$n]{r_content}};

            # decode the content if needed
            if (defined $messagesloop->[$i]{attachment}[$n]{'content-transfer-encoding'}) {
               my $encoding = $messagesloop->[$i]{attachment}[$n]{'content-transfer-encoding'};

               $content = $encoding =~ m/^base64$/i           ? decode_base64($content)      :
                          $encoding =~ m/^quoted-printable$/i ? decode_qp($content)          :
                          $encoding =~ m/^x-uuencode$/i       ? ow::mime::uudecode($content) :
                          $content;
            }

            # try to convert tnef content -> zip/tgz/tar
            if ($messagesloop->[$i]{attachment}[$n]{'content-type'} =~ m#^application/ms\-tnef#) {
               my $tnefbin = ow::tool::findbin('tnef');
               if ($tnefbin ne '') {
                  my ($arcname, $r_arcdata) = ow::tnef::get_tnef_archive($tnefbin, $messagesloop->[$i]{attachment}[$n]{filename}, \$content);
                  if ($arcname ne '') { # tnef extraction and conversion successed
                     $messagesloop->[$i]{attachment}[$n]{filename} = $arcname;
                     $content = ${$r_arcdata};
                  }
               }
            }

            my $tempfile = ow::tool::untaint("/tmp/$messagesloop->[$i]{attachment}[$n]{filename}");

            sysopen(FILE, $tempfile, O_WRONLY|O_TRUNC|O_CREAT) or
              openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_create} $tempfile ($!)\n");
            binmode FILE; # to ensure images don't corrupt
            print FILE $content;
            close FILE || openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $tempfile ($!)\n");

            push(@filelist, $messagesloop->[$i]{attachment}[$n]{filename});
         }
      }
   }

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
   my @now       = ow::datetime::seconds2array($localtime);
   my $dlname    = sprintf("%4d%02d%02d-%02d%02d", $now[5]+1900,$now[4]+1,$now[3], $now[2],$now[1]);

   my @cmd = ();
   my $zipbin = ow::tool::findbin('zip');
   if ($zipbin ne '') {
      @cmd = ($zipbin, '-ryq', '-');
      $dlname .= ".zip";
   } else {
      my $gzipbin = ow::tool::findbin('gzip');
      my $tarbin  = ow::tool::findbin('tar');
      if ($gzipbin ne '') {
         $ENV{PATH} = $gzipbin;
         $ENV{PATH} =~ s#/gzip##; # for tar

         @cmd = ($tarbin, '-zcpf', '-');
         $dlname .= ".tgz";
      } else {
         @cmd = ($tarbin, '-cpf', '-');
         $dlname .= ".tar";
      }
   }

   my $contenttype = ow::tool::ext2contenttype($dlname);

   # send a header that causes the browser to prompt the user with a "file save" dialog box
   local $| = 1;
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$dlname"\n|;
   if ($ENV{HTTP_USER_AGENT} =~ m/MSIE 5.5/) { # ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$dlname"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$dlname"\n|;
   }
   print qq|\n|;

   chdir("/tmp") or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_chdirto} /tmp\n");

   # set environment variables for cmd
   $ENV{USER} = $ENV{LOGNAME} = $user;
   $ENV{HOME} = $homedir;

   $< = $>; # drop ruid by setting ruid = euid

   exec(@cmd, @filelist) or print qq|Error in executing |.join(' ', @cmd, @filelist);
}

sub delete_nontext {
   # delete all non-text attachments from a message
   my $messageid = param('message_id') || '';
   my $nodeid    = param('nodeid') || '';

   return readmessage() unless $nodeid;

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);
   my @attr = get_message_attributes($messageid, $folderdb);

   my ($block, $msgsize, $err, $errmsg, %message);
   ($msgsize, $errmsg) = lockget_message_block($messageid, $folderfile, $folderdb, \$block);
   return ($msgsize, $errmsg) if ($msgsize <= 0);

   ($message{header}, $message{body}, $message{attachment}) = ow::mailparse::parse_rfc822block(\$block, "0", "all");
   return 0 if (!defined @{$message{attachment}});

   my @datas;
   my $boundary = "----=OPENWEBMAIL_ATT_" . rand();
   my $contenttype_line = 0;
   foreach my $line (split(/\n/, $message{header})) {
      if ($line =~ m/^Content\-Type:/i) {
         $contenttype_line = 1;
         $datas[0] .= qq|Content-Type: multipart/mixed;\n|.
                      qq|\tboundary="$boundary"\n|;
      } else {
         next if ($line =~ m/^\s/ && $contenttype_line);
         $contenttype_line = 0;
         $datas[0] .= "$line\n";
      }
   }
   $attr[$_HEADERCHKSUM] = ow::tool::calc_checksum(\$datas[0]);
   $attr[$_HEADERSIZE]   = length($datas[0]);

   push(@datas, "\n");
   push(@datas, $message{body});

   my @att          = @{$message{attachment}};
   my $has_namedatt = 0;
   my $delatt       = 0;
   foreach my $i (0 .. $#att) {
      if ($nodeid eq 'NONTEXT') {
         if (${$att[$i]}{'content-type'} !~ m/^text/i) {
           $delatt++;
           next;
         }
      } else {
         if (${$att[$i]}{nodeid} eq $nodeid) {
           $delatt++;
           next;
         }
      }

      push(@datas, "\n--$boundary\n");
      push(@datas, ${$att[$i]}{header});
      push(@datas, "\n");
      push(@datas, ${${$att[$i]}{r_content}});

      $has_namedatt++ if (${$att[$i]}{filename} !~ m/^Unknown\./);
   }
   push(@datas, "\n--$boundary--\n\n");
   return 0 if ($delatt == 0);

   $block          = join('', @datas);
   $attr[$_SIZE]   = length($block);
   $attr[$_STATUS] =~ s/T// if (!$has_namedatt);

   ow::filelock::lock($folderfile, LOCK_EX) or return(-2, "$folderfile write lock error");
   ($err, $errmsg) = append_message_to_folder($messageid, \@attr, \$block, $folderfile, $folderdb);
   if ($err == 0) {
      my $zapped = folder_zapmessages($folderfile, $folderdb);
      if ($zapped < 0) {
         my $m = "mailfilter - $folderfile zap error $zapped";
         writelog($m);
         writehistory($m);
      }
   }
   ow::filelock::lock($folderfile, LOCK_UN);

   writelog("delete nontext attachments - error $err:$errmsg") if $err < 0;

   return readmessage();
}
