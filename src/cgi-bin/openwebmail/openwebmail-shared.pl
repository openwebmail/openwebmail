#
# routines shared by 
# openwebmail.pl, openwebmail-main.pl, openwebmail-prefs.pl, 
# spellcheck and checkmail.pl
#

# languagenames - The abbreviation of the languages and related names
%languagenames = (
                 'ca'           => 'Catalan',
                 'cs'           => 'Czech',
                 'da'           => 'Danish',
                 'de'           => 'German',			# Deutsch
                 'en'           => 'English',
                 'es'           => 'Spanish',			# Espanol
                 'fi'           => 'Finnish',
                 'fr'           => 'French',
                 'hu'           => 'Hungarian',
                 'it'           => 'Italiano',
                 'kr'           => 'Korean',
                 'lt'           => 'Lithuanian',
                 'nl'           => 'Nederlands',
                 'no_NY'        => 'Norwegian Nynorsk',
                 'pl'           => 'Polish',
                 'pt'           => 'Portuguese',
                 'pt_BR'        => 'Portuguese Brazil',
                 'ro'           => 'Romanian',
                 'ru'           => 'Russian',
                 'sk'           => 'Slovak',
                 'sv'           => 'Swedish',			# Svenska
                 'uk'           => 'Ukrainian',
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
            # resolv %var% but forward reference is not supported
            ${$r_confighash}{$key} =~ s/\%([\w\d_]+)\%/${$r_confighash}{$1}/msg; 
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
               # resolv %var% but forward reference is not supported
               $value =~ s/\%([\w\d_]+)\%/${$r_confighash}{$1}/msg; 
               ${$r_confighash}{$key}=$value; 
            }
         }
      }
   }
   close(CONFIG);

   # processing yes/no
   foreach $key ( 'use_hashedmailspools', 'use_homedirspools',
                  'use_homedirfolders', 'use_dotlockfile', 
                  'deliver_use_GMT', 'savedsuid_support',
                  'refresh_after_login', 'enable_rootlogin',
                  'enable_changepwd', 'enable_setfromemail', 
                  'enable_autoreply', 'enable_pop3', 'enable_setforward',
                  'autopop3_at_refresh', 'default_autopop3', 
                  'default_reparagraphorigmsg',
                  'default_confirmmsgmovecopy', 'default_viewnextaftermsgmovecopy',
                  'default_moveoldmsgfrominbox', 'forced_moveoldmsgfrominbox',
                  'default_hideinternal', 'symboliclink_mbox',
                  'default_filter_fakedsmtp', 'default_filter_fakedexecontenttype',
                  'default_disablejs', 'default_disableembcgi', 
                  'default_newmailsound', 
                  'default_usefixedfont', 'default_usesmileicon') {
      if (${$r_confighash}{$key} =~ /yes/i || ${$r_confighash}{$key} == 1) {
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
   if ( ${$r_confighash}{'timeoffset'} eq 'auto' ) {
      ${$r_confighash}{'timeoffset'}=gettimeoffset();
   }

   # processing list
   foreach $key ('domainnames', 'spellcheck_dictionaries', 
		 'allowed_clientip', 'allowed_clientdomain', 
                 'allowed_receiverdomain', 'disallowed_pop3servers') {
      if (! defined(@{${$r_confighash}{$key}}) ) { # conv str to list
         my @list=split(/\s*,\s*/, ${$r_confighash}{$key});
         ${$r_confighash}{$key}=\@list;
      }
   }

   # processing none
   if ( ${$r_confighash}{'default_bgurl'} eq 'none' ) {
      $value="${$r_confighash}{'ow_htmlurl'}/images/backgrounds/Transparent.gif";
      ${$r_confighash}{'default_bgurl'}=$value;
   }

   # bypass taint check for pathname defined in openwebmail.conf
   foreach $key ( 'smtpserver', 'auth_module', 
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
   my (%DB, %DBR, %DBS, $metainfo);

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

   if ($loginname=~/^(.*)\@(.*)$/) {
      my ($name, $domain)=($1, $2);
      $virtualuser=$name.'@'.$domain;
      $user=get_user_by_virtualuser($virtualuser, "$config{'ow_etcdir'}/virtusertable");
      if ($user eq "") {
         if ($domain=~s/^mail\.//) {
            $virtualuser=$name.'@'.$domain;
         } else {
            $virtualuser=$name.'@mail.'.$domain;
         }
         $user=get_user_by_virtualuser($virtualuser, "$config{'ow_etcdir'}/virtusertable");
      }
   } else {
      $virtualuser=$loginname.'@'.$ENV{'HTTP_HOST'};
      $user=get_user_by_virtualuser($virtualuser, "$config{'ow_etcdir'}/virtusertable");
      if ($user eq "" && $virtualuser=~s/\@mail\./\@/) {
         $user=get_user_by_virtualuser($virtualuser, "$config{'ow_etcdir'}/virtusertable");
      }
      if ($user eq "") {
         $virtualuser=$loginname;
         $user=get_user_by_virtualuser($virtualuser, "$config{'ow_etcdir'}/virtusertable");
      }
   }

   if ($user eq "") {
      $user=$loginname;
      $virtualuser=get_virtualuser_by_user($loginname, "$config{'ow_etcdir'}/virtusertable.rev");
      if ($virtualuser ne "") {	# user not used if virtualuser mapping exist
         return("", "", "", "", "", "");
      }
   }

   ($realname, $uid, $gid, $homedir)=get_userinfo($user);
   if ($uid ne "") {
      return($virtualuser, $user, $realname||$default_realname, $uid, $gid, $homedir);
   } else {
      return("", "", "", "", "", "");
   }
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
         my ($_email, $_realname) = split(/\@\@\@/, $_, 2);
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

   # get default value from config for err/undefined/empty prefs entries

   # entries disallowed to be empty
   foreach $key ( 'language', 'dictionary', 'style', 'iconset', 'bgurl', 
                  'sort', 'dateformat', 'headersperpage', 
                  'editcolumns', 'editrows',
                  'confirmmsgmovecopy', 'viewnextaftermsgmovecopy', 
                  'reparagraphorigmsg', 'replywithorigmsg',
                  'sendreceipt', 'moveoldmsgfrominbox',
                  'filter_repeatlimit', 'filter_fakedsmtp', 
                  'filter_fakedexecontenttype',
                  'disablejs', 'disableembcgi', 'hideinternal', 'newmailsound', 
                  'usefixedfont', 'usesmileicon', 'autopop3',
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
# This routine must be called after readstyle 
# since it references $prefs{'bgurl'}
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

   $stylehash{"css"}=~ s/\@\@\@BG_URL\@\@\@/$prefs{"bgurl"}/g;
   if ($prefs{'usefixedfont'}) {
      $stylehash{"css"}=~ s/\@\@\@FIXEDFONT\@\@\@/"Courier New",/g;
   } else {
      $stylehash{"css"}=~ s/\@\@\@FIXEDFONT\@\@\@//g;
   }
   return \%stylehash;
}
##################### END READSTYLE ######################

################# APPLYSTYLE ##############################
sub applystyle {
   my $template = shift;
   my $url;

   $template =~ s/\@\@\@NAME\@\@\@/$config{'name'}/g;
   $template =~ s/\@\@\@VERSION\@\@\@/$config{'version'}/g;
   $template =~ s/\@\@\@LOGO_URL\@\@\@/$config{'logo_url'}/g;
   $template =~ s/\@\@\@LOGO_LINK\@\@\@/$config{'logo_link'}/g;
   $template =~ s/\@\@\@PAGE_FOOTER\@\@\@/$config{'page_footer'}/g;

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
   my ($r_folders, $r_usage)=@_;
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
         if ($1 ne $user && 
             $1 ne 'address.book' && 
             $1 ne 'filter.book' && 
             ! -f "$folderdir/$1" ) {
            # dbm or cache whose folder doesn't exist
            ($filename =~ /^(.+)$/) && ($filename = $1); # bypass taint check
            push (@delfiles, "$folderdir/$filename");
            next;
         }
      # clean tmp file in msg rebuild
      } elsif ($filename=~/^_rebuild_tmp_\d+$/ ||
               $filename=~/^\._rebuild_tmp_\d+$/ ) {
         ($filename =~ /^(.+)$/) && ($filename = $1); # bypass taint check
         push (@delfiles, "$folderdir/$filename");
         next;
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

#################### GETMESSAGE ###########################
sub getmessage {
   my ($messageid, $mode) = @_;
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $folderhandle=FileHandle->new();
   my $r_messageblock;
   my %message = ();

   filelock($folderfile, LOCK_SH|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
   update_headerdb($headerdb, $folderfile);
   open($folderhandle, "$folderfile");
   $r_messageblock=get_message_block($messageid, $headerdb, $folderhandle);
   close($folderhandle);
   filelock($folderfile, LOCK_UN);

   if (${$r_messageblock} eq "" ||	# msgid not found
       ${$r_messageblock}!~/^From / ) {	# db index inconsistance
      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");

      filelock("$headerdb$config{'dbm_ext'}", LOCK_EX);
      my %HDB;
      dbmopen (%HDB, $headerdb, undef);
      $HDB{'METAINFO'}="ERR";
      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN);
      
      # forced reindex since metainfo = ERR
      update_headerdb($headerdb, $folderfile);

      open($folderhandle, "$folderfile");
      $r_messageblock=get_message_block($messageid, $headerdb, $folderhandle);
      close($folderhandle);

      filelock($folderfile, LOCK_UN);
      writelog("db error - $folderfile index inconsistence fixed");
      writehistory("db error - $folderfile index inconsistence fixed");

      return \%message if (${$r_messageblock} eq "" );
   }

   my ($currentheader, $currentbody, $r_currentattachments, $currentfrom, $currentdate,
       $currentsubject, $currentid, $currenttype, $currentto, $currentcc, $currentbcc,
       $currentreplyto, $currentencoding, $currentstatus, $currentreceived,
       $currentpriority, $currentinreplyto, $currentreferences);

   # $r_attachment is a reference to attachment array!
   if ($mode eq "all") {
      ($currentheader, $currentbody, $r_currentattachments)
		=parse_rfc822block($r_messageblock, "0", "all");
   } else {
      ($currentheader, $currentbody, $r_currentattachments)
		=parse_rfc822block($r_messageblock, "0", "");
   }
   return \%message if ( $currentheader eq "" );

   $currentfrom = $currentdate = $currentsubject = $currenttype = 
   $currentto = $currentcc = $currentreplyto = $currentencoding = 'N/A';
   $currentstatus = '';
   $currentpriority = '';
   $currentinreplyto = $currentreferences = '';

   my $lastline = 'NONE';
   my @smtprelays=();
   foreach (split(/\n/, $currentheader)) {
      if (/^\s/) {
         s/^\s+/ /;
         if    ($lastline eq 'FROM') { $currentfrom .= $_ }
         elsif ($lastline eq 'REPLYTO') { $currentreplyto .= $_ }
         elsif ($lastline eq 'DATE') { $currentdate .= $_ }
         elsif ($lastline eq 'SUBJ') { $currentsubject .= $_ }
         elsif ($lastline eq 'MESSID') { s/^\s+//; $currentid .= $_ }
         elsif ($lastline eq 'TYPE') { $currenttype .= $_ }
         elsif ($lastline eq 'ENCODING') { $currentencoding .= $_ }
         elsif ($lastline eq 'TO')   { $currentto .= $_ }
         elsif ($lastline eq 'CC')   { $currentcc .= $_ }
         elsif ($lastline eq 'BCC')   { $currentbcc .= $_ }
         elsif ($lastline eq 'INREPLYTO') { $currentinreplyto .= $_ }
         elsif ($lastline eq 'REFERENCES') { $currentreferences .= $_ }
         elsif ($lastline eq 'RECEIVED') { $currentreceived .= $_ }
      } elsif (/^from:\s+(.+)$/ig) {
         $currentfrom = $1;
         $lastline = 'FROM';
      } elsif (/^reply-to:\s+(.+)$/ig) {
         $currentreplyto = $1;
         $lastline = 'REPLYTO';
      } elsif (/^to:\s+(.+)$/ig) {
         $currentto = $1;
         $lastline = 'TO';
      } elsif (/^cc:\s+(.+)$/ig) {
         $currentcc = $1;
         $lastline = 'CC';
      } elsif (/^bcc:\s+(.+)$/ig) {
         $currentbcc = $1;
         $lastline = 'BCC';
      } elsif (/^date:\s+(.+)$/ig) {
         $currentdate = $1;
         $lastline = 'DATE';
      } elsif (/^subject:\s+(.+)$/ig) {
         $currentsubject = $1;
         $lastline = 'SUBJ';
      } elsif (/^message-id:\s+(.*)$/ig) {
         $currentid = $1;
         $lastline = 'MESSID';
      } elsif (/^content-type:\s+(.+)$/ig) {
         $currenttype = $1;
         $lastline = 'TYPE';
      } elsif (/^content-transfer-encoding:\s+(.+)$/ig) {
         $currentencoding = $1;
         $lastline = 'ENCODING';
      } elsif (/^status:\s+(.+)$/ig) {
         $currentstatus .= $1;
         $currentstatus =~ s/\s//g;
         $lastline = 'NONE';
      } elsif (/^x-status:\s+(.+)$/ig) {
         $currentstatus .= $1;
         $currentstatus =~ s/\s//g;
         $lastline = 'NONE';
      } elsif (/^references:\s+(.+)$/ig) {
         $currentreferences = $1;
         $lastline = 'REFERENCES';
      } elsif (/^in-reply-to:\s+(.+)$/ig) {
         $currentinreplyto = $1;
         $lastline = 'INREPLYTO';
      } elsif (/^priority:\s+(.*)$/ig) {
         $currentpriority = $1;
         $currentstatus .= "I";
         $lastline = 'NONE';
      } elsif (/^Received:(.+)$/ig) {
         my $tmp=$1;
         if ($currentreceived=~ /.*\sby\s([^\s]+)\s.*/) {
            unshift(@smtprelays, $1) if ($smtprelays[0] ne $1);
         }
         if ($currentreceived=~ /.*\sfrom\s([^\s]+)\s.*/) {
            unshift(@smtprelays, $1);
         } elsif ($currentreceived=~ /.*\(from\s([^\s]+)\).*/is) {
            unshift(@smtprelays, $1);
         }
         $currentreceived=$tmp;
         $lastline = 'RECEIVED';
      } else {
         $lastline = 'NONE';
      }
   }
   # capture last Received: block
   if ($currentreceived=~ /.*\sby\s([^\s]+)\s.*/) {
      unshift(@smtprelays, $1) if ($smtprelays[0] ne $1);
   }
   if ($currentreceived=~ /.*\sfrom\s([^\s]+)\s.*/) {
      unshift(@smtprelays, $1);
   } elsif ($currentreceived=~ /.*\(from\s([^\s]+)\).*/is) {
      unshift(@smtprelays, $1);
   }
   # count first fromhost as relay only if there are just 2 host on relaylist 
   # since it means sender pc uses smtp to talk to our mail server directly
   shift(@smtprelays) if ($#smtprelays>1);

search_smtprelay:
   foreach my $relay (@smtprelays) {
      next if ($relay !~ /[\w\d\-_]+\.[\w\d\-_]+/);
      foreach (@{$config{'domainnames'}}) {
         next search_smtprelay if ($relay =~ $_);
      }
      $relay=~s/[\[\]]//g;	# remove [] around ip addr in mailheader
				# since $message{smtprelay} may be put into filterrule
                        	# and we don't want [] be treat as regular expression
      $message{smtprelay} = $relay;
      last;
   }

   $message{header} = $currentheader;
   $message{body} = $currentbody;
   $message{attachment} = $r_currentattachments;

   $message{from}    = decode_mimewords($currentfrom);
   $message{replyto} = decode_mimewords($currentreplyto) unless ($currentreplyto eq "N/A");
   $message{to}      = decode_mimewords($currentto) unless ($currentto eq "N/A");
   $message{cc}      = decode_mimewords($currentcc) unless ($currentcc eq "N/A");
   $message{bcc}     = decode_mimewords($currentbcc) unless ($currentbcc eq "N/A");
   $message{subject} = decode_mimewords($currentsubject);

   $message{date} = $currentdate;
   $message{status} = $currentstatus;
   $message{messageid} = $currentid;
   $message{contenttype} = $currenttype;
   $message{encoding} = $currentencoding;
   $message{inreplyto} = $currentinreplyto;
   $message{references} = $currentreferences;
   $message{priority} = $currentpriority;

   # Determine message's number and previous and next message IDs.
   my ($totalsize, $newmessages, $r_messageids)=getinfomessageids();
   foreach my $i (0..$#{$r_messageids}) {
      if (${$r_messageids}[$i] eq $messageid) {
         $message{"prev"} = ${$r_messageids}[$i-1] if ($i > 0);
         $message{"next"} = ${$r_messageids}[$i+1] if ($i < $#{$r_messageids});
         $message{"number"} = $i+1;
         $message{"total"}=$#{$r_messageids}+1;
         last;
      }
   }
   return \%message;
}
#################### END GETMESSAGE #######################

################### GETINFOMESSAGEIDS ###################
sub getinfomessageids {
   my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $folder);
   my $index_complete=0;

   # do new indexing in background if folder > 10 M && empty db
   if ( (stat("$headerdb$config{'dbm_ext'}"))[7]==0 && 
        (stat($folderfile))[7] >= 10485760 ) {
      $|=1; 				# flush all output
      $SIG{CHLD} = sub { wait; $index_complete=1 if ($?==0) };	# handle zombie
      if ( fork() == 0 ) {		# child
         close(STDOUT);
         close(STDIN);
         filelock($folderfile, LOCK_SH|LOCK_NB) or exit 1;
         update_headerdb($headerdb, $folderfile);
         filelock($folderfile, LOCK_UN);
         exit 0;
      }

      for (my $i=0; $i<120; $i++) {	# wait index to complete for 120 seconds
         sleep 1;
         if ($index_complete==1) {
            last;
         }
      }   
      if ($index_complete==0) {
         openwebmailerror("$folderfile $lang_err{'under_indexing'}");
      }
   } else {	# do indexing directly if small folder
      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
      update_headerdb($headerdb, $folderfile);
      filelock($folderfile, LOCK_UN);
   }

   # Since recipients are displayed instead of sender in folderview of 
   # SENT/DRAFT folder, the $sort must be changed from 'sender' to 
   # 'recipient' in this case
   if ( $folder=~ m#sent-mail#i || 
        $folder=~ m#saved-drafts#i ||
        $folder=~ m#$lang_folders{'sent-mail'}#i ||
        $folder=~ m#$lang_folders{'saved-drafts'}#i ) {
      $sort='recipient' if ($sort eq 'sender');
   }

   if ( $keyword ne '' ) {
      my $folderhandle=FileHandle->new();
      my ($totalsize, $new, $r_haskeyword, $r_messageids, $r_messagedepths);
      my @messageids=();
      my @messagedepths=();
      
      ($totalsize, $new, $r_messageids, $r_messagedepths)=get_info_messageids_sorted($headerdb, $sort, "$headerdb.cache", $prefs{'hideinternal'});

      filelock($folderfile, LOCK_SH|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_locksh'} $folderfile!");
      open($folderhandle, $folderfile);
      ($totalsize, $new, $r_haskeyword)=search_info_messages_for_keyword($keyword, $searchtype, $headerdb, $folderhandle, "$folderdir/.search.cache", $prefs{'hideinternal'});
      close($folderhandle);
      filelock($folderfile, LOCK_UN);

      for (my $i=0; $i<@{$r_messageids}; $i++) {
	my $id = ${$r_messageids}[$i];
	if ( ${$r_haskeyword}{$id} == 1 ) {
	  push (@messageids, $id);
	  push (@messagedepths, ${$r_messagedepths}[$i]);
        }
      }
#      foreach (@{$r_messageids}) {
#         push (@messageids, $_) if ( ${$r_haskeyword}{$_} == 1 ); 
#      }
      return($totalsize, $new, \@messageids, \@messagedepths);

   } else { # return: $totalsize, $new, $r_messageids for whole folder

      return(get_info_messageids_sorted($headerdb, $sort, "$headerdb.cache", $prefs{'hideinternal'}))

   }
}
################# END GETINFOMESSAGEIDS #################

################# FILTERMESSAGE ###########################
sub filtermessage {
   my $filtered=mailfilter($user, 'INBOX', $folderdir, \@validfolders, 
	$prefs{'filter_repeatlimit'}, $prefs{'filter_fakedsmtp'}, $prefs{'filter_fakedexecontenttype'});
   if ($filtered > 0) {
      writelog("filtermsg - filter $filtered msgs from INBOX");
      writehistory("filtermsg - filter $filtered msgs from INBOX");
   } elsif ($filtered == -1 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.check!");
   } elsif ($filtered == -2 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.book!");
   } elsif ($filtered == -3 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} INBOX!");
   } elsif ($filtered == -4 ) {
      openwebmailerror("$lang_err{'couldnt_open'} INBOX!");
   } elsif ($filtered == -5 ) {
      openwebmailerror("$lang_err{'couldnt_lock'} mail-trash!");
   } elsif ($filtered == -6 ) {
      openwebmailerror("$lang_err{'couldnt_open'} .filter.check!");
   }
}
################# END FILTERMESSAGE #######################

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
            $html =~ s/\@\@\@USERINFO\@\@\@/$prefs{'email'} \($folderusage%\) \-/g;
         } else {
            $html =~ s/\@\@\@USERINFO\@\@\@/$prefs{'email'} \-/g;
         }
      } else {
         $html =~ s/\@\@\@USERINFO\@\@\@//g;
      }

      push(@headers, -pragma=>'no-cache');
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
   my $mailgid=getgrnam('mail');

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
         print start_html(-"title"=>"$config{'name'}",
                          -BGCOLOR=>"$background",
                          -BACKGROUND=>$prefs{'bgurl'});
         print qq|<style type="text/css">|,
               $css,
               qq|</style>|,
               qq|<FONT FACE=$fontface>\n|;
      }
      print qq|<BR><BR><BR><BR><BR><BR><BR>|,
            qq|<table border="0" align="center" width="40%" cellpadding="1" cellspacing="1">|,
            qq|<tr><td bgcolor=$titlebar align="left">|,
            qq|<font color=$titlebar_text face=$fontface size="3"><b>$config{'name'} ERROR</b></font>|,
            qq|</td></tr>|,
            qq|<tr><td align="center" bgcolor=$window_light><BR>\n|,
            @_, "\n",
            qq|<BR><font color=$window_light size=-2>\n|,	# hide the fonts
            qq|euid=$>, egid=$), mailgid=$mailgid\n|,
            qq|</font><BR>|,
            qq|</td></tr>|,
            qq|</table>\n|;
      print qq|<p align="center"><font size="-1"><BR>|,
            qq|$config{'page_footer'}<BR>|,
            qq|</FONT></FONT></P></BODY></HTML>|;

      $headerprinted = 0;
      exit 0;

   } else { # command mode
      print join(" ",@_), " (euid=$>, egid=$), mailgid=$mailgid)\n";
      exit 1;
   }
}
################### END OPENWEBMAILERROR #######################

##################### BIG5 <-> GB #########################
sub g2b {
   return($_[0]) if ($_[0]!~/[\x80-\xff]/);

   my $big5="";
   my $prog=(split(/\s+/, $config{'g2b_converter'}))[0];
   if (! -x $prog ) {
      openwebmailerror("GB to Big5 conversion is not available.<br>( $prog not found )");
   }

   my $tmpfile="/tmp/.openwebmail.tmp.$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);   # bypass taint check
   open (TMP, ">$tmpfile");
   print TMP $_[0];		# orig gb
   close(TMP);

   # required on linux since it execute shell with real uid, thus g2b_converter 
   # with ruid may be not able to read $tmpfile if mode not set
   chmod(0644, $tmpfile);	

   open(CONV, "$config{'g2b_converter'} < $tmpfile |");
   while (<CONV>) {
      $big5 .= $_;
   }
   close(CONV);

   unlink $tmpfile;
   return($big5);
}

sub b2g {
   return($_[0]) if ($_[0]!~/[\x80-\xff]/);

   my $gb="";
   my $prog=(split(/\s+/, $config{'b2g_converter'}))[0];
   if (! -x $prog ) {
      openwebmailerror("Big5 to GB conversion is not available.<br>( $prog not found )");
   }

   my $tmpfile="/tmp/.openwebmail.tmp.$$";
   ($tmpfile =~ /^(.+)$/) && ($tmpfile = $1);   # bypass taint check
   open (TMP, ">$tmpfile");
   print TMP $_[0];		# orig big5
   close(TMP);

   # required on linux since it execute shell with real uid, thus g2b_converter 
   # with ruid may be not able to read $tmpfile if mode not set
   chmod(0644, $tmpfile);

   open(CONV, "$config{'b2g_converter'} < $tmpfile |");
   while (<CONV>) {
      $gb .= $_;
   }
   close(CONV);

   unlink $tmpfile;
   return($gb);
}
##################### END BIG5 <-> GB #########################

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
# this routine save euid root to ruid in case system doesn't support saved-euid
# so we can give up euid root temporarily and get it back later.
# Saved-euid means the euid will be saved to a variable saved-euid(prepared by OS) 
# before it is changed, thus the process can switch back to previous euid if required
sub set_euid_egid_umask {
   my ($uid, $gid, $umask)=@_;

   # note! egid must be set before set euid to normal user,
   #       since a normal user can not set egid to others
   $) = $gid;

   if ($> != $uid) {
      $<=$> if (!$config{'savedsuid_support'} && $>==0); 
      $> = $uid 
   }
   umask($umask);
}
################### END SET_EUID_EGID_UMASK ###############

########################## METAINFO #########################
# return a string composed by the modify time & size of a file
sub metainfo {
   if (-e $_[0]) {
      # dev, ino, mode, nlink, uid, gid, rdev, size, atime, mtime, ctime, blksize, blocks
      my @l=stat($_[0]);
      return("mtime=$l[9] size=$l[7]");
   } else {
      return("");
   }
}

######################## END METAINFO #######################

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

#################### GETTIMEOFFSET #########################
sub gettimeoffset {
   my $t=time();
   my @g=gmtime($t);
   my @l=localtime($t);
   my $gserial=sprintf("%04d%02d%02d%02d%02d%02d", $g[5], $g[4], $g[3], $g[2], $g[1]);
   my $lserial=sprintf("%04d%02d%02d%02d%02d%02d", $l[5], $l[4], $l[3], $l[2], $l[1]);
   my $offset;

   if ( $lserial gt $gserial ) {
      my ($hour, $min)=($l[2]-$g[2], $l[1]-$g[1]);
      if ($min<0) { $min+=60; $hour--; }
      if ($hour<0) { $hour+=24; }
      $offset=sprintf("+%02d%02d", $hour, $min);
   } elsif ( $lserial lt $gserial ) {
      my ($hour, $min)=($g[2]-$l[2], $g[1]-$l[1]);
      if ($min<0) { $min+=60; $hour--; }
      if ($hour<0) { $hour+=24; }
      $offset=sprintf("-%02d%02d", $hour, $min);
   } else {
      $offset="+0000";
   }
   return($offset);
}
#################### END GETTIMEOFFSET #########################

#################### GETDATESERIAL #########################
sub getdateserial {
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime;
   my $serial;

   $year+=1900; $mon++;
   $serial=sprintf("%4d%02d%02d%02d%02d%02d", 
			$year, $mon, $mday, $hour, $min, $sec);
   return($serial);
}                      
#################### END GETDATESERIAL #########################

#################### ADD_DATESERIAL_TIMEOFFSET #########################
sub add_dateserial_timeoffset {
   my ($dateserial, $timeoffset)=@_;

   $dateserial=~/^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)$/;
   my ($y, $m, $d, $hour, $min, $sec)=($1,$2,$3, $4,$5,$6);
   $timeoffset=~/^([+\-]?)(\d\d)(\d\d)$/;
   my ($sign, $houroffset, $minoffset)=($1, $2, $3);

   my @mday=(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
   $mday[1]++ if ( $y%400==0 || ($y%100!=0 && $y%4==0) ); # leap year

   if ($sign eq "-") {
      $min-=$minoffset;
      $hour-=$houroffset;
      if ($min  < 0 ) { $min +=60; $hour--; }
      if ($hour < 0 ) { $hour+=24; $d--; }
      if ($d    < 1 ) { 
         $m--; 
         if ($m < 1) { $m+=12; $y--; }
         $d+=$mday[$m-1];
      }
   } else {
      $min+=$minoffset;
      $hour+=$houroffset;
      if ($min  >= 60 )          { $min -=60; $hour++; }
      if ($hour >= 24 )          { $hour-=24; $d++; }
      if ($d    >  $mday[$m-1] ) { $d-=$mday[$m-1]; $m++; }
      if ($m    >  12 )          { $m-=12; $y++; }
   }
   return(sprintf("%04d%02d%02d%02d%02d%02d", $y, $m, $d, $hour, $min, $sec));
}
#################### END ADD_DATESERIAL_TIMEOFFSET #########################

##################### DATESERIAL2STR #######################
sub dateserial2str {
   my ($serial, $format)=@_;
   my $str;

   return $serial if ( $serial !~ /^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)$/ );
   if ( $format eq "mm/dd/yyyy") {
      $str="$2/$3/$1 $4:$5:$6";
   } elsif ( $format eq "dd/mm/yyyy") {
      $str="$3/$2/$1 $4:$5:$6";
   } elsif ( $format eq "yyyy/mm/dd") {
      $str="$1/$2/$3 $4:$5:$6";
   } elsif ( $format eq "mm-dd-yyyy") {
      $str="$2-$3-$1 $4:$5:$6";
   } elsif ( $format eq "dd-mm-yyyy") {
      $str="$3-$2-$1 $4:$5:$6";
   } elsif ( $format eq "yyyy-mm-dd") {
      $str="$1-$2-$3 $4:$5:$6";
   } else {
      $str="$2/$3/$1 $4:$5:$6";
   }
   return($str);
}
################### END DATESERIAL2STR #####################

#################### EMAIL2NAMEADDR ######################
sub email2nameaddr {
   my $email=$_[0];
   my ($name, $address);

   if ($email =~ m/^\s*"?(.+?)"?\s*<(.*)>$/) {
      $name = $1;
      $address = $2;
   } elsif ($email =~ m/<?(.*?@.*?)>?\s+\((.+?)\)/) {
      $name = $2;
      $address = $1;
   } elsif ($email =~ m/<(.+)>/) {
      $name = $1;
      $address = $1;
      $name =~ s/\@.*$//;
   } elsif ($email =~ m/(.+)/) {
      $name = $1;
      $address = $1;
      $name =~ s/\@.*$//;
   }
   return($name, $address);
}
################ END EMAIL2NAMEADDR  #####################

###################### STR2LIST #######################
sub str2list {
   my $str=$_[0];
   my (@list, @tmp, $delimiter);
   my $pairmode=0; 
   my ($prevchar, $postchar);

   if ($str=~/,/) {
      @tmp=split(/,/, $str);
      $delimiter=',';
   } elsif ($str=~/;/) {
      @tmp=split(/;/, $str);
      $delimiter=';';
   } else {
      return($str);
   }

   foreach my $token (@tmp) {
      next if ($token=~/^\s*$/);
      if ($pairmode) {
         push(@list, pop(@list).$delimiter.$token);
         if ($token=~/\Q$postchar\E/ && $token!~/\Q$prevchar\E.*\Q$postchar\E/) {
            $pairmode=0 
         }
      } else {
         push(@list, $token);
         if ($token=~/^.*?(['"\(])/) {
            $prevchar=$1;
            if ($prevchar eq '(' ) {
               $postchar=')';
            } else {
               $postchar=$prevchar;
            }
            if ($token!~/\Q$prevchar\E.*\Q$postchar\E/) {
               $pairmode=1;
            }
         }
      }
   }

   foreach (@list) {
      s/^\s+//g;
      s/\s+$//g;
   }
   return(@list);
}
#################### END STR2LIST #####################

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
