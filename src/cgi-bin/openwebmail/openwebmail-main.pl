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
use HTML::Template 2.9;

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/htmltext.pl";
require "modules/mime.pl";
require "modules/mailparse.pl";
require "modules/spamcheck.pl";
require "modules/viruscheck.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/lockget.pl";
require "shares/cut.pl";
require "shares/getmsgids.pl";
require "shares/fetchmail.pl";
require "shares/pop3book.pl";
require "shares/calbook.pl";
require "shares/filterbook.pl";
require "shares/mailfilter.pl";

# optional module
ow::tool::has_module('IO/Socket/SSL.pm');
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($default_logindomain);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw($htmltemplatefilters); # defined in ow-shared.pl
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err %lang_sortlabels %lang_calendar %lang_wday); # defined in lang/locale
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES); # defined in maildb.pl

# local globals
use vars qw($folder $sort $msgdatetype);
use vars qw($page $longpage);
use vars qw($searchtype $keyword);
use vars qw($pop3_fetches_complete);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

my $action = param('action') || '';

if (!$config{enable_webmail} && $action ne "logout") {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{webmail} $lang_err{access_denied}");
}

$folder      = param('folder') || 'INBOX';
$keyword     = param('keyword') || '';
$longpage    = param('longpage') || 0;
$msgdatetype = param('msgdatetype') || $prefs{msgdatetype};
$page        = param('page') || 1;
$searchtype  = param('searchtype') || 'subject';
$sort        = param('sort') || $prefs{sort} || 'date_rev';

$keyword     = '' if param('clearsearchbutton');
$keyword     =~ s/^\s*//;
$keyword     =~ s/\s*$//;

# TODO: This action processing seems a little overly complicated. It could probably be cleaner and simpler.
writelog("debug - request main begin, action=$action, folder=$folder - " .__FILE__.":". __LINE__) if ($config{debug_request});

if ($action eq "movemessage" || defined param('movebutton') || defined param('copybutton') ) {
   my @messageids  = param('message_ids');
   my $destination = ow::tool::untaint(safefoldername(param('destination')));

   if ($destination eq 'FORWARD' && $#messageids >= 0) {
      # write the forwarding message-ids to a file for openwebmail-send to read
      sysopen(FORWARDIDS, "$config{ow_sessionsdir}/$thissession-forwardids", O_WRONLY|O_TRUNC|O_CREAT)
         or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_open} $config{ow_sessionsdir}/$thissession-forwardids");
      print FORWARDIDS join("\n", @messageids);
      close(FORWARDIDS)
         or openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_close} $config{ow_sessionsdir}/$thissession-forwardids");
      my %params = (
                     action         => 'composemessage',
                     composetype    => 'forwardids',
                     compose_caller => 'main',
                     folder         => $folder,
                     keyword        => $keyword,
                     longpage       => $longpage,
                     msgdatetype    => $msgdatetype,
                     page           => $page,
                     searchtype     => $searchtype,
                     sessionid      => $thissession,
                     sort           => $sort,
                   );
      my $redirect = "$config{ow_cgiurl}/openwebmail-send.pl?" .
                     join('&', map { "$_=" . ow::tool::escapeURL($params{$_}) } sort keys %params);
      print redirect(-location => $redirect);
   } else {
      # move/copy/delete messages
      movemessage(\@messageids, $destination) if ($#messageids >= 0);
      if (param('messageaftermove')) {
         my $messageid = param('messageaftermove') || '';
         $messageid    = $messageids[0] if defined param('copybutton'); # copy button pressed, msg not moved

         my $headers   = param('headers') || $prefs{headers} || 'simple';
         my $attmode   = param('attmode') || 'simple';

         my $redirect = "$config{ow_cgiurl}/openwebmail-read.pl?action=readmessage&" .
                        join ("&", (
                                      "attmode="     . ow::tool::escapeURL($attmode),
                                      "folder="      . ow::tool::escapeURL($folder),
                                      "headers="     . ow::tool::escapeURL($headers),
                                      "keyword="     . ow::tool::escapeURL($keyword),
                                      "longpage="    . ow::tool::escapeURL($longpage),
                                      "message_id="  . ow::tool::escapeURL($messageid),
                                      "msgdatetype=" . ow::tool::escapeURL($msgdatetype),
                                      "page="        . ow::tool::escapeURL($page),
                                      "searchtype="  . ow::tool::escapeURL($searchtype),
                                      "sessionid="   . ow::tool::escapeURL($thissession),
                                      "sort="        . ow::tool::escapeURL($sort),
                                   )
                             );
         print redirect(-location => $redirect);
      } else {
         listmessages();
      }
   }
} elsif ($action eq "listmessages_afterlogin") {
   clean_trash_spamvirus();

   if ($quotalimit > 0 && $quotausage > $quotalimit) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }

   if (($config{forced_moveoldmsgfrominbox} || $prefs{moveoldmsgfrominbox}) && (!$quotalimit || ($quotausage < $quotalimit))) {
      moveoldmsg2saved();
   }

   update_pop3check();
   authpop3_fetch() if ($config{auth_module} eq 'auth_pop3.pl' || $config{auth_module} eq 'auth_ldap_vpopmail.pl');
   pop3_fetches($prefs{autopop3wait}) if ($config{enable_pop3} && $prefs{autopop3});
   listmessages();
} elsif ($action eq "userrefresh") {
   if ($folder eq 'INBOX') {
      authpop3_fetch() if ($config{auth_module} eq 'auth_pop3.pl' || $config{auth_module} eq 'auth_ldap_vpopmail.pl');
   }

   if ($config{quota_module} ne 'none') {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }

   listmessages();

   if (update_pop3check()) {
      pop3_fetches(0) if ($config{enable_pop3} && $prefs{autopop3});
   }
} elsif ($action eq "listmessages") {
   my $update = 0;
   $update = 1 if (update_pop3check());
   if ($update) {
      # get mail from auth pop3 server
      authpop3_fetch() if ($config{auth_module} eq 'auth_pop3.pl' || $config{auth_module} eq 'auth_ldap_vpopmail.pl');
   }

   listmessages();

   if ($update) {
      # get mail from misc pop3 servers
      pop3_fetches(0) if ($config{enable_pop3} && $prefs{autopop3});
   }
} elsif ($action eq "markasread") {
   markasread();
   listmessages();
} elsif ($action eq "markasunread") {
   markasunread();
   listmessages();
} elsif ($action eq "pop3fetches" && $config{enable_pop3}) {
   www_pop3_fetches();
   listmessages();
} elsif ($action eq "pop3fetch" && $config{enable_pop3}) {
   www_pop3_fetch();
   listmessages();
} elsif ($action eq "emptyfolder") {
   www_emptyfolder($folder);
   if ($quotalimit > 0 && $quotausage > $quotalimit) {
      $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
   }
   listmessages();
} elsif ($action eq "logout") {
   clean_trash_spamvirus();

   if (($config{forced_moveoldmsgfrominbox} || $prefs{moveoldmsgfrominbox}) && (!$quotalimit || ($quotausage < $quotalimit))) {
      moveoldmsg2saved();
   }

   logout();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{has_illegal_chars}");
}

writelog("debug - request main end, action=$action, folder=$folder - " .__FILE__.":". __LINE__) if ($config{debug_request});

openwebmail_requestend();



# BEGIN SUBROUTINES

sub listmessages {
   my $orig_inbox_newmessages = 0;
   my $now_inbox_newmessages  = 0;
   my $now_inbox_allmessages  = 0;
   my $inboxsize_k            = 0;
   my $folder_allmessages     = 0;

   my %FDB;

   # make note of how many inbox messages we have before re-reading the inbox
   my $spooldb = (get_folderpath_folderdb($user, 'INBOX'))[1];
   if (ow::dbm::exist($spooldb)) {
      ow::dbm::open(\%FDB, $spooldb, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db $spooldb");
      $orig_inbox_newmessages = $FDB{NEWMESSAGES}; # new messages in INBOX
      ow::dbm::close(\%FDB, $spooldb);
   }

   # filter messages in the background
   filtermessage($user, 'INBOX', \%prefs);

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   # reset global $folder to INBOX if it is not a valid folder
   $folder = 'INBOX' unless scalar grep { $_ eq $folder } @validfolders;

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
      $destinationdefault = 'INBOX';
   } elsif ($folder =~ m#^(?:sent-mail|saved-drafts)$#) {
      $destinationdefault = 'mail-trash';
   } else {
      $destinationdefault = $prefs{defaultdestination} || 'mail-trash';
      $destinationdefault = 'mail-trash' if $folder eq $destinationdefault;
   }

   # get all the messageids, already sorted
   my ($totalsize, $newmessages, $r_messageids, $r_messagedepths) = getinfomessageids($user, $folder, $sort, $msgdatetype, $searchtype, $keyword);

   my $totalmessage = scalar @{$r_messageids};
   $totalmessage = 0 if ($totalmessage < 0);

   my $msgsperpage = $prefs{msgsperpage} || 10;
   $msgsperpage = 1000 if ($longpage);

   my $totalpage = int($totalmessage/$msgsperpage+0.999999);
   $totalpage = 1 if ($totalpage == 0);

   $page = 1 if ($page < 1);
   $page = $totalpage if ($page > $totalpage);

   my $firstmessage = ($page-1) * $msgsperpage + 1;

   my $lastmessage = $firstmessage + $msgsperpage - 1;
   $lastmessage = $totalmessage if ($lastmessage > $totalmessage);

   # process the messages that we have already retrieved above with getinfomessageids
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   my $userbrowsercharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{available_locales})))[6];
   my $r_abookemailhash   = get_abookemailhash();

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_readlock} db " . f2u($folderdb));

   my $messagesloop = [];
   foreach my $messagenumber ($firstmessage  .. $lastmessage) {
      my $messageid    = $r_messageids->[$messagenumber - 1];
      my $messagedepth = $r_messagedepths->[$messagenumber - 1] || 0;

      next if (!defined $FDB{$messageid});

      my @attr    = split(/\n/, $FDB{$messageid});
      my $charset = $attr[$_CHARSET];

      # assume msg is from sender using same language as the recipient's browser
      $charset = $userbrowsercharset if ($charset eq '' && $prefs{charset} eq 'utf-8');

      # convert from message charset to current user charset
      my ($from, $to, $subject) = iconv('utf-8', $prefs{charset}, $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]);

      # status
      my $status = $attr[$_STATUS] || '';
      $status =~ s/\s//g; # remove whitespace

      # date difference between received time and sent time
      my $timeintransit = ow::datetime::dateserial2gmtime($attr[$_RECVDATE]) - ow::datetime::dateserial2gmtime($attr[$_DATE]);
      my $timeintransitsign = $timeintransit > 0 ? '+' : '-';
      $timeintransit *= -1 if $timeintransit < 0;

      # from/to
      my (@to_namelist, @to_addrlist);
      foreach my $recipient (ow::tool::str2list($to, 0)) {
         my ($name, $emailaddress) = ow::tool::email2nameaddr($recipient);
         next if !defined $name || !defined $emailaddress || $name =~ m/"/ || $emailaddress =~ m/"/; # eliminate incomplete addresses
         push(@to_namelist, $name);
         push(@to_addrlist, $emailaddress);
      }

      my $to_names = join(", ", @to_namelist);
      $to_names = substr($to_names, 0, 29) . '...' if length $to_names > 32;

      my $to_addrs = join(", ", @to_addrlist);
      $to_addrs = substr($to_addrs, 0, 61) . '...' if length $to_addrs > 64;

      my $to_keywords = join('|',@to_addrlist); # for searching

      my $tocontactinaddressbook = scalar grep { exists $r_abookemailhash->{lc($_)} } @to_addrlist;

      my ($from_name, $from_addr) = ow::tool::email2nameaddr($from);
      $from_addr =~ s/"//g;

      my $fromcontactinaddressbook = exists $r_abookemailhash->{lc($from_addr)};

      # subject
      $subject = substr($subject, 0, 64) . "..." if length $subject > 67;

      my $subject_keyword = $subject;
      $subject_keyword =~ s/^(?:\s*.{1,3}[.\s]*:\s*)+//; # strip leading Re: Fw: R: Res: Ref:
      $subject_keyword =~ s/\[.*?\]:?//g;                # strip leading [listname] type text

      push(@{$messagesloop}, {
                                odd                  => (scalar @{$messagesloop} + 1) % 2, # for row color toggle
                                messagenumber        => $messagenumber,
                                messageid            => $messageid,
                                messagecharset       => lc($charset),
                                messagestatus        => $status,
                                status_read          => $status =~ m/R/i?1:0,
                                status_answered      => $status =~ m/A/i?1:0,
                                status_attachments   => $status =~ m/T/i?1:0,
                                status_important     => $status =~ m/I/i?1:0,
                                messagedatesent      => ow::datetime::dateserial2str(
                                                          $attr[$_DATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                                          $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}),
                                messagedatereceived  => ow::datetime::dateserial2str(
                                                          $attr[$_RECVDATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                                          $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}),
                                showdatereceived     => $msgdatetype eq 'recvdate'?1:0,
                                timeintransitsign    => $timeintransitsign,
                                timeintransithour    => int($timeintransit / 60 / 60),
                                timeintransitmin     => int($timeintransit / 60) % 60,
                                timeintransitsec     => $timeintransit % 60,
                                to_namesandaddresses => $to,
                                to_names             => $to_names,
                                to_addresses         => $to_addrs,
                                to_keywords          => $to_keywords,
                                from_nameandaddress  => $from,
                                from_name            => $from_name,
                                from_address         => $from_addr,
                                contactinaddressbook => $config{enable_addressbook}
                                                        && ($sort =~ m#^(?:sender|sender_rev)$#        ? $fromcontactinaddressbook :
                                                            $sort =~ m#^(?:recipient|recipient_rev)$#  ? $tocontactinaddressbook   :
                                                            $folder =~ m#^(?:sent-mail|saved-drafts)$# ? $tocontactinaddressbook   :
                                                            $folder =~ m#^\Q$lang_folders{'sent-mail'}\E[\Q$prefs{categorizedfolders_fs}\E\s_-]#i ?
                                                            $tocontactinaddressbook :
                                                            $fromcontactinaddressbook)?1:0,
                                subjecttext          => $subject,
                                subjectindent        => '&nbsp;' x $messagedepth,
                                subject_keyword      => $subject_keyword,
                                messagesize          => lenstr($attr[$_SIZE], 0),
                                accesskey            => (scalar @{$messagesloop}) + 1 < 10?(scalar @{$messagesloop}) + 1:'',
                             }
          );
   }

   ow::dbm::close(\%FDB, $folderdb);
   undef(@{$r_messageids});
   undef($r_messageids);

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

   # show unread inbox messages count in titlebar
   # TODO: it would be great to move this functionality to the get_header sub
   # so that it can show on every page, not just main_listview
   my $unread_messages_info = '';
   if ($now_inbox_newmessages > 0) {
      $unread_messages_info = "$lang_folders{INBOX}: $now_inbox_newmessages $lang_text{messages} $lang_text{unread}";
   }

   # vars used again here just to surpress warnings
   {
   my $surpress = exists $ow::lang::RTL{$prefs{locale}} ? 1 :
                  defined $ow::datetime::wday_en[0]     ? 1 : 0;
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("main_listview.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 1,
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
                      use_texticon            => ($prefs{iconset} =~ m/^Text\./?1:0),
                      iconset                 => $prefs{iconset},
                      charset                 => $prefs{charset},

                      # main_listview.tmpl
                      msgsperpage             => $msgsperpage,
                      folderselectloop        => $folderselectloop,
                      textbrowser             => $ENV{HTTP_USER_AGENT} =~ m/(?:lynx|w3m)/i?1:0,
                      enable_quota            => $enable_quota,
                      quotashowusage          => $quotashowusage,
                      quotaoverthreshold      => $quotaoverthreshold,
                      quotabytesusage         => $quotabytesusage,
                      quotapercentusage       => $quotapercentusage,
                      quotalimit              => $quotalimit,
                      quotaoverlimit          => ($quotalimit > 0 && $quotausage > $quotalimit)?1:0,
                      spoollimit              => $config{spool_limit},
                      spooloverlimit          => ($config{spool_limit} > 0 && $inboxsize_k > $config{spool_limit})?1:0,
                      overlimit               => (($quotalimit > 0 && $quotausage > $quotalimit)
                                                 || ($config{spool_limit} > 0 && $inboxsize_k > $config{spool_limit}))?1:0,
                      newmessages             => $newmessages,
                      totalmessages           => $totalmessage,
                      totalsize               => lenstr($totalsize,1),
                      enable_userfilter       => $config{enable_userfilter},
                      enable_saprefs          => $config{enable_saprefs},
                      enable_preference       => $config{enable_preference},
                      is_folder_inbox         => $folder eq 'INBOX'?1:0,
                      enable_webmail          => $config{enable_webmail},
                      enable_pop3             => $config{enable_pop3},
                      enable_advsearch        => $config{enable_advsearch},
                      enable_addressbook      => $config{enable_addressbook},
                      enable_calendar         => $config{enable_calendar},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      use_ssh2                => -r "$config{ow_htmldir}/applet/mindterm2/mindterm.jar"?1:0,
                      use_ssh1                => -r "$config{ow_htmldir}/applet/mindterm/mindtermfull.jar"?1:0,
                      calendar_defaultview    => $prefs{calendar_defaultview},
                      enable_learnham         => $config{enable_learnspam} && $folder eq 'spam-mail'?1:0,
                      enable_learnspam        => $config{enable_learnspam} && $folder !~ m#^(?:saved-drafts|sent-mail|spam-mail|virus-mail)$#?1:0,
                      show_emptyfolder        => $folder =~ m#^(?:saved-drafts|mail-trash|spam-mail|virus-mail)$#?1:0,
                      foldername              => exists $lang_folders{$folder}?$lang_folders{$folder}:f2u($folder),
                      folder_allmessages      => $folder_allmessages,
                      trashfolder             => $quotalimit > 0 && $quotausage > $quotalimit?'DELETE':'mail-trash',
                      totalpage               => $totalpage,
                      nextpage                => $page < $totalpage?($page + 1):0,
                      prevpage                => ($page - 1) || 0,
                      is_right_to_left        => $ow::lang::RTL{$prefs{locale}}?1:0,
                      eventreminderloop       => get_upcomingevents($prefs{calendar_reminderdays}),
                      controlbartop           => $prefs{ctrlposition_folderview} eq 'top'?1:0,
                      controlbarbottom        => $prefs{ctrlposition_folderview} ne 'top'?1:0,
                      searchselectloop        => [
                                                    map { {
                                                             option   => $_,
                                                             label    => $lang_text{$_},
                                                             selected => $_ eq $searchtype?1:0
                                                        } } qw(from to subject date attfilename header textcontent all)
                                                 ],
                      pageselectloop          => [
                                                    map { {
                                                             option   => $_,
                                                             label    => $_,
                                                             selected => $_ eq $page?1:0
                                                        } } grep {
                                                                    $_ == 1
                                                                    || $_ == $totalpage
                                                                    || abs($_ - $page) < 10
                                                                    || abs($_ - $page) < 100 && $_ % 10 == 0
                                                                    || abs($_ - $page) < 1000 && $_ % 100 == 0
                                                                    || $_ % 1000 == 0
                                                                 } (1..$totalpage)
                                                 ],
                      destinationselectloop   => [
                                                    map { {
                                                             option   => $_,
                                                             label    => exists $lang_folders{$_}?$lang_folders{$_}:f2u($_),
                                                             selected => $_ eq $destinationdefault?1:0
                                                        } } @destinationfolders
                                                 ],
                      confirmmsgmovecopy      => $prefs{confirmmsgmovecopy},
                      middlepluginoutput      => htmlplugin($config{webmail_middle_pluginfile}, $config{webmail_middle_pluginfile_charset}, $prefs{charset}),
                      headingloop             => [
                                                    map { {
                                                             date    => $_ eq 'date'?1:0,
                                                             from    => $_ eq 'from'?1:0,
                                                             subject => $_ eq 'subject'?1:0,
                                                             size    => $_ eq 'size'?1:0,
                                                             active  => ($_ eq $sort || "${_}_rev" eq $sort
                                                                         || ($_ eq 'from' && $sort =~ m#^(?:recipient|sender|recipient_rev|sender_rev)$#))?1:0,
                                                        } } split(/\s*[,\s]+\s*/, $prefs{fieldorder}) # date from subject size
                                                 ],
                      headingreversesort      => $sort =~ m#_rev$#?1:0,
                      headingdatebysent       => $msgdatetype eq 'sentdate'?1:0,
                      headingfrombysender     => $sort =~ m#^(?:sender|sender_rev)$#        ? 1 :
                                                 $sort =~ m#^(?:recipient|recipient_rev)$#  ? 0 :
                                                 $folder =~ m#^(?:sent-mail|saved-drafts)$# ? 0 :
                                                 $folder =~ m#^\Q$lang_folders{'sent-mail'}\E[\Q$prefs{categorizedfolders_fs}\E\s_-]#i ? 0:1,
                      uselightbar             => $prefs{uselightbar}?1:0,
                      singlemessage           => $totalmessage == 1?1:0,
                      messagesloop            => $messagesloop,
                      useminisearchicon       => $prefs{useminisearchicon}?1:0,
                      headers                 => $prefs{headers},
                      topjumpcontrol          => ($lastmessage - $firstmessage > 10)?1:0,
                      newmailsound            => $now_inbox_newmessages > $orig_inbox_newmessages &&
                                                 -f "$config{ow_htmldir}/sounds/$prefs{newmailsound}"?$prefs{newmailsound}:0,
                      popup_quotahitdelmail   => $quotahit_deltype eq 'quotahit_delmail'?1:0,
                      popup_quotahitdelfile   => $quotahit_deltype eq 'quotahit_delfile'?1:0,
                      popup_messagesent       => (defined param('sentsubject') && $prefs{mailsentwindowtime} > 0)?1:0,
                      sentsubject             => param('sentsubject') || 'N/A',
                      mailsentwindowtime      => $prefs{mailsentwindowtime},
                      incomingmessagesloop    => $incomingmessagesloop,
                      newmailwindowtime       => $prefs{newmailwindowtime},
                      newmailwindowheight     => (scalar @{$incomingmessagesloop} * 16) + 70,

                      # footer.tmpl
                      footer_template         => get_footer($config{footer_template_file}),
                   );

   httpprint([
                -Refresh => ($prefs{refreshinterval} * 60) .
                            ";URL=openwebmail-main.pl?action=listmessages&session_noupdate=1&" .
                            join ("&", (
                                          "folder=" . ow::tool::escapeURL($folder),
                                          "keyword=" . ow::tool::escapeURL($keyword),
                                          "longpage=" . ow::tool::escapeURL($longpage),
                                          "msgdatetype=" . ow::tool::escapeURL($msgdatetype),
                                          "page=" . ow::tool::escapeURL($page),
                                          "searchtype=" . ow::tool::escapeURL($searchtype),
                                          "sessionid=" . ow::tool::escapeURL($thissession),
                                          "sort=" . ow::tool::escapeURL($sort),
                                       )
                                 )
             ], [$template->output]);
}

sub get_upcomingevents {
   # returns up to 6 upcoming events from multiple calendar sources
   my $reminderdays = shift;

   return [] unless ($config{enable_calendar} && $reminderdays > 0);

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
   my ($year, $month, $day, $hour, $min) = (ow::datetime::seconds2array($localtime))[5,4,3,2,1];
   my $hourminnow = sprintf("%02d%02d", $hour, $min);
   $month += 1;
   $year  += 1900;

   my (%items, %indexes);

   my $calbookfile = dotpath('calendar.book');
   if (readcalbook($calbookfile, \%items, \%indexes, 0) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $calbookfile");
   }

   # merge other calendar's events into the hashes. The 1E6 and 1E7 are offset numbers to
   # ensure that the index numbers of these other calendars do not collide with the index
   # numbers of the calendar.book we have already read
   if ($prefs{calendar_reminderforglobal}) {
      readcalbook("$config{global_calendarbook}", \%items, \%indexes, 1E6);
      if ($prefs{calendar_holidaydef} eq 'auto') {
         readcalbook("$config{ow_holidaysdir}/$prefs{locale}", \%items, \%indexes, 1E7);
      } elsif ($prefs{calendar_holidaydef} ne 'none') {
         readcalbook("$config{ow_holidaysdir}/$prefs{calendar_holidaydef}", \%items, \%indexes, 1E7);
      }
   }

   my $upcomingevents = [];

   my %seen = (); # remember index numbers so an item won't be shown more than once, in case it is a regexp
   foreach my $daysfromnow (0..($reminderdays-1)) {
      my $wdaynum = 0;
      ($wdaynum, $year, $month, $day) = (ow::datetime::seconds2array($localtime+$daysfromnow*86400))[6,5,4,3];
      $month += 1;
      $year  += 1900;
      my $dow   = $ow::datetime::wday_en[$wdaynum]; # Sun, Mon, etc
      my $date  = sprintf("%04d%02d%02d", $year,$month,$day);
      my $date2 = sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

      # gather all of the events for this daysfromnow
      my @indexlist=();
      push(@indexlist, @{$indexes{$date}}) if (exists $indexes{$date} && defined $indexes{$date});
      push(@indexlist, @{$indexes{'*'}})   if (exists $indexes{'*'} && defined $indexes{'*'});
      @indexlist = sort { ($items{$a}{starthourmin} || 1E9) <=> ($items{$b}{starthourmin} || 1E9) } @indexlist;

      foreach my $index (@indexlist) {
         next if (exists $seen{$index} && $seen{$index} > 0);
         next if (!$items{$index}{eventreminder});

         if ($date =~ m/$items{$index}{idate}/ || $date2 =~ /$items{$index}{idate}/ || ow::datetime::easter_match($year, $month, $day, $items{$index}{idate})) {
            if ($items{$index}{starthourmin} >= $hourminnow || $items{$index}{starthourmin} == 0 || $daysfromnow > 0) {
               $seen{$index}++;

               my $itemstartendtime = '#';
               if ($items{$index}{starthourmin} =~ m/(\d+)(\d\d)/) {
                  if ($prefs{hourformat} == 12) {
                     my ($h, $ampm) = ow::datetime::hour24to12($1);
                     $itemstartendtime = "$h:$2$ampm";
                  } else {
                     $itemstartendtime = "$1:$2";
                  }

                  if ($items{$index}{endhourmin} =~ m/(\d+)(\d\d)/) {
                     if ($prefs{hourformat} == 12) {
                        my ($h, $ampm) = ow::datetime::hour24to12($1);
                        $itemstartendtime .= "-$h:$2$ampm";
                     } else {
                        $itemstartendtime .= "-$1:$2";
                     }
                  }
               }

               my $itemstring = (iconv($items{$index}{charset}, $prefs{charset}, $items{$index}{string}))[0];
               $itemstring = substr($itemstring, 0, 20) . ".." if (length($itemstring) >= 21);
               $itemstring .= '*' if ($index >= 1E6);

               my $itemtitletext = $prefs{dateformat} || "mm/dd/yyyy";
               my ($m, $d) = (sprintf("%02d",$month), sprintf("%02d",$day));
               $itemtitletext =~ s#yyyy#$year#;
               $itemtitletext =~ s#mm#$m#;
               $itemtitletext =~ s#dd#$d#;

               push(@{$upcomingevents}, {
                                           itemdaysfromnow  => $daysfromnow,
                                           itemstartendtime => $itemstartendtime,
                                           itemstring       => $itemstring,
                                           itemtitletext    => $itemtitletext,
                                           itemweekday      => $lang_wday{$wdaynum},
                                           itemyear         => $year,
                                           itemmonth        => $month,
                                           itemday          => $day,
                                        }
                   );
               last if scalar @{$upcomingevents} > 5;
            }
         }
      }
   }

   return($upcomingevents);
}

sub markasread {
   my $messageid = param('message_id');
   return if ($messageid eq "");

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);
   my @attr = get_message_attributes($messageid, $folderdb);
   return if ($#attr < 0); # msg not found in db

   if ($attr[$_STATUS] !~ m/R/i) {
      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile) . "!");
      update_message_status($messageid, $attr[$_STATUS]."R", $folderdb, $folderfile);
      ow::filelock::lock($folderfile, LOCK_UN);
   }
}

sub markasunread {
   my $messageid = param('message_id');
   return if ($messageid eq "");

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);
   my @attr = get_message_attributes($messageid, $folderdb);
   return if ($#attr < 0); # msg not found in db

   if ($attr[$_STATUS] =~ m/[RV]/i) {
      # clear flag R(read), V(verified by mailfilter)
      my $newstatus = $attr[$_STATUS];
      $newstatus =~ s/[RV]//ig;

      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile) . "!");
      update_message_status($messageid, $newstatus, $folderdb, $folderfile);
      ow::filelock::lock($folderfile, LOCK_UN);
   }
}

sub movemessage {
   my ($r_messageids, $destination) = @_;
   if ($destination eq $folder) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{shouldnt_move_here}");
   }

   my $op = 'move';
   if ($destination eq 'DELETE') {
      return if (defined param('copybutton'));       # copy to DELETE is meaningless, so return
      $op = 'delete';
   } else {
      $op = 'copy' if (defined param('copybutton')); # copy button pressed
   }

   if ($quotalimit > 0 && $quotausage > $quotalimit && $op ne "delete") {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{quotahit_alert}");
   }

   my ($learntype, $learnfolder) = ('none', $folder);
   if ($destination eq 'LEARNSPAM') {
      $learntype   = 'learnspam';
      $destination = $folder; # force initial default to not move messages by setting destination = source
      if ($folder ne 'spam-mail' && $folder ne 'virus-mail') {
         # move spam messages if they are not in the spam or virus folders
         $learnfolder = $destination = $config{learnspam_destination};
      }
   } elsif ($destination eq 'LEARNHAM') {
      $learntype   = 'learnham';
      $destination = $folder; # force initial default to not move messages by setting destination = source
      if ($folder eq 'mail-trash' || $folder eq 'spam-mail' || $folder eq 'virus-mail') {
         # move ham messages if they are in the trash, spam, or virus folders
         $learnfolder = $destination = $config{learnham_destination};
      }
   }

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);
   my ($dstfile, $dstdb)       = get_folderpath_folderdb($user, $destination);

   if (!-f $folderfile) {
      openwebmailerror(__FILE__, __LINE__, f2u($folderfile) . " $lang_err{doesnt_exist}");
   }

   my ($counted, $errmsg) = (0, '');
   if ($folder ne $destination) {
      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile) . "!");

      if ($destination eq 'DELETE') {
         ($counted, $errmsg) = operate_message_with_ids($op, $r_messageids, $folderfile, $folderdb);
      } else {
         if (!-f "$dstfile" ) {
            if (!sysopen(F, $dstfile, O_WRONLY|O_APPEND|O_CREAT)) {
               my $err = $!;
               ow::filelock::lock($folderfile, LOCK_UN);
               openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} $lang_err{destination_folder} " . f2u($dstfile) . "! ($err)");
            }
            close(F);
         }
         if (!ow::filelock::lock($dstfile, LOCK_EX)) {
            ow::filelock::lock($folderfile, LOCK_UN);
            openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($dstfile) . "!");
         }
         ($counted, $errmsg) = operate_message_with_ids($op, $r_messageids, $folderfile, $folderdb, $dstfile, $dstdb);
      }
      folder_zapmessages($folderfile, $folderdb) if ($counted > 0);

      ow::filelock::lock($dstfile, LOCK_UN);
      ow::filelock::lock($folderfile, LOCK_UN);
   }

   # fork a child to learn the msg in the background
   # so the resultant msglist can be returned as soon as possible
   if ($learntype ne 'none') {
      # below handler is not necessary, as we call zombie_cleaner at end of each request
      #local $SIG{CHLD}=\&ow::tool::zombie_cleaner;

      local $|=1; 			# flush all output

      if ( fork() == 0 ) {		# child
         close(STDIN); close(STDOUT); close(STDERR);
         writelog("debug - $learntype process forked - " . __FILE__ . ":" . __LINE__) if ($config{debug_fork});

         ow::suid::drop_ruid_rgid(); # set ruid=euid to avoid fork in spamcheck.pl
         my ($totallearned, $totalexamed) = (0,0);
         my ($learnfile, $learndb) = get_folderpath_folderdb($user, $learnfolder);
         # TODO: replace Filehandle with IO::Handle. IO::Handle uses less memory.
         # right now this is coming from the maildb.pl file 'use Filehandle;'
         my $learnhandle = FileHandle->new();
         foreach my $messageid (@{$r_messageids}) {
            my ($msgsize, $errmsg, $block, $learned, $examed);
            ($msgsize, $errmsg) = lockget_message_block($messageid, $learnfile, $learndb, \$block);
            next if ($msgsize <= 0);

            if ($learntype eq 'learnspam') {
               ($learned, $examed) = ow::spamcheck::learnspam($config{learnspam_pipe}, \$block);
            } else {
               ($learned, $examed) = ow::spamcheck::learnham($config{learnham_pipe}, \$block);
            }
            if ($learned == -99999) {
               my $m = "$learntype - error ($examed) at $messageid";
               writelog($m);
               writehistory($m);
               last;
            } else {
               $totallearned += $learned;
               $totalexamed  += $examed;
            }
         }
         my $m = "$learntype - $totallearned learned, $totalexamed examined";
         writelog($m);
         writehistory($m);

         writelog("debug - $learntype process terminated - " . __FILE__ . ":" . __LINE__) if ($config{debug_fork});
         openwebmail_exit(0);
      }
   }

   if ($counted > 0){
      my $msg;
      if ( $op eq 'move') {
         $msg = "move message - move $counted msgs from $folder to $destination - ids=" . join(", ", @{$r_messageids});
      } elsif ($op eq 'copy' ) {
         $msg = "copy message - copy $counted msgs from $folder to $destination - ids=" . join(", ", @{$r_messageids});
      } else {
         $msg = "delete message - delete $counted msgs from $folder - ids=" . join(", ", @{$r_messageids});
        # recalc used quota for del if user quotahit
        if ($quotalimit > 0 && $quotausage > $quotalimit) {
           $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
        }
      }
      writelog($msg);
      writehistory($msg);
   } elsif ($counted < 0) {
      openwebmailerror(__FILE__, __LINE__, $errmsg);
   }
   return;
}

sub www_emptyfolder {
   my $folder = shift;
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile) . "!");
   my $ret = empty_folder($folderfile, $folderdb);
   ow::filelock::lock($folderfile, LOCK_UN);

   if ($ret == -1) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} " . f2u($folderfile) . "!");
   } elsif ($ret == -2) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_updatedb} db " . f2u($folderdb));
   }

   writelog("emptyfolder - $folder");
   writehistory("emptyfolder - $folder");
}

sub www_pop3_fetch {
   my $pop3host = param('pop3host') || '';
   my $pop3port = param('pop3port') || '110';
   my $pop3user = param('pop3user') || '';
   my $pop3book = dotpath('pop3.book');

   return if ($pop3host eq '' || $pop3user eq '' || !-f $pop3book);

   foreach ( @{$config{pop3_disallowed_servers}} ) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{disallowed_pop3} $pop3host") if ($pop3host eq $_);
   }

   my %accounts;
   if (readpop3book($pop3book, \%accounts) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $pop3book!");
   }

   # ignore the enable flag since this is triggered by user clicking
   my ($pop3ssl, $pop3passwd, $pop3del) = (split(/\@\@\@/, $accounts{"$pop3host:$pop3port\@\@\@$pop3user"}))[2,4,5];

   my ($ret, $errmsg) = pop3_fetch($pop3host,$pop3port,$pop3ssl, $pop3user,$pop3passwd,$pop3del);

   if ($ret < 0) {
      openwebmailerror(__FILE__, __LINE__, "$errmsg at $pop3user\@$pop3host:$pop3port");
   }
}

sub pop3_fetch {
   my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del) = @_;

   my ($ret, $errmsg) = fetchmail($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del);

   if ($ret < 0) {
      writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
      writehistory("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
   }
   return($ret, $errmsg);
}

sub authpop3_fetch {
   return 0 if (!$config{authpop3_getmail});

   my $authpop3book = dotpath('authpop3.book');
   my %accounts;
   if (-f "$authpop3book") {
      if (readpop3book($authpop3book, \%accounts) > 0) {
         my $login = $user;
         $login .= "\@$domain" if $config{auth_withdomain};

         my ($pop3ssl, $pop3passwd, $pop3del) = (split(/\@\@\@/, $accounts{"$config{authpop3_server}:$config{authpop3_port}\@\@\@$login"}))[2,4,5];

         # don't case enable flag since noreason to stop fetch from auth server
         return pop3_fetch($config{authpop3_server},$config{authpop3_port},$pop3ssl, $login,$pop3passwd,$pop3del);
      } else {
         writelog("pop3 error - couldn't open $authpop3book");
         writehistory("pop3 error - couldn't open $authpop3book");
      }
   }
   return 0;
}

sub www_pop3_fetches {
   return if (! -f dotpath('pop3.book'));
   if (update_pop3check()) {
      authpop3_fetch() if ($config{auth_module} eq 'auth_pop3.pl' ||
                           $config{auth_module} eq 'auth_ldap_vpopmail.pl');
   }
   pop3_fetches(10);	# wait background fetching for no more 10 second
}

sub pop3_fetches {
   my $timeout = shift;

   my $pop3book = dotpath('pop3.book');

   my %accounts;
   return 0 if ( ! -f "$pop3book" );
   if (readpop3book("$pop3book", \%accounts) < 0) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_read} $pop3book!");
   }

   # fork a child to do fetch pop3 mails and return immediately
   if (%accounts > 0) {
      local $| = 1;                                                 # flush all output
      local $pop3_fetches_complete = 0;	                            # localize for reentry safe
      local $SIG{CHLD} = sub { wait; $pop3_fetches_complete = 1; }; # signaled when pop3 fetch completes

      if ( fork() == 0 ) { # child
         close(STDIN);
         close(STDOUT);
         close(STDERR);

         writelog("debug - pop3_fetches process forked - " . __FILE__ . ":" . __LINE__) if ($config{debug_fork});

         ow::suid::drop_ruid_rgid(); # set ruid=euid can avoid fork in spamcheck.pl
         foreach (values %accounts) {
            my ($pop3host,$pop3port,$pop3ssl, $pop3user,$pop3passwd, $pop3del, $enable) = split(/\@\@\@/,$_);

            next if (!$enable);

            my $disallowed = 0;
            foreach ( @{$config{pop3_disallowed_servers}} ) {
               if ($pop3host eq $_) {
                  $disallowed = 1;
                  last;
               }
            }
            next if ($disallowed);
            my ($ret, $errmsg) = fetchmail($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del);
            if ($ret < 0) {
               writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
               writehistory("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
            }
         }

         writelog("debug - fetch pop3s process terminated - " .__FILE__.":". __LINE__) if ($config{debug_fork});
         openwebmail_exit(0);
      }

      # wait for fetch to complete for $timeout seconds
      for (my $i=0; $i<$timeout; $i++) {
         sleep 1;
         last if ($pop3_fetches_complete);
      }
   }

   return 0;
}

sub update_pop3check {
   my $now = time();

   my $pop3checkfile = dotpath('pop3.check');

   my $ftime = (stat($pop3checkfile))[9];

   if (!$ftime) { # create if not exist
      sysopen(F, $pop3checkfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} $pop3checkfile! ($!)");
      print F "pop3check timestamp file";
      close(F);
   }
   if ( $now - $ftime > $config{fetchpop3interval} * 60 ) {
      utime($now - 1, $now - 1, ow::tool::untaint($pop3checkfile)); # -1 is trick for nfs
      return 1;
   } else {
      return 0;
   }
}

sub moveoldmsg2saved {
   my ($srcfile, $srcdb) = get_folderpath_folderdb($user, 'INBOX');
   my ($dstfile, $dstdb) = get_folderpath_folderdb($user, 'saved-messages');

   ow::filelock::lock($srcfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($srcfile) . "!");
   ow::filelock::lock($dstfile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($dstfile) . "!");

   my $counted = move_oldmsg_from_folder($srcfile, $srcdb, $dstfile, $dstdb);

   ow::filelock::lock($dstfile, LOCK_UN);
   ow::filelock::lock($srcfile, LOCK_UN);

   if ($counted > 0){
      my $msg = "move message - move $counted old msgs from INBOX to saved-messages";
      writelog($msg);
      writehistory($msg);
   }
}

sub clean_trash_spamvirus {
   my $now = time();

   my $trashcheckfile = dotpath('trash.check');

   my $ftime = (stat($trashcheckfile))[9];

   if (!$ftime) { # create if not exist
      sysopen(TRASHCHECK, $trashcheckfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_write} " . f2u($trashcheckfile) . "! ($!)");
      print TRASHCHECK "trashcheck timestamp file";
      close(TRASHCHECK);
   }

   my %reserveddays=('mail-trash' => $prefs{trashreserveddays},
                     'spam-mail'  => $prefs{spamvirusreserveddays},
                     'virus-mail' => $prefs{spamvirusreserveddays} );
   my (@f, $msg);
   push(@f, 'virus-mail') if ($config{has_virusfolder_by_default});
   push(@f, 'spam-mail') if ($config{has_spamfolder_by_default});
   push(@f, 'mail-trash');
   foreach my $folder (@f) {
      next if ($reserveddays{$folder} < 0 || $reserveddays{$folder} >= 999999);

      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{couldnt_writelock} " . f2u($folderfile) . "!");

      if ($reserveddays{$folder} == 0) { # empty folder
         my $ret = empty_folder($folderfile, $folderdb);
         if ($ret == 0) {
            $msg .= ', ' if (defined $msg && $msg ne '');
            $msg .= "all msg deleted from $folder";
         }
      } elsif ( $now - $ftime > 43200 ) { # do clean only if last clean has passed for more than 0.5 day (43200 sec)
         my $deleted = delete_message_by_age($reserveddays{$folder}, $folderdb, $folderfile);
         if ($deleted > 0) {
            $msg .= ', ' if (defined $msg && $msg ne '');
            $msg .= "$deleted msg deleted from $folder";
         }
      }
      ow::filelock::lock($folderfile, LOCK_UN);
   }
   if (defined $msg && $msg ne '') {
      writelog("clean trash - $msg");
      writehistory("clean trash - $msg");
   }

   if ( $now-$ftime > 43200 ) {	# more than half day, update timestamp of checkfile
      utime($now - 1, $now - 1, ow::tool::untaint($trashcheckfile)); # -1 is trick for nfs
   }
   return;
}

sub logout {
   unlink "$config{ow_sessionsdir}/$thissession";
   autologin_rm(); # disable next autologin for specific ip/browser/user
   writelog("logout - $thissession");
   writehistory("logout - $thissession");

   my $start_url = $config{start_url};

   if (cookie("ow-ssl")) { # backto SSL
      $start_url = "https://$ENV{HTTP_HOST}$start_url" if ($start_url !~ s#^https?://#https://#i);
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("main_logout.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 1,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 1,
                                     );

   $template->param(
                      # header.tmpl
                      header_template     => get_header($config{header_template_file}),

                      # main_logout.tmpl
                      url_start           => $start_url,
                      default_logindomain => $default_logindomain,

                      # footer.tmpl
                      footer_template     => get_footer($config{footer_template_file}),
                   );

   # clear session cookie at logout
   my $cookie= cookie(-name  => "ow-sessionkey-$domain-$user",
                      -value => '',
                      -path  => '/',
                      -expires => '+1s');

   httpprint([-cookie => $cookie], [$template->output]);
}
