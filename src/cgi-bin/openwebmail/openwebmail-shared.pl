#
# routines shared by openwebmail.pl and openwebmail-prefs.pl

############### GET_SPOOLFILE_FOLDERDB ################
sub get_spoolfile_headerdb {
   my ($username, $foldername)=@_;
   my ($spoolfile, $headerdb);

   if ($foldername eq 'INBOX') {
      if ($homedirspools eq "yes") {
         $spoolfile = "$homedir/$homedirspoolname";
      } elsif ($hashedmailspools eq "yes") {
         $username =~ /^(.)(.)/;
         my $firstchar = $1;
         my $secondchar = $2;
         $spoolfile = "$mailspooldir/$firstchar/$secondchar/$username";
      } else {
         $spoolfile = "$mailspooldir/$username";
      }
      $headerdb="$folderdir/.$username";

   } elsif ($foldername eq 'DELETE') {
      $spoolfile = $headerdb ='';

   } elsif ( ( $homedirfolders eq 'yes' ) || 
      ($foldername eq 'SAVED') || ($foldername eq 'SENT') || 
      ($foldername eq 'DRAFT') || ($foldername eq 'TRASH') ) {
      $spoolfile = "$folderdir/$foldername";
      $headerdb="$folderdir/.$foldername";

   } else {
      $spoolfile = "$folderdir/$foldername.folder";
      $headerdb= "$folderdir/.$foldername.folder";
   }

   return($spoolfile, $headerdb);
}

sub set_euid_egid_umask {
   my ($uid, $gid, $umask)=@_;
   # chnage egid and euid if data is located in user dir
   if ( ( ($homedirfolders eq 'yes') || ($homedirspools eq 'yes') ) && ($> == 0) ) {
      $) = $gid;
      $> = $uid;
      umask($umask); # make sure only owner can read/write
   }
}


############### GET_SPOOLFILE_FOLDERDB ################


############## VERIFYSESSION ########################
local $validsession=0;
sub verifysession {
   if ($validsession == 1) {
      return 1;
   }
   if ( -M "$openwebmaildir/$thissession" > $sessiontimeout || !(-e "$openwebmaildir/$thissession")) {
      my $html = '';
      printheader();
      open (TIMEOUT, "$openwebmaildir/templates/$lang/sessiontimeout.template") or
         openwebmailerror("$lang_err{'couldnt_open'} sessiontimeout.template!");
      while (<TIMEOUT>) {
         $html .= $_;
      }
      close (TIMEOUT);

      $html = applystyle($html);

      print $html;

      printfooter();
      writelog("timed-out session access attempt - $thissession");
      exit 0;
   }
   if ( -e "$openwebmaildir/$thissession" ) {
      open (SESSION, "$openwebmaildir/$thissession");
      my $cookie = <SESSION>;
      close (SESSION);
      chomp $cookie;
      unless ( cookie("sessionid") eq $cookie) {
         writelog("attempt to hijack session $thissession!");
         openwebmailerror("$lang_err{'inv_sessid'}");
      }
   }

   openwebmailerror("Session ID $lang_err{'has_illegal_chars'}") unless
      (($thissession =~ /^([\w\.\-]+)$/) && ($thissession = $1));
   open (SESSION, '>' . $openwebmaildir . $thissession) or
      openwebmailerror("$lang_err{'couldnt_open'} $thissession!");
   print SESSION cookie("sessionid");
   close (SESSION);
   $validsession = 1;
   return 1;
}
############# END VERIFYSESSION #####################

################## GETFOLDERS ####################
sub getfolders {
   my (@folders, @userfolders);
   my @delfiles=();
   my $totalfoldersize = 0;
   my $filename;

   if ( $homedirfolders eq 'yes' ) {
      @folders = qw(INBOX saved-messages sent-mail saved-drafts mail-trash);
      $totalfoldersize += ( -s "$folderdir/saved-messages" ) || 0;
      $totalfoldersize += ( -s "$folderdir/sent-mail" ) || 0;
      $totalfoldersize += ( -s "$folderdir/saved-drafts" ) || 0;
      $totalfoldersize += ( -s "$folderdir/mail-trash" ) || 0;
   } else {
      @folders = qw(INBOX SAVED SENT DRAFT TRASH);
      $totalfoldersize += ( -s "$folderdir/SAVED" ) || 0;
      $totalfoldersize += ( -s "$folderdir/SENT" ) || 0;
      $totalfoldersize += ( -s "$folderdir/DRAFT" ) || 0;
      $totalfoldersize += ( -s "$folderdir/TRASH" ) || 0;
   }

   opendir (FOLDERDIR, "$folderdir") or 
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir!");

   while (defined($filename = readdir(FOLDERDIR))) {

      ### files started with . are not folders
      ### they are openwebmail internal files (., .., dbm, search caches)
      if ( $filename=~/^\./ ) {
         if ( $filename=~/^\.(.*)\.db$/ ||
              $filename=~/^\.(.*)\.dir$/ ||
              $filename=~/^\.(.*)\.pag$/ ||
              $filename=~/^(.*)\.lock$/ ||
              ($filename=~/^\.(.*)\.cache$/ && $filename ne ".search.cache") ) {
            if ( ($1 ne $user) && (! -f "$folderdir/$1") ){
               # dbm or cache whose folder doesn't exist
               ($filename =~ /^(.+)$/) && ($filename = $1); # bypass taint check
               push (@delfiles, "$folderdir/$filename");	
            }
         }
         next;
      }

      ### find all user folders
      if ( $homedirfolders eq 'yes' ) {
         unless ( ($filename eq 'saved-messages') ||
                  ($filename eq 'sent-mail') ||
                  ($filename eq 'saved-drafts') ||
                  ($filename eq 'mail-trash') ||
                  ($filename eq '.') || ($filename eq '..') ||
                  ($filename =~ /\.lock$/) 
                ) {
            push (@userfolders, $filename);
            $totalfoldersize += ( -s "$folderdir/$filename" );
         }
      } else {
         if ($filename =~ /^(.+)\.folder$/) {
            push (@userfolders, $1);
            $totalfoldersize += ( -s "$folderdir/$filename" );
         }
      }
   }

   closedir (FOLDERDIR) or
      openwebmailerror("$lang_err{'couldnt_close'} $folderdir!");

   push (@folders, sort(@userfolders));

   if ($#delfiles >= 0) {
      unlink(@delfiles);
   }

   if ($folderquota) {
      ($hitquota = 1) if ($totalfoldersize >= ($folderquota * 1024));
   }

   return \@folders;
}
################ END GETFOLDERS ##################

###################### READPREFS #########################
sub readprefs {
   my ($key,$value);
   my %prefshash;
   if ( -f "$userprefsdir$user/config" ) {
      open (CONFIG,"$userprefsdir$user/config") or
         openwebmailerror("$lang_err{'couldnt_open'} config!");
      while (<CONFIG>) {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         if ($key eq 'style') {
            $value =~ s/\.//g;  ## In case someone gets a bright idea...
         }
         $prefshash{"$key"} = $value;
      }
      close (CONFIG) or openwebmailerror("$lang_err{'couldnt_close'} config!");
   }
   if ( -f "$userprefsdir$user/signature" ) {
      $prefshash{"signature"} = '';
      open (SIGNATURE, "$userprefsdir$user/signature") or
         openwebmailerror("$lang_err{'couldnt_open'} signature!");
      while (<SIGNATURE>) {
         $prefshash{"signature"} .= $_;
      }
      close (SIGNATURE) or openwebmailerror("$lang_err{'couldnt_close'} signature!");
   }
   return \%prefshash;
}
##################### END READPREFS ######################

###################### READSTYLE #########################
sub readstyle {
   my ($key,$value);
   my $stylefile = $prefs{"style"} || 'Default';
   my %stylehash;
   unless ( -f "$stylesdir$stylefile") {
      $stylefile = 'Default';
   }
   open (STYLE,"$stylesdir$stylefile") or
      openwebmailerror("$lang_err{'couldnt_open'} $stylefile!");
   while (<STYLE>) {
      if (/###STARTSTYLESHEET###/) {
         $stylehash{"css"} = '';
         while (<STYLE>) {
            $stylehash{"css"} .= $_;
         }
      } else {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         $stylehash{"$key"} = $value;
      }
   }
   close (STYLE) or openwebmailerror("$lang_err{'couldnt_close'} $stylefile!");
   return \%stylehash;
}
##################### END READSTYLE ######################

################# APPLYSTYLE ##############################
sub applystyle {
   my $template = shift;
   $template =~ s/\@\@\@LOGO_URL\@\@\@/$logo_url/g;
   $template =~ s/\@\@\@BACKGROUND\@\@\@/$style{"background"}/g;
   $template =~ s/\@\@\@TITLEBAR\@\@\@/$style{"titlebar"}/g;
   $template =~ s/\@\@\@TITLEBAR_TEXT\@\@\@/$style{"titlebar_text"}/g;
   $template =~ s/\@\@\@MENUBAR\@\@\@/$style{"menubar"}/g;
   $template =~ s/\@\@\@WINDOW_DARK\@\@\@/$style{"window_dark"}/g;
   $template =~ s/\@\@\@WINDOW_LIGHT\@\@\@/$style{"window_light"}/g;
   $template =~ s/\@\@\@ATTACHMENT_DARK\@\@\@/$style{"attachment_dark"}/g;
   $template =~ s/\@\@\@ATTACHMENT_LIGHT\@\@\@/$style{"attachment_light"}/g;
   $template =~ s/\@\@\@COLUMNHEADER\@\@\@/$style{"columnheader"}/g;
   $template =~ s/\@\@\@TABLEROW_LIGHT\@\@\@/$style{"tablerow_light"}/g;
   $template =~ s/\@\@\@TABLEROW_DARK\@\@\@/$style{"tablerow_dark"}/g;
   $template =~ s/\@\@\@FONTFACE\@\@\@/$style{"fontface"}/g;
   $template =~ s/\@\@\@SCRIPTURL\@\@\@/$scripturl/g;
   $template =~ s/\@\@\@PREFSURL\@\@\@/$prefsurl/g;
   $template =~ s/\@\@\@CSS\@\@\@/$style{"css"}/g;
   $template =~ s/\@\@\@VERSION\@\@\@/$version/g;

   return $template;
}
################ END APPLYSTYLE ###########################

##################### PRINTHEADER #########################
# once we print the header, we don't want to do it again if there's an error
local $headerprinted=0;
sub printheader {
   my $cookie;
   my @headers=();

   unless ($headerprinted) {
      if ($setcookie) {
         $cookie = cookie( -name    => 'sessionid',
                           -"value" => $setcookie,
                           -path    => '/' );
      }
      my $html = '';
      $headerprinted = 1;
      open (HEADER, "$openwebmaildir/templates/$lang/header.template") or
         openwebmailerror("$lang_err{'couldnt_open'} header.template!");

      while (<HEADER>) {
         $html .= $_;
      }
      close (HEADER);

      $html = applystyle($html);
      $html =~ s/\@\@\@BG_URL\@\@\@/$bg_url/g;
      $html =~ s/\@\@\@CHARSET\@\@\@/$lang_charset/g;

      push(@headers, -pragma=>'no-cache');
      push(@headers, -cookie=>$cookie) if ($setcookie);
      push(@headers, -charset=>$lang_charset) if ($CGI::VERSION>=2.57);
      push(@headers, @_);
      print header(@headers);
      print $html;
   }
}
################### END PRINTHEADER #######################

################### PRINTFOOTER ###########################
sub printfooter {
   my $html = '';
   open (FOOTER, "$openwebmaildir/templates/$lang/footer.template") or
      openwebmailerror("$lang_err{'couldnt_open'} footer.template!");
   while (<FOOTER>) {
      $html .= $_;
   }
   close (FOOTER);
   
   $html = applystyle($html);
   
   $html =~ s/\@\@\@VERSION\@\@\@/$version/g;
   print $html;
}
################# END PRINTFOOTER #########################

##################### WRITELOG ############################
sub writelog {
   unless ( ($logfile eq 'no') || ( -l "$logfile" ) ) {
      open (LOGFILE,">>$logfile") or openwebmailerror("$lang_err{'couldnt_open'} $logfile!");
      my $timestamp = localtime();
      my $logaction = shift;
      my $loggeduser = $user || 'UNKNOWNUSER';
      my $loggedip = $userip || 'UNKNOW';
      print LOGFILE "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
      close (LOGFILE);
   }
}
#################### END WRITELOG #########################

##################### OPENWEBMAILERROR ##########################
sub openwebmailerror {
   unless ($headerprinted) {
      $headerprinted = 1;
      my $background = $style{"background"};
      $background =~ s/"//g;

      if ( $CGI::VERSION>=2.57) {
         print header(-pragma=>'no-cache',
                      -charset=>$lang_charset);
      } else {
         print header(-pragma=>'no-cache');
      }
      print start_html(-"title"=>"Open WebMail version $version",
                       -BGCOLOR=>$background,
                       -BACKGROUND=>$bg_url);
      print '<style type="text/css">';
      print $style{"css"};
      print '</style>';
      print "<FONT FACE=",$style{"fontface"},">\n";
   }
   print '<BR><BR><BR><BR><BR><BR>';
   print '<table border="0" align="center" width="40%" cellpadding="1" cellspacing="1">';

   print '<tr><td bgcolor=',$style{"titlebar"},' align="left">',
   '<font color=',$style{"titlebar_text"},' face=',$style{"fontface"},' size="3"><b>OPENWEBMAIL ERROR</b></font>',
   '</td></tr><tr><td align="center" bgcolor=',$style{"window_light"},'><BR>';
   print shift;
   print '<BR><BR></td></tr></table>';
   print '<p align="center"><font size="1"><BR>
          <a href="http://turtle.ee.ncku.edu.tw/openwebmail/">
          Open WebMail</a> version ', $version,'<BR>
          </FONT></FONT></P></BODY></HTML>';
   exit 0;
}
################### END OPENWEBMAILERROR #######################

1;
