#
# routines shared by openwebmail.pl, openwebmail-prefs.pl and checkmail.pl
#

############### GET_SPOOLFILE_FOLDERDB ################
sub get_folderfile_headerdb {
   my ($username, $foldername)=@_;
   my ($folderfile, $headerdb);

   if ($foldername eq 'INBOX') {
      if ($homedirspools eq "yes") {
         $folderfile = "$homedir/$homedirspoolname";
      } elsif ($hashedmailspools eq "yes") {
         $username =~ /^(.)(.)/;
         my $firstchar = $1;
         my $secondchar = $2;
         $folderfile = "$mailspooldir/$firstchar/$secondchar/$username";
      } else {
         $folderfile = "$mailspooldir/$username";
      }
      $headerdb="$folderdir/.$username";

   } elsif ($foldername eq 'DELETE') {
      $folderfile = $headerdb ='';

   } else {
      $folderfile = "$folderdir/$foldername";
      $headerdb="$folderdir/.$foldername";
   }

   return($folderfile, $headerdb);
}

sub set_euid_egid_umask {
   my ($uid, $gid, $umask)=@_;

   # note! egid must be set before set euid to normal user,
   #       since a normal user can not set egid to others
   $) = $gid;
   $> = $uid if ($> == 0);
   umask($umask);
}

############### GET_SPOOLFILE_FOLDERDB ################


############## VERIFYSESSION ########################
local $validsession=0;
sub verifysession {
   if ($validsession == 1) {
      return 1;
   }
   if ( -M "$openwebmaildir/sessions/$thissession" > $sessiontimeout || !(-e "$openwebmaildir/sessions/$thissession")) {
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
   if ( -e "$openwebmaildir/sessions/$thissession" ) {
      open (SESSION, "$openwebmaildir/sessions/$thissession");
      my $cookie = <SESSION>;
      close (SESSION);
      chomp $cookie;
      if ( cookie("sessionid") ne $cookie) {
         writelog("attempt to hijack session $thissession!");
         openwebmailerror("$lang_err{'inv_sessid'}");
      }
   }

   openwebmailerror("Session ID $lang_err{'has_illegal_chars'}") unless
      (($thissession =~ /^([\w\.\-]+)$/) && ($thissession = $1));
   open (SESSION, "> $openwebmaildir/sessions/$thissession") or
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

   @folders = qw(INBOX saved-messages sent-mail saved-drafts mail-trash);
   $totalfoldersize += ( -s "$folderdir/saved-messages" ) || 0;
   $totalfoldersize += ( -s "$folderdir/sent-mail" ) || 0;
   $totalfoldersize += ( -s "$folderdir/saved-drafts" ) || 0;
   $totalfoldersize += ( -s "$folderdir/mail-trash" ) || 0;

   opendir (FOLDERDIR, "$folderdir") or 
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir!");

   while (defined($filename = readdir(FOLDERDIR))) {

      ### files started with . are not folders
      ### they are openwebmail internal files (., .., dbm, search caches)
      if ( $filename=~/^\./ ) {	# .* are files other than folder
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
      if ( ($filename ne 'saved-messages') &&
           ($filename ne 'sent-mail') &&
           ($filename ne 'saved-drafts') &&
           ($filename ne 'mail-trash') &&
           ($filename ne '.') && ($filename ne '..') &&
           ($filename !~ /\.lock$/) ) {
         push (@userfolders, $filename);
         $totalfoldersize += ( -s "$folderdir/$filename" );
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
   if ( -f "$folderdir/.openwebmailrc" ) {
      open (CONFIG,"$folderdir/.openwebmailrc") or
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.openwebmailrc!");
      while (<CONFIG>) {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         if ($key eq 'style') {
            $value =~ s/\.//g;  ## In case someone gets a bright idea...
         }
         $prefshash{"$key"} = $value;
      }
      close (CONFIG) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.openwebmailrc!");
   }
   if ( -f "$folderdir/.signature" ) {
      $prefshash{"signature"} = '';
      open (SIGNATURE, "$folderdir/.signature") or
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.signature!");
      while (<SIGNATURE>) {
         $prefshash{"signature"} .= $_;
      }
      close (SIGNATURE) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.signature!");
   }
   return \%prefshash;
}
##################### END READPREFS ######################

###################### READSTYLE #########################
sub readstyle {
   my ($key,$value);
   my $stylefile = $prefs{"style"} || 'Default';
   my %stylehash;
   unless ( -f "$openwebmaildir/styles/$stylefile") {
      $stylefile = 'Default';
   }
   open (STYLE,"$openwebmaildir/styles/$stylefile") or
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
      $headerprinted = 1;

      my $html = '';
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
      if ($setcookie) {
         $cookie = cookie( -name    => 'sessionid',
                           -"value" => $setcookie,
                           -path    => '/' );
         push(@headers, -cookie=>$cookie);
      }
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
   return;
}
#################### END WRITELOG #########################

##################### OPENWEBMAILERROR ##########################
sub openwebmailerror{
   # load prefs if possible, or use default value
   my $background = $style{"background"}||"#FFFFFF";
   my $css = $style{"css"}||"";
   my $fontface = $style{"fontface"}||"Arial, Helvetica";
   my $titlebar = $style{"titlebar"}||"#002266";
   my $titlebar_text = $style{"titlebar_text"}||"#FFFFFF";
   my $window_light = $style{"window_light"}||"#EEEEEE";

   unless ($headerprinted) {
      $headerprinted = 1;
      $background =~ s/"//g;

      if ( $CGI::VERSION>=2.57) {
         print header(-pragma=>'no-cache',
                      -charset=>$lang_charset);
      } else {
         print header(-pragma=>'no-cache');
      }
      print start_html(-"title"=>"Open WebMail version $version",
                       -BGCOLOR=>"$background",
                       -BACKGROUND=>$bg_url);
      print '<style type="text/css">';
      print $css;
      print '</style>';
      print "<FONT FACE=",$fontface,">\n";
   }
   print '<BR><BR><BR><BR><BR><BR>';
   print '<table border="0" align="center" width="40%" cellpadding="1" cellspacing="1">';

   print '<tr><td bgcolor=',$titlebar,' align="left">',
   '<font color=',$titlebar_text,' face=',$fontface,' size="3"><b>OPENWEBMAIL ERROR</b></font>',
   '</td></tr><tr><td align="center" bgcolor=',$window_light,'><BR>';
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
