#!/usr/bin/perl -T
#############################################################################
# Open WebMail - Provides a web interface to user mailboxes                 #
#                                                                           #
# Copyright (C) 2001-2002                                                   #
# Chung-Kie Tung, Nai-Jung Kuo, Chao-Chiu Wang, Emir Litric, Thomas Chung   #
# Copyright (C) 2000                                                        #
# Ernie Miller  (original GPL project: Neomail)                             #
#                                                                           #
# This program is distributed under GNU General Public License              #
#############################################################################

use vars qw($SCRIPT_DIR);
if ( $ENV{'SCRIPT_FILENAME'} =~ m!^(.*?)/[\w\d\-\.]+\.pl! || $0 =~ m!^(.*?)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\n\$SCRIPT_DIR not set in CGI script!\n"; exit 0; }
push (@INC, $SCRIPT_DIR, ".");

$ENV{PATH} = ""; # no PATH should be needed
$ENV{ENV} = "";      # no startup script for sh
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

require "openwebmail-shared.pl";
require "filelock.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

openwebmail_init();
verifysession();

use vars qw($firstmessage);
use vars qw($sort);
use vars qw($messageid $escapedmessageid);

$firstmessage = param("firstmessage") || 1;
$sort = param("sort") || $prefs{'sort'} || 'date';
$messageid=param("message_id") || '';
$escapedmessageid=escapeURL($messageid);

# extern vars
use vars qw(%lang_folders %lang_text %lang_err);	# defined in lang/xy

########################## MAIN ##############################

my $action = param("action");
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
} elsif ($action eq "importabook_pine") {
   importabook_pine();
} elsif ($action eq "exportabook") {
   exportabook();
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}
###################### END MAIN ##############################

#################### ADDRESSBOOK #######################
sub addressbook {
   my $form=param("form");
   my $field=param("field");
   my $preexisting = param("preexisting") || '';
   my $abook_keyword = param("abook_keyword") || '';
   my $abook_searchtype = param("abook_searchtype") || 'name';

   printheader();

   my $html = '';
   my $temphtml;

   open (ABOOKTEMPLATE, "$config{'ow_etcdir'}/templates/$prefs{'language'}/addressbook.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/addressbook.template");
   while (<ABOOKTEMPLATE>) {
      $html .= $_;
   }
   close (ABOOKTEMPLATE);

   $html = applystyle($html);

   if (defined($lang_text{$field})) {
      $temphtml=$lang_text{$field}.": $lang_text{'abook'}";
   } else {
      $temphtml=uc($field).": $lang_text{'abook'}";
   }

   $html =~ s/\@\@\@ADDRESSBOOKFOR\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                   	  -name=>'search'
                          );
   $temphtml .= hidden(-name=>'action',
                       -value=>'addressbook',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -value=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'form',
                       -value=>$form,
                       -override=>'1');
   $temphtml .= hidden(-name=>'field',
                       -value=>$field,
                       -override=>'1');
   $temphtml .= hidden(-name=>'preexisting',
                       -value=>$preexisting,
                       -override=>'1');

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
                          -size=>'16',
                          -override=>'1');
   $temphtml .= "&nbsp;";
   $temphtml .= submit(-name=>"$lang_text{'search'}",
	               -class=>'medtext');

   $html =~ s/\@\@\@SEARCH\@\@\@/$temphtml/g;

   $temphtml = startform(-action=>"javascript:Update()",
                   	 -name=>'addressbook'
                        );

   $html =~ s/\@\@\@STARTADDRESSFORM\@\@\@/$temphtml/g;

   # split $preexisting in to a hash
   my %preexistinghash=();
   foreach my $u (str2list($preexisting,0)) {
      my ($name, $email)=email2nameaddr($u);
      $preexistinghash{$email}=$u;
   }


   $temphtml="";
   $temphtml .= qq|<tr><td colspan="4">&nbsp;</td></tr>|;

   my $count=0;
   my $bgcolor = $style{"tablerow_dark"};
   if ( -f "$folderdir/.address.book" ||
        -f "$folderdir/.address.book"  ) {
      my %addresses=();
      my %notes=();

      # read openwebmail addressbook
      if ( open(ABOOK,"$folderdir/.address.book") ) {
         while (<ABOOK>) {
            my ($name, $email, $note) = split(/\@\@\@/, $_, 3);
            chomp($email);
            chomp($note);
            if ( $abook_keyword ne "" &&
                 ( ($abook_searchtype eq "name" &&
                    $name!~/$abook_keyword/i && $name!~/\Q$abook_keyword\E/i)   ||
                   ($abook_searchtype eq "email" &&
                    $email!~/$abook_keyword/i && $email!~/\Q$abook_keyword\E/i) ||
                   ($abook_searchtype eq "note" &&
                    $note!~/$abook_keyword/i && $note!~/\Q$abook_keyword\E/i)   ||
                   ($abook_searchtype eq "all" &&
                    "$name.$email.$note" !~ /$abook_keyword/i &&
                    "$name.$email.$note" !~ /\Q$abook_keyword\E/i) )  ) {
               next;
            }
            $addresses{"$name"} = "$email";
            $notes{"$name"} = "$note";
         }
         close (ABOOK);
      }

      foreach my $name (sort { lc($a) cmp lc($b) } keys %addresses) {
         my $email=$addresses{$name};
         my $emailstr;

         if ( $form eq "newaddress" && $field eq "email" ) { # definition mode
            $emailstr="$email";	                             # need only pure addr

         } else {			# reference mode
            if ( $email =~ /[,"]/ ) {	# expand multiple addr to multiple "name" <addr>
               foreach my $e (str2list($email,0)) {
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

         $temphtml .= qq|<tr>| if ($count %2 == 0);
         $temphtml .= qq|<td width="20" bgcolor=$bgcolor><input type="checkbox" name="to" value="$emailstr"|;
         if (defined($preexistinghash{$email})) {
            delete $preexistinghash{$email};
            $temphtml .= " checked";
         }
         $temphtml .= qq|></td><td width="49%" bgcolor=$bgcolor nowrap>|.
                      qq|<a href="javascript:Update('$emailstr')" title="$email $notes{$name}">$name</a></td>\n|;
         $temphtml .= qq|</tr>| if ($count %2 == 1);

         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"} if ($count %2 == 0);
         } else {
            $bgcolor = $style{"tablerow_dark"} if ($count %2 == 0);
         }
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
            if ( $abook_keyword ne "" &&
                 ( ($abook_searchtype eq "name" &&
                    $name!~/$abook_keyword/i && $name!~/\Q$abook_keyword\E/i)   ||
                   ($abook_searchtype eq "email" &&
                    $email!~/$abook_keyword/i && $email!~/\Q$abook_keyword\E/i) ||
                   ($abook_searchtype eq "note" &&
                    $note!~/$abook_keyword/i && $note!~/\Q$abook_keyword\E/i)   ||
                   ($abook_searchtype eq "all" &&
                    "$name.$email.$note" !~ /$abook_keyword/i &&
                    "$name.$email.$note" !~ /\Q$abook_keyword\E/i) )  ) {
               next;
            }
            next if ($email=~/^\s*$/);	# skip if email is null
            $globaladdresses{"$name"} = "$email";
            $globalnotes{"$name"} = "$note";
            push(@namelist, $name);
         }
         close (ABOOK);
      }
      foreach my $name (@namelist) {
         my $email=$globaladdresses{$name};
         my $emailstr;
         if ( $form eq "newaddress" && $field eq "email" ) { # chk if group email definition
            $emailstr="$email";	                             # which needs only pure email
         } else {
            if ( $email =~ /[,"]/ ) {	# expamd multiple addr to "name" <addr>
               foreach my $e (str2list($email,0)) {
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
         if (defined($preexistinghash{$email})) {
            delete $preexistinghash{$email};
            $temphtml .= " checked";
         }
         $temphtml .= qq|></td><td width="49%" bgcolor=$bgcolor nowrap>|.
                      qq|<a href="javascript:Update('$emailstr')" title="$email $globalnotes{$name}">$name</a></td>\n|;
         $temphtml .= qq|</tr>| if ($count %2 == 1);

         if ($bgcolor eq $style{"tablerow_dark"}) {
            $bgcolor = $style{"tablerow_light"} if ($count %2 == 0);
         } else {
            $bgcolor = $style{"tablerow_dark"} if ($count %2 == 0);
         }
         $count++
      }
   }

   $temphtml .= qq|<td width="20" bgcolor=$bgcolor></td><td width="45%" bgcolor=$bgcolor></td></tr>| if ($count %2 == 1);

   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/g;

   # rebuild others into preexisting
   my @u=sort values(%preexistinghash);
   $preexisting=join(",", @u);

   $temphtml = hidden(-name=>'remainingstr',
                      -value=>$preexisting,
                      -override=>'1').
               submit(-name=>"mailto.x",
                       -value=>"$lang_text{'continue'}",
	               -class=>'medtext').
               "&nbsp;&nbsp;".
               button(-name=>"cancel",
                       -value=>"$lang_text{'cancel'}",
                       -onclick=>'window.close();',
	               -class=>'medtext',
                       -override=>'1');

   $html =~ s/\@\@\@BUTTONS\@\@\@/$temphtml/g;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $html =~ s/\@\@\@FORMNAME\@\@\@/$form/g;
   $html =~ s/\@\@\@FIELDNAME\@\@\@/$field/g;


   print $html;

   print end_html();
}
################## END ADDRESSBOOK #####################

##################### IMPORTABOOK ############################
sub importabook {
   my ($name, $email, $note);
   my (%addresses, %notes);
   my $abookupload = param("abook") || '';
   my $abooktowrite='';
   my $mua = param("mua") || '';
   if ($abookupload) {
      my $abookcontents = '';
      while (<$abookupload>) {
         $abookcontents .= $_;
      }
      close($abookupload);
#      if ($mua eq 'outlookexp5') {
#         unless ($abookcontents =~ /^Name,E-mail Address/) {
#            openwebmailerror(qq|$lang_err{'abook_invalid'} <a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid">$lang_err{'back'}</a> $lang_err{'tryagain'}|);
#         }
#      }
      if (! -f "$folderdir/.address.book" ) {
         open (ABOOK, ">>$folderdir/.address.book"); # Create if nonexistent
         close(ABOOK);
      }
      filelock("$folderdir/.address.book", LOCK_EX|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_lock'} $folderdir/.address.book!");
      open (ABOOK,"+<$folderdir/.address.book") or
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.address.book!");
      while (<ABOOK>) {
         ($name, $email, $note) = split(/\@\@\@/, $_, 3);
         chomp($email); chomp($note);
         $addresses{"$name"} = $email;
         $notes{"$name"}=$note;
      }
      foreach my $line (split(/\r*\n/, $abookcontents)) {
 #        next if ( ($mua eq 'outlookexp5') && (/^Name,E-mail Address/) );
         next if ( $line !~ /\@/ );
         my @fields = str2list($line,1);
         if ( ($mua eq 'outlookexp5') && ($fields[0]) && ($fields[1]) ) {
            $fields[0] =~ s/://;
            $fields[0] =~ s/</&lt;/g;
            $fields[0] =~ s/>/&gt;/g;
            $fields[1] =~ s/</&lt;/g;
            $fields[1] =~ s/>/&gt;/g;
            $addresses{$fields[0]} = $fields[1];
            $note = join(",", @fields[2..9]);
            $note =~ s/,\s*,//g;
            $note =~ s/^\s*,\s*//g;
            $note =~ s/\s*,\s*$//g;
            $notes{$fields[0]} = $note;
         } elsif ( ($mua eq 'nsmail') && ($fields[0]) && ($fields[6]) ) {
            $fields[0] =~ s/://;
            $fields[0] =~ s/</&lt;/g;
            $fields[0] =~ s/>/&gt;/g;
            $fields[6] =~ s/</&lt;/g;
            $fields[6] =~ s/>/&gt;/g;
            $addresses{"$fields[0]"} = $fields[6];
            $note = join(",", @fields[1..5,7..9]);
            $note =~ s/,\s*,//g;
            $note =~ s/^\s*,\s*//g;
            $note =~ s/\s*,\s*$//g;
            $notes{$fields[0]} = $note;
         }
      }

      seek (ABOOK, 0, 0) or
         openwebmailerror("$lang_err{'couldnt_seek'} $folderdir/.address.book!");

      foreach (sort keys %addresses) {
         ($name,$email,$note)=($_, $addresses{$_}, $notes{$_});
         $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
         $email=~s/\@\@/\@\@ /g; $email=~s/\@$/\@ /;
         $abooktowrite .= "$name\@\@\@$email\@\@\@$note\n";
      }

      if (length($abooktowrite) > ($config{'maxbooksize'} * 1024)) {
         openwebmailerror(qq|$lang_err{'abook_toobig'}|.
                          qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid">$lang_err{'back'}</a>|.
                          qq|$lang_err{'tryagain'}|);
      }
      print ABOOK $abooktowrite;
      truncate(ABOOK, tell(ABOOK));

      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.address.book!");
      filelock("$folderdir/.address.book", LOCK_UN);

      writelog("import addressbook");
      writehistory("import addressbook");

#      print "Location: $config{'ow_cgiurl'}/openwebmail-abook.pl?action=editaddresses&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&message_id=$escapedmessageid\n\n";
      editaddresses();

   } else {

      my $abooksize = ( -s "$folderdir/.address.book" ) || 0;
      my $freespace = int($config{'maxbooksize'} - ($abooksize/1024) + .5);

      my $html = '';
      my $temphtml;

      open (IMPORTTEMPLATE, "$config{'ow_etcdir'}/templates/$prefs{'language'}/importabook.template") or
         openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/importabook.template");
      while (<IMPORTTEMPLATE>) {
         $html .= $_;
      }
      close (IMPORTTEMPLATE);

      $html = applystyle($html);

      printheader();

      $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace/g;

      $temphtml = start_multipart_form();
      $temphtml .= hidden(-name=>'action',
                          -value=>'importabook',
                          -override=>'1') .
                   hidden(-name=>'sessionid',
                          -value=>$thissession,
                          -override=>'1') .
                   hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1') .
                   hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1') .
                   hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
                   hidden(-name=>'message_id',
                          -default=>$messageid,
                          -override=>'1');
      $html =~ s/\@\@\@STARTIMPORTFORM\@\@\@/$temphtml/;


      my %mualabels =(outlookexp5 => 'Outlook Express 5',
                      nsmail      => 'Netscape Mail 4.x');
      $temphtml = radio_group(-name=>'mua',
                              -"values"=>['outlookexp5','nsmail'],
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

      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl") .
                  hidden(-name=>'action',
                         -value=>'editaddresses',
                         -override=>'1') .
                  hidden(-name=>'sessionid',
                         -value=>$thissession,
                         -override=>'1') .
                  hidden(-name=>'sort',
                         -default=>$sort,
                         -override=>'1') .
                  hidden(-name=>'folder',
                         -default=>$folder,
                         -override=>'1') .
                  hidden(-name=>'firstmessage',
                         -default=>$firstmessage,
                         -override=>'1');
                  hidden(-name=>'message_id',
                         -default=>$messageid,
                         -override=>'1') .
      $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;


      $temphtml = submit("$lang_text{'cancel'}");
      $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

      print $html;

      printfooter(2);
   }
}

sub importabook_pine {
   if ( ! -f "$folderdir/.address.book" ) {
      open (ABOOK, ">>$folderdir/.address.book"); # Create if nonexistent
      close(ABOOK);
   }

   if (open (PINEBOOK,"$homedir/.addressbook") ) {
      my ($name, $email, $note);
      my (%addresses, %notes);
      my $abooktowrite='';

      filelock("$folderdir/.address.book", LOCK_EX|LOCK_NB) or
         openwebmailerror("$lang_err{'couldnt_lock'} $folderdir/.address.book!");
      open (ABOOK,"+<$folderdir/.address.book") or
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.address.book!");

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
         openwebmailerror("$lang_err{'couldnt_seek'} $folderdir/.address.book!");

      foreach (sort keys %addresses) {
         ($name,$email,$note)=($_, $addresses{$_}, $notes{$_});
         $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
         $email=~s/\@\@/\@\@ /g; $email=~s/\@$/\@ /;
         $abooktowrite .= "$name\@\@\@$email\@\@\@$note\n";
      }

      if (length($abooktowrite) > ($config{'maxbooksize'} * 1024)) {
         openwebmailerror(qq|$lang_err{'abook_toobig'}|.
                          qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid">$lang_err{'back'}</a>|.
                          qq|$lang_err{'tryagain'}|);
      }
      print ABOOK $abooktowrite;
      truncate(ABOOK, tell(ABOOK));

      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.address.book!");
      filelock("$folderdir/.address.book", LOCK_UN);

      writelog("import addressbook");
      writehistory("import addressbook");
   }
   editaddresses();
}
#################### END IMPORTABOOK #########################

##################### EXPORTABOOK ############################
sub exportabook {
   filelock("$folderdir/.address.book", LOCK_EX|LOCK_NB) or
      openwebmailerror("$lang_err{'couldnt_lock'} $folderdir/.address.book!");
   open (ABOOK,"$folderdir/.address.book") or
      openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.address.book!");

   # disposition:attachment default to save
   print qq|Content-Transfer-Coding: binary\n|,
         qq|Connection: close\n|,
         qq|Content-Type: text/plain; name="adbook.csv"\n|;

   # ugly hack since ie5.5 is broken with disposition: attchment
   if ( $ENV{'HTTP_USER_AGENT'}!~/MSIE 5.5/ ) {
      print qq|Content-Disposition: attachment; filename="adbook.csv"\n|,
   }
   print qq|\n|;

   print qq|Name,E-mail Address,Note\n|;

   while (<ABOOK>) {
      print join(",", split(/\@\@\@/,$_,3));
   }

   close(ABOOK);
   filelock("$folderdir/.address.book", LOCK_UN);

   writelog("export addressbook");
   writehistory("export addressbook");

   return;
}
#################### END EXPORTABOOK #########################

#################### EDITADDRESSES ###########################
sub editaddresses {
   my %addresses=();
   my %notes=();
   my %globaladdresses=();
   my %globalnotes=();
   my @globalnamelist=();
   my ($name, $email, $note);
   my $abook_keyword = param("abook_keyword") || '';
   my $abook_searchtype = param("abook_searchtype") || 'name';

   my $html = '';
   my $temphtml;

   open (EDITABOOKTEMPLATE, "$config{'ow_etcdir'}/templates/$prefs{'language'}/editaddresses.template") or
      openwebmailerror("$lang_err{'couldnt_open'} $config{'ow_etcdir'}/templates/$prefs{'language'}/editaddresses.template");
   while (<EDITABOOKTEMPLATE>) {
      $html .= $_;
   }
   close (EDITABOOKTEMPLATE);

   $html = applystyle($html);

   if ( -f "$folderdir/.address.book" ) {
      open (ABOOK,"$folderdir/.address.book") or
         openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.address.book!");
      while (<ABOOK>) {
         ($name, $email, $note) = split(/\@\@\@/, $_, 3);
         chomp($email); chomp($note);
         $addresses{"$name"} = $email;
         $notes{"$name"}=$note;
      }
      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.address.book!");
   }
   my $abooksize = ( -s "$folderdir/.address.book" ) || 0;
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

   printheader();

   $html =~ s/\@\@\@FREESPACE\@\@\@/$freespace/g;

   if ( param("message_id") ) {
      $temphtml = qq|<a href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid" title="$lang_text{'backto'} $printfolder"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/backtofolder.gif" border="0" ALT="$lang_text{'backto'} $printfolder"></a> &nbsp; |;
   } else {
      $temphtml = qq|<a href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=displayheaders&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder" title="$lang_text{'backto'} $printfolder"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/backtofolder.gif" border="0" ALT="$lang_text{'backto'} $printfolder"></a> &nbsp; |;
   }
   $temphtml .= qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid" title="$lang_text{'importadd'}"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/import.gif" border="0" ALT="$lang_text{'importadd'}"></a> |;
   if ( -f "$homedir/.addressbook" ) {
      $temphtml .= qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=importabook_pine&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid" title="$lang_text{'importadd'} (Pine)"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/import.gif" border="0" ALT="$lang_text{'importadd'} (Pine)"></a> |;
   }
   $temphtml .= qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=exportabook&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid" title="$lang_text{'exportadd'}"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/export.gif" border="0" ALT="$lang_text{'exportadd'}"></a> |.
                qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=clearaddress&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid" onclick="return confirm('$lang_text{'clearadd'}?')" title="$lang_text{'clearadd'}"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/clearaddress.gif" border="0" ALT="$lang_text{'clearadd'}"></a> &nbsp; |;
   if ($abook_keyword ne ''){
      $temphtml .= qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;firstmessage=$firstmessage&amp;folder=$folder&amp;message_id=$escapedmessageid&amp;abook_keyword=" title="$lang_text{'refresh'}"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/refresh.gif" border="0" ALT="$lang_text{'refresh'}"></a>|;
   }

   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl");
   $temphtml .= hidden(-name=>'action',
                       -value=>'editaddresses',
                       -override=>'1');
   $temphtml .= hidden(-name=>'sessionid',
                       -value=>$thissession,
                       -override=>'1');
   $temphtml .= hidden(-name=>'sort',
                       -default=>$sort,
                       -override=>'1');
   $temphtml .= hidden(-name=>'firstmessage',
                       -default=>$firstmessage,
                       -override=>'1');
   $temphtml .= hidden(-name=>'folder',
                       -default=>$folder,
                       -override=>'1');
   $temphtml .= hidden(-name=>'message_id',
                       -default=>$messageid,
                       -override=>'1');
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
                          -override=>'1');
   $temphtml .= "&nbsp;";
   $temphtml .= submit(-name=>"$lang_text{'search'}",
	               -class=>'medtext');
   $html =~ s/\@\@\@SEARCH\@\@\@/$temphtml/g;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                         -name=>'newaddress') .
               hidden(-name=>'action',
                      -value=>'addaddress',
                      -override=>'1') .
               hidden(-name=>'sessionid',
                      -value=>$thissession,
                      -override=>'1') .
               hidden(-name=>'sort',
                      -default=>$sort,
                      -override=>'1') .
               hidden(-name=>'firstmessage',
                      -default=>$firstmessage,
                      -override=>'1') .
               hidden(-name=>'folder',
                      -default=>$folder,
                      -override=>'1');
               hidden(-name=>'message_id',
                      -default=>$messageid,
                      -override=>'1');

   $html =~ s/\@\@\@STARTADDRESSFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'realname',
                         -default=>'',
                         -size=>'20',
                         -override=>'1');

   $html =~ s/\@\@\@REALNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'email',
                         -default=>'',
                         -size=>'30',
                         -override=>'1');
   $temphtml .= qq|<a href="Javascript:GoAddressWindow('email')" title="$lang_text{'group'}"><IMG SRC="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/group.gif" border="0" ALT="$lang_text{'group'}"></a>|;

   $html =~ s/\@\@\@EMAILFIELD\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'note',
                         -default=>'',
                         -size=>'25',
                         -override=>'1');
   $html =~ s/\@\@\@NOTEFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name=>"$lang_text{'addmod'}",
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = '';
   my $bgcolor = $style{"tablerow_dark"};

   foreach my $key (sort { lc($a) cmp lc($b) } keys %addresses) {
      my ($namestr, $emailstr, $notestr)=($key, $addresses{$key}, $notes{$key});
      if ( $abook_keyword ne "" &&
           ( ($abook_searchtype eq "name" &&
              $namestr!~/$abook_keyword/i && $namestr!~/\Q$abook_keyword\E/i)   ||
             ($abook_searchtype eq "email" &&
              $emailstr!~/$abook_keyword/i && $emailstr!~/\Q$abook_keyword\E/i) ||
             ($abook_searchtype eq "note" &&
              $notestr!~/$abook_keyword/i && $notestr!~/\Q$abook_keyword\E/i)   ||
             ($abook_searchtype eq "all" &&
              "$namestr.$emailstr.$notestr" !~ /$abook_keyword/i &&
              "$namestr.$emailstr.$notestr" !~ /\Q$abook_keyword\E/i) )  ) {
         next;
      }
      $namestr=substr($namestr, 0, 25)."..." if (length($namestr)>30);
      $emailstr=substr($emailstr, 0, 35)."..." if (length($emailstr)>40);
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor width="150"><a href="Javascript:Update('$key','$addresses{$key}','$notes{$key}')">$namestr</a></td>|.
                   qq|<td bgcolor=$bgcolor width="250"><a href="$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;firstmessage=$firstmessage&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$addresses{$key}">$emailstr</a></td>|.
                   qq|<td bgcolor=$bgcolor width="150">$notestr</td>|;

      $temphtml .= qq|<td bgcolor=$bgcolor align="center">|;

      $temphtml .= start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl");
      $temphtml .= hidden(-name=>'action',
                          -value=>'deleteaddress',
                          -override=>'1');
      $temphtml .= hidden(-name=>'sessionid',
                          -value=>$thissession,
                          -override=>'1');
      $temphtml .= hidden(-name=>'sort',
                          -default=>$sort,
                          -override=>'1');
      $temphtml .= hidden(-name=>'firstmessage',
                          -default=>$firstmessage,
                          -override=>'1');
      $temphtml .= hidden(-name=>'folder',
                          -default=>$folder,
                          -override=>'1');
      $temphtml .= hidden(-name=>'message_id',
                          -default=>$messageid,
                          -override=>'1');
      $temphtml .= hidden(-name=>'realname',
                          -value=>$key,
                          -override=>'1');
      $temphtml .= submit(-name=>"$lang_text{'delete'}",
                          -class=>"medtext");

      $temphtml .= '</td></tr>';
      $temphtml .= end_form();

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   if ($#globalnamelist >= 0) {
      $temphtml .= qq|<tr><td colspan="4">&nbsp;</td></tr>\n|.
                   qq|<tr><td colspan="4" bgcolor=$style{columnheader}><B>$lang_text{globaladdressbook}</B> ($lang_text{readonly})</td></tr>\n|;
   }
   $bgcolor = $style{"tablerow_dark"};
   foreach my $key (@globalnamelist) {
      my ($namestr, $emailstr, $notestr)=($key, $globaladdresses{$key}, $globalnotes{$key});
      if ( $abook_keyword ne "" &&
           ( ($abook_searchtype eq "name" &&
              $namestr!~/$abook_keyword/i && $namestr!~/\Q$abook_keyword\E/i)   ||
             ($abook_searchtype eq "email" &&
              $emailstr!~/$abook_keyword/i && $emailstr!~/\Q$abook_keyword\E/i) ||
             ($abook_searchtype eq "note" &&
              $notestr!~/$abook_keyword/i && $notestr!~/\Q$abook_keyword\E/i)   ||
             ($abook_searchtype eq "all" &&
              "$namestr.$emailstr.$notestr" !~ /$abook_keyword/i &&
              "$namestr.$emailstr.$notestr" !~ /\Q$abook_keyword\E/i) )  ) {
         next;
      }
      $namestr=substr($namestr, 0, 25)."..." if (length($namestr)>30);
      $emailstr=substr($emailstr, 0, 35)."..." if (length($emailstr)>40);
      $temphtml .= qq|<tr>|.
                   qq|<td bgcolor=$bgcolor width="150"><a href="Javascript:Update('$key','$globaladdresses{$key}','$globalnotes{$key}')">$namestr</a></td>|.
                   qq|<td bgcolor=$bgcolor width="250"><a href="$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;firstmessage=$firstmessage&amp;sort=$sort&amp;folder=$escapedfolder&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$globaladdresses{$key}">$emailstr</a></td>|.
                   qq|<td bgcolor=$bgcolor width="150">$notestr</td>|.
                   qq|<td bgcolor=$bgcolor align="center">-----</td></tr>|;

      if ($bgcolor eq $style{"tablerow_dark"}) {
         $bgcolor = $style{"tablerow_light"};
      } else {
         $bgcolor = $style{"tablerow_dark"};
      }
   }

   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/;

   print $html;

   printfooter(2);
}
################### END EDITADDRESSES ########################

################### MODADDRESS ##############################
sub modaddress {
   my $mode = shift;
   my ($realname, $address, $usernote);
   $realname = param("realname") || '';
   $address = param("email") || '';
   $usernote = param("note") || '';
   $realname =~ s/^\s*//; # strip beginning and trailing spaces from hash key
   $address =~ s/[#&=\?]//g;
   $address =~ s/^\s*mailto:\s*//;
   $usernote =~ s/^\s*//; # strip beginning and trailing spaces
   $usernote =~ s/\s*$//;

   if (($realname && $address) || (($mode eq 'delete') && $realname) ) {
      my %addresses;
      my %notes;
      my ($name,$email,$note);
      if ( -f "$folderdir/.address.book" ) {
         if ($mode ne 'delete') {
            if ( (-s "$folderdir/.address.book") >= ($config{'maxbooksize'} * 1024) ) {
               openwebmailerror(qq|$lang_err{'abook_toobig'} <a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=editaddresses&amp;sessionid=$thissession&amp;sort=$sort&amp;folder=$escapedfolder&amp;firstmessage=$firstmessage&amp;message_id=$escapedmessageid">$lang_err{'back'}</a>$lang_err{'tryagain'}|);
            }
         }
         filelock("$folderdir/.address.book", LOCK_EX|LOCK_NB) or
            openwebmailerror("$lang_err{'couldnt_lock'} $folderdir/.address.book!");
         open (ABOOK,"+<$folderdir/.address.book") or
            openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.address.book!");
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
            openwebmailerror("$lang_err{'couldnt_seek'} $folderdir/.address.book!");

         foreach (sort keys %addresses) {
            ($name,$email,$note)=($_, $addresses{$_}, $notes{$_});
            $name=~s/\@\@/\@\@ /g; $name=~s/\@$/\@ /;
            $email=~s/\@\@/\@\@ /g; $email=~s/\@$/\@ /;
            print ABOOK "$name\@\@\@$email\@\@\@$note\n";
         }
         truncate(ABOOK, tell(ABOOK));
         close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.address.book!");
         filelock("$folderdir/.address.book", LOCK_UN);
      } else {
         open (ABOOK, ">$folderdir/.address.book" ) or
            openwebmailerror("$lang_err{'couldnt_open'} $folderdir/.address.book!");
         $realname=~s/\@\@/\@\@ /g; $realname=~s/\@$/\@ /;
         $address=~s/\@\@/\@\@ /g; $address=~s/\@$/\@ /;
         print ABOOK "$realname\@\@\@$address\@\@\@$usernote\n";
         close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.address.book!");
      }
   }

   if ( param("message_id") ) {
      my $searchtype = param("searchtype") || 'subject';
      my $keyword = param("keyword") || '';
      my $escapedkeyword = escapeURL($keyword);
      print "Location: $config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&sessionid=$thissession&firstmessage=$firstmessage&sort=$sort&keyword=$escapedkeyword&searchtype=$searchtype&folder=$escapedfolder&message_id=$escapedmessageid\n\n";
   } else {
      editaddresses();
   }
}
################## END MODADDRESS ###########################

################## CLEARADDRESS ###########################
sub clearaddress {
   if ( -f "$folderdir/.address.book" ) {
      open (ABOOK, ">$folderdir/.address.book") or
         openwebmailerror ("$lang_err{'couldnt_open'} $folderdir/.address.book!");
      close (ABOOK) or openwebmailerror("$lang_err{'couldnt_close'} $folderdir/.address.book!");
   }

   writelog("clear addressbook");
   writehistory("clear addressbook");

#   print "Location: $config{'ow_cgiurl'}/openwebmail-abook.pl?action=editaddresses&sessionid=$thissession&sort=$sort&folder=$escapedfolder&firstmessage=$firstmessage&message_id=$escapedmessageid\n\n";
   editaddresses();
}
################## END CLEARADDRESS ###########################

