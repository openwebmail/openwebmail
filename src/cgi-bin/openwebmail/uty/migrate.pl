#
# this script is used to change the default mail folderdir for users.
# It is mainly for doing upgrade from neomail or neomail professional 
# to Open WebMail.
#
# 03/15/2001 tung@turtle.ee.ncku.edu.tw
#
#
# syntax:
#
# perl migrate.pl [olduserprefsdir] [userprefsdir] [oldhomedirfolderdirname] [homedirfolderdirname]
#
# 	olduserprefsdir : 
#	neomail's userprefsdir, ex: /usr/local/www/cgi/neomail/etc/users
#
# 	userprefsdir: 
#	open webmail's userprefsdir, ex: /usr/local/www/cgi/openwebmail/etc/users
#
# 	oldhomedirfolderdirname: 
#	folderdirname for each user used by neomail, ex: neomail
#
# 	homedirfolderdirname: 
#	folderdirname used for each user to be used in open webmail, ex: mail
#
# example:
#
# perl /usr/local/www/cgi-bin/neomail/etc/users /usr/local/www/cgi-bin/openwebmail/etc/users neomail mail
#

if ( $#ARGV ne 3 ) {
   print("perl migrate.pl [olduserprefsdir] [userprefsdir] [oldhomedirfolderdirname] [homedirfolderdirname]\n");
   exit 1;
}

$olduserprefsdir=$ARGV[0];
$userprefsdir=$ARGV[1];
$oldhomedirfolderdirname=$ARGV[2];
$homedirfolderdirname=$ARGV[3];

if ( ! -d "$userprefsdir" ) {
   print("\$userprefsdir $userprefsdir doesn't exist, abort\n");
   exit 1;
}

# unbuffered print
$|=1;


# move user's prefs
print ("============== move all user preferences ==============\n");
print "mv $olduserprefsdir/* $userprefsdir/\n";
`mv $olduserprefsdir/* $userprefsdir/ 2>/dev/null`;


# move user mails
open (PASS, "/etc/passwd");
while (<PASS>) {
   $user=(split(/:/))[0];

   ($login, $pass, $uid, $ugid, $homedir) = (getpwnam($user))[0,1,2,3,7];
   $gid = getgrnam('mail');
   $folderdir = "$homedir/$homedirfolderdirname";
   $oldfolderdir = "$homedir/$oldhomedirfolderdirname";

   if ( ! -d "$oldfolderdir" ) {
      next;
   }

   print ("============== move '$user' folders ==============\n");

   if ( -l $folderdir ) {	# unlink symbolic link to prevent loop
      unlink($folderdir);
   }

   if ( ! -d $folderdir ) {
      print "mkdir $folderdir\n";
      mkdir ("$folderdir", oct(700));
      chown ("$uid", "$ugid", "$folderdir");
   }
            
   opendir (OLDFOLDERDIR, "$oldfolderdir");

   while (defined($oldfilename = readdir(OLDFOLDERDIR))) {
      if ( $oldfilename eq "." || $oldfilename eq ".." ) {
         next;
      }
      if ( -l "$oldfolderdir/$oldfilename" ) {	# remove symboliclink to avoid loop
         print "rm symbliclink $oldfolderdir/$oldfilename\n";
         unlink("$oldfolderdir/$oldfilename");
         next;
      }

      $filename=$oldfilename;
      $filename=~s/saved_messages/saved-messages/;
      $filename=~s/sent_mail/sent-mail/;
      $filename=~s/neomail_trash/mail-trash/;
      if ( -l "$folderdir/$filename" ) {	# remove symboliclink to avoid loop
         print "rm symboliclink $folderdir/$filename\n";
         unlink("$folderdir/$filename");
      }

      if ( -f "$folderdir/$filename" && $filename !~/^\./ ) {
         print "cat $oldfolderdir/$oldfilename >> $folderdir/$filename\n";
         `cat "$oldfolderdir/$oldfilename" >> "$folderdir/$filename"`;

         print "rm $oldfolderdir/$oldfilename\n";
         unlink("$oldfolderdir/$oldfilename");

      } else {
         print "mv $oldfolderdir/$oldfilename $folderdir/$filename\n";
         `mv "$oldfolderdir/$oldfilename" "$folderdir/$filename"`;

      }
   }
   closedir (OLDFOLDERDIR);
   print "rmdir $oldfolderdir\n";
   `rmdir $oldfolderdir`;

   if ( -f "$userprefsdir/$user/addressbook" ) {
      print "mv $userprefsdir/$user/addressbook $folderdir/.address.book\n";
      `mv $userprefsdir/$user/addressbook $folderdir/.address.book`;
      chown($uid, $ugid, "$userprefsdir/$user/addressbook $folderdir/.address.book");
   }
}
print ("============== migration is done ==============\n");
