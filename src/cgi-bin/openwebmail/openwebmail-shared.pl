#
# routines shared by 
# openwebmail.pl, openwebmail-prefs.pl, spellcheck and checkmail.pl
#

# languagenames - The abbreviation of the languages and related names
%languagenames = (
                 'ca'           => 'Catalan',
                 'da'           => 'Danish',
                 'de'           => 'German',			# Deutsch
                 'en'           => 'English',
                 'es'           => 'Spanish',			# Espanol
                 'fi'           => 'Finnish',
                 'fr'           => 'French',
                 'hu'           => 'Hungarian',
                 'it'           => 'Italiano',
                 'nl'           => 'Nederlands',
                 'no_NY'        => 'Norwegian Nynorsk',
                 'pl'           => 'Polish',
                 'pt'           => 'Portuguese',
                 'pt_BR'        => 'Portuguese Brazil',
                 'ro'           => 'Romanian',
                 'ru'           => 'Russian',
                 'sk'           => 'Slovak',
                 'sv'           => 'Swedish',			# Svenska
                 'zh_CN.GB2312' => 'Chinese ( Simplified )',
                 'zh_TW.Big5'   => 'Chinese ( Traditional )'
                 );

####################### READCONF #######################
# read openwebmail.conf into a hash
# the hash is 'called by reference' since we want to do 'bypass taint' on it
sub readconf {
   my ($r_confighash, $configfile)=@_;

   # read config
   open(CONFIG, $configfile) or
      openwebmailerror("Couldn't open config file $configfile");
   my ($key, $value)=("", "");
   my $blockmode=0;
   while ((my $line=<CONFIG>)) {
      $line=~s/\s+$//;
      if ($blockmode) {
         if ( $line =~ m!</$key>! ) {
            $blockmode=0;
         } else {
            ${$r_confighash}{$key} .= "$line\n";
         }
      } else { 
         $line=~s/#.*$//;
         $line=~s/^\s+//; $line=~s/\s+$//;
         next if ($line=~/^#/);

         if ( $line =~ m!^<(.+)>$! ) {
            $key=$1; $key=~s/^\s+//; $key=~s/\s+$//;
            ${$r_confighash}{$key}="";
            $blockmode=1;
         } else {
            ($key, $value)=split(/\s+/, $line, 2);
            if ($key ne "" && $value ne "" ) {
               # resolv %var% and forward reference is not allowed
               $value =~ s/\%([\w\d_]+)\%/${$r_confighash}{$1}/g; 
               ${$r_confighash}{$key}=$value; 
            }
         }
      }
   }
   close(CONFIG);

   # processing yes/no
   foreach $key ( 'use_hashedmailspools', 'use_homedirspools',
                  'use_homedirfolders', 'use_dotlockfile', 
                  'enable_changepwd', 'enable_setfromemail', 
                  'enable_autoreply', 'enable_pop3', 
                  'autopop3_at_refresh', 'symboliclink_mbox',
                  'default_hideinternal', 'default_filter_fakedsmtp', 
                  'default_disablejs', 'default_autopop3', 
                  'default_newmailsound') {
      if (${$r_confighash}{$key} =~ /yes/i) {
         ${$r_confighash}{$key}=1;
      } else {
         ${$r_confighash}{$key}=0;
      }
   }

   # processing auto
   if ( ${$r_confighash}{'domainnames'} eq 'auto' ) {
      $value=`/bin/hostname`;
      $value=~s/^\s+//; $value=~s/\s+$//;
      ${$r_confighash}{'domainnames'}=$value;
   }

   # processing list
   foreach $key ('domainnames', 'spellcheck_dictionaries', 'disallowed_pop3servers') {
      my @list=split(/\s*,\s*/, ${$r_confighash}{$key});
      ${$r_confighash}{$key}=\@list;
   }

   # processing none
   if ( ${$r_confighash}{'default_bgurl'} eq 'none' ) {
      $value="${$r_confighash}{'ow_htmlurl'}/images/backgrounds/Transparent.gif";
      ${$r_confighash}{'default_bgurl'}=$value;
   }

   # bypass taint check for pathname defined in openwebmail.conf
   foreach $key ( 'sendmail', 'auth_module', 
        'mailspooldir', 'homedirspoolname', 'homedirfolderdirname', 'dbm_ext',
        'ow_cgidir', 'ow_htmldir','ow_etcdir', 'logfile', 'spellcheck',
	'vacationinit', 'vacationpipe', 'g2b_converter', 'b2g_converter' ) {
      (${$r_confighash}{$key} =~ /^(.+)$/) && (${$r_confighash}{$key}=$1);
   }

   return(0);
}
##################### END READCONF #######################

##################### VIRTUALUSER related ################
sub update_virtusertable {
   my ($virdb, $virfile)=@_;
   my (%DB, %DBS, $metainfo);

   if (! -e $virfile) {
      unlink("$virdb$config{'dbm_ext'}") if (-e "$virdb$config{'dbm_ext'}");
      unlink("$virdb.short$config{'dbm_ext'}") if (-e "$virdb.short$config{'dbm_ext'}");
      return;
   }

   ($virdb =~ /^(.+)$/) && ($virdb = $1);		# bypass taint check
   if ( -e "$virdb$config{'dbm_ext'}" ) {
      my ($metainfo);

      filelock("$virdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%DB, $virdb, undef);
      $metainfo=$DB{'METAINFO'};
      dbmclose(%DB);
      filelock("$virdb$config{'dbm_ext'}", LOCK_UN);

      return if ( $metainfo eq metainfo($virfile) );
   } 

   writelog("update virtusertable.db");

   unlink("$virdb$config{'dbm_ext'}",
          "$virdb.rev$config{'dbm_ext'}",
          "$virdb.short$config{'dbm_ext'}");

   dbmopen(%DB, $virdb, 0644);
   filelock("$virdb$config{'dbm_ext'}", LOCK_EX);
   %DB=();	# ensure the virdb is empty

   dbmopen(%DBR, "$virdb.rev", 0644);
   filelock("$virdb.rev$config{'dbm_ext'}", LOCK_EX);
   %DBR=();

   dbmopen(%DBS, "$virdb.short", 0644);
   filelock("$virdb.short$config{'dbm_ext'}", LOCK_EX);
   %DBS=();

   open (VIRT, $virfile);
   while (<VIRT>) {
      s/^\s+//;
      s/\s+$//;
      s/#.*$//;

      my ($vu, $u)=split(/[\s\t]+/);
      next if ($vu eq "" || $u eq "");
      next if ($vu =~ /^@/);	# don't care entries for whole domain mapping

      $DB{$vu}=$u;

      if ( defined($DBR{$u}) ) {
         $DBR{$u}.=",$vu";
      } else {
         $DBR{$u}.="$vu";
      }

      if ($vu=~/^(.+)@.+/) {
         my $shortname=$1;
         if ( defined($DBS{$shortname}) ) {
            $DBS{$shortname}.=",$vu";
         } else {
            $DBS{$shortname}=$vu;
         }
      }
   }
   close(VIRT);

   $DB{'METAINFO'}=metainfo($virfile);

   filelock("$virdb.short$config{'dbm_ext'}", LOCK_UN);
   dbmclose(%DBS);

   filelock("$virdb.rev$config{'dbm_ext'}", LOCK_UN);
   dbmclose(%DBR);

   filelock("$virdb$config{'dbm_ext'}", LOCK_UN);
   dbmclose(%DB);
   return;
}

sub get_virtualuser_by_user {
   my ($user, $virdbr)=@_;
   my (%DBR, $vu);

   if ( -f "$virdbr$config{'dbm_ext'}" ) {
      filelock("$virdbr$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%DBR, $virdbr, undef);
      $vu=$DBR{$user};
      dbmclose(%DBR);
      filelock("$virdbr$config{'dbm_ext'}", LOCK_UN);
   }
   return($vu);
}

sub get_virtualuser_by_shortname {
   my ($shortname, $virdbs)=@_;
   my (%DBS, $vu);

   if ( -f "$virdbs$config{'dbm_ext'}" ) {
      filelock("$virdbs$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%DBS, $virdbs, undef);
      $vu=$DBS{$shortname};
      dbmclose(%DBS);
      filelock("$virdbs$config{'dbm_ext'}", LOCK_UN);
   }
   return($vu);
}

sub get_user_by_virtualuser {
   my ($vu, $virdb)=@_;
   my (%DB, $u);

   if ( -f "$virdb$config{'dbm_ext'}" ) {
      filelock("$virdb$config{'dbm_ext'}", LOCK_SH);
      dbmopen (%DB, $virdb, undef);
      $u=$DB{$vu};
      dbmclose(%DB);
      filelock("$virdb$config{'dbm_ext'}", LOCK_UN);
   }
   return($u);
}

sub get_virtualuser_user_userinfo {
   my $loginname=$_[0];
   my ($virtualuser, $user, $realname, $uid, $gid, $homedir);

   my $default_realname=$loginname; 
   $default_realname=~s/\@.*^//;

   # loginname is a real user and not mappped by any virtualuser
   $virtualuser=get_virtualuser_by_user($loginname, "$config{'ow_etcdir'}/virtusertable.rev");
   if ($virtualuser eq "") {    # loginname is a real userid (uuu)
      ($realname, $uid, $gid, $homedir)=get_userinfo($loginname);
      if ($uid ne "") {
         return("", $loginname, $realname||$default_realname, $uid, $gid, $homedir);
      }
   }

   # loginname@HTTP_HOST is a virtualuser (uuu)
   if ($loginname !~ /\@/) {
      my $domain=$ENV{'HTTP_HOST'};
      $user=get_user_by_virtualuser($loginname.'@'.$domain, "$config{'ow_etcdir'}/virtusertable");
      if ($user eq "" && $domain=~s/^mail\.//) {
         $user=get_user_by_virtualuser($loginname.'@'.$domain, "$config{'ow_etcdir'}/virtusertable");
      }
      if ($user ne "") {
         ($realname, $uid, $gid, $homedir)=get_userinfo($user);
         if ($uid ne "") {
            return($loginname.'@'.$domain, $user, $realname||$default_realname, $uid, $gid, $homedir);
         }
      }
   }

   # loginname is a virtualuser (uuu or uuu@hhh)
   $user=get_user_by_virtualuser($loginname, "$config{'ow_etcdir'}/virtusertable");
   if ($user ne "") {
      ($realname, $uid, $gid, $homedir)=get_userinfo($user);
      if ($uid ne "") {
         return($loginname, $user, $realname||$default_realname, $uid, $gid, $homedir);
      }
   }

   # loginname is the username part of a virtualuser (uuu)
   $virtualuser=get_virtualuser_by_shortname($loginname, "$config{'ow_etcdir'}/virtusertable.short");
   # and this username appears only in this virtualuser
   if ($virtualuser ne "" && $virtualuser !~ /,/) {	
      $user=get_user_by_virtualuser($virtualuser, "$config{'ow_etcdir'}/virtusertable");
      if ($user ne "") {
         ($realname, $uid, $gid, $homedir)=get_userinfo($user);
         if ($uid ne "") {
            return($virtualuser, $user, $realname||$default_realname, $uid, $gid, $homedir);
         }
      }
   }

   # user not found
   return("", "", "", "", "", "");
}
##################### END VIRTUALUSER related ################

##################### GET_DEFAULTEMAILS, GET_USERFROM ################
sub get_defaultemails {
   my ($virtualuser, $user)=@_;
   my @emails=();

   if ($virtualuser ne "") {
      if ($virtualuser =~ /\@/ ) {
         push(@emails, $virtualuser);
      } else {
         foreach my $domain (@{$config{'domainnames'}}) {
            push(@emails, "$virtualuser".'@'."$domain");
         }
      }
   } else {
      foreach my $domain (@{$config{'domainnames'}}) {
         push(@emails, "$user".'@'."$domain");
      }
   }
   return(@emails);
}

sub get_userfrom {
   my ($virtualuser, $user, $realname, $frombook)=@_;
   my %from=();

   # get default fromemail
   my @defaultemails=get_defaultemails($virtualuser, $user);
   foreach (@defaultemails) {
      $from{$_}=$realname;
   }

   # get user defined fromemail
   if (open (FROMBOOK, $frombook)) {
      while (<FROMBOOK>) {
         my ($_email, $_realname) = split(/:/, $_, 2);
         chomp($_realname); 
         if ( defined($from{"$_email"}) || $config{'enable_setfromemail'} ) {
             $from{"$_email"} = $_realname||$realname;
         }
      }
      close (FROMBOOK);
   }

   return(%from);
}
##################### END GET_DEFAULTEMAILS GET_USERFROM ################

###################### READPREFS #########################
# error message is hardcoded with english 
# since $prefs{'language'} has not been initialized before this routine
sub readprefs {
   my ($key,$value);
   my %prefshash;

   if ( -f "$folderdir/.openwebmailrc" ) {
      open (CONFIG,"$folderdir/.openwebmailrc") or
         openwebmailerror("Couldn't open $folderdir/.openwebmailrc!");
      while (<CONFIG>) {
         ($key, $value) = split(/=/, $_);
         chomp($value);
         if ($key eq 'style') {
            $value =~ s/^\.//g;  ## In case someone gets a bright idea...
         }
         $prefshash{"$key"} = $value;
      }
      close (CONFIG);
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
         openwebmailerror("Couldn't open $signaturefile!");
      while (<SIGNATURE>) {
         $prefshash{"signature"} .= $_;
      }
      close (SIGNATURE);
   }

   # validate email with defaultemails if setfromemail is not allowed
   if (!$config{'enable_setfromemail'} || $prefshash{'email'} eq "") {
      my @defaultemails=get_defaultemails($virtualuser, $user);
      my $email;
      foreach $email (@defaultemails) {
         last if ($prefshash{'email'} eq $email);
      }
      if ($prefshash{'email'} ne $email) {
         $prefshash{'email'}=$defaultemails[0];
      }
   }

   # get default value from config for undefined/empty prefs entries

   # entries disallowed to be empty
   foreach $key ( 'language', 'dictionary', 'style', 'iconset', 'bgurl', 
                  'sort', 'headersperpage', 'editcolumns', 'editrows',
                  'filter_repeatlimit', 'filter_fakedsmtp',
                  'disablejs', 'hideinternal', 'newmailsound', 'autopop3',
                  'trashreserveddays') {
      if ( !defined($prefshash{$key}) || $prefshash{$key} eq "" ) {
          $prefshash{$key}=$config{'default_'.$key};
      }
   }

   # entries allowed to be empty
   foreach $key ( 'signature') {
      if ( !defined($prefshash{$key}) ) {
          $prefshash{$key}=$config{'default_'.$key};
      }
   }

   # entries related to ondisk dir or file
   if ( ! -f "$config{'ow_etcdir'}/lang/$prefshash{'language'}" ) {
      $prefshash{'language'}=$config{'default_language'};
   }
   if ( ! -f "$config{'ow_etcdir'}/styles/$prefshash{'style'}" ) {
      $prefshash{'style'}=$config{'default_style'};
   }
   if ( ! -d "$config{'ow_htmldir'}/images/iconsets/$prefs{'iconset'}" ) {
      $prefshash{'iconset'}=$config{'default_iconset'};
   }

   return \%prefshash;
}
##################### END READPREFS ######################

###################### READSTYLE #########################
# error message is hardcoded with english 
# since $prefs{'language'} has not been initialized before this routine
sub readstyle {
   my ($key,$value);
   my $stylefile = $prefs{"style"} || 'Default';
   my %stylehash;

   unless ( -f "$config{'ow_etcdir'}/styles/$stylefile") {
      $stylefile = 'Default';
   }
   open (STYLE,"$config{'ow_etcdir'}/styles/$stylefile") or
      openwebmailerror("Couldn't open $config{'ow_etcdir'}/styles/$stylefile!");
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
   close (STYLE);
   return \%stylehash;
}
##################### END READSTYLE ######################

################# APPLYSTYLE ##############################
sub applystyle {
   my $template = shift;
   my $url;

   $template =~ s/\@\@\@VERSION\@\@\@/$config{'version'}/g;
   $template =~ s/\@\@\@HTML_URL\@\@\@/$config{'ow_htmlurl'}/g;
   $template =~ s/\@\@\@LOGO_URL\@\@\@/$config{'logo_url'}/g;
   $template =~ s/\@\@\@LOGO_LINK\@\@\@/$config{'logo_link'}/g;

   $url="$config{'ow_cgiurl'}/openwebmail.pl";
   $template =~ s/\@\@\@SCRIPTURL\@\@\@/$url/g;
   $url="$config{'ow_cgiurl'}/openwebmail-prefs.pl";
   $template =~ s/\@\@\@PREFSURL\@\@\@/$url/g;
   $url="$config{'ow_htmlurl'}/images";
   $template =~ s/\@\@\@IMAGEDIR_URL\@\@\@/$url/g;

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
   $template =~ s/\@\@\@CSS\@\@\@/$style{"css"}/g;

   return $template;
}
################ END APPLYSTYLE ###########################

##################### escapeURL, unescapeURL #################
# escape & unescape routine are not available in CGI.pm 3.0
# so we borrow the 2 routines from 2.xx version of CGI.pm
sub unescapeURL {
    my $todecode = shift;
    return undef unless defined($todecode);
    $todecode =~ tr/+/ /;       # pluses become spaces
    $todecode =~ s/%([0-9a-fA-F]{2})/pack("c",hex($1))/ge;
    return $todecode;
}

sub escapeURL {
    my $toencode = shift;
    return undef unless defined($toencode);
    $toencode=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
    return $toencode;
}

##################### END escapeURL, unescapeURL #################


##################### SET_EUID_EGID_UMASK #################
sub set_euid_egid_umask {
   my ($uid, $gid, $umask)=@_;

   # note! egid must be set before set euid to normal user,
   #       since a normal user can not set egid to others
   $) = $gid;
   $> = $uid if ($> != $uid);
   umask($umask);
}
################### END SET_EUID_EGID_UMASK ###############

############## VERIFYSESSION ########################
sub verifysession {
   if ( (-M "$config{'ow_etcdir'}/sessions/$thissession") > $config{'sessiontimeout'}/60/24
     || !(-e "$config{'ow_etcdir'}/sessions/$thissession")) {
      my $html = '';
      printheader();
      open (TIMEOUT, "$config{'ow_etcdir'}/templates/$prefs{'language'}/sessiontimeout.template") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/sessiontimeout.template!");
      while (<TIMEOUT>) {
         $html .= $_;
      }
      close (TIMEOUT);

      $html = applystyle($html);

      print $html;

      printfooter();
      writelog("session error - session $thissession timeout access attempt");
      writehistory("session error - session $thissession timeout access attempt");
      exit 0;
   }
   if ( -e "$config{'ow_etcdir'}/sessions/$thissession" ) {
      open (SESSION, "$config{'ow_etcdir'}/sessions/$thissession");
      my $cookie = <SESSION>;
      close (SESSION);
      chomp $cookie;
      if ( cookie("$user-sessionid") ne $cookie) {
         writelog("session error - session $thissession hijack attempt!");
         writehistory("session error - session $thissession hijack attempt!");
         openwebmailerror("$lang_err{'inv_sessid'}");
      }
   }

   openwebmailerror("Session ID $lang_err{'has_illegal_chars'}") unless
      (($thissession =~ /^([\w\.\-\@]+)$/) && ($thissession = $1));

   if ( !defined(param("refresh")) ) {
      # extend the session lifetime only if this is not a auto-refresh
      open (SESSION, "> $config{'ow_etcdir'}/sessions/$thissession") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/sessions/$thissession!");
      print SESSION cookie("$user-sessionid");
      close (SESSION);
   }
   return 1;
}
############# END VERIFYSESSION #####################

############### GET_SPOOLFILE_FOLDERDB ################
sub get_folderfile_headerdb {
   my ($username, $foldername)=@_;
   my ($folderfile, $headerdb);

   if ($foldername eq 'INBOX') {
      if ($config{'use_homedirspools'}) {
         $folderfile = "$homedir/$config{'homedirspoolname'}";
      } elsif ($config{'use_hashedmailspools'}) {
         $username =~ /^(.)(.)/;
         my $firstchar = $1;
         my $secondchar = $2;
         $folderfile = "$config{'mailspooldir'}/$firstchar/$secondchar/$username";
      } else {
         $folderfile = "$config{'mailspooldir'}/$username";
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
   my ($r_folders, $r_usage, $do_delfiles)=@_;
   my @delfiles=();
   my @userfolders;
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

      # skip openwebmail internal files (conf, dbm, lock, search caches...)
      next if ( $filename=~/^\./ || $filename =~ /\.lock$/);
      
      # find all user folders
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

   @{$r_folders}=();
   push (@{$r_folders}, 
         'INBOX', 'saved-messages', 'sent-mail', 'saved-drafts', 'mail-trash',
         sort(@userfolders));

   # add INBOX size to totalsize
   my ($spoolfile,$headerdb)=get_folderfile_headerdb($user, 'INBOX');
   if ( -f $spoolfile ) {
      $totalsize += ( -s "$spoolfile" ) || 0;
   } else {
      # create spool file with user uid, gid if it doesn't exist
      ($spoolfile =~ /^(.+)$/) && ($spoolfile = $1); # bypass taint check
      open (F, ">>$spoolfile");
      close(F);
      chown ($uuid, $ugid, $spoolfile);
   }

   if ($config{'folderquota'}) {
      ${$r_usage}=int($totalsize*1000/($config{'folderquota'}*1024))/10;
   } else {
      ${$r_usage}=0;
   }

   return;
}
################ END GETFOLDERS ##################

##################### WRITELOG ############################
sub writelog {
   my ($logaction)=$_[0];
   return if ( ($config{'logfile'} eq 'no') || ( -l "$config{'logfile'}" ) );

   my $timestamp = localtime();
   my $loggeduser = $virtualuser || $user || 'UNKNOWNUSER';
   my $loggedip = get_clientip();

   open (LOGFILE,">>$config{'logfile'}") or 
      openwebmailerror("$lang_err{'couldnt_open'} $config{'logfile'}!");
   print LOGFILE "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
   close (LOGFILE);

   return;
}
#################### END WRITELOG #########################

################## WRITEHISTORY ####################
sub writehistory {
   my ($logaction)=$_[0];
   my $timestamp = localtime();
   my $loggeduser = $virtualuser || $user || 'UNKNOWNUSER';
   my $loggedip = get_clientip();

   if ( -f "$folderdir/.history.log" ) {
      my ($start, $end, $buff);

      filelock("$folderdir/.history.log", LOCK_EX);
      open (HISTORYLOG,"+< $folderdir/.history.log") or 
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.history.log");
      seek(HISTORYLOG, 0, 2);	# seek to tail
      $end=tell(HISTORYLOG);

      if ( $end > ($config{'maxbooksize'} * 1024)) {
         seek(HISTORYLOG, $end-int($config{'maxbooksize'} * 1024 * 0.8), 0);
         $_=<HISTORYLOG>;
         $start=tell(HISTORYLOG);

         read(HISTORYLOG, $buff, $end-$start);

         seek(HISTORYLOG, 0, 0);
         print HISTORYLOG $buff;

         $end=tell(HISTORYLOG);
         truncate(HISTORYLOG, $end);
      }

      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
      close(HISTORYLOG);
      filelock("$folderdir/.history.log", LOCK_UN);

   } else {
      open(HISTORYLOG, ">$folderdir/.history.log") or
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.history.log");
      print HISTORYLOG "$timestamp - [$$] ($loggedip) $loggeduser - $logaction\n";
      close(HISTORYLOG);
   }

   return(0);
}

################ END WRITEHISTORY ##################

##################### PRINTHEADER #########################
# $headerprinted is set to 1 once printheader is called and seto 0 until
# printfooter is called. This variable is used to not print header again
# in openwebmailerror
local $headerprinted=0;
sub printheader {
   my $cookie;
   my @headers=();

   unless ($headerprinted) {
      $headerprinted = 1;

      my $html = '';
      open (HEADER, "$config{'ow_etcdir'}/templates/$prefs{'language'}/header.template") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/header.template!");
      while (<HEADER>) {
         $html .= $_;
      }
      close (HEADER);

      $html = applystyle($html);

      $html =~ s/\@\@\@BG_URL\@\@\@/$prefs{"bgurl"}/g;
      $html =~ s/\@\@\@CHARSET\@\@\@/$lang_charset/g;

      if ($user) {
         if ($config{'folderquota'}) {
            $html =~ s/\@\@\@USERINFO\@\@\@/\- $prefs{'email'} \($folderusage%\)/g;
         } else {
            $html =~ s/\@\@\@USERINFO\@\@\@/\- $prefs{'email'}/g;
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

   open (FOOTER, "$config{'ow_etcdir'}/templates/$prefs{'language'}/footer.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/footer.template!");
   while (<FOOTER>) {
      $html .= $_;
   }
   close (FOOTER);
   
   $html = applystyle($html);
   
   my $remainingseconds= 365*24*60*60;	# default timeout = 1 year
   if ($thissession ne "") { 	# if this is a session
      my $sessionage=(-M "$config{'ow_etcdir'}/sessions/$thissession"); 
      if ($sessionage ne "") {	# if this session is valid
         $remainingseconds= ($config{'sessiontimeout'}/60/24-$sessionage)
                            *24*60*60 - (time()-$^T);
      } 
   }

   $html =~ s/\@\@\@USEREMAIL\@\@\@/$prefs{'email'}/g;
   $html =~ s/\@\@\@REMAININGSECONDS\@\@\@/$remainingseconds/g;

   print $html;

   $headerprinted = 0;
}
################# END PRINTFOOTER #########################

##################### OPENWEBMAILERROR ##########################
sub openwebmailerror {
   if (defined($ENV{'HTTP_HOST'})) {	# in CGI mode
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
         print start_html(-"title"=>"Open WebMail version $config{'version'}",
                          -BGCOLOR=>"$background",
                          -BACKGROUND=>$prefs{'bgurl'});
         print qq|<style type="text/css">|,
               $css,
               qq|</style>|,
               qq|<FONT FACE=$fontface>\n|;
      }
      print qq|<BR><BR><BR><BR><BR><BR>|,
            qq|<table border="0" align="center" width="40%" cellpadding="1" cellspacing="1">|,
            qq|<tr><td bgcolor=$titlebar align="left">|,
            qq|<font color=$titlebar_text face=$fontface size="3"><b>OPENWEBMAIL ERROR</b></font>|,
            qq|</td></tr>|,
            qq|<form>|,
            qq|<tr><td align="center" bgcolor=$window_light><BR>|,
            @_,
            qq|<BR><font color=$window_light size=-2>|,	# hide the fonts
            qq|euid=$>, egid=$), mailgid=$mailgid|,
            qq|</font><BR>|,
            qq|<input type="submit" value=" Back " onclick=history.go(-1)>|,
            qq|<BR><BR>|,
            qq|</td></tr>|,
            qq|</form>|,
            qq|</table>|;
      print qq|<p align="center"><font size="1"><BR>|,
            qq|<a href="$config{'ow_htmlurl'}/openwebmail/openwebmail.html">|,
            qq|Open WebMail</a> version $config{'version'}<BR>|,
            qq|</FONT></FONT></P></BODY></HTML>|;

      $headerprinted = 0;
      exit 0;

   } else { # command mode
      print join(" ",@_), " (euid=$>, egid=$), mailgid=$mailgid)\n";
      exit 1;
   }
}
################### END OPENWEBMAILERROR #######################

#################### GET_CLIENTIP #############################
sub get_clientip {
   my $clientip;

   if (defined $ENV{'HTTP_X_FORWARDED_FOR'} &&
      $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^10\./ &&
      $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^172\.[1-3][0-9]\./ &&
      $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^192\.168\./ &&
      $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^127\.0\./ ) {
      $clientip=(split(/,/,$ENV{HTTP_X_FORWARDED_FOR}))[0];
   } elsif (defined $ENV{REMOTE_ADDR} ) {
      $clientip=$ENV{REMOTE_ADDR};
   } else {
      $clientip="127.0.0.1";
   }

   return $clientip;
}
#################### END GET_CLIENTIP #########################

#################### GET_PROTOCOL #########################
sub get_protocol {
   if ($ENV{'HTTPS'}=~/on/i || 
       $ENV{'SERVER_PORT'}==443 || 
       $ENV{'HTTP_REFERER'}=~/^https/i ) {
      return("https");
   } else {
      return("http");
   }
}
#################### END GET_PROTOCOL #########################

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

   open(Z, ">> /tmp/openwebmail.debug");

   # unbuffer mode
   select(Z); $| = 1;    
   select(STDOUT); 

   print Z "$today $time ", join(" ",@msg), "\n";
   close(Z);
   chmod(0666, "/tmp/openwebmail.debug");
}

################## END LOG_TIME (for profiling) ##################

1;
