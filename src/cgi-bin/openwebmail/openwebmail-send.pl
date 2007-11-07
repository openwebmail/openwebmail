#!/usr/bin/suidperl -T
#
# openwebmail-send.pl - mail composing and sending program
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { local $1; $SCRIPT_DIR=$1 }
if ($SCRIPT_DIR eq '' && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { local $1; $SCRIPT_DIR=$1 }
}
if ($SCRIPT_DIR eq '') { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

foreach (qw(ENV BASH_ENV CDPATH IFS TERM)) {delete $ENV{$_}}; $ENV{PATH}='/bin:/usr/bin'; # secure ENV
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);
use MIME::Base64;
use MIME::QuotedPrint;
use Net::SMTP;

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "modules/mailparse.pl";
require "modules/htmltext.pl";
require "modules/htmlrender.pl";
require "modules/enriched.pl";
require "modules/tnef.pl";
require "modules/wget.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/getmessage.pl";
require "shares/lockget.pl";
require "shares/statbook.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $logindomain $loginuser);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($quotausage $quotalimit);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_wdbutton %lang_text %lang_err
            %lang_prioritylabels %lang_msgformatlabels); # defined in lang/xy
use vars qw(%charset_convlist);	# defined in iconv.pl
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_STATUS $_CHARSET $_REFERENCES);	# defined in maildb.pl

# local globals
use vars qw($folder $messageid $mymessageid);
use vars qw($sort $msgdatetype $page);
use vars qw($searchtype $keyword);
use vars qw($escapedfolder $escapedmessageid $escapedkeyword);

########## MAIN ##################################################
openwebmail_requestbegin();
userenv_init();

if (!$config{'enable_webmail'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$folder = ow::tool::unescapeURL(param('folder')) || 'INBOX';
$messageid = param('message_id')||'';		# the orig message to reply/forward
$mymessageid = param('mymessageid')||'';		# msg we are editing
$page = param('page') || 1;
$sort = param('sort') || $prefs{'sort'} || 'date_rev';
$msgdatetype = param('msgdatetype') || $prefs{'msgdatetype'};

$searchtype = param('searchtype') || 'subject';
$keyword = param('keyword') || '';

$escapedfolder = ow::tool::escapeURL($folder);
$escapedmessageid = ow::tool::escapeURL($messageid);
$escapedkeyword = ow::tool::escapeURL($keyword);

my $action = param('action')||'';
writelog("debug - request send begin, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ($action eq "replyreceipt") {
   replyreceipt();
} elsif ($action eq "composemessage") {
   composemessage();
} elsif ($action eq "sendmessage") {
   sendmessage();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request send end, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## REPLYRECEIPT ##########################################
sub replyreceipt {
   my $html='';
   my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
   my @attr;
   my %FDB;

   ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} ".f2u($folderdb));
   @attr=string2msgattr($FDB{$messageid});
   ow::dbm::close(\%FDB, $folderdb);

   if ($attr[$_SIZE]>0) {
      my $header;

      # get message header
      sysopen(FOLDER, $folderfile, O_RDONLY) or
          openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} ".f2u($folderfile)."! ($!)");
      seek (FOLDER, $attr[$_OFFSET], 0) or
          openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_seek'} ".f2u($folderfile)."! ($!)");
      $header="";
      while (<FOLDER>) {
         last if ($_ eq "\n" && $header=~/\n$/);
         $header.=$_;
      }
      close(FOLDER);

      # get notification-to
      if ($header=~/^Disposition-Notification-To:\s?(.*?)$/im ) {
         my $to=$1;
         my $from=$prefs{'email'};
         my $date=ow::datetime::dateserial2datefield(ow::datetime::gmtime2dateserial(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
         my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, dotpath('from.book'));
         foreach (keys %userfrom) {
            if ($header=~/$_/) {
               $from=$_; last;
            }
         }
         my $realname=$userfrom{$from};
         $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts
         $from =~ s/['"]/ /g;  # Get rid of shell escape attempts

         my @recipients=();
         foreach (ow::tool::str2list($to,0)) {
            my $addr=(ow::tool::email2nameaddr($_))[1];
            next if ($addr eq "" || $addr=~/\s/);
            push (@recipients, $addr);
         }

         $mymessageid=fakemessageid($from) if ($mymessageid eq '');

         my $smtp;
         my $timeout=120;
         $timeout = 30 if (scalar @{$config{'smtpserver'}} > 1); # cycle through available smtp servers faster
         $timeout += 60 if ($#recipients>=1);                    # more than 1 recipient

         # try to connect to one of the smtp servers available
         my $smtpserver;
         foreach $smtpserver (@{$config{'smtpserver'}}) {
            my $connectmsg = "send message - trying to connect to smtp server $smtpserver:$config{'smtpport'}";
            writelog($connectmsg); writehistory($connectmsg);

            $smtp=Net::SMTP->new($smtpserver,
                                 Port => $config{'smtpport'},
                                 Timeout => $timeout,
                                 Hello => ${$config{'domainnames'}}[0]);

            if ($smtp) {
               $connectmsg = "send message - connected to smtp server $smtpserver:$config{'smtpport'}";
               writelog($connectmsg); writehistory($connectmsg);
               last;
            } else {
               $connectmsg = "send message - error connecting to smtp server $smtpserver:$config{'smtpport'}";
               writelog($connectmsg); writehistory($connectmsg);
            }
         }

         unless ($smtp) {
            # we didn't connect to any smtp servers successfully
            openwebmailerror(__FILE__, __LINE__,
                             qq|$lang_err{'couldnt_open'} SMTP servers |.
                             join(", ", @{$config{'smtpserver'}}).
                             qq| at port $config{'smtpport'}!|);
         }

         # SMTP SASL authentication (PLAIN only)
         if ($config{'smtpauth'}) {
            my $auth = $smtp->supports("AUTH");
            $smtp->auth($config{'smtpauth_username'}, $config{'smtpauth_password'}) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'network_server_error'}!<br>($smtpserver - ".$smtp->message.")", "passthrough");
         }

         $smtp->mail($from);
         my @ok=$smtp->recipient(@recipients, { SkipBad => 1 });
         if ($#ok<0) {
            $smtp->close();
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'sendmail_error'}!");
         }

         $smtp->data();

         my $s;

         if ($realname ne '') {
            $s .= "From: ".ow::mime::encode_mimewords(qq|"$realname" <$from>|, ('Charset'=>$prefs{'charset'}))."\n";
         } else {
            $s .= "From: ".ow::mime::encode_mimewords(qq|$from|, ('Charset'=>$prefs{'charset'}))."\n";
         }
         $s .= "To: ".ow::mime::encode_mimewords($to, ('Charset'=>$prefs{'charset'}))."\n";
         $s .= "Reply-To: ".ow::mime::encode_mimewords($prefs{'replyto'}, ('Charset'=>$prefs{'charset'}))."\n" if ($prefs{'replyto'});

         # reply with english if sender has different charset than us
         my $is_samecharset=0;
         # replies in local language currently disabled, utf-8 is whole world
         # $is_samecharset=1 if ( $attr[$_CONTENT_TYPE]=~/charset="?\Q$prefs{'charset'}\E"?/i);

         if ($is_samecharset) {
            $s .= "Subject: ".ow::mime::encode_mimewords("$lang_text{'read'} - $attr[$_SUBJECT]",('Charset'=>$prefs{'charset'}))."\n";
         } else {
            $s .= "Subject: ".ow::mime::encode_mimewords("Read - $attr[$_SUBJECT]", ('Charset'=>'utf-8'))."\n";
         }
         $s .= "Date: $date\n".
               "Message-Id: $mymessageid\n".
               safexheaders($config{'xheaders'}).
               "MIME-Version: 1.0\n";
         if ($is_samecharset) {
            $s .= "Content-Type: text/plain; charset=$prefs{'charset'}\n\n".
                  "$lang_text{'yourmsg'}\n\n".
                  "  $lang_text{'to'}: $attr[$_TO]\n".
                  "  $lang_text{'subject'}: $attr[$_SUBJECT]\n".
                  "  $lang_text{'delivered'}: ".
                  ow::datetime::dateserial2str($attr[$_DATE],
                                   $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                   $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'}).
                  "\n\n".
                  "$lang_text{'wasreadon1'} ".
                  ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial(),
                                   $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                   $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'}).
                  " $lang_text{'wasreadon2'}\n\n";
         } else {
            $s .= "Content-Type: text/plain; charset=utf-8\n\n".
                  "Your message\n\n".
                  "  To: $attr[$_TO]\n".
                  "  Subject: $attr[$_SUBJECT]\n".
                  "  Delivered: ".
                  ow::datetime::dateserial2str($attr[$_DATE],
                                   $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                   $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'}).
                  "\n\n".
                  "was read on ".
                  ow::datetime::dateserial2str(ow::datetime::gmtime2dateserial(),
                                   $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                                   $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'}).
                  ".\n\n";
         }
         $s .= str2str($config{'mailfooter'}, "text")."\n" if ($config{'mailfooter'}=~/[^\s]/);

         if (!$smtp->datasend($s) || !$smtp->dataend()) {
            $smtp->close();
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'sendmail_error'}!");
         }
         $smtp->quit();
      }

      # close the window that is processing confirm-reading-receipt
      $html=qq|<script language="JavaScript">\n|.
            qq|<!--\n|.
            qq|window.close();\n|.
            qq|//-->\n|.
            qq|</script>\n|;
   } else {
      my $msgidstr = ow::htmltext::str2html($messageid);
      $html="What the heck? Message $msgidstr seems to be gone!";
   }
   httpprint([], [htmlheader(), $html, htmlfooter(1)]);
}
########## END REPLYRECEIPT ######################################

########## COMPOSEMESSAGE ########################################
# 9 composetype: reply, replyall, forward, editdraft,
#                forwardasorig (resent to another with exactly same msg),
#                forwardasatt (orig msg as an att),
#                continue(used after adding attachment),
#                sendto(newmail with dest user),
#                none(newmail)
use vars qw($_htmlarea_css_cache);
sub composemessage {
   my %message;
   my $attnumber;
   my $atterror;
   my $from ='';
   my $replyto = param('replyto') || '';
   my $subject = param('subject') || '';
   my $body = param('body') || '';
   my $inreplyto = param('inreplyto') || '';
   my $references = param('references') || '';
   my $priority = param('priority') || 'normal';	# normal/urgent/non-urgent
   my $statname = ow::tool::unescapeURL(param('statname')) || '';
   my $composetype = param('composetype')||'';

   # hashify to,cc,bcc to eliminate duplicates and strip off xowmuid tracker stuff after %@#
   my (%tohash, %cchash, %bcchash) = ();
   for (ow::tool::str2list(param('to').",".param('checkedto'))) { if ($_ ne '') { $_ =~ s/%@#(?:.*)$//; $tohash{$_} = 1 } };
   for (ow::tool::str2list(param('cc').",".param('checkedcc'))) { if ($_ ne '') { $_ =~ s/%@#(?:.*)$//; $cchash{$_} = 1 } };
   for (ow::tool::str2list(param('bcc').",".param('checkedbcc'))) { if ($_ ne '') { $_ =~ s/%@#(?:.*)$//; $bcchash{$_} = 1 } };
   my $to = join(", ", sort { lc($a) cmp lc($b) } keys %tohash);
   my $cc = join(", ", sort { lc($a) cmp lc($b) } keys %cchash);
   my $bcc = join(", ", sort { lc($a) cmp lc($b) } keys %bcchash);

   my @forwardids=();
   if ($composetype eq 'forwardids' || $composetype eq 'forwardids_delete') {
      # parameter passed with file from openwebmail-main.pl
      sysopen(FORWARDIDS, "$config{'ow_sessionsdir'}/$thissession-forwardids", O_RDONLY);
      while(<FORWARDIDS>) {
         chomp(); push(@forwardids, $_);
      }
      close(FORWARDIDS);
      unlink("$config{'ow_sessionsdir'}/$thissession-forwardids");
   }

   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, dotpath('from.book'));
   if (defined param('from')) {
      $from=param('from')||'';
   } elsif ($userfrom{$prefs{'email'}} ne "") {
      $from=qq|"$userfrom{$prefs{'email'}}" <$prefs{'email'}>|;
   } else {
      $from=qq|$prefs{'email'}|;
   }

   # msgformat is text, html or both
   my $msgformat = param('msgformat') || $prefs{'msgformat'} || 'text';
   my $newmsgformat = param('newmsgformat') || $msgformat;
   if (!htmlarea_compatible()) {
      $msgformat = $newmsgformat = 'text';
   }

   # composecharset is the charset choosed by user for current composing
   my $composecharset= $prefs{'charset'};
   if (ow::lang::is_charset_supported(param('composecharset')) || exists $charset_convlist{param('composecharset')}) {
      $composecharset=param('composecharset');
   }

   # convfrom is the charset choosed by user in last reading message
   my $convfrom=param('convfrom')||'';
   if ($convfrom =~/^none\.(.*)$/) {
      $composecharset=$1 if ow::lang::is_charset_supported($1);
   }

   my ($attfiles_totalsize, $r_attfiles);
   if ( param('deleteattfile') ne '' ) { # user click 'del' link
      my $deleteattfile=param('deleteattfile');

      $deleteattfile =~ s/\///g;  # just in case someone gets tricky ...
      $deleteattfile=ow::tool::untaint($deleteattfile);
      # only allow to delete attfiles belongs the $thissession
      if ($deleteattfile=~/^\Q$thissession\E/) {
         unlink ("$config{'ow_sessionsdir'}/$deleteattfile");
      }
      ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

   } elsif (defined param('addbutton') ||	# user press 'add' button
            param('webdisksel') ) { 		# file selected from webdisk
      ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

      no strict 'refs';	# for $attchment, which is fname and fhandle of the upload

      my $attachment = param('attachment') ||'';
      # the webdisksel value copied from webdisk is in fscharset and protected with escapeURL.
      # please see filldestname in openwebmail-webdisk.pl and templates/dirfilesel.template
      my $webdisksel = ow::tool::unescapeURL(param('webdisksel')) ||'';
      my ($attname, $attcontenttype);
      if ($webdisksel || $attachment) {
         if ($attachment) {
            if ($attachment=~m!^(https?|ftp)://!) {	# attachment is a url
               my $wgetbin=ow::tool::findbin('wget');
               if ($wgetbin ne '') {
                  $attname=$attachment;			# url
                  $attname=ow::tool::unescapeURL($attname); 	# unescape str in URL
                  my ($ret, $errmsg);
                  ($ret, $errmsg, $attcontenttype, $attachment)=ow::wget::get_handle($wgetbin, $attachment);
                  if ($ret==0) {
                     my $ext=ow::tool::contenttype2ext($attcontenttype);
                     $attname=~s/\?.*$//;				# clean cgi parm in url
                     $attname=~ s!/$!!; $attname =~ s|^.*/||;	# clear path in url
                     $attname.=".$ext" if ($attname!~/\.$ext$/ && $ext ne 'bin');
                  } else {
                     undef $attachment;		# silent if wget err
                  }
               } else {
                  undef $attachment;		# silent if wget no available
               }
            } else {
               # Convert :: back to the ' like it should be.
               $attname = $attachment;
               $attname =~ s/::/'/g;
               # Trim the path info from the filename
               if ($composecharset eq 'big5' || $composecharset eq 'gb2312') {
                  $attname = ow::tool::zh_dospath2fname($attname);	# dos path
               } else {
                  $attname =~ s|^.*\\||;		# dos path
               }
               $attname =~ s|^.*/||;	# unix path
               $attname =~ s|^.*:||;	# mac path and dos drive

               if (defined uploadInfo($attachment)) {
#                  my %info=%{uploadInfo($attachment)};
                  $attcontenttype = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
               } else {
                  $attcontenttype = 'application/octet-stream';
               }
            }

         } elsif ($webdisksel && $config{'enable_webdisk'}) {
            my $webdiskrootdir=ow::tool::untaint($homedir.absolute_vpath("/", $config{'webdisk_rootpath'}));
            my $vpath=absolute_vpath('/', $webdisksel);
            my $vpathstr=(iconv($prefs{'fscharset'}, $composecharset, $vpath))[0];
            my $err=verify_vpath($webdiskrootdir, $vpath);
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'access_denied'} ($vpathstr: $err)") if ($err);
            openwebmailerror(__FILE__, __LINE__, "$lang_text{'file'} $vpathstr $lang_err{'doesnt_exist'}") if (!-f "$webdiskrootdir/$vpath");

            $attachment=do { local *FH };
            sysopen($attachment, "$webdiskrootdir/$vpath", O_RDONLY) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $lang_text{'webdisk'} $vpathstr! ($!)");
            $attname=$vpath; $attname=~s|/$||; $attname=~s|^.*/||;
            $attname=(iconv($prefs{fscharset}, $composecharset, $attname))[0];	# conv to composehcarset
            $attcontenttype=ow::tool::ext2contenttype($vpath);
         }

         if ($attachment) {
            if ( ($config{'attlimit'}) &&
                 ( ($attfiles_totalsize + (-s $attachment)) > ($config{'attlimit'}*1024) ) ) {
               close($attachment);
               $atterror = "$lang_err{'att_overlimit'} $config{'attlimit'} $lang_sizes{'kb'}!";
            } else {
               my $attserial = time();
               sysopen(ATTFILE, "$config{'ow_sessionsdir'}/$thissession-att$attserial", O_WRONLY|O_TRUNC|O_CREAT);
               print ATTFILE qq|Content-Type: $attcontenttype;\n|.
                          qq|\tname="|.ow::mime::encode_mimewords($attname, ('Charset'=>$composecharset)).qq|"\n|.
                          qq|Content-Id: <att$attserial>\n|.
                          qq|Content-Disposition: attachment; filename="|.ow::mime::encode_mimewords($attname, ('Charset'=>$composecharset)).qq|"\n|.
                          qq|Content-Transfer-Encoding: base64\n\n|;
               my ($buff, $attsize);
               while (read($attachment, $buff, 400*57)) {
                  $buff=encode_base64($buff);
                  $attsize += length($buff);
                  print ATTFILE $buff;
               }
               close ATTFILE;
               close($attachment);	# close tmpfile created by CGI.pm

               push(@{$r_attfiles}, { 'content-id' => "att$attserial",
                                      name         => $attname,
                                      namecharset  => $composecharset,
                                      file         => "$thissession-att$attserial",
                                      size         => $attsize} );
               $attfiles_totalsize+=$attsize;
            }
         }
      }

   # usr press 'send' button but no receiver, keep editing
   } elsif (defined param('sendbutton') &&
            param('to') eq '' && param('cc') eq '' && param('bcc') eq '' ) {
      ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

   } elsif ($newmsgformat ne $msgformat) {	# chnage msg format between text & html
      ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

   } elsif (param('convto') ne "") {
      ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

   } else {	# this is new message, remove previous aged attachments
      deleteattachments();
   }

   if ($composetype eq "reply" || $composetype eq "replyall" ||
       $composetype eq "forward" || $composetype eq "forwardasorig" ||
       $composetype eq "editdraft" ) {
      if ($composetype eq "forward" || $composetype eq "forwardasorig" ||
          $composetype eq "editdraft") {
         %message = %{&getmessage($user, $folder, $messageid, "all")};
      } else {
         %message = %{&getmessage($user, $folder, $messageid, "")};
      }

      # make the $body(text version) $bodyhtml(html version) for new mesage
      # from original mesage for different contenttype

      # we try to reserve the bdy in its original format so no info would be lost
      # if user browser is compatible with htmlarea for html msg composing
      my $bodyformat='text';	# text or html

      # handle the messages generated if sendmail is set up to send MIME error reports
      if ($message{'content-type'} =~ /^multipart\/report/i) {
         foreach my $attnumber (0 .. $#{$message{attachment}}) {
            if (defined ${${$message{attachment}[$attnumber]}{r_content}}) {
               $body .= ${${$message{attachment}[$attnumber]}{r_content}};
               shift @{$message{attachment}};
            }
         }
      } elsif ($message{'content-type'} =~ /^multipart/i) {
         # If the first attachment is text,
         # assume it's the body of a message in multi-part format
         if ( defined %{$message{attachment}[0]} &&
              ${$message{attachment}[0]}{'content-type'} =~ /^text/i ) {
            if (${$message{attachment}[0]}{'content-transfer-encoding'} =~ /^quoted-printable/i) {
               $body = decode_qp(${${$message{attachment}[0]}{r_content}});
            } elsif (${$message{attachment}[0]}{'content-transfer-encoding'} =~ /^base64/i) {
               $body = decode_base64(${${$message{attachment}[0]}{r_content}});
            } elsif (${$message{attachment}[0]}{'content-transfer-encoding'} =~ /^x-uuencode/i) {
               $body = ow::mime::uudecode(${${$message{attachment}[0]}{r_content}});
            } else {
               $body = ${${$message{attachment}[0]}{r_content}};
            }
            if (${$message{attachment}[0]}{'content-type'} =~ /^text\/html/i) {
               $bodyformat='html';
            } elsif (${$message{attachment}[0]}{'content-type'} =~ /^text\/enriched/i) {
               $body= ow::enriched::enriched2html($body);
               $bodyformat='html';
            }

            # handle mail with both text and html version
            # rename html to other name so if user in text compose mode,
            # the modified/forwarded text won't be overridden by html again
            if ( defined %{$message{attachment}[1]} &&
                 ${$message{attachment}[1]}{boundary} eq ${$message{attachment}[0]}{boundary} ) {
               # rename html attachment in the same alternative group
               if ( (${$message{attachment}[0]}{subtype}=~/alternative/i &&
                     ${$message{attachment}[1]}{subtype}=~/alternative/i &&
                     ${$message{attachment}[1]}{'content-type'}=~/^text/i  &&
                     ${$message{attachment}[1]}{filename}=~/^Unknown\./ ) ||
               # rename next if this=unknown.txt and next=unknown.html
                    (${$message{attachment}[0]}{'content-type'}=~/^text\/(?:plain|enriched)/i &&
                     ${$message{attachment}[0]}{filename}=~/^Unknown\./       &&
                     ${$message{attachment}[1]}{'content-type'}=~/^text\/(?:html|enriched)/i  &&
                     ${$message{attachment}[1]}{filename}=~/^Unknown\./ ) ) {
                  if ($msgformat ne 'text' && $bodyformat eq 'text' ) {
                     if (${$message{attachment}[1]}{'content-transfer-encoding'} =~ /^quoted-printable/i) {
                        $body = decode_qp(${${$message{attachment}[1]}{r_content}});
                     } elsif (${$message{attachment}[1]}{'content-transfer-encoding'} =~ /^base64/i) {
                        $body = decode_base64(${${$message{attachment}[1]}{r_content}});
                     } elsif (${$message{attachment}[0]}{'content-transfer-encoding'} =~ /^x-uuencode/i) {
                        $body = ow::mime::uudecode(${${$message{attachment}[1]}{r_content}});
                     } else {
                        $body = ${${$message{attachment}[1]}{r_content}};
                     }
                     if (${$message{attachment}[1]}{'content-type'}=~/^text\/enriched/i) {
                        $body=ow::enriched::enriched2html($body);
                     }
                     $bodyformat='html';
                     # remove 1 attachment from the message's attachemnt list for html
                     shift @{$message{attachment}};
                  } else {
                     ${$message{attachment}[1]}{filename}=~s/^Unknown/Original/;
                     ${$message{attachment}[1]}{header}=~s!^Content-Type: \s*text/(?:html|enriched);!Content-Type: text/$1;\n   name="OriginalMsg.htm";!i;
                  }
               }
            }
            # remove 1 attachment from the message's attachemnt list for text
            shift @{$message{attachment}};
         } else {
            $body = '';
         }
      } else {
         $body = $message{'body'} || '';
         # handle mail programs that send the body encoded
         if ($message{'content-type'} =~ /^text/i) {
            if ($message{'content-transfer-encoding'} =~ /^quoted-printable/i) {
               $body= decode_qp($body);
            } elsif ($message{'content-transfer-encoding'} =~ /^base64/i) {
               $body= decode_base64($body);
            } elsif ($message{'content-transfer-encoding'} =~ /^x-uuencode/i) {
               $body= ow::mime::uudecode($body);
            }
         }
         if ($message{'content-type'} =~ /^text\/html/i) {
            $bodyformat='html';
         } elsif ($message{'content-type'} =~ /^text\/enriched/i) {
            $body= ow::enriched::enriched2html($body);
            $bodyformat='html';
         }
      }

      # carry attachments from old mesage to the new one
      if ($composetype eq "forward" ||  $composetype eq "forwardasorig" ||
          $composetype eq "editdraft") {
         if (defined ${$message{attachment}[0]}{header}) {
            my $attserial=time(); $attserial=ow::tool::untaint($attserial);
            foreach my $attnumber (0 .. $#{$message{attachment}}) {
               my $r_attachment=$message{attachment}[$attnumber];
               $attserial++;
               if (${$r_attachment}{header} ne "" &&
                   defined ${$r_attachment}{r_content}) {
                  my ($attheader, $r_content)=(${$r_attachment}{header}, ${$r_attachment}{r_content});

                  if (${$r_attachment}{'content-type'}=~/^application\/ms\-tnef/i) {
                     my ($arc_attheader, $arc_r_content)=tnefatt2archive($r_attachment, $convfrom, $composecharset);
                     ($attheader, $r_content)=($arc_attheader, $arc_r_content) if ($arc_attheader ne '');
                  }
                  sysopen(ATTFILE, "$config{'ow_sessionsdir'}/$thissession-att$attserial", O_WRONLY|O_TRUNC|O_CREAT) or
                     openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $config{'ow_sessionsdir'}/$thissession-att$attserial! ($!)");
                  print ATTFILE $attheader, "\n", ${$r_content};
                  close ATTFILE;
               }
            }
            ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();
         }
      }

      if ($bodyformat eq 'html') {
         $body = ow::htmlrender::html4nobase($body);
         if ($composetype ne "editdraft" && $composetype ne "forwardasorig") {
            $body = ow::htmlrender::html4disablejs($body) if ($prefs{'disablejs'});
            $body = ow::htmlrender::html4disableembcode($body) if ($prefs{'disableembcode'});
            $body = ow::htmlrender::html4disableemblink($body, $prefs{'disableemblink'}, "$config{'ow_htmlurl'}/images/backgrounds/Transparent.gif") if ($prefs{'disableemblink'} ne 'none');
         }
         $body = ow::htmlrender::html4attfiles($body, $r_attfiles, "$config{'ow_cgiurl'}/openwebmail-viewatt.pl", "action=viewattfile&amp;sessionid=$thissession");
         $body = ow::htmlrender::html2block($body);
      }

      if ($msgformat eq 'auto') {
         $msgformat=$bodyformat;
         $msgformat='both' if ($msgformat eq 'html');

         my $showhtmlastext=$prefs{'showhtmlastext'};
         $showhtmlastext=param('showhtmlastext') if (defined param('showhtmlastext'));
         $msgformat='text' if ($showhtmlastext);
      }

      if ($bodyformat eq 'text' && $msgformat ne 'text')  {
         $body=ow::htmltext::text2html($body);
      } elsif ($bodyformat ne 'text' && $msgformat eq 'text')  {
         $body=ow::htmltext::html2text($body);
      }

      my $fromemail=$prefs{'email'};
      foreach (keys %userfrom) {
         if ($composetype eq "editdraft") {
            if ($message{'from'}=~/$_/i) {
               $fromemail=$_; last;
            }
         } else { # reply/replyall/forward/forwardasatt/forwardasorig
            if ($message{'to'}=~/$_/i || $message{'cc'}=~/$_/i ) { # case-insensitive for UpPeRcAsE@ExAmPlE.cOm matching
               $fromemail=$_; last;
            }
         }
      }
      if ($userfrom{$fromemail} ne '') {
         $from=qq|"$userfrom{$fromemail}" <$fromemail>|;
      } else {
         $from=qq|$fromemail|;
      }


      if ($composetype eq "reply" || $composetype eq "replyall") {
         $subject = $message{'subject'} || '';
         $subject = "Re: " . $subject unless ($subject =~ /^re:/i);
         if (defined $message{'reply-to'} && $message{'reply-to'}=~/[^\s]/) {
            $to = $message{'reply-to'} || '';
         } else {
            $to = $message{'from'} || '';
         }

         if ($composetype eq "replyall") {
            my $toaddr=(ow::tool::email2nameaddr($to))[1];
            my @recv=();
            foreach my $email (ow::tool::str2list($message{'to'},0)) {
               my $addr=(ow::tool::email2nameaddr($email))[1];
               next if ($addr eq $fromemail || $addr eq $toaddr ||
                        $addr=~/^\s*$/ || $addr=~/undisclosed\-recipients:\s?;?/i );
               push(@recv, $email);
            }
            $to .= "," . join(',', @recv) if ($#recv>=0);

            @recv=();
            foreach my $email (ow::tool::str2list($message{'cc'},0)) {
               my $addr=(ow::tool::email2nameaddr($email))[1];
               next if ($addr eq $fromemail || $addr eq $toaddr ||
                        $addr=~/^\s*$/ || $addr=~/undisclosed\-recipients:\s?;?/i );
               push(@recv, $email);
            }
            $cc = join(',', @recv) if ($#recv>=0);
         }

         if ($msgformat eq 'text') {
            # reparagraph orig msg for better look in compose window
            $body=reparagraph($body, $prefs{'editcolumns'}-8) if ($prefs{'reparagraphorigmsg'});
            # remove odds space or blank lines from body
            $body =~ s/(?: *\r?\n){2,}/\n\n/g;
            $body =~ s/^\s+//; $body =~ s/\s+$//;
            $body =~ s/\n/\n\> /g; $body = "> ".$body if ($body =~ /[^\s]/);
         } else {
            # remove all reference to inline attachments
            # because we don't carry them from original message when replying
            $body=~s/<[^\<\>]*?(?:background|src)\s*=[^\<\>]*?cid:[^\<\>]*?>//sig;

            # replace <p> with <br> to strip blank lines
            $body =~ s!<(?:p|p [^\<\>]*?)>!<br>!gi; $body =~ s!</p>!!gi;

            # replace <div> with <br> to strip layer and add blank lines
            $body =~ s!<(?:div|div [^\<\>]*?)>!<br>!gi; $body =~ s!</div>!!gi;

            $body =~ s!<br ?/?>(?:\s*<br ?/?>)+!<br><br>!gis;
            $body =~ s!^(?:\s*<br ?/?>)*!!gi; $body =~ s!(?:<br ?/?>\s*)*$!!gi;
            $body =~ s!(<br ?/?>|<div>|<div [^\<\>]*?>)!$1&gt; !gis; $body = '&gt; '.$body;
         }

         if ($prefs{replywithorigmsg} eq 'at_beginning') {
            my $h="On $message{'date'}, ".(ow::tool::email2nameaddr($message{'from'}))[0]." wrote";
            ($h)=iconv('utf-8', $composecharset, $h);
            ($body)=iconv($convfrom, $composecharset, $body);
            if ($msgformat eq 'text') {
               $body = $h."\n".$body if ($body=~/[^\s]/);
            } else {
               $body = '<b>'.ow::htmltext::text2html($h).'</b><br>'.$body;
            }
         } elsif ($prefs{replywithorigmsg} eq 'at_end') {
            my $h="From: $message{'from'}\n".
                  "To: $message{'to'}\n";
            $h .= "Cc: $message{'cc'}\n" if ($message{'cc'} ne "");
            $h .= "Sent: $message{'date'}\n".
                  "Subject: $message{'subject'}\n";
            ($h)=iconv('utf-8', $composecharset, $h);
            ($body)=iconv($convfrom, $composecharset, $body);
            if ($msgformat eq 'text') {
               $body = "---------- Original Message -----------\n".
                       "$h\n$body\n".
                       "------- End of Original Message -------\n";
            } else {
               $body = "<b>---------- Original Message -----------</b><br>\n".
                       ow::htmltext::text2html($h)."<br>$body<br>".
                       "<b>------- End of Original Message -------</b><br>\n";
            }
         }
         ($subject, $to, $cc)=iconv('utf-8',$composecharset,$subject,$to,$cc);

         if (defined $prefs{'autocc'} && $prefs{'autocc'} ne '') {
            $cc .= ', ' if ($cc ne '');
            $cc .= (iconv($prefs{'charset'}, $composecharset, $prefs{'autocc'}))[0];
         }
         $replyto = (iconv($prefs{'charset'}, $composecharset, $prefs{'replyto'}))[0] if (defined $prefs{'replyto'});
         $inreplyto = $message{'message-id'};
         if ($message{'references'} =~ /\S/) {
            $references = $message{'references'}." ".$message{'message-id'};
         } elsif ($message{'in-reply-to'} =~ /\S/) {
            my $s=$message{'in-reply-to'}; $s=~s/^.*?(\<\S+\>).*$/$1/;
            $references = $s." ".$message{'message-id'};
         } else {
            $references = $message{'message-id'};
         }

         my $origbody=$body;

         my $statcontent;
         if ($config{'enable_stationery'} && $statname ne '') {
            my $statbookfile=dotpath('stationery.book');
            if (-f $statbookfile) {
               my %stationery;
               my ($ret, $errmsg)=read_stationerybook($statbookfile, \%stationery);
               $statcontent=(iconv($stationery{$statname}{charset}, $composecharset, $stationery{$statname}{content}))[0] if ($ret==0);
            }
         }

         my $n="\n"; $n="<br>" if ($msgformat ne 'text');
         if ($statcontent=~/[^\s]/) {
            $body = str2str($statcontent, $msgformat).$n;
         } else {
            $body = $n.$n;
         }
         $body.= str2str((iconv($prefs{'charset'}, $composecharset, $prefs{'signature'}))[0], $msgformat).$n if ($prefs{'signature'}=~/[^\s]/);

         if ($prefs{replywithorigmsg} eq 'at_beginning') {
            $body = $origbody.$n.$body;
         } elsif ($prefs{replywithorigmsg} eq 'at_end') {
            $body = $body.$n.$origbody;
         }

      } elsif ($composetype eq "forward") {
         $subject = $message{'subject'} || '';
         $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);

         my $h="From: $message{'from'}\n".
               "To: $message{'to'}\n";
         $h .= "Cc: $message{'cc'}\n" if ($message{'cc'} ne "");
         $h .= "Sent: $message{'date'}\n".
               "Subject: $message{'subject'}\n";
         ($h, $subject)=iconv('utf-8', $composecharset, $h, $subject);
         ($body)=iconv($convfrom, $composecharset, $body);

         if ($msgformat eq 'text') {
            # remove odds space or blank lines from body
            $body =~ s/( *\r?\n){2,}/\n\n/g; $body =~ s/^\s+//; $body =~ s/\s+$//;
            $body = "\n".
                    "---------- Forwarded Message -----------\n".
                    "$h\n$body\n".
                    "------- End of Forwarded Message -------\n";
         } else {
            $body =~ s/<br>(\s*<br>)+/<br><br>/gis;
            $body = "<br>\n".
                    "<b>---------- Forwarded Message -----------</b><br>\n".
                    ow::htmltext::text2html($h)."<br>$body<br>".
                    "<b>------- End of Forwarded Message -------</b><br>\n";
         }

         my $n="\n"; $n="<br>" if ($msgformat ne 'text');
         $body .= $n.$n;
         $body .= str2str((iconv($prefs{'charset'}, $composecharset, $prefs{'signature'}))[0], $msgformat).$n if ($prefs{'signature'}=~/[^\s]/);

         $cc = (iconv($prefs{'charset'}, $composecharset, $prefs{'autocc'}))[0] if (defined $prefs{'autocc'});
         $replyto = (iconv($prefs{'charset'}, $composecharset, $prefs{'replyto'}))[0] if (defined $prefs{'replyto'});
         $inreplyto = $message{'message-id'};
         if ($message{'references'} =~ /\S/) {
            $references = $message{'references'}." ".$message{'message-id'};
         } elsif ($message{'in-reply-to'} =~ /\S/) {
            my $s=$message{'in-reply-to'}; $s=~s/^.*?(\<\S+\>).*$/$1/;
            $references = $s." ".$message{'message-id'};
         } else {
            $references = $message{'message-id'};
         }

      } elsif ($composetype eq "forwardasorig") {
         $subject = $message{'subject'} || '';
         $replyto = $message{'from'};
         ($subject, $replyto)=iconv('utf-8',$composecharset,$subject,$replyto);
         ($body)=iconv($convfrom, $composecharset, $body);

         $references = $message{'references'};
         $priority = $message{'priority'} if (defined $message{'priority'});

         $cc = (iconv($prefs{'charset'}, $composecharset, $prefs{'autocc'}))[0] if (defined $prefs{'autocc'});

         # remove odds space or blank lines from body
         if ($msgformat eq 'text') {
            $body =~ s/( *\r?\n){2,}/\n\n/g; $body =~ s/^\s+//; $body =~ s/\s+$//;
         } else {
            $body =~ s/<br>(\s*<br>)+/<br><br>/gis;
         }

      } elsif ($composetype eq "editdraft") {
         $subject = $message{'subject'} || '';
         $to = $message{'to'} if (defined $message{'to'});
         $cc = $message{'cc'} if (defined $message{'cc'});
         $bcc = $message{'bcc'} if (defined $message{'bcc'});
         $replyto = $message{'reply-to'} if (defined $message{'reply-to'});
         ($subject, $to, $cc, $bcc, $replyto)=
            iconv('utf-8', $composecharset, $subject,$to,$cc,$bcc,$replyto);
         ($body)= iconv($convfrom, $composecharset, $body);

         $inreplyto = $message{'in-reply-to'};
         $references = $message{'references'};
         $priority = $message{'priority'} if (defined $message{'priority'});
         $replyto = (iconv($prefs{'charset'}, $composecharset, $prefs{'replyto'}))[0] if ($replyto eq '' && defined $prefs{'replyto'});

         # we prefer to use the messageid in a draft message if available
         $mymessageid = $messageid if ($messageid);
      }

   } elsif ($composetype eq 'forwardasatt') {
      $msgformat='text' if ($msgformat eq 'auto');

      my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} ".f2u($folderfile)."!");
      if (update_folderindex($folderfile, $folderdb)<0) {
         ow::filelock::lock($folderfile, LOCK_UN);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} ".f2u($folderdb));
      }

      my @attr=get_message_attributes($messageid, $folderdb);
      openwebmailerror(__FILE__, __LINE__, f2u($folderdb)." $messageid $lang_err{'doesnt_exist'}") if ($#attr<0);

      my $fromemail=$prefs{'email'};
      foreach (keys %userfrom) {
         if ($attr[$_TO]=~/$_/) {
            $fromemail=$_; last;
         }
      }
      if ($userfrom{$fromemail} ne '') {
         $from=qq|"$userfrom{$fromemail}" <$fromemail>|;
      } else {
         $from=qq|$fromemail|;
      }

      sysopen(FOLDER, $folderfile, O_RDONLY);
      my $attserial=time(); $attserial=ow::tool::untaint($attserial);
      sysopen(ATTFILE, "$config{'ow_sessionsdir'}/$thissession-att$attserial", O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $config{'ow_sessionsdir'}/$thissession-att$attserial! ($!)");
      my $attdesc=ow::mime::encode_mimewords($attr[$_SUBJECT], ('Charset'=>$composecharset));
      print ATTFILE qq|Content-Type: message/rfc822;\n|,
                    qq|Content-Transfer-Encoding: 8bit\n|,
                    qq|Content-Disposition: attachment; filename="Forward.msg"\n|,
                    qq|Content-Description: $attdesc\n\n|;

      # copy message to be forwarded
      my $left=$attr[$_SIZE];
      seek(FOLDER, $attr[$_OFFSET], 0);

      # do not copy 1st line if it is the 'From ' delimiter
      $_ = <FOLDER>; print ATTFILE $_ if (!/^From /); $left-=length($_);

      # copy other lines with the 'From ' delimiter escaped
      while ($left>0) {
         $_ = <FOLDER>; s/^From />From /;
         print ATTFILE $_; $left-=length($_);
      }

      close(ATTFILE);
      close(FOLDER);

      ow::filelock::lock($folderfile, LOCK_UN);

      ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

      $subject = $attr[$_SUBJECT];
      $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);
      ($subject)=iconv('utf-8', $composecharset, $subject);

      $inreplyto = $message{'message-id'};
      if ($message{'references'} =~ /\S/) {
         $references = $message{'references'}." ".$message{'message-id'};
      } elsif ($message{'in-reply-to'} =~ /\S/) {
         my $s=$message{'in-reply-to'}; $s=~s/^.*?(\<\S+\>).*$/$1/;
         $references = $s." ".$message{'message-id'};
      } else {
         $references = $message{'message-id'};
      }
      $cc = (iconv($prefs{'charset'}, $composecharset, $prefs{'autocc'}))[0] if (defined $prefs{'autocc'});
      $replyto = (iconv($prefs{'charset'}, $composecharset, $prefs{'replyto'}))[0] if (defined $prefs{'replyto'});

      my $n="\n"; $n="<br>" if ($msgformat ne 'text');
      $body = $n."# Message forwarded as attachment".$n.$n;
      $body .= str2str((iconv($prefs{'charset'}, $composecharset, $prefs{'signature'}))[0], $msgformat).$n if ($prefs{'signature'}=~/[^\s]/);

   } elsif ($composetype eq 'forwardids' || $composetype eq 'forwardids_delete') {
      $msgformat='text' if ($msgformat eq 'auto');

      my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $folder);
      ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} ".f2u($folderfile)."!");

      if (update_folderindex($folderfile, $folderdb)<0) {
         ow::filelock::lock($folderfile, LOCK_UN);
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} ".f2u($folderdb));
      }

      sysopen(FOLDER, $folderfile, O_RDONLY);
      my $attserial=time(); $attserial=ow::tool::untaint($attserial);
      for (my $i=0; $i<=$#forwardids; $i++) {
         $attserial++;
         my @attr=get_message_attributes($forwardids[$i], $folderdb);
         sysopen(ATTFILE, "$config{'ow_sessionsdir'}/$thissession-att$attserial", O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $config{'ow_sessionsdir'}/$thissession-att$attserial! ($!)");
         my $attdesc=ow::mime::encode_mimewords($attr[$_SUBJECT], ('Charset'=>$composecharset));
         print ATTFILE qq|Content-Type: message/rfc822;\n|,
                       qq|Content-Transfer-Encoding: 8bit\n|,
                       qq|Content-Disposition: attachment; filename="Forward$i.msg"\n|,
                       qq|Content-Description: $attdesc\n\n|;

         # copy message to be forwarded
         my $left=$attr[$_SIZE];
         seek(FOLDER, $attr[$_OFFSET], 0);

         # do not copy 1st line if it is the 'From ' delimiter
         $_ = <FOLDER>; print ATTFILE $_ if (!/^From /); $left-=length($_);

         # copy other lines with the 'From ' delimiter escaped
         while ($left>0) {
            $_ = <FOLDER>; s/^From />From /;
            print ATTFILE $_; $left-=length($_);
         }

         close(ATTFILE);
      }
      close(FOLDER);

      # delete the forwarded messages if required
      if ($composetype eq 'forwardids_delete') {
         my $deleted=(operate_message_with_ids('delete', \@forwardids, $folderfile, $folderdb))[0];
         folder_zapmessages($folderfile, $folderdb) if ($deleted>0);
      }
      ow::filelock::lock($folderfile, LOCK_UN);

      ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

      $subject = "Fw: ";
      $cc = (iconv($prefs{'charset'}, $composecharset, $prefs{'autocc'}))[0] if (defined $prefs{'autocc'});
      $replyto = (iconv($prefs{'charset'}, $composecharset, $prefs{'replyto'}))[0] if (defined $prefs{'replyto'});

      my $n="\n"; $n="<br>" if ($msgformat ne 'text');
      if ($#forwardids>0) {
         $body = $n."# Messages forwarded as attachment".$n.$n;
      } else {
         $body = $n."# Message forwarded as attachment".$n.$n;
      }
      $body .= str2str((iconv($prefs{'charset'}, $composecharset, $prefs{'signature'}))[0], $msgformat).$n if ($prefs{'signature'}=~/[^\s]/);

   } elsif ($composetype eq 'continue') {
      $msgformat='text'    if ($msgformat eq 'auto');
      $newmsgformat='text' if ($newmsgformat eq 'auto');

      my $convto=param('convto')||'';
      ($body, $subject, $from, $to, $cc, $bcc, $replyto)=
         iconv($composecharset, $convto, $body,$subject,$from,$to,$cc,$bcc,$replyto);

      if (ow::lang::is_charset_supported($convto) || exists $charset_convlist{$convto}) {
         $composecharset=$convto;
      }

      if ( $msgformat eq 'text' && $newmsgformat ne 'text') {
         # default font size to 2 for html msg crecation
         $body=qq|<font size=2>|.ow::htmltext::text2html($body).qq|</font>|;
      } elsif ($msgformat ne 'text' && $newmsgformat eq 'text' ) {
         $body=ow::htmltext::html2text($body);
      }
      $msgformat=$newmsgformat;

   } else { # sendto or newmail
      $msgformat='text' if ($msgformat eq 'auto');
      if (defined $prefs{'autocc'} && $prefs{'autocc'} ne '') {
         $cc .= ', ' if ($cc ne '');
         $cc .= (iconv($prefs{'charset'}, $composecharset, $prefs{'autocc'}))[0];
      }
      $replyto = (iconv($prefs{'charset'}, $composecharset, $prefs{'replyto'}))[0] if (defined $prefs{'replyto'});

      my $n="\n"; $n="<br>" if ($msgformat ne 'text');
      $body.=$n.$n.str2str((iconv($prefs{'charset'}, $composecharset, $prefs{'signature'}))[0], $msgformat).$n if ($prefs{'signature'}=~/[^\s]/);

   }

   # remove tail blank line and space
   $body=~s/\s+$/\n/s;

   if ($msgformat eq 'text') {
      # text area would eat leading \n, so we add it back here
      $body="\n".$body;
   } else {
      # insert \n for long lines to keep them short
      # so the width of html message composer can always fit within screen resolution
      $body =~ s!([^\n\r]{1,80})( |&nbsp;)!$1$2\n!ig;
      # default font size to 2 for html msg crecation
      $body=qq|<font size=2>$body\n</font>| if ($composetype ne 'continue');
   }

   my ($html, $temphtml, @tmp);

   if ($composecharset ne $prefs{'charset'}) {
      @tmp=($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'});
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=('en_US', $composecharset, 'en_US.UTF-8');
      loadlang($prefs{'locale'});
      charset($prefs{'charset'}) if ($CGI::VERSION>=2.58);	# setup charset of CGI module
   }
   $html = applystyle(readtemplate("composemessage.template"));
   if ($#tmp>=1) {
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=@tmp;
   }

   my $compose_caller=param('compose_caller')||'';
   my $urlparm="sessionid=$thissession&amp;folder=$escapedfolder&amp;page=$page&amp;sort=$sort&amp;msgdatetype=$msgdatetype&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype";
   my $folderstr=$lang_folders{$folder}||(iconv($prefs{'fscharset'}, $composecharset, $folder))[0];
   if ($compose_caller eq "read") {
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $folderstr",
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?$urlparm&amp;action=readmessage&amp;message_id=$escapedmessageid&amp;headers=$prefs{'headers'}&amp;attmode=simple"|);
   } elsif ($compose_caller eq "addrlistview") {
      # NOTE: ow::tool::escapeURL(ow::tool::unescapeURL($a)) may be not equal $a
      #       as unescape will do nothing if the string is already unescaped.
      # we call unescapeURL here for param because it may be protected by escapeURL to avoid charset problem caused by js in browser
      my $escapedabookfolder=ow::tool::escapeURL(ow::tool::unescapeURL(param('abookfolder')));
      my $abookpage = param('abookpage');
      my $abooksort = param('abooksort');
      my $escapedabookkeyword = ow::tool::escapeURL(ow::tool::unescapeURL(param('abookkeyword')));
      my $abooksearchtype = param('abooksearchtype');
      my $abookcollapse = param('abookcollapse');
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $lang_text{'addressbook'}",
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;$urlparm&amp;abookfolder=$escapedabookfolder&amp;abookpage=$abookpage&amp;abooksort=$abooksort&amp;abookkeyword=$escapedabookkeyword&amp;abooksearchtype=$abooksearchtype&amp;abookcollapse=$abookcollapse"|). qq|\n|;
   } else { # main
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $folderstr",
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;$urlparm"|). qq|\n|;
   }

   $temphtml .= qq|&nbsp;\n|;

   # this refresh button is actually the same as add button,
   # because we need to post the request to keep user input data in the submission
   $temphtml .= iconlink("refresh.gif", $lang_text{'refresh'}, qq|accesskey="R" href="javascript:document.composeform.addbutton.click();"|);

   $html =~ s/\@\@\@BACKTOFOLDER\@\@\@/$temphtml/;

   $temphtml = start_multipart_form(-name=>'composeform').
               ow::tool::hiddens(action=>'sendmessage',
                                 sessionid=>$thissession,
                                 composetype=>'continue',
                                 deleteattfile=>'',
                                 inreplyto=>$inreplyto,
                                 references=>$references,
                                 composecharset=>$composecharset,
                                 compose_caller=>$compose_caller,
                                 folder=>$escapedfolder,
                                 sort=>$sort,
                                 page=>$page,
                                 searchtype=>$searchtype,
                                 keyword=>$keyword,
                                 session_noupdate=>0);
   $temphtml .= ow::tool::hiddens(message_id=>param('message_id')) if (param('message_id'));
   $mymessageid=fakemessageid((ow::tool::email2nameaddr($from))[1]) if ($mymessageid eq '');
   $temphtml .= ow::tool::hiddens(mymessageid=>$mymessageid);
   my $show_phonekbd=param('show_phonekbd')||0;	# for big5 charset input
   $temphtml .= ow::tool::hiddens(show_phonekbd=>$show_phonekbd);
   $html =~ s/\@\@\@STARTCOMPOSEFORM\@\@\@/$temphtml/;

   my @fromlist=();
   foreach (sort_emails_by_domainnames($config{'domainnames'}, keys %userfrom)) {
      if ($userfrom{$_} ne '') {
         push(@fromlist, iconv($prefs{'charset'}, $composecharset, qq|"$userfrom{$_}" <$_>|));
      } else {
         push(@fromlist, qq|$_|);
      }
   }
   $temphtml = popup_menu(-name=>'from',
                          -values=>\@fromlist,
                          -default=>$from,
                          -accesskey=>'F',
                          -override=>'1');
   $html =~ s/\@\@\@FROMMENU\@\@\@/$temphtml/;

   my @prioritylist=("urgent", "normal", "non-urgent");
   $temphtml = popup_menu(-name=>'priority',
                          -values=>\@prioritylist,
                          -default=>$priority || 'normal',
                          -labels=>\%lang_prioritylabels,
                          -override=>'1');
   $html =~ s/\@\@\@PRIORITYMENU\@\@\@/$temphtml/;

   # charset conversion menu
   my %ctlabels=( 'none' => "$composecharset *" );
   my @ctlist=('none');
   my %allsets=();
   foreach ((map { $ow::lang::charactersets{$_}[1] } keys %ow::lang::charactersets), keys %charset_convlist) {
      $allsets{$_}=1 if (!defined $allsets{$_});
   }
   delete $allsets{$composecharset};

   if (defined $charset_convlist{$composecharset}) {
      foreach my $ct (sort @{$charset_convlist{$composecharset}}) {
         if (is_convertible($composecharset, $ct)) {
            $ctlabels{$ct}="$composecharset > $ct";
            push(@ctlist, $ct);
            delete $allsets{$ct};
         }
      }
   }
   push(@ctlist, sort keys %allsets);

   $temphtml = popup_menu(-name=>'convto',
                          -values=>\@ctlist,
                          -labels=>\%ctlabels,
                          -default=>'none',
                          -onChange=>'javascript:bodygethtml(); return(sessioncheck() && submit());',
                          -accesskey=>'I',
                          -override=>'1');
   $html =~ s/\@\@\@CONVTOMENU\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'to',
                         -default=>$to,
                         -size=>'66',
                         -accesskey=>'T',
                         -override=>'1');
   if ($config{'enable_addressbook'}) {
      $temphtml.=qq|\n |.iconlink("addrbook.s.gif", $lang_text{'addressbook'}, qq|href="javascript:GoAddressWindow()"|);
   }
   $html =~ s/\@\@\@TOFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'cc',
                         -default=>$cc,
                         -size=>'66',
                         -accesskey=>'C',
                         -override=>'1');
   $html =~ s/\@\@\@CCFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'bcc',
                         -default=>$bcc,
                         -size=>'66',
                         -override=>'1');
   $html =~ s/\@\@\@BCCFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'replyto',
                         -default=>$replyto,
                         -size=>'45',
                         -accesskey=>'R',
                         -override=>'1');
   $html =~ s/\@\@\@REPLYTOFIELD\@\@\@/$temphtml/;

   $temphtml = checkbox(-name=>'confirmreading',
                        -value=>'1',
                        -label=>'');
   $html =~ s/\@\@\@CONFIRMREADINGCHECKBOX\@\@\@/$temphtml/;

   # table of attachment list
   my $htmlarea_attlist_js;

   if ($#{$r_attfiles}>=0) {
      $temphtml = "<table cellspacing='0' cellpadding='0' width='70%'><tr valign='bottom'>\n";

      $temphtml .= "<td><table cellspacing='0' cellpadding='0'>\n";
      for (my $i=0; $i<=$#{$r_attfiles}; $i++) {
         my $blank="";
         if (${${$r_attfiles}[$i]}{name}=~/\.(?:txt|jpg|jpeg|gif|png|bmp)$/i) {
            $blank="target=_blank";
         }

         my $escapedattfile=ow::tool::escapeURL(${${$r_attfiles}[$i]}{file});
         my $escapedattname=ow::tool::escapeURL(${${$r_attfiles}[$i]}{name});
         my $attnamestr=(iconv(${${$r_attfiles}[$i]}{namecharset}, $composecharset, ${${$r_attfiles}[$i]}{name}))[0];

         my $attsize=${${$r_attfiles}[$i]}{size};
         if ($attsize > 1024) {
            $attsize=int($attsize/1024)."$lang_sizes{'kb'}";
         } else {
            $attsize= $attsize."$lang_sizes{'byte'}";
         }

         my $attlink=qq|$config{'ow_cgiurl'}/openwebmail-viewatt.pl/$escapedattname?|.
                     qq|sessionid=$thissession&amp;action=viewattfile&amp;attfile=$escapedattfile|;
         $temphtml .= qq|<tr valign=top>|.
                      qq|<td><a href="$attlink" $blank><em>$attnamestr</em></a></td>|.
                      qq|<td nowrap align='right'>&nbsp; $attsize &nbsp;</td>|.
                      qq|<td nowrap>|.
                      qq|<a href="javascript:DeleteAttFile('${${$r_attfiles}[$i]}{file}')">[$lang_text{'delete'}]</a>\n|;
         if (${${$r_attfiles}[$i]}{name}=~/\.(?:doc|dot)$/i) {
            $temphtml .= qq|<a href="$attlink&amp;wordpreview=1" title="MS Word $lang_wdbutton{'preview'}" target="_blank">[$lang_wdbutton{'preview'}]</a>|;
         }
         if ($config{'enable_webdisk'} && !$config{'webdisk_readonly'}) {
            $temphtml .= qq|<a href=#here title="$lang_text{'savefile_towd'}" |.
                         qq|onClick="window.open('$config{'ow_cgiurl'}/openwebmail-webdisk.pl?|.
                         qq|action=sel_saveattfile&amp;sessionid=$thissession&amp;attfile=$escapedattfile&amp;|.
                         qq|attnamecharset=${${$r_attfiles}[$i]}{namecharset}&amp;attname=$escapedattname|.
                         qq|', '_blank','width=500,height=330,scrollbars=yes,resizable=yes,location=no'); return false;">[$lang_text{'webdisk'}]</a>|;
         }
         $temphtml .= qq|</td></tr>\n|;

         if ($attlink !~ m!^https?://!) {
            if ($ENV{'HTTPS'}=~/on/i || $ENV{'SERVER_PORT'}==443) {
               $attlink="https://$ENV{'HTTP_HOST'}$attlink";
            } else {
               $attlink="http://$ENV{'HTTP_HOST'}$attlink";
            }
         }
         $htmlarea_attlist_js.=qq|,\n| if ($htmlarea_attlist_js);
         $htmlarea_attlist_js.=qq|"${${$r_attfiles}[$i]}{name}": "$attlink"|;
      }
      $temphtml .= "</table></td>\n";

      $temphtml .= "<td align='right' nowrap>\n";
      if ( $attfiles_totalsize ) {
         $temphtml .= "<em>" . int($attfiles_totalsize/1024) . $lang_sizes{'kb'};
         $temphtml .= " $lang_text{'of'} $config{'attlimit'} $lang_sizes{'kb'}" if ( $config{'attlimit'} );
         $temphtml .= "</em>";
      }
      $temphtml .= "</td>";

      $temphtml .= "</tr></table>\n";
   } else {
      $temphtml="";
   }

   $temphtml .= filefield(-name=>'attachment',
                         -default=>'',
                         -size=>'45',
                         -accesskey=>'A',
                         -override=>'1');
   $temphtml .= submit(-name=>'addbutton',
                       -OnClick=>'bodygethtml(); return sessioncheck();',
                       -value=>$lang_text{'add'});
   $temphtml .= "&nbsp;";
   if ($config{'enable_webdisk'}) {
      $temphtml .= ow::tool::hiddens(webdisksel=>'')."\n ".
                   iconlink("webdisk.s.gif", $lang_text{'webdisk'}, qq|href="#" onClick="bodygethtml(); window.open('$config{ow_cgiurl}/openwebmail-webdisk.pl?sessionid=$thissession&amp;action=sel_addattachment', '_addatt','width=500,height=330,scrollbars=yes,resizable=yes,location=no'); return false;"|);
   }
   $html =~ s/\@\@\@ATTACHMENTFIELD\@\@\@/$temphtml/;

   if ($config{'enable_backupsent'}) {
      $temphtml = textfield(-name=>'subject',
                            -default=>$subject,
                            -size=>'45',
                            -accesskey=>'S',
                            -override=>'1');
      $html =~ s/\@\@\@SUBJECTFIELD\@\@\@/$temphtml/;

      templateblock_enable($html, 'BACKUPSENT');
      my $backupsent=$prefs{'backupsentmsg'};
      if (defined param('backupsent')) {
         $backupsent=param('backupsent')||0;
      }
      $temphtml = checkbox(-name=>'backupsentmsg',
                           -value=>'1',
                           -checked=>$backupsent,
                           -label=>'');
      $html =~ s/\@\@\@BACKUPSENTMSGCHECKBOX\@\@\@/$temphtml/;
   } else {
      $temphtml = textfield(-name=>'subject',
                            -default=>$subject,
                            -size=>'66',
                            -accesskey=>'S',
                            -override=>'1');
      $html =~ s/\@\@\@SUBJECTFIELD\@\@\@/$temphtml/;

      templateblock_disable($html, 'BACKUPSENT');
   }

   $temphtml = qq|<table width="100%" cellspacing="1" cellpadding="0" border="0">|;

   if ($show_phonekbd) {	# for big5 input
      $temphtml.=qq|<tr><td colspan="3"><a href="javascript:document.composeform.show_phonekbd.value=0; bodygethtml(); document.composeform.submit();">\n|.
                 qq|<IMG SRC="$config{'ow_htmlurl'}/images/phonekbd.gif" border="0" align="absmiddle" alt="ÁôÂÃ"></a></td></tr>\n|;
   }

   $temphtml.=qq|<tr valign=top><td width="2"></td><td>\n|;
   if ($msgformat eq 'text') {
      $temphtml .= textarea(-name=>'body',
                            -id=>'body',
                            -default=>$body,
                            -rows=>$prefs{'editrows'}||'20',
                            -columns=>$prefs{'editcolumns'}||'78',
                            -wrap=>'hard',	# incompatible with htmlarea
                            -accesskey=>'M',	# msg area
                            -override=>'1');
   } else {
      $temphtml .= textarea(-name=>'body',
                            -id=>'body',
                            -default=>$body,
                            -rows=>$prefs{'editrows'}||'20',
                            -columns=>$prefs{'editcolumns'}||'78',
                            -style=>'width:100%',
                            -accesskey=>'M',	# msg area
                            -override=>'1');
   }
   $temphtml .= qq|</td><td width="2"></td></tr></table>\n|;
   $html =~ s/\@\@\@BODYAREA\@\@\@/$temphtml/;


   # 4 buttons: send, savedraft, spellcheck, cancel, 1 menu: msgformat

   $temphtml=qq|<table cellspacing="2" cellpadding="2" border="0"><tr>|;

   $temphtml.=qq|<td align="center">|.
              submit(-name=>'sendbutton',
                     -value=>$lang_text{'send'},
                     -onClick=>'bodygethtml(); return (sessioncheck() && sendcheck());',
                     -accesskey=>'G',	# send, outGoing
                     -override=>'1').
              qq|</td>\n|;

   if ($config{'enable_savedraft'}) {
      $temphtml.=qq|<td align="center">|.
                 submit(-name=>'savedraftbutton',
                        -value=>$lang_text{'savedraft'},
                        -onClick=>'bodygethtml(); return sessioncheck();',
                        -accesskey=>'W',	# savedraft, Write
                        -override=>'1').
                 qq|</td>\n|;
   }

   if ($config{'enable_spellcheck'}) {
      my $chkname=(split(/\s/, $config{'spellcheck'}))[0]; $chkname=~s|^.*/||;
      $temphtml.=qq|<td nowrap align="center">|.
                 qq|<!--spellcheckstart-->\n|.
                 qq|<table cellpadding="0" cellspacing="0"><tr><td>|.
                 popup_menu(-name=>'dictionary2',
                            -values=>$config{'spellcheck_dictionaries'},
                            -default=>$prefs{'dictionary'},
                            -onChange=>"JavaScript:document.spellcheckform.dictionary.value=this.value;",
                            -override=>'1').
                 qq|</td><td>|.
                 button(-name=>'spellcheckbutton',
                        -value=> $lang_text{'spellcheck'},
                        -title=> $chkname,
                        -onClick=>'owmspellcheck(); return (sessioncheck() && document.spellcheckform.submit());',
                        -override=>'1').
                 qq|</td></tr></table>|.
                 qq|<!--spellcheckend-->\n|.
                 qq|</td>\n|;
   }

   $temphtml.=qq|<td align="center">\n|.
              qq|<!--newmsgformatstart-->\n|.
              qq|<table cellspacing="1" cellpadding="1" border="0"><tr>|.
              qq|<td nowrap align="right">&nbsp;$lang_text{'msgformat'}</td><td>|;
   if (htmlarea_compatible()) {
      $temphtml.=popup_menu(-name=>'newmsgformat',
                            -values=>['text', 'html', 'both'],
                            -default=>$msgformat,
                            -labels=>\%lang_msgformatlabels,
                            -onChange => "return (sessioncheck() && msgfmtchangeconfirm());",
                            -override=>'1');
   } else {
      $temphtml.=popup_menu(-name=>'newmsgformat',
                            -values=>['text'],
                            -labels=>\%lang_msgformatlabels,
                            -onClick => "msgfmthelp();",
                            -override=>'1');
   }
   $temphtml.=ow::tool::hiddens(msgformat=>$msgformat).
              qq|</td></tr></table>\n|.
              qq|<!--newmsgformatend-->\n|.
              qq|</td>\n|;

   $temphtml.=qq|<td align="center">|.
              button(-name=>'cancelbutton',
                      -value=> $lang_text{'cancel'},
                      -onClick=>'document.cancelform.submit();',
                      -override=>'1').
              qq|</td>\n|;

   $temphtml.=qq|<td>|.
              qq|<!--kbdiconstart-->\n|;
   if ($composecharset eq 'big5' && $show_phonekbd==0) {	# for big5 input
      $temphtml.=qq|<a href="javascript:document.composeform.show_phonekbd.value=1; bodygethtml(); document.composeform.submit();">\n|.
                 qq|<IMG SRC="$config{'ow_htmlurl'}/images/kbd.gif" border="0" align="absmiddle" alt="Åã¥Üª`­µÁä½L"></a>\n|;
   }
   $temphtml.=qq|<!--kbdiconend-->\n|.
              qq|</td>\n|;

   $temphtml.=qq|</tr></table>\n|;

   if ($prefs{'sendbuttonposition'} eq 'after') {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@//;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$temphtml/;
   } elsif ($prefs{'sendbuttonposition'} eq 'both') {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@/$temphtml/;
      $temphtml =~ s|<!--spellcheckstart-->|<!--|;
      $temphtml =~ s|<!--spellcheckend-->|-->|;
      $temphtml =~ s|<!--newmsgformatstart-->|<!--|;
      $temphtml =~ s|<!--newmsgformatend-->|-->|;
      $temphtml =~ s|<!--kbdiconstart-->|<!--|;
      $temphtml =~ s|<!--kbdiconend-->|-->|;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$temphtml/;
   } else {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@/$temphtml/;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@//;
   }

   if ($config{'enable_spellcheck'}) {
      # spellcheck form
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-spell.pl",
                             -name=>'spellcheckform',
                             -target=>'_spellcheck').
                  ow::tool::hiddens(sessionid=>$thissession,
                                    htmlmode=>($msgformat ne 'text'),
                                    form=>'',
                                    field=>'',
                                    string=>'',
                                    dictionary=>$prefs{'dictionary'});
      $html =~ s/\@\@\@STARTSPELLCHECKFORM\@\@\@/$temphtml/;
   } else {
      $html =~ s/\@\@\@STARTSPELLCHECKFORM\@\@\@.*?\@\@\@ENDFORM\@\@\@//s;
   }

   # cancel form
   if (param('message_id')) {
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl",
                             -name=>'cancelform').
                  ow::tool::hiddens(action=>'readmessage',
                                    message_id=>param('message_id')||'',
                                    headers=>$prefs{'headers'} || 'simple');
   } else {
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                             -name=>'cancelform').
                  ow::tool::hiddens(action=>'listmessages');
   }
   $temphtml .= ow::tool::hiddens(sessionid=>$thissession,
                                  folder=>$escapedfolder,
                                  sort=>$sort,
                                  page=>$page,
                                  searchtype=>$searchtype,
                                  keyword=>$keyword);
   $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   my $abook_width = $prefs{'abook_width'};
   $abook_width = 'screen.availWidth' if ($abook_width eq 'max');
   $html =~ s/\@\@\@ABOOKWIDTH\@\@\@/$abook_width/;

   my $abook_height = $prefs{'abook_height'};
   $abook_height = 'screen.availHeight' if ($abook_height eq 'max');
   $html =~ s/\@\@\@ABOOKHEIGHT\@\@\@/$abook_height/;

   my $abook_searchtype = $prefs{'abook_defaultfilter'}?ow::tool::escapeURL($prefs{'abook_defaultsearchtype'}):'';
   $html =~ s/\@\@\@ABOOKSEARCHTYPE\@\@\@/$abook_searchtype/;

   my $abook_keyword = $prefs{'abook_defaultfilter'}?ow::tool::escapeURL($prefs{'abook_defaultkeyword'}):'';
   $html =~ s/\@\@\@ABOOKKEYWORD\@\@\@/$abook_keyword/;

   # load css and js for html editor
   if ($msgformat ne 'text') {
      if ($_htmlarea_css_cache eq '') {
         sysopen(F, "$config{'ow_htmldir'}/javascript/htmlarea.openwebmail/htmlarea.css", O_RDONLY) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_htmldir'}/javascript/htmlarea.openwebmail/htmlarea.css! ($!)");
         local $/; undef $/; $_htmlarea_css_cache=<F>; # read whole file in once
         close(F);
      }

      my $css = $_htmlarea_css_cache;
      $css =~ s/\@\@\@BGCOLOR\@\@\@/$style{'window_light'}/g;
      $css =~ s/"//g;

      my $htmlarealocale = $prefs{'locale'};
      $htmlarealocale='en_US.UTF-8' if ($composecharset ne $prefs{'charset'});

      my $direction="ltr";
      $direction="rtl" if ($composecharset eq $prefs{'charset'} && $ow::lang::RTL{$prefs{'locale'}});

      $html= qq|<script language="JavaScript" src="$config{'ow_htmlurl'}/javascript/htmlarea.openwebmail/htmlarea.js"></script>\n|.
             qq|<script language="JavaScript" src="$config{'ow_htmlurl'}/javascript/htmlarea.openwebmail/dialog.js"></script>\n|.
             qq|<script language="JavaScript" src="$config{'ow_htmlurl'}/javascript/htmlarea.openwebmail/popups/$htmlarealocale/htmlarea-lang.js"></script>\n|.
             $html.
             qq|<style type="text/css">\n$css\n</style>\n|.
             qq|<script language="JavaScript">\n<!--\n|.
             qq|   var editor=new HTMLArea("body");\n|.
             qq|   editor.config.editorURL = "$config{'ow_htmlurl'}/javascript/htmlarea.openwebmail/";\n|.
             qq|   editor.config.imgURL = "images/";\n|.
             qq|   editor.config.popupURL = "popups/$htmlarealocale/";\n|.
             qq|   editor.config.bodyDirection = "$direction";\n|.
             qq|   editor.config.attlist = {\n$htmlarea_attlist_js};\n|.
             qq|   editor.config.attlist = {\n$htmlarea_attlist_js};\n|.
             qq|   editor.generate();\n|.
             qq|//-->\n</script>\n|;
   }

   @tmp=();
   if ($composecharset ne $prefs{'charset'}) {
      @tmp=($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'});
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=('en_US', $composecharset, 'en_US.UTF-8');
   }
   if ($atterror) { 
      $html.= readtemplate('showmsg.js').
              qq|<script language="JavaScript">\n<!--\n|.
              qq|showmsg('$prefs{charset}', '$lang_text{attachment}', '$atterror', '$lang_text{"close"}', '_attlimit', 300, 100, 5);\n|.
              qq|//-->\n</script>\n|;
   }
   my $session_noupdate=param('session_noupdate')||'';
   if (defined param('savedraftbutton') && !$session_noupdate) {
      # savedraft from user clicking, show show some msg for notifitcaiton
      my $msg=qq|<font size="-1">$lang_text{'draftsaved'}</font>|;
      $msg=~s/\@\@\@SUBJECT\@\@\@/$subject/;
      $html.= readtemplate('showmsg.js').
              qq|<script language="JavaScript">\n<!--\n|.
              qq|showmsg('$prefs{charset}', '$lang_text{savedraft}', '$msg', '$lang_text{"close"}', '_savedraft', 300, 100, 5);\n|.
              qq|//-->\n</script>\n|;
   }
   if (defined param('savedraftbutton') && $session_noupdate) {
      # this is auto savedraft triggered by timeoutwarning,
      # timeoutwarning js code is not required any more
      httpprint([], [htmlheader(), $html, htmlfooter(2)]);
   } else {
      # load timeoutchk.js and plugin jscode
      # which will be triggered when timeoutwarning shows up.
      my $jscode=qq|document.composeform.session_noupdate.value=1;|.
                 qq|document.composeform.savedraftbutton.click();|;
      httpprint([], [htmlheader(), $html, htmlfooter(2, $jscode)]);
   }
   if ($#tmp>=1) {
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=@tmp;
   }
   return;
}
########## END COMPOSEMESSAGE ####################################

########## SENDMESSAGE ###########################################
sub sendmessage {
   no strict 'refs';	# for $attchment, which is fname and fhandle of the upload
   # goto composemessage if !savedraft && !send
   if ( !defined param('savedraftbutton') &&
        !(defined param('sendbutton') && (param('to')||param('cc')||param('bcc')))  ) {
      return(composemessage());
   }

   my %userfrom=get_userfrom($logindomain, $loginuser, $user, $userrealname, dotpath('from.book'));
   my ($realname, $from);
   if (param('from')) {
      # use _email2nameaddr since it may return null name
      ($realname, $from)=ow::tool::_email2nameaddr(param('from'));
   } else {
      ($realname, $from)=($userfrom{$prefs{'email'}}, $prefs{'email'});
   }
   $from =~ s/['"]/ /g;  # Get rid of shell escape attempts
   $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts

   my $dateserial=ow::datetime::gmtime2dateserial();
   my $date=ow::datetime::dateserial2datefield($dateserial, $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});

   my $to = param('to')||'';
   my $cc = param('cc')||'';
   my $bcc = param('bcc')||'';
   my $replyto = param('replyto')||'';
   my $subject = param('subject') || 'N/A';
   my $inreplyto = param('inreplyto')||'';
   my $references = param('references')||'';
   my $composecharset = param('composecharset') || $prefs{'charset'};
   my $priority = param('priority')||'';
   my $confirmreading = param('confirmreading')||'';
   my $msgformat = param('msgformat')||'';
   my $body = param('body')||'';

   $mymessageid= fakemessageid($from) if ($mymessageid eq '');

   my ($attfiles_totalsize, $r_attfiles)=getattfilesinfo();

   $body =~ s/\r//g;		# strip ^M characters from message. How annoying!
   if ($msgformat ne 'text') {
      # replace links to attfiles with their cid
      $body = ow::htmlrender::html4attfiles_link2cid($body, $r_attfiles, "$config{'ow_cgiurl'}/openwebmail-viewatt.pl");
      # replace url#anchor with #anchor (to remove url added by htmlarea)
      $body =~ s!https?://$ENV{'HTTP_HOST'}$config{'ow_cgiurl'}/openwebmail-send.pl.*?action=composemessage.*?#!#!gs;
   }

   my $attachment = param('attachment');
   my $attheader;
   if ( $attachment ) {
      if ( ($config{'attlimit'}) && ( ( $attfiles_totalsize + (-s $attachment) ) > ($config{'attlimit'} * 1024) ) ) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'att_overlimit'} $config{'attlimit'} $lang_sizes{'kb'}!");
      }
      my $attcontenttype;
      if (defined uploadInfo($attachment)) {
         $attcontenttype = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
      } else {
         $attcontenttype = 'application/octet-stream';
      }
      my $attname = $attachment;
      # Convert :: back to the ' like it should be.
      $attname =~ s/::/'/g;
      # Trim the path info from the filename
      if ($composecharset eq 'big5' || $composecharset eq 'gb2312') {
         $attname = ow::tool::zh_dospath2fname($attname);	# dos path
      } else {
         $attname =~ s|^.*\\||;		# dos path
      }
      $attname =~ s|^.*/||;	# unix path
      $attname =~ s|^.*:||;	# mac path and dos drive

      $attheader = qq|Content-Type: $attcontenttype;\n|.
                   qq|\tname="|.ow::mime::encode_mimewords($attname, ('Charset'=>$composecharset)).qq|"\n|.
                   qq|Content-Disposition: attachment; filename="|.ow::mime::encode_mimewords($attname, ('Charset'=>$composecharset)).qq|"\n|.
                   qq|Content-Transfer-Encoding: base64\n|;
   }

   # convert message to prefs{'sendcharset'}
   if ($prefs{'sendcharset'} ne 'sameascomposing') {
      ($realname,$replyto,$to,$cc,$subject,$body)=
         iconv($composecharset, $prefs{'sendcharset'}, $realname,$replyto,$to,$cc,$subject,$body);
      $composecharset=$prefs{'sendcharset'};
   }

   # form html body to a complete html;
   if ($msgformat ne 'text') {
      $body=qq|<HTML>\n<HEAD>\n|.
            qq|<META content="text/html; charset=$composecharset" http-equiv=Content-Type>\n|.
            qq|<META content="OPENWEBMAIL" name=GENERATOR>\n|.
            qq|</HEAD>\n<BODY bgColor=#ffffff>\n|.
            $body.
            qq|\n</BODY>\n</HTML>\n|;
   }

   my $do_send=1;
   my $senderrstr="";
   my $senderr=0;

   my $do_save=1;
   my $saveerrstr="";
   my $saveerr=0;

   my $smtp;
   my ($smtperrfh, $smtperrfile)=ow::tool::mktmpfile('smtp.err');

   # redirect stderr to filehandle $smtperrfh
   open(SAVEERR,">&STDERR"); open(STDERR,">&=".fileno($smtperrfh)); close($smtperrfh);
   select(STDERR); local $| = 1; select(STDOUT);

   my ($savefolder, $savefile, $savedb);
   my $messagestart=0;
   my $messagesize=0;
   my $messageheader='';
   my $folderhandle=do { local *FH };

   if (defined param('savedraftbutton')) { # save msg to draft folder
      $savefolder = 'saved-drafts';
      $do_send=0;
      $do_save=0 if ($quotalimit>0 && $quotausage>=$quotalimit ||
                     !$config{'enable_savedraft'});
   } else {					     # save msg to sent folder && send
      $savefolder = $folder;
		$savefolder = 'sent-mail' if (!$prefs{'backupsentoncurrfolder'} || ($folder eq '') || ($folder =~ /INBOX|saved-drafts/));
      $do_save=0 if (($quotalimit>0 && $quotausage>=$quotalimit) ||
                     param('backupsentmsg')==0 ||
                     !$config{'enable_backupsent'});
   }

   if ($do_send) {
      my @recipients=();

      foreach my $recv ($to, $cc, $bcc) {
         next if ($recv eq "");
         foreach (ow::tool::str2list($recv,0)) {
            my $addr=(ow::tool::email2nameaddr($_))[1];
            next if ($addr eq "" || $addr=~/\s/);
            push (@recipients, $addr);
         }
      }
      foreach my $email (@recipients) {	# validate receiver email
         matchlist_fromtail('allowed_receiverdomain', $email) or
            openwebmailerror(__FILE__, __LINE__, $lang_err{'disallowed_receiverdomain'}." ( $email )");
      }

      # redirect stderr to smtperrfile

      my $timeout=120;
      $timeout = 30 if (scalar @{$config{'smtpserver'}} > 1); # cycle through available smtp servers faster
      $timeout += 60 if ($#recipients>=1);                    # more than 1 recipient

      # try to connect to one of the smtp servers available
      my $smtpserver;
      foreach $smtpserver (@{$config{'smtpserver'}}) {
         my $connectmsg = "send message - trying to connect to smtp server $smtpserver:$config{'smtpport'}";
         writelog($connectmsg); writehistory($connectmsg);

         $smtp=Net::SMTP->new($smtpserver,
                              Port => $config{'smtpport'},
                              Timeout => $timeout,
                              Hello => ${$config{'domainnames'}}[0],
                              Debug=>1);

         if ($smtp) {
            $connectmsg = "send message - connected to smtp server $smtpserver:$config{'smtpport'}";
            writelog($connectmsg); writehistory($connectmsg);
            last;
         } else {
            $connectmsg = "send message - error connecting to smtp server $smtpserver:$config{'smtpport'}";
            writelog($connectmsg); writehistory($connectmsg);
         }
      }

      unless ($smtp) {
         # we didn't connect to any smtp servers successfully
         $senderr++;
         $senderrstr = qq|$lang_err{'couldnt_open'} any SMTP servers |.
                       join(", ", @{$config{'smtpserver'}}).
                       qq| at port $config{'smtpport'}|;
         my $m = qq|send message error - couldn't open any SMTP servers |.
                 join(", ", @{$config{'smtpserver'}}).
                 qq| at port $config{'smtpport'}|;
         writelog($m); writehistory($m);
      }

      # SMTP SASL authentication (PLAIN only)
      if ($config{'smtpauth'} && !$senderr) {
         my $auth = $smtp->supports("AUTH");
         if (! $smtp->auth($config{'smtpauth_username'}, $config{'smtpauth_password'}) ) {
            $senderr++;
            $senderrstr="$lang_err{'network_server_error'}!<br>($smtpserver - ".$smtp->message.")";
            my $m="send message error - SMTP server $smtpserver error - ".$smtp->message;
            writelog($m); writehistory($m);
         }
      }

      $smtp->mail($from) or $senderr++ if (!$senderr);
      if (!$senderr) {
         my @ok=$smtp->recipient(@recipients, { SkipBad => 1 });
         $senderr++ if ($#ok<$#recipients);
      }
      $smtp->data()      or $senderr++ if (!$senderr);

      # save message to draft if smtp error, Dattola Filippo 06/20/2002
      if ($senderr && (!$quotalimit||$quotausage<$quotalimit) && $config{'enable_savedraft'}) {
         $do_save = 1;
         $savefolder = 'saved-drafts';
      }
   }

   if ($do_save) {
      ($savefile, $savedb)=get_folderpath_folderdb($user, $savefolder);

      if ( ! -f $savefile) {
         if (sysopen($folderhandle, $savefile, O_WRONLY|O_TRUNC|O_CREAT)) {
            close($folderhandle);
         } else {
            $saveerrstr="$lang_err{'couldnt_write'} $savefile!";
            $saveerr++;
            $do_save=0;
         }
      }

      if (!$saveerr && ow::filelock::lock($savefile, LOCK_EX)) {
         if (update_folderindex($savefile, $savedb)<0) {
            ow::filelock::lock($savefile, LOCK_UN);
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_updatedb'} ".f2u($savedb));
         }

         my $oldmsgfound=0;
         my $oldsubject='';
         my %FDB;
         ow::dbm::open(\%FDB, $savedb, LOCK_SH) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} ".f2u($savedb));
         if (defined $FDB{$mymessageid}) {
            $oldmsgfound=1;
            $oldsubject=(string2msgattr($FDB{$mymessageid}))[$_SUBJECT];
         }
         ow::dbm::close(\%FDB, $savedb);

         if ($oldmsgfound) {
            if ($savefolder eq 'saved-drafts' && $subject eq $oldsubject) {
               # remove old draft if the subject is the same
               if ((operate_message_with_ids("delete", [$mymessageid], $savefile, $savedb))[0]>0) {
                  folder_zapmessages($savefile, $savedb);
               } else {
                  $mymessageid=fakemessageid($from);	# use another id if remove failed
               }
            } else {
               # change mymessageid to ensure messageid is unique in one folder
               # note: this new mymessageid will be used by composemessage later
               $mymessageid=fakemessageid($from);
            }
         }

         if (sysopen($folderhandle, $savefile, O_RDWR) ) {
            $messagestart=(stat($folderhandle))[7];
            seek($folderhandle, $messagestart, 0);	# seek end manually to cover tell() bug in perl 5.8
         } else {
            $saveerrstr="$lang_err{'couldnt_write'} $savefile!";
            $saveerr++;
            $do_save=0;
         }

      } else {
         $saveerrstr="$lang_err{'couldnt_writelock'} $savefile!";
         $saveerr++;
         $do_save=0;
      }
   }

   # nothing to do, return error msg immediately
   if ($do_send==0 && $do_save==0) {
      if ($saveerr) {
         openwebmailerror(__FILE__, __LINE__, $saveerrstr);
      } else {
         print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&sessionid=$thissession&sort=$sort&msgdatetype=$msgdatetype&folder=$escapedfolder&page=$page");
      }
   }

   my $s;

   # Add a 'From ' as delimeter for local saved msg
   $s = "From $user ";
   if ($config{'delimiter_use_GMT'}) {
      $s.=ow::datetime::dateserial2delimiter(ow::datetime::gmtime2dateserial(), "", $prefs{'daylightsaving'}, $prefs{'timezone'})."\n";
   } else {
      # use server localtime for delimiter
      $s.=ow::datetime::dateserial2delimiter(ow::datetime::gmtime2dateserial(), ow::datetime::gettimeoffset(), $prefs{'daylightsaving'}, $prefs{'timezone'})."\n";
   }
   print $folderhandle $s or $saveerr++ if ($do_save && !$saveerr);
   $messageheader.=$s;

   if ($realname ne '') {
      $s = "From: ".ow::mime::encode_mimewords(qq|"$realname" <$from>|, ('Charset'=>$composecharset))."\n";
   } else {
      $s = "From: ".ow::mime::encode_mimewords(qq|$from|, ('Charset'=>$composecharset))."\n";
   }
   dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
   $messageheader.=$s;

   if ($to ne '') {
      $s = "To: ".ow::mime::encode_mimewords(folding($to), ('Charset'=>$composecharset))."\n";
      dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
      $messageheader.=$s;
   } elsif ($bcc ne '' && $cc eq '') { # recipients in Bcc only, To and Cc are null
      $s = "To: undisclosed-recipients: ;\n";
      print $folderhandle $s or $saveerr++ if ($do_save && !$saveerr);
      $messageheader.=$s;
   }

   if ($cc ne '') {
      $s = "Cc: ".ow::mime::encode_mimewords(folding($cc), ('Charset'=>$composecharset))."\n";
      dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
      $messageheader.=$s;
   }
   if ($bcc ne '') {	# put bcc header in folderfile only, not in outgoing msg
      $s = "Bcc: ".ow::mime::encode_mimewords(folding($bcc), ('Charset'=>$composecharset))."\n";
      print $folderhandle $s or $saveerr++ if ($do_save && !$saveerr);
      $messageheader.=$s;
   }

   $s  = "";
   $s .= "Reply-To: ".ow::mime::encode_mimewords($replyto, ('Charset'=>$composecharset))."\n" if ($replyto);
   $s .= "Subject: ".ow::mime::encode_mimewords($subject, ('Charset'=>$composecharset))."\n";
   $s .= "Date: $date\n";
   $s .= "Message-Id: $mymessageid\n";
   $s .= "In-Reply-To: $inreplyto\n" if ($inreplyto);
   $s .= "References: $references\n" if ($references);
   $s .= "Priority: $priority\n" if ($priority && $priority ne 'normal');
   $s .= safexheaders($config{'xheaders'});
   if ($confirmreading) {
      if ($replyto ne '') {
         $s .= "X-Confirm-Reading-To: ".ow::mime::encode_mimewords($replyto, ('Charset'=>$composecharset))."\n";
         $s .= "Disposition-Notification-To: ".ow::mime::encode_mimewords($replyto, ('Charset'=>$composecharset))."\n";
      } else {
         $s .= "X-Confirm-Reading-To: $from\n";
         $s .= "Disposition-Notification-To: $from\n";
      }
   }
   $s .= "MIME-Version: 1.0\n";
   dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
   $messageheader.=$s;

   my $contenttype;
   my $boundary = "----=OPENWEBMAIL_ATT_" . rand();
   my $boundary2 = "----=OPENWEBMAIL_ATT_" . rand();
   my $boundary3 = "----=OPENWEBMAIL_ATT_" . rand();

   my (@related, @mixed);
   foreach my $r_att (@{$r_attfiles}) {
      if (${$r_att}{'referencecount'}>0 && $msgformat ne "text") {
         push(@related, $r_att);
      } else {
         ${$r_att}{'referencecount'}=0;
         push(@mixed, $r_att);
      }
   }

   if ($attachment || $#mixed>=0 ) {
      # HAS MIXED ATTACHMENT
      $contenttype="multipart/mixed;";

      $s=qq|Content-Type: multipart/mixed;\n|.
         qq|\tboundary="$boundary"\n|;
      dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
      print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);
      $messageheader.=$s."Status: R\n";

      dump_str(qq|\nThis is a multi-part message in MIME format.\n|,
               $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

      if ($#related>=0) { # has related att, has mixed att
         if ($msgformat eq 'html') {
            dump_str(qq|\n--$boundary\n|.
                     qq|Content-Type: multipart/related;\n|.
                     qq|\ttype="text/html";\n|.
                     qq|\tboundary="$boundary2"\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_bodyhtml(\$body, $boundary2, $composecharset, $msgformat,
                              $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            dump_atts(\@related, $boundary2, $composecharset,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

         } elsif ($msgformat eq "both") {
            $contenttype="multipart/related;";

            dump_str(qq|\n--$boundary\n|.
                     qq|Content-Type: multipart/related;\n|.
                     qq|\ttype="multipart/alternative";\n|.
                     qq|\tboundary="$boundary2"\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_str(qq|\n--$boundary2\n|.
                     qq|Content-Type: multipart/alternative;\n|.
                     qq|\tboundary="$boundary3"\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_bodytext(\$body, $boundary3, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            dump_bodyhtml(\$body, $boundary3, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_str(qq|\n--$boundary3--\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_atts(\@related, $boundary2, $composecharset,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
         }

         dump_str(qq|\n--$boundary2--\n|,
                  $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

      } else {	# no related att, has mixed att
         if ($msgformat eq 'text') {
            dump_bodytext(\$body, $boundary, $composecharset,  $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

         } elsif ($msgformat eq 'html') {
            dump_bodyhtml(\$body, $boundary, $composecharset,  $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

         } elsif ($msgformat eq 'both') {
            dump_str(qq|\n--$boundary\n|.
                     qq|Content-Type: multipart/alternative;\n|.
                     qq|\tboundary="$boundary2"\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_bodytext(\$body, $boundary2, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            dump_bodyhtml(\$body, $boundary2, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_str(qq|\n--$boundary2--\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
         }
      }

      dump_atts(\@mixed, $boundary, $composecharset,
                $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

      if ($attachment) {
         dump_str(qq|\n--$boundary\n$attheader\n|,
                  $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
         while (read($attachment, $s, 400*57)) { # attachmet fh to uploadfile stored by CGI.pm
            dump_str(encode_base64($s),
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
         }
         close($attachment);    # close tmpfile created by CGI.pm
      }

      dump_str(qq|\n--$boundary--\n|,
               $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

   } else {
      # NO MIXED ATTACHMENT
      if ($#related>=0) { # has related att, no mixed att, !attachment param

         if ($msgformat eq 'html') {
            $contenttype="multipart/related;";

            $s=qq|Content-Type: multipart/related;\n|.
               qq|\ttype="text/html";\n|.
               qq|\tboundary="$boundary"\n|;
            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);
            $messageheader.=$s."Status: R\n";

            dump_str(qq|\nThis is a multi-part message in MIME format.\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_bodyhtml(\$body, $boundary, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            dump_atts(\@related, $boundary, $composecharset,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

         } elsif ($msgformat eq "both") {
            $contenttype="multipart/related;";

            $s=qq|Content-Type: multipart/related;\n|.
               qq|\ttype="multipart/alternative";\n|.
               qq|\tboundary="$boundary"\n|;
            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);
            $messageheader.=$s."Status: R\n";

            dump_str(qq|\nThis is a multi-part message in MIME format.\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_str(qq|\n--$boundary\n|.
                     qq|Content-Type: multipart/alternative;\n|.
                     qq|\tboundary="$boundary2"\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_bodytext(\$body, $boundary2, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            dump_bodyhtml(\$body, $boundary2, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_str(qq|\n--$boundary2--\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_atts(\@related, $boundary, $composecharset,
                      $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
         }

         dump_str(qq|\n--$boundary--\n|,
                  $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

      } else {	# no related att, no mixed att, !attachment param
         if ($msgformat eq 'text') {
            $contenttype="text/plain; charset=$composecharset";

            $s=qq|Content-Type: text/plain;\n|.
               qq|\tcharset=$composecharset\n|;
            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);
            $messageheader.=$s."Status: R\n";

            $smtp->datasend("\n$body\n")    or $senderr++ if ($do_send && !$senderr);
            $body=~s/^From />From /gm;
            print $folderhandle "\n$body\n" or $saveerr++ if ($do_save && !$saveerr);
            if ( $config{'mailfooter'}=~/[^\s]/) {
               $s=str2str($config{'mailfooter'}, $msgformat)."\n";
               $smtp->datasend($s) or $senderr++ if ($do_send && !$senderr);
            }

         } elsif ($msgformat eq 'html') {
            $contenttype="text/html; charset=$composecharset";

            $s=qq|Content-Type: text/html;\n|.
               qq|\tcharset=$composecharset\n|.
               qq|Content-Transfer-Encoding: quoted-printable\n|;
            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);
            $messageheader.=$s."Status: R\n";

            $s = qq|\n|.encode_qp($body).qq|\n|;
            $smtp->datasend($s)    or $senderr++ if ($do_send && !$senderr);
            $s=~s/^From />From /gm;
            print $folderhandle $s or $saveerr++ if ($do_save && !$saveerr);
            if ( $config{'mailfooter'}=~/[^\s]/) {
               $s=encode_qp(str2str($config{'mailfooter'}, $msgformat))."\n";
               $smtp->datasend($s) or $senderr++ if ($do_send && !$senderr);
            }

         } elsif ($msgformat eq 'both') {
            $contenttype="multipart/alternative;";

            $s=qq|Content-Type: multipart/alternative;\n|.
               qq|\tboundary="$boundary"\n|;
            dump_str($s, $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            print $folderhandle "Status: R\n" or $saveerr++ if ($do_save && !$saveerr);
            $messageheader.=$s."Status: R\n";

            dump_str(qq|\nThis is a multi-part message in MIME format.\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_bodytext(\$body, $boundary, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
            dump_bodyhtml(\$body, $boundary, $composecharset, $msgformat,
                          $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);

            dump_str(qq|\n--$boundary--\n|,
                     $smtp, $folderhandle, $do_send, $do_save, \$senderr, \$saveerr);
         }
      }
   }

   # terminate this message
   $smtp->dataend() or $senderr++ if ($do_send && !$senderr);
   # ensure a blank line between messages for local saved msgs
   print $folderhandle "\n" or $saveerr++ if ($do_save && !$saveerr);

   if ($do_send) {
      if (!$senderr) {
         $smtp->quit();
         open(STDERR,">&SAVEERR"); close(SAVEERR);	# redirect stderr back

         my @r;
         push(@r, "to=$to") if ($to);
         push(@r, "cc=$cc") if ($cc);
         push(@r, "bcc=$bcc") if ($bcc);
         my $m="send message - subject=".(iconv($composecharset, $prefs{'fscharset'}, $subject))[0]." - ".join(', ', @r);
         writelog($m); writehistory($m);
      } else {
         $smtp->close() if ($smtp); # close smtp if it was sucessfully opened
         open(STDERR,">&SAVEERR"); close(SAVEERR);	# redirect stderr back

         if ($senderrstr eq "") {
            $senderrstr= qq|$lang_err{'sendmail_error'}|;

            if ($do_save && $savefolder eq 'saved-drafts') {
               my $draft_url = qq|$config{'ow_cgiurl'}/openwebmail-send.pl?sessionid=|.
                               ow::htmltext::str2html($thissession) .
                               qq|&amp;action=composemessage&amp;composetype=editdraft&amp;folder=|.
                               ow::htmltext::str2html($savefolder) .
                               qq|&amp;message_id=|.ow::tool::escapeURL($mymessageid);
               $senderrstr.= qq|<br>\n<a href="$draft_url">$lang_err{'sendmail_chkdraft'}</a>|;
            }

            my $smtperr=readsmtperr($smtperrfile);
            # any user input in recipient names is automatically html-entity
            # encoded from smtperr by CGI.pm textarea
            $senderrstr.=qq|<br><br>\n<form>|.
                         textarea(-name=>'smtperror',
                                  -default=>$smtperr,
                                  -rows=>'10',
                                  -columns=>'72',
                                  -wrap=>'soft',
                                  -override=>'1').
                         qq|</form>|;
            $smtperr=~s/\n/\n /gs; $smtperr=~s/\s+$//;
            writelog("send message error - smtp error ...\n $smtperr");
            writehistory("send message error - smtp error");
         }
      }
   } else {
      open(STDERR,">&SAVEERR"); close(SAVEERR);	# redirect stderr back
   }
   unlink($smtperrfile);

   if ($do_save) {
      if (!$saveerr) {
         close($folderhandle);
         $messagesize=(stat($savefile))[7] - $messagestart;

         my @attr;
         $attr[$_OFFSET]=$messagestart;

         $attr[$_TO]=$to;
         $attr[$_TO]=$cc if ($attr[$_TO] eq '');
         $attr[$_TO]=$bcc if ($attr[$_TO] eq '');
         # some dbm(ex:ndbm on solaris) can only has value shorter than 1024 byte,
         # so we cut $_to to 256 byte to make dbm happy
         if (length($attr[$_TO]) >256) {
            $attr[$_TO]=substr($attr[$_TO], 0, 252)."...";
         }

         if ($realname) {
            $attr[$_FROM]=qq|"$realname" <$from>|;
         } else {
            $attr[$_FROM]=qq|$from|;
         }
         $attr[$_DATE]=$dateserial;
         $attr[$_RECVDATE]=$dateserial;
         $attr[$_SUBJECT]=$subject;
         $attr[$_CONTENT_TYPE]=$contenttype;

         ($attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT])=iconv($composecharset, 'utf-8', $attr[$_FROM], $attr[$_TO], $attr[$_SUBJECT] );

         $attr[$_STATUS]="R";
         $attr[$_STATUS].="I" if ($priority eq 'urgent');
         # flags used by openwebmail internally
         $attr[$_STATUS].="T" if ($attachment || $#{$r_attfiles}>=0 );

         $attr[$_REFERENCES]=$references;
         $attr[$_CHARSET]=$composecharset;
         $attr[$_SIZE]=$messagesize;
         $attr[$_HEADERSIZE]=length($messageheader);
         $attr[$_HEADERCHKSUM]=ow::tool::calc_checksum(\$messageheader);

         my %FDB;
         ow::dbm::open(\%FDB, $savedb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($savedb));
         $FDB{$mymessageid}=msgattr2string(@attr);
         $FDB{'ALLMESSAGES'}++;
         $FDB{'METAINFO'}=ow::tool::metainfo($savefile);
         $FDB{'LSTMTIME'}=time();
         ow::dbm::close(\%FDB, $savedb);
      } else {
         truncate($folderhandle, ow::tool::untaint($messagestart));
         close($folderhandle);

         my %FDB;
         ow::dbm::open(\%FDB, $savedb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($savedb));
         $FDB{'METAINFO'}=ow::tool::metainfo($savefile);
         $FDB{'LSTMTIME'}=time();
         ow::dbm::close(\%FDB, $savedb);
      }

      ow::filelock::lock($savefile, LOCK_UN);
   }

   # status update(mark referenced message as answered) and folderdb update
   #
   # this must be done AFTER the above do_savefolder block
   # since the start of the savemessage would be changed by status_update
   # if the savedmessage is on the same folder as the answered message
   if ($do_send && !$senderr && $inreplyto) {
      my @checkfolders=();

      # if current folder is sent/draft folder,
      # we try to find orig msg from other folders
      # Or we just check the current folder
      if ($folder eq "sent-mail" || $folder eq "saved-drafts" ) {
         my (@validfolders, $inboxusage, $folderusage);
         getfolders(\@validfolders, \$inboxusage, \$folderusage);
         foreach (@validfolders) {
            if ($_ ne "sent-mail" || $_ ne "saved-drafts" ) {
               push(@checkfolders, $_);
            }
         }
      } else {
         push(@checkfolders, $folder);
      }

      # identify where the original message is
      foreach my $foldername (@checkfolders) {
         my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $foldername);
         my (%FDB, $oldstatus, $found);

         ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($folderdb));
         if (defined $FDB{$inreplyto}) {
            $oldstatus = (string2msgattr($FDB{$inreplyto}))[$_STATUS];
            $found=1;
         }

         ow::dbm::close(\%FDB, $folderdb);

         if ( $found ) {
            if ($oldstatus !~ /a/i) {
               # try to mark answered if get filelock
               if (ow::filelock::lock($folderfile, LOCK_EX)) {
                  update_message_status($inreplyto, $oldstatus."A", $folderdb, $folderfile);
                  ow::filelock::lock($folderfile, LOCK_UN);
               }
            }
            last;
         }
      }
   }

   if ($senderr) {
      openwebmailerror(__FILE__, __LINE__, $senderrstr, "passthrough");
   } elsif ($saveerr) {
      openwebmailerror(__FILE__, __LINE__, $saveerrstr);
   } else {
      if (defined param('sendbutton')) {
         # delete attachments only if no error,
         # in case user trys resend, attachments could be available
         deleteattachments();

         my ($sentsubject)=iconv($composecharset, $prefs{'charset'}, $subject||'N/A');
         $sentsubject=ow::tool::escapeURL($sentsubject);
         print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&sessionid=$thissession&sort=$sort&msgdatetype=$msgdatetype&folder=$escapedfolder&page=$page&sentsubject=$sentsubject");
      } else {
         # save draft, call getfolders to recalc used quota
         if ($quotalimit>0 && $quotausage+$messagesize>$quotalimit) {
            $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
         }
         return(composemessage());
      }
   }
}

# convert filename in attheader to same charset as message itself when sending
sub _convert_attfilename {
   my ($prefix, $name, $postfix, $targetcharset)=@_;
   my $origcharset;
   $origcharset=$1 if ($name =~ m{=\?([^?]*)\?[bq]\?[^?]+\?=}xi);
   return($prefix.$name.$postfix)   if ($origcharset eq '' || $origcharset eq $targetcharset);

   if (is_convertible($origcharset, $targetcharset)) {
      $name=ow::mime::decode_mimewords($name);
      ($name)=iconv($origcharset, $targetcharset, $name);
      $name=ow::mime::encode_mimewords($name, ('Charset'=>$targetcharset));
   }
   return($prefix.$name.$postfix);
}

sub dump_str {
   my ($s, $smtp, $folderhandle, $do_send, $do_save, $r_senderr, $r_saveerr)=@_;
   $smtp->datasend($s)    or ${$r_senderr}++ if ($do_send && !${$r_senderr});
   print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});
}

sub dump_bodytext {
   my ($r_body, $boundary, $composecharset, $msgformat,
       $smtp, $folderhandle, $do_send, $do_save, $r_senderr, $r_saveerr)=@_;

   my $s = qq|\n--$boundary\n|.
           qq|Content-Type: text/plain;\n|.
           qq|\tcharset=$composecharset\n\n|;
   if ($msgformat eq "text") {
      $s.=${$r_body}.qq|\n|;
   } else {
      $s.=ow::htmltext::html2text(${$r_body}).qq|\n|;
   }
   $smtp->datasend($s) or ${$r_senderr}++ if ($do_send && !${$r_senderr});

   $s=~s/^From / From/gm;
   print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});

   if ( $config{'mailfooter'}=~/[^\s]/) {
      $s=str2str($config{'mailfooter'}, $msgformat)."\n";
      $smtp->datasend($s) or ${$r_senderr}++ if ($do_send && !${$r_senderr});
   }
}

sub dump_bodyhtml {
   my ($r_body, $boundary, $composecharset, $msgformat,
       $smtp, $folderhandle, $do_send, $do_save, $r_senderr, $r_saveerr)=@_;

   my $s = qq|\n--$boundary\n|.
           qq|Content-Type: text/html;\n|.
           qq|\tcharset=$composecharset\n|.
           qq|Content-Transfer-Encoding: quoted-printable\n\n|;
   if ($msgformat eq "text") {
      $s.=encode_qp(ow::htmltext::text2html(${$r_body})).qq|\n|;
   } else {
      $s.=encode_qp(${$r_body}).qq|\n|;
   }
   $smtp->datasend($s) or ${$r_senderr}++ if ($do_send && !${$r_senderr});

   $s=~s/^From / From/gm;
   print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});

   if ( $config{'mailfooter'}=~/[^\s]/) {
      $s=encode_qp(str2str($config{'mailfooter'}, $msgformat))."\n";
      $smtp->datasend($s) or ${$r_senderr}++ if ($do_send && !${$r_senderr});
   }
}

sub dump_atts {
   my ($r_atts, $boundary, $composecharset,
       $smtp, $folderhandle, $do_send, $do_save, $r_senderr, $r_saveerr)=@_;
   my $s;

   foreach my $r_att (@{$r_atts}) {
      $smtp->datasend("\n--$boundary\n")    or ${$r_senderr}++ if ($do_send && !${$r_senderr});
      print $folderhandle "\n--$boundary\n" or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});

      my $attfile="$config{ow_sessionsdir}/${$r_att}{file}";
      my $referenced=${$r_att}{referencecount};

      sysopen(ATTFILE, $attfile, O_RDONLY);
      # print attheader line by line
      while (defined($s = <ATTFILE>)) {
         if ($s =~ /^Content\-Id: <?att\d\d\d\d\d\d\d\d/ && !$referenced) {
            # remove contentid from attheader if it was set by openwebmail but not referenced,
            # since outlook will treat an attachment as invalid
            # if it has content-id but not been referenced
            next;
         }
         $s =~ s/^(.+name="?)([^"]+)("?.*)$/_convert_attfilename($1, $2, $3, $composecharset)/ie;
         $smtp->datasend($s)    or ${$r_senderr}++ if ($do_send && !${$r_senderr});
         print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});
         last if ($s =~ /^\s+$/ );
      }
      # print attbody block by block
      while (read(ATTFILE, $s, 32768)) {
         $smtp->datasend($s)    or ${$r_senderr}++ if ($do_send && !${$r_senderr});
         print $folderhandle $s or ${$r_saveerr}++ if ($do_save && !${$r_saveerr});
      }
      close(ATTFILE);
   }
   return;
}

########## END SENDMESSAGE #######################################

########## GET_TEXT_HTML #########################################
sub str2str {
   my ($str, $format)=@_;
   my $is_html; $is_html=1 if ($str=~/(?:<br>|<p>|<a .*>|<font .*>|<table .*>)/is);
   if ($format eq 'text') {
      return ow::htmltext::html2text($str) if ($is_html)
   } else {
      return ow::htmltext::text2html($str) if (!$is_html);
   }
   return $str;
}
########## END GET_TEXT_HTML #####################################

########## GETATTLISTINFO ########################################
sub getattfilesinfo {
   my (@attfiles, @sessfiles);
   my $totalsize = 0;

   opendir(SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_sessionsdir'}! ($!)");
      @sessfiles = sort readdir(SESSIONSDIR);
   closedir(SESSIONSDIR);

   foreach my $currentfile (@sessfiles) {
      if ($currentfile =~ /^(\Q$thissession\E\-att\d+)$/) {
         my (%att, $attheader);

         push(@attfiles, \%att);
         $att{file}=$1;

         local $/="\n\n";	# read whole file until blank line
         sysopen(ATTFILE, "$config{'ow_sessionsdir'}/$currentfile", O_RDONLY);
         $attheader=<ATTFILE>;
         close(ATTFILE);

         $att{'content-type'}='application/octet-stream';	# assume attachment is binary
         ow::mailparse::parse_header(\$attheader, \%att);
         $att{'content-id'}=~s/^\s*\<(.+)\>\s*$/$1/;

         ($att{name}, $att{namecharset})=
            ow::mailparse::get_filename_charset($att{'content-type'}, $att{'content-disposition'});
         $att{name}=~s/Unknown/attachment_$#attfiles/;
         $att{size}=(-s "$config{'ow_sessionsdir'}/$currentfile");

         $totalsize += $att{size};
      }
   }

   return ($totalsize, \@attfiles);
}
########## END GETATTLISTINFO ####################################

########## DELETEATTACHMENTS #####################################
sub deleteattachments {
   my (@delfiles, @sessfiles);

   opendir(SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_sessionsdir'}! ($!)");
      @sessfiles=readdir(SESSIONSDIR);
   closedir(SESSIONSDIR);

   foreach my $attfile (@sessfiles) {
      if ($attfile =~ /^(\Q$thissession\E\-att\d+)$/) {
         push(@delfiles, ow::tool::untaint("$config{'ow_sessionsdir'}/$attfile"));
      }
   }
   unlink(@delfiles) if ($#delfiles>=0);
}
########## END DELETEATTACHMENTS #################################

########## FOLDING ###############################################
# folding the to, cc, bcc field so it won't violate the 998 char
# limit (defined in RFC 2822 2.2.3) after base64/qp encoding
# ps: since qp may extend strlen for 3 times, we use 998/3=332 as limit
sub folding {
   return($_[0]) if (length($_[0])<330);

   my ($folding, $line)=('', '');
   foreach my $token (ow::tool::str2list($_[0],0)) {
      if (length($line)+length($token) <330) {
         $line.=",$token";
      } else {
         $folding.="$line,\n   ";
         $line=$token;
      }
   }
   $folding.=$line;

   $folding=~s/^,//;
   return($folding);
}
########## END FOLDING ###########################################

########## REPARAGRAPH ###########################################
sub reparagraph {
   my @lines=split(/\n/, $_[0]);
   my $maxlen=$_[1];
   my ($text,$left) = ('','');

   foreach my $line (@lines) {
      if ($left eq  "" && length($line) < $maxlen) {
         $text.="$line\n";
      } elsif ($line=~/^\s*$/ ||		# newline
               $line=~/^>/ || 		# previous orig
               $line=~/^#/ || 		# comment line
               $line=~/^\s*[\-=#]+\s*$/ || # dash line
               $line=~/^\s*[\-=#]{3,}/ ) { # dash line
         $text.= "$left\n" if ($left ne "");
         $text.= "$line\n";
         $left="";
      } else {
         if ($line=~/^\s*\(/ ||
               $line=~/^\s*\d\d?[\.:]/ ||
               $line=~/^\s*[A-Za-z][\.:]/ ||
               $line=~/\d\d:\d\d:\d\d/ ||
               $line=~/¡G/) {
            $text.= "$left\n";
            $left=$line;
         } else {
            if ($left=~/ $/ || $line=~/^ / || $left eq "" || $line eq "") {
               $left.=$line;
            } else {
               $left.=" ".$line;
            }
         }

         while ( length($left)>$maxlen ) {
            my $furthersplit=0;
            for (my $len=$maxlen-2; $len>2; $len-=2) {
               if ($left =~ /^(.{$len}.*?[\s\,\)\-])(.*)$/) {
                  if (length($1) < $maxlen) {
                     $text.="$1\n"; $left=$2;
                     $furthersplit=1;
                     last;
                  }
               } else {
                  $text.="$left\n"; $left="";
                  last;
               }
            }
            last if ($furthersplit==0);
         }

      }
   }
   $text.="$left\n" if ($left ne "");
   return($text);
}
########## END REPARAGRAPH #######################################

########## FAKEMESSGAEID #########################################
sub fakemessageid {
   my $postfix=$_[0];
   my $fakedid = ow::datetime::gmtime2dateserial().'.M'.int(rand()*100000);
   if ($postfix =~ /@(.*)$/) {
      return("<$fakedid".'@'."$1>");
   } else {
      return("<$fakedid".'@'."$postfix>");
   }
}
########## END FAKEMESSGAEID #####################################

########## READSMTPERR ###########################################
sub readsmtperr {
   my ($content, $linecount)=('', 0);

   sysopen(F, $_[0], O_RDONLY);
   while (<F>) {
      s/\s*$//;
      if (/(>>>.*$)/ || /(<<<.*$)/) {
         $content.="$1\n";
         $linecount++;
         if ($linecount==50) {
            my $snip=(-s $_[0])-512-tell(F);
            if ($snip>512) {
               seek(F, $snip, 1);
               $_=<F>;
               $snip+=length($_);
               $content.="\n $snip bytes snipped ...\n\n";
            }
         }
      }
   }
   close(F);
   return($content);
}
########## END READSMTPERR #######################################

########## HTMLAREA_COMPATIBLE ###################################
sub htmlarea_compatible {
   my $u=$ENV{'HTTP_USER_AGENT'};
   if ( $u=~m!Mozilla/4.0! &&
        $u=~m!compatible;!) {
      return 0 if ($u=~m!Opera!);	# not Opera
      if ($u=~m!Windows! &&
          $u=~m!MSIE ([\d\.]+)! ) {
         return 1 if ($1>=5.5);		# MSIE>=5.5 on windows platform
      }
   }
   if ( $u=~m!Mozilla/5.0! &&
        $u!~m!compatible;!) {
      if ($u!~m!(?:Phoenix|Galeon|Firebird)/! &&
          $u=~m!rv:([\d\.]+)! ) {
         return 1 if ($1 ge "1.3");	# full Mozilla>=1.3 on all plaform
      }
      if ($u=~m!Firebird/([\d\.]+)!) {
         return 1 if ($1 ge "0.6.1");	# Firebird>=0.6.1 on all plaform
      }
   }
   return 0;
}
########## END HTMLAREA_COMPATIBLE ###############################

########## TNEFATT2ARCHIVE #######################################
sub tnefatt2archive {
   my ($r_attachment, $convfrom, $composecharset)=@_;
   my $tnefbin=ow::tool::findbin('tnef');
   return('') if ($tnefbin eq '');

   my $content;
   if (${$r_attachment}{'content-transfer-encoding'} =~ /^base64$/i) {
      $content = decode_base64(${${$r_attachment}{r_content}});
   } elsif (${$r_attachment}{'content-transfer-encoding'} =~ /^quoted-printable$/i) {
      $content = decode_qp(${${$r_attachment}{r_content}});
   } else { ## Guessing it's 7-bit, at least sending SOMETHING back! :)
      $content = ${${$r_attachment}{r_content}};
   }
   my ($arcname, $r_arcdata, @arcfilelist)=ow::tnef::get_tnef_archive($tnefbin, ${$r_attachment}{filename}, \$content);
   return('') if ($arcname eq '');

   my $arccontenttype=ow::tool::ext2contenttype($arcname);
   my $arcdescription=join(', ', @arcfilelist);

   # convfrom is the charset choosed by user in message reading
   # we convert att attributes from convfrom to current composecharset
   if (is_convertible($convfrom, $composecharset) ) {
      ($arcname, $arcdescription)=iconv($convfrom, $composecharset, $arcname, $arcdescription);
      $arcname=ow::mime::encode_mimewords($arcname, ('Charset'=>$composecharset));
      $arcdescription=ow::mime::encode_mimewords($arcdescription, ('Charset'=>$composecharset));
   } else {
      $arcname=ow::mime::encode_mimewords($arcname, ('Charset'=>${$r_attachment}{charset}));
      $arcdescription=ow::mime::encode_mimewords($arcdescription, ('Charset'=>${$r_attachment}{charset}));
   }

   my $attheader = qq|Content-Type: $arccontenttype;\n|.
                   qq|\tname="$arcname"\n|.
                   qq|Content-Disposition: attachment; filename="$arcname"\n|.
                   qq|Content-Transfer-Encoding: base64\n|;
   $attheader.= qq|Content-Description: $arcdescription\n| if ($#arcfilelist>0);

   $content=encode_base64(${$r_arcdata});
   return($attheader, \$content);
}
########## TNEFATT2ARCHIVE #######################################
