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
   my ($_OFFSET, $_FROM, $_TO, $_DATE, $_SUBJECT, $_CONTENT_TYPE, $_STATUS, $_SIZE, $_REFERENCES, $_CHARSET)
       =(0,1,2,3,4,5,6,7,8,9);
   my %is_internal_dbkey= (
      METAINFO => 1,
      NEWMESSAGES => 1,
      INTERNALMESSAGES => 1,
      ALLMESSAGES => 1,
      ZAPSIZE => 1,
      "" => 1
   );

   my $folderdir="$homedir/$config{'homedirfolderdirname'}";

   my (@validfolders, $folderusage);
   getfolders(\@validfolders, \$folderusage);

   if ( $user_releasedate lt "20011101" ) {
      if ( -f "$folderdir/.filter.book" ) {
         $content="";
         ow::filelock::lock("$folderdir/.filter.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.filter.book");
         open(F, "$folderdir/.filter.book");
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
            open(F, ">$folderdir/.filter.book");
            print F $content;
            close(F);
         }
         ow::filelock::lock("$folderdir/.filter.book", LOCK_UN);
      }

      if ( -f "$folderdir/.pop3.book" ) {
         $content="";
         ow::filelock::lock("$folderdir/.pop3.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.pop3.book");
         open(F, "$folderdir/.pop3.book");
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
            open(F, ">$folderdir/.pop3.book");
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
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/$book");
            open(F, "$folderdir/$book");
            while (<F>) {
               last if (/\@\@\@/);
               s/:/\@\@\@/g;
               $content.=$_
            }
            close(F);
            if ($content ne "") {
               writehistory("release upgrade - $folderdir/$book by 20011117");
               writelog("release upgrade - $folderdir/$book by 20011117");
               open(F, ">$folderdir/$book");
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
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir ($!)");
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

   if ( $user_releasedate lt "20020108.02" ) {
      foreach my $foldername (@validfolders) {
         my ($folderfile, $folderdb)=get_folderpath_folderdb_old($user, $foldername);
         my (%FDB, @messageids, @attr);
         next if (!ow::dbm::exist($folderdb));

         ow::filelock::lock($folderfile, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderfile");
         open (FOLDER, $folderfile);
         ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} db $folderdb");

         if ( $FDB{'METAINFO'} eq ow::tool::metainfo($folderfile) ) { # upgrade only if hdb is uptodate
            @messageids=keys %FDB;
            foreach my $id (@messageids) {
               next if ($is_internal_dbkey{$id});
               @attr=split( /@@@/, $FDB{$id} );

               next if ( ($attr[$_CONTENT_TYPE] eq '' ||
                          $attr[$_CONTENT_TYPE] eq 'N/A' ||
                          $attr[$_CONTENT_TYPE] =~ /^text/i)
                       && $attr[$_SIZE]<4096 );

               next if ($attr[$_STATUS] =~ /T/i);

               if ($attr[$_SIZE]>65536) { # assume message > 64k has attachments
                  $attr[$_STATUS].="T";
               } else {
                  my $buff;
                  seek(FOLDER, $attr[$_OFFSET], 0);
                  read(FOLDER, $buff, $attr[$_SIZE]);
                  if ( $buff =~ /\ncontent\-type:.*;\s+name\s*=(.+?)\n/ims ||
                       $buff =~ /\n\s+name\s*=(.+?)\n/ims ||
                       $buff =~ /\ncontent\-disposition:.*;\s+filename\s*=(.+?)\n/ims ||
                       $buff =~ /\n\s+filename\s*=(.+?)\n/ims ||
                       $buff =~ /\nbegin [0-7][0-7][0-7][0-7]? [^\n\r]+\n/ims ) {
                     my $misc=$1;
                     if ($misc !~ /[\<\>]/ && $misc !~ /type=/i) {
                        $attr[$_STATUS].="T";
                     } else {
                        next;
                     }
                  } else {
                     next;
                  }
               }
               $FDB{$id}=join('@@@', @attr);
            }
         }
         ow::dbm::close(\%FDB, $folderdb);
         close(FOLDER);
         ow::filelock::lock($folderfile, LOCK_UN);
      }
      writehistory("release upgrade - $folderdir/* by 20020108.02");
      writelog("release upgrade - $folderdir/* by 20020108.02");
   }

   if ( $user_releasedate lt "20020108.02" ) {
      foreach my $foldername (@validfolders) {
         my ($folderfile, $folderdb)=get_folderpath_folderdb_old($user, $foldername);
         my (%FDB, @messageids, @attr);
         next if (!ow::dbm::exist($folderdb));

         ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} db $folderdb");
         @messageids=keys %FDB;
         foreach my $id (@messageids) {
            next if ($is_internal_dbkey{$id});
            @attr=split( /@@@/, $FDB{$id} );
            next if ( $attr[$_DATE] !~ m!(\d+)/(\d+)/(\d\d+)\s+(\d+):(\d+):(\d+)! );
            my @d = ($1, $2, $3, $4, $5, $6);
            if ($d[2]<50) {
               $d[2]+=2000;
            } elsif ($d[2]<=1900) {
               $d[2]+=1900;
            }
            $attr[$_DATE]=sprintf("%4d%02d%02d%02d%02d%02d",
					$d[2],$d[0],$d[1], $d[3],$d[4],$d[5]);
            $FDB{$id}=join('@@@', @attr);
         }
         ow::dbm::close(\%FDB, $folderdb);

         my $cachefile=ow::tool::untaint("$folderdb.cache");
         unlink($cachefile); # remove cache possiblely for old dbm
      }
      writehistory("release upgrade - $folderdir/.* db by 20020108.02");
      writelog("release upgrade - $folderdir/.* db by 20020108.02");
   }

   if ( $user_releasedate lt "20020601" ) {
      my $timeoffset=ow::datetime::gettimeoffset();
      foreach my $foldername (@validfolders) {
         my ($folderfile, $folderdb)=get_folderpath_folderdb_old($user, $foldername);
         my (%FDB, @messageids, @attr);
         next if (!ow::dbm::exist($folderdb));

         ow::filelock::lock($folderfile, LOCK_SH) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_locksh'} $folderfile");
         open (FOLDER, $folderfile);
         ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} db $folderdb");

         @messageids=keys %FDB;
         foreach my $id (@messageids) {
            next if ($is_internal_dbkey{$id});
            my ($buff, $delimiter, $datefield, $dateserial);
            @attr=split( /@@@/, $FDB{$id} );
            seek(FOLDER, $attr[$_OFFSET], 0);
            if (length($attr[$_FROM].$attr[$_TO].$attr[$_SUBJECT].$attr[$_CONTENT_TYPE].$attr[$_REFERENCES])>384) {
                read(FOLDER, $buff, 2048);
            } else {
                read(FOLDER, $buff, 1024);
            }
            if ( $buff =~ /^From (.+?)\n/ims) {
               $delimiter=$1;
               if ( $buff =~ /\nDate: (.+?)\n/ims ) {
                  $datefield=$1;
               }
               my $dateserial=ow::datetime::datefield2dateserial($datefield);
               my $deliserial=ow::datetime::delimiter2dateserial($delimiter, $config{'deliver_use_GMT'}, $prefs{'daylightsaving'}) ||
                              ow::datetime::gmtime2dateserial();
               if ($dateserial eq "") {
                  $dateserial=$deliserial;
               } elsif ($deliserial ne "") {
                   my $t=ow::datetime::dateserial2gmtime($deliserial)-ow::datetime::dateserial2gmtime($dateserial);
                   if ($t>86400*7 || $t<-86400) { # msg transmission time
                      # use deliverytime in case sender host may have wrong time configuration
                      $dateserial=$deliserial;
                   }
               }
               $attr[$_DATE]=$dateserial;
            } else {
               my $t=ow::datetime::dateserial2gmtime($attr[$_DATE]) -
                     ow::datetime::timeoffset2seconds($timeoffset);	# local -> gm
               $t-=3600 if (ow::datetime::is_dst($t, $timeoffset));
               $attr[$_DATE]=ow::datetime::gmtime2dateserial($t);
            }
            $FDB{$id}=join('@@@', @attr);
         }
         ow::dbm::close(\%FDB, $folderdb);
         close(FOLDER);
         ow::filelock::lock($folderfile, LOCK_UN);
      }
      writehistory("release upgrade - $folderdir/* by 20020601");
      writelog("release upgrade - $folderdir/* by 20020601");
   }

   if ( $user_releasedate lt "20021111" ) {
      foreach my $foldername (@validfolders) {
         my ($folderfile, $folderdb)=get_folderpath_folderdb_old($user, $foldername);
         my (%FDB, @messageids, @attr);
         next if (!ow::dbm::exist($folderdb));

         ow::dbm::open(\%FDB, $folderdb, LOCK_EX) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} db $folderdb");
         @messageids=keys %FDB;
         foreach my $id (@messageids) {
            next if ($is_internal_dbkey{$id});
            @attr=split( /@@@/, $FDB{$id} );
            if ( $attr[$_CHARSET] eq "" &&
                 $attr[$_CONTENT_TYPE]=~/charset="?([^\s"';]*)"?\s?/i) {
               $attr[$_CHARSET]=$1;
               $FDB{$id}=join('@@@', @attr);
            }
         }
         ow::dbm::close(\%FDB, $folderdb);
      }
      writehistory("release upgrade - $folderdir/.* db by 20021111.02");
      writelog("release upgrade - $folderdir/.* db by 20021111.02");
   }

   if ( $user_releasedate lt "20021201" ) {
      if ( -f "$folderdir/.calendar.book" ) {
         my $content='';
         ow::filelock::lock("$folderdir/.calendar.book", LOCK_EX) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.calendar.book");
         open(F, "$folderdir/.calendar.book");
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
            open(F, ">$folderdir/.calendar.book");
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
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $folderdir/.pop3.book");
         open(F, "$folderdir/.pop3.book");
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
            open(F, ">$folderdir/.pop3.book");
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
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $folderdir ($!)");
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
}

# used by upgrade routine before 20031128 to locate folder db
sub get_folderpath_folderdb_old {
   my ($username, $foldername)=@_;
   my ($folderfile, $folderdb)=get_folderpath_folderdb($username, $foldername);
   if ($foldername eq 'INBOX') {
      $folderdb="$homedir/$config{'homedirfolderdirname'}/.$username";
   } else {
      $folderdb="$homedir/$config{'homedirfolderdirname'}/$foldername";
      ($folderdb=~/^(.+)\/(.*)$/) && ($folderdb = "$1/.$2");
   }
   return($folderfile, ow::tool::untaint($folderdb));
}

sub read_releasedatefile {
   # try every possible release date file
   my $releasedatefile=dotpath('release.date');
   $releasedatefile="$homedir/$config{'homedirfolderdirname'}/.release.date" if (! -f $releasedatefile);
   $releasedatefile="$homedir/.release.date" if (! -f $releasedatefile);

   my $d;
   if (open(D, $releasedatefile)) {
      $d=<D>; chomp($d); close(D);
   }
   return($d);
}

sub update_releasedatefile {
   my $releasedatefile=dotpath('release.date');
   open(D, ">$releasedatefile") or 
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $releasedatefile ($!)");
   print D $config{'releasedate'};
   close(D);
}

1;
