#!/usr/bin/suidperl -T
#
# openwebmail-send.pl - mail composing and sending program
#

use vars qw($SCRIPT_DIR);
if ( $ENV{'SCRIPT_FILENAME'} =~ m!^(.*?)/[\w\d\-\.]+\.pl! || $0 =~ m!^(.*?)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\n\$SCRIPT_DIR not set in CGI script!\n"; exit 0; }
push (@INC, $SCRIPT_DIR, ".");

$ENV{PATH} = ""; # no PATH should be needed
$ENV{ENV} = "";      # no startup script for sh
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script
use Net::SMTP;

require "ow-shared.pl";
require "filelock.pl";
require "mime.pl";
require "iconv.pl";
require "maildb.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

openwebmail_init();
verifysession();

use vars qw($firstmessage);
use vars qw($sort);
use vars qw($searchtype $keyword $escapedkeyword);

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';
$searchtype = param("searchtype") || 'subject';
$keyword = param("keyword") || '';
$escapedkeyword = escapeURL($keyword);

# extern vars
use vars qw(%lang_folders %lang_text %lang_err %lang_prioritylabels);	# defined in lang/xy
use vars qw(%charset_convlist);	# defined in iconv.pl
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET);	# defined in maildb.pl

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

   filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) if (!$config{'dbmopen_haslock'});
   dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);
   @attr=split(/@@@/, $HDB{$messageid});
   dbmclose(%HDB);
   filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

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
         my $date = dateserial2datefield(gmtime2dateserial(), $prefs{'timeoffset'});

         my %userfrom=get_userfrom($loginname, $user, $userrealname, "$folderdir/.from.book");
         foreach (sort keys %userfrom) {
            if ($header=~/$_/) {
               $from=$_; last;
            }
         }
         my $realname=$userfrom{$from};
         $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts
         $from =~ s/['"]/ /g;  # Get rid of shell escape attempts

         # fake a messageid for this message
         my $fakedid = gmtime2dateserial().'.M'.int(rand()*100000);
         if ($from =~ /@(.*)$/) {
            $fakedid="<$fakedid".'@'."$1>";
         } else {
            $fakedid="<$fakedid".'@'."$from>";
         }

         my $smtp;
         $smtp=Net::SMTP->new($config{'smtpserver'},
                              Port => $config{'smtpport'},
                              Timeout => 120,
                              Hello => ${$config{'domainnames'}}[0]) or
            openwebmailerror("$lang_err{'couldnt_open'} SMTP server $config{'smtpserver'}:$config{'smtpport'}!");

         # SMTP SASL authentication (PLAIN only)
         if ($config{'smtpauth'}) {
            my $auth = $smtp->supports("AUTH");
            $smtp->auth($config{'smtpauth_username'}, $config{'smtpauth_password'}) or
               openwebmailerror("$lang_err{'network_server_error'}!<br>($config{'smtpserver'} - ".$smtp->message.")");
         }

         $smtp->mail($from);

         my @recipients=();
         foreach (str2list($to,0)) {
            my $email=(email2nameaddr($_))[1];
            next if ($email eq "" || $email=~/\s/);
            push (@recipients, $email);
         }
         if (! $smtp->recipient(@recipients, { SkipBad => 1 }) ) {
            $smtp->reset();
            $smtp->quit();
            openwebmailerror("$lang_err{'sendmail_error'}!");
         }

         $smtp->data();
         if ($realname) {
            $smtp->datasend("From: ".encode_mimewords(qq|"$realname" <$from>|, ('Charset'=>$prefs{'charset'}))."\n");
         } else {
            $smtp->datasend("From: ".encode_mimewords(qq|$from|, ('Charset'=>$prefs{'charset'}))."\n");
         }
         $smtp->datasend("To: ".encode_mimewords($to, ('Charset'=>$prefs{'charset'}))."\n");
         $smtp->datasend("Reply-To: ".encode_mimewords($prefs{'replyto'}, ('Charset'=>$prefs{'charset'}))."\n") if ($prefs{'replyto'});

         my $xmailer = $config{'name'};
         $xmailer .= " $config{'version'} $config{'releasedate'}" if ($config{'xmailer_has_version'});
         my $xoriginatingip = get_clientip();
         $xoriginatingip .= " ($loginname)" if ($config{'xoriginatingip_has_userid'});

         # reply with english if sender has different charset than us
         if ( $attr[$_CONTENT_TYPE]=~/charset="?\Q$prefs{'charset'}\E"?/i) {
            $smtp->datasend("Subject: ".encode_mimewords("$lang_text{'read'} - $attr[$_SUBJECT]",('Charset'=>$prefs{'charset'}))."\n",
                            "Date: $date\n",
                            "Message-Id: $fakedid\n",
                            "X-Mailer: $xmailer\n",
                            "X-OriginatingIP: $xoriginatingip\n",
                            "MIME-Version: 1.0\n",
                            "Content-Type: text/plain; charset=$prefs{'charset'}\n\n");
            $smtp->datasend("$lang_text{'yourmsg'}\n\n",
                            "  $lang_text{'to'}: $attr[$_TO]\n",
                            "  $lang_text{'subject'}: $attr[$_SUBJECT]\n",
                            "  $lang_text{'delivered'}: ", dateserial2str($attr[$_DATE], $prefs{'dateformat'}), "\n\n",
                            "$lang_text{'wasreadon1'} ", dateserial2str(localtime2dateserial(), $prefs{'dateformat'}), " $lang_text{'wasreadon2'}\n\n");
         } else {
            $smtp->datasend("Subject: ".encode_mimewords("Read - $attr[$_SUBJECT]", ('Charset'=>$prefs{'charset'}))."\n",
                            "Date: $date\n",
                            "Message-Id: $fakedid\n",
                            "X-Mailer: $xmailer\n",
                            "X-OriginatingIP: $xoriginatingip\n",
                            "MIME-Version: 1.0\n",
                            "Content-Type: text/plain; charset=iso-8859-1\n\n");
            $smtp->datasend("Your message\n\n",
                            "  To: $attr[$_TO]\n",
                            "  Subject: $attr[$_SUBJECT]\n",
                            "  Delivered: ", dateserial2str($attr[$_DATE], $prefs{'dateformat'}), "\n\n",
                            "was read on", dateserial2str(localtime2dateserial(), $prefs{'dateformat'}), ".\n\n");
         }
         # $smtp->datasend($prefs{'signature'},   "\n") if (defined($prefs{'signature'}));
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
   printfooter(1);
}
################ END REPLYRECEIPT ################

############### COMPOSEMESSAGE ###################
# 8 composetype: reply, replyall, forward, editdraft,
#                forwardasatt (orig msg as an att),
#                continue(used after adding attachment),
#                sendto(newmail with dest user),
#                none(newmail)
sub composemessage {
#   no strict 'refs';
   my $charset= param("charset") || $prefs{'charset'};
   my ($savedattsize, $r_attlist);

   if ( param("deleteattfile") ne '' ) { # user click 'del' link
      my $deleteattfile=param("deleteattfile");

      $deleteattfile =~ s/\///g;  # just in case someone gets tricky ...
      ($deleteattfile =~ /^(.+)$/) && ($deleteattfile = $1);   # untaint ...
      # only allow to delete attfiles belongs the $thissession
      if ($deleteattfile=~/^$thissession/) {
         unlink ("$config{'ow_sessionsdir'}/$deleteattfile");
      }
      ($savedattsize, $r_attlist) = getattlistinfo();

   } elsif (defined(param('addbutton'))) { # user press 'add' button
      ($savedattsize, $r_attlist) = getattlistinfo();
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
         if ($charset eq 'big5') {
            $attname =~ s|^.*[^\xA1-\xF9]\\||;	# dos path
         } elsif ($charset eq 'gb2312') {
            $attname =~ s|^.*[^\x81-\xFE]\\||;	# dos path
         } else {
            $attname =~ s|^.*\\||;		# dos path
         }
         $attname =~ s|^.*/||;	# unix path
         $attname =~ s|^.*:||;	# mac path and dos drive

         if (defined(uploadInfo($attachment))) {
#            my %info=%{uploadInfo($attachment)};
#            foreach my $k (keys %info) { log_time("$k -> $info{$k}"); }
            $content_type = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
         } else {
            $content_type = 'application/octet-stream';
         }

         my $attserial = time();
         open (ATTFILE, ">$config{'ow_sessionsdir'}/$thissession-att$attserial");
         print ATTFILE qq|Content-Type: $content_type;\n|,
                       qq|Content-Disposition: attachment; filename="|.encode_mimewords($attname, ('Charset'=>$charset)).qq|"\n|,
                       qq|Content-Transfer-Encoding: base64\n\n|;
         while (read($attachment, $attcontents, 600*57)) {
            $attcontents=encode_base64($attcontents);
            $savedattsize += length($attcontents);
            print ATTFILE $attcontents;
         }
         close ATTFILE;
         close($attachment);	# close tmpfile created by CGI.pm

         $attname = str2html($attname);

         my $attnum=$#{$r_attlist}+1;
         ${${$r_attlist}[$attnum]}{name}=$attname;
         ${${$r_attlist}[$attnum]}{namecharset}=$charset;
         ${${$r_attlist}[$attnum]}{file}="$thissession-att$attserial";
      }

   # usr press 'send' button but no receiver, keep editing
   } elsif ( defined(param('sendbutton')) &&
             param("to") eq '' && param("cc") eq '' && param("bcc") eq '' ) {
      ($savedattsize, $r_attlist) = getattlistinfo();

   } elsif (param('convto') ne "") {
      ($savedattsize, $r_attlist) = getattlistinfo();

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
   my $replyto = param("replyto") || $prefs{'replyto'} || '';
   my $subject = param("subject") || '';
   my $body = param("body") || '';
   my $inreplyto = param("inreplyto") || '';
   my $references = param("references") || '';
   my $priority = param("priority") || 'normal';	# normal/urgent/non-urgent
   my $statname = param("statname") || '';

   my %userfrom=get_userfrom($loginname, $user, $userrealname, "$folderdir/.from.book");

   if ( defined(param("from")) ) {
      $from=param("from");
   } elsif ($userfrom{$prefs{'email'}} ne "") {
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

      my $convfrom=param('convfrom');
      $convfrom=$message{'charset'} if ($convfrom eq 'none.msgcharset');

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

            # handle mail with both text and html version
            # rename html to other name so modified/forwarded text won't be overridden by html again
            if ( defined(%{$message{attachment}[1]}) &&
                 (${$message{attachment}[1]}{boundary} eq
		  ${$message{attachment}[0]}{boundary}) ) {
               # rename html attachment in the same alternative group
               if ( (${$message{attachment}[0]}{subtype}=~/alternative/i &&
                     ${$message{attachment}[1]}{subtype}=~/alternative/i &&
                     ${$message{attachment}[1]}{contenttype}=~/^text/i   &&
                     ${$message{attachment}[1]}{filename}=~/^Unknown\./ ) ||
               # rename next if this=unknow.txt and next=unknow.html
                    (${$message{attachment}[0]}{contenttype}=~/^text\/plain/i &&
                     ${$message{attachment}[0]}{filename}=~/^Unknown\./       &&
                     ${$message{attachment}[1]}{contenttype}=~/^text\/html/i  &&
                     ${$message{attachment}[1]}{filename}=~/^Unknown\./ )  ) {
                  ${$message{attachment}[1]}{filename}=~s/^Unknown/Original/;
                  ${$message{attachment}[1]}{header}=~s!^Content-Type: \s*text/html;!Content-Type: text/html;\n   name="OriginalMsg.htm";!i;
               }
            }
            # remove this text attachment from the message's attachemnt list
            shift @{$message{attachment}};
         } else {
            $body = '';
         }
      } else {
         $body = $message{'body'} || '';
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
         $subject = $message{'subject'} || '';
         if (defined($message{'replyto'}) && $message{'replyto'}=~/[^\s]/) {
            $to = $message{'replyto'} || '';
         } else {
            $to = $message{'from'} || '';
         }
         if ($composetype eq "replyall") {
            $to .= "," . $message{'to'} if (defined($message{'to'}) && $message{'to'}=~/[^\s]/);
            $cc = $message{'cc'} if (defined($message{'cc'}) && $message{'cc'}=~/[^\s]/);
         }

         if (is_convertable($convfrom, $prefs{'charset'}) ) {
            ($body, $subject, $to, $cc)=iconv($convfrom, $body,$subject,$to,$cc);
         }

         $subject = "Re: " . $subject unless ($subject =~ /^re:/i);
         # rm tab or space surrounding comma, in case old 'to' or 'cc' has tab which make sendmail unhappy
         if ($composetype eq "replyall") {
            $to=join(",", split(/\s*,\s*/,$to));
            $cc=join(",", split(/\s*,\s*/,$cc));
         }
         $replyto = $prefs{'replyto'} if (defined($prefs{'replyto'}));
         $inreplyto = $message{'messageid'};
         if ( $message{'references'} ne "" ) {
            $references = $message{'references'}." ".$message{'messageid'};
         } elsif ( $message{'inreplyto'} ne "" ) {
            $references = $message{'inreplyto'}." ".$message{'messageid'};
         } else {
            $references = $message{'messageid'};
         }

         my $stationery;
         if ($config{'enable_stationery'} && $statname ne '') {
            my ($name,$content,%stationery);
            if ( -f "$folderdir/.stationery.book" ) {
               open (STATBOOK,"$folderdir/.stationery.book") or
                  openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.stationery.book!");
               while (<STATBOOK>) {
                  ($name, $content) = split(/\@\@\@/, $_, 2);
                  chomp($name); chomp($content);
                  $stationery{escapeURL($name)} = unescapeURL($content);
               }
               close (STATBOOK) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.stationery.book!");
            }
            $stationery = $stationery{$statname};
         }

         if ($body =~ /[^\s]/) {
            $body =~ s/\n/\n\> /g;
            $body = "> " . $body;
         }
         if ($prefs{replywithorigmsg} eq 'at_beginning') {
            $body = "On $message{'date'}, ".(email2nameaddr($message{'from'}))[0]." wrote\n". $body if ($body=~/[^\s]/);
            $body .= "\n".$stationery."\n";
            if (defined($prefs{'signature'})) {
               $body .= "\n\n".$prefs{'signature'};
            }
         } elsif ($prefs{replywithorigmsg} eq 'at_end') {
            $body = "---------- Original Message -----------\n".
                    "From: $message{'from'}\n".
                    "To: $message{'to'}\n".
                    "Sent: $message{'date'}\n".
                    "Subject: $message{'subject'}\n\n".
                    "$body\n".
                    "------- End of Original Message -------\n";
            if (defined($prefs{'signature'})) {
               $body = "\n".$stationery."\n\n".$prefs{'signature'}."\n\n".$body;
            } else {
               $body = "\n".$stationery."\n\n".$body;
            }
         } else {
            if (defined($prefs{'signature'})) {
               $body = "\n".$stationery."\n\n".$prefs{'signature'};
            } else {
               $body = "\n".$stationery."\n";
            }
         }

      } elsif ($composetype eq "forward" || $composetype eq "editdraft") {
         # carry attachments from old mesage to the new one
         if (defined(${$message{attachment}[0]}{header})) {
            my $attserial=time();
            ($attserial =~ /^(.+)$/) && ($attserial = $1);   # untaint ...
            foreach my $attnumber (0 .. $#{$message{attachment}}) {
               $attserial++;
               if (${$message{attachment}[$attnumber]}{header} ne "" &&
                   defined(${${$message{attachment}[$attnumber]}{r_content}}) ) {
                  open (ATTFILE, ">$config{'ow_sessionsdir'}/$thissession-att$attserial") or
                     openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}/$thissession-att$attserial!");
                  print ATTFILE ${$message{attachment}[$attnumber]}{header}, "\n\n";
                  print ATTFILE ${${$message{attachment}[$attnumber]}{r_content}};
                  close ATTFILE;
               }
            }
            ($savedattsize, $r_attlist) = getattlistinfo();
         }

         $subject = $message{'subject'} || '';

         if ($composetype eq "editdraft") {
            $to = $message{'to'} if (defined($message{'to'}));
            $cc = $message{'cc'} if (defined($message{'cc'}));
            $bcc = $message{'bcc'} if (defined($message{'bcc'}));
            $replyto = $message{'replyto'} if (defined($message{'replyto'}));

            if (is_convertable($convfrom, $prefs{'charset'}) ) {
               ($body, $subject, $to, $cc, $bcc, $replyto)=iconv($convfrom, $prefs{'charset'}, $body,$subject,$to,$cc,$bcc,$replyto);
            }

            $replyto = $prefs{'replyto'} if ($replyto eq '' && defined($prefs{'replyto'}));
            $inreplyto = $message{'inreplyto'};
            $references = $message{'references'};
            $priority = $message{'priority'} if (defined($message{'priority'}));

         } elsif ($composetype eq "forward") {
            if (is_convertable($convfrom, $prefs{'charset'}) ) {
               ($body, $subject)=iconv($convfrom, $prefs{'charset'}, $body,$subject);
            }

            $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);
            $replyto = $prefs{'replyto'} if (defined($prefs{'replyto'}));
            $inreplyto = $message{'messageid'};
            if ( $message{'references'} ne "" ) {
               $references = $message{'references'}." ".$message{'messageid'};
            } elsif ( $message{'inreplyto'} ne "" ) {
               $references = $message{'inreplyto'}." ".$message{'messageid'};
            } else {
               $references = $message{'messageid'};
            }

            $body = "\n".
                    "\n---------- Forwarded Message -----------\n".
                    "From: $message{'from'}\n".
                    "To: $message{'to'}\n".
                    "Sent: $message{'date'}\n".
                    "Subject: $message{'subject'}\n\n".
                    "$body".
                    "\n------- End of Forwarded Message -------\n";
            $body .= "\n\n".$prefs{'signature'} if (defined($prefs{'signature'}));
         }
      }

   } elsif ($composetype eq 'forwardasatt') {
      my $messageid = param("message_id");
      my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
      my $folderhandle=FileHandle->new();
      my $atthandle=FileHandle->new();

      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
      if (update_headerdb($headerdb, $folderfile)<0) {
         filelock($folderfile, LOCK_UN);
         openwebmailerror("$lang_err{'couldnt_updatedb'} $headerdb$config{'dbm_ext'}");
      }

      my @attr=get_message_attributes($messageid, $headerdb);

      my $fromemail=$prefs{'email'};
      foreach (keys %userfrom) {
         if ($attr[$_TO]=~/$_/) {
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
      ($attserial =~ /^(.+)$/) && ($attserial = $1);   # untaint ...
      open ($atthandle, ">$config{'ow_sessionsdir'}/$thissession-att$attserial") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}/$thissession-att$attserial!");
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

      ($savedattsize, $r_attlist) = getattlistinfo();

      $subject = $attr[$_SUBJECT];
      if (is_convertable($attr[$_CHARSET], $prefs{'charset'}) ) {
         ($subject)=iconv($attr[$_CHARSET], $prefs{'charset'}, $subject);
      }

      $subject = "Fw: " . $subject unless ($subject =~ /^fw:/i);
      $replyto = $prefs{'replyto'} if (defined($prefs{'replyto'}));

      $inreplyto = $message{'messageid'};
      if ( $message{'references'} ne "" ) {
         $references = $message{'references'}." ".$message{'messageid'};
      } elsif ( $message{'inreplyto'} ne "" ) {
         $references = $message{'inreplyto'}." ".$message{'messageid'};
      } else {
         $references = $message{'messageid'};
      }

      $body = "\n\n# Message forwarded as attachment\n";
      $body .= "\n\n".$prefs{'signature'} if (defined($prefs{'signature'}));

   } elsif ($composetype eq 'continue') {
      my $convto=param('convto');

      $body = "\n".$body;	# the form text area would eat leading \n, so we add it back here
      if ($charset ne $convto && is_convertable($charset, $convto) ) {
         ($body, $subject, $from, $to, $cc, $bcc, $replyto)=iconv($charset, $convto,
                                                     $body,$subject,$from,$to,$cc,$bcc,$replyto);
         $charset=$convto;
      }
   } else { # sendto or newmail
      $body .= "\n\n\n".$prefs{'signature'} if (defined($prefs{'signature'}));
   }

   my ($html, $temphtml);

   if ($charset ne $prefs{'charset'}) {
      my @tmp=($prefs{'language'}, $prefs{'charset'});
      ($prefs{'language'}, $prefs{'charset'})=('en', $charset);

      require "$config{'ow_langdir'}/$prefs{'language'}";
      printheader();
      $printfolder = $lang_folders{$folder} || $folder || '';
      $html = readtemplate("composemessage.template");

      ($prefs{'language'}, $prefs{'charset'})=@tmp;
   } else {
      printheader();
      $html = readtemplate("composemessage.template");
   }
   $html = applystyle($html);

   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;sort=$sort&amp;keyword=$escapedkeyword&amp;searchtype=$searchtype&amp;firstmessage=$firstmessage"|). qq| \n|;
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
   $temphtml .= hidden(-name=>'inreplyto',
                       -default=>$inreplyto,
                       -override=>'1');
   $temphtml .= hidden(-name=>'references',
                       -default=>$references,
                       -override=>'1');
   $temphtml .= hidden(-name=>'charset',
                       -default=>$charset,
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

   # charset conversion menu
   my %ctlabels=( 'none' => $charset );
   my @ctlist=('none');
   if (defined($charset_convlist{$charset})) {
      foreach my $ct (@{$charset_convlist{$charset}}) {
         if (is_convertable($charset, $ct)) {
            $ctlabels{$ct}="$charset > $ct";
            push(@ctlist, $ct);
         }
      }
   }
   $temphtml = popup_menu(-name=>'convto',
                          -"values"=>\@ctlist,
                          -labels=>\%ctlabels,
                          -default=>'none',
                          -onChange=>'javascript:submit();',
                          -override=>'1');
   $html =~ s/\@\@\@CONVTOMENU\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'to',
                         -default=>$to,
                         -size=>'70',
                         -override=>'1').
               qq|\n |.iconlink("addrbook.s.gif", $lang_text{'addressbook'}, qq|href="javascript:GoAddressWindow('to')"|);
   $html =~ s/\@\@\@TOFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'cc',
                         -default=>$cc,
                         -size=>'70',
                         -override=>'1').
               qq|\n |.iconlink("addrbook.s.gif", $lang_text{'addressbook'}, qq|href="javascript:GoAddressWindow('cc')"|);
   $html =~ s/\@\@\@CCFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'bcc',
                         -default=>$bcc,
                         -size=>'70',
                         -override=>'1').
               qq|\n |.iconlink("addrbook.s.gif", $lang_text{'addressbook'}, qq|href="javascript:GoAddressWindow('bcc')"|);
   $html =~ s/\@\@\@BCCFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'replyto',
                         -default=>$replyto,
                         -size=>'55',
                         -override=>'1');
   $html =~ s/\@\@\@REPLYTOFIELD\@\@\@/$temphtml/g;

   $temphtml = checkbox(-name=>'confirmreading',
                        -value=>'1',
                        -label=>'');

   $html =~ s/\@\@\@CONFIRMREADINGCHECKBOX\@\@\@/$temphtml/;

   # table of attachment list
   if ($#{$r_attlist}>=0) {
      $temphtml = "<table cellspacing='0' cellpadding='0' width='70%'><tr valign='bottom'>\n";

      $temphtml .= "<td><table cellspacing='0' cellpadding='0'>\n";
      for (my $i=0; $i<=$#{$r_attlist}; $i++) {
         my $attsize=int((-s "$config{'ow_sessionsdir'}/${${$r_attlist}[$i]}{file}")/1024);
         my $blank="";
         if (${${$r_attlist}[$i]}{name}=~/\.(txt|jpg|jpeg|gif|png|bmp)$/i) {
            $blank="target=_blank";
         }
         if (${${$r_attlist}[$i]}{namecharset} &&
             is_convertable(${${$r_attlist}[$i]}{namecharset}, $charset) ) {
            (${${$r_attlist}[$i]}{name})=iconv(${${$r_attlist}[$i]}{namecharset}, $charset, 
                                             ${${$r_attlist}[$i]}{name});
         }
         $temphtml .= qq|<tr valign=top>|.
                      qq|<td><a href="$config{'ow_cgiurl'}/openwebmail-viewatt.pl?sessionid=$thissession&amp;action=viewattfile&amp;attfile=${${$r_attlist}[$i]}{file}" $blank><em>${${$r_attlist}[$i]}{name}</em></a></td>|.
                      qq|<td nowrap align='right'>&nbsp;$attsize KB &nbsp;</td>|.
                      qq|<td nowrap><a href="javascript:DeleteAttFile('${${$r_attlist}[$i]}{file}')">[$lang_text{'delete'}]</a></td>|.
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
                         -size=>'55',
                         -override=>'1');
   $temphtml .= submit(-name=>"addbutton",
                       -value=>"$lang_text{'add'}");
   $html =~ s/\@\@\@ATTACHMENTFIELD\@\@\@/$temphtml/g;

   $temphtml = textfield(-name=>'subject',
                         -default=>$subject,
                         -size=>'55',
                         -override=>'1');
   $html =~ s/\@\@\@SUBJECTFIELD\@\@\@/$temphtml/g;

   my $backupsent=$prefs{'backupsentmsg'};
   if (defined(param("backupsent"))) {
      $backupsent=param("backupsent");
   }
   $temphtml = checkbox(-name=>'backupsentmsg',
                        -value=>'1',
                        -checked=>$backupsent,
                        -label=>'');

   $html =~ s/\@\@\@BACKUPSENTMSGCHECKBOX\@\@\@/$temphtml/;

   $temphtml = textarea(-name=>'body',
                        -default=>$body,
                        -rows=>$prefs{'editrows'}||'20',
                        -columns=>$prefs{'editcolumns'}||'78',
                        -wrap=>'hard',
                        -override=>'1');
   $html =~ s/\@\@\@BODYAREA\@\@\@/$temphtml/g;


   # 4 buttons: send, savedraft, spellcheck, cancel

   $temphtml=qq|<table cellspacing="2" cellpadding="2" border="0"><tr>|;
   $temphtml.=qq|<td align="center">|.
              submit(-name=>"sendbutton",
                     -value=>"$lang_text{'send'}",
                     -onClick=>'return sendcheck();',
                     -override=>'1').
              qq|&nbsp;&nbsp;</td>\n|;

   $temphtml.=qq|<td align="center">|.
              submit(-name=>"savedraftbutton",
                     -value=>"$lang_text{'savedraft'}",
                     -override=>'1').
              qq|&nbsp;&nbsp;</td>\n|;

   $temphtml.=qq|<td align="center">|.
              popup_menu(-name=>'dictionary2',
                         -"values"=>$config{'spellcheck_dictionaries'},
                         -default=>$prefs{'dictionary'},
                         -onChange=>"JavaScript:document.spellcheckform.dictionary.value=this.value;",
                         -override=>'1')." ".
              button(-name=>'spellcheckbutton',
                     -value=> $lang_text{'spellcheck'},
                     -onClick=>'spellcheck(); document.spellcheckform.submit();',
                     -override=>'1').
              qq|&nbsp;&nbsp;</td>\n|;

   $temphtml.=qq|<td align="center">|.
              button(-name=>'cancelbutton',
                      -value=> $lang_text{'cancel'},
                      -onClick=>'document.cancelform.submit();',
                      -override=>'1').
              qq|&nbsp;&nbsp;</td>\n|;
   $temphtml.=qq|</tr></table>\n|;

   if ($prefs{'sendbuttonposition'} eq 'after') {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@//g;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$temphtml/g;
   } elsif ($prefs{'sendbuttonposition'} eq 'both') {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@/$temphtml/g;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$temphtml/g;
   } else {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@/$temphtml/g;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@//g;
   }

   # spellcheck form
   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-spell.pl",
                          -name=>'spellcheckform',
                          -target=>'_spellcheck').
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
                      -override=>'1').
               hidden(-name=>'dictionary',
                      -default=>$prefs{'dictionary'},
                      -override=>'1');
   $html =~ s/\@\@\@STARTSPELLCHECKFORM\@\@\@/$temphtml/g;

   # cancel form
   if (param("message_id")) {
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-read.pl",
                             -name=>'cancelform');
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
                          -default=>$prefs{'headers'} || 'simple',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -default=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>param("message_id"),
                          -override=>'1');
   } else {
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-main.pl",
                             -name=>'cancelform');
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

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   print $html;

   if ($charset ne $prefs{'charset'}) {
      my @tmp=($prefs{'language'}, $prefs{'charset'});
      ($prefs{'language'}, $prefs{'charset'})=('en', $charset);
      printfooter(2);
      ($prefs{'language'}, $prefs{'charset'})=@tmp;
   } else {
      printfooter(2);
   }
}
############# END COMPOSEMESSAGE #################

############### SENDMESSAGE ######################
sub sendmessage {
   no strict 'refs';
   # goto composemessage if !savedraft && !send
   if ( !defined(param('savedraftbutton')) &&
        !(defined(param('sendbutton')) && (param("to")||param("cc")||param("bcc")))  ) {
      return(composemessage());
   }

   my %userfrom=get_userfrom($loginname, $user, $userrealname, "$folderdir/.from.book");
   my ($realname, $from);
   if (param('from')) {
      ($realname, $from)=_email2nameaddr(param('from')); # use _email2nameaddr since it may return null name
   } else {
      ($realname, $from)=($userfrom{$prefs{'email'}}, $prefs{'email'});
   }
   $from =~ s/['"]/ /g;  # Get rid of shell escape attempts
   $realname =~ s/['"]/ /g;  # Get rid of shell escape attempts

   my $dateserial=gmtime2dateserial();
   my $date = dateserial2datefield($dateserial, $prefs{'timeoffset'});

   my $boundary = "----=OPENWEBMAIL_ATT_" . rand();
   my $to = param("to");
   my $cc = param("cc");
   my $bcc = param("bcc");
   my $replyto = param("replyto") || $prefs{'replyto'};
   my $subject = param("subject") || 'N/A';
#   $subject =~ s/&#8364;/€/g;	# Euro symbo

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
   my $charset = param("charset") || $prefs{'charset'};
   my $priority = param("priority");
   my $confirmreading = param("confirmreading");
   my $body = param("body");

   my $attachment = param("attachment");
   my $attheader;
   if ( $attachment ) {
      my $savedattsize=(getattlistinfo())[0];
      if ( ($config{'attlimit'}) && ( ( $savedattsize + (-s $attachment) ) > ($config{'attlimit'} * 1048576) ) ) {
         openwebmailerror ("$lang_err{'att_overlimit'} $config{'attlimit'} MB!");
      }
      my $attcontenttype;
      if (defined(uploadInfo($attachment))) {
         $attcontenttype = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
      } else {
         $attcontenttype = 'application/octet-stream';
      }
      my $attname = $attachment;
      # Convert :: back to the ' like it should be.
      $attname =~ s/::/'/g;
      # Trim the path info from the filename
      if ($charset eq 'big5') {
         $attname =~ s|^.*[^\xA1-\xF9]\\||;	# dos path
      } elsif ($charset eq 'gb2312') {
         $attname =~ s|^.*[^\x81-\xFE]\\||;	# dos path
      } else {
         $attname =~ s|^.*\\||;		# dos path
      }
      $attname =~ s|^.*/||;	# unix path
      $attname =~ s|^.*:||;	# mac path and dos drive

      $attheader = qq|Content-Type: $attcontenttype;\n|.
                   qq|\tname="|.encode_mimewords($attname, ('Charset'=>$charset)).qq|"\n|.
                   qq|Content-Transfer-Encoding: base64\n|;
   }
   my @attfilelist=();
   opendir (SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}!");
   while (defined(my $currentfile = readdir(SESSIONSDIR))) {
      if ($currentfile =~ /^($thissession-att\d+)$/) {
         push (@attfilelist, "$config{'ow_sessionsdir'}/$1");
      }
   }
   closedir (SESSIONSDIR);

   # convert message to prefs{'sendcharset'}
   if ($prefs{'sendcharset'} ne 'sameascomposing' &&
       is_convertable($charset, $prefs{'sendcharset'}) ) {
      ($from,$replyto,$to,$cc,$subject,$body)=iconv($charset, $prefs{'sendcharset'},
   						$from,$replyto,$to,$cc,$subject,$body);
      $charset=$prefs{'sendcharset'};
   }
   $body =~ s/\r//g;		# strip ^M characters from message. How annoying!
#   $body =~ s/&#8364;/€/g;	# Euro symbo

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

   if (defined(param('savedraftbutton'))) { # save msg to draft folder
      $savefolder = 'saved-drafts';
      $do_sendmsg=0;
      $do_savemsg=0 if  ($folderusage>=100);
   } else {					     # save msg to sent folder && send
      $savefolder = 'sent-mail';
      $do_savemsg=0 if  ($folderusage>=100 || param("backupsentmsg")==0 );
   }

   if ($do_sendmsg) {
      my @recipients=();
      foreach my $recv ($to, $cc, $bcc) {
         next if ($recv eq "");
         foreach (str2list($recv,0)) {
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
               if (lc($token) eq 'all' || $email=~/\Q$token\E$/i) {
                  $allowed=1; last;
               } elsif (lc($token) eq 'none') {
                  last;
               }
            }
            if (!$allowed) {
               openwebmailerror($lang_err{'disallowed_receiverdomain'}." ( $email )");
            }
         }
      }

      # redirect stderr to smtperrfile
      ($smtperrfile =~ /^(.+)$/) && ($smtperrfile = $1);   # untaint ...
      open(STDERR, ">$smtperrfile");
      select(STDERR); $| = 1; select(STDOUT);

      if ( !($smtp=Net::SMTP->new($config{'smtpserver'},
                           Port => $config{'smtpport'},
                           Timeout => 120,
                           Hello => ${$config{'domainnames'}}[0],
                           Debug=>1)) ) {
         $send_errcount++;
         $send_errstr="$lang_err{'couldnt_open'} SMTP server $config{'smtpserver'}:$config{'smtpport'}!";
      }

      # SMTP SASL authentication (PLAIN only)
      if ($config{'smtpauth'} && $send_errcount==0) {
         my $auth = $smtp->supports("AUTH");
         if (! $smtp->auth($config{'smtpauth_username'}, $config{'smtpauth_password'}) ) {
            $send_errcount++;
            $send_errstr="$lang_err{'network_server_error'}!<br>($config{'smtpserver'} - ".$smtp->message.")";
         }
      }

      $smtp->mail($from)                              || $send_errcount++ if ($send_errcount==0);
      $smtp->recipient(@recipients, { SkipBad => 1 }) || $send_errcount++ if ($send_errcount==0);
      $smtp->data()                                   || $send_errcount++ if ($send_errcount==0);

      # save message to draft if smtp error, Dattola Filippo 06/20/2002
      if ($send_errcount>0 && $folderusage<100) {
         $do_savemsg = 1;
         $savefolder = 'saved-drafts';
	 }
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
         if (update_headerdb($savedb, $savefile)<0) {
            filelock($savefile, LOCK_UN);
            openwebmailerror("$lang_err{'couldnt_updatedb'} $savedb$config{'dbm_ext'}");
         }
         # remove message with same id from draft folder
         if ( $savefolder eq 'saved-drafts' && defined(param("message_id")) ) {
            my $removeoldone=0;
            my $messageid=param("message_id");
            my %HDB;

            filelock("$savedb$config{'dbm_ext'}", LOCK_EX) if (!$config{'dbmopen_haslock'});
            dbmopen(%HDB, "$savedb$config{'dbmopen_ext'}", undef);
            if (defined($HDB{$messageid})) {
               my @oldheaders=split(/@@@/, $HDB{$messageid});
               if ($oldheaders[$_SUBJECT] eq $subject) {
                  $removeoldone=1;
               }
            }
            dbmclose(%HDB);
            filelock("$savedb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});

            if ($removeoldone) {
               my @ids;
               push (@ids, $messageid);
               operate_message_with_ids("delete", \@ids, $savefile, $savedb);
            }
         }

         if (open (FOLDER, ">>$savefile") ) {
            seek(FOLDER, 0, 2);	# seek end manually to cover tell() bug in perl 5.8
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
         print "Location: $config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
      }
   }

   # Add a 'From ' as the message delimeter before save a message
   # into sent-mail/saved-drafts folder
   my $delimiter;
   if ($config{'delimiter_use_GMT'}) {
      $delimiter=dateserial2delimiter(gmtime2dateserial(), "");
   } else {
      $delimiter=dateserial2delimiter(localtime2dateserial(), "");
   }
   print FOLDER "From $user $delimiter\n" || $save_errcount++ if ($do_savemsg && $save_errcount==0);

   my $tempcontent="";
   if ($realname) {
      $tempcontent .= "From: ".encode_mimewords(qq|"$realname" <$from>|, ('Charset'=>$charset))."\n";
   } else {
      $tempcontent .= "From: ".encode_mimewords(qq|$from|, ('Charset'=>$charset))."\n";
   }
   $tempcontent .= "To: ".encode_mimewords(folding($to), ('Charset'=>$charset))."\n";
   $tempcontent .= "CC: ".encode_mimewords(folding($cc), ('Charset'=>$charset))."\n" if ($cc);
   $smtp->datasend($tempcontent) || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
   print FOLDER    $tempcontent  || $save_errcount++ if ($do_savemsg && $save_errcount==0);

   if ($bcc) {	# put bcc header in folderfile only, not in SMTP session
      $tempcontent = "Bcc: ".encode_mimewords(folding($bcc), ('Charset'=>$charset))."\n";
      print FOLDER    $tempcontent  || $save_errcount++ if ($do_savemsg && $save_errcount==0);
   }

   $tempcontent="";
   $tempcontent .= "Reply-To: ".encode_mimewords($replyto, ('Charset'=>$charset))."\n" if ($replyto);
   $tempcontent .= "Subject: ".encode_mimewords($subject, ('Charset'=>$charset))."\n";
   $tempcontent .= "Date: $date\n";

   $tempcontent .= "Message-Id: $fakedid\n";

   $tempcontent .= "In-Reply-To: $inreplyto\n" if ($inreplyto);
   $tempcontent .= "References: $references\n" if ($references);
   $tempcontent .= "Priority: $priority\n" if ($priority && $priority ne 'normal');

   my $xmailer = $config{'name'};
   $xmailer .= " $config{'version'} $config{'releasedate'}" if ($config{'xmailer_has_version'});
   my $xoriginatingip = get_clientip();
   $xoriginatingip .= " ($loginname)" if ($config{'xoriginatingip_has_userid'});

   $tempcontent .= "X-Mailer: $xmailer\n";
   $tempcontent .= "X-OriginatingIP: $xoriginatingip\n";
   $tempcontent .= "MIME-Version: 1.0\n";
   if ($confirmreading) {
      if ($replyto) {
         $tempcontent .= "X-Confirm-Reading-To: ".encode_mimewords($replyto, ('Charset'=>$charset))."\n";
         $tempcontent .= "Disposition-Notification-To: ".encode_mimewords($replyto, ('Charset'=>$charset))."\n";
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
                     qq|Content-Type: text/plain; charset=$charset\n\n|;

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
         $tempcontent = qq|--$boundary\n|.$attheader.qq|\n|;
         $smtp->datasend($tempcontent) || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
         print FOLDER    $tempcontent  || $save_errcount++ if ($do_savemsg && $save_errcount==0);

         while (read($attachment, $buff, 600*57)) {
            $tempcontent=encode_base64($buff);
            $smtp->datasend($tempcontent) || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
            print FOLDER    $tempcontent  || $save_errcount++ if ($do_savemsg && $save_errcount==0);
         }
         close($attachment);	# close tmpfile created by CGI.pm

         $smtp->datasend("\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
         print FOLDER    "\n"  || $save_errcount++ if ($do_savemsg && $save_errcount==0);
      }
      $smtp->datasend("--$boundary--") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
      print FOLDER    "--$boundary--"  || $save_errcount++ if ($do_savemsg && $save_errcount==0);

      $smtp->datasend("\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
      print FOLDER   "\n\n" || $save_errcount++ if ($do_savemsg && $save_errcount==0);

   } else {
      $contenttype="text/plain; charset=$charset";

      $smtp->datasend("Content-Type: text/plain; charset=$charset\n\n", $body, "\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0);
      $smtp->datasend($config{'mailfooter'}, "\n") || $send_errcount++ if ($do_sendmsg && $send_errcount==0 && $config{'mailfooter'}=~/[^\s]/);

      $body =~ s/^From />From /gm;
      print FOLDER   "Content-Type: text/plain; charset=$charset\n\n", $body, "\n\n" || $save_errcount++ if ($do_savemsg && $save_errcount==0);
   }

   if ($do_sendmsg) {
      if ($send_errcount==0) {
         $smtp->dataend();
         $smtp->quit();
         close(STDERR);
      } else {
         if ($smtp) { # close smtp only if it was sucessfully opened
            $smtp->reset();
            $smtp->quit();
            $send_errstr="$lang_err{'sendmail_error'}!".readsmtperr($smtperrfile) if ($send_errstr eq "");
         }
         close(STDERR);
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

         if ($realname) {
            $attr[$_FROM]=qq|"$realname" <$from>|;
         } else {
            $attr[$_FROM]=qq|$from|;
         }
         $attr[$_DATE]=$dateserial;
         $attr[$_SUBJECT]=$subject;
         $attr[$_CONTENT_TYPE]=$contenttype;
         $attr[$_STATUS]="R";
         $attr[$_STATUS].="I" if ($priority eq 'urgent');

         # flags used by openwebmail internally
         $attr[$_STATUS].="T" if ($attachment || $#attfilelist>=0 );

         $attr[$_SIZE]=$messagesize;
         $attr[$_REFERENCES]=$references;
         $attr[$_CHARSET]=$charset;

         my %HDB;
         filelock("$savedb$config{'dbm_ext'}", LOCK_EX) if (!$config{'dbmopen_haslock'});
         dbmopen(%HDB, "$savedb$config{'dbmopen_ext'}", 0600);
         $HDB{$fakedid}=join('@@@', @attr);
         $HDB{'ALLMESSAGES'}++;
         $HDB{'METAINFO'}=metainfo($savefile);
         dbmclose(%HDB);
         filelock("$savedb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
         filelock($savefile, LOCK_UN);

      } else {
         seek(FOLDER, $messagestart, 0);
         truncate(FOLDER, tell(FOLDER));
         close(FOLDER);

         my %HDB;
         filelock("$savedb$config{'dbm_ext'}", LOCK_EX) if (!$config{'dbmopen_haslock'});
         dbmopen(%HDB, "$savedb$config{'dbmopen_ext'}", 0600);
         $HDB{'METAINFO'}=metainfo($savefile);
         dbmclose(%HDB);
         filelock("$savedb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
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

         dbmopen(%HDB, "$headerdb$config{'dbmopen_ext'}", 0600);
         filelock("$headerdb$config{'dbm_ext'}", LOCK_EX) if (!$config{'dbmopen_haslock'});
         if (defined($HDB{$inreplyto})) {
            $oldstatus = (split(/@@@/, $HDB{$inreplyto}))[$_STATUS];
            $found=1;
         }
         filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
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
      print "Location: $config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage\n\n";
   }
}
############## END SENDMESSAGE ###################

##################### GETATTLISTINFO ###############################
sub getattlistinfo {
   my $currentfile;
   my @attlist=();
   my $totalsize = 0;

   opendir (SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}!");

   my $attnum=-1;
   while (defined($currentfile = readdir(SESSIONSDIR))) {
      if ($currentfile =~ /^($thissession-att\d+)$/) {
         $attnum++;
         $currentfile = $1;
         $totalsize += ( -s "$config{'ow_sessionsdir'}/$currentfile" );

         ${$attlist[$attnum]}{file}=$currentfile;

         open (ATTFILE, "$config{'ow_sessionsdir'}/$currentfile");
         while (defined(my $line = <ATTFILE>)) {
            if ($line =~ s/^.+name="?([^"]+)"?.*$/$1/i) {
               ${$attlist[$attnum]}{namecharset}=lc($1) if ($line =~ m{=\?([^?]*)\?[bq]\?[^?]+\?=}xi);
               $line = decode_mimewords($line);
               $line = str2html($line);
               ${$attlist[$attnum]}{name}=$line;
               last;
            } elsif ($line =~ /^\s+$/ ) {
               ${$attlist[$attnum]}{name}="attachment.$attnum";
               ${$attlist[$attnum]}{namecharset}='';
               last;
            }
         }
         close (ATTFILE);
      }
   }

   closedir (SESSIONSDIR);

   return ($totalsize, \@attlist);
}
##################### END GETATTLISTINFO ###########################

##################### DELETEATTACHMENTS ############################
sub deleteattachments {
   my (@delfiles, $attfile);
   opendir (SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_sessionsdir'}!");
   while (defined($attfile = readdir(SESSIONSDIR))) {
      if ($attfile =~ /^($thissession-att\d+)$/) {
         $attfile = $1;
         push(@delfiles, "$config{'ow_sessionsdir'}/$attfile");
      }
   }
   closedir (SESSIONSDIR);
   unlink(@delfiles) if ($#delfiles>=0);
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
   foreach my $token (str2list($_[0],0)) {
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
