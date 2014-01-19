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
require "shares/adrbook.pl";

# optional module
ow::tool::has_module('IO/Socket/SSL.pm');
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($default_logindomain);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs $icons);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw($htmltemplatefilters $po); # defined in ow-shared.pl
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES); # defined in maildb.pl

# local globals
use vars qw($folder $sort $msgdatetype $page $longpage $searchtype $keyword);
use vars qw($pop3_fetches_complete);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

my $action = param('action') || '';

openwebmailerror(gettext('Access denied: the webmail module is not enabled.'))
   if !$config{enable_webmail} && $action ne 'logout';

$folder      = param('folder') || 'INBOX';
$keyword     = param('keyword') || '';
$longpage    = param('longpage') || 0;
$msgdatetype = param('msgdatetype') || $prefs{msgdatetype};
$page        = param('page') || 1;
$searchtype  = param('searchtype') || $prefs{searchtype} || 'subject';
$sort        = param('sort') || $prefs{sort} || 'date_rev';

$keyword     =~ s/^\s*//;
$keyword     =~ s/\s*$//;

if (param('clearsearchbutton')) {
  $keyword  = '';
  $longpage = 0;
  $page     = 1;
}

# TODO: This action processing seems a little overly complicated. It could probably be cleaner and simpler.
writelog("debug_request :: request main begin, action=$action, folder=$folder") if $config{debug_request};

if ($action eq 'movemessage' || defined param('movebutton') || defined param('copybutton') ) {
   my $destination = ow::tool::untaint(safefoldername(param('destination')));

   if ($destination eq 'FORWARD') {
      my @messageids = param('message_ids');

      if (scalar @messageids > 0) {
         my %params = (
                        action          => 'compose',
                        compose_caller  => 'main',
                        folder          => $folder,
                        keyword         => $keyword,
                        longpage        => $longpage,
                        msgdatetype     => $msgdatetype,
                        page            => $page,
                        searchtype      => $searchtype,
                        sessionid       => $thissession,
                        sort            => $sort,
                      );

         if (scalar @messageids == 1) {
            # a single message will be forwarded inline style
            $params{composetype} = 'forward';
            $params{message_id}  = $messageids[0];
         }

         if (scalar @messageids > 1) {
            # multiple messages will be forwarded as attachments
            $params{composetype} = 'forwardasatt';

            # write the forwarding message-ids to a file for openwebmail-send to read
            my $batchid = join('', map { int(rand(10)) }(1..9));
            sysopen(FORWARDIDS, "$config{ow_sessionsdir}/$thissession-forwardids-$batchid", O_WRONLY|O_TRUNC|O_CREAT)
              or openwebmailerror(gettext('Cannot open file:') . " $config{ow_sessionsdir}/$thissession-forwardids-$batchid ($!)");

            print FORWARDIDS join("\n", @messageids);

            close(FORWARDIDS)
              or openwebmailerror(gettext('Cannot close file:') . " $config{ow_sessionsdir}/$thissession-forwardids-$batchid ($!)");

            $params{forward_batchid} = $batchid;
         }

         my $redirect = "$config{ow_cgiurl}/openwebmail-send.pl?" .
                        join('&', map { "$_=" . ow::tool::escapeURL($params{$_}) } sort keys %params);
         print redirect(-location => $redirect);
      } else {
         listmessages();
      }
   } elsif ($destination eq 'MARKASREAD') {
      markasread();
      listmessages();
   } elsif ($destination eq 'MARKASUNREAD') {
      markasunread();
      listmessages();
   } else {
      # move/copy/delete messages
      my @messageids = param('message_ids');
      movemessage(\@messageids, $destination) if scalar @messageids > 0;

      if (param('messageaftermove')) {
         my $headers   = param('headers') || $prefs{headers} || 'simple';
         my $attmode   = param('attmode') || 'simple';
         my $messageid = param('messageaftermove') || '';
         $messageid    = $messageids[0] if defined param('copybutton'); # copy button pressed, msg not moved

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
} elsif ($action eq 'listmessages_afterlogin') {
   clean_trash_spamvirus();

   $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2] if $quotalimit > 0 && $quotausage > $quotalimit;

   moveoldmsg2saved() if ($config{forced_moveoldmsgfrominbox} || $prefs{moveoldmsgfrominbox}) && (!$quotalimit || ($quotausage < $quotalimit));

   update_pop3check();
   authpop3_fetch() if $config{auth_module} eq 'auth_pop3.pl' || $config{auth_module} eq 'auth_ldap_vpopmail.pl';
   pop3_fetches($prefs{autopop3wait}) if $config{enable_pop3} && $prefs{autopop3};
   listmessages();
} elsif ($action eq 'userrefresh') {
   authpop3_fetch() if $folder eq 'INBOX' && ($config{auth_module} eq 'auth_pop3.pl' || $config{auth_module} eq 'auth_ldap_vpopmail.pl');

   $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2] if $config{quota_module} ne 'none';

   listmessages();

   pop3_fetches(0) if update_pop3check() && $config{enable_pop3} && $prefs{autopop3};
} elsif ($action eq 'listmessages') {
   my $update = update_pop3check() ? 1 : 0;

   # get mail from auth pop3 server
   authpop3_fetch() if $update && ($config{auth_module} eq 'auth_pop3.pl' || $config{auth_module} eq 'auth_ldap_vpopmail.pl');

   listmessages();

   # get mail from misc pop3 servers
   pop3_fetches(0) if $update && $config{enable_pop3} && $prefs{autopop3};
} elsif ($action eq 'markasread') {
   markasread();
   listmessages();
} elsif ($action eq 'markasunread') {
   markasunread();
   listmessages();
} elsif ($action eq 'pop3fetches' && $config{enable_pop3}) {
   www_pop3_fetches();
   listmessages();
} elsif ($action eq 'pop3fetch' && $config{enable_pop3}) {
   www_pop3_fetch();
   listmessages();
} elsif ($action eq 'emptyfolder') {
   www_emptyfolder($folder);

   $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2] if $quotalimit > 0 && $quotausage > $quotalimit;

   listmessages();
} elsif ($action eq 'logout') {
   clean_trash_spamvirus();

   moveoldmsg2saved() if ($config{forced_moveoldmsgfrominbox} || $prefs{moveoldmsgfrominbox}) && (!$quotalimit || ($quotausage < $quotalimit));

   logout();
} else {
   openwebmailerror(gettext('Action has illegal characters.'));
}

writelog("debug_request :: request main end, action=$action, folder=$folder") if $config{debug_request};

openwebmail_requestend();



# BEGIN SUBROUTINES

sub listmessages {
   my $orig_inbox_newmessages = 0;
   my $now_inbox_newmessages  = 0;
   my $now_inbox_allmessages  = 0;
   my $inboxsize_k            = 0;
   my $folder_allmessages     = 0;

   my %FDB = ();

   # make note of how many inbox messages we have before re-reading the inbox
   my $spooldb = (get_folderpath_folderdb($user, 'INBOX'))[1];
   if (ow::dbm::existdb($spooldb)) {
      ow::dbm::opendb(\%FDB, $spooldb, LOCK_SH) or
         openwebmailerror(gettext('Cannot open db:') . " $spooldb ($!)");

      $orig_inbox_newmessages = $FDB{NEWMESSAGES} || 0; # new messages in INBOX

      ow::dbm::closedb(\%FDB, $spooldb) or
         openwebmailerror(gettext('Cannot close db:') . " $spooldb ($!)");
   }

   writelog("debug_mailprocess :: $folder :: listmessages") if $config{debug_mailprocess};

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
            my $webdiskrootdir = $homedir . absolute_vpath('/', $config{webdisk_rootpath});
            cutdirfiles(($quotausage - ($quotalimit * 0.9)) * 1024, $webdiskrootdir);
         }
         $quotausage = (ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2]; # get up to date usage
      }
   }

   my $enable_quota       = $config{quota_module} eq 'none' ? 0 : 1;
   my $quotashowusage     = 0;
   my $quotaoverthreshold = 0;
   my $quotabytesusage    = 0;
   my $quotapercentusage  = 0;
   if ($enable_quota) {
      $quotaoverthreshold = (($quotalimit > 0) && (($quotausage / $quotalimit) > ($config{quota_threshold} / 100)));
      $quotashowusage     = ($quotaoverthreshold || $config{quota_threshold} == 0) ? 1 : 0;
      $quotabytesusage    = lenstr($quotausage * 1024, 1) if $quotashowusage;
      $quotapercentusage  = int($quotausage * 1000 / $quotalimit) / 10 if $quotaoverthreshold;
   }

   my $folderselectloop = [];
   foreach my $foldername (@validfolders) {
      my $newmessagesthisfolder = 0;
      my $allmessagesthisfolder = 0;

      # find message count for this folder
      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $foldername);
      if (ow::dbm::existdb($folderdb)) {
         ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
            openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb) . " ($!)");

         $allmessagesthisfolder  = $FDB{ALLMESSAGES} if (defined $FDB{ALLMESSAGES});
         $allmessagesthisfolder -= $FDB{ZAPMESSAGES} if (defined $FDB{ZAPMESSAGES});
         $allmessagesthisfolder -= $FDB{INTERNALMESSAGES} if (defined $FDB{INTERNALMESSAGES} && $prefs{hideinternal});
         $newmessagesthisfolder  = $FDB{NEWMESSAGES} || 0;

         if ($foldername eq 'INBOX') {
            $now_inbox_allmessages = $allmessagesthisfolder;
            $now_inbox_newmessages = $newmessagesthisfolder;
            $inboxsize_k = (-s $folderfile) / 1024;
         } elsif ($foldername eq $folder) {
            $folder_allmessages = $allmessagesthisfolder;
         }

         ow::dbm::closedb(\%FDB, $folderdb) or
            openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($folderdb) . " ($!)");
      }

      push(@{$folderselectloop}, {
                                    "option_$foldername"  => 1,
                                    is_defaultfolder      => is_defaultfolder($foldername) ? 1 : 0,
                                    option                => $foldername,
                                    label                 => f2u($foldername),
                                    selected              => $foldername eq $folder ? 1 : 0,
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
      push(@destinationfolders, 'LEARNSPAM', 'LEARNHAM') if $config{enable_learnspam};
      push(@destinationfolders, 'MARKASREAD', 'MARKASUNREAD', 'FORWARD', 'DELETE');
   }

   my $destinationdefault = '';
   if ($quotalimit > 0 && $quotausage >= $quotalimit) {
      $destinationdefault = 'DELETE';
   } elsif ($folder =~ m/^(?:mail-trash|spam-mail|virus-mail)$/) {
      $destinationdefault = 'INBOX';
   } elsif ($folder =~ m/^(?:sent-mail|saved-drafts)$/) {
      $destinationdefault = 'mail-trash';
   } else {
      $destinationdefault = $prefs{defaultdestination} || 'mail-trash';
      $destinationdefault = 'mail-trash' if $folder eq $destinationdefault;
   }

   # automatically switch search in sent-mail for convenience
   $searchtype = 'to' if !defined param('searchtype') && !$keyword && $searchtype eq 'from' && $folder eq 'sent-mail';

   # load the contacts map of email addresses to xowmuids
   # so we can provide quick links to contact information
   my $contacts = {};

   if ($config{enable_addressbook}) {
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

   my $userbrowsercharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{available_locales})))[4];

   # get all the messageids, already sorted
   my ($totalsize, $newmessages, $r_messageids, $r_messagedepths) = getinfomessageids($user, $folder, $sort, $msgdatetype, $searchtype, $keyword);

   my $totalmessage = scalar @{$r_messageids};
   $totalmessage = 0 if $totalmessage < 0;

   my $totalmessagesummary = sprintf(ngettext('%d message', '%d messages', $totalmessage), $totalmessage);
   my $newmessagessummary = sprintf(ngettext('%d unread', '%d unread', $newmessages), $newmessages);

   my $msgsperpage = $prefs{msgsperpage} || 10;
   my $showmsgsperpage = $longpage ? $msgsperpage : 1000;
   $msgsperpage = 1000 if $longpage;

   my $totalpage = int($totalmessage/$msgsperpage+0.999999);
   $totalpage = 1 if $totalpage == 0;

   $page = 1 if $page < 1;
   $page = $totalpage if $page > $totalpage;

   my $firstmessage = ($page-1) * $msgsperpage + 1;

   my $lastmessage = $firstmessage + $msgsperpage - 1;
   $lastmessage = $totalmessage if $lastmessage > $totalmessage;

   my $categorizedfolders_prefix = gettext('Sent');

   # process the messages that we have already retrieved above with getinfomessageids
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   ow::dbm::opendb(\%FDB, $folderdb, LOCK_SH) or
      openwebmailerror(gettext('Cannot open db:') . ' ' . f2u($folderdb) . " ($!)");

   my $messagesloop = [];

   foreach my $messagenumber ($firstmessage  .. $lastmessage) {
      my $messageid    = $r_messageids->[$messagenumber - 1];
      my $messagedepth = $r_messagedepths->[$messagenumber - 1] || 0;

      next unless defined $FDB{$messageid};

      my @attr = string2msgattr($FDB{$messageid});

      # assume message is from sender using same charset as the
      # recipients browser if the charset is not defined by the message
      my $charset = $attr[$_CHARSET] || $userbrowsercharset || 'utf-8';

      # convert from database stored 'utf-8' charset to current user charset
      my ($from, $to, $subject) = iconv('utf-8', $prefs{charset}, $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT]);

      # status
      my $status = $attr[$_STATUS] || '';
      $status =~ s/\s//g; # remove whitespace

      # date difference between received time and sent time
      my $timeintransit = ow::datetime::dateserial2gmtime($attr[$_RECVDATE]) - ow::datetime::dateserial2gmtime($attr[$_DATE]);
      my $timeintransitsign = $timeintransit > 0 ? '+' : '-';
      $timeintransit *= -1 if $timeintransit < 0;

      # from/to
      my @to_namelist = ();
      my @to_addrlist = ();
      foreach my $recipient (ow::tool::str2list($to)) {
         my ($name, $emailaddress) = ow::tool::email2nameaddr($recipient);
         next if !defined $name || !defined $emailaddress || $name =~ m/"/ || $emailaddress =~ m/"/; # eliminate incomplete addresses
         push(@to_namelist, $name);
         push(@to_addrlist, $emailaddress);
      }

      my $to_names = join(", ", @to_namelist);
      $to_names = mbsubstr($to_names, 0, 29, $prefs{charset}) . '...' if length $to_names > 32;

      my $to_addrs = join(", ", @to_addrlist);
      $to_addrs = mbsubstr($to_addrs, 0, 61, $prefs{charset}) . '...' if length $to_addrs > 64;

      my $to_keywords = join('|',@to_addrlist); # for searching

      my $to_xowmuid = (scalar @to_addrlist == 1 && exists $contacts->{lc($to_addrlist[0])}) ? $contacts->{lc($to_addrlist[0])} : 0;

      my ($from_name, $from_addr) = ow::tool::email2nameaddr($from);
      $from_addr =~ s/"//g;
      $from_name = mbsubstr($from_name, 0, 37, $prefs{charset}) . '...' if length $from_name > 40;
      $from_name =~ s/\\(["'])/$1/g; # e.g: Toys \"R\" Us ==> Toys "R" Us

      my $from_xowmuid = exists $contacts->{lc($from_addr)} ? $contacts->{lc($from_addr)} : 0;

      my ($add_givenname, $add_familyname, $add_email) =
        $sort =~ m/^(?:sender|sender_rev)$/ ? (split(/\s+/, $from_name, 2), $from_addr) :
        scalar @to_addrlist == 1
        && (
             $sort =~ m/^(?:recipient|recipient_rev)$/
             || $folder =~ m/^(?:sent-mail|saved-drafts)$/
             || $folder =~ m/^\Q$categorizedfolders_prefix\E[\Q$prefs{categorizedfolders_fs}\E]/i
           ) ? (split(/\s+/, $to_names, 2), $to_addrs) : (split(/\s+/, $from_name, 2), $from_addr);

      # subject
      $subject = mbsubstr($subject, 0, 64, $prefs{charset}) . '...' if length $subject > 67;

      my $subject_keyword = $subject;
      $subject_keyword =~ s/^(?:\s*.{1,3}[.\s]*:\s*)+//; # strip leading Re: Fw: R: Res: Ref:
      $subject_keyword =~ s/\[.*?\]:?//g;                # strip leading [listname] type text

      push(@{$messagesloop}, {
                                odd                  => (scalar @{$messagesloop} + 1) % 2, # for row color toggle
                                messagenumber        => $messagenumber,
                                messageid            => $messageid,
                                messagecharset       => lc($charset),
                                messagestatus        => $status,
                                status_read          => $status =~ m/R/i ? 1 : 0,
                                status_answered      => $status =~ m/A/i ? 1 : 0,
                                status_attachments   => $status =~ m/T/i ? 1 : 0,
                                status_important     => $status =~ m/I/i ? 1 : 0,
                                messagedatesent      => ow::datetime::dateserial2str(
                                                          $attr[$_DATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                                          $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}),
                                messagedatereceived  => ow::datetime::dateserial2str(
                                                          $attr[$_RECVDATE], $prefs{timeoffset}, $prefs{daylightsaving},
                                                          $prefs{dateformat}, $prefs{hourformat}, $prefs{timezone}),
                                showdatereceived     => $msgdatetype eq 'recvdate' ? 1 : 0,
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
                                                        ?  $sort =~ m#^(?:sender|sender_rev)$#
                                                           ? $from_xowmuid
                                                           : $sort =~ m#^(?:recipient|recipient_rev)$#
                                                             || $folder =~ m#^(?:sent-mail|saved-drafts)$#
                                                             || $folder =~ m#^\Q$categorizedfolders_prefix\E[\Q$prefs{categorizedfolders_fs}\E]#i
                                                             ? $to_xowmuid
                                                             : $from_xowmuid
                                                        : '',
                                hide_contactadd      => !$config{enable_addressbook}
                                                        || scalar @to_addrlist != 1
                                                           && (
                                                                $sort =~ m#^(?:recipient|recipient_rev)$#
                                                                || $folder =~ m#^(?:sent-mail|saved-drafts)$#
                                                                || $folder =~ m#^\Q$categorizedfolders_prefix\E[\Q$prefs{categorizedfolders_fs}\E]#i
                                                              ) ? 1 : 0,
                                add_givenname        => $add_givenname,
                                add_familyname       => $add_familyname,
                                add_email            => $add_email,
                                subjecttext          => $subject,
                                subjectindent        => '&nbsp;' x $messagedepth,
                                subject_keyword      => $subject_keyword,
                                messagesize          => lenstr($attr[$_SIZE], 0),
                                accesskey            => (scalar @{$messagesloop}) + 1 < 10 ? (scalar @{$messagesloop}) + 1 : '',
                             }
          );
   }

   ow::dbm::closedb(\%FDB, $folderdb) or
      openwebmailerror(gettext('Cannot close db:') . ' ' . f2u($folderdb) . " ($!)");

   undef(@{$r_messageids});
   undef($r_messageids);

   # incoming messages popup
   my $incomingmessagesloop = [];
   if ($prefs{newmailwindowtime} > 0) {
      if ($now_inbox_newmessages > $orig_inbox_newmessages) {
         push(@{$incomingmessagesloop}, {
                                           is_defaultfolder     => 1,
                                           incomingfolder_INBOX => gettext('Inbox'),
                                           incomingcount        => $now_inbox_newmessages - $orig_inbox_newmessages,
                                        }
             );
      }

      my ($totalfiltered, %filtered) = read_filterfolderdb(1);

      if (defined $totalfiltered && $totalfiltered > 0) {
         foreach my $defaultfolder (get_defaultfolders(), 'DELETE') {
            if (exists $filtered{$defaultfolder} && $filtered{$defaultfolder} > 0) {
               push(@{$incomingmessagesloop}, {
                                                 is_defaultfolder                => 1,
                                                 "incomingfolder_$defaultfolder" => 1,
                                                 incomingcount                   => $filtered{$defaultfolder},
                                              }
                   );
            }
         }

         foreach my $filteredfolder (sort keys %filtered) {
            next if is_defaultfolder($filteredfolder);
            push(@{$incomingmessagesloop}, {
                                              is_defaultfolder => 0,
                                              incomingfolder   => f2u($filteredfolder),
                                              incomingcount    => $filtered{$filteredfolder},
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
      $unread_messages_info = sprintf(ngettext('Inbox: %d unread message', 'Inbox: %d unread messages', $now_inbox_newmessages), $now_inbox_newmessages);
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
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        # TODO get rid of global_vars by explicitly declaring vars in loops
                                        # this is slow and makes a big mess of the loop vars
                                        global_vars       => 1,
                                        cache             => 0,
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
                      use_texticon            => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      iconset                 => $prefs{iconset},
                      charset                 => $prefs{charset},
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # main_listview.tmpl
                      messagesperpagesummary  => sprintf(ngettext('%d message per page','%d messages per page', $showmsgsperpage), $showmsgsperpage),
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
                      totalmessages           => $totalmessage,
                      messagessummary         => $newmessages
                                                 ? "$newmessagessummary / $totalmessagesummary / " . lenstr($totalsize, 1)
                                                 : "$totalmessagesummary / " . lenstr($totalsize, 1),
                      enable_userfilter       => $config{enable_userfilter},
                      enable_saprefs          => $config{enable_saprefs},
                      enable_preference       => $config{enable_preference},
                      is_folder_inbox         => $folder eq 'INBOX' ? 1 : 0,
                      enable_webmail          => $config{enable_webmail},
                      enable_pop3             => $config{enable_pop3},
                      enable_advsearch        => $config{enable_advsearch},
                      enable_addressbook      => $config{enable_addressbook},
                      enable_calendar         => $config{enable_calendar},
                      enable_webdisk          => $config{enable_webdisk},
                      enable_sshterm          => $config{enable_sshterm},
                      use_ssh2                => -r "$config{ow_htmldir}/applet/mindterm2/mindterm.jar" ? 1 : 0,
                      use_ssh1                => -r "$config{ow_htmldir}/applet/mindterm/mindtermfull.jar" ? 1 : 0,
                      calendar_defaultview    => $prefs{calendar_defaultview},
                      enable_learnham         => $config{enable_learnspam} && $folder eq 'spam-mail' ? 1 : 0,
                      enable_learnspam        => $config{enable_learnspam} && $folder !~ m#^(?:saved-drafts|sent-mail|spam-mail|virus-mail)$# ? 1 : 0,
                      show_emptyfolder        => $folder =~ m#^(?:mail-trash|spam-mail|virus-mail)$# ? 1 : 0,
                      emptyfolderconfirm      => $folder eq 'mail-trash'
                                                 ? sprintf(ngettext('Empty Trash folder (%d message)?','Empty Trash folder (%d messages)?', $folder_allmessages), $folder_allmessages) :
                                                 $folder eq 'spam-mail'
                                                 ? sprintf(ngettext('Empty Spam folder (%d message)?','Empty Spam folder (%d messages)?', $folder_allmessages), $folder_allmessages) :
                                                 $folder eq 'virus-mail'
                                                 ? sprintf(ngettext('Empty Virus folder (%d message)?','Empty Virus folder (%d messages)?', $folder_allmessages), $folder_allmessages) : '',
                      trashfolder             => $quotalimit > 0 && $quotausage > $quotalimit ? 'DELETE' : 'mail-trash',
                      totalpage               => $totalpage,
                      nextpage                => $page < $totalpage ? ($page + 1) : 0,
                      prevpage                => ($page - 1) || 0,
                      is_right_to_left        => $ow::lang::RTL{$prefs{locale}} ? 1 : 0,
                      eventreminderloop       => get_upcomingevents($prefs{calendar_reminderdays}),
                      controlbartop           => $prefs{ctrlposition_folderview} eq 'top' ? 1 : 0,
                      controlbarbottom        => $prefs{ctrlposition_folderview} ne 'top' ? 1 : 0,
                      searchselectloop        => [
                                                    map { {
                                                             "option_$_" => $_,
                                                             selected    => $_ eq $searchtype ? 1 : 0
                                                        } } qw(from to subject date attfilename header textcontent all)
                                                 ],
                      pageselectloop          => [
                                                    map { {
                                                             option   => $_,
                                                             label    => $_,
                                                             selected => $_ eq $page ? 1 : 0
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
                                                             "option_$_"      => 1,
                                                             is_defaultfolder => is_defaultfolder($_) ? 1 : 0,
                                                             option           => $_,
                                                             label            => f2u($_),
                                                             selected         => $_ eq $destinationdefault ? 1 : 0
                                                        } } @destinationfolders
                                                 ],
                      confirmmsgmovecopy      => $prefs{confirmmsgmovecopy},
                      middlepluginoutput      => htmlplugin($config{webmail_middle_pluginfile}, $config{webmail_middle_pluginfile_charset}, $prefs{charset}),
                      headingloop             => [
                                                    map { {
                                                             date    => $_ eq 'date' ? 1 : 0,
                                                             from    => $_ eq 'from' ? 1 : 0,
                                                             subject => $_ eq 'subject' ? 1 : 0,
                                                             size    => $_ eq 'size' ? 1 : 0,
                                                             active  => ($_ eq $sort || "${_}_rev" eq $sort
                                                                         || (
                                                                              $_ eq 'from'
                                                                              && $sort =~ m#^(?:recipient|sender|recipient_rev|sender_rev)$#)
                                                                            ) ? 1 : 0,
                                                        } } split(/\s*[,\s]+\s*/, $prefs{fieldorder}) # date from subject size
                                                 ],
                      headingreversesort      => $sort =~ m#_rev$# ? 1 : 0,
                      headingdatebysent       => $msgdatetype eq 'sentdate' ? 1 : 0,
                      headingfrombysender     => $sort =~ m#^(?:sender|sender_rev)$#        ? 1 :
                                                 $sort =~ m#^(?:recipient|recipient_rev)$#  ? 0 :
                                                 $folder =~ m#^(?:sent-mail|saved-drafts)$# ? 0 :
                                                 $folder =~ m#^\Q$categorizedfolders_prefix\E[\Q$prefs{categorizedfolders_fs}\E]#i ? 0 : 1,
                      uselightbar             => $prefs{uselightbar} ? 1 : 0,
                      singlemessage           => $totalmessage == 1 ? 1 : 0,
                      messagesloop            => $messagesloop,
                      useminisearchicon       => $prefs{useminisearchicon} ? 1 : 0,
                      headers                 => $prefs{headers},
                      topjumpcontrol          => ($lastmessage - $firstmessage > 10) ? 1 : 0,
                      newmailsound            => $now_inbox_newmessages > $orig_inbox_newmessages &&
                                                 -f "$config{ow_htmldir}/sounds/$prefs{newmailsound}" ? $prefs{newmailsound} : 0,
                      popup_quotahitdelmail   => $quotahit_deltype eq 'quotahit_delmail' ? 1 : 0,
                      popup_quotahitdelfile   => $quotahit_deltype eq 'quotahit_delfile' ? 1 : 0,
                      popup_messagesent       => (defined param('sentsubject') && $prefs{mailsentwindowtime} > 0) ? 1 : 0,
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
                            join ('&', (
                                          'folder='      . ow::tool::escapeURL($folder),
                                          'keyword='     . ow::tool::escapeURL($keyword),
                                          'longpage='    . ow::tool::escapeURL($longpage),
                                          'msgdatetype=' . ow::tool::escapeURL($msgdatetype),
                                          'page='        . ow::tool::escapeURL($page),
                                          'searchtype='  . ow::tool::escapeURL($searchtype),
                                          'sessionid='   . ow::tool::escapeURL($thissession),
                                          'sort='        . ow::tool::escapeURL($sort),
                                       )
                                 )
             ], [$template->output]);
}

sub get_upcomingevents {
   # returns up to 5 upcoming events from multiple calendar sources
   my $reminderdays = shift;

   return [] unless $config{enable_calendar} && $reminderdays > 0;

   my $localtime = ow::datetime::time_gm2local(time(), $prefs{timeoffset}, $prefs{daylightsaving}, $prefs{timezone});
   my ($year, $month, $day, $hour, $min) = (ow::datetime::seconds2array($localtime))[5,4,3,2,1];
   my $hourminnow = sprintf("%02d%02d", $hour, $min);
   $month += 1;
   $year  += 1900;

   my %items   = ();
   my %indexes = ();

   my $calbookfile = dotpath('calendar.book');
   if (readcalbook($calbookfile, \%items, \%indexes, 0) < 0) {
      openwebmailerror(gettext('Cannot read calendar file:') . " $calbookfile ($!)");
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

   my %seen = (); # remember index numbers so an item will not be shown more than once, in case it is a regexp
   foreach my $daysfromnow (0..($reminderdays-1)) {
      my $wdaynum = 0;
      ($wdaynum, $year, $month, $day) = (ow::datetime::seconds2array($localtime+$daysfromnow*86400))[6,5,4,3];
      $month += 1;
      $year  += 1900;
      my $dow   = $ow::datetime::wday_en[$wdaynum]; # Sun, Mon, etc
      my $date  = sprintf("%04d%02d%02d", $year,$month,$day);
      my $date2 = sprintf("%04d,%02d,%02d,%s", $year,$month,$day,$dow);

      # gather all of the events for this daysfromnow
      my @indexlist = ();
      push(@indexlist, @{$indexes{$date}}) if exists $indexes{$date} && defined $indexes{$date};
      push(@indexlist, @{$indexes{'*'}})if exists $indexes{'*'} && defined $indexes{'*'};
      @indexlist = sort { ($items{$a}{starthourmin} || 1E9) <=> ($items{$b}{starthourmin} || 1E9) } @indexlist;

      foreach my $index (@indexlist) {
         next if exists $seen{$index} && $seen{$index} > 0;
         next if !$items{$index}{eventreminder};

         if (
              $date =~ m/$items{$index}{idate}/
              || $date2 =~ /$items{$index}{idate}/
              || ow::datetime::easter_match($year, $month, $day, $items{$index}{idate})
            ) {
            if (
                 $items{$index}{starthourmin} >= $hourminnow
                 || $items{$index}{starthourmin} == 0
                 || $daysfromnow > 0
               ) {
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
               $itemstring = mbsubstr($itemstring, 0, 20, $prefs{charset}) . ".." if length($itemstring) >= 21;
               $itemstring .= '*' if $index >= 1E6;

               my $itemdatetext = $prefs{dateformat} || "mm/dd/yyyy";
               my ($m, $d) = (sprintf("%02d",$month), sprintf("%02d",$day));
               $itemdatetext =~ s#yyyy#$year#;
               $itemdatetext =~ s#mm#$m#;
               $itemdatetext =~ s#dd#$d#;

               push(@{$upcomingevents}, {
                                           itemdaysfromnow        => $daysfromnow,
                                           itemstartendtime       => $itemstartendtime,
                                           itemstring             => $itemstring,
                                           itemdatetext           => $itemdatetext,
                                           "itemweekday_$wdaynum" => $wdaynum,
                                           itemyear               => $year,
                                           itemmonth              => $month,
                                           itemday                => $day,
                                        }
                   );

               last if scalar @{$upcomingevents} == 5;
            }
         }
      }
   }

   return($upcomingevents);
}

sub markasread {
   my @messageids = (defined param('movebutton') || defined param('copybutton')) ? param('message_ids') : param('message_id');
   return if scalar @messageids == 0;

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   foreach my $messageid (@messageids) {
      my @attr = get_message_attributes($messageid, $folderdb);
      next if scalar @attr == 0; # msg not found in db

      if ($attr[$_STATUS] !~ m/R/i) {
         ow::filelock::lock($folderfile, LOCK_EX) or
            openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile) . " ($!)");
         update_message_status($messageid, $attr[$_STATUS] . 'R', $folderdb, $folderfile);
         ow::filelock::lock($folderfile, LOCK_UN);
      }
   }
}

sub markasunread {
   my @messageids = (defined param('movebutton') || defined param('copybutton')) ? param('message_ids') : param('message_id');
   return if scalar @messageids == 0;

   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   foreach my $messageid (@messageids) {
      my @attr = get_message_attributes($messageid, $folderdb);
      next if scalar @attr == 0; # msg not found in db

      if ($attr[$_STATUS] =~ m/[RV]/i) {
         # clear flag R(read), V(verified by mailfilter)
         my $newstatus = $attr[$_STATUS];
         $newstatus =~ s/[RV]//ig;

         ow::filelock::lock($folderfile, LOCK_EX) or
            openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile) . " ($!)");
         update_message_status($messageid, $newstatus, $folderdb, $folderfile);
         ow::filelock::lock($folderfile, LOCK_UN);
      }
   }
}

sub movemessage {
   my ($r_messageids, $destination) = @_;

   openwebmailerror(gettext('Move aborted: source and destination folder are the same.')) if $destination eq $folder;

   my $op = 'move';
   if ($destination eq 'DELETE') {
      return if defined param('copybutton'); # copy to DELETE is meaningless, so return
      $op = 'delete';
   } else {
      $op = 'copy' if defined param('copybutton'); # copy button pressed
   }

   openwebmailerror(gettext('Quota limit exceeded. Please delete some messages or webdisk files to free disk space.'))
     if $quotalimit > 0 && $quotausage > $quotalimit && $op ne 'delete';

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

   openwebmailerror(gettext('File does not exist:') . ' ' . f2u($folderfile)) unless -f $folderfile;

   my $counted = 0;

   if ($folder ne $destination) {
      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile) . " ($!)");

      if ($destination eq 'DELETE') {
         $counted = operate_message_with_ids($op, $r_messageids, $folderfile, $folderdb);
      } else {
         if (!-f $dstfile) {
            if (!sysopen(F, $dstfile, O_WRONLY|O_APPEND|O_CREAT)) {
               ow::filelock::lock($folderfile, LOCK_UN);
               openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($dstfile) . " ($!)");
            }
            close(F);
         }

         if (!ow::filelock::lock($dstfile, LOCK_EX)) {
            ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");
            openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($dstfile) . " ($!)");
         }

         $counted = operate_message_with_ids($op, $r_messageids, $folderfile, $folderdb, $dstfile, $dstdb);
      }

      folder_zapmessages($folderfile, $folderdb) if $counted > 0;

      ow::filelock::lock($dstfile, LOCK_UN);
      ow::filelock::lock($folderfile, LOCK_UN);
   }

   # fork a child to learn the message in the background
   # so the resultant msglist can be returned as soon as possible
   if ($learntype ne 'none') {
      # below handler is not necessary, as we call zombie_cleaner at end of each request
      #local $SIG{CHLD}=\&ow::tool::zombie_cleaner;

      local $| = 1; # flush all output

      if (fork() == 0) { # child
         close(STDIN);  # close fd0
         close(STDOUT); # close fd1
         close(STDERR); # close fd2

         # perl automatically chooses the lowest available file
         # descriptor, so open some fake ones to occupy 0,1,2 to
         # avoid warnings
         sysopen(FDZERO, '/dev/null', O_RDONLY); # occupy fd0
         sysopen(FDONE, '/dev/null', O_WRONLY);  # occupy fd1
         sysopen(FDTWO, '/dev/null', O_WRONLY);  # occupy fd2

         local $SIG{__WARN__} = sub { writelog(@_); exit(1) };
         local $SIG{__DIE__}  = sub { writelog(@_); exit(1) };

         writelog("debug_fork :: $learntype process forked") if $config{debug_fork};

         ow::suid::drop_ruid_rgid(); # set ruid=euid to avoid fork in spamcheck.pl

         my ($totallearned, $totalexamed) = (0,0);
         my ($learnfile, $learndb) = get_folderpath_folderdb($user, $learnfolder);

         my $learnhandle = do { no warnings 'once'; local *FH };
         foreach my $messageid (@{$r_messageids}) {
            my $block   = '';
            my $learned = 0;
            my $examed  = 0;
            my $msgsize = lockget_message_block($messageid, $learnfile, $learndb, \$block);
            next if $msgsize <= 0;

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

         writelog("debug_fork :: $learntype process terminated") if $config{debug_fork};

         close(FDZERO);
         close(FDONE);
         close(FDTWO);

         openwebmail_exit(0);
      }
   }

   if ($counted > 0) {
      my $msg = '';

      if ($op eq 'move') {
         $msg = "move message - move $counted msgs from $folder to $destination - ids=" . join(", ", @{$r_messageids});
      } elsif ($op eq 'copy') {
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
   }

   return;
}

sub www_emptyfolder {
   my $folder = shift;
   my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

   ow::filelock::lock($folderfile, LOCK_EX) or
      openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile) . " ($!)");

   my $ret = empty_folder($folderfile, $folderdb);

   ow::filelock::lock($folderfile, LOCK_UN) or writelog("cannot unlock file $folderfile");

   if ($ret == -1) {
      openwebmailerror(gettext('Cannot write file:') . ' ' . f2u($folderfile) . " ($!)");
   } elsif ($ret == -2) {
      openwebmailerror(gettext('Cannot update db:') . ' ' . f2u($folderdb) . " ($!)");
   }

   writelog("emptyfolder - $folder");
   writehistory("emptyfolder - $folder");
}

sub www_pop3_fetch {
   my $pop3host = param('pop3host') || '';
   my $pop3port = param('pop3port') || '110';
   my $pop3user = param('pop3user') || '';
   my $pop3book = dotpath('pop3.book');

   return if $pop3host eq '' || $pop3user eq '' || !-f $pop3book;

   foreach (@{$config{pop3_disallowed_servers}}) {
      openwebmailerror(gettext('Disallowed POP3 server:') . " $pop3host") if $_ eq $pop3host;
   }

   my %accounts = ();
   openwebmailerror(gettext('Cannot read pop3 book:') . " $pop3book")
     if readpop3book($pop3book, \%accounts) < 0;

   # ignore the enable flag since this is triggered by user clicking
   my ($pop3ssl, $pop3passwd, $pop3del) = (split(/\@\@\@/, $accounts{"$pop3host:$pop3port\@\@\@$pop3user"}))[2,4,5];

   my ($ret, $errmsg) = pop3_fetch($pop3host,$pop3port,$pop3ssl, $pop3user,$pop3passwd,$pop3del);

   openwebmailerror("$errmsg :: $pop3user\@$pop3host:$pop3port") if $ret < 0;
}

sub pop3_fetch {
   my ($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del) = @_;

   my ($ret, $errmsg) = fetchmail($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del);

   if ($ret < 0) {
      writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
      writehistory("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
   }

   return ($ret, $errmsg);
}

sub authpop3_fetch {
   return 0 unless $config{authpop3_getmail};

   my $authpop3book = dotpath('authpop3.book');
   my %accounts = ();
   if (-f $authpop3book) {
      if (readpop3book($authpop3book, \%accounts) > 0) {
         my $login = $user;
         $login .= "\@$domain" if $config{auth_withdomain};

         my ($pop3ssl, $pop3passwd, $pop3del) = (split(/\@\@\@/, $accounts{"$config{authpop3_server}:$config{authpop3_port}\@\@\@$login"}))[2,4,5];

         # do not case enable flag since noreason to stop fetch from auth server
         return pop3_fetch($config{authpop3_server},$config{authpop3_port},$pop3ssl, $login,$pop3passwd,$pop3del);
      } else {
         writelog("pop3 error - could not open $authpop3book");
         writehistory("pop3 error - could not open $authpop3book");
      }
   }
   return 0;
}

sub www_pop3_fetches {
   return unless -f dotpath('pop3.book');

   if (update_pop3check()) {
      authpop3_fetch() if (
                            $config{auth_module} eq 'auth_pop3.pl'
                            || $config{auth_module} eq 'auth_ldap_vpopmail.pl'
                          );
   }

   pop3_fetches(10); # wait background fetching for no more 10 second
}

sub pop3_fetches {
   my $timeout = shift;

   my $pop3book = dotpath('pop3.book');

   my %accounts = ();

   return 0 unless -f $pop3book;

   openwebmailerror(gettext('Cannot read pop3 book:') . " $pop3book")
     if readpop3book($pop3book, \%accounts) < 0;

   # fork a child to do fetch pop3 mails and return immediately
   if (scalar keys %accounts > 0) {
      local $| = 1;                                                 # flush all output
      local $pop3_fetches_complete = 0;	                            # localize for reentry safe
      local $SIG{CHLD} = sub { wait; $pop3_fetches_complete = 1; }; # signaled when pop3 fetch completes

      if (fork() == 0) { # child
         close(STDIN);  # close fd0
         close(STDOUT); # close fd1
         close(STDERR); # close fd2

         # perl automatically chooses the lowest available file
         # descriptor, so open some fake ones to occupy 0,1,2 to
         # avoid warnings
         sysopen(FDZERO, '/dev/null', O_RDONLY); # occupy fd0
         sysopen(FDONE, '/dev/null', O_WRONLY);  # occupy fd1
         sysopen(FDTWO, '/dev/null', O_WRONLY);  # occupy fd2

         local $SIG{__WARN__} = sub { writelog(@_); exit(1) };
         local $SIG{__DIE__}  = sub { writelog(@_); exit(1) };

         writelog("debug_fork :: pop3_fetches process forked") if $config{debug_fork};

         ow::suid::drop_ruid_rgid(); # set ruid=euid can avoid fork in spamcheck.pl
         foreach (values %accounts) {
            my ($pop3host,$pop3port,$pop3ssl, $pop3user,$pop3passwd, $pop3del, $enable) = split(/\@\@\@/,$_);

            next unless $enable;

            my $disallowed = 0;

            foreach (@{$config{pop3_disallowed_servers}}) {
               if ($pop3host eq $_) {
                  $disallowed = 1;
                  last;
               }
            }

            next if $disallowed;

            my ($ret, $errmsg) = fetchmail($pop3host, $pop3port, $pop3ssl, $pop3user, $pop3passwd, $pop3del);

            if ($ret < 0) {
               writelog("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
               writehistory("pop3 error - $errmsg at $pop3user\@$pop3host:$pop3port");
            }
         }

         writelog("debug_fork :: fetch pop3s process terminated") if $config{debug_fork};

         close(FDZERO);
         close(FDONE);
         close(FDTWO);

         openwebmail_exit(0);
      }

      # wait for fetch to complete for $timeout seconds
      for (my $i = 0; $i < $timeout; $i++) {
         sleep 1;
         last if $pop3_fetches_complete;
      }
   }

   return 0;
}

sub update_pop3check {
   my $now = time();

   my $pop3checkfile = dotpath('pop3.check');

   my $ftime = (stat($pop3checkfile))[9];

   if (!defined $ftime || $ftime eq '') {
      # create pop3.check if it does not exist
      sysopen(F, $pop3checkfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $pop3checkfile ($!)");

      print F "pop3check timestamp file";

      close(F) or writelog("cannot close file $pop3checkfile ($!)");

      $ftime = (stat($pop3checkfile))[9];
   }

   if ($now - $ftime > $config{fetchpop3interval} * 60) {
      # -1 is trick for nfs
      utime($now - 1, $now - 1, ow::tool::untaint($pop3checkfile));

      return 1;
   } else {
      return 0;
   }
}

sub moveoldmsg2saved {
   my ($srcfile, $srcdb) = get_folderpath_folderdb($user, 'INBOX');
   my ($dstfile, $dstdb) = get_folderpath_folderdb($user, 'saved-messages');

   ow::filelock::lock($srcfile, LOCK_EX) or
      openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($srcfile) . " ($!)");

   ow::filelock::lock($dstfile, LOCK_EX) or
      openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($dstfile) . " ($!)");

   my $counted = move_oldmsg_from_folder($srcfile, $srcdb, $dstfile, $dstdb);

   ow::filelock::lock($dstfile, LOCK_UN) or writelog("cannot unlock file $dstfile");
   ow::filelock::lock($srcfile, LOCK_UN) or writelog("cannot unlock file $srcfile");

   if ($counted > 0){
      my $msg = "move message - move $counted old msgs from INBOX to saved-messages";
      writelog($msg);
      writehistory($msg);
   }
}

sub clean_trash_spamvirus {
   my $now = time();

   my $trashcheckfile = dotpath('trash.check');

   if (!-e $trashcheckfile) { # create if not exist
      sysopen(TRASHCHECK, $trashcheckfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . ' ' . f2u($trashcheckfile) . " ($!)");
      print TRASHCHECK "trashcheck timestamp file";
      close(TRASHCHECK);
   }

   my $ftime = (stat($trashcheckfile))[9] || $now;

   my %reserveddays = (
                        'mail-trash' => $prefs{trashreserveddays},
                        'spam-mail'  => $prefs{spamvirusreserveddays},
                        'virus-mail' => $prefs{spamvirusreserveddays},
                      );

   my @f   = ();
   my $msg = '';

   push(@f, 'virus-mail') if $config{has_virusfolder_by_default};
   push(@f, 'spam-mail') if $config{has_spamfolder_by_default};
   push(@f, 'mail-trash');

   foreach my $folder (@f) {
      next if $reserveddays{$folder} < 0 || $reserveddays{$folder} >= 999999;

      my ($folderfile, $folderdb) = get_folderpath_folderdb($user, $folder);

      ow::filelock::lock($folderfile, LOCK_EX) or
         openwebmailerror(gettext('Cannot lock file:') . ' ' . f2u($folderfile) . " ($!)");

      if (exists $reserveddays{$folder} && $reserveddays{$folder} == 0) {
         # empty folder
         my $ret = empty_folder($folderfile, $folderdb);
         if ($ret == 0) {
            $msg .= ', ' if defined $msg && $msg ne '';
            $msg .= "all messages deleted from $folder";
         }
      } elsif ($now - $ftime > 43200) { # do clean only if last clean has passed for more than 0.5 day (43200 sec)
         my $deleted = delete_message_by_age($reserveddays{$folder}, $folderdb, $folderfile);
         if ($deleted > 0) {
            $msg .= ', ' if defined $msg && $msg ne '';
            $msg .= "$deleted messages deleted from $folder";
         }
      }
      ow::filelock::lock($folderfile, LOCK_UN);
   }

   if (defined $msg && $msg ne '') {
      writelog("clean trash - $msg");
      writehistory("clean trash - $msg");
   }

   if ($now - $ftime > 43200) { # more than half day, update timestamp of checkfile
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
                                        cache             => 0,
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
