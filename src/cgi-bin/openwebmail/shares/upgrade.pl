
#                              The BSD License
#
#  Copyright (c) 2009-2010, The OpenWebMail Project
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

# upgrade.pl - routines to do upgrades to user data between releases
# these routines convert data file formats from old releases to most current releases

use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);
use MIME::Base64;

use vars qw(%config %prefs $po);
use vars qw($domain $user $uuid $homedir);
use vars qw(@openwebmailrcitem);

sub upgrade_20030323 {
   # rename old homedir for compatibility
   # called only if homedir does not exist
   if (!$config{use_syshomedir} && $config{auth_withdomain} && !-d $homedir && -d "$config{ow_usersdir}/$user\@$domain") {
      my $olddir = ow::tool::untaint("$config{ow_usersdir}/$user\@$domain");

      rename($olddir, $homedir) or
         openwebmailerror(gettext('Cannot rename directory:') . " $olddir -> $homedir ($!)");

      writelog("release upgrade - rename $olddir to $homedir by 20030323");
   }
}

sub upgrade_20021218 {
   # called only if folderdir does not exist
   my $user_releasedate = shift;

   my $folderdir = "$homedir/$config{homedirfolderdirname}";

   # mv folders from $homedir to $folderdir($homedir/mail/) for old ow_usersdir
   if ($user_releasedate lt '20021218') {
      if (!$config{use_syshomedir} && -f "$homedir/.openwebmailrc" && !-f "$folderdir/.openwebmailrc") {
         opendir(D, $homedir) or writelog("cannot open directory $homedir");

         my @files = readdir(D);

         closedir(D) or writelog("cannot close directory $homedir ($!)");

         foreach my $file (@files) {
            next if $file eq '.' || $file eq '..' || $file eq $config{homedirfolderdirname};
            $file = ow::tool::untaint($file);
            rename("$homedir/$file", "$folderdir/$file")
               or writelog("cannot rename file $homedir/$file -> $folderdir/$file ($!)");
         }

         writelog("release upgrade - mv $homedir/* to $folderdir/* by 20021218");
      }
   }
}

sub upgrade_all {
   # called if user releasedate is older than current releasedate
   my $user_releasedate = shift;

   my $content = '';

   my $folderdir = "$homedir/$config{homedirfolderdirname}";

   my (@validfolders, $inboxusage, $folderusage) = (0,0,0);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   if ($user_releasedate lt '20011101') {
      my $filterbook = "$folderdir/.filter.book";

      if (-f $filterbook) {
         ow::filelock::lock($filterbook, LOCK_EX) or
            openwebmailerror(gettext('Cannot lock file:') . " $filterbook");

         sysopen(F, $filterbook, O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $filterbook ($!)");

         $content = '';

         while (my $line = <F>) {
            chomp($line);

            my ($priority, $ruletype, $include, $text, $op, $destination, $enable) = split(/\@\@\@/, $line);

            if ($enable eq '') {
               ($priority, $ruletype, $include, $text, $destination, $enable) = split(/\@\@\@/, $line);
               $op = 'move';
            }

            $ruletype = 'textcontent' if $ruletype eq 'body';
            $content .= "$priority\@\@\@$ruletype\@\@\@$include\@\@\@$text\@\@\@$op\@\@\@$destination\@\@\@$enable\n";
         }

         close(F) or writelog("cannot close file $filterbook ($!)");

         if ($content ne '') {
            writehistory("release upgrade - $filterbook by 20011101");
            writelog("release upgrade - $filterbook by 20011101");

            sysopen(F, $filterbook, O_WRONLY|O_TRUNC|O_CREAT) or
               openwebmailerror(gettext('Cannot open file:') . " $filterbook ($!)");

            print F $content;

            close(F) or writelog("cannot close file $filterbook ($!)");
         }

         ow::filelock::lock($filterbook, LOCK_UN) or writelog("cannot unlock file $filterbook");
      }

      my $pop3book = "$folderdir/.pop3.book";

      if (-f $pop3book) {
         $content = '';

         ow::filelock::lock($pop3book, LOCK_EX) or
            openwebmailerror(gettext('Cannot lock file:') . " $pop3book");

         sysopen(F, $pop3book, O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $pop3book ($!)");

         while (my $line = <F>) {
            chomp($line);

            my @a = split(/:/, $line);

            my $pop3host   = '';
            my $pop3user   = '';
            my $pop3passwd = '';
            my $pop3lastid = '';
            my $pop3del    = '';
            my $enable     = '';

            if ($#a == 4) {
               ($pop3host, $pop3user, $pop3passwd, $pop3del, $pop3lastid) = @a;
               $enable = 1;
            } elsif ($a[3] =~ m/\@/) {
               my $pop3email = '';
               ($pop3host, $pop3user, $pop3passwd, $pop3email, $pop3del, $pop3lastid) = @a;
               $enable = 1;
            } else {
               ($pop3host, $pop3user, $pop3passwd, $pop3lastid, $pop3del, $enable) = @a;
            }

            $content .= "$pop3host\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@RESERVED\@\@\@$pop3del\@\@\@$enable\n";
         }

         close(F) or writelog("cannot close file $pop3book ($!)");

         if ($content ne '') {
            writehistory("release upgrade - $pop3book by 20011101");
            writelog("release upgrade - $pop3book by 20011101");

            sysopen(F, $pop3book, O_WRONLY|O_TRUNC|O_CREAT) or
               openwebmailerror(gettext('Cannot open file:') . " $pop3book ($!)");

            print F $content;

            close(F) or writelog("cannot close file $pop3book ($!)");
         }

         ow::filelock::lock($pop3book, LOCK_UN) or writelog("cannot unlock file $pop3book");
      }
   }

   if ($user_releasedate lt '20011117') {
      for my $book ('.from.book', '.address.book', '.pop3.book') {
         if (-f "$folderdir/$book") {
            $content = '';

            ow::filelock::lock("$folderdir/$book", LOCK_EX) or
               openwebmailerror(gettext('Cannot lock file:') . " $folderdir/$book");

            sysopen(F, "$folderdir/$book", O_RDONLY) or
               openwebmailerror(gettext('Cannot open file:') . " $folderdir/$book ($!)");

            while (my $line = <F>) {
               last if $line =~ m/\@\@\@/;
               $line =~ s/:/\@\@\@/g;
               $content .= $line;
            }

            close(F) or writelog("cannot close file $folderdir/$book ($!)");

            if ($content ne '') {
               writehistory("release upgrade - $folderdir/$book by 20011117");
               writelog("release upgrade - $folderdir/$book by 20011117");

               sysopen(F, "$folderdir/$book", O_WRONLY|O_TRUNC|O_CREAT) or
                  openwebmailerror(gettext('Cannot open file:') . " $folderdir/$book ($!)");

               print F $content;

               close(F) or writelog("cannot close file $folderdir/$book ($!)");
            }

            ow::filelock::lock("$folderdir/$book", LOCK_UN) or writelog("cannot unlock file $folderdir/$book");
         }
      }
   }

   if ($user_releasedate lt '20011216') {
      opendir(FOLDERDIR, $folderdir) or
         openwebmailerror(gettext('Cannot read directory:') . " $folderdir ($!)");

      my @cachefiles = map { "$folderdir/$_" } grep { m/^\..+\.cache$/ } readdir(FOLDERDIR);

      closedir(FOLDERDIR) or writelog("cannot close directory $folderdir ($!)");

      if (scalar @cachefiles > 0) {
         writehistory("release upgrade - $folderdir/*.cache by 20011216");
         writelog("release upgrade - $folderdir/*.cache by 20011216");
         # remove old .cache since its format is not compatible with new one
         unlink(@cachefiles);
      }
   }

   if ($user_releasedate lt '20021201') {
      if (-f "$folderdir/.calendar.book") {
         my $content = '';

         ow::filelock::lock("$folderdir/.calendar.book", LOCK_EX) or
            openwebmailerror(gettext('Cannot lock file:') . " $folderdir/.calendar.book");

         sysopen(F, "$folderdir/.calendar.book", O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $folderdir/.calendar.book ($!)");

         while (my $line = <F>) {
            next if $line =~ m/^#/;

            chomp($line);

            # fields: idate, starthourmin, endhourmin, string, link, email, color
            my @a = split(/\@\@\@/, $line);

            if ($#a == 7) {
               $content .= join('@@@', @a);
            } elsif ($#a == 6) {
               $content .= join('@@@', @a, 'none');
            } elsif ($#a == 5) {
               $content .= join('@@@', @a, ,'0', 'none');
            } elsif ($#a < 5) {
               $content .= join('@@@', $a[0], $a[1], $a[2], '0', $a[3], $a[4], '0', 'none');
            }

            $content .= "\n";
         }

         close(F) or writelog("cannot close file $folderdir/.calendar.book ($!)");;

         if ($content ne '') {
            writehistory("release upgrade - $folderdir/.calendar.book by 20021201");
            writelog("release upgrade - $folderdir/.calendar.book by 20021201");

            sysopen(F, "$folderdir/.calendar.book", O_WRONLY|O_TRUNC|O_CREAT) or
               openwebmailerror(gettext('Cannot open file:') . " $folderdir/.calendar.book ($!)");

            print F $content;

            close(F) or writelog("cannot close file $folderdir/.calendar.book ($!)");;
         }

         ow::filelock::lock("$folderdir/.calendar.book", LOCK_UN) or writelog("cannot unlock file $folderdir/.calendar.book");
      }
   }

   if ($user_releasedate lt '20030312') {
      # change the owner of files under ow_usersdir/username from root to $uuid
      if(!$config{use_syshomedir} && -d $homedir) {
         my $chown_bin = '';

         foreach my $bin ('/bin/chown', '/usr/bin/chown', '/sbin/chown', '/usr/sbin/chown') {
            $chown_bin = $bin if -x $bin;
         }

         system($chown_bin, '-R', $uuid, $homedir) == 0 or writelog("chown failed: $@");

         writelog("release upgrade - chown -R $uuid $homedir/* by 20030312");
      }
   }

   if ($user_releasedate lt '20030528') {
      if (-f "$folderdir/.pop3.book") {
         $content = '';

         ow::filelock::lock("$folderdir/.pop3.book", LOCK_EX) or
            openwebmailerror(gettext('Cannot lock file:') . " $folderdir/.pop3.book");

         sysopen(F, "$folderdir/.pop3.book", O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $folderdir/.pop3.book ($!)");

         while (my $line = <F>) {
            chomp($line);

            my @a = split(/\@\@\@/, $line);

            my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $enable) = @a;

            if ($pop3port !~ m/^\d+$/ || $pop3port > 65535) {
               # not port number? old format!
               ($pop3host, $pop3user, $pop3passwd, $pop3del, $enable) = @a[0,1,2,4,5];
               $pop3port = 110;

               # not secure, but better than plaintext
               $pop3passwd = $pop3passwd ^ substr($pop3host, 5, length($pop3passwd));
               $pop3passwd = encode_base64($pop3passwd, '');
            }

            $content .= "$pop3host\@\@\@$pop3port\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable\n";
         }

         close(F) or writelog("cannot close file $folderdir/.pop3.book ($!)");

         if ($content ne '') {
            writehistory("release upgrade - $folderdir/.pop3.book by 20030528");
            writelog("release upgrade - $folderdir/.pop3.book by 20030528");

            sysopen(F, "$folderdir/.pop3.book", O_WRONLY|O_TRUNC|O_CREAT) or
               openwebmailerror(gettext('Cannot open file:') . " $folderdir/.pop3.book ($!)");

            print F $content;

            close(F) or writelog("cannot close file $folderdir/.pop3.book ($!)");;
         }

         ow::filelock::lock("$folderdir/.pop3.book", LOCK_UN) or writelog("cannot unlock file $folderdir/.pop3.book");
      }
   }

   if ($user_releasedate lt '20031128') {
      my %is_dotpath = ();

      $is_dotpath{$_} = 1 for qw(
                                   openwebmailrc
                                   release.date
                                   history.log
                                   filter.book
                                   filter.check
                                   from.book
                                   address.book
                                   stationery.book
                                   trash.check
                                   search.cache
                                   signature
                                   calendar.book
                                   notify.check
                                   webdisk.cache
                                   pop3.book
                                   pop3.check
                                   authpop3.book
                                );

      opendir(FOLDERDIR, $folderdir) or
         openwebmailerror(gettext('Cannot open directory:') . " $folderdir ($!)");

      while (defined(my $file = readdir(FOLDERDIR))) {
         next if $file eq '..' || $file !~ m/^\./;

         $file =~ s/^\.//;

         if ((exists $is_dotpath{$file} && $is_dotpath{$file}) || $file =~ m/^uidl\./ || $file =~ m/^filter\.book/) {
            rename(ow::tool::untaint("$folderdir/.$file"), dotpath($file));
         } elsif ($file =~ m/\.(lock|cache|db|dir|pag|db\.lock|dir\.lock|pag\.lock)$/) {
            rename(ow::tool::untaint("$folderdir/.$file"), ow::tool::untaint(dotpath('db')."/$file"));
         }
      }

      closedir(FOLDERDIR) or writelog("cannot close directory $folderdir ($!)");

      writehistory("release upgrade - $folderdir/.* to .openwebmail/ by 20031128");
      writelog("release upgrade - $folderdir/.* to .openwebmail/ by 20031128");
   }

   if ($user_releasedate lt '20040111') {
      my $pop3book = dotpath('pop3.book');

      if (-f $pop3book) {
         $content = '';

         ow::filelock::lock($pop3book, LOCK_EX) or
            openwebmailerror(gettext('Cannot lock file:') . " $pop3book ($!)");

         sysopen(F, $pop3book, O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $pop3book ($!)");

         while (my $line = <F>) {
            chomp($line);

            my @a = split(/\@\@\@/, $line);
            if ($#a == 6) {
               $content .= "$_\n";
            } else {
               my ($pop3host, $pop3port, $pop3user, $pop3passwd, $pop3del, $enable) = @a;
               my $pop3ssl = 0;
               $content .= "$pop3host\@\@\@$pop3port\@\@\@$pop3ssl\@\@\@$pop3user\@\@\@$pop3passwd\@\@\@$pop3del\@\@\@$enable\n";
            }
         }

         close(F) or writelog("cannot close file $pop3book ($!)");

         if ($content ne '') {
            writehistory("release upgrade - $pop3book by 20040111");
            writelog("release upgrade - $pop3book by 20040111");

            sysopen(F, $pop3book, O_WRONLY|O_TRUNC|O_CREAT) or
               openwebmailerror(gettext('Cannot open file:') . " $pop3book ($!)");

            print F $content;

            close(F) or writelog("cannot close file $pop3book ($!)");
         }

         ow::filelock::lock($pop3book, LOCK_UN) or writelog("cannot unlock file $pop3book");
      }
   }

   if ($user_releasedate lt '20040724') {
      my $filterbook   = dotpath('filter.book');
      my $filterruledb = dotpath('filter.ruledb');

      # rename filter.book.db -> filter.ruledb.db
      ow::dbm::renamedb($filterbook, $filterruledb) or writelog("cannot rename file $filterbook to $filterruledb");

      writehistory("release upgrade - mv $filterbook to $filterruledb by 20040724");
      writelog("release upgrade - mv $filterbook to $filterruledb by 20040724");
   }

   if ($user_releasedate lt '20041101') {
      my $rcfile = dotpath('openwebmailrc');

      if (-f $rcfile) {
         %prefs = readprefs();
         $prefs{abook_width}              = $config{default_abook_width};
         $prefs{abook_height}             = $config{default_abook_height};
         $prefs{abook_listviewfieldorder} = $config{default_abook_listviewfieldorder};

         # $rcfile is written back in update_openwebmailrc()
         writehistory('release upgrade - openwebmailrc by 20041101');
         writelog('release upgrade - openwebmailrc by 20041101');
      }
   }

   if ($user_releasedate lt '20041107') {
      my $calbookfile = dotpath('calendar.book');

      my $data = '';

      sysopen(F, $calbookfile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $calbookfile ($!)");

      while (my $line = <F>) {
         chomp($line);
         my @a = split(/\@\@\@/, $line);
         $a[8] = $prefs{charset} if !defined $a[8] || $a[8] eq '';
         $data .= join('@@@', @a) . "\n";
      }

      close(F) or writelog("cannot close file $calbookfile ($!)");

      sysopen(F, $calbookfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $calbookfile ($!)");

      print F $data;

      close(F) or writelog("cannot close file $calbookfile ($!)");

      writehistory("release upgrade - $calbookfile charset by 20041107");
      writelog("release upgrade - $calbookfile charset by 20041107");
   }

   if ($user_releasedate lt '20050206') {
      my $filterbookfile = dotpath('filter.book');

      my $data = '';

      sysopen(F, $filterbookfile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $filterbookfile ($!)");

      while (my $line = <F>) {
         chomp($line);
         my @a = split(/\@\@\@/, $line);
         $a[7] = $prefs{charset} if !defined $a[7] || $a[7] eq '';
         $data .= join('@@@', @a) . "\n";
      }

      close(F) or writelog("cannot close file $filterbookfile ($!)");

      sysopen(F, $filterbookfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $filterbookfile ($!)");

      print F $data;

      close(F) or writelog("cannot close file $filterbookfile ($!)");

      writehistory("release upgrade - $filterbookfile charset by 20050206");
      writelog("release upgrade - $filterbookfile charset by 20050206");
   }

   if ($user_releasedate lt '20050319') {
      my $calbookfile = dotpath('calendar.book');

      my $data = '';

      sysopen(F, $calbookfile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $calbookfile ($!)");

      while (my $line = <F>) {
         chomp($line);
         my @a = split(/\@\@\@/, $line);
         $a[9] = 1 if !defined $a[9] || $a[9] eq '';
         $data .= join('@@@', @a) . "\n";
      }

      close(F) or writelog("cannot close file $calbookfile ($!)");

      sysopen(F, $calbookfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $calbookfile ($!)");

      print F $data;

      close(F) or writelog("cannot close file $calbookfile ($!)");

      writehistory("release upgrade - $calbookfile charset by 20050319");
      writelog("release upgrade - $calbookfile charset by 20050319");
   }

   if ($user_releasedate lt '20050410') {
      my $rcfile = dotpath('openwebmailrc');

      if (-f $rcfile) {
         %prefs = readprefs();
         if ($prefs{sort} eq 'date') {
            $prefs{sort} = 'date_rev';

            sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT) or
               openwebmailerror(gettext('Cannot open file:') . " $rcfile ($!)");

            print RC "$_=$prefs{$_}\n" for @openwebmailrcitem;

            close(RC) or writelog("cannot close file $rcfile");

            writehistory('release upgrade - openwebmailrc by 20050410');
            writelog('release upgrade - openwebmailrc by 20050410');
         }
      }
   }

   if ($user_releasedate lt '20060721') {
      # users preferences need to be updated to reflect move to locales instead of just lang/charset
      my $rcfile = dotpath('openwebmailrc');
      if (-f $rcfile) {
         %prefs = readprefs();

         my $prefscharset = uc($prefs{charset});                     # utf-8 -> UTF-8
         $prefscharset =~ s#[-_\s]+##g;                              # UTF-8 -> UTF8
         $prefscharset = $ow::lang::charactersets{$prefscharset}[0]; # OWM Locale style

         my $prefslanguage = substr(lc($prefs{language}), 0, 2);     # en.utf8 -> en

         # find locale by matching language and character set, or just by language, or default to en_US.UTF-8
         my $locale = (grep { m/^$prefslanguage/ && m/\Q$prefscharset\E$/ } sort keys %{$config{available_locales}})[0]
                      || (grep { m/^$prefslanguage/ } sort keys %{$config{available_locales}})[0]
                      || 'en_US.UTF-8';

         # add locale support
         $prefs{language} = join("_", (ow::lang::localeinfo($locale))[0,1]);
         $prefs{charset}  = (ow::lang::localeinfo($locale))[4];
         $prefs{locale}   = $locale;
         $po = loadlang($locale);

         # update holidays
         my %holidays = (
                          'at'              => 'de_AT.ISO8859-1',
                          'cs'              => 'cs_CZ.ISO8859-2',
                          'de'              => 'de_DE.ISO8859-1',
                          'de_CH'           => 'de_CH.ISO8859-1',
                          'el'              => 'el_GR.ISO8859-7',
                          'en'              => 'en_US.UTF-8',
                          'en_GB'           => 'en_GB.ISO8859-1',
                          'en_HK'           => 'en_HK.ISO8859-1',
                          'en_US'           => 'en_US.UTF-8',
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
                          'pt_BR'           => 'pt_BR.UTF-8',
                          'sk'              => 'sk_SK.ISO8859-2',
                          'sl'              => 'sl_SI.CP1250',
                          'uk'              => 'uk_UA.KOI8-U',
                          'ur'              => 'ur_PK.UTF-8',
                          'zh_CN.GB2312'    => 'zh_CN.GB2312',
                          'zh_HK.Big5'      => 'zh_HK.Big5',
                          'zh_TW.Big5'      => 'zh_TW.Big5',
                        );

         $prefs{calendar_holidaydef} = $holidays{$prefs{calendar_holidaydef}} if exists $holidays{$prefs{calendar_holidaydef}};

         sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(gettext('Cannot open file:') . " $rcfile ($!)");

         print RC "$_=$prefs{$_}\n" for @openwebmailrcitem;

         close(RC) or writelog("cannot close file $rcfile");

         writehistory('release upgrade - openwebmailrc by 20060721');
         writelog('release upgrade - openwebmailrc by 20060721');
      }
   }

   if ($user_releasedate lt '20090606') {
      # users preferences need to be updated to add the preference to show lunar calendar days or not
      my $rcfile = dotpath('openwebmailrc');

      if (-f $rcfile) {
         %prefs = readprefs();

         # automatically show lunar days for zh_TW.* and zh_CN.* locales (like old behavior)
         $prefs{calendar_showlunar} = $prefs{locale} =~ m/^(?:zh_TW|zh_CN)/ ? 1 : 0;

         sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(gettext('Cannot open file:') . " $rcfile ($!)");

         print RC "$_=$prefs{$_}\n" for @openwebmailrcitem;

         close(RC) or writelog("cannot close file $rcfile");

         writehistory('release upgrade - openwebmailrc by 20090607');
         writelog('release upgrade - openwebmailrc by 20090607');
      }
   }

#   if ($user_releasedate lt '20101116') {
#      # users preferences need to be updated to accomodate the new layouts and styles
#      my $rcfile = dotpath('openwebmailrc');
#      if (-f $rcfile) {
#         %prefs = readprefs();
#
#         $prefs{style} = lc($prefs{style});
#
#         if (sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT)) {
#            foreach my $key (@openwebmailrcitem) {
#               print RC "$key=$prefs{$key}\n";
#            }
#            close(RC);
#            writehistory("release upgrade - openwebmailrc by 20100605");
#            writelog("release upgrade - openwebmailrc by 20100605");
#         }
#      }
#   }

   return;
}

sub read_releasedatefile {
   # try every possible release date file
   my $releasedatefile = dotpath('release.date');
   $releasedatefile    = "$homedir/$config{homedirfolderdirname}/.release.date" if !-f $releasedatefile;
   $releasedatefile    = "$homedir/.release.date" if !-f $releasedatefile;

   sysopen(D, $releasedatefile, O_RDONLY) or
      openwebmailerror(gettext('Cannot open file:') . " $releasedatefile ($!)");

   my $d = <D>;

   chomp($d);

   close(D) or writelog("cannot close file $releasedatefile ($!)");

   return $d;
}

sub update_releasedatefile {
   my $releasedatefile = dotpath('release.date');

   sysopen(D, $releasedatefile, O_WRONLY|O_TRUNC|O_CREAT) or
      openwebmailerror(gettext('Cannot open file:') . " $releasedatefile ($!)");

   print D $config{releasedate};

   close(D);
}

sub update_openwebmailrc {
   my $user_releasedate = shift;

   my $rcfile = dotpath('openwebmailrc');
   my $saverc = 0;

   if (-f $rcfile) {
      $saverc = 1 if $user_releasedate lt '20050501'; # rc upgrade
      %prefs  = readprefs() if $saverc;               # load user old prefs + sys defaults
   } else {
      $saverc = 1 if $config{auto_createrc};          # rc auto create
   }

   if ($saverc) {
      sysopen(RC, $rcfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(gettext('Cannot open file:') . " $rcfile ($!)");

      print RC "$_=$prefs{$_}\n" for @openwebmailrcitem;

      close(RC) or writelog("cannot close file $rcfile");
   }

   return;
}

1;
