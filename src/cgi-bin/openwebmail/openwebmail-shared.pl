#
# routines shared by openwebmail.pl, openwebmail-prefs.pl and checkmail.pl
#

##################### SET_EUID_EGID_UMASK #################
sub set_euid_egid_umask {
   my ($uid, $gid, $umask)=@_;

   # note! egid must be set before set euid to normal user,
   #       since a normal user can not set egid to others
   $) = $gid;
   $> = $uid if ($> == 0);
   umask($umask);
}
################### END SET_EUID_EGID_UMASK ###############

############## VERIFYSESSION ########################
local $validsession=0;
sub verifysession {
   if ($validsession == 1) {
      return 1;
   }

   if ( (-M "$openwebmaildir/sessions/$thissession")>$sessiontimeout
        || !(-e "$openwebmaildir/sessions/$thissession")) {
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
      if ( cookie("$user-sessionid") ne $cookie) {
         writelog("attempt to hijack session $thissession!");
         openwebmailerror("$lang_err{'inv_sessid'}");
      }
   }

   openwebmailerror("Session ID $lang_err{'has_illegal_chars'}") unless
      (($thissession =~ /^([\w\.\-]+)$/) && ($thissession = $1));

   if ( !defined(param("refresh")) ) {
      # extend the session lifetime only if this is not a auto-refresh
      open (SESSION, "> $openwebmaildir/sessions/$thissession") or
         openwebmailerror("$lang_err{'couldnt_open'} $thissession!");
      print SESSION cookie("$user-sessionid");
      close (SESSION);
   }
   $validsession = 1;
   return 1;
}
############# END VERIFYSESSION #####################

##################### VIRTUALUSER related ################
sub update_genericstable {
   my ($gendb, $genfile)=@_;
   my (%DB, %DBR, $metainfo);

   if (! -e $genfile) {
      unlink("$gendb.$dbm_ext") if (-e "$gendb.$dbm_ext");
      unlink("$gendb.r.$dbm_ext") if (-e "$gendb.r.$dbm_ext");
      return;
   }

   ($gendb =~ /^(.+)$/) && ($gendb = $1);		# bypass taint check
   if ( -e "$gendb.$dbm_ext" ) {
      my ($metainfo);

      filelock("$gendb.$dbm_ext", LOCK_SH);
      dbmopen (%DB, $gendb, undef);
      $metainfo=$DB{'METAINFO'};
      dbmclose(%DB);
      filelock("$gendb.$dbm_ext", LOCK_UN);

      return if ( $metainfo eq metainfo($genfile) );
   } 

   dbmopen(%DB, $gendb, 0644);
   filelock("$gendb.$dbm_ext", LOCK_EX);
   %DB=();	# ensure the gendb is empty

   dbmopen(%DBR, "$gendb.r", 0644);
   filelock("$gendb.r.$dbm_ext", LOCK_EX);
   %DBR=();

   open (GEN, $genfile);
   while (<GEN>) {
      s/^\s+//;
      s/\s+$//;
      s/#.*$//;

      my ($u, $vm)=split(/[\s\t]+/);
      next if ($u eq "" || $vm eq "");
      $DB{$u}=$vm;

      my ($vu, $vh)=split(/\@/, $vm);
      next if ($vu eq "");
      if ( !defined($DBR{$vu}) ) {
         $DBR{$vu}=$u;
      } else {
         $DBR{$vu}.=",$u";
      }
   }
   close(GEN);

   filelock("$gendb.r.$dbm_ext", LOCK_UN);
   dbmclose(%DBR);

   filelock("$gendb.$dbm_ext", LOCK_UN);
   dbmclose(%DB);
   return;
}

sub get_virtualemail_by_user {
   my ($user, $gendb)=@_;
   my (%DB, $email);

   dbmopen (%DB, $gendb, undef);
   $email=$DB{$user};
   dbmclose(%DB);
   return($email);
}

sub get_userlist_by_virtualuser {
   my ($virtualuser, $gendbr)=@_;
   my $userlist;

   dbmopen (%DBR, $gendbr, undef);
   $userlist=$DBR{$virtualuser};
   dbmclose(%DBR);
   return( split(/[,\s]+/, $userlist) );
}   

##################### END VIRTUALUSER related ################

################# GET_USEREMAIL_DOMAINNAMES ###################
# this routine handles virtualuser@virtualdomain in sendmail genericstable
# and add virtualdomain to global @domainnames defined in openwebmail.conf
sub get_useremail_domainnames {
   my ($user, $gendb, @domainnames)=@_;
   my ($virtualuser, $virtualdomain)=split(/\@/, get_virtualemail_by_user($user, $gendb));
   my $domainname;
   my $useremail;

   if ($virtualdomain) {
      my $found=0;
      foreach (@domainnames) {
         if ($virtualdomain eq $_) {
            $found=1; last;
         }
      }
      push(@domainnames, $virtualdomain) if (!$found);
   }

   foreach (@domainnames) {
      if ($prefs{domainname} eq $_) {
         $domainname=$_;
         last;
      }
   }
   $domainname=$virtualdomain || $domainnames[0] if ($domainname eq '');

   if ($enable_setfromname eq 'yes' && $prefs{"fromname"}) {
      # Create from: address when "fromname" is not null
      $useremail = $prefs{"fromname"} . "@" . $domainname; 
   } else {	
      # Create from: address when "fromname" is null
      if ($virtualuser) {
         $useremail = $virtualuser . "@" . $domainname; 
      } else {
         $useremail = $user . "@" . $domainname; 
      }
   } 

   return($useremail, @domainnames);
}

################# END GET_USEREMAIL_DOMAINNAMES ###################

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

############### GET_SPOOLFILE_FOLDERDB ################

################## GETFOLDERS ####################
# return list of valid folders and calc the total folder usage(0..100%)
sub getfolders {
   my $do_delfiles=$_[0];
   my @delfiles=();
   my (@folders, @userfolders);
   my $totalsize = 0;
   my $filename;

   opendir (FOLDERDIR, "$folderdir") or 
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir!");

   while (defined($filename = readdir(FOLDERDIR))) {

      next if ( $filename eq "." || $filename eq ".." );

      # find internal file that are stale
      if ( $filename=~/^\.(.*)\.db$/ ||
           $filename=~/^\.(.*)\.dir$/ ||
           $filename=~/^\.(.*)\.pag$/ ||
           $filename=~/^(.*)\.lock$/ ||
           ($filename=~/^\.(.*)\.cache$/ && $filename ne ".search.cache") ) {
         if ($1 ne $user && ! -f "$folderdir/$1" ) {
            if ($do_delfiles) {
               # dbm or cache whose folder doesn't exist
               ($filename =~ /^(.+)$/) && ($filename = $1); # bypass taint check
               push (@delfiles, "$folderdir/$filename");
            }
            next;
         }
      }

      # summary file size
      $totalsize += ( -s "$folderdir/$filename" ) || 0;

      ### skip openwebmail internal files (conf, dbm, lock, search caches...)
      next if ( $filename=~/^\./ || $filename =~ /\.lock$/);
      
      ### find all user folders
      if ( $filename ne 'saved-messages' &&
           $filename ne 'sent-mail' &&
           $filename ne 'saved-drafts' &&
           $filename ne 'mail-trash' ) {
         push (@userfolders, $filename);
      }
   }

   closedir (FOLDERDIR) or
      openwebmailerror("$lang_err{'couldnt_close'} $folderdir!");

   if ($#delfiles >= 0) {
      unlink(@delfiles);
   }

   @folders = qw(INBOX saved-messages sent-mail saved-drafts mail-trash);
   push (@folders, sort(@userfolders));

   # add INBOX size to totalsize
   my ($spoolfile,$headerdb)=get_folderfile_headerdb($user, 'INBOX');
   if ( -f $spoolfile ) {
      $totalsize += ( -s "$spoolfile" ) || 0;
   } else {
      # create spool file with user uid, gid if it doesn't exist
      my ($uuid, $ugid) = (get_userinfo($user))[1,2];
      open (F, ">>$spoolfile");
      close(F);
      chown ($uuid, $ugid, $spoolfile);
   }

   if ($folderquota) {
      $folderusage=int($totalsize*1000/($folderquota*1024))/10;
   } else {
      $folderusage=0;
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
            $value =~ s/^\.//g;  ## In case someone gets a bright idea...
         }
         $prefshash{"$key"} = $value;
      }
      close (CONFIG) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.openwebmailrc!");
   }

   my $signaturefile="";
   if ( -f "$folderdir/.signature" ) {
      $signaturefile="$folderdir/.signature";
   } elsif ( -f "$homedir/.signature" ) {
      $signaturefile="$homedir/.signature";
   }
   if ($signaturefile) {
      $prefshash{"signature"} = '';
      open (SIGNATURE, $signaturefile) or
         openwebmailerror("$lang_err{'couldnt_open'} $signaturefile!");
      while (<SIGNATURE>) {
         $prefshash{"signature"} .= $_;
      }
      close (SIGNATURE) or openwebmailerror("$lang_err{'couldnt_close'} $signaturefile!");
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

      if ($prefs{"bgurl"} ne "") {
         $html =~ s/\@\@\@BG_URL\@\@\@/$prefs{"bgurl"}/g;
      } else {
         $html =~ s/\@\@\@BG_URL\@\@\@/$bg_url/g;
      }
      $html =~ s/\@\@\@CHARSET\@\@\@/$lang_charset/g;

      if ($user) {
         if ($folderquota) {
            $html =~ s/\@\@\@USERINFO\@\@\@/\- $useremail \($folderusage%\)/g;
         } else {
            $html =~ s/\@\@\@USERINFO\@\@\@/\- $useremail/g;
         }
      } else {
         $html =~ s/\@\@\@USERINFO\@\@\@//g;
      }

      push(@headers, -pragma=>'no-cache');
      if ($setcookie) {
         $cookie = cookie( -name    => "$user-sessionid",
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
   my $remainingseconds;

   open (FOOTER, "$openwebmaildir/templates/$lang/footer.template") or
      openwebmailerror("$lang_err{'couldnt_open'} footer.template!");
   while (<FOOTER>) {
      $html .= $_;
   }
   close (FOOTER);
   
   $html = applystyle($html);
   
   if ($validsession || $setcookie) {
      $remainingseconds=
         ($sessiontimeout-(-M "$openwebmaildir/sessions/$thissession"))*24*60*60
         - (time()-$^T);
   } else {
      $remainingseconds= 365*24*60*60;	# make session never timeout
   }

   $html =~ s/\@\@\@USEREMAIL\@\@\@/$useremail/g;
   $html =~ s/\@\@\@REMAININGSECONDS\@\@\@/$remainingseconds/g;

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
      my $loggedip = $clientip || 'UNKNOW';
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
         '</td></tr>',
         '<form>',
         '<tr><td align="center" bgcolor=',$window_light,'><BR>',
         @_,
         '<BR><BR>',
         '<input type="submit" value=" Back " onclick=history.go(-1)>',
         '<BR><BR>',
         '</td></tr>',
         '</form>',
         '</table>';
   print '<p align="center"><font size="1"><BR>',
         '<a href="http://turtle.ee.ncku.edu.tw/openwebmail/">',
         'Open WebMail</a> version ', $version,'<BR>',
         '</FONT></FONT></P></BODY></HTML>';
   exit 0;
}
################### END OPENWEBMAILERROR #######################

################### DST_ADJUST #######################
# adjust timeoffset for DaySavingTime
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

#################### LOG_TIME (for profiling) ####################
sub log_time {
   my @msg=@_;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
   my ($today, $time);

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime;
   $year+=1900; $mon++;
   $today=sprintf("%4d%02d%02d", $year, $mon, $mday);
   $time=sprintf("%02d%02d%02d",$hour,$min, $sec);

   open(Z, ">> /tmp/time.log");

   # unbuffer mode
   select(Z); $| = 1;    
   select(STDOUT); 

   print Z "$today $time ", join(" ",@msg), "\n";
   close(Z);
   1;
}

################## END LOG_TIME (for profiling) ##################

1;
