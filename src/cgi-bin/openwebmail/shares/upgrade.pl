#
# upgrade.pl - routines to do release upgrade
#
# these routines convert data file format from old release to most current
#

use strict;
use Fcntl qw(:DEFAULT :flock);

# extern vars, defined in caller openwebmail-xxx.pl
use vars qw(%config %prefs %lang_text %lang_err);
use vars qw($domain $user $uuid $homedir);
use vars qw(@openwebmailrcitem);	# defined in ow-shared.pl

sub upgrade_20030323 {		# called only if homedir doesn't exist
   # rename old homedir for compatibility
   if (!$config{'use_syshomedir'} && $config{'auth_withdomain'} &&
       !-d "$homedir" && -d "$config{'ow_usersdir'}/$user\@$domain") {
      my $olddir=ow::tool::untaint("$config{'ow_usersdir'}/$user\@$domain");
      rename($olddir, $homedir) or
         openwebmailerror(__FILE__, __LINE__, "$lang_text{'rename'} $olddir to $homedir $lang_text{'failed'} ($!)");
      writelog("release upgrade - rename $olddir to $homedir by 20030323");
   }
}

sub upgrade_20021218 {		# called only if folderdir doesn't exist
   my $user_releasedate=$_[0];
   my $folderdir="$homedir/$config{'homedirfolderdirname'}";

   # mv folders from $homedir to $folderdir($homedir/mail/) for old ow_usersdir
   if ($user_releasedate lt "20021218") {
      if ( !$config{'use_syshomedir'} &&
           -f "$homedir/.openwebmailrc" && !-f "$folderdir/.openwebmailrc") {
         opendir(D, $homedir);
         my @files=readdir(D);
         closedir(D);
         foreach my $file (@files) {
            next if ($file eq "." || $file eq ".." || $file eq $config{'homedirfolderdirname'});
            $file=ow::tool::untaint($file);
            rename("$homedir/$file", "$folderdir/$file");
         }
         writelog("release upgrade - mv $homedir/* to $folderdir/* by 20021218");
      }
   }
}

sub upgrade_all {	# called if user releasedate is too old
   my $user_releasedate=$_[0];
   my $content;

   my $folderdir="$homedir/$config{'homedirfolderdirname'}";

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   if ( $user_releasedate lt "20011101" ) {
      if ( -f "$folderdir/.filter.book" ) {
         $content="";
         ow::filelock::lock("$folderdir/.filter.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $folderdir/.filter.book");
         sysopen(F, "$folderdir/.filter.book", O_RDONLY);
         while (<F>) {
            chomp;
            my ($priority, $ruletype, $include, $text, $op, $destination, $enable) = split(/\@\@\@/);
            if ( $enable eq '') {
               ($priority, $ruletype, $include, $text, $destination, $enable) = split(/\@\@\@/);
               $op='move';
            }
            $ruletype='textcontent' if ($ruletype eq 'body');
            $content.="$priority\@\@\@$ruletype\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable\n";
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $folderdir/.filter.book by 20011101");
            writelog("release upgrade - $folderdir/.filter.book by 20011101");
            sysopen(F, "$folderdir/.filter.book", O_WRONLY|O_TRUNC|O_CREAT);
            print F $content;
            close(F);
         }
         ow::filelock::lock("$folderdir/.filter.book", LOCK_UN);
      }

      if ( -f "$folderdir/.pop3.book" ) {
         $content="";
         ow::filelock::lock("$folderdir/.pop3.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $folderdir/.pop3.book");
         sysopen(F, "$folderdir/.pop3.book", O_RDONLY);
         while (<F>) {
            chomp;
            my @a=split(/:/);
            my ($pop3host, $pop3user, $pop3passwd, $pop3lastid, $pop3del, $enable);
            if ($#a==4) {
               ($pop3host, $pop3user, $pop3passwd, $pop3del, $pop3lastid) = @a;
               $enable=1;
            } elsif ($a[3]=~/\@/) {
               my $pop3email;
               ($pop3host, $pop3user, $pop3passwd, $pop3email, $pop3del, $pop3lastid) = @a;
               $enable=1;
            } else {
               ($pop3host, $pop3user, $pop3passwd, $pop3lastid, $pop3del, $enable) =@a;
            }
            $content.="$pop3host\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@RESERVED\@\@\@$pop3del\@\@\@$enable\n";
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $folderdir/.pop3.book by 20011101");
            writelog("release upgrade - $folderdir/.pop3.book by 20011101");
            sysopen(F, "$folderdir/.pop3.book", O_WRONLY|O_TRUNC|O_CREAT);
            print F $content;
            close(F);
         }
         ow::filelock::lock("$folderdir/.pop3.book", LOCK_UN);
      }
   }

   if ( $user_releasedate lt "20011117" ) {
      for my $book (".from.book", ".address.book", ".pop3.book") {
         if ( -f "$folderdir/$book" ) {
            $content="";
            ow::filelock::lock("$folderdir/$book", LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $folderdir/$book");
            sysopen(F, "$folderdir/$book", O_RDONLY);
            while (<F>) {
               last if (/\@\@\@/);
               s/:/\@\@\@/g;
               $content.=$_
            }
            close(F);
            if ($content ne "") {
               writehistory("release upgrade - $folderdir/$book by 20011117");
               writelog("release upgrade - $folderdir/$book by 20011117");
               sysopen(F, "$folderdir/$book", O_WRONLY|O_TRUNC|O_CREAT);
               print F $content;
               close(F);
            }
            ow::filelock::lock("$folderdir/$book", LOCK_UN);
         }
      }
   }

   if ( $user_releasedate lt "20011216" ) {
      my @cachefiles;
      my $file;
      opendir(FOLDERDIR, "$folderdir") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $folderdir ($!)");
      while (defined($file = readdir(FOLDERDIR))) {
         if ($file=~/^(\..+\.cache)$/) {
            $file="$folderdir/$1";
            push(@cachefiles, $file);
         }
      }
      closedir(FOLDERDIR);
      if ($#cachefiles>=0) {
         writehistory("release upgrade - $folderdir/*.cache by 20011216");
         writelog("release upgrade - $folderdir/*.cache by 20011216");
         # remove old .cache since its format is not compatible with new one
         unlink(@cachefiles);
      }
   }

   if ( $user_releasedate lt "20021201" ) {
      if ( -f "$folderdir/.calendar.book" ) {
         my $content='';
         ow::filelock::lock("$folderdir/.calendar.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $folderdir/.calendar.book");
         sysopen(F, "$folderdir/.calendar.book", O_RDONLY);
         while (<F>) {
            next if (/^#/);
            chomp;
            # fields: idate, starthourmin, endhourmin, string, link, email, color
            my @a=split(/\@\@\@/, $_);
            if ($#a==7) {
               $content.=join('@@@', @a);
            } elsif ($#a==6) {
               $content.=join('@@@', @a, 'none');
            } elsif ($#a==5) {
               $content.=join('@@@', @a, ,'0', 'none');
            } elsif ($#a<5) {
               $content.=join('@@@', $a[0], $a[1], $a[2], '0', $a[3], $a[4], '0', 'none');
            }
            $content.="\n";
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $folderdir/.calendar.book by 20021201");
            writelog("release upgrade - $folderdir/.calendar.book by 20021201");
            sysopen(F, "$folderdir/.calendar.book", O_WRONLY|O_TRUNC|O_CREAT);
            print F $content;
            close(F);
         }
         ow::filelock::lock("$folderdir/.calendar.book", LOCK_UN);
      }
   }

   # change the owner of files under ow_usersdir/username from root to $uuid
   if ($user_releasedate lt "20030312") {
      if( !$config{'use_syshomedir'} && -d $homedir) {
         my $chown_bin;
         foreach ("/bin/chown", "/usr/bin/chown", "/sbin/chown", "/usr/sbin/chown") {
            $chown_bin=$_ if (-x $_);
         }
         system($chown_bin, '-R', $uuid, $homedir);
         writelog("release upgrade - chown -R $uuid $homedir/* by 20030312");
      }
   }

   if ( $user_releasedate lt "20030528" ) {
      if ( -f "$folderdir/.pop3.book" ) {
         $content="";
         ow::filelock::lock("$folderdir/.pop3.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $folderdir/.pop3.book");
         sysopen(F, "$folderdir/.pop3.book", O_RDONLY);
         while (<F>) {
            chomp;
            my @a=split(/\@\@\@/);
            my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $enable)=@a;
            if ($pop3port!~/^\d+$/||$pop3port>65535) {	# not port number? old format!
               ($pop3host, $pop3user, $pop3passwd, $pop3del, $enable)=@a[0,1,2,4,5];
               $pop3port=110;
               # not secure, but better than plaintext
               $pop3passwd=$pop3passwd ^ substr($pop3host,5,length($pop3passwd));
               $pop3passwd=encode_base64($pop3passwd, '');
            }
            $content.="$pop3host\@\@\@$pop3port\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable\n";
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $folderdir/.pop3.book by 20030528");
            writelog("release upgrade - $folderdir/.pop3.book by 20030528");
            sysopen(F, "$folderdir/.pop3.book", O_WRONLY|O_TRUNC|O_CREAT);
            print F $content;
            close(F);
         }
         ow::filelock::lock("$folderdir/.pop3.book", LOCK_UN);
      }
   }

   if ( $user_releasedate lt "20031128" ) {
      my %is_dotpath;
      foreach (qw(
         openwebmailrc release.date history.log
         filter.book filter.check
         from.book address.book stationery.book
         trash.check search.cache signature
         calendar.book notify.check
         webdisk.cache
         pop3.book pop3.check authpop3.book
      )) { $is_dotpath{$_}=1; }

      opendir(FOLDERDIR, "$folderdir") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $folderdir ($!)");
      while (defined(my $file = readdir(FOLDERDIR))) {
         next if ($file eq '..' || $file!~/^\./);
         $file=~s/^\.//;
         if ($is_dotpath{$file} || $file=~/^uidl\./ || $file=~/^filter\.book/) {
            rename(ow::tool::untaint("$folderdir/.$file"), dotpath($file));
         } elsif ($file=~/\.(lock|cache|db|dir|pag|db\.lock|dir\.lock|pag\.lock)$/) {
            rename(ow::tool::untaint("$folderdir/.$file"), ow::tool::untaint(dotpath('db')."/$file"));
         }
      }
      closedir(FOLDERDIR);
      writehistory("release upgrade - $folderdir/.* to .openwebmail/ by 20031128");
      writelog("release upgrade - $folderdir/.* to .openwebmail/ by 20031128");
   }

   if ( $user_releasedate lt "20040111" ) {
      my $pop3book = dotpath('pop3.book');
      if ( -f $pop3book ) {
         $content="";
         ow::filelock::lock($pop3book, LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $pop3book");
         sysopen(F, $pop3book, O_RDONLY);
         while (<F>) {
            chomp;
            my @a=split(/\@\@\@/);
            if ($#a==6) {
               $content.="$_\n";
            } else {
               my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $enable)=@a;
               my $pop3ssl=0;
               $content.="$pop3host\@\@\@$pop3port\@\@\@$pop3ssl\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable\n";
            }
         }
         close(F);
         if ($content ne "") {
            writehistory("release upgrade - $pop3book by 20040111");
            writelog("release upgrade - $pop3book by 20040111");
            sysopen(F, $pop3book, O_WRONLY|O_TRUNC|O_CREAT);
            print F $content;
            close(F);
         }
         ow::filelock::lock($pop3book, LOCK_UN);
      }
   }

   if ( $user_releasedate lt "20040724" ) {
      my $filterbook = dotpath('filter.book');
      my $filterruledb = dotpath('filter.ruledb');
      # rename filter.book.db -> filter.ruledb.db
      ow::dbm::rename($filterbook, $filterruledb);
      writehistory("release upgrade - mv $filterbook to $filterruledb by 20040724");
      writelog("release upgrade - mv $filterbook to $filterruledb by 20040724");
   }

   if ( $user_releasedate lt "20041101" ) {
      my $rcfile=dotpath('openwebmailrc');
      if (-f $rcfile) {
         %prefs = readprefs();
         $prefs{'abook_width'}=$config{'default_abook_width'};
         $prefs{'abook_height'}=$config{'default_abook_height'};
         $prefs{'abook_listviewfieldorder'}=$config{'default_abook_listviewfieldorder'};
         # $rcfile is written back in update_openwebmailrc()
         writehistory("release upgrade - openwebmailrc by 20041101");
         writelog("release upgrade - openwebmailrc by 20041101");
      }
   }

   if ( $user_releasedate lt "20041107" ) {
      my $calbookfile=dotpath('calendar.book');
      my $data;
      if (sysopen(F, $calbookfile, O_RDONLY)) {
         while (<F>) {
            chomp;
            my @a=split(/\@\@\@/, $_);
            $a[8]=$prefs{'charset'} if ($a[8] eq '');
            $data.=join('@@@', @a)."\n";
         }
         close(F);
         if (sysopen(F, $calbookfile, O_WRONLY|O_TRUNC|O_CREAT)) {
            print F $data;
            close(F);
            writehistory("release upgrade - $calbookfile charset by 20041107");
            writelog("release upgrade - $calbookfile charset by 20041107");
         }
      }
   }

   if ( $user_releasedate lt "20050206" ) {
      my $filterbookfile=dotpath('filter.book');
      my $data;
      if (sysopen(F, $filterbookfile, O_RDONLY)) {
         while (<F>) {
            chomp;
            my @a=split(/\@\@\@/, $_);
            $a[7]=$prefs{'charset'} if ($a[7] eq '');
            $data.=join('@@@', @a)."\n";
         }
         close(F);
         if (sysopen(F, $filterbookfile, O_WRONLY|O_TRUNC|O_CREAT)) {
            print F $data;
            close(F);
            writehistory("release upgrade - $filterbookfile charset by 20050206");
            writelog("release upgrade - $filterbookfile charset by 20050206");
         }
      }
   }

   if ( $user_releasedate lt "20050319" ) {
      my $calbookfile=dotpath('calendar.book');
      my $data;
      if (sysopen(F, $calbookfile, O_RDONLY)) {
         while (<F>) {
            chomp;
            my @a=split(/\@\@\@/, $_);
            $a[9]=1 if ($a[9] eq '');
            $data.=join('@@@', @a)."\n";
         }
         close(F);
         if (sysopen(F, $calbookfile, O_WRONLY|O_TRUNC|O_CREAT)) {
            print F $data;
            close(F);
            writehistory("release upgrade - $calbookfile charset by 20050319");
            writelog("release upgrade - $calbookfile charset by 20050319");
         }
      }
   }

   if ( $user_releasedate lt "20050410" ) {
      my $rcfile=dotpath('openwebmailrc');
      if (-f $rcfile) {
         %prefs = readprefs();
         if ($prefs{'sort'} eq 'date') {
            $prefs{'sort'}='date_rev';
            if (sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT)) {
               foreach my $key (@openwebmailrcitem) {
                  print RC "$key=$prefs{$key}\n";
               }
               close(RC);
               writehistory("release upgrade - openwebmailrc by 20050410");
               writelog("release upgrade - openwebmailrc by 20050410");
            }
         }
      }
   }

   if ( $user_releasedate lt "20060721" ) {
      # users preferences need to be updated to reflect move to locales instead of just lang/charset
      my $rcfile=dotpath('openwebmailrc');
      if (-f $rcfile) {
         %prefs = readprefs();

         my $prefscharset = uc($prefs{'charset'});                   # utf-8 -> UTF-8
         $prefscharset =~ s#[-_\s]+##g;                              # UTF-8 -> UTF8
         $prefscharset = $ow::lang::charactersets{$prefscharset}[0]; # OWM Locale style

         my $prefslanguage = substr(lc($prefs{'language'}), 0, 2);   # en.utf8 -> en

         # find locale by matching language and character set, or just by language, or default to en_US.ISO8859-1
         my $locale = (grep { m/^$prefslanguage/ && m/\Q$prefscharset\E$/ } sort keys %{$config{'available_locales'}})[0] ||
                      (grep { m/^$prefslanguage/ } sort keys %{$config{'available_locales'}})[0] ||
                      'en_US.ISO8859-1';

         # add locale support
         $prefs{'language'} = join("_", (ow::lang::localeinfo($locale))[0,2]);
         $prefs{'charset'}  = (ow::lang::localeinfo($locale))[6];
         $prefs{'locale'} = $locale;
         loadlang ($locale);

         # update holidays
         my %holidays = (
                          'at'              => 'de_AT.ISO8859-1',
                          'cs'              => 'cs_CZ.ISO8859-2',
                          'de'              => 'de_DE.ISO8859-1',
                          'de_CH'           => 'de_CH.ISO8859-1',
                          'el'              => 'el_GR.ISO8859-7',
                          'en'              => 'en_US.ISO8859-1',
                          'en_GB'           => 'en_GB.ISO8859-1',
                          'en_HK'           => 'en_HK.ISO8859-1',
                          'en_US'           => 'en_US.ISO8859-1',
                          'es'              => 'es_ES.ISO8859-1',
                          'es_AR'           => 'es_AR.ISO8859-1',
                          'fi'              => 'fi_FI.ISO8859-1',
                          'hu'              => 'hu_HU.ISO8859-2',
                          'it'              => 'it_IT.ISO8859-1',
                          'ja_JP.Shift_JIS' => 'ja_JP.Shift_JIS',
                          'ja_JP.utf8'      => 'ja_JP.UTF-8',
                          'nl'              => 'nl_NL.ISO8859-1',
                          'pl'              => 'pl_PL.ISO8859-2',
                          'pt'              => 'pt_PT.ISO8859-1',
                          'pt_BR'           => 'pt_BR.ISO8859-1',
                          'sk'              => 'sk_SK.ISO8859-2',
                          'sl'              => 'sl_SI.CP1250',
                          'uk'              => 'uk_UA.KOI8-U',
                          'ur'              => 'ur_PK.UTF-8',
                          'zh_CN.GB2312'    => 'zh_CN.GB2312',
                          'zh_HK.Big5'      => 'zh_HK.Big5',
                          'zh_TW.Big5'      => 'zh_TW.Big5',
                        );
         $prefs{'calendar_holidaydef'} = $holidays{$prefs{'calendar_holidaydef'}} if exists $holidays{$prefs{'calendar_holidaydef'}};

         if (sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT)) {
            foreach my $key (@openwebmailrcitem) {
               print RC "$key=$prefs{$key}\n";
            }
            close(RC);
            writehistory("release upgrade - openwebmailrc by 20060721");
            writelog("release upgrade - openwebmailrc by 20060721");
         }
      }
   }

   return;
}

sub read_releasedatefile {
   # try every possible release date file
   my $releasedatefile=dotpath('release.date');
   $releasedatefile="$homedir/$config{'homedirfolderdirname'}/.release.date" if (! -f $releasedatefile);
   $releasedatefile="$homedir/.release.date" if (! -f $releasedatefile);

   my $d;
   if (sysopen(D, $releasedatefile, O_RDONLY)) {
      $d=<D>; chomp($d); close(D);
   }
   return($d);
}

sub update_releasedatefile {
   my $releasedatefile=dotpath('release.date');
   sysopen(D, $releasedatefile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $releasedatefile ($!)");
   print D $config{'releasedate'};
   close(D);
}

sub update_openwebmailrc {
   my $user_releasedate=$_[0];

   my $rcfile=dotpath('openwebmailrc');
   my $saverc=0;
   if (-f $rcfile) {
      $saverc=1 if ( $user_releasedate lt "20050501" );	# rc upgrade
      %prefs = readprefs() if ($saverc);		# load user old prefs + sys defaults
   } else {
      $saverc=1 if ($config{'auto_createrc'});		# rc auto create
   }
   if ($saverc) {
      sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $rcfile! ($!)");
      foreach my $key (@openwebmailrcitem) {
         print RC "$key=$prefs{$key}\n";
      }
      close(RC) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $rcfile!");
   }
   return;
}

1;
