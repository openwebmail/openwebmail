#!/usr/bin/perl -T
#############################################################################
# Open WebMail - Provides a web interface to user mailboxes                 #
#                                                                           #
# Copyright (C) 2001-2002                                                   #
# Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric                 #
# Copyright (C) 2000                                                        #
# Ernie Miller  (original GPL project: Neomail)                             #
#                                                                           #
# This program is distributed under GNU General Public License              #
#############################################################################

local $SCRIPT_DIR="";
if ( $ENV{'SCRIPT_FILENAME'} =~ m!^(.*?)/[\w\d\-]+\.pl! || $0 =~ m!^(.*?)/[\w\d\-]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\n\$SCRIPT_DIR not set in CGI script!\n"; exit 0; }

use strict;
no strict 'vars';
use Fcntl qw(:DEFAULT :flock);
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script
use Net::SMTP;

$ENV{PATH} = ""; # no PATH should be needed
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0007); # make sure the openwebmail group can write

push (@INC, $SCRIPT_DIR, ".");
require "openwebmail-shared.pl";
require "filelock.pl";
require "mime.pl";
require "maildb.pl";

local (%config, %config_raw);
local $thissession;
local ($loginname, $domain, $user, $userrealname, $uuid, $ugid, $homedir);
local (%prefs, %style);
local ($lang_charset, %lang_folders, %lang_sortlabels, %lang_text, %lang_err);
local ($folderdir, @validfolders, $folderusage);
local ($folder, $printfolder, $escapedfolder);

openwebmail_init();
verifysession();

local $firstmessage;
local $sort;
local ($searchtype, $keyword, $escapedkeyword);

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{"sort"} || 'date';
$searchtype = param("searchtype") || 'subject';
$keyword = param("keyword") || '';
$escapedkeyword = escapeURL($keyword);

########################## MAIN ##############################

my $action = param("action");
if ($action eq "replyreceipt") {
   replyreceipt();
} elsif ($action eq "composemessage") {
   composemessage();
} elsif ($action eq "sendmessage") {
   sendmessage();
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}

###################### END MAIN ##############################

################## REPLYRECEIPT ##################
sub replyreceipt {
   printheader();
   my $messageid = param("message_id");
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();
   my @attr;
   my %HDB;

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH);
   dbmopen (%HDB, $headerdb, undef);
   @attr=split(/@@@/, $HDB{$messageid});
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
   
   if ($attr[$_SIZE]>0) {
      my $header;

      # get message header
      open ($folderhandle, "+<$folderfile") or 
          openwebmailerror("$lang_err{'couldnt_open'} $folderfile!");
      seek ($folderhandle, $attr[$_OFFSET], 0) or openwebmailerror("$lang_err{'couldnt_seek'} $folderfile!");
      $header="";
      while (<$folderhandle>) {
         last if ($_ eq "\n" && $header=~/\n$/);
         $header.=$_;
      }
      close($folderhandle);

      # get notification-to 
      if ($header=~/^Disposition-Notification-To:\s?(.*?)$/im ) {
         my $to=$1;
         my $from=$prefs{'email'};

         my %userfrom=get_userfrom($loginname, $userrealname, "$folderdir/.from.book");
         foreach (sort keys %userfrom) {
            if ($header=~/$_/) {
               $from=$_; last;
            }
         }
         my $realname=$userfrom{$from};

         $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts
         $from =~ s/['"]/ /g;  # Get rid of shell escape attempts 

         # $date is used in message header Date: xxxx
         my $localtime = scalar(localtime);
         my @datearray = split(/ +/, $localtime);
         my $date = "$datearray[0], $datearray[2] $datearray[1] $datearray[4] $datearray[3] ".dst_adjust($config{'timeoffset'});

         ($realname =~ /^(.+)$/) && ($realname = '"'.$1.'"');
         ($from =~ /^(.+)$/) && ($from = $1);
         ($to =~ /^(.+)$/) && ($to = $1);
         ($date =~ /^(.+)$/) && ($date = $1);

         # fake a messageid for this message
         my $fakedid = getdateserial().'.M'.int(rand()*100000);
         if ($from =~ /@(.*)$/) {
            $fakedid="<$fakedid".'@'."$1>";
         } else {
            $fakedid="<$fakedid".'@'."$from>";
         }

         my $smtp;
         $smtp=Net::SMTP->new($config{'smtpserver'}, 
                              Port => $config{'smtpport'}, 
                              Timeout => 30, 
                              Hello => ${$config{'domainnames'}}[0]) or 
            openwebmailerror("$lang_err{'couldnt_open'} SMTP server $config{'smtpserver'}:$config{'smtpport'}!");
         $smtp->mail($from);
         if (! $smtp->recipient(str2list($to), { SkipBad => 1 }) ) {
            $smtp->reset();
            $smtp->quit();
            openwebmailerror("$lang_err{'sendmail_error'}!");
         }

         $smtp->data();
         $smtp->datasend("From: $realname <$from>\n",
                         "To: $to\n");
         $smtp->datasend("Reply-To: ", $prefs{"replyto"}, "\n") if ($prefs{"replyto"});


         # reply with english if sender has different charset than us
         if ( $attr[$_CONTENT_TYPE]=~/charset="?\Q$lang_charset\E"?/i) {
            $smtp->datasend("Subject: $lang_text{'read'} - $attr[$_SUBJECT]\n",
                            "Date: $date\n",
                            "Message-Id: $fakedid\n",
                            "X-Mailer: $config{'name'} $config{'version'} $config{'releasedate'}\n",
                            "X-OriginatingIP: ", get_clientip(), " ($loginname)\n",
                            "MIME-Version: 1.0\n",
                            "Content-Type: text/plain; charset=$lang_charset\n\n");
            $smtp->datasend("$lang_text{'yourmsg'}\n\n",
                            "  $lang_text{'to'}: $attr[$_TO]\n",
                            "  $lang_text{'subject'}: $attr[$_SUBJECT]\n",
                            "  $lang_text{'delivered'}: ", dateserial2str($attr[$_DATE], $prefs{'dateformat'}), "\n\n",
                            "$lang_text{'wasreadon1'} ", dateserial2str(getdateserial(), $prefs{'dateformat'}), " $lang_text{'wasreadon2'}\n\n");
         } else {
            $smtp->datasend("Subject: Read - $attr[$_SUBJECT]\n",
                            "Date: $date\n",
                            "Message-Id: $fakedid\n",
                            "X-Mailer: $config{'name'} $config{'version'} $config{'releasedate'}\n",
                            "X-OriginatingIP: ", get_clientip(), " ($loginname)\n",
                            "MIME-Version: 1.0\n",
                            "Content-Type: text/plain; charset=iso-8859-1\n\n");
            $smtp->datasend("Your message\n\n",
                            "  To: $attr[$_TO]\n",
                            "  Subject: $attr[$_SUBJECT]\n",
                            "  Delivered: ", dateserial2str($attr[$_DATE], $prefs{'dateformat'}), "\n\n",
                            "was read on", dateserial2str(getdateserial(), $prefs{'dateformat'}), ".\n\n");
         }
         $smtp->datasend($prefs{'signature'},   "\n") if (defined($prefs{'signature'}));
         $smtp->datasend($config{'mailfooter'}, "\n") if ($config{'mailfooter'}=~/[^\s]/);

         if (!$smtp->dataend()) {
            $smtp->reset();
            $smtp->quit();
            openwebmailerror("$lang_err{'sendmail_error'}!");
         }
         $smtp->quit();
      }

      # close the window that is processing confirm-reading-receipt 
      print qq|<script language="JavaScript">\n|,
            qq|<!--\n|,
            qq|window.close();\n|,
            qq|//-->\n|,
            qq|</script>\n|;
   } else {
      $messageid = str2html($messageid);
      print "What the heck? Message $messageid seems to be gone!";
   }
   printfooter();   
}
################ END REPLYRECEIPT ################

############### COMPOSEMESSAGE ###################
# 8 composetype: reply, replyall, forward, editdraft, 
#                forwardasatt (orig msg as an att),
#                continue(used after adding attachment), 
#                sendto(newmail with dest user),
#                none(newmail)
sub composemessage {
   no strict 'refs';
   my $html = '';
   my $temphtml;
   my ($savedattsize, $r_attnamelist, $r_attfilelist);

   open (COMPOSEMESSAGE, "$config{'ow_etcdir'}/templates/$prefs{'language'}/composemessage.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/composemessage.template!");
   while (<COMPOSEMESSAGE>) {
      $html .= $_;
   }
   close (COMPOSEMESSAGE);

   $html = applystyle($html);
   
   if ( param("deleteattfile") ne '' ) { # user click 'del' link
      my $deleteattfile=param("deleteattfile");

      $deleteattfile =~ s/\///g;  # just in case someone gets tricky ...
      ($deleteattfile =~ /^(.+)$/) && ($deleteattfile = $1);   # bypass taint check
      # only allow to delete attfiles belongs the $thissession
      if ($deleteattfile=~/^$thissession/) {
         unlink ("$config{'ow_etcdir'}/sessions/$deleteattfile");
      }
      ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();

   } elsif (defined(param($lang_text{'add'}))) { # user press 'add' button
      ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();
      my $attachment = param("attachment");
      my $attname = $attachment;
      my $attcontents = '';

      if ($attachment) {
         if ( ($config{'attlimit'}) && ( ( $savedattsize + (-s $attachment) ) > ($config{'attlimit'} * 1048576) ) ) {
            openwebmailerror ("$lang_err{'att_overlimit'} $config{'attlimit'} MB!");
         }
         my $content_type;
         # Convert :: back to the ' like it should be.
         $attname =~ s/::/'/g;
         # Trim the path info from the filename
         $attname =~ s/^.*\\//;
         $attname =~ s/^.*\///;
         $attname =~ s/^.*://;

         if (defined(uploadInfo($attachment))) {
            $content_type = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
         } else {
            $content_type = 'application/octet-stream';
         }

         my $attserial = time();
         open (ATTFILE, ">$config{'ow_etcdir'}/sessions/$thissession-att$attserial");
         print ATTFILE qq|Content-Type: $content_type;\n|;
         print ATTFILE qq|\tname="$attname"\nContent-Transfer-Encoding: base64\n\n|;
         while (read($attachment, $attcontents, 600*57)) {
            $attcontents=encode_base64($attcontents);
            $savedattsize += length($attcontents);
            print ATTFILE $attcontents;
         }
         close ATTFILE;

         $attname = str2html($attname);
         push (@{$r_attnamelist}, "$attname");
         push (@{$r_attfilelist}, "$thissession-att$attserial");
      }

   # usr press 'send' button but no receiver, keep editing
   } elsif ( defined(param($lang_text{'send'})) &&
             param("to") eq '' && param("cc") eq '' && param("bcc") eq '' ) {
      ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();

   } else {	# this is new message, remove previous aged attachments
      deleteattachments();
   }

   my $messageid = param("message_id");
   my %message;
   my $attnumber;
   my $from ='';
   my $to = param("to") || '';
   my $cc = param("cc") || '';
   my $bcc = param("bcc") || '';
   my $replyto = param("replyto") || $prefs{"replyto"} || '';
   my $subject = param("subject") || '';
   my $body = param("body") || '';
   my $inreplyto = param("inreplyto") || '';
   my $references = param("references") || '';
   my $priority = param("priority") || 'normal';	# normal/urgent/non-urgent

   my %userfrom=get_userfrom($loginname, $userrealname, "$folderdir/.from.book");
   if ($userfrom{$prefs{'email'}} ne "") {
      $from=qq|"$userfrom{$prefs{'email'}}" <$prefs{'email'}>|;
   } else {
      $from=qq|$prefs{'email'}|;
   }

   my $composetype = param("composetype");
   if ($composetype eq "reply" || $composetype eq "replyall" ||
       $composetype eq "forward" || $composetype eq "editdraft" ) {

      if ($composetype eq "forward" || $composetype eq "editdraft") {
         %message = %{&getmessage($messageid, "all")};
      } else {
         %message = %{&getmessage($messageid, "")};
      }

      my $fromemail=$prefs{'email'};
      foreach (keys %userfrom) {
         if ($composetype eq "editdraft") {
            if ($message{'from'}=~/$_/) {
               $fromemail=$_; last;
            }
         } else {	# reply/replyall/forward
            if ($message{'to'}=~/$_/ || $message{'cc'}=~/$_/ ) {
               $fromemail=$_; last;
            }
         }
      }
      if ($userfrom{$fromemail}) {
         $from=qq|"$userfrom{$fromemail}" <$fromemail>|;
      } else {
         $from=qq|$fromemail|;
      }

      # make the body for new mesage from original mesage for different contenttype
      #
      # handle the messages generated if sendmail is set up to send MIME error reports
      if ($message{contenttype} =~ /^multipart\/report/i) {
         foreach my $attnumber (0 .. $#{$message{attachment}}) {
            if (defined(${${$message{attachment}[$attnumber]}{r_content}})) {
               $body .= ${${$message{attachment}[$attnumber]}{r_content}};
               shift @{$message{attachment}};
            }
         }
      } elsif ($message{contenttype} =~ /^multipart/i) {
         # If the first attachment is text, 
         # assume it's the body of a message in multi-part format
         if ( defined(${$message{attachment}[0]}{contenttype}) &&
              ${$message{attachment}[0]}{contenttype} =~ /^text/i ) {
            if (${$message{attachment}[0]}{encoding} =~ /^quoted-printable/i) {
               ${${$message{attachment}[0]}{r_content}} =
            		decode_qp(${${$message{attachment}[0]}{r_content}});
            } elsif (${$message{attachment}[$attnumber]}{encoding} =~ /^base64/i) {
               ${${$message{attachment}[$attnumber]}{r_content}} = 
			decode_base64(${${$message{attachment}[$attnumber]}{r_content}});
            } elsif (${$message{attachment}[$attnumber]}{encoding} =~ /^x-uuencode/i) {
               ${${$message{attachment}[$attnumber]}{r_content}} = 
			uudecode(${${$message{attachment}[$attnumber]}{r_content}});
            }
            $body = ${${$message{attachment}[0]}{r_content}};
            if (${$message{attachment}[0]}{contenttype} =~ /^text\/html/i) {
               $body= html2text($body);
            }
            # remove this text attachment from the message's attachemnt list
            shift @{$message{attachment}};
         } else {
            $body = '';
         }
      } else {
         $body = $message{"body"} || '';
         # handle mail programs that send the body encoded
         if ($message{contenttype} =~ /^text/i) {
            if ($message{encoding} =~ /^quoted-printable/i) {
               $body= decode_qp($body);
            } elsif ($message{encoding} =~ /^base64/i) {
               $body= decode_base64($body);
            } elsif ($message{encoding} =~ /^x-uuencode/i) {
               $body= uudecode($body);
            }
         }
         # convert to pure text since user is going to edit it
         if ($message{contenttype} =~ /^text\/html/i) {
            $body= html2text($body);
         }
      }

      # reparagraph orig msg for better look in compose window
      if ( ($composetype eq "reply" || $composetype eq "replyall")
           && $prefs{'reparagraphorigmsg'} ) {
         $body=reparagraph($body, $prefs{'editcolumns'}-8);
      }

      # remove odds space or blank lines from body
      $body =~ s/(\r?\n){2,}/\n\n/g;
      $body =~ s/^\s+//;	
      $body =~ s/\s+$//;

      if ( $composetype eq "reply" || $composetype eq "replyall" ) {
         $subject = $message{"subject"} || '';
         $subject = "Re: " . $subject unless ($subject =~ /^re:/i);

         if (defined($message{"replyto"})) {
            $to = $message{"replyto"} || '';
         } else {
            $to = $message{"from"} || '';
         }
         if ($composetype eq "replyall") {
            $to .= "," . $message{"to"} if (defined($message{"to"}));
            $cc = $message{"cc"} if (defined($message{"cc"}));
            # remove tab or space surrounding comma 
            # in case old 'to' or 'cc' has tab which make snedmail unhappy
            $to=join(",", split(/\s*,\s*/,$to));
            $cc=join(",", split(/\s*,\s*/,$cc));
         }
         $replyto = $prefs{"replyto"} if (defined($prefs{"replyto"}));

         $inreplyto = $message{'messageid'};
         if ( $message{'references'} ne "" ) {
            $references = $message{'references'}." ".$message{'messageid'};
         } elsif ( $message{'inreplyto'} ne "" ) {
            $references = $message{'inreplyto'}." ".$message{'messageid'};
         } else {
            $references = $message{'messageid'};
         }

         if ($body =~ /[^\s]/) {
            $body =~ s/\n/\n\> /g;
            $body = "> " . $body;
         }
         if ($prefs{replywithorigmsg} eq 'at_beginning') {
            if (defined($prefs{"signature"})) {
               $body .= "\n\n\n".$prefs{"signature"};
            }
         } elsif ($prefs{replywithorigmsg} eq 'at_end') {
            $body = "---------- Original Message -----------\n".
                    "From: $message{'from'}\n".
                    "To: $message{'to'}\n".
                    "Sent: $message{'date'}\n".
                    "Subject: $message{'subject'}\n\n".
                    "$body\n".
                    "------- End of Original Message -------\n";
            if (defined($prefs{"signature"})) {
               $body = "\n\n\n".$prefs{"signature"}."\n\n".$body;
            } else {
               $body = "\n\n\n".$body;
            }
         } else {
            if (defined($prefs{"signature"})) {
               $body = "\n\n\n".$prefs{"signature"};
            } else {
               $body = "";
            }
         }


      } elsif ($composetype eq "forward" || $composetype eq "editdraft") {
         # carry attachments from old mesage to the new one
         if (defined(${$message{attachment}[0]}{header})) {
            my $attserial=time();
            ($attserial =~ /^(.+)$/) && ($attserial = $1);   # bypass taint check
            foreach my $attnumber (0 .. $#{$message{attachment}}) {
               $attserial++;
               open (ATTFILE, ">$config{'ow_etcdir'}/sessions/$thissession-att$attserial") or 
                  openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions/$thissession-att$attserial!");
               print ATTFILE ${$message{attachment}[$attnumber]}{header}, "\n\n", ${${$message{attachment}[$attnumber]}{r_content}};
               close ATTFILE;
            }
            ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();
         }

         $subject = $message{"subject"} || '';

         if ($composetype eq "editdraft") {
            $to = $message{"to"} if (defined($message{"to"}));
            $cc = $message{"cc"} if (defined($message{"cc"}));
            $bcc = $message{"bcc"} if (defined($message{"bcc"}));
            if (defined($message{"replyto"})) {
               $replyto = $message{"replyto"} 
            } else {
               $replyto = $prefs{"replyto"} if (defined($prefs{"replyto"}));
            }

            $inreplyto = $message{'inreplyto'};
            $references = $message{'references'};
            $priority = $message{"priority"} if (defined($message{"priority"}));

         } elsif ($composetype eq "forward") {
            $replyto = $prefs{"replyto"} if (defined($prefs{"replyto"}));
            $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);

            $inreplyto = $message{'messageid'};
            if ( $message{'references'} ne "" ) {
               $references = $message{'references'}." ".$message{'messageid'};
            } elsif ( $message{'inreplyto'} ne "" ) {
               $references = $message{'inreplyto'}." ".$message{'messageid'};
            } else {
               $references = $message{'messageid'};
            }

            if ($body =~ /[^\s]/) {
               $body = "\n".
                       "\n---------- Forwarded Message -----------\n".
                       "$body".
                       "\n------- End of Forwarded Message -------\n";
               $body .= "\n\n".$prefs{"signature"} if (defined($prefs{"signature"}));
            }
         }
      }

   } elsif ($composetype eq 'forwardasatt') {
      my $messageid = param("message_id");
      my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
      my $folderhandle=FileHandle->new();
      my $atthandle=FileHandle->new();

      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
      update_headerdb($headerdb, $folderfile);

      my @attr=get_message_attributes($messageid, $headerdb);

      my $fromemail=$prefs{'email'};
      foreach (keys %userfrom) {
         if ($attr{$_TO}=~/$_/) {
            $fromemail=$_; last;
         }
      }
      if ($userfrom{$fromemail}) {
         $from=qq|"$userfrom{$fromemail}" <$fromemail>|;
      } else {
         $from=qq|$fromemail|;
      }

      open($folderhandle, "$folderfile");
      my $attserial=time();
      ($attserial =~ /^(.+)$/) && ($attserial = $1);   # bypass taint check
      open ($atthandle, ">$config{'ow_etcdir'}/sessions/$thissession-att$attserial") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions/$thissession-att$attserial!");
      print $atthandle qq|Content-Type: message/rfc822;\n|,
                       qq|Content-Disposition: attachment; filename="Forward.msg"\n\n|;

      # copy message to be forwarded
      my $left=$attr[$_SIZE];
      seek($folderhandle, $attr[$_OFFSET], 0);

      # do not copy 1st line if it is the 'From ' delimiter 
      $_ = <$folderhandle>; $left-=length($_);
      if ( ! /^From / ) {
         print $atthandle $_;
      }
      # copy other lines with the 'From ' delimiter escaped
      while ($left>0) {
         $_ = <$folderhandle>; $left-=length($_);
         s/^From />From /;
         print $atthandle $_;
      }

      close $atthandle;
      close($folderhandle);

      filelock($folderfile, LOCK_UN);

      ($savedattsize, $r_attnamelist, $r_attfilelist) = getattlistinfo();

      $replyto = $prefs{"replyto"} if (defined($prefs{"replyto"}));
      $subject = $attr[$_SUBJECT];
      $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);

      $inreplyto = $message{'messageid'};
      if ( $message{'references'} ne "" ) {
         $references = $message{'references'}." ".$message{'messageid'};
      } elsif ( $message{'inreplyto'} ne "" ) {
         $references = $message{'inreplyto'}." ".$message{'messageid'};
      } else {
         $references = $message{'messageid'};
      }

      $body = "\n\n# Message forwarded as attachment\n";
      $body .= "\n\n".$prefs{"signature"} if (defined($prefs{"signature"}));

   } elsif ($composetype eq 'continue') {
      $body = "\n".$body;	# the form text area would eat leading \n, so we add it back here

   } else { # sendto or newmail
      $body .= "\n\n\n".$prefs{"signature"} if (defined($prefs{"signature"}));
   } 

   # convert between gb and big5
   if ( param('zhconvert') eq 'b2g' ) {
      $subject= b2g($subject);
      $body= b2g($body);
   } elsif ( param('zhconvert') eq 'g2b' ) {
      $subject= g2b($subject);
      $body= g2b($body);
   }

   printheader();
   
   $temphtml = qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;firstmessage=$firstmessage" title="$lang_text{'backto'} $printfolder"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/backtofolder.gif" border="0" ALT="$lang_text{'backto'} $printfolder"></a>\n|;
   if ($prefs{'language'} eq 'zh_CN.GB2312' ) {
       $temphtml .= qq| &nbsp; |.
                    qq|<a href="javascript:convert_b2g()" title="Big5 to GB"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/big52gb.gif" border="0" ALT="Big5 to GB"></a> \n|.
                    qq|<a href="javascript:convert_g2b()" title="GB to Big5"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/gb2big5.gif" border="0" ALT="GB to Big5"></a>\n|;
   } elsif ($prefs{'language'} eq 'zh_TW.Big5' ) {
       $temphtml .= qq| &nbsp; |.
                    qq|<a href="javascript:convert_g2b()" title="GB to Big5"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/gb2big5.gif" border="0" ALT="GB to Big5"></a> \n|.
                    qq|<a href="javascript:convert_b2g()" title="Big5 to GB"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/big52gb.gif" border="0" ALT="Big5 to GB"></a>\n|;
   }

   $html =~ s/\@\@\@BACKTOFOLDER\@\@\@/$temphtml/g;

   $temphtml = start_multipart_form(-name=>'composeform');

   $temphtml .= hidden(-name=>'action',
                       -default=>'sendmessage',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -default=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'composetype',
                       -default=>'continue',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sort',
                       -default=>$sort,
                       -override=>'1');
   $temphtml .= hidden(-name=>'keyword',
                       -default=>$keyword,
                       -override=>'1');
   $temphtml .= hidden(-name=>'searchtype',
                       -default=>$searchtype,
                       -override=>'1');
   $temphtml .= hidden(-name=>'firstmessage',
                       -default=>$firstmessage,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');
   $temphtml .= hidden(-name=>'deleteattfile',
                       -default=>'',
                       -override=>'1');
   $temphtml .= hidden(-name=>'zhconvert',
                       -default=>'',
                       -override=>'1');
   $temphtml .= hidden(-name=>'inreplyto',
                       -default=>$inreplyto,
                       -override=>'1');
   $temphtml .= hidden(-name=>'references',
                       -default=>$references,
                       -override=>'1');

   if (param("message_id")) {
      $temphtml .= hidden(-name=>'message_id',
                          -default=>param("message_id"),
                          -override=>'1');
   }
   $html =~ s/\@\@\@STARTCOMPOSEFORM\@\@\@/$temphtml/g;

   my @fromlist=();
   foreach (sort keys %userfrom) {
      if ($userfrom{$_}) {
         push(@fromlist, qq|"$userfrom{$_}" <$_>|);
      } else {
         push(@fromlist, qq|$_|);
      }
   }
   $temphtml = popup_menu(-name=>'from',
                          -"values"=>\@fromlist,
                          -default=>$from,
                          -override=>'1');

   $html =~ s/\@\@\@FROMMENU\@\@\@/$temphtml/;

   my @prioritylist=("urgent", "normal", "non-urgent");
   $temphtml = popup_menu(-name=>'priority',
                          -"values"=>\@prioritylist,
                          -default=>$priority || 'normal',
                          -labels=>\%lang_prioritylabels,
                          -override=>'1');

   $html =~ s/\@\@\@PRIORITYMENU\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'to',
                         -default=>$to,
                         -size=>'70',
                         -override=>'1').
               qq| <a href="javascript:GoAddressWindow('to')" title="$lang_text{'addressbook'}"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/addrbook.s.gif" valign=bottom border="0" ALT="$lang_text{'addressbook'}"></a>|;
   $html =~ s/\@\@\@TOFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'cc',
                         -default=>$cc,
                         -size=>'70',
                         -override=>'1').
               qq| <a href="javascript:GoAddressWindow('cc')" title="$lang_text{'addressbook'}"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/addrbook.s.gif" valign=bottom border="0" ALT="$lang_text{'addressbook'}"></a>|;
   $html =~ s/\@\@\@CCFIELD\@\@\@/$temphtml/g;
          
   $temphtml = textfield(-name=>'bcc',
                         -default=>$bcc,
                         -size=>'70',
                         -override=>'1').
               qq| <a href="javascript:GoAddressWindow('bcc')" title="$lang_text{'addressbook'}"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/addrbook.s.gif" valign=bottom border="0" ALT="$lang_text{'addressbook'}"></a>|;
   $html =~ s/\@\@\@BCCFIELD\@\@\@/$temphtml/g;
 
   $temphtml = textfield(-name=>'replyto',
                         -default=>$replyto,
                         -size=>'70',
                         -override=>'1');
   $html =~ s/\@\@\@REPLYTOFIELD\@\@\@/$temphtml/g;
   
   # table of attachment list 
   if ($#{$r_attnamelist}>=0) {
      $temphtml = "<table cellspacing='0' cellpadding='0' width='70%'><tr valign='bottom'>\n";

      $temphtml .= "<td><table cellspacing='0' cellpadding='0'>\n";
      for (my $i=0; $i<=$#{$r_attnamelist}; $i++) {
         my $attsize=int((-s "$config{'ow_etcdir'}/sessions/${$r_attfilelist}[$i]")/1024);
         my $blank="";
         if (${$r_attnamelist}[$i]=~/\.(txt|jpg|jpeg|gif|png|bmp)$/i) {
            $blank="target=_blank";
         }
         $temphtml .= qq|<tr valign=top>|.
                      qq|<td><a href="$config{'ow_cgiurl'}/openwebmail-viewatt.pl?sessionid=$thissession&amp;action=viewattfile&amp;attfile=${$r_attfilelist}[$i]" $blank><em>${$r_attnamelist}[$i]</em></a></td>|.
                      qq|<td nowrap align='right'>&nbsp;$attsize KB &nbsp;</td>|.
                      qq|<td nowrap><a href="javascript:DeleteAttFile('${$r_attfilelist}[$i]')">[$lang_text{'delete'}]</a></td>|.
                      qq|</tr>\n|;
      }
      $temphtml .= "</table></td>\n";

      $temphtml .= "<td align='right'>\n";
      if ( $savedattsize ) {
         $temphtml .= "<em>" . int($savedattsize/1024) . "KB";
         $temphtml .= " $lang_text{'of'} $config{'attlimit'} MB" if ( $config{'attlimit'} );
         $temphtml .= "</em>";
      }
      $temphtml .= "</td>";

      $temphtml .= "</tr></table>\n";
   } else {
      $temphtml="";
   }

   $temphtml .= filefield(-name=>'attachment',
                         -default=>'',
                         -size=>'60',
                         -override=>'1',
                         -tabindex=>'-1');
   $temphtml .= submit(-name=>"$lang_text{'add'}",
                       -value=>"$lang_text{'add'}",
                       -tabindex=>'-1'
                      );
   $html =~ s/\@\@\@ATTACHMENTFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'subject',
                         -default=>$subject,
                         -size=>'60',
                         -override=>'1');
   $html =~ s/\@\@\@SUBJECTFIELD\@\@\@/$temphtml/g;


   $temphtml = checkbox(-name=>'confirmreading',
                        -value=>'1',
                        -label=>'');

   $html =~ s/\@\@\@CONFIRMREADINGCHECKBOX\@\@\@/$temphtml/;

   $temphtml = textarea(-name=>'body',
                        -default=>$body,
                        -rows=>$prefs{'editrows'}||'20',
                        -columns=>$prefs{'editcolumns'}||'78',
                        -wrap=>'hard',
                        -override=>'1');
   $html =~ s/\@\@\@BODYAREA\@\@\@/$temphtml/g;

   $temphtml = submit(-name=>"$lang_text{'send'}",
                      -value=>"$lang_text{'send'}",
                      -onClick=>'return sendcheck();',
                      -override=>'1');
   $html =~ s/\@\@\@SENDBUTTON\@\@\@/$temphtml/g;

   $temphtml = submit("$lang_text{'savedraft'}");
   $html =~ s/\@\@\@SAVEDRAFTBUTTON\@\@\@/$temphtml/g;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-spell.pl",
                          -name=>'spellcheckform',
                          -target=>'SpellChecker').
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1').
               hidden(-name=>'form',
                      -default=>'',
                      -override=>'1').
               hidden(-name=>'field',
                      -default=>'',
                      -override=>'1').
               hidden(-name=>'string',
                      -default=>'',
                      -override=>'1');
   $html =~ s/\@\@\@STARTSPELLCHECKFORM\@\@\@/$temphtml/g;

   $temphtml = popup_menu(-name=>'dictionary',
                          -"values"=>$config{'spellcheck_dictionaries'},
                          -default=>$prefs{'dictionary'},
                          -override=>'1');

   $html =~ s/\@\@\@DICTIONARYMENU\@\@\@/$temphtml/;

   $temphtml = submit(-name=>'spellcheckbutton', 
                      -value=> $lang_text{'spellcheck'},
                      -onClick=>'spellcheck();',
                      -override=>'1');
   $html =~ s/\@\@\@SPELLCHECKBUTTON\@\@\@/$temphtml/g;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;
   
   if (param("message_id")) {
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl");
      $temphtml .= hidden(-name=>'action',
                          -default=>'readmessage',
                          -override=>'1');
      $temphtml .= hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1');
      $temphtml .= hidden(-name=>'keyword',
                          -default=>$keyword,
                          -override=>'1');
      $temphtml .= hidden(-name=>'searchtype',
                          -default=>$searchtype,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'headers',
                          -default=>$prefs{"headers"} || 'simple',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -default=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>param("message_id"),
                          -override=>'1');
   } else {
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl");
      $temphtml .= hidden(-name=>'action',
                          -default=>'displayheaders',
                          -override=>'1');
      $temphtml .= hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1');
      $temphtml .= hidden(-name=>'keyword',
                          -default=>$keyword,
                          -override=>'1');
      $temphtml .= hidden(-name=>'searchtype',
                          -default=>$searchtype,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -default=>$thissession,
                          -override=>'1');
   }
   $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/g;

   $temphtml = submit("$lang_text{'cancel'}");
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/g;

   print $html;

   printfooter();
}
############# END COMPOSEMESSAGE #################

############### SENDMESSAGE ######################
sub sendmessage {
   no strict 'refs';
   # user press 'add' button or click 'delete' link
   if (defined(param($lang_text{'add'})) 
    || param("deleteattfile") ne '' 
    || param("zhconvert") ne ''
    || ( defined(param($lang_text{'send'}))
         && param("to") eq '' 
         && param("cc") eq '' 
         && param("bcc") eq '') ) {
      composemessage();

   } else {
      # $localtime is used in delimiter line 'From ...' in folder file
      # $date is used in message header Date: xxxx
      my $localtime = scalar(localtime);
      my $dateserial= getdateserial();
      my @datearray = split(/ +/, $localtime);
      my $date = "$datearray[0], $datearray[2] $datearray[1] $datearray[4] $datearray[3] ".dst_adjust($config{'timeoffset'});

      my %userfrom=get_userfrom($loginname, $userrealname, "$folderdir/.from.book");
      my ($realname, $from);
      if (param('from')) {
         ($realname, $from)=email2nameaddr(param('from'));
      } else {
         ($realname, $from)=($userfrom{$prefs{'email'}}, $prefs{'email'});
      }

      $from =~ s/['"]/ /g;  # Get rid of shell escape attempts
      $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts
      ($realname =~ /^(.+)$/) && ($realname = '"'.$1.'"');
      ($from =~ /^(.+)$/) && ($from = $1);

      my $boundary = "----=OPENWEBMAIL_ATT_" . rand();
      my $to = param("to");
      my $cc = param("cc");
      my $bcc = param("bcc");
      my $replyto = param("replyto") || $prefs{"replyto"};
      my $subject = param("subject") || 'N/A';
      $subject =~ s/&#8364;/€/g;	# Euro symbo

      # fake a messageid for this message
      my $fakedid = $dateserial.'.M'.int(rand()*100000);
      if ($from =~ /@(.*)$/) {
         $fakedid="<$fakedid".'@'."$1>";
      } else {
         $fakedid="<$fakedid".'@'."$from>";
      }

      my $folder = param("folder");
      my $inreplyto = param("inreplyto");
      my $references = param("references");
      my $priority = param("priority");
      my $confirmreading = param("confirmreading");
      my $body = param("body");

      $body =~ s/\r//g;		# strip ^M characters from message. How annoying!
      $body =~ s/&#8364;/€/g;	# Euro symbo

      my $attachment = param("attachment");
      if ( $attachment ) {
         my $savedattsize=(getattlistinfo())[0];
         if ( ($config{'attlimit'}) && ( ( $savedattsize + (-s $attachment) ) > ($config{'attlimit'} * 1048576) ) ) {
            openwebmailerror ("$lang_err{'att_overlimit'} $config{'attlimit'} MB!");
         }
      }
      my $attname = $attachment;
      # Convert :: back to the ' like it should be.
      $attname =~ s/::/'/g;
      # Trim the path info from the filename
      $attname =~ s/^.*\\//;
      $attname =~ s/^.*\///;
      $attname =~ s/^.*://;

      my @attfilelist=();
      opendir (SESSIONSDIR, "$config{'ow_etcdir'}/sessions") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions!");
      while (defined(my $currentfile = readdir(SESSIONSDIR))) {
         if ($currentfile =~ /^($thissession-att\d+)$/) {
            push (@attfilelist, "$config{'ow_etcdir'}/sessions/$1");
         }
      }
      closedir (SESSIONSDIR);

      my $do_sendmsg=1;
      my $send_errstr="";
      my $send_errcount=0;

      my $do_savemsg=1;
      my $save_errstr="";
      my $save_errcount=0;

      my $smtp;
      my $smtperrfile="/tmp/.openwebmail.smtperr.$$";
      local (*STDERR);	# localize stderr to a new global variable

      my ($savefolder, $savefile, $savedb);
      my $messagestart=0;
      my $messagesize=0;

      if (defined(param($lang_text{'savedraft'}))) { # save msg to draft folder
         $savefolder = 'saved-drafts';
         $do_sendmsg=0;
         $do_savemsg=0 if  ($folderusage>=100);
      } else {					     # save msg to sent folder && send 
         $savefolder = 'sent-mail';
         $do_savemsg=0 if  ($folderusage>=100);
      }


      if ($do_sendmsg) { 
         my @recipients=();
         foreach my $recv ($to, $cc, $bcc) {
            next if ($recv eq "");
            foreach (str2list($recv)) {
               my $email=(email2nameaddr($_))[1];
               next if ($email eq "" || $email=~/\s/);
               push (@recipients, $email);
            }
         }

         # validate receiver email
         if ($#{$config{'allowed_receiverdomain'}}>=0) {
            foreach my $email (@recipients) {
               my $allowed=0;
               foreach my $token (@{$config{'allowed_receiverdomain'}}) {
                  if ($token eq 'ALL' || $email=~/\Q$token\E$/i) {
                     $allowed=1; last;
                  } elsif ($token eq 'NONE') {
                     last;
                  }
               }
               if (!$allowed) {
                  openwebmailerror($lang_err{'disallowed_receiverdomain'}." ( $email )");
               }
            }
         }

         # redirect stderr to smtperrfile
         ($smtperrfile =~ /^(.+)$/) && ($smtperrfile = $1);   # bypass taint check
         open(STDERR, ">$smtperrfile"); 
         select(STDERR); $| = 1; select(STDOUT);

         $smtp=Net::SMTP->new($config{'smtpserver'}, 
                              Port => $config{'smtpport'}, 
                              Timeout => 30, 
                              Hello => ${$config{'domainnames'}}[0], 
                              Debug=>1) or 
            openwebmailerror("$lang_err{'couldnt_open'} SMTP server $config{'smtpserver'}:$config{'smtpport'}!");
         $smtp->mail($from);

         if (! $smtp->recipient(@recipients, { SkipBad => 1 }) ) {
            close(STDERR);
            my $msg="$lang_err{'sendmail_error'}!".
                    readsmtperr($smtperrfile);
            unlink($smtperrfile);
            $smtp->reset();
            $smtp->quit();
            openwebmailerror($msg);
         }
         $smtp->data();
      }

      if ($do_savemsg) {
         ($savefile, $savedb)=get_folderfile_headerdb($user, $savefolder);

         if ( ! -f $savefile) {
            if (open (FOLDER, ">$savefile")) {
               close (FOLDER);
            } else {
               $save_errstr="$lang_err{'couldnt_open'} $savefile!";
               $save_errcount++;
               $do_savemsg=0;
            }
         }

         if ($save_errcount==0 && filelock($savefile, LOCK_EX|LOCK_NB)) {
            update_headerdb($savedb, $savefile);

            # remove message with same id from draft folder
            if ( $savefolder eq 'saved-drafts' && defined(param("message_id")) ) {
               my $removeoldone=0;
               my $messageid=param("message_id");
               my %HDB;

               filelock("$savedb$config{'dbm_ext'}", LOCK_EX);
               dbmopen(%HDB, $savedb, undef);
               if (defined($HDB{$messageid})) {
                  my @oldheaders=split(/@@@/, $HDB{$messageid});
                  if ($oldheaders[$_SUBJECT] eq $subject) {
                     $removeoldone=1;
                  }
               }
               dbmclose(%HDB);
               filelock("$savedb$config{'dbm_ext'}", LOCK_UN);

               if ($removeoldone) {
                  my @ids;
                  push (@ids, $messageid);
                  operate_message_with_ids("delete", \@ids, $savefile, $savedb);
               }
            }

            if (open (FOLDER, ">>$savefile") ) {
               $messagestart=tell(FOLDER);
            } else {
               $save_errstr="$lang_err{'couldnt_open'} $savefile!";
               $save_errcount++;
               $do_savemsg=0;
            }

         } else {
            $save_errstr="$lang_err{'couldnt_lock'} $savefile!";
            $save_errcount++;
            $do_savemsg=0;
         }
      } 

      # nothing to do, return error msg immediately
      if ($do_sendmsg==0 && $do_savemsg==0) {
         if ($save_errcount>0) {
            openwebmailerror($save_errstr);
         } else {
            my $protocol=get_protocol(); 
            print "Location: $protocol://$ENV{'HTTP_HOST'}$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
         }
      }

      # Add a 'From ' as the message delimeter before save a message
      # into sent-mail/saved-drafts folder 
      print FOLDER "From $user $localtime\n" || $save_errcount++ if ($do_savemsg && $save_errcount==0);

      my $tempcontent="";
      $tempcontent .= "From: $realname <$from>\n";
      $tempcontent .= "To: ".folding($to)."\n";
      $tempcontent .= "CC: ".folding($cc)."\n" if ($cc);
      $tempcontent .= "Bcc: ".folding($bcc)."\n" if ($bcc);
      $tempcontent .= "Reply-To: $replyto\n" if ($replyto);
      $tempcontent .= "Subject: $subject\n";
      $tempcontent .= "Date: $date\n";

      $tempcontent .= "Message-Id: $fakedid\n";

      $tempcontent .= "In-Reply-To: $inreplyto\n" if ($inreplyto);
      $tempcontent .= "References: $references\n" if ($references);
      $tempcontent .= "Priority: $priority\n" if ($priority && $priority ne 'normal');
      $tempcontent .= "X-Mailer: $config{'name'} $config{'version'} $config{'releasedate'}\n";
      $tempcontent .= "X-OriginatingIP: ".get_clientip()." ($loginname)\n";
      $tempcontent .= "MIME-Version: 1.0\n";
      if ($confirmreading) {
         if ($replyto) {
            $tempcontent .= "X-Confirm-Reading-To: $replyto\n";
            $tempcontent .= "Disposition-Notification-To: $replyto\n";
         } else {
            $tempcontent .= "X-Confirm-Reading-To: $from\n";
            $tempcontent .= "Disposition-Notification-To: $from\n";
         }
      }
      $smtp->datasend($tempcontent) || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
      print FOLDER    $tempcontent  || $save_errcount++ if ($do_savemsg && $save_errcount==0);

      # mark msg saved in sent/draft folder as read
      print FOLDER    "Status: R\n" || $save_errcount++ if ($do_savemsg && $save_errcount==0);

      my $contenttype;
      if ($attachment || $#attfilelist>=0 ) {
         $contenttype="multipart/mixed;";

         $tempcontent = qq|Content-Type: multipart/mixed;\n|.
                        qq|\tboundary="$boundary"\n\n|.
                        qq|This is a multi-part message in MIME format.\n\n|.
                        qq|--$boundary\n|.
                        qq|Content-Type: text/plain; charset=$lang_charset\n\n|;

         $smtp->datasend($tempcontent) || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
         print FOLDER    $tempcontent  || $save_errcount++ if ($do_savemsg && $save_errcount==0);

         $smtp->datasend($body, "\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
         $smtp->datasend($config{'mailfooter'}, "\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0 && $config{'mailfooter'}=~/[^\s]/);
         $body =~ s/^From />From /gm;
         print FOLDER    $body, "\n"  || $save_errcount++ if ($do_savemsg && $save_errcount==0);

         my $buff='';
         foreach (@attfilelist) {
            $smtp->datasend("\n--$boundary\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
            print FOLDER    "\n--$boundary\n"  || $save_errcount++ if ($do_savemsg && $save_errcount==0);
            open(ATTFILE, $_);

            while (read(ATTFILE, $buff, 32768)) {
               $smtp->datasend($buff) || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
               print FOLDER    $buff  || $save_errcount++ if ($do_savemsg && $save_errcount==0);
            }
            close(ATTFILE);
         }

         $smtp->datasend("\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
         print FOLDER    "\n"  || $save_errcount++ if ($do_savemsg && $save_errcount==0);

         if ($attachment) {
            my $attcontenttype;
            if (defined(uploadInfo($attachment))) {
               $attcontenttype = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
            } else {
               $attcontenttype = 'application/octet-stream';
            }
            $tempcontent = qq|--$boundary\nContent-Type: $attcontenttype;\n|.
                           qq|\tname="$attname"\n|.
                           qq|Content-Transfer-Encoding: base64\n\n|;

            $smtp->datasend($tempcontent) || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
            print FOLDER    $tempcontent  || $save_errcount++ if ($do_savemsg && $save_errcount==0);
            
            while (read($attachment, $buff, 600*57)) {
               $tempcontent=encode_base64($buff);
               $smtp->datasend($tempcontent) || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
               print FOLDER    $tempcontent  || $save_errcount++ if ($do_savemsg && $save_errcount==0);
            }

            $smtp->datasend("\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
            print FOLDER    "\n"  || $save_errcount++ if ($do_savemsg && $save_errcount==0);
         }
         $smtp->datasend("--$boundary--") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
         print FOLDER    "--$boundary--"  || $save_errcount++ if ($do_savemsg && $save_errcount==0);

         $smtp->datasend("\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
         print FOLDER   "\n\n" || $save_errcount++ if ($do_savemsg && $save_errcount==0);

      } else {
         $contenttype="text/plain; charset=$lang_charset";

         $smtp->datasend("Content-Type: text/plain; charset=$lang_charset\n\n", $body, "\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
         $smtp->datasend($config{'mailfooter'}, "\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0 && $config{'mailfooter'}=~/[^\s]/);

         $body =~ s/^From />From /gm;
         print FOLDER   "Content-Type: text/plain; charset=$lang_charset\n\n", $body, "\n\n" || $save_errcount++ if ($do_savemsg && $save_errcount==0);
      }

      if ($do_sendmsg) {
         if ($send_errcount==0) {
            $smtp->dataend();
            $smtp->quit();
            close(STDERR);
         } else {
            $smtp->reset();
            $smtp->quit();
            close(STDERR);
            $send_errstr="$lang_err{'send_err'}!".readsmtperr($smtperrfile);
         }
         unlink($smtperrfile);
      }
      

      if ($do_savemsg) {
         if ($save_errcount==0) {
            $messagesize=tell(FOLDER)-$messagestart if ($do_savemsg && $save_errcount==0);
            close(FOLDER);

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

            $attr[$_FROM]="$realname <$from>";
            $attr[$_DATE]=$dateserial;
            $attr[$_SUBJECT]=$subject;
            $attr[$_CONTENT_TYPE]=$contenttype;
            $attr[$_STATUS]="R";
            $attr[$_STATUS].="I" if ($priority eq 'urgent');

            # flags used by openwebmail internally
            $attr[$_STATUS].="T" if ($attachment || $#attfilelist>=0 );
            $attr[$_STATUS].="B" if ($lang_charset=~/big5/i);
            $attr[$_STATUS].="G" if ($lang_charset=~/gb2312/i);

            $attr[$_SIZE]=$messagesize;

            my %HDB;
            filelock("$savedb$config{'dbm_ext'}", LOCK_EX);
            dbmopen(%HDB, $savedb, 0600);
            $HDB{$fakedid}=join('@@@', @attr);
            $HDB{'ALLMESSAGES'}++;
            $HDB{'METAINFO'}=metainfo($savefile);
            dbmclose(%HDB);
            filelock("$savedb$config{'dbm_ext'}", LOCK_UN);
            filelock($savefile, LOCK_UN);

         } else {
            seek(FOLDER, $messagestart, 0);
            truncate(FOLDER, tell(FOLDER));
            close(FOLDER);

            my %HDB;
            filelock("$savedb$config{'dbm_ext'}", LOCK_EX);
            dbmopen(%HDB, $savedb, 0600);
            $HDB{'METAINFO'}=metainfo($savefile);
            dbmclose(%HDB);
            filelock("$savedb$config{'dbm_ext'}", LOCK_UN);
            filelock($savefile, LOCK_UN);
         }

      }

      # status update(mark referenced message as answered) and headerdb update
      #
      # this must be done AFTER the above do_savefolder block 
      # since the start of the savemessage would be changed by status_update
      # if the savedmessage is on the same folder as the answered message
      if ($do_sendmsg && $send_errcount==0 && $inreplyto) {
         my @checkfolders=();

         # if current folder is sent/draft folder, 
         # we try to find orig msg from other folders
         # Or we just check the current folder
         if ($folder eq "sent-mail" || $folder eq "saved-drafts" ) {
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
            my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldername);
            my (%HDB, $oldstatus, $found);

            dbmopen(%HDB, $headerdb, 0600);
            filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
            if (defined($HDB{$inreplyto})) {
               $oldstatus = (split(/@@@/, $HDB{$inreplyto}))[$_STATUS];
               $found=1;
            }
            filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
            dbmclose(%HDB);

            if ( $found ) {
               if ($oldstatus !~ /a/i) {
                  # try to mark answered if get filelock
                  if (filelock($folderfile, LOCK_EX|LOCK_NB)) { 
                     update_message_status($inreplyto, $oldstatus."A", $headerdb, $folderfile);
                     filelock("$folderfile", LOCK_UN);
                  }
               }
               last;
            }
         }
      }
      
      if ($send_errcount>0) {
         openwebmailerror($send_errstr);
      } elsif ($save_errcount>0) {
         openwebmailerror($save_errstr);
      } else {
         # delete attachments only if no error,
         # in case user trys resend, attachments could be available
         deleteattachments();

         # call getfolders to recalc used quota
         #getfolders(\@validfolders, \$folderusage); 
         #displayheaders();

         # we do redirect with hostname specified.
         # Since if we do redirect with only url, the url line in browser will
         # keep the same as refered_from url, which make the cgi with 
         # action=displayheaders invalid
         my $protocol=get_protocol(); 
         print "Location: $protocol://$ENV{'HTTP_HOST'}$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
      }
   }
}
############## END SENDMESSAGE ###################

##################### GETATTLISTINFO ###############################
sub getattlistinfo {
   my $currentfile;
   my @namelist=();
   my @filelist=();
   my $totalsize = 0;

   opendir (SESSIONSDIR, "$config{'ow_etcdir'}/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions!");

   my $attnum=-1;
   while (defined($currentfile = readdir(SESSIONSDIR))) {
      if ($currentfile =~ /^($thissession-att\d+)$/) {
         $attnum++;
         $currentfile = $1;
         $totalsize += ( -s "$config{'ow_etcdir'}/sessions/$currentfile" );

         push (@filelist, $currentfile);

         open (ATTFILE, "$config{'ow_etcdir'}/sessions/$currentfile");
         while (defined(my $line = <ATTFILE>)) {
            if ($line =~ s/^.+name="?([^"]+)"?.*$/$1/i) {
               $line = str2html($line);
               push (@namelist, $line);
               last;
            } elsif ($line =~ /^\s+$/ ) {
               push (@namelist, "attachment.$attnum");
               last; 
            }
         }
         close (ATTFILE);
      }
   }

   closedir (SESSIONSDIR);
   return ($totalsize, \@namelist, \@filelist);
}
##################### END GETATTLISTINFO ###########################

##################### DELETEATTACHMENTS ############################
sub deleteattachments {
   my $currentfile;
   opendir (SESSIONSDIR, "$config{'ow_etcdir'}/sessions") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions!");
   while (defined($currentfile = readdir(SESSIONSDIR))) {
      if ($currentfile =~ /^($thissession-att\d+)$/) {
         $currentfile = $1;
         unlink ("$config{'ow_etcdir'}/sessions/$currentfile");
      }
   }
   closedir (SESSIONSDIR);
}
#################### END DELETEATTACHMENTS #########################

################### DST_ADJUST #######################
# adjust timeoffset for DaySavingTime for outgoing message
sub dst_adjust {
   my $timeoffset=$_[0];
   
   if ( (localtime())[8] ) {
      if ($timeoffset =~ m|^([\+\-]\d\d)(\d\d)| ) {
         my ($h, $m)=($1, $2);
         $h++;
         if ($h>=0) {
            $timeoffset=sprintf("+%02d%02d", $h, $m);
         } else {
            $timeoffset=sprintf("-%02d%02d", abs($h), $m);
         }
      }
   }
   return $timeoffset;
}
################### END DST_ADJUST #######################

###################### FOLDING ###########################
# folding the to, cc, bcc field in case it violates the 998 char limit 
# defined in RFC 2822 2.2.3
sub folding {
   return($_[0]) if (length($_[0])<960);

   my ($folding, $line)=('', '');
   foreach my $token (str2list($_[0])) {
      if (length($line)+length($token) <960) {
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
###################### END FOLDING ########################

################### REPARAGRAPH #########################
sub reparagraph {
   my @lines=split("\n", $_[0]);
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
################### END REPARAGRAPH #########################

################### READSMTPERR ##########################
sub readsmtperr {
   my $content='';

   open(F, $_[0]);
   while (<F>) {
      $content.="$1\n" if (/(>>>.*$)/ || /(<<<.*$)/);
   }
   close(F);
   $content =qq|<form>|.
               textarea(-name=>'smtperror',
                        -default=>$content,
                        -rows=>'5',
                        -columns=>'72',
                        -wrap=>'soft',
                        -override=>'1').
             qq|</form>|;
   return($content);
}
################### END READSMTPERR ##########################
