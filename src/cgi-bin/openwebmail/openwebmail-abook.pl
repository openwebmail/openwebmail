#!/usr/bin/suidperl -T
#
# openwebmail-abook.pl - address book program
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1 }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { $SCRIPT_DIR=$1 }
}
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

foreach (qw(PATH ENV BASH_ENV CDPATH IFS TERM)) { $ENV{$_}='' }	# secure ENV
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/dbm.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "shares/ow-shared.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err);	# defined in lang/xy

# local globals
use vars qw($folder $messageid);
use vars qw($sort $page);
use vars qw($escapedmessageid $escapedfolder);

########## MAIN ##################################################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop

userenv_init();

if (!$config{'enable_webmail'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

$folder = param('folder') || 'INBOX';
$page = param('page') || 1;
$sort = param('sort') || $prefs{'sort'} || 'date';
$messageid=param('message_id') || '';

$escapedfolder=ow::tool::escapeURL($folder);
$escapedmessageid=ow::tool::escapeURL($messageid);

my $action = param('action')||'';
if ($action eq "addressbook") {
   addressbook();
} elsif ($action eq "editaddresses") {
   editaddresses();
} elsif ($action eq "addaddress") {
   modaddress("add");
} elsif ($action eq "deleteaddress") {
   modaddress("delete");
} elsif ($action eq "clearaddress") {
   clearaddress();
} elsif ($action eq "importabook") {
   importabook();
} elsif ($action eq "exportabook") {
   exportabook();
} elsif ($action eq "importabook_pine") {
   importabook_pine();
} elsif ($action eq "exportabook_pine") {
   exportabook_pine();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}

openwebmail_requestend();
########## END MAIN ##############################################

########## ADDRESSBOOK ###########################################
sub addressbook {
   my $elist = param('elist') || '';	# emails not checked or not convered by addressbook
   my $tolist = join(",", param('to')) || '';	# emails checked in addressbook window
   my $form=param('form')||'';
   my $field=param('field')||'';

   my %emailhash=();	# store all entries in emailhash
   foreach my $u (ow::tool::str2list($elist,0), ow::tool::str2list($tolist,0)) {
      if ($u) {
         my $email=(ow::tool::email2nameaddr($u))[1];
         $emailhash{$email}=$u;
      }
   }

   my $abook_keyword = param('abook_keyword') || '';
   my $abook_searchtype = param('abook_searchtype') || 'name';
   my $results_flag = 0;

   my ($html, $temphtml);
   $html = applystyle(readtemplate("addressbook.template"));

   if (defined($lang_text{$field})) {
      $temphtml=$lang_text{$field}.": $lang_text{'abook'}";
   } else {
      $temphtml=uc($field).": $lang_text{'abook'}";
   }
   $html =~ s/\@\@\@ADDRESSBOOKFOR\@\@\@/$temphtml/g;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                   	 -name=>'addressbook');
   $html =~ s/\@\@\@STARTADDRESSFORM\@\@\@/$temphtml/g;

   my %searchtypelabels = ('name'=>$lang_text{'name'},
                           'email'=>$lang_text{'email'},
                           'note'=>$lang_text{'note'},
                           'all'=>$lang_text{'all'});
   $temphtml = popup_menu(-name=>'abook_searchtype',
                           -default=>$abook_searchtype || 'name',
                           -values=>['name', 'email', 'note', 'all'],
                           -labels=>\%searchtypelabels);
   $temphtml .= textfield(-name=>'abook_keyword',
                          -default=>$abook_keyword,
                          -size=>'16',
                          -override=>'1');
   $temphtml .= "&nbsp;";
   $temphtml .= submit(-name=>$lang_text{'search'},
	               -class=>'medtext');
   $html =~ s/\@\@\@SEARCH\@\@\@/$temphtml/g;

   $temphtml="";
   $temphtml .= qq|<tr><td colspan="4">&nbsp;</td></tr>|;

   my $addrbookfile=dotpath('address.book');

   my $count=0;
   my $bgcolor = $style{"tablerow_dark"};
   if ( -f $addrbookfile ) {
      my %addresses=();
      my %notes=();

      # read openwebmail addressbook
      if ( open(ABOOK, $addrbookfile) ) {
         while (<ABOOK>) {
            my ($name, $email, $note) = split(/\@\@\@/, $_, 3);
            chomp($email);
            chomp($note);
	    next if (!is_entry_matched($abook_keyword,$abook_searchtype, $name,$note,$email));
            $addresses{$name} = $email;
            $notes{$name} = $note;
         }
         close (ABOOK);
      }

      foreach my $name (sort { lc($a) cmp lc($b) } keys %addresses) {
         my $email=$addresses{$name};
         my $emailstr;

         if ( $form eq "newaddress" && $field eq "email" ) { # if addr popup window is used to define group email
            $emailstr="$email";	                             # then only pure addr is required
         } else {
            if ( $email =~ /[,"]/ ) {	# expand multiple addr to multiple "name" <addr>
               foreach my $e (ow::tool::str2list($email,0)) {
                  foreach my $n (keys %addresses) {
                     if ( $e eq $addresses{$n} ) {
                        $e="\&quot;$n\&quot; &lt;$e&gt;";
                        last;
                     }
                  }
                  $emailstr .= "," if ($emailstr ne "");
                  $emailstr .= $e;
               }
            } else {
               $emailstr="\&quot;$name\&quot; &lt;$email&gt;";
            }
         }

         my $accesskeystr=$count%10+1;
         if ($accesskeystr == 10) {
            $accesskeystr=qq|accesskey="0"|;
         } elsif ($accesskeystr < 10) {
            $accesskeystr=qq|accesskey="$accesskeystr"|;
         }
         $temphtml .= qq|<tr>| if ($count %2 == 0);
         $temphtml .= qq|<td width="20" bgcolor=$bgcolor><input type="checkbox" name="to" value="$emailstr"|;

         if (defined($emailhash{$email})) {
            $temphtml .= " checked";
            delete $emailhash{$email};
         }

         $emailstr=~s/\\/\\\\/g; $emailstr=~s/'/\\'/g;	# escape \ and ' for javascript
         $temphtml .= qq|></td><td width="45%" bgcolor=$bgcolor nowrap>|.
                      qq|<a $accesskeystr href="javascript:Update('$emailstr')" title="$email $notes{$name}">$name</a></td>\n|;
         $temphtml .= qq|</tr>| if ($count %2 == 1);

         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"} if ($count %2 == 0);
         } else {
            $bgcolor = $style{"tablerow_dark"} if ($count %2 == 0);
         }
         $results_flag = 1;
         $count++
      }

   }
   $temphtml .= qq|<tr><td colspan="4">&nbsp;</td></tr>| if ($count>0);

   $count = 0;
   if ( $config{'global_addressbook'} ne "" && -f "$config{'global_addressbook'}" ) {
      my %globaladdresses=();
      my %globalnotes=();
      my @namelist=();	# keep the order in global addressbook

      if (open (ABOOK,"$config{'global_addressbook'}")) {
         while (<ABOOK>) {
            my ($name, $email, $note) = split(/\@\@\@/, $_, 3);
            chomp($email);
            chomp($note);
	    next if (!is_entry_matched($abook_keyword,$abook_searchtype, $name,$note,$email));
            next if ($email=~/^\s*$/);	# skip if email is null
            $globaladdresses{$name} = $email;
            $globalnotes{$name} = $note;
            push(@namelist, $name);
         }
         close (ABOOK);
      }
      foreach my $name (@namelist) {
         my $email=$globaladdresses{$name};
         my $emailstr;

         if ( $form eq "newaddress" && $field eq "email" ) { # if addr popup window is used to define group email
            $emailstr="$email";	                             # then only pure addr is required
         } else {
            if ( $email =~ /[,"]/ ) {	# expamd multiple addr to "name" <addr>
               foreach my $e (ow::tool::str2list($email,0)) {
                  foreach my $n (keys %globaladdresses) {
                     if ( $e eq $globaladdresses{$n} ) {
                        $e="\&quot;$n\&quot; &lt;$e&gt;";
                        last;
                     }
                  }
                  $emailstr .= "," if ($emailstr ne "");
                  $emailstr .= $e;
               }
            } else {
               $emailstr="\&quot;$name\&quot; &lt;$email&gt;";
            }
         }

         $temphtml .= qq|<tr>| if ($count %2 == 0);
         $temphtml .= qq|<td width="20" bgcolor=$bgcolor><input type="checkbox" name="to" value="$emailstr"|;

         if (defined($emailhash{$email})) {
            $temphtml .= " checked";
            delete $emailhash{$email};
         }

         $emailstr=~s/\\/\\\\/g; $emailstr=~s/'/\\'/g;	# escape \ and ' for javascript
         $temphtml .= qq|></td><td width="45%" bgcolor=$bgcolor nowrap>|.
                      qq|<a href="javascript:Update('$emailstr')" title="$email $globalnotes{$name}">$name</a></td>\n|;
         $temphtml .= qq|</tr>| if ($count %2 == 1);

         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"} if ($count %2 == 0);
         } else {
            $bgcolor = $style{"tablerow_dark"} if ($count %2 == 0);
         }
         $results_flag = 1;
         $count++
      }
      $temphtml .= qq|<tr><td colspan="4">&nbsp;</td></tr>| if ($count>0);
   }

   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/g;

   # rebuild entries not checked on address popup window backto elist
   my @u=sort values(%emailhash);
   $elist=join(",", @u);

   $temphtml = ow::tool::hiddens(elist=>$elist,
                                 action=>'addressbook',
                                 sessionid=>$thissession,
                                 form=>$form,
                                 field=>$field);
   $html =~ s/\@\@\@HIDDENFIELDS\@\@\@/$temphtml/g;

   $temphtml = button(-name=>'update',
                      -value=>$lang_text{'continue'},
                      -accesskey=>'C',		# continue
	              -class=>'medtext',
                      -onclick=>'Update(); return false;').
               "&nbsp;&nbsp;".
               button(-name=>'cancel',
                      -value=>$lang_text{'cancel'},
                      -onclick=>'window.close();',
	              -class=>'medtext',
                      -accesskey=>'Q',		# quit
                      -override=>'1');

   my $temphtml_before = '&nbsp;</td></tr><tr><td align="center" colspan=4>'.$temphtml;
   if ($prefs{'abook_buttonposition'} eq 'after') {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@//g;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$temphtml/g;
   } elsif (($prefs{'abook_buttonposition'} eq 'both') && $results_flag) {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@/$temphtml_before/g;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$temphtml/g;
   } else {
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@/$temphtml_before/g;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@//g;
   }

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $html =~ s/\@\@\@FORMNAME\@\@\@/$form/g;
   $html =~ s/\@\@\@FIELDNAME\@\@\@/$field/g;

   httpprint([], [htmlheader(), $html, htmlfooter(0)]);
}
########## END ADDRESSBOOK #######################################

########## IMPORT/EXPORTABOOK ####################################
sub importabook {
   my ($name, $email, $note);
   my (%addresses, %notes);
   my $abookupload = param('abook') || '';
   my $abooktowrite='';
   my $mua = param('mua') || '';

   my $addrbookfile=dotpath('address.book');

   if ($abookupload) {
      my $abookcontents = '';
      while (<$abookupload>) {
         $abookcontents .= $_;
      }
      close($abookupload);
#      if ($mua eq 'outlookexp5') {
#         unless ($abookcontents =~ /^Name,E-mail Address/) {
#            openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_invalid'} <a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;page=$page&amp;message_id=$escapedmessageid">$lang_err{'back'}</a> $lang_err{'tryagain'}|);
#         }
#      }

      if (! -f $addrbookfile) {
         open (ABOOK, ">>$addrbookfile"); # Create if nonexistent
         close(ABOOK);
      }
      ow::filelock::lock($addrbookfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $addrbookfile!");
      open (ABOOK,"+< $addrbookfile") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $addrbookfile! ($!)");
      while (<ABOOK>) {
         ($name, $email, $note) = split(/\@\@\@/, $_, 3);
         chomp($email); chomp($note);
         $addresses{"$name"} = $email;
         $notes{"$name"}=$note;
      }
      foreach my $line (split(/\r*\n/, $abookcontents)) {
 #        next if ( ($mua eq 'outlookexp5') && (/^Name,E-mail Address/) );
         next if ( $line !~ /\@/ );
         my @t = ow::tool::str2list($line,1);
         if ( $mua eq 'outlookexp5' && $t[0] && $t[1] ) {
            $name=shift(@t);
            $name =~ s/</&lt;/g; $name =~ s/>/&gt;/g;
            $email=shift(@t);
            while ($t[0]=~/^[\w\d\.-_]+\@[\w\d-_]+(\.[\w\d-_]+)+$/) {
               $email.=",".shift(@t);	# for owm group addr import
            }
            $email =~ s/</&lt;/g; $email =~ s/>/&gt;/g;
            $note = join(",", @t);
            $note =~ s/,\s*,//g; $note =~ s/^\s*,\s*//g; $note =~ s/\s*,\s*$//g;

            $addresses{$name} = $email;
            $notes{$name} = $note;

         } elsif ( $mua eq 'nsmail' && $t[0] && $t[6] ) {
            $name=$t[0];
            $name =~ s/</&lt;/g; $name =~ s/>/&gt;/g;
            $email=$t[6];
            $email =~ s/</&lt;/g; $email =~ s/>/&gt;/g;
            $note = join(",", @t[1..5,7..9]);
            $note =~ s/,\s*,//g; $note =~ s/^\s*,\s*//g; $note =~ s/\s*,\s*$//g;

            $addresses{$name} = $email;
            $notes{$name} = $note;
         }
      }

      seek (ABOOK, 0, 0) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_seek'} $addrbookfile! ($!)");

      foreach (sort keys %addresses) {
         ($name,$email,$note)=($_, $addresses{$_}, $notes{$_});
         $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
         $email=~s/\@\@/\@\@ /g; $email=~s/\@$/\@ /;
         $abooktowrite .= "$name\@\@\@$email\@\@\@$note\n";
      }

      if (length($abooktowrite) > ($config{'maxbooksize'} * 1024)) {
         openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'}|.
                          qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;page=$page&amp;message_id=$escapedmessageid">$lang_err{'back'}</a>|.
                          qq|$lang_err{'tryagain'}|);
      }
      print ABOOK $abooktowrite;
      truncate(ABOOK, tell(ABOOK));

      close (ABOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $addrbookfile! ($!)");
      ow::filelock::lock($addrbookfile, LOCK_UN);

      writelog("import addressbook");
      writehistory("import addressbook");

      editaddresses();

   } else {

      my $abooksize = ( -s $addrbookfile ) || 0;
      my $freespace = int($config{'maxbooksize'} - ($abooksize/1024) + .5);

      my ($html, $temphtml);
      $html = applystyle(readtemplate("importabook.template"));

      $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace $lang_sizes{'kb'}/g;

      $temphtml = start_multipart_form().
                  ow::tool::hiddens(action=>'importabook',
                                    sessionid=>$thissession,
                                    sort=>$sort,
                                    page=>$page,
                                    folder=>$folder,
                                    message_id=>$messageid);
      $html =~ s/\@\@\@STARTIMPORTFORM\@\@\@/$temphtml/;


      my %mualabels =(outlookexp5 => 'Outlook Express 5',
                      nsmail      => 'Netscape Mail 4.x');
      $temphtml = radio_group(-name=>'mua',
                              -values=>['outlookexp5','nsmail'],
                              -default=>'outlookexp5',
                              -labels=>\%mualabels);
      $html =~ s/\@\@\@MUARADIOGROUP\@\@\@/$temphtml/;

      $temphtml = filefield(-name=>'abook',
                            -default=>'',
                            -size=>'30',
                            -override=>'1');
      $html =~ s/\@\@\@IMPORTFILEFIELD\@\@\@/$temphtml/;

      $temphtml = submit("$lang_text{'import'}");
      $html =~ s/\@\@\@IMPORTBUTTON\@\@\@/$temphtml/;

      $temphtml = end_form();
      $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                  ow::tool::hiddens(action=>'editaddresses',
                                    sessionid=>$thissession,
                                    sort=>$sort,
                                    folder=>$folder,
                                    page=>$page,
                                    message_id=>$messageid);
      $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;

      $temphtml = submit("$lang_text{'cancel'}");
      $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

      httpprint([], [htmlheader(), $html, htmlfooter(2)]);
   }
}

sub exportabook {
   my $addrbookfile=dotpath('address.book');

   ow::filelock::lock($addrbookfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $addrbookfile!");
   open (ABOOK, $addrbookfile) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $addrbookfile! ($!)");

   # disposition:attachment default to save
   print qq|Connection: close\n|,
         qq|Content-Type: text/plain; name="adbook.csv"\n|;
   if ( $ENV{'HTTP_USER_AGENT'}=~/MSIE 5.5/ ) {	# ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="adbook.csv"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="adbook.csv"\n|;
   }
   print qq|\n|;
   print qq|Name,E-mail Address,Note\n|;
   while (<ABOOK>) {
      print join(",", split(/\@\@\@/,$_,3));
   }

   close(ABOOK);
   ow::filelock::lock($addrbookfile, LOCK_UN);

   writelog("export addressbook");
   writehistory("export addressbook");

   return;
}

########## END IMPORT/EXPORTABOOK ################################

########## IMPORT/EXPORTABOOK PINE ###############################
sub importabook_pine {
   my $addrbookfile=dotpath('address.book');

   if ( ! -f $addrbookfile ) {
      open (ABOOK, ">>$addrbookfile"); # Create if nonexistent
      close(ABOOK);
   }

   if (open (PINEBOOK,"$homedir/.addressbook") ) {
      my ($name, $email, $note);
      my (%addresses, %notes);
      my $abooktowrite='';

      ow::filelock::lock($addrbookfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $addrbookfile!");
      open (ABOOK,"+<$addrbookfile") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $addrbookfile! ($!)");

      while (<ABOOK>) {
         ($name, $email, $note) = split(/\@\@\@/, $_, 3);
         chomp($email); chomp($note);
         $addresses{"$name"} = $email;
         $notes{"$name"}=$note;
      }

      while (<PINEBOOK>) {
         my ($name, $email, $note) = (split(/\t/, $_,5))[1,2,4];
         chomp($email);
         chomp($note);
         next if ($email=~/^\s*$/);  # skip if email is null
         $addresses{"$name"} = $email;
         $notes{"$name"}=$note;
      }
      close (PINEBOOK);

      seek (ABOOK, 0, 0) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_seek'} $addrbookfile! ($!)");

      foreach (sort keys %addresses) {
         ($name,$email,$note)=($_, $addresses{$_}, $notes{$_});
         $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
         $email=~s/\@\@/\@\@ /g; $email=~s/\@$/\@ /;
         $abooktowrite .= "$name\@\@\@$email\@\@\@$note\n";
      }

      if (length($abooktowrite) > ($config{'maxbooksize'} * 1024)) {
         openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'}|.
                          qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;page=$page&amp;message_id=$escapedmessageid">$lang_err{'back'}</a>|.
                          qq|$lang_err{'tryagain'}|);
      }
      print ABOOK $abooktowrite;
      truncate(ABOOK, tell(ABOOK));

      close (ABOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $addrbookfile! ($!)");
      ow::filelock::lock($addrbookfile, LOCK_UN);

      writelog("import pine addressbook, $homedir/.addressbook");
      writehistory("import pine addressbook, $homedir/.addressbook");
   }
   editaddresses();
}

sub exportabook_pine {
   my $addrbookfile=dotpath('address.book');

   if (-f $addrbookfile) {
      ow::filelock::lock($addrbookfile, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $addrbookfile!");
      open (ABOOK, $addrbookfile) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $addrbookfile! ($!)");

      my (%nicknames, %emails, %fccs, %notes);
      my ($nickname, $name, $email, $fcc, $note);
      my $abooktowrite='';

      while (<ABOOK>) {
         ($name, $email, $note) = split(/\@\@\@/, $_, 3);
         foreach ($name, $email, $note) { chomp; }
         $emails{$name} = $email;
         $notes{$name} = $note;
      }
      close(ABOOK);
      ow::filelock::lock($addrbookfile, LOCK_UN);

      ow::filelock::lock("$homedir/.addressbook", LOCK_EX) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $homedir/.addressbook!");
           
      if (open (PINEBOOK, "$homedir/.addressbook")) {
         while (<PINEBOOK>) {
            my ($nickname, $name, $email, $fcc, $note) = (split(/\t/, $_,5))[1,2,4];
            foreach ($nickname, $name, $email, $fcc, $note) { chomp; }
            next if ($email=~/^\s*$/);  # skip if email is null
            $nicknames{$name}=$nickname;
            $emails{$name} = $email;
            $fccs{$name}=$fcc;
            $notes{$name}=$note;
         }
         close(PINEBOOK);
      }

      open (PINEBOOK,">$homedir/.addressbook") or
         openwebmailerror(__FILE__, __LINE__, "couldnt_open $homedir/.address.book! ($!)");

      foreach (sort keys %emails) {
         $abooktowrite .= join("\t", $nicknames{$_}, $_,
                                     $emails{$_}, $fccs{$_}, $notes{$_})."\n";
      }
      print PINEBOOK $abooktowrite;
      truncate(PINEBOOK, tell(PINEBOOK));
      close (PINEBOOK);
      ow::filelock::lock("$homedir/.addressbook", LOCK_UN);

      writelog("emport addressbook to pine, $homedir/.addressbook");
      writehistory("emport addressbook to pine, $homedir/.addressbook");
   }
   editaddresses();
}
########## END IMPORT/EXPORTABOOK PINE ###########################

########## EDITADDRESSES #########################################
sub editaddresses {
   my %addresses=();
   my %notes=();
   my %globaladdresses=();
   my %globalnotes=();
   my @globalnamelist=();
   my ($name, $email, $note);
   my $abook_keyword = param('abook_keyword') || '';
   my $abook_searchtype = param('abook_searchtype') || 'name';

   my ($html, $temphtml);
   $html = applystyle(readtemplate("editaddresses.template"));

   my $addrbookfile=dotpath('address.book');

   if ( -f $addrbookfile ) {
      open (ABOOK, $addrbookfile) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $addrbookfile! ($!)");
      while (<ABOOK>) {
         ($name, $email, $note) = split(/\@\@\@/, $_, 3);
         chomp($email); chomp($note);
         $addresses{"$name"} = $email;
         $notes{"$name"}=$note;
      }
      close (ABOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $addrbookfile! ($!)");
   }
   my $abooksize = ( -s $addrbookfile ) || 0;
   my $freespace = int($config{'maxbooksize'} - ($abooksize/1024) + .5);

   if ( $config{'global_addressbook'} ne "" && -f "$config{'global_addressbook'}" ) {
      if (open (ABOOK,"$config{'global_addressbook'}") ) {
         while (<ABOOK>) {
            ($name, $email, $note) = split(/\@\@\@/, $_, 3);
            chomp($email);
            $globaladdresses{"$name"} = $email;
            $globalnotes{"$name"} = $note;
            push(@globalnamelist, $name);
         }
         close (ABOOK);
      }
   }

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace $lang_sizes{'kb'}/g;

   if ( param('message_id') ) {
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder),
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   } else {
      $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} ".($lang_folders{$folder}||$folder),
                           qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder"|);
   }

   $temphtml .= "&nbsp;\n";

   $temphtml .= iconlink("import.gif", $lang_text{'importadd'}, qq|accesskey="I" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   if ( -f "$homedir/.addressbook" ) {
      $temphtml .= iconlink("import.gif", "$lang_text{'importadd'} (Pine)", qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook_pine&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|);
   }
   $temphtml .= iconlink("export.gif", $lang_text{'exportadd'}, qq|accesskey="E" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=exportabook&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|).
                iconlink("export.gif", "$lang_text{'exportadd'} (Pine)", qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=exportabook_pine&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid"|).
                iconlink("clearaddress.gif", $lang_text{'clearadd'}, qq|accesskey="Z" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=clearaddress&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid" onclick="return confirm('$lang_text{'clearadd'}?')"|). qq| &nbsp; \n|;
   if ($abook_keyword ne ''){
      $temphtml .= iconlink("refresh.gif", $lang_text{'refresh'}, qq|accesskey="R" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;page=$page&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;abook_keyword="|);
   }

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
               ow::tool::hiddens(action=>'editaddresses',
                                 sessionid=>$thissession,
                                 sort=>$sort,
                                 page=>$page,
                                 folder=>$folder,
                                 message_id=>$messageid);
   $html =~ s/\@\@\@STARTSEARCHFORM\@\@\@/$temphtml/g;

   my %searchtypelabels = ('name'=>$lang_text{'name'},
                           'email'=>$lang_text{'email'},
                           'note'=>$lang_text{'note'},
                           'all'=>$lang_text{'all'});
   $temphtml = popup_menu(-name=>'abook_searchtype',
                           -default=>$abook_searchtype || 'name',
                           -values=>['name', 'email', 'note', 'all'],
                           -labels=>\%searchtypelabels);
   $temphtml .= textfield(-name=>'abook_keyword',
                          -default=>$abook_keyword,
                          -size=>'25',
                          -accesskey=>'S',
                          -override=>'1');
   $temphtml .= "&nbsp;";
   $temphtml .= submit(-name=>$lang_text{'search'},
	               -class=>'medtext');
   $html =~ s/\@\@\@SEARCH\@\@\@/$temphtml/g;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                         -name=>'newaddress').
               ow::tool::hiddens(action=>'addaddress',
                                 sessionid=>$thissession,
                                 sort=>$sort,
                                 page=>$page,
                                 folder=>$folder,
                                 message_id=>$messageid);
   $html =~ s/\@\@\@STARTADDRESSFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'realname',
                         -default=>'',
                         -size=>'20',
                         -accesskey=>'I',
                         -override=>'1');
   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = qq|<table cellspacing="0" cellpadding="0"><tr><td>|.
               textfield(-name=>'email',
                         -default=>'',
                         -size=>'30',
                         -override=>'1').
               qq|</td><td>|.
               iconlink("group.gif", $lang_text{'group'}, qq|accesskey="G" href="Javascript:GoAddressWindow('email')"|).
               qq|</td></tr></table>|;
   $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'note',
                         -default=>'',
                         -size=>'25',
                         -override=>'1');
   $html =~ s/\@\@\@NOTEFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name=>$lang_text{'addmod'},
                      -accesskey=>'A',
                      -onClick=>'return addcheck();',
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};
   my $i=0;
   foreach my $key (sort { lc($a) cmp lc($b) } keys %addresses) {
      my ($namestr, $emailstr, $notestr)=($key, $addresses{$key}, $notes{$key});
      next if (!is_entry_matched($abook_keyword,$abook_searchtype, $namestr,$notestr,$emailstr));
      $namestr=substr($namestr, 0, 25)."..." if (length($namestr)>30);
      $emailstr=substr($emailstr, 0, 35)."..." if (length($emailstr)>40);

      my $accesskeystr=$i%10+1;
      if ($accesskeystr == 10) {
         $accesskeystr=qq|accesskey="0"|;
      } elsif ($accesskeystr < 10) {
         $accesskeystr=qq|accesskey="$accesskeystr"|;
      }

      my ($k, $a, $n)=($key, $addresses{$key}, $notes{$key});
      $k=~s/\\/\\\\/; $k=~s/'/\\'/;
      $a=~s/\\/\\\\/; $a=~s/'/\\'/;
      $n=~s/\\/\\\\/; $n=~s/'/\\'/; # escape \ and ' for javascript
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor><a $accesskeystr href="Javascript:Update('$k','$a','$n')">$namestr</a></td>|.
                   qq|<td bgcolor=$bgcolor><a href="$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;page=$page&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=|.
                   ow::tool::escapeURL($addresses{$key}).qq|&amp;compose_caller=abook">$emailstr</a></td>|.
                   qq|<td bgcolor=$bgcolor>$notestr</td>|;

      $temphtml .= qq|<td bgcolor=$bgcolor align="center">|;

      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                   ow::tool::hiddens(action=>'deleteaddress',
                                     sessionid=>$thissession,
                                     sort=>$sort,
                                     page=>$page,
                                     folder=>$folder,
                                     message_id=>$messageid,
                                     realname=>$key).
                   submit(-name=>$lang_text{'delete'},
                          -class=>"medtext").
                   qq|</td></tr>|.
                   end_form();

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
      $i++;
   }

   if ($#globalnamelist >= 0) {
      $temphtml .= qq|<tr><td colspan="4">&nbsp;</td></tr>\n|.
                   qq|<tr><td colspan="4" bgcolor=$style{columnheader}><B>$lang_text{globaladdressbook}</B> ($lang_text{readonly})</td></tr>\n|;
   }
   $bgcolor = $style{"tablerow_dark"};
   $i=0;
   foreach my $key (@globalnamelist) {
      my ($namestr, $emailstr, $notestr)=($key, $globaladdresses{$key}, $globalnotes{$key});
      next if (!is_entry_matched($abook_keyword,$abook_searchtype, $namestr,$notestr,$emailstr));
      $namestr=substr($namestr, 0, 25)."..." if (length($namestr)>30);
      $emailstr=substr($emailstr, 0, 35)."..." if (length($emailstr)>40);

      my ($k, $a, $n)=($key, $globaladdresses{$key}, $globalnotes{$key});
      $k=~s/\\/\\\\/; $k=~s/'/\\'/;
      $a=~s/\\/\\\\/; $a=~s/'/\\'/;
      $n=~s/\\/\\\\/; $n=~s/'/\\'/; # escape \ and ' for javascript
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor><a href="Javascript:Update('$k','$a','$n')">$namestr</a></td>|.
                   qq|<td bgcolor=$bgcolor><a href="$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;page=$page&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=|.
                   ow::tool::escapeURL($globaladdresses{$key}).qq|&amp;compose_caller=abook">$emailstr</a></td>|.
                   qq|<td bgcolor=$bgcolor>$notestr</td>|.
                   qq|<td bgcolor=$bgcolor align="center">-----</td></tr>|;

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
      $i++;
   }
   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END EDITADDRESSES #####################################

########## MODADDRESS ############################################
sub modaddress {
   my $mode = shift;
   my $realname = param('realname') || '';
   my $address = param('email') || '';
   my $usernote = param('note') || '';
   $realname =~ s/^\s*//; $realname =~ s/^\s*//;
   $address =~ s/[\<\>\[\]\\:\`\"\s]//g;
   $address =~ s/^\s*mailto:\s*//;
   $usernote =~ s/^\s*//; $usernote =~ s/\s*$//;

   if (($realname && $address) || (($mode eq 'delete') && $realname) ) {

      my (%addresses, %notes, $name, $email, $note);
      my $addrbookfile=dotpath('address.book');

      if ( -f $addrbookfile ) {
         if ($mode ne 'delete') {
            if ( (-s $addrbookfile) >= ($config{'maxbooksize'} * 1024) ) {
               openwebmailerror(__FILE__, __LINE__, qq|$lang_err{'abook_toobig'} <a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;page=$page&amp;message_id=$escapedmessageid">$lang_err{'back'}</a>$lang_err{'tryagain'}|);
            }
         }
         ow::filelock::lock($addrbookfile, LOCK_EX|LOCK_NB) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_lock'} $addrbookfile!");
         open (ABOOK,"+<$addrbookfile") or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $addrbookfile! ($!)");
         while (<ABOOK>) {
            ($name, $email, $note) = split(/\@\@\@/, $_, 3);
            chomp($email); chomp($note);
            $addresses{"$name"} = $email;
            $notes{"$name"} = $note;
         }
         if ($mode eq 'delete') {
            delete $addresses{"$realname"};
         } else {
            $addresses{"$realname"} = $address;
            # overwrite old note only if new one is not _reserved_
            # check addaddress in openwebmail-read.pl
            if ($usernote ne '_reserved_') {
               $notes{"$realname"} = $usernote;
            }
         }
         seek (ABOOK, 0, 0) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_seek'} $addrbookfile! ($!)");

         foreach (sort keys %addresses) {
            ($name,$email,$note)=($_, $addresses{$_}, $notes{$_});
            $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
            $email=~s/\@\@/\@\@ /g; $email=~s/\@$/\@ /;
            print ABOOK "$name\@\@\@$email\@\@\@$note\n";
         }
         truncate(ABOOK, tell(ABOOK));
         close (ABOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $addrbookfile! ($!)");
         ow::filelock::lock($addrbookfile, LOCK_UN);
      } else {
         open (ABOOK, ">$addrbookfile" ) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $addrbookfile! ($!)");
         $realname=~s/\@\@/\@\@ /g; $realname=~s/\@$/\@ /;
         $address=~s/\@\@/\@\@ /g; $address=~s/\@$/\@ /;
         print ABOOK "$realname\@\@\@$address\@\@\@$usernote\n";
         close (ABOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $addrbookfile! ($!)");
      }
   }

   if ( param('message_id') ) {
      my $searchtype = param('searchtype') || 'subject';
      my $keyword = param('keyword') || '';
      my $escapedkeyword = ow::tool::escapeURL($keyword);
      print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-read.pl?sessionid=$thissession&folder=$escapedfolder&page=$page&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&message_id=$escapedmessageid&action=readmessage&headers=$prefs{'headers'}&attmode=simple");
   } else {
      editaddresses();
   }
}
########## END MODADDRESS ########################################

########## CLEARADDRESS ##########################################
sub clearaddress {
   my $addrbookfile=dotpath('address.book');

   if ( -f $addrbookfile ) {
      open (ABOOK, ">$addrbookfile") or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_open'} $addrbookfile! ($!)");
      close (ABOOK) or openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $addrbookfile! ($!)");
   }

   writelog("clear addressbook");
   writehistory("clear addressbook");

   editaddresses();
}
########## END CLEARADDRESS ######################################

########## IS_ENTRY_MATCHED ######################################
sub is_entry_matched {
  my ($keyword,$searchtype, $name,$note,$email)=@_;

  $keyword=~s/^\s*//; $keyword=~s/\s*$//;
  return 1 if ($keyword eq '');

  my %string= (
     name => $name,
     email => $email,
     note => $note,
     all => "$name $email $note"
  );
  if ($string{$searchtype}=~/\Q$keyword\E/i ||
      (ow::tool::is_regex($keyword) && $string{$searchtype}=~/$keyword/i) ) {
     return 1;
  }
  return 0;
}
########## END IS_ENTRY_MATCHED ##################################
