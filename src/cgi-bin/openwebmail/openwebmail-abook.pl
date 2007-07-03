#!/usr/bin/suidperl -T
#
# openwebmail-abook.pl - address book program
#

use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { local $1; $SCRIPT_DIR=$1 }
if ($SCRIPT_DIR eq '' && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { local $1; $SCRIPT_DIR=$1 }
}
if ($SCRIPT_DIR eq '') { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

foreach (qw(ENV BASH_ENV CDPATH IFS TERM)) {delete $ENV{$_}}; $ENV{PATH}='/bin:/usr/bin'; # secure ENV
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);
use Data::Dumper; $Data::Dumper::Sortkeys=1; $Data::Dumper::Deepcopy=1; $Data::Dumper::Purity=1;

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/htmltext.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/adrbook.pl";
require "shares/iconv.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);

# extern vars
use vars qw(%lang_folders %lang_sizes %lang_text %lang_err %lang_wday
            %lang_order %lang_wday_abbrev %lang_month); # defined in lang/xy
use vars qw(%lang_abookselectionlabels %lang_abookclasslabels
            %lang_timezonelabels %lang_wdbutton);
use vars qw(%charset_convlist);	# defined in iconv.pl

# local globals
use vars qw($folder $messageid $sort $msgdatetype $page $searchtype $keyword);
use vars qw($escapedmessageid $escapedfolder $escapedkeyword);
use vars qw($quotausage $quotalimit);
use vars qw($abookfolder $abookpage $abooklongpage $abooksort $abooksearchtype $abookkeyword $abookcollapse);
use vars qw(%supportedimportexportformat);
use vars qw($escapedabookfolder $escapedabookkeyword);

use vars qw($webmail_urlparm $webmail_formparm);
use vars qw($abook_urlparm $abook_urlparm_with_abookfolder $abook_formparm $abook_formparm_with_abookfolder);
use vars qw($urlparm $formparm $importfieldcount);

# DEBUGGING
use vars qw($addrdebug);
$addrdebug = 0;

########## MAIN ##################################################
openwebmail_requestbegin();
userenv_init();

if (!$config{'enable_addressbook'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'addressbook'} $lang_err{'access_denied'}");
}

# supported import and export formats
my %supportedimportexportformat = (
                                   'vcard3.0' => [\&importvcard,\&exportvcard,'vCard v3.0 (vFile .vcf)','vcf'],
                                   'vcard2.1' => [\&importvcard,\&exportvcard,'vCard v2.1 (vFile .vcf)','vcf'],
                                   'csv'      => [\&importcsv,\&exportcsv,'CSV (Comma Separated Value .csv)','csv'],
                                   'csv auto' => [\&importcsv,\&exportcsv,'CSV (first line contains field names .csv)','csv'],
                                   'tab'      => [\&importtab,\&exporttab,'Tab Delimited File (.tab)','tab'],
                                   'tab auto' => [\&importtab,\&exporttab,'Tab Delimited File (first line contains field names .tab)','tab'],
                                   # NOT SUPPORTED...YET
                                   # 'pine'   => [\&importpine,'\&exportpine','Pine Addressbook Format'],
                                   # 'ldif'   => [\&importldif,'\&exportldif','LDIF (LDAP Directory Interchange Format)'],
                                  );

# Number of selectable fields when importing TAB/CSV files
$importfieldcount = 5;

# convert old proprietary addressbooks to the new vcard format
convert_addressbook('user', $prefs{'charset'});

# mail globals
$folder = ow::tool::unescapeURL(param('folder')) || 'INBOX';
$page = param('page') || 1;
$sort = param('sort') || $prefs{'sort'} || 'date_rev';
$msgdatetype = param('msgdatetype') || $prefs{'msgdatetype'};
$messageid = param('message_id') || '';
$searchtype = param('searchtype') || '';
$keyword = ow::tool::unescapeURL(param('keyword')) || '';

# escaped mail globals
$escapedfolder = ow::tool::escapeURL($folder);
$escapedmessageid = ow::tool::escapeURL($messageid);
$escapedkeyword = ow::tool::escapeURL($keyword);

# addressbook globals
if (defined param('abookfolder') && param('abookfolder') ne "") {
   # unescape just in case if this parm is returned in escaped form
   $abookfolder = ow::tool::unescapeURL(param('abookfolder'));
} else {
   $abookfolder = cookie("ow-abookfolder-$domain-$user") || 'ALL';
}

$abookpage = param('abookpage') || 1;
$abooklongpage = param('abooklongpage') || 0;
$abooksort = param('abooksort') || $prefs{'abook_sort'} || 'fullname';
$abooksearchtype = $prefs{'abook_defaultfilter'}?$prefs{'abook_defaultsearchtype'}:undef;
$abooksearchtype = param('abooksearchtype') if (defined param('abooksearchtype'));
$abookkeyword = $prefs{'abook_defaultfilter'}?$prefs{'abook_defaultkeyword'}:undef;
$abookkeyword = ow::tool::unescapeURL(param('abookkeyword')) if (defined param('abookkeyword'));
$keyword=ow::tool::unescapeURL($keyword);
$abookcollapse = param('abookcollapse');
$abookcollapse = $prefs{'abook_collapse'} if (!defined $abookcollapse);

# escaped addressbook globals
$escapedabookfolder = ow::tool::escapeURL($abookfolder);
$escapedabookkeyword = ow::tool::escapeURL($abookkeyword);

# refresh ldapcache addrbook
refresh_ldapcache_abookfile();

# does the requested book exist (mabye it was deleted)
if ($abookfolder ne "ALL" && !-e abookfolder2file($abookfolder)) {
   $abookfolder = $escapedabookfolder = 'ALL';
}

# all webmail related settings to remember
$webmail_urlparm = qq|folder=$escapedfolder&amp;|.
                   qq|page=$page&amp;|.
                   qq|sort=$sort&amp;|.
                   qq|msgdatetype=$msgdatetype&amp;|.
                   qq|searchtype=$searchtype&amp;|.
                   qq|keyword=$escapedkeyword&amp;|.
                   qq|message_id=$escapedmessageid|;
$webmail_formparm=ow::tool::hiddens(folder=>$escapedfolder,
                                    page=>$page,
                                    sort=>$sort,
                                    msgdatetype=>$msgdatetype,
                                    searchtype=>$searchtype,
                                    keyword=>$escapedkeyword,
                                    message_id=>$messageid);
# all addressbook settings to remember
$abook_urlparm = qq|abookpage=$abookpage&amp;|.
                 qq|abooklongpage=$abooklongpage&amp;|.
                 qq|abooksort=$abooksort&amp;|.
                 qq|abooksearchtype=$abooksearchtype&amp;|.
                 qq|abookkeyword=$escapedabookkeyword&amp;|.
                 qq|abookcollapse=$abookcollapse|;
$abook_urlparm_with_abookfolder = $abook_urlparm.
                                  qq|&amp;abookfolder=$escapedabookfolder|;
$abook_formparm=ow::tool::hiddens(abookpage=>$abookpage,
                                  abooklongpage=>$abooklongpage,
                                  abooksort=>$abooksort,
                                  abooksearchtype=>$abooksearchtype,
                                  abookkeyword=>$escapedabookkeyword,
                                  abookcollapse=>$abookcollapse);
$abook_formparm_with_abookfolder = $abook_formparm.
                                   ow::tool::hiddens(abookfolder=>$escapedabookfolder);
# common settings to remember
$urlparm=qq|$webmail_urlparm&amp;|.
         qq|$abook_urlparm_with_abookfolder&amp;|.
         qq|sessionid=$thissession|;
$formparm=$webmail_formparm.
          $abook_formparm_with_abookfolder.
          ow::tool::hiddens(sessionid=>$thissession);

my $action = param('action')||'';
writelog("debug - request abook begin, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ($action eq "addrlistview") {
   addrlistview();
} elsif ($action eq "addrshowchecked") {
   addrshowchecked();
} elsif ($action eq "addrbookedit") {
   addrbookedit();
} elsif ($action eq "addrbookadd") {
   addrbookadd();
} elsif ($action eq "addrbookdelete") {
   addrbookdelete();
} elsif ($action eq "addrbookrename") {
   addrbookrename();
} elsif ($action eq "addrbookdownload") {
   addrbookdownload();
} elsif ($action eq "addreditform") {
   addreditform();
} elsif ($action eq "addredit") {
   addredit();
} elsif ($action eq "addrmovecopydelete") {
   addrmovecopydelete();
} elsif ($action eq "addrimportform") {
   addrimportform();
} elsif ($action eq "addrimport") {
   addrimport();
} elsif ($action eq "addrexport") {
   addrexport();
} elsif ($action eq "addrviewatt") {
   addrviewatt();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request abook end, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################


########## ADDRBOOKADD ###########################################
sub addrbookadd {
   my $abookfoldernewstr = ow::tool::untaint(param('abookfoldernew'))||'';
   my $abookfoldernew = u2f($abookfoldernewstr);
   is_safefoldername($abookfoldernew) or
      openwebmailerror(__FILE__, __LINE__, "$abookfoldernewstr $lang_err{'has_illegal_chars'}");

   return addrbookedit() if ($abookfoldernew eq '');

   my $abookfilenew = abookfolder2file($abookfoldernew);
   if (-e $abookfilenew || $abookfoldernew =~ m/^(?:ALL|DELETE)$/) {
      my $msg=$lang_err{'abook_already_exists'};
      $msg =~ s/\@\@\@ADDRESSBOOK\@\@\@/$abookfoldernewstr/;
      openwebmailerror(__FILE__, __LINE__, $msg);
   } else {
      if (length($abookfoldernew) > $config{'foldername_maxlen'}) {
         my $msg="$lang_err{'abook_name_too_long'}";
         $msg =~ s/\@\@\@ADDRESSBOOK\@\@\@/$abookfoldernewstr/;
         $msg =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/;
         openwebmailerror(__FILE__, __LINE__, $msg);
      } else {
         sysopen(NEWBOOK, $abookfilenew, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'cant_create_folder'}! ($!)");
         close(NEWBOOK);

         writelog("add addressbook - $abookfoldernew");
         writehistory("add addressbook - $abookfoldernew");
      }
   }

   addrbookedit();
}
########## END ADDRBOOKADD #######################################


########## ADDRBOOKDELETE ########################################
sub addrbookdelete {
   $abookfolder = ow::tool::untaint(safefoldername($abookfolder));
   my $abookfolderstr = f2u($abookfolder);
   my $abookfile = abookfolder2file($abookfolder);

   # do the delete
   if (-e $abookfile) {
      my $msg=$lang_err{'abook_delete_book'}; $msg=~s/\@\@\@ADDRESSBOOK\@\@\@/$abookfolderstr/;
      unlink($abookfile) or openwebmailerror(__FILE__, __LINE__, "$msg! ($!)");
      writelog("delete addressbook - $abookfolder");
      writehistory("delete addressbook - $abookfolder");
   } else {
      my $msg=$lang_err{'abook_doesnt_exist'}; $msg=~s/\@\@\@ADDRESSBOOK\@\@\@/$abookfolderstr/;
      openwebmailerror(__FILE__, __LINE__, "$msg! ($!)");
   }

   addrbookedit();
}
########## END ADDRBOOKDELETE ####################################


########## ADDRBOOKEDIT ##########################################
sub addrbookedit {
   # keep totals
   my %total = ();

   # load the addresses - only the required information
   my %addresses=();
   my %searchterms = ();
   my %only_return = ('N' => 1);

   my @allabookfolders = get_readable_abookfolders();
   foreach my $abookfolder (@allabookfolders) {
      my $abookfile=abookfolder2file($abookfolder);
      my $thisbook = readadrbook($abookfile, (keys %searchterms?\%searchterms:undef), (keys %only_return?\%only_return:undef));
      $total{$abookfolder}{'entries'} = keys %{$thisbook};
      $total{$abookfolder}{'size'} = (-s $abookfile);
   }

   # get the html cooking
   my ($html, $temphtml) = ();
   $html = applystyle(readtemplate("addrbookedit.template"));

   # menubar links
   my $abookfolderstr=ow::htmltext::str2html($lang_abookselectionlabels{$abookfolder}||f2u($abookfolder));
   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $abookfolderstr",
                        qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;$urlparm"|);
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $html =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/g;

   # add addressbooks form
   $temphtml = start_form(-name=>"addBookForm",
                          -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
               ow::tool::hiddens(
                                 action=>'addrbookadd',
                                 sessionid=>$thissession,
                                );
   $html =~ s/\@\@\@STARTFOLDERFORM\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'abookfoldernew',
                         -default=>'',
                         -size=> 24,
                         -maxlength=>$config{'foldername_maxlen'},
                         -accesskey=>'I',
                         -override=>'1');
   $html =~ s/\@\@\@FOLDERNAMEFIELD\@\@\@/$temphtml/;

   $temphtml = submit(-name=>$lang_text{'add'},
                      -accesskey=>'A',
                      -class=>"medtext");
   $html =~ s/\@\@\@ADDBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   my @bgcolor = ($style{"tablerow_dark"}, $style{"tablerow_light"});
   my $colornum = 0;

   # the personal abook folder data
   my $i = 1;
   $temphtml = '';
   foreach my $abookfolder (@allabookfolders) {
      next if (is_abookfolder_global($abookfolder));
      my $escapedabookfolder = ow::tool::escapeURL($abookfolder);
      my $abookfolderstr=f2u($abookfolder);
      my $jsfolderstr = $abookfolderstr; $jsfolderstr =~ s/'/\\'/g;
      $temphtml .= qq|<tr>\n|.
                   qq|<td width="10" bgcolor=$bgcolor[$colornum]>&nbsp;</td>|.
                   qq|<td bgcolor=$bgcolor[$colornum]>|.
                   iconlink("download.gif", $lang_text{'download'},
                             qq|accesskey="W" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrbookdownload&amp;sessionid=$thissession&amp;abookfolder=$escapedabookfolder"|).
                   qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;sessionid=$thissession&amp;abookfolder=$escapedabookfolder">|.ow::htmltext::str2html($abookfolderstr).qq|</a></td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor[$colornum]>$total{$abookfolder}{'entries'}</td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor[$colornum]>|.lenstr($total{$abookfolder}{'size'},0).qq|</td>\n|.
                   qq|<td bgcolor=$bgcolor[$colornum] align="center" nowrap>\n|.
                   qq|   <table cellpadding="0" cellspacing="0" border="0">\n|.
                   qq|   <tr>\n|.
                   qq|      <td>\n|.

                   start_form(-name=>"abookDeleteForm$i",
                              -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                   ow::tool::hiddens(
                                     action=>'addrbookdelete',
                                     sessionid=>$thissession,
                                     abookfolder=>ow::tool::escapeURL($abookfolder),
                                    ).
                   submit(-name=>$lang_text{'delete'}, -class=>"medtext",
                          -onClick=>"return OpConfirm('deletebook', 'abookDeleteForm$i', $lang_text{'folderdelconf'}+' ($jsfolderstr)');").
                   end_form().

                   qq|      </td>\n|.
                   qq|      <td>\n|.

                   start_form(-name=>"abookRenameForm$i",
                              -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                   ow::tool::hiddens(
                                     action=>'addrbookrename',
                                     sessionid=>$thissession,
                                     abookfolder=>ow::tool::escapeURL($abookfolder),
                                     abookfolderstr=>$abookfolderstr,
                                     abookfoldernew=>'',
                                    ).
                   submit(-name=>$lang_text{'rename'}, -class=>"medtext",
                          -onClick=>"return OpConfirm('renamebook', 'abookRenameForm$i', $lang_text{'folderrenprop'})").
                   end_form().

                   qq|      </td>\n|.
                   qq|   </tr>\n|.
                   qq|   </table>\n|.
                   qq|</td>\n|.
                   qq|</tr>\n|;

      $colornum=($colornum+1)%2; # alternate the bgcolor
      $i++;
   }
   $html =~ s/\@\@\@FOLDERS\@\@\@/$temphtml/;

   # the default abook folder data
   $colornum = 1;
   $temphtml = '';
   foreach my $abookfolder (get_global_abookfolders()) {
      my $abookfolderstr=$lang_abookselectionlabels{$abookfolder}||f2u($abookfolder);
      $temphtml .= qq|<tr>\n|.
                   qq|<td width="10" bgcolor=$bgcolor[$colornum]>&nbsp;</td>|.
                   qq|<td bgcolor=$bgcolor[$colornum]>|.
                   iconlink("download.gif", $lang_text{'download'},
                             qq|accesskey="W" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrbookdownload&amp;sessionid=$thissession&amp;abookfolder=$abookfolder"|).
                   qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;sessionid=$thissession&amp;abookfolder=|.ow::tool::escapeURL($abookfolder).qq|">|.ow::htmltext::str2html($abookfolderstr).qq|</a></td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor[$colornum]>$total{$abookfolder}{'entries'}</td>\n|.
                   qq|<td align="center" bgcolor=$bgcolor[$colornum]>|.lenstr($total{$abookfolder}{'size'},0).qq|</td>\n|.
                   qq|<td bgcolor=$bgcolor[$colornum] align="center">&nbsp;</td>\n|.
                   qq|</tr>\n|;
      $colornum=($colornum+1)%2; # alternate the bgcolor
   }
   $html =~ s/\@\@\@DEFAULTFOLDERS\@\@\@/$temphtml/;

   # totals
   my ($totalsize, $totalentries) = (0, 0);
   for (keys %total) {
      $totalsize += $total{$_}{'size'};
      $totalentries += $total{$_}{'entries'};
   }
   $temphtml = qq|<tr>|.
               qq|<td width="10" bgcolor=$bgcolor[$colornum]>&nbsp;</td>|.
               qq|<td bgcolor=$bgcolor[$colornum]><b>$lang_text{'total'}</b></td>|.
               qq|<td bgcolor=$bgcolor[$colornum] align="center"><b>$totalentries</b></td>|.
               qq|<td bgcolor=$bgcolor[$colornum] align="center"><b>|.lenstr($totalsize,0).qq|</b></td>|.
               qq|<td bgcolor=$bgcolor[$colornum] align="center">&nbsp;</td>\n|.
               qq|</tr>\n|;
   $html =~ s/\@\@\@TOTAL\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END ADDRBOOKEDIT ######################################


########## ADDRBOOKRENAME ########################################
sub addrbookrename {
   my $abookfoldernewstr = ow::tool::untaint(param('abookfoldernew')) || '';
   my $abookfoldernew=u2f($abookfoldernewstr);
   is_safefoldername($abookfoldernew) or
      openwebmailerror(__FILE__, __LINE__, "$abookfoldernewstr $lang_err{'has_illegal_chars'}");
   $abookfoldernew = safefoldername($abookfoldernew);
   return addrbookedit() if ($abookfoldernew eq '');

   $abookfolder = ow::tool::untaint(safefoldername($abookfolder));

   my $abookfilenew=abookfolder2file($abookfoldernew);
   my $abookfile=abookfolder2file($abookfolder);

   if (-e $abookfilenew || $abookfoldernew=~/^(?:ALL|DELETE|)$/) {
      my $msg=$lang_err{'abook_already_exists'}; $msg =~ s/\@\@\@ADDRESSBOOK\@\@\@/$abookfoldernewstr/;
      openwebmailerror(__FILE__, __LINE__, $msg);
   } else {
      if (length($abookfoldernew) > $config{'foldername_maxlen'}) {
         my $msg=$lang_err{'abook_name_too_long'};
         $msg =~ s/\@\@\@ADDRESSBOOK\@\@\@/$abookfoldernewstr/;
         $msg =~ s/\@\@\@FOLDERNAME_MAXLEN\@\@\@/$config{'foldername_maxlen'}/;
         openwebmailerror(__FILE__, __LINE__, $msg);
      } else {
         rename($abookfile, $abookfilenew) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_cant_rename'}! ($!)");
         writelog("rename addressbook - $abookfolder to $abookfoldernew");
         writehistory("rename addressbook - $abookfolder to $abookfoldernew");
      }
   }

   addrbookedit();
}
########## END ADDRBOOKRENAME ####################################


########## ADDRBOOKDOWNLOAD ######################################
sub addrbookdownload {
   $abookfolder = ow::tool::untaint(safefoldername($abookfolder));
   my $abookfile=abookfolder2file($abookfolder);

   ow::filelock::lock($abookfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($abookfile));

   my ($cmd, $contenttype, $filename);
   if ( ($cmd=ow::tool::findbin("zip")) ne "" ) {
      $contenttype='application/x-zip-compressed';
      $filename="$abookfolder.vcf.zip";
      open(T, "-|") or
         do { open(STDERR,">/dev/null"); exec(ow::tool::untaint($cmd), "-qj", "-", $abookfile); exit 9 };
   } elsif ( ($cmd=ow::tool::findbin("gzip")) ne "" ) {
      $contenttype='application/x-gzip-compressed';
      $filename="$abookfolder.vcf.gz";
      open(T, "-|") or
         do { open(STDERR,">/dev/null"); exec(ow::tool::untaint($cmd), "-c", $abookfile); exit 9 };
   } else {
      $contenttype='application/x-vcard';
      $filename="$abookfolder.vcf";
      sysopen(T, $abookfile, O_RDONLY);
   }

   $filename=~s/\s+/_/g;

   # disposition:attachment default to save
   print qq|Connection: close\n|,
         qq|Content-Type: $contenttype; name="$filename"\n|;
   if ( $ENV{'HTTP_USER_AGENT'}=~/MSIE 5.5/ ) { # ie5.5 is broken with content-disposition: attachment
      print qq|Content-Disposition: filename="$filename"\n|;
   } else {
      print qq|Content-Disposition: attachment; filename="$filename"\n|;
   }
   print qq|\n|;

   my $buff;
   while ( read(T, $buff,32768) ) {
     print $buff;
   }

   close(T);

   ow::filelock::lock($abookfile, LOCK_UN);

   writelog("download addressbook - $abookfolder");
   writehistory("download addressbook - $abookfolder");

   return;
}
########## END ADDRBOOKDOWNLOAD ##################################


########## ADDRLISTVIEW ##########################################
# addrlistview can run in 3 modes, so know what mode you are
# running in before you start hacking here. The 3 modes are
# '','composeselect', and 'export'.
# (composeselect has 2 cases, editgroup or compose)
sub addrlistview {
   # show the book we left from
   my $editformcaller = safefoldername(ow::tool::unescapeURL(param('editformcaller')));
   if ($editformcaller ne '') {
      $abookfolder = $editformcaller;
      $escapedabookfolder = ow::tool::escapeURL($abookfolder);
   }

   # are we coming from the compose page?
   my $listviewmode = param('listviewmode');
   my $editgroupform=0;
   if ($listviewmode eq 'composeselect' && param('editgroupform')) {
      # param(editgroupform) is always set in the submit button in editgroup form
      # which causes param(editgroupform) here be set even the listviewmode is not composeselect
      # so we need to check both the listviewmode and editgroup parm
      $editgroupform=1;
   }

   my @fieldorder=split(/\s*[,\s]\s*/, $prefs{'abook_listviewfieldorder'});

   if ($listviewmode eq 'composeselect') {
      # use only the name type and email type headers
      # we don't want to see phone or note in this mode
      my $emailexists = 0;
      for (my $i=0; $i <= $#fieldorder; $i++) {
         if ($fieldorder[$i] eq 'email') {
            $emailexists = 1;
         }
         if ($fieldorder[$i] !~ m/^(fullname|prefix|first|middle|last|suffix|email)$/) {
            splice(@fieldorder,$i,1); # take this one out
            $i--; # do this index over since the array got shorter
         }
      }
      if ($emailexists == 0) {
         # email must be a header in the compose mode
         push(@fieldorder,'email');
      }
   }

   # what do users want to see?
   my @headings = @fieldorder;
   for(my $index=0; $index <= $#headings; $index++) {
      if ($headings[$index] =~ m/^none$/i) {
         splice(@headings,$index,1); # take out the nones
         $index--;                   # do this index over since the array got shorter
      }
   }

   # prep for html
   my ($html, $temphtml);

   # store the column position of each heading
   my %headingpos = ();
   for (0..$#headings) { $headingpos{$headings[$_]} = $_+1 }; # The +1 is for the num column

   # load up the list of available books
   my @allabookfolders = get_readable_abookfolders();		# readable ones
   my @writableabookfolders = get_writable_abookfolders();	# writable ones

   # calculate the available free space
   my $availfreespace = $config{'abook_maxsizeallbooks'} - userabookfolders_totalsize();

   # load the addresses - only the required information
   my %addresses=();
   my %searchterms = ();

   my %vcardmapping = (
                       'fullname' => 'FN',
                       'prefix'   => 'N',
                       'first'    => 'N',
                       'middle'   => 'N',
                       'last'     => 'N',
                       'suffix'   => 'N',
                       'email'    => 'EMAIL',
                       'phone'    => 'TEL',
                       'note'     => 'NOTE',
                       'categories' => 'CATEGORIES',
                      );

   my %only_return = (                       # Always load these ones because:
                       'CATEGORIES' => 1,    # Categories is always a searchable parameter
                       'SORT-STRING' => 1,   # We need to be able to do sort overrides
                       'X-OWM-CHARSET' => 1, # This charset of data in this vcard
                       'X-OWM-GROUP' => 1,   # There is special handling for group entries, so we must always know
                     );
   $only_return{$vcardmapping{$_}}=1 for (@headings); # populate %only_return with what else we want

   my %Nmap = (
               'prefix' => 'NAMEPREFIX',
               'first'  => 'GIVENNAME',
               'middle' => 'ADDITIONALNAMES',
               'last'   => 'FAMILYNAME',
               'suffix' => 'NAMESUFFIX',
              );

   # setup the search terms
   if ($abooksearchtype ne '' && defined $abookkeyword && $abookkeyword ne '' && $abookkeyword !~ m/^\s+$/) {
      if ($vcardmapping{$abooksearchtype} eq 'N') {
         $searchterms{$vcardmapping{$abooksearchtype}}[0]{VALUE}{$Nmap{$abooksearchtype}} = $abookkeyword;
      } elsif ($vcardmapping{$abooksearchtype} eq 'CATEGORIES') {
         $searchterms{$vcardmapping{$abooksearchtype}}[0]{VALUE}{CATEGORIES}[0] = $abookkeyword;
      } else {
         $searchterms{$vcardmapping{$abooksearchtype}}[0]{VALUE} = $abookkeyword;
      }
      $searchterms{'X-OWM-CHARSET'}[0]{VALUE} = $prefs{'charset'};
   }

   my @viewabookfolders=();
   foreach (@allabookfolders) {
      if ($abookfolder eq $_) {		#  current book is one of the readable books
         push(@viewabookfolders, $_); last;
      }
   }
   @viewabookfolders=@allabookfolders if ($#viewabookfolders<0);
   foreach my $abookfolder (@viewabookfolders) {
      my $abookfile=abookfolder2file($abookfolder);
      my $thisbook = readadrbook($abookfile, (keys %searchterms?\%searchterms:undef), \%only_return);
      # remember what book this address came from
      foreach my $xowmuid (keys %{$thisbook}) {
         ${$thisbook}{$xowmuid}{'X-OWM-BOOK'}[0]{VALUE} = $abookfolder;
         # add it to addresses
         $addresses{$xowmuid} = ${$thisbook}{$xowmuid};
      }
   }


   # sort the addresses
   my %TELsort = (
                  'PREF'  => '0',
                  'HOME'  => '1',
                  'WORK'  => '2',
                  'CELL'  => '3',
                  'CAR'   => '4',
                  'FAX'   => '5',
                  'PAGER' => '6',
                  'VOICE' => '7',
                  'VIDEO' => '8',
                  'MSG'   => '9',
                  'BBS'   => '10',
                  'ISDN'  => '11',
                  'MODEM' => '12',
                 );

   foreach my $xowmuid (keys %addresses) {
      # first sub-sort the EMAIL and TEL fields if they exist in each record
      # so that the main sort uses the correct 'top' email or tel value
      if (exists($addresses{$xowmuid}{TEL})) {
         # sort the numbers by the TELsort custom sorting hash
         @{$addresses{$xowmuid}{TEL}} = sort { # figure out the highest priority number
                                               my $aPri = 13; # assign lowest priority by default
                                               my $bPri = 13; # assign lowest priority by default
                                               for (keys %TELsort) {
                                                  if (exists($a->{TYPES})) {
                                                     if (exists($a->{TYPES}{$_})) {
                                                        $aPri = $TELsort{$_} if $TELsort{$_} < $aPri;
                                                     }
                                                  }
                                                  if (exists($b->{TYPES})) {
                                                     if (exists($b->{TYPES}{$_})) {
                                                        $bPri = $TELsort{$_} if $TELsort{$_} < $bPri;
                                                     }
                                                  }
                                               }

                                               # Now compare based on priority then value
                                               ($aPri == $bPri ? $a->{VALUE} cmp $b->{VALUE} : $aPri <=> $bPri);
                                             } @{$addresses{$xowmuid}{TEL}};
      }
      if (exists($addresses{$xowmuid}{EMAIL})) {
         # sort the emails alphabetically - pop the prefs (exists=0) to the top - Schwartzian transform
         @{$addresses{$xowmuid}{EMAIL}} = map { $_->[2] }
                                          sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] }
                                          map { [ exists($_->{TYPES})?(exists($_->{TYPES}{PREF})?0:1):1, lc($_->{VALUE}), $_] }
                                          @{$addresses{$xowmuid}{EMAIL}};
      }
      if (exists($addresses{$xowmuid}{NOTE})) {
         # sort the notes alphabetically
         @{$addresses{$xowmuid}{NOTE}} = sort { $a->{VALUE} cmp $b->{VALUE} } @{$addresses{$xowmuid}{NOTE}};
      }
   }

   my $abooksort_short = $abooksort;
   $abooksort_short =~ s/_rev$//;
   $abooksort = $abooksort_short = $headings[0] if (!exists $headingpos{$abooksort_short});

   my @sorted_addresses = ();
   if ($abooksort =~ m/^(?:fullname|email|phone|note)$/) {
      @sorted_addresses = sort { (exists($addresses{$a}{$vcardmapping{$abooksort_short}})?lc($addresses{$a}{$vcardmapping{$abooksort_short}}[0]{VALUE}):undef) cmp
                                 (exists($addresses{$b}{$vcardmapping{$abooksort_short}})?lc($addresses{$b}{$vcardmapping{$abooksort_short}}[0]{VALUE}):undef)
                               } keys %addresses;

   } elsif ($abooksort =~ m/^(?:fullname_rev|email_rev|phone_rev|note_rev)$/) {
      @sorted_addresses = sort { (exists($addresses{$b}{$vcardmapping{$abooksort_short}})?lc($addresses{$b}{$vcardmapping{$abooksort_short}}[0]{VALUE}):undef) cmp
                                 (exists($addresses{$a}{$vcardmapping{$abooksort_short}})?lc($addresses{$a}{$vcardmapping{$abooksort_short}}[0]{VALUE}):undef)
                               } keys %addresses;
   } elsif ($abooksort =~ m/_rev$/) {
      @sorted_addresses = sort { (exists($addresses{$b}{N})?
                                   (exists($addresses{$b}{N}[0]{VALUE}{$Nmap{$abooksort_short}})?
                                     ($abooksort_short eq 'last' && exists($addresses{$b}{'SORT-STRING'}))?
                                     lc($addresses{$b}{'SORT-STRING'}[0]{VALUE}):lc($addresses{$b}{N}[0]{VALUE}{$Nmap{$abooksort_short}})
                                     :undef)
                                 :undef)
                                 cmp
                                 (exists($addresses{$a}{N})?
                                   (exists($addresses{$a}{N}[0]{VALUE}{$Nmap{$abooksort_short}})?
                                     ($abooksort_short eq 'last' && exists($addresses{$a}{'SORT-STRING'}))?
                                     lc($addresses{$a}{'SORT-STRING'}[0]{VALUE}):lc($addresses{$a}{N}[0]{VALUE}{$Nmap{$abooksort_short}})
                                     :undef)
                                 :undef)
                               } keys %addresses;
   } else {
      @sorted_addresses = sort { (exists($addresses{$a}{N})?
                                   (exists($addresses{$a}{N}[0]{VALUE}{$Nmap{$abooksort_short}})?
                                     ($abooksort_short eq 'last' && exists($addresses{$a}{'SORT-STRING'}))?
                                     lc($addresses{$a}{'SORT-STRING'}[0]{VALUE}):lc($addresses{$a}{N}[0]{VALUE}{$Nmap{$abooksort_short}})
                                     :undef)
                                 :undef)
                                 cmp
                                 (exists($addresses{$b}{N})?
                                   (exists($addresses{$b}{N}[0]{VALUE}{$Nmap{$abooksort_short}})?
                                     ($abooksort_short eq 'last' && exists($addresses{$b}{'SORT-STRING'}))?
                                     lc($addresses{$b}{'SORT-STRING'}[0]{VALUE}):lc($addresses{$b}{N}[0]{VALUE}{$Nmap{$abooksort_short}})
                                     :undef)
                                 :undef)
                               } keys %addresses;
   }


   # calculate how many pages we have and which addresses are on this page
   my $addrperpage=$prefs{'abook_addrperpage'}||10;
   $addrperpage = 5 if ($listviewmode eq 'export');
   $addrperpage=1000 if ($abooklongpage);

   my $totaladdrs=keys %addresses;
   my $totalpage=int($totaladdrs/$addrperpage+0.999999); $totalpage=1 if ($totalpage==0);
   $abookpage = 1 if ($abookpage < 1); $abookpage = $totalpage if ($abookpage>$totalpage);

   my $firstaddr = ($abookpage-1)*$addrperpage + 1;
   my $lastaddr = $firstaddr + $addrperpage - 1;
   $lastaddr = $totaladdrs if ($lastaddr>$totaladdrs);

   $firstaddr--; $lastaddr--; # to make it pull the correct entry from the sortedaddresses array

   # remember all of the email addresses user checked with %waschecked hash
   my %waschecked = ();
   foreach my $key ('TO', 'CC', 'BCC') {
      foreach my $parmname (lc($key), 'checked'.lc($key)) {
         my $recipients = join(',', param(lc($parmname)));
         # these param are passed in by javascript escape() routine
         # CJK will be encoded as %uXXXX, we have to convert them back to prefs charset
         if ($recipients =~ s/%u([0-9a-fA-F]{4})/ow::tool::ucs4_to_utf8(hex($1))/ge) {
            ($recipients) = iconv('utf-8', $prefs{'charset'}, $recipients);
         }
         for (ow::tool::str2list($recipients)) {
            $waschecked{$key}{$_} = 1 if ($_ ne '');
         }
      }
   }

   # addresses arrive from editgroupform as '\n' delimited.
   # separate them into each individual addresses and put them
   # in %waschecked.
   foreach my $key (qw(TO CC BCC)) {
      foreach my $email (keys %{$waschecked{$key}}) {
         delete $waschecked{$key}{$email};
         foreach my $line (split(/\n/,$email)) {
            $line =~ s/^\s+//; $line =~ s/\s+$//;
            $waschecked{$key}{$line} = 1 if ($line ne '');
         }
      }
   }

   # move the ones that appear on the current page being viewed from %waschecked to %ischecked
   my %ischecked = ();
   foreach my $addrindex ($firstaddr..$lastaddr) {
      my $xowmuid = $sorted_addresses[$addrindex];

      # when we are in normal listview mode we add the xowmuid
      # to the check fields so that move/copy/delete applies to
      # the correct contact.
      my $xowmuidtrack = ($listviewmode?'':"%@#$xowmuid");

      # all group cards should have an all members entry
      if (exists($addresses{$xowmuid}{'X-OWM-GROUP'})) {
         unshift(@{$addresses{$xowmuid}{'EMAIL'}}, {'VALUE'=>$lang_text{'abook_group_allmembers'}, 'TYPES'=>{ 'PREF' => 'TYPE' }});
      }

      # how many rows for this $xowmuid
      my $rows = (# build a list of how many entries this xowmuid has for each heading, sort largest to the top
                  sort { $b <=> $a }
                   map { exists($addresses{$xowmuid}{$vcardmapping{$_}})?$#{$addresses{$xowmuid}{$vcardmapping{$_}}}:0 }
                  grep { !m/^(to|cc|bcc)$/ } @headings
                 )[0]; # but only return the largest one

      if ($rows >= 0) {
         for(my $index=0; $index <= $rows; $index++) {
            next if ($index > 0 && $abookcollapse == 1);
            if (exists $addresses{$xowmuid}{EMAIL}) {
               if (defined $addresses{$xowmuid}{EMAIL}[$index]) {
                  my $email = '';
                  if ($listviewmode eq 'export') {
                     # keep track of xowmuids, not email addresses
                     $email = $xowmuid;
                  } else {
                     if (exists($addresses{$xowmuid}{'X-OWM-GROUP'}) && $index == 0) {
                        $email = join (", ", grep { !m/^$lang_text{'abook_group_allmembers'}$/ }
                                              map { $_->{'VALUE'} }
                                             sort { lc($a->{'VALUE'}) cmp lc($b->{'VALUE'}) } @{$addresses{$xowmuid}{EMAIL}}
                                      );
                     } else {
                        if (!exists($addresses{$xowmuid}{'X-OWM-GROUP'}) && exists $addresses{$xowmuid}{FN}) {
                           $email = qq|"$addresses{$xowmuid}{FN}[0]{VALUE}" <$addresses{$xowmuid}{EMAIL}[$index]{VALUE}>|;
                        } elsif (!exists($addresses{$xowmuid}{'X-OWM-GROUP'}) && exists $addresses{$xowmuid}{N}) {
                           $email = join (" ", map { exists $addresses{$xowmuid}{N}[0]{VALUE}{$_}?
                                                     defined $addresses{$xowmuid}{N}[0]{VALUE}{$_}?$addresses{$xowmuid}{N}[0]{VALUE}{$_}:''
                                                     :''
                                                   } qw(NAMEPREFIX GIVENNAME ADDITIONALNAMES FAMILYNAME NAMESUFFIX)
                                         );
                           $email =~ s/^\s+(\S)/$1/;
                           $email =~ s/(\S)\s+$/$1/;
                           $email = qq|"$email" <$addresses{$xowmuid}{EMAIL}[$index]{VALUE}>|;
                        } else {
                           $email = "$addresses{$xowmuid}{EMAIL}[$index]{VALUE}";
                        }
                     }
                  }
                  # do iconv on the "name" part of the "name" <user@hostname>
                  ($email)=iconv($addresses{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}, $prefs{charset}, $email);

                  foreach my $key (qw(TO CC BCC)) {
                     if (exists $addresses{$xowmuid}{'X-OWM-GROUP'} && $abookcollapse == 1) {
                        # move all or none to %ischecked
                        my $allarechecked = 1;
                        foreach my $member (ow::tool::str2list($email)) {
                           $member .= $xowmuidtrack; # add the xowmuid to match the checked string
                           $allarechecked = exists $waschecked{$key}{$member}?1:undef;
                           last unless defined $allarechecked;
                        }
                        if ($allarechecked) {
                           foreach my $member (ow::tool::str2list($email)) {
                              $member .= $xowmuidtrack; # add the xowmuid to match the checked string
                              delete $waschecked{$key}{$member};
                              $ischecked{$key}{$member} = 1;
                           }
                        }
                     } else {
                        foreach my $member (ow::tool::str2list($email)) {
                           $member .= $xowmuidtrack; # add the xowmuid to match the checked string
                           if (exists $waschecked{$key}{$member}) {
                              delete $waschecked{$key}{$member};
                              $ischecked{$key}{$member} = 1;
                           }
                        }
                     }
                  }
               }
            } elsif ($listviewmode eq 'export') {
               my $email = $xowmuid;
               foreach my $key (qw(TO CC BCC)) {
                  if (exists $addresses{$xowmuid}{'X-OWM-GROUP'} && $abookcollapse == 1) {
                     # move all or none to %ischecked
                     my $allarechecked = 1;
                     foreach my $member (ow::tool::str2list($email)) {
                        $allarechecked = exists $waschecked{$key}{$member}?1:undef;
                        last unless defined $allarechecked;
                     }
                     if ($allarechecked) {
                        foreach my $member (ow::tool::str2list($email)) {
                           delete $waschecked{$key}{$member};
                           $ischecked{$key}{$member} = 1;
                        }
                     }
                  } else {
                     foreach my $member (ow::tool::str2list($email)) {
                        if (exists $waschecked{$key}{$member}) {
                           delete $waschecked{$key}{$member};
                           $ischecked{$key}{$member} = 1;
                        }
                     }
                  }
               }
            }
         }
      }
   }

   # remember what was checked so we can put these values into our form.
   # if we are in an editgroupform scenario the remembered addresses will be
   # '\n' delimited instead of ', ' delimited.
   my $checkedto = join(($editgroupform?"\n":", "), sort { lc($a) cmp lc($b) } keys %{$waschecked{TO}});
   my $checkedcc = join(($editgroupform?"\n":", "), sort { lc($a) cmp lc($b) } keys %{$waschecked{CC}});
   my $checkedbcc = join(($editgroupform?"\n":", "), sort { lc($a) cmp lc($b) } keys %{$waschecked{BCC}});

   # check if quota is overlimit
   my $limited=(($quotalimit>0 && $quotausage>$quotalimit));

   # setup the table specs and row color toggle
   my $tabletotalspan = '';
   if ($listviewmode eq 'export' || $editgroupform) {
      $tabletotalspan = @headings + 2; # number, (export|to)
   } else {
      $tabletotalspan = @headings + 4; # number,to,cc,bcc
   }

   # Now we can start making the html
   $html = applystyle(readtemplate("addrlistview.template"));
   $html .= applystyle(readtemplate("displaynote.js")) if (exists $only_return{NOTE});

   # apply the extra html to the template for this mode
   if ($listviewmode eq 'export') {
      applytemplatemode(\$html,"addrexportbook.template");
   } elsif ($listviewmode eq 'composeselect') {
      applytemplatemode(\$html,"addrcomposeselect.template");
   } else {
      $html =~ s/\@\@\@BEFORELISTVIEWEXTRAHTML\@\@\@//;
      $html =~ s/\@\@\@AFTERLISTVIEWEXTRAHTML\@\@\@//;
      $html =~ s/\@\@\@EXTRAJAVASCRIPT\@\@\@//;
   }

   $html =~ s/\@\@\@TOTALSPAN\@\@\@/$tabletotalspan/g;

   # the addressbook selection
   $temphtml = start_form(-name=>'abookFolderForm',
                         -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl");

   # selection menu with fscharset support, tricky but important sample!
   # this abookfolder needs to be unescaped when retrivaled from param (see line 32)
   my (@abookvalues, %abooklabels);
   foreach my $abook ('ALL', @allabookfolders) {
      my ($value, $label)=(ow::tool::escapeURL($abook), $abook);
      $label=(defined $lang_abookselectionlabels{$abook})?$lang_abookselectionlabels{$abook}:f2u($abook);
      $label.=" *" if (is_abookfolder_global($abook));
      push(@abookvalues, $value); $abooklabels{$value}=$label;
   }
   $temphtml .= popup_menu(-name=>'abookfolder',
                           -default=>ow::tool::escapeURL($abookfolder),
                           -values=>\@abookvalues,
                           -labels=>\%abooklabels,
                           -override=>1,
                           -onChange=>"javascript:document.forms['contactsForm'].elements['abookfolder'].value=document.forms['abookFolderForm'].elements['abookfolder'].options[document.forms['abookFolderForm'].elements['abookfolder'].selectedIndex].value; document.contactsForm.submit();");

   $temphtml .= end_form();
   if ($listviewmode eq '') {
      $html =~ s/\@\@\@ABOOKSELECTIONFORM\@\@\@/$temphtml/g;
   } elsif ($listviewmode eq 'export') {
      $html =~ s#\@\@\@ABOOKSELECTIONFORM\@\@\@#<font color=$style{'titlebar_text'} face=$style{'fontface'} size="3"><b>$lang_text{'abook_export'}</b></font>#g;
   } elsif ($listviewmode eq 'composeselect') {
#      $html =~ s#\@\@\@ABOOKSELECTIONFORM\@\@\@#<font color=$style{'titlebar_text'} face=$style{'fontface'} size="3"><b>$lang_text{'abook_listview_composemode'}</b></font>#g;
      $html =~ s/\@\@\@ABOOKSELECTIONFORM\@\@\@/$temphtml/g;	# menu could be helpful in composeselect mode, tung
   }

   $html =~ s/\@\@\@FREESPACE\@\@\@/$availfreespace $lang_sizes{'kb'}/g;


   # left side navigation buttons
   $temphtml = '';
   if ($listviewmode eq '') {
      if ($#writableabookfolders>=0) {
         $temphtml .= iconlink("abooknewcontact.gif", $lang_text{'abook_newcontact'},
                               qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addreditform&amp;$urlparm"|);
         $temphtml .= iconlink("abooknewgroup.gif", $lang_text{'abook_newgroup'},
                               qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addreditform&amp;editgroupform=1&amp;$urlparm"|);
      } else {
         $temphtml .= iconlink("abooknewcontact.gif", $lang_text{'abook_newcontact'},
                            qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrbookedit&amp;$urlparm" onclick="return confirm('$lang_err{abook_all_readonly}');"|);
         $temphtml .= iconlink("abooknewgroup.gif", $lang_text{'abook_newgroup'},
                            qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrbookedit&amp;$urlparm" onclick="return confirm('$lang_err{abook_all_readonly}');"|);
      }

      $temphtml .= iconlink("abooks.gif", $lang_text{'abooks'},
                            qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrbookedit&amp;$urlparm"|);
      $temphtml .= iconlink("abookimport.gif", $lang_text{'abook_import'}, qq|accesskey="I" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrimportform&amp;$urlparm"|);
      $temphtml .= iconlink("abookexport.gif", $lang_text{'abook_export'}, qq|accesskey="E" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;sessionid=$thissession&amp;listviewmode=export"|);
      if ($abookkeyword ne ''){
         $temphtml .= "&nbsp;\n";
         $temphtml .= iconlink("refresh.gif", $lang_text{'refresh'},
                                qq|accesskey="R" href="javascript:document.contactsForm.abookkeyword.value=''; document.contactsForm.submit();"|
                              );
      }

      $temphtml .= "&nbsp;\n";
      if ($config{'enable_webmail'}) {
         my $folderstr=ow::htmltext::str2html($lang_folders{$folder}||f2u($folder));
         if ($messageid eq "") {
            $temphtml .= iconlink("owm.gif", "$lang_text{'backto'} $folderstr",
                                  qq|accesskey="M" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;$webmail_urlparm"|);
         } else {
            $temphtml .= iconlink("owm.gif", "$lang_text{'backto'} $folderstr",
                                  qq|accesskey="M" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession&amp;folder=$escapedfolder&amp;message_id=$escapedmessageid&amp;$webmail_urlparm"|);
         }
      }
      if ($config{'enable_calendar'}) {
         $temphtml .= iconlink("calendar.gif", $lang_text{'calendar'},
                               qq|accesskey="K" href="$config{'ow_cgiurl'}/openwebmail-cal.pl?action=$prefs{'calendar_defaultview'}&amp;sessionid=$thissession&amp;$webmail_urlparm"|);
      }
      if ($config{'enable_webdisk'}) {
         $temphtml .= iconlink("webdisk.gif", $lang_text{'webdisk'},
                               qq|accesskey="E" href="$config{'ow_cgiurl'}/openwebmail-webdisk.pl?action=showdir&amp;sessionid=$thissession&amp;$webmail_urlparm"|);
      }
      if ( $config{'enable_sshterm'}) {
         if ( -r "$config{'ow_htmldir'}/applet/mindterm2/mindterm.jar" ) {
            $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ",
                                  qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm2/ssh2.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
         } elsif ( -r "$config{'ow_htmldir'}/applet/mindterm/mindtermfull.jar" ) {
            $temphtml .= iconlink("sshterm.gif" ,"$lang_text{'sshterm'} ",
                                  qq|accesskey="T" href="#" onClick="window.open('$config{ow_htmlurl}/applet/mindterm/ssh.html', '_applet', 'width=400,height=100,top=2000,left=2000,resizable=no,menubar=no,scrollbars=no');"|);
         }
      }
      if ( $config{'enable_preference'}) {
         $temphtml .= iconlink("prefs.gif", $lang_text{'userprefs'},
                               qq|accesskey="O" href="$config{'ow_cgiurl'}/openwebmail-prefs.pl?action=editprefs&amp;$urlparm&amp;prefs_caller=addrlistview"|);
      }
      $temphtml .= iconlink("logout.gif", "$lang_text{'logout'} $prefs{'email'}",
                            qq|accesskey="X" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=logout&amp;sessionid=$thissession"|);

   } elsif ($listviewmode eq 'export') {
      my $abookfolderstr=ow::htmltext::str2html($lang_abookselectionlabels{$abookfolder}||f2u($abookfolder));
      $temphtml .= iconlink("backtofolder.gif", "$lang_text{'backto'} $abookfolderstr",
                               qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;$urlparm"|);
   }
   # in any defined listviewmode the temphtml here will be the addressbook dropdown form
   $html =~ s/\@\@\@MENUBARLINKSLEFT\@\@\@/$temphtml/g;


   # right side navigation and action buttons
   $temphtml='';
   if ($listviewmode eq '') {
      if (!$limited) {
         $temphtml .= iconlink("compose.gif", $lang_text{'composenew'},
                               qq|accesskey="C" href="javascript:addToForm('composeForm','contactsForm','to','cc','bcc'); document.composeForm.submit();"|);
         $temphtml .= "&nbsp;&nbsp;";
         $temphtml .= iconlink("abookviewselected.gif", $lang_text{'abook_listview_viewselected'},
                               qq|accesskey="Q" href="#" onClick="javascript:window.open('$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrshowchecked&amp;sessionid=$thissession&amp;listviewmode=grabopenerdata','_checkedlist','width=550,height=500,resizable=yes,scrollbars=yes');"|);
         $temphtml .= iconlink("abookunselectall.gif", $lang_text{'abook_listview_unselectall'},
                               qq|accesskey="P" href="javascript:clearAll('contactsForm','to','cc','bcc','checkedto','checkedcc','checkedbcc'); document.contactsForm.submit();"|);
      }
   } else {	# export or composeselect
      $temphtml .= iconlink("abookviewselected.gif", $lang_text{'abook_listview_viewselected'},
                           qq|accesskey="Q" href="#" onClick="javascript:window.open('$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrshowchecked&amp;sessionid=$thissession&amp;listviewmode=grabopenerdata&amp;aftergrabmode=$listviewmode','_checkedlist','width=550,height=500,resizable=yes,scrollbars=yes');"|);
      $temphtml .= iconlink("abookunselectall.gif", $lang_text{'abook_listview_unselectall'},
                            qq|accesskey="P" href="javascript:clearAll('contactsForm','to','cc','bcc','checkedto','checkedcc','checkedbcc'); document.contactsForm.submit();"|);
   }
   $html =~ s/\@\@\@MENUBARLINKSRIGHT\@\@\@/$temphtml/g;


   # page selection arrows
   if ($abookpage > 1) {
      $temphtml = iconlink(($ow::lang::RTL{$prefs{'locale'}}?"right.gif":"left.gif"), "&lt;",
                           qq|accesskey="B" href="javascript:document.contactsForm.abookpage.value=|.($abookpage-1).qq|; document.contactsForm.submit();"|
                          );
   } else {
      $temphtml = iconlink(($ow::lang::RTL{$prefs{'locale'}}?"right-grey.gif":"left-grey.gif"), "-", "");
   }
   $temphtml.=qq|$abookpage/$totalpage|;
   if ($abookpage < $totalpage) {
      $temphtml .= iconlink(($ow::lang::RTL{$prefs{'locale'}}?"left.gif":"right.gif"), "&gt;",
                            qq|accesskey="F" href="javascript:document.contactsForm.abookpage.value=|.($abookpage+1).qq|; document.contactsForm.submit();"|
                           );
   } else {
      $temphtml .= iconlink(($ow::lang::RTL{$prefs{'locale'}}?"left-grey.gif":"right-grey.gif"), "-", "");
   }
   $html =~ s/\@\@\@PAGECONTROL\@\@\@/$temphtml/g;


   # move/copy/delete menu
   my @destabookfolders=();
   my $is_src_editable=0;
   if ($abookfolder eq 'ALL') {
      @destabookfolders=@writableabookfolders;
      $is_src_editable=1 if ($#writableabookfolders>=0);
   } else {
      foreach (@writableabookfolders) {
         if ($_ eq $abookfolder) {
            $is_src_editable=1; next;
         } else {
            push(@destabookfolders, $_);
         }
      }
   }

   my (@mvcpvalues, %mvcplabels);
   foreach my $abook (@destabookfolders) {
      my ($value, $label)=(ow::tool::escapeURL($abook), $abook);
      $label=(defined $lang_abookselectionlabels{$abook})?$lang_abookselectionlabels{$abook}:f2u($abook);
      $label.=" *" if (is_abookfolder_global($abook));
      push(@mvcpvalues, $value); $mvcplabels{$value}=$label if ($label ne $value);
   }
   $mvcplabels{'DELETE'}=$lang_folders{'DELETE'};

   $temphtml = '';
   if ($listviewmode eq '' &&				# not in export or compose popup
       ($is_src_editable || $#destabookfolders>=0) ) {	# either src or dst is writable, then cp/mv make sence
      $temphtml = start_form(-name=>"moveCopyForm",
                             -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                  ow::tool::hiddens(action=>'addrmovecopydelete',
                                    # remembering which ones we're deleting
                                    checkedto=>ow::htmltext::str2html($checkedto),
                                    checkedcc=>ow::htmltext::str2html($checkedcc),
                                    checkedbcc=>ow::htmltext::str2html($checkedbcc),
                                    # javascript will populate these before submit
                                    # from values in the contactsForm
                                    to=>'',
                                    cc=>'',
                                    bcc=>'',
                                    ). $formparm;
      if ($is_src_editable) {
         $temphtml .=popup_menu(-name=>'destinationabook',
                                -default=>ow::tool::escapeURL($writableabookfolders[0]),
                                -override=>1,
                                -values=>[@mvcpvalues, 'DELETE'],
                                -labels=>\%mvcplabels,
                               );
         $temphtml .=submit(-name=>'addrmoveaddresses',
                            -value=>$lang_text{'abook_listview_move'},
                            -onClick=>"javascript:addToForm('moveCopyForm','contactsForm','to','cc','bcc'); document.moveCopyForm.submit();",
                            -class=>"medtext");
      } else {
         $temphtml .=popup_menu(-name=>'destinationabook',
                                -default=>ow::tool::escapeURL($writableabookfolders[0]),
                                -override=>1,
                                -values=>\@mvcpvalues,
                                -labels=>\%mvcplabels,
                               );
      }
      if ($#destabookfolders>=0) {	# dest is writable
         $temphtml .=submit(-name=>'addrcopyaddresses',
                            -value=>$lang_text{'abook_listview_copy'},
                            -onClick=>"javascript:addToForm('moveCopyForm','contactsForm','to','cc','bcc'); document.moveCopyForm.submit();",
                            -class=>"medtext");
      }
      $temphtml .=endform();

      $html =~ s/\@\@\@MOVECOPYFORM\@\@\@/$temphtml/g;
      $html =~ s/\@\@\@MOVECOPYFORMWIDTH\@\@\@/width="33%"/g;
   } else {
      $html =~ s/\@\@\@MOVECOPYFORM\@\@\@//g;
      $html =~ s/\@\@\@MOVECOPYFORMWIDTH\@\@\@//g;
   }

   # search form
   my %searchtypelabels = ();
   for (@headings) { $searchtypelabels{$_} = $lang_text{"abook_listview_$_"} };
   $searchtypelabels{'categories'} = $lang_text{"abook_listview_categories"};

   $temphtml = qq|<table cellspacing="0" cellpadding="0" border="0">|.
               start_form(-name=>"searchForm",
                          -action=>"javascript:document.forms['contactsForm'].elements['abooksearchtype'].value=document.forms['searchForm'].elements['abooksearchtype'].options[document.forms['searchForm'].elements['abooksearchtype'].selectedIndex].value; document.forms['contactsForm'].elements['abookkeyword'].value=document.forms['searchForm'].elements['abookkeyword'].value; document.contactsForm.submit();").
               qq|<tr><td>|.
               popup_menu(-name=>'abooksearchtype',
                          -default=>$abooksearchtype || $headings[0],
                          -values=>[@headings, 'categories'],
                          -labels=>\%searchtypelabels).
               qq|</td><td>|.
               textfield(-name=>'abookkeyword',
                         -default=>$abookkeyword,
                         -size=>'15',
                         -accesskey=>'S',
                         -override=>'1').
               qq|</td><td>|.
               submit(-name=>$lang_text{'search'},
                      -class=>'medtext',
                      -onClick=>"javascript:document.forms['contactsForm'].elements['abooksearchtype'].value=document.forms['searchForm'].elements['abooksearchtype'].options[document.forms['searchForm'].elements['abooksearchtype'].selectedIndex].value; document.forms['contactsForm'].elements['abookkeyword'].value=document.forms['searchForm'].elements['abookkeyword'].value; document.contactsForm.submit(); return false").
               qq|</td></tr>|.
               end_form().
               qq|</table>\n|;
   $html =~ s/\@\@\@SEARCHBARFORM\@\@\@/$temphtml/g;


   # the page selection dropdown
   my @pagevalues;
   for (my $p=1; $p<=$totalpage; $p++) {
      my $pdiff=abs($p-$page);
      if ( $pdiff<10 || $p==1 || $p==$totalpage || ($pdiff<100 && $p%10==0) || ($pdiff<1000 && $p%100==0) || $p%1000==0) {
         push(@pagevalues, $p);
      }
   }

   $temphtml = start_form(-name=>"abookPageForm",
                          -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
               qq|$lang_text{'page'}&nbsp;|.
               popup_menu(-name=>'abookpage',
                          -values=>\@pagevalues,
                          -default=>$abookpage,
                          -onChange=>"javascript:document.forms['contactsForm'].elements['abookpage'].value=document.forms['abookPageForm'].elements['abookpage'].options[document.forms['abookPageForm'].elements['abookpage'].selectedIndex].value; document.forms['contactsForm'].submit();",
                          -override=>'1');
   if ($abooklongpage) {
      my $str=$lang_text{'abook_listview_addrperpage'}; $str=~s/\@\@\@ADDRCOUNT\@\@\@/$prefs{'abook_addrperpage'}/;
      $temphtml.=qq|<a href="javascript:document.forms['contactsForm'].elements['abooklongpage'].value=0; document.forms['contactsForm'].submit();" title="$str">&nbsp;-&nbsp;</a>|;
   } else {
      my $str=$lang_text{'abook_listview_addrperpage'}; $str=~s/\@\@\@ADDRCOUNT\@\@\@/1000/;
      $temphtml.=qq|<a href="javascript:document.forms['contactsForm'].elements['abooklongpage'].value=1; document.forms['contactsForm'].submit();" title="$str">&nbsp;+&nbsp;</a>|;
   }
   $temphtml.= end_form();
   $html =~ s/\@\@\@PAGESELECTIONFORM\@\@\@/$temphtml/g;


   # expand/collapse all
   $temphtml = qq|&nbsp;|.
               iconlink(($abookcollapse?"left.gif":"down.gif"), ($abookcollapse?$lang_text{'abook_listview_expandall'}:$lang_text{'abook_listview_collapseall'}),
                        qq|accesskey="Z" href="javascript:document.contactsForm.abookcollapse.value=|.($abookcollapse?0:1).qq|; document.contactsForm.submit();"|
                       ).
               qq|&nbsp;|;
   $html =~ s/\@\@\@EXPANDCOLLAPSE\@\@\@/$temphtml/g;



   # the quick-add toolbar
   if ($listviewmode eq '') {
      if ( is_abookfolder_writable($abookfolder) ) {
         my %addaddressmap = (
                              'first' => 'N.0.VALUE.GIVENNAME',
                              'last' => 'N.0.VALUE.FAMILYNAME',
                              'phone' => 'TEL.0.VALUE',
                              'email' => 'EMAIL.0.VALUE',
                             );

         my %accesskeymap = (
                             'fullname' => 'N',
                             'first'    => 'F',
                             'last'     => 'L',
                             'middle'   => 'M',
                             'suffix'   => 'U',
                             'prefix'   => 'P',
                             'email'    => 'E',
                             'phone'    => 'T',
                            );

         $temphtml = qq|<tr><td colspan="$tabletotalspan">&nbsp;</td></tr>\n|.
                     qq|<tr>\n|.
                     qq|<td colspan="$tabletotalspan" bgcolor=$style{"tablerow_dark"}>\n|.
                     qq|<table cellpadding="0" cellspacing="4" border="0" align="center">\n|.
                     start_form(-name=>'quickAddForm',
                                -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                     ow::tool::hiddens(action=>'addredit',
                                       sessionid=>$thissession,
                                       abookfolder=>ow::tool::escapeURL($abookfolder),
                                       abookcollapse=>$abookcollapse,
                                       sort=>$sort,
                                       msgdatetype=>$msgdatetype,
                                       page=>$page,
                                       folder=>$escapedfolder,
                                       message_id=>$messageid,
                                       'X-OWM-CHARSET.0.VALUE'=>$prefs{'charset'}).
                     #qq|<tr><td class="smalltext">&nbsp;</td></tr>\n|.
                     qq|<tr>\n|;

         foreach my $field (qw(first last phone email)) {
            $temphtml .= qq|<td><b>$lang_text{"abook_listview_$field"}</b></td>\n|;
         }

         $temphtml .= qq|<td rowspan="2" align="center" valign="center">&nbsp;&nbsp;|.
                      submit(-name=>$lang_text{'abook_listview_quickadd'},
                             -accesskey=>'A',
                             -class=>"medtext",
                             -onClick=>"if (document.quickAddForm.elements['$addaddressmap{first}'].value=='' && document.quickAddForm.elements['$addaddressmap{last}'].value=='') {return false; } else {return true;}"
                             ).
                      qq|&nbsp;&nbsp;</td>\n|.
                      qq|</tr>\n|.
                      qq|<tr>\n|;

         foreach my $field (qw(first last phone email)) {
            $temphtml .= qq|<td>|.
                         textfield(-name=>$addaddressmap{$field},
                                   -default=>'',
                                   -class=>'mono',
                                   -size=>'20',
                                   -accesskey=>$accesskeymap{$field},
                                   -override=>'1').
                         qq|&nbsp;&nbsp;</td>\n|;
         }

         $temphtml .= qq|</tr>\n|.
                      end_form().
                      qq|</table></td></tr>\n|.
                      qq|<tr><td colspan="$tabletotalspan">&nbsp;</td></tr>\n|;
      } else {
         $temphtml = qq|<tr><td colspan="$tabletotalspan">&nbsp;</td></tr>\n|;
      }
   } else {
      $temphtml = qq|<tr><td colspan="$tabletotalspan">&nbsp;</td></tr>\n|;
   }
   $html =~ s/\@\@\@QUICKADDFORM\@\@\@/$temphtml/g;


   if ($listviewmode eq '') {
      if (!$limited) {
         $temphtml = start_form(-name=>'composeForm',
                                -action=>"$config{'ow_cgiurl'}/openwebmail-send.pl").
                     ow::tool::hiddens(action=>'composemessage',
                                       sessionid=>$thissession,
                                       checkedto=>ow::htmltext::str2html($checkedto),
                                       checkedcc=>ow::htmltext::str2html($checkedcc),
                                       checkedbcc=>ow::htmltext::str2html($checkedbcc),
                                       compose_caller=>'addrlistview',
                                       listviewmode=>$listviewmode,
                                       # javascript will populate these before submit
                                       # from values in the contactsForm
                                       to=>'',
                                       cc=>'',
                                       bcc=>'',
                                      ). $abook_formparm_with_abookfolder.
                     end_form();
      }
   } elsif ($listviewmode eq 'export') {
      $temphtml = start_form(-name=>'exportForm',
                             -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                  ow::tool::hiddens(action=>'addrexport',
                                    sessionid=>$thissession,
                                    checkedto=>ow::htmltext::str2html($checkedto),
                                    checkedcc=>ow::htmltext::str2html($checkedcc),
                                    checkedbcc=>ow::htmltext::str2html($checkedbcc),
                                    exportformat=>'',
                                    exportcharset=>'',
                                    # javascript will populate these before submit
                                    # from values in the contactsForm
                                    to=>'',
                                    cc=>'',
                                    bcc=>'',
                                   ).
                  end_form();
   } elsif ($listviewmode eq 'composeselect') {
      $temphtml = start_form(-name=>'composeselectForm',
                             -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                  ow::tool::hiddens(
                                    checkedto=>ow::htmltext::str2html($checkedto),
                                    checkedcc=>ow::htmltext::str2html($checkedcc),
                                    checkedbcc=>ow::htmltext::str2html($checkedbcc),
                                   ).
                  endform();
   }

   # start the overall contacts area form (to capture to,cc,bcc input checkboxes)
   $temphtml .= start_form(-name=>'contactsForm',
                           -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
                ow::tool::hiddens(action=>'addrlistview',
                                  checkedto=>ow::htmltext::str2html($checkedto),
                                  checkedcc=>ow::htmltext::str2html($checkedcc),
                                  checkedbcc=>ow::htmltext::str2html($checkedbcc),
                                  listviewmode=>$listviewmode,
                                  $editgroupform?('editgroupform'=>1):()
                                 ). $formparm;

   # the column headings
   if ($listviewmode eq 'export' || $editgroupform) {
      push(@headings, 'to'); # only one checkbox for exporting or editgroup
   } else {
      push(@headings, qw(to cc bcc));
   }
   $temphtml .= qq|<tr height="20">\n|;
   $temphtml .= qq|<td bgcolor=$style{'columnheader'}>&nbsp;</td>|; # the number cell
   for (@headings) {
      if (m/^(?:to|cc|bcc)$/) {
         if ($listviewmode eq 'export') {
            $temphtml .= qq|<td bgcolor=$style{'columnheader'} align="center"><a href="javascript:CheckAll(this,'contactsForm','|.$_.qq|');"><b>$lang_text{'export'}</b></a></td>\n|;
         } elsif ($editgroupform) {
            $temphtml .= qq|<td bgcolor=$style{'columnheader'} align="center"><a href="javascript:CheckAll(this,'contactsForm','|.$_.qq|');"><b>$lang_text{'abook_group_member'}</b></a></td>\n|;
         } else {
            $temphtml .= qq|<td bgcolor=$style{'columnheader'} align="center"><a href="javascript:CheckAll(this,'contactsForm','|.$_.qq|');"><b>$lang_text{$_}</b></a></td>\n|;
         }
      } else {
         if (m/$abooksort_short/) { # this heading is the sort column
            if ($abooksort =~ m/_rev$/) {
               $temphtml .= qq|<td bgcolor=$style{'columnheader'}><a href="javascript:document.contactsForm.abooksort.value='$_'; document.contactsForm.submit();"><b>$lang_text{"abook_listview_$_"}&nbsp;|.
                            iconlink("down.gif", "v", "").
                            qq|</b></a></td>\n|;
            } else {
               $temphtml .= qq|<td bgcolor=$style{'columnheader'}><a href="javascript:document.contactsForm.abooksort.value='$_\_rev'; document.contactsForm.submit();"><b>$lang_text{"abook_listview_$_"}&nbsp;|.
                            iconlink("up.gif", "^", "").
                            qq|</b></a></td>\n|;
            }
         } else {
               $temphtml .= qq|<td bgcolor=$style{'columnheader'}><a href="javascript:document.contactsForm.abooksort.value='$_'; document.contactsForm.submit();"><b>$lang_text{"abook_listview_$_"}</b></a></td>\n|;
         }
      }
   }

   $temphtml .= qq|</tr>\n|;
   $html =~ s/\@\@\@COLUMNHEADINGS\@\@\@/$temphtml/g;



   # write out the html of the addresses
   $temphtml = '';
   foreach my $addrindex ($firstaddr..$lastaddr) {
      my $xowmuid = $sorted_addresses[$addrindex];
      my $addrbook=$addresses{$xowmuid}{'X-OWM-BOOK'}[0]{VALUE};
      my $escapedaddrbook = ow::tool::escapeURL($addrbook);

      my $editurl = qq|$config{'ow_cgiurl'}/openwebmail-abook.pl?action=|.
                    (exists($addresses{$xowmuid}{'X-OWM-GROUP'})?'addreditform&amp;editgroupform=1':'addreditform').qq|&amp;|.
                    qq|sessionid=$thissession&amp;|.
                    qq|rootxowmuid=$xowmuid&amp;|.
                    qq|abookfolder=$escapedaddrbook&amp;|.
                    qq|editformcaller=$escapedabookfolder&amp;|.
                    qq|$webmail_urlparm&amp;|.
                    $abook_urlparm;
      my $composeurl = qq|$config{'ow_cgiurl'}/openwebmail-send.pl?action=composemessage&amp;|.
                       qq|composetype=sendto&amp;|.
                       qq|compose_caller=addrlistview&amp;|.
                       $urlparm;

      my $hreftitle='';
      if ($abookfolder eq 'ALL') {
         my $addrbookstr=ow::htmltext::str2html(f2u($addrbook));
         if (is_abookfolder_global($addrbook)) {
            $hreftitle=qq|title="$lang_text{'abook_global'}:$addrbookstr"|;
         } else {
            $hreftitle=qq|title="$lang_text{'abook_personal'}:$addrbookstr"|;
         }
      }


      # how many rows for this $xowmuid
      my $rows = (# build a list of how many entries this xowmuid has for each heading, sort largest to the top
                  sort { $b <=> $a }
                   map { exists($addresses{$xowmuid}{$vcardmapping{$_}})?$#{$addresses{$xowmuid}{$vcardmapping{$_}}}:0 }
                  grep { !m/^(to|cc|bcc)$/ } @headings
                 )[0]; # but only return the largest one

      if ($rows >= 0) {
         for(my $index=0; $index <= $rows; $index++) {
            next if ($index > 0 && $abookcollapse == 1);

            my ($id, $tr_bgcolorstr, $td_bgcolorstr, $onclickstr);
            my $id=$addrindex.'_'.$index;
            if ($prefs{'uselightbar'}) {
               $tr_bgcolorstr=qq|bgcolor=$style{tablerow_light} |;
               $tr_bgcolorstr.=qq|onMouseOver='this.style.backgroundColor=$style{tablerow_hicolor};' |.
                               qq|onMouseOut='this.style.backgroundColor =$style{tablerow_light};' |.
                               qq|id="tr_$id" |;
               $td_bgcolorstr='';
            } else {
               $tr_bgcolorstr='';
               $td_bgcolorstr=qq|bgcolor=|.($style{"tablerow_light"},$style{"tablerow_dark"})[$addrindex%2];
            }
            $onclickstr=qq|onClick='setchkbox("$id")'|;

            my @newrow = ();
            $newrow[$tabletotalspan-1] = undef; # set the length of the newrow

            # the number cell
            if ($index == 0) {
               $newrow[0] .= qq|<td $td_bgcolorstr $onclickstr nowrap><b>|.($addrindex+1);
               if ($listviewmode eq '') {
                  $newrow[0] .= qq|&nbsp;|;
                  if (is_abookfolder_global($addrbook)) {
                     $newrow[0] .= qq|&nbsp;<img src="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/abookglobalicon.gif" border="0" title="$lang_text{'abook_global'}">|;
                  }
               }
               $newrow[0] .= qq|&nbsp;&nbsp;&nbsp;</b></td>\n|;
            }

            # the name stuff
            if (exists $addresses{$xowmuid}{N}) {
               if (defined $addresses{$xowmuid}{N}[$index]) {
                  foreach my $heading (grep(!m/^(to|cc|bcc)$/, @headings)) {
                     if (exists $addresses{$xowmuid}{N}[$index]{VALUE}{$Nmap{$heading}}) {
                        # do iconv on name prefix, first, middle, last, suffix
                        my ($s)=iconv($addresses{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}, $prefs{charset}, $addresses{$xowmuid}{N}[$index]{VALUE}{$Nmap{$heading}});
                        if ($listviewmode eq '') {
                           $newrow[$headingpos{$heading}] .= qq|<td $td_bgcolorstr $onclickstr><a href="$editurl" $hreftitle>|.ow::htmltext::str2html($s).qq|</a></td>\n|;
                        } else {
                           $newrow[$headingpos{$heading}] .= qq|<td $td_bgcolorstr $onclickstr>|.ow::htmltext::str2html($s).qq|</td>\n|;
                        }
                     }
                  }
               }
            }

            # the fullname stuff
            if (exists $addresses{$xowmuid}{FN}) {
               if (defined $addresses{$xowmuid}{FN}[$index]) {
                  my ($s)=iconv($addresses{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}, $prefs{charset}, $addresses{$xowmuid}{FN}[$index]{VALUE});
                  if ($listviewmode eq '') {
                     $newrow[$headingpos{'fullname'}] .= qq|<td $td_bgcolorstr $onclickstr><a href="$editurl" $hreftitle>|.ow::htmltext::str2html($s).qq|</a></td>\n|;
                  } else {
                     $newrow[$headingpos{'fullname'}] .= qq|<td $td_bgcolorstr $onclickstr>|.ow::htmltext::str2html($s).qq|</td>\n|;
                  }
               }
            }

            # the email stuff
            my ($allemails, $escapedallemails, $email, $escapedemail) = ();
            my $disabled = 'disabled="1"';
            if (exists $addresses{$xowmuid}{EMAIL}) {
               if (defined $addresses{$xowmuid}{EMAIL}[$index]) {
                  $disabled = '';
                  if (exists($addresses{$xowmuid}{'X-OWM-GROUP'}) && $index == 0) {
                     # if we're in editgroupform mode we want the addresses delimited by '\n',
                     # instead of the normal ', '.
                     $allemails = join (($editgroupform?"\n":", "), grep { !m/^$lang_text{'abook_group_allmembers'}$/ }
                                               map { $_->{'VALUE'} }
                                              sort { lc($a->{'VALUE'}) cmp lc($b->{'VALUE'}) } @{$addresses{$xowmuid}{EMAIL}}
                                       );

                     $escapedallemails = ow::tool::escapeURL($allemails);
                     if ($listviewmode eq '') {
                        $newrow[$headingpos{'email'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap>|.
                                                         iconlink("group.gif", "$lang_text{'abook_group_allmembers'}", qq|accesskey="G" href="$composeurl&amp;to=$escapedallemails"|).
                                                         qq|&nbsp;<a href="$composeurl&amp;to=$escapedallemails">|.ow::htmltext::str2html($addresses{$xowmuid}{EMAIL}[$index]{VALUE}).qq|</a>|.
                                                         qq|</td>\n|;
                     } elsif ($listviewmode eq 'composeselect') {
                        $newrow[$headingpos{'email'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap><a href="javascript:document.closeform.okbutton.click();"><img src="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/group.gif" border="0" align="absmiddle">&nbsp;|.ow::htmltext::str2html($addresses{$xowmuid}{EMAIL}[$index]{VALUE}).qq|</a></td>\n|;
                     } else {
                        $newrow[$headingpos{'email'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap><img src="$config{'ow_htmlurl'}/images/iconsets/$prefs{'iconset'}/group.gif" border="0" align="absmiddle">&nbsp;|.ow::htmltext::str2html($addresses{$xowmuid}{EMAIL}[$index]{VALUE}).qq|</td>\n|;
                     }
                  } else {
                     if (!exists($addresses{$xowmuid}{'X-OWM-GROUP'}) && exists $addresses{$xowmuid}{FN}) {
                        $email = qq|"$addresses{$xowmuid}{FN}[0]{VALUE}" <$addresses{$xowmuid}{EMAIL}[$index]{VALUE}>|;
                     } elsif (!exists($addresses{$xowmuid}{'X-OWM-GROUP'}) && exists $addresses{$xowmuid}{N}) {
                        $email = join (" ", map { exists $addresses{$xowmuid}{N}[0]{VALUE}{$_}?
                                                  defined $addresses{$xowmuid}{N}[0]{VALUE}{$_}?$addresses{$xowmuid}{N}[0]{VALUE}{$_}:''
                                                  :''
                                                } qw(NAMEPREFIX GIVENNAME ADDITIONALNAMES FAMILYNAME NAMESUFFIX)
                                      );
                        $email =~ s/^\s+(\S)/$1/;
                        $email =~ s/(\S)\s+$/$1/;
                        $email = qq|"$email" <$addresses{$xowmuid}{EMAIL}[$index]{VALUE}>|;
                     } else {
                        $email = "$addresses{$xowmuid}{EMAIL}[$index]{VALUE}";
                     }
                     # do iconv on the "name" part of the "name" <user@hostname>
                     ($email)=iconv($addresses{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}, $prefs{charset}, $email);
                     $escapedemail = ow::tool::escapeURL($email);
                     if ($listviewmode eq '') {
                        $newrow[$headingpos{'email'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap><a href="$composeurl&amp;to=$escapedemail" title="$lang_text{'abook_listview_writemailto'}|.ow::htmltext::str2html($email).qq|">|.ow::htmltext::str2html($addresses{$xowmuid}{EMAIL}[$index]{VALUE}).qq|</a></td>\n|;
                     } elsif ($listviewmode eq 'composeselect') {
                        $newrow[$headingpos{'email'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap><a href="javascript:document.closeform.okbutton.click();">|.ow::htmltext::str2html($addresses{$xowmuid}{EMAIL}[$index]{VALUE}).qq|</a></td>\n|;
                     } else {
                        $newrow[$headingpos{'email'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap>|.ow::htmltext::str2html($addresses{$xowmuid}{EMAIL}[$index]{VALUE}).qq|</td>\n|;
                     }
                  }
               }
            }

            # the telephone stuff
            if (exists $addresses{$xowmuid}{TEL}) {
               if (defined $addresses{$xowmuid}{TEL}[$index]) {
                  my $typestag = join(', ', map { defined($lang_text{"abook_listview_tel$_->[1]"})?$lang_text{"abook_listview_tel$_->[1]"}:undef }
                                           sort { $a->[0] <=> $b->[0] }
                                            map { [(defined($TELsort{$_})?$TELsort{$_}:100), lc($_)] }
                                           grep { !m/VOICE/ } keys %{$addresses{$xowmuid}{TEL}[$index]{TYPES}}
                                     );
                  my $s=$addresses{$xowmuid}{TEL}[$index]{VALUE};
                  ($s)=iconv($addresses{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}, $prefs{charset}, $s) if ($s=~/[^\d\-\+]/);
                  if ($listviewmode eq '') {
                     $newrow[$headingpos{'phone'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap><a href="$editurl">|.ow::htmltext::str2html("$s $typestag").qq|</a></td>\n|;
                  } else {
                     $newrow[$headingpos{'phone'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap>|.ow::htmltext::str2html("$s $typestag").qq|</td>\n|;
                  }
               }
            }

            # the note stuff
            if (exists $addresses{$xowmuid}{NOTE}) {
               if (defined $addresses{$xowmuid}{NOTE}[$index]) {
                  my ($displaynote)=iconv($addresses{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE}, $prefs{charset}, $addresses{$xowmuid}{NOTE}[$index]{VALUE});
                  my $shortnote = $displaynote;

                  $shortnote = substr($shortnote,0,20) . "...";
                  $shortnote =~ s/</&lt;/g;
                  $shortnote =~ s/>/&gt;/g;
                  $shortnote =~ s/\n/ /g;

                  $displaynote =~ s/\n/<br>/g;
                  $displaynote =~ s!(https?|ftp|mms|nntp|news|gopher|telnet)://([\w\d\-\.]+?/?[^\s\(\)\<\>\x80-\xFF]*[\w/])([\b|\n| ]*)!<a href="$1://$2" target="_blank"+>$1://$2</a>$3!gs;
                  $displaynote =~ s!([\b|\n| ]+)(www\.[\w\d\-\.]+\.[\w\d\-]{2,4})([\b|\n| ]*)!$1<a href="http://$2" target="_blank">$2</a>$3!igs;
                  $displaynote =~ s!([\b|\n| ]+)(ftp\.[\w\d\-\.]+\.[\w\d\-]{2,4})([\b|\n| ]*)!$1<a href="ftp://$2" target="_blank">$2</a>$3!igs;

                  # escape chars for javascript
                  $displaynote =~ s!\\!\\\\!g;	# \ -> \\
                  $displaynote =~ s!'!\\'!g;	# ' -> \'
                  $displaynote =~ s!"!&quot;!g; # " -> &quot;
                  $displaynote =~ s!\)!\\\)!g;  # ) -> \)
                  $displaynote =~ s!\(!\\\(!g;  # ( -> \(

                  my $noteoffset = ($headingpos{'note'} > int(((@headings-3)/2)+1) ? -350 : 150);
                  $newrow[$headingpos{'note'}] .= qq|<td $td_bgcolorstr $onclickstr nowrap><a href="javascript:{;}" onClick="displayNote(this,'notepopup',$noteoffset,-25,'|.
                                                  $displaynote.
                                                  qq|');">|.ow::htmltext::str2html($shortnote).qq|</a></td>\n|;
               }
            }

            # the to,cc,bcc,export
            if ($listviewmode eq 'export') {
               # keep track of xowmuids, not email addresses
               $email = $allemails = $xowmuid;
               $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="to" id="$id" value="|.ow::htmltext::str2html($email).qq|" |.(exists $ischecked{TO}{$email}?'checked':'').qq|></td>\n|;
            } elsif ($editgroupform) {	# edit group
               my $xowmuidtrack = '';
               if (exists $addresses{$xowmuid}{'X-OWM-GROUP'}) {
                  #my $escapedxowmgroup = ow::htmltext::str2html($addresses{$xowmuid}{'X-OWM-GROUP'}[0]{'VALUE'});
                  my $escapedxowmgroup = ow::htmltext::str2html($xowmuid);	# xowmgroup is always 1, we use owmid instead, tung
                  if ($index == 0) { # the first line of a group
                     if ($abookcollapse == 1) {
                        $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="to" id="$id" value="|.ow::htmltext::str2html("$allemails$xowmuidtrack").qq|" $disabled|.is_groupbox_checked('TO',\%ischecked,\$allemails,$xowmuidtrack).qq|></td>\n|;
                     } else {
                        $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" onClick=CheckAll(this,'contactsForm','to','$escapedxowmgroup'); name="to" id="$id" value="" $disabled|.is_groupbox_checked('TO',\%ischecked,\$allemails,$xowmuidtrack).qq|></td>\n|;
                     }
                  } elsif ($index > 0) { # not the first line of a group
                     $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="to" id="$id" value="|.ow::htmltext::str2html("$email$xowmuidtrack").qq|" $disabled|.(exists $ischecked{TO}{"$email$xowmuidtrack"}?'checked':'').qq|><input type="hidden" name="$escapedxowmgroup" value="1"></td>\n|;
                  }
               } else {
                  $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="to" id="$id" value="|.ow::htmltext::str2html("$email$xowmuidtrack").qq|" $disabled|.(exists $ischecked{TO}{"$email$xowmuidtrack"}?'checked':'').qq|></td>\n|;
               }
            } else {
               my $xowmuidtrack = ($listviewmode eq "composeselect"?'':"%@#$xowmuid"); # allows move/copy to work
               if (exists $addresses{$xowmuid}{'X-OWM-GROUP'}) {
                  #my $escapedxowmgroup = ow::htmltext::str2html($addresses{$xowmuid}{'X-OWM-GROUP'}[0]{'VALUE'});
                  my $escapedxowmgroup = ow::htmltext::str2html($xowmuid);	# xowmgroup is always 1, we use owmid instead, tung
                  if ($index == 0) { # the first line of a group
                     if ($abookcollapse == 1) {
                        $newrow[$tabletotalspan-3] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="to" id="$id" value="|.ow::htmltext::str2html("$allemails$xowmuidtrack").qq|" $disabled|.is_groupbox_checked('TO',\%ischecked,\$allemails,$xowmuidtrack).qq|></td>\n|;
                        $newrow[$tabletotalspan-2] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="cc" value="|.ow::htmltext::str2html("$allemails$xowmuidtrack").qq|" $disabled|.is_groupbox_checked('CC',\%ischecked,\$allemails,$xowmuidtrack).qq|></td>\n|;
                        $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="bcc" value="|.ow::htmltext::str2html("$allemails$xowmuidtrack").qq|" $disabled|.is_groupbox_checked('BCC',\%ischecked,\$allemails,$xowmuidtrack).qq|></td>\n|;
                     } else {
                        $newrow[$tabletotalspan-3] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" onClick=CheckAll(this,'contactsForm','to','$escapedxowmgroup'); name="to" id="$id" value="" $disabled|.is_groupbox_checked('TO',\%ischecked,\$allemails,$xowmuidtrack).qq|></td>\n|;
                        $newrow[$tabletotalspan-2] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" onClick=CheckAll(this,'contactsForm','cc','$escapedxowmgroup'); name="cc" value="" $disabled|.is_groupbox_checked('CC',\%ischecked,\$allemails,$xowmuidtrack).qq|></td>\n|;
                        $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" onClick=CheckAll(this,'contactsForm','bcc','$escapedxowmgroup'); name="bcc" value="" $disabled|.is_groupbox_checked('BCC',\%ischecked,\$allemails,$xowmuidtrack).qq|></td>\n|;
                     }
                  } elsif ($index > 0) { # not the first line of a group
                     $newrow[$tabletotalspan-3] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="to" id="$id" value="|.ow::htmltext::str2html("$email$xowmuidtrack").qq|" $disabled|.(exists $ischecked{TO}{"$email$xowmuidtrack"}?'checked':'').qq|><input type="hidden" name="$escapedxowmgroup" value="1"></td>\n|;
                     $newrow[$tabletotalspan-2] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="cc" value="|.ow::htmltext::str2html("$email$xowmuidtrack").qq|" $disabled|.(exists $ischecked{CC}{"$email$xowmuidtrack"}?'checked':'').qq|><input type="hidden" name="$escapedxowmgroup" value="1"></td>\n|;
                     $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="bcc" value="|.ow::htmltext::str2html("$email$xowmuidtrack").qq|" $disabled|.(exists $ischecked{BCC}{"$email$xowmuidtrack"}?'checked':'').qq|><input type="hidden" name="$escapedxowmgroup" value="1"></td>\n|;
                  }
               } else {
                  $newrow[$tabletotalspan-3] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="to" id="$id" value="|.ow::htmltext::str2html("$email$xowmuidtrack").qq|" $disabled|.(exists $ischecked{TO}{"$email$xowmuidtrack"}?'checked':'').qq|></td>\n|;
                  $newrow[$tabletotalspan-2] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="cc" value="|.ow::htmltext::str2html("$email$xowmuidtrack").qq|" $disabled|.(exists $ischecked{CC}{"$email$xowmuidtrack"}?'checked':'').qq|></td>\n|;
                  $newrow[$tabletotalspan-1] = qq|<td $td_bgcolorstr align="center"><input type="checkbox" name="bcc" value="|.ow::htmltext::str2html("$email$xowmuidtrack").qq|" $disabled|.(exists $ischecked{BCC}{"$email$xowmuidtrack"}?'checked':'').qq|></td>\n|;
               }
            }

            # add it on to the html
            $temphtml .= qq|<tr $tr_bgcolorstr>\n|;
            foreach my $slot (@newrow) {
               if (defined $slot) {
                  # the cell contents
                  $temphtml .= $slot;
               } else {
                  # a blank cell
                  $temphtml .= qq|<td $td_bgcolorstr $onclickstr>&nbsp;</td>\n|;
               }
            }
            $temphtml .= qq|</tr>\n|;
         }
      }
   }

   if ($lastaddr == -1) {
      $temphtml .= qq|<tr><td bgcolor=$style{"tablerow_light"} colspan="$tabletotalspan" align="center"><br><b>|;
      if ($abookkeyword eq '') {
         $temphtml .= $lang_text{'abook_listview_noaddresses'};
      } else {
         $temphtml .= $lang_text{'abook_listview_nomatch'};
      }
      $temphtml.=qq|</b><br>&nbsp;</td></tr>\n|;
   }

   $temphtml .= end_form(); # end the contactsForm
   $html =~ s/\@\@\@ADDRESSES\@\@\@/$temphtml/g;


   # add the buttons at the bottom if this is a listview mode
   $temphtml = '';
   if ($listviewmode eq 'composeselect') {
      my $jsfunction = '';
      if ($editgroupform) {
         $jsfunction = 'updateEditForm(\'composeselectForm\', \'contactsForm\');';
      } else {
         $jsfunction = 'updateComposeForm(\'composeselectForm\', \'contactsForm\');';
      }

      my $buttons = qq|<tr>|.
                    qq|<td colspan="$tabletotalspan" align="center" nowrap>|.
                    start_form(-name=>'closeform',
                               -action=>"#").
                    button(-name=>'okbutton',
                           -value=>$lang_text{'abook_listview_done'},
                           -accesskey=>'J',
                           -onClick=>$jsfunction,
                           -class=>"medtext").
                    "&nbsp;".
                    button(-name=>'cancelbutton',
                           -value=>$lang_text{'cancel'},
                           -accesskey=>'X',
                           -onClick=>'javascript:window.close();',
                           -class=>"medtext").
                    endform().
                    qq|</td>|.
                    qq|</tr>|;
      my $spacer = qq|<tr><td colspan="$tabletotalspan">&nbsp;</td></tr>|;
      if ($prefs{'abook_buttonposition'} eq 'before') {
         $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@/$buttons$spacer/g;
         $html =~ s/\@\@\@BUTTONSAFTER\@\@\@//g;
      } elsif ($prefs{'abook_buttonposition'} eq 'after') {
         $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@//g;
         $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$buttons/g;
      } else { # both
         $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@/$buttons$spacer/g;
         $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$buttons/g;
      }

   } elsif ($listviewmode eq 'export') {
      my %supportedlabels = ();
      my %supportedexportformat = %supportedimportexportformat;
      delete($supportedexportformat{'csv auto'});
      delete($supportedexportformat{'tab auto'});
      for (keys %supportedexportformat) { $supportedlabels{$_} = $supportedexportformat{$_}[2] };
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                             -name=>'exportformatForm');
      $temphtml .= popup_menu(-name=>'exportformat',
                             -values=>[sort keys %supportedexportformat],
                             -default=>'vcard3.0',
                             -labels=>\%supportedlabels,
                             -onChange=>"javascript:document.forms['exportForm'].elements['exportformat'].value=document.forms['exportformatForm'].elements['exportformat'].options[document.forms['exportformatForm'].elements['exportformat'].selectedIndex].value; exportOptionsToggle(document.forms['exportformatForm'].elements['exportformat'].options[document.forms['exportformatForm'].elements['exportformat'].selectedIndex].value, 'exportformatForm');",
                             -override=>1);
      $html =~ s/\@\@\@EXPORTMODEFORMFORMATSMENU\@\@\@/$temphtml/;

      my @charset = ($lang_text{'abook_noconversion'});
      push @charset, sort map { $ow::lang::charactersets{$_}[1] } keys %ow::lang::charactersets;
      my $defaultcharset = $prefs{'charset'};
      $temphtml = "$lang_text{'charset'}:";
      $temphtml .= popup_menu(-name=>'exportcharset',
                              -values=>\@charset,
                              -default=>$defaultcharset,
                              -onChange=>"javascript:document.forms['exportForm'].elements['exportcharset'].value=document.forms['exportformatForm'].elements['exportcharset'].options[document.forms['exportformatForm'].elements['exportcharset'].selectedIndex].value;",
                              -override=>1,
                              -disabled=>'1'); # javascript enabled when user chooses a .csv or .tab export format
      $temphtml .= end_form();
      $html =~ s/\@\@\@EXPORTCHARSETMENU\@\@\@/$temphtml/;

      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                             -name=>'exportnowForm');
      $temphtml .= button(-name=>$lang_text{'abook_exportnow'},
                          -accesskey=>'J',
                          -onClick=>"javascript:addToForm('exportForm','contactsForm','to','cc','bcc'); document.exportForm.submit();",
                          -class=>"medtext");
      $temphtml .= end_form();
      $html =~ s/\@\@\@EXPORTMODEFORMEXPORTNOW\@\@\@/$temphtml/;

      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                             -name=>'cancelExportForm').
                  ow::tool::hiddens(action=>'addrlistview'). $formparm;
      $temphtml .= submit(-name=>"$lang_text{'cancel'}",
                          -class=>"medtext");
      $temphtml .= endform();
      $html =~ s/\@\@\@EXPORTMODECANCELFORM\@\@\@/$temphtml/g;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@//g;
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@//g;

   } else {
      # compose button
      my $buttons = qq|<tr>|.
                    qq|<td colspan="$tabletotalspan" align="right">|.
                    start_form(-name=>"composeButtonForm", -action=>"#").
                    button(-name=>$lang_text{'abook_listview_compose'},
                           -accesskey=>'J',
                           -onClick=>'addToForm(\'composeForm\',\'contactsForm\',\'to\',\'cc\',\'bcc\'); document.composeForm.submit();',
                           -class=>"medtext").
                    endform().
                    qq|</td>|.
                    qq|</tr>|;
      $html =~ s/\@\@\@BUTTONSAFTER\@\@\@/$buttons/g;
      $html =~ s/\@\@\@BUTTONSBEFORE\@\@\@//g;
   }

   my $cookie = cookie( -name  => "ow-abookfolder-$domain-$user",
                        -value => $abookfolder,
                        -path  => '/');
   if ($listviewmode eq '') {
      httpprint([-cookie=>[$cookie]],
                [htmlheader(),
                 htmlplugin($config{'header_pluginfile'}, $config{'header_pluginfile_charset'}, $prefs{'charset'}),
                 $html,
                 htmlplugin($config{'footer_pluginfile'}, $config{'footer_pluginfile_charset'}, $prefs{'charset'}),
                 htmlfooter(2)] );
   } else {
      httpprint([-cookie=>[$cookie]], [htmlheader(), $html, htmlfooter(2)]);
   }
}
########## END ADDRLISTVIEW ######################################


########## ADDREDITFORM ##########################################
sub addreditform {
   print header() if $addrdebug;

   # first time called?
   if (param('action') eq 'addreditform') {
      deleteattachments(); # delete previous attachments
   }

   $abookfolder = ow::tool::untaint(safefoldername($abookfolder));

   # where are we coming from?
   my $editformcaller = safefoldername(ow::tool::unescapeURL(param('editformcaller'))) || $abookfolder;
   my $escapededitformcaller = ow::tool::escapeURL($editformcaller);

   # what do we want?
   my $xowmuid = param('rootxowmuid');
   my $abookfile = abookfolder2file($abookfolder);

   # possible destination for new entry
   my @writableabookfolders = get_writable_abookfolders();

   # These data structures control which class each propertyname belongs to (100 class,
   # 200 class, etc) and how the propertyname is processed.

   # CLASSES:
   # Each propertyname is assigned a class value number. The number controls
   # in which class the value appears and in what order it appears in that class.
   # The main template defines the overall order of all the classes. The number of
   # classes defined in the main template should match the number of classes defined
   # here. If you are assigning a 700 class number to a bunch of propertynames here, make
   # sure your main template contains a @@@700@@@ class area for those propertynames
   # to go. Always make sure you have one more class than you need in order to catch
   # all the custom propertynames in your main template (@@@800@@@).
   # -1's do not get added to $contact. It is assumed that the data is either meant to be
   # discarded, or that it is merged into another non-negative propertyname in order to
   # be processed and displayed there.

   # PROCESSING:
   # Named values are processed with the special htmloutput handler specified.
   # If you define a htmloutput handler for a propertyname, then you need to
   # also write the htmloutput function to do the work.
   # Undefined values are automatically processed using the GENERIC processor.

   my %htmloutput = ();
   if (!param('editgroupform')) {
      # We are editing a normal contact.
      %htmloutput = (
         # These propertynames are defined in the RFC and vCard specification
         'BEGIN'       => [-1],                          # vCard 2.1 (required) and 3.0 (required)
         'END'         => [-1],                          # vCard 2.1 (required) and 3.0 (required)
         'REV'         => [-1],                          # vCard 2.1 and 3.0
         'VERSION'     => [-1],                          # vCard 2.1 (required) and 3.0 (required)
         'PROFILE'     => [-1],                          # vCard 3.0
         'CATEGORIES'  => [-1],                          # vCard 3.0
         'PHOTO'       => [100,\&addreditform_PHOTO],    # vCard 2.1 and 3.0
         'N'           => [110,\&addreditform_N],        # vCard 2.1 (required) and 3.0 (required)
         'FN'          => [120],                         # vCard 2.1 and 3.0 (required)
         'SOUND'       => [130,\&addreditform_SOUND],    # vCard 2.1 and 3.0
         'NICKNAME'    => [140],                         # vCard 3.0
         'SORT-STRING' => [150],                         # vCard 3.0
         'BDAY'        => [160,\&addreditform_BDAY],     # vCard 2.1 and 3.0
         'EMAIL'       => [200,\&addreditform_EMAIL],    # vCard 2.1 and 3.0
         'TEL'         => [300,\&addreditform_TEL],      # vCard 2.1 and 3.0
         'ADR'         => [400,\&addreditform_ADR],      # vCard 2.1 and 3.0
         'LABEL'       => [-1],                          # vCard 2.1 and 3.0 - OWM Bundles into ADR
         'LOGO'        => [500,\&addreditform_PHOTO],    # vCard 2.1 and 3.0
         'TITLE'       => [-1],                          # vCard 2.1 and 3.0 - OWM Bundles into ORG
         'ROLE'        => [-1],                          # vCard 2.1 and 3.0 - OWM Bundles into ORG
         'ORG'         => [510,\&addreditform_ORG],      # vCard 2.1 and 3.0
         'URL'         => [600],                         # vCard 2.1 and 3.0
         'TZ'          => [610,\&addreditform_TZ],       # vCard 2.1 and 3.0
         'GEO'         => [620,\&addreditform_GEO],      # vCard 2.1 and 3.0
         'MAILER'      => [630],                         # vCard 2.1 and 3.0
         'NOTE'        => [640,\&addreditform_NOTE],     # vCard 2.1 and 3.0
         'KEY'         => [650,\&addreditform_KEYAGENT], # vCard 2.1 and 3.0
         'AGENT'       => [660,\&addreditform_KEYAGENT], # vCard 2.1 and 3.0
         'CLASS'       => [700,\&addreditform_CLASS],    # vCard 3.0
         'SOURCE'      => [710],                         # vCard 3.0
         'NAME'        => [720],                         # vCard 3.0
         'UID'         => [730],                         # vCard 2.1 and 3.0
         'PRODID'      => [740],                         # vCard 3.0

         # These are X- extension propertynames
         'X-OWM-UID'     => [750,\&addreditform_HIDDEN],       # Openwebmail: our system unique id
         'X-OWM-BOOK'    => [-1],                              # Openwebmail: remember addressbook name
         'X-OWM-GROUP'   => [-1],                              # Openwebmail: vcard is a group if defined
         'X-OWM-CHARSET' => [-1],                              # Openwebmail: vcard character set support
         'X-OWM-CUSTOM'  => [799,\&addreditform_X_OWM_CUSTOM], # Openwebmail: support user-defined custom fields
      );
   } else {
      # We are editing a GLOBAL contact. Allow much less input and output.
      %htmloutput = (
         # These propertynames are defined in the RFC and vCard specification
         'BEGIN'       => [-1],                            # vCard 2.1 (required) and 3.0 (required)
         'END'         => [-1],                            # vCard 2.1 (required) and 3.0 (required)
         'REV'         => [-1],                            # vCard 2.1 and 3.0
         'VERSION'     => [-1],                            # vCard 2.1 (required) and 3.0 (required)
         'PROFILE'     => [-1],                            # vCard 3.0
         'CATEGORIES'  => [-1],                            # vCard 3.0
         'PHOTO'       => [100,\&addreditform_PHOTO],      # vCard 2.1 and 3.0
         'N'           => [-1],                            # *** added later for group ***
         'FN'          => [120,\&addreditform_FNGROUP],    # vCard 2.1 and 3.0 (required)
         'SOUND'       => [130,\&addreditform_SOUND],      # vCard 2.1 and 3.0
         'NICKNAME'    => [-1],                            # vCard 3.0
         'SORT-STRING' => [-1],                            # vCard 3.0
         'BDAY'        => [-1],                            # vCard 2.1 and 3.0
         'EMAIL'       => [140,\&addreditform_EMAILGROUP], # vCard 2.1 and 3.0
         'TEL'         => [-1],                            # vCard 2.1 and 3.0
         'ADR'         => [-1],                            # vCard 2.1 and 3.0
         'LABEL'       => [-1],                            # vCard 2.1 and 3.0 - OWM Bundles into ADR
         'LOGO'        => [-1],                            # vCard 2.1 and 3.0
         'TITLE'       => [-1],                            # vCard 2.1 and 3.0 - OWM Bundles into ORG
         'ROLE'        => [-1],                            # vCard 2.1 and 3.0 - OWM Bundles into ORG
         'ORG'         => [-1],                            # vCard 2.1 and 3.0
         'URL'         => [-1],                            # vCard 2.1 and 3.0
         'TZ'          => [-1],                            # vCard 2.1 and 3.0
         'GEO'         => [-1],                            # vCard 2.1 and 3.0
         'MAILER'      => [-1],                            # vCard 2.1 and 3.0
         'NOTE'        => [150,\&addreditform_NOTE],       # vCard 2.1 and 3.0
         'KEY'         => [-1],                            # vCard 2.1 and 3.0
         'AGENT'       => [-1],                            # vCard 2.1 and 3.0
         'CLASS'       => [-1],                            # vCard 3.0
         'SOURCE'      => [-1],                            # vCard 3.0
         'NAME'        => [-1],                            # vCard 3.0
         'UID'         => [-1],                            # vCard 2.1 and 3.0
         'PRODID'      => [-1],                            # vCard 3.0

         # These are X- extension propertynames
         'X-OWM-UID'     => [160,\&addreditform_HIDDEN], # Openwebmail: our system unique id
         'X-OWM-BOOK'    => [-1],                        # Openwebmail: remember addressbook name
         'X-OWM-GROUP'   => [170,\&addreditform_HIDDEN], # Openwebmail: vcard is a group if defined
         'X-OWM-CHARSET' => [-1],                        # Openwebmail: vcard character set support
         'X-OWM-CUSTOM'  => [-1],                        # Openwebmail: support user-defined custom fields
      );
   }

   my $completevcard;  # will contain all of the data for this card
   my $contact;        # will be a pointer to a level of data in $completevcard

   if ($xowmuid ne '') {
      # load up the requested book
      my %searchterms = ( 'X-OWM-UID' => [ { 'VALUE' => $xowmuid } ] ); # only pull this card
      my %only_return = ();

      $completevcard = readadrbook($abookfile, (keys %searchterms?\%searchterms:undef), (keys %only_return?\%only_return:undef));

      print "<pre>addreditform COMPLETEVCARD as loaded:\n" . Dumper(\%{$completevcard}) . "</pre>" if $addrdebug;
   }

   # Tag as a GROUP
   $completevcard->{$xowmuid}{'X-OWM-GROUP'}[0]{VALUE} = 1 if (param('editgroupform'));

   # To access AGENT nested data we will need to know what the targetagent is.
   # Targetagent looks like: <traversedirection>,<agent position(s)>,[<last position accessed>]
   # Traverse direction can be 'access agent'(1) or 'access parent'(-1).
   # Last should only be used if traversedirection is -1 (so we know what card to save the form
   # data to before we traverse to the parent).
   my @targetagent = split(/,/,param('targetagent'));
   my $traversedirection = shift(@targetagent); # we need to pop off the first value to get the targetdepth correctly
   pop(@targetagent) if ($traversedirection == -1); # we need to pop off the last value if we're traversing up
   my $targetdepth = @targetagent || 0;

   print "<pre>\n\naddreditform TARGETDEPTH: $targetdepth\nTRAVERSEDIRECTION: $traversedirection\nTARGETAGENT:\n".Dumper(\@targetagent)."\n\n</pre>" if $addrdebug;

   # Align $contact so it is pointing to the completevcard data we want to modify.
   my $target = \%{$completevcard->{$xowmuid}};
   my $nextgif="right.s.gif"; $nextgif="left.s.gif" if ($ow::lang::RTL{$prefs{'locale'}});

   my @agentpath=($target->{FN}[0]{VALUE});
   my @agentpath_charset=($target->{'X-OWM-CHARSET'}[0]{VALUE}||'');

   for(my $depth=1;$depth<=$targetdepth;$depth++) { # 0,0
   print "<pre>Digging: targetagent position ".($depth-1)." is ".$targetagent[$depth-1]."</pre>\n" if $addrdebug;
      if (exists $target->{AGENT}[$targetagent[$depth-1]]{VALUE}) {
         foreach my $agentxowmuid (keys %{$target->{AGENT}[$targetagent[$depth-1]]{VALUE}}) {
            print "<pre>The AGENTXOWMUID at this position is $agentxowmuid</pre>\n" if $addrdebug;
            $target = \%{$target->{AGENT}[$targetagent[$depth-1]]{VALUE}{$agentxowmuid}};
            push(@agentpath, $target->{FN}[0]{VALUE});
            push(@agentpath_charset, $target->{'X-OWM-CHARSET'}[0]{VALUE}||'');
         }
      } else {
         # we're creating a new agent from scratch
         $target->{AGENT}[$targetagent[$depth-1]]{TYPES}{VCARD} = 'TYPE';
         $target = \%{$target->{AGENT}[$targetagent[$depth-1]]{VALUE}{''}};
         push(@agentpath, '_NEW_');
         push(@agentpath_charset, '');
      }
   }
   $contact->{$xowmuid} = $target;

   print "<pre>addreditform CONTACT has been aligned to:\n" . Dumper(\%{$contact}) . "</pre>" if $addrdebug;

   #################################################################################################################
   #          $contact gets modified after this point so be careful when you analize your Data::Dump's             #
   #################################################################################################################

   # bundle information from one property into another property so they display together
   # (of course to display together you need to write the code for the target property)
   my %bundlemap = ( 'LABEL' => 'ADR', 'TITLE' => 'ORG', 'ROLE' => 'ORG' );
   for (keys %bundlemap) {
      if (exists $contact->{$xowmuid}{$_}) {
         for(my $index=0;$index<@{$contact->{$xowmuid}{$_}};$index++) {
            $contact->{$xowmuid}{$bundlemap{$_}}[$index]{VALUE}{$_} = $contact->{$xowmuid}{$_}[$index]{VALUE};
         }
         delete $contact->{$xowmuid}{$_};
      }
   }

   print "<pre>FORM DUMP:\n".Dump()."\n</pre>\n\n\n" if $addrdebug;

   # convert embedded base64 file data to a file in sessions dir
   # replace the value in %contact with this $fileserial
   foreach my $propertyname (qw(PHOTO LOGO SOUND KEY AGENT)) {
      if (exists $contact->{$xowmuid}{$propertyname}) {
         print "<pre>Working on propertyname $propertyname\n</pre>" if $addrdebug;
         for(my $index=0;$index<@{$contact->{$xowmuid}{$propertyname}};$index++) {
            print "<pre>working on index $index\n</pre>" if $addrdebug;
            if (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}) {
               print "<pre>this contact has defined types\n</pre>" if $addrdebug;
               if ((exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{BASE64} ||
                    exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{VCARD})) {
                  print "<pre>this contact has a type of either VCARD or of BASE64\n</pre>" if $addrdebug;
                  if (param('EDITFORMUPLOAD') eq '' && param('webdisksel') eq '' && param('formchange') eq '') {
                     my $fileserial = time() . join("",map { int(rand(10)) }(1..9));
                     print "<pre>saving out the $propertyname index $index to fileserial $fileserial\n</pre>" if $addrdebug;
                     sysopen(FILE, "$config{'ow_sessionsdir'}/$thissession-vcard$fileserial", O_WRONLY|O_TRUNC|O_CREAT) or
                        openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $config{'ow_sessionsdir'}/$thissession-vcard$fileserial ($!)\n");
                     binmode FILE; # to ensure images don't corrupt
                     if (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{VCARD}) {
                        print FILE outputvfile('vcard',$contact->{$xowmuid}{$propertyname}[$index]{VALUE});
                     } elsif (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{BASE64}) {
                        print FILE $contact->{$xowmuid}{$propertyname}[$index]{VALUE}; # it's already been decoded in %contact
                     }
                     close FILE || openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'ow_sessionsdir'}/$thissession-vcard$fileserial ($!)\n");
                     $contact->{$xowmuid}{$propertyname}[$index]{VALUE} = "$fileserial";
                  }
               }
            }
         }
      }
   }

   # are we modifying the contact (formchanging or uploading something)?
   if (param('formchange') ne '' || param('EDITFORMUPLOAD') || param('webdisksel')) {
      # clear out $contact so we can populate it with the form data
      foreach my $propertyname (keys %{$contact->{$xowmuid}}) {
         delete $contact->{$xowmuid}{$propertyname};
      }

      # populate $contact with the form data
      my $formdata = addreditform_to_vcard();
      foreach my $propertyname (keys %{$formdata->{$xowmuid}}) {
         next if ($propertyname eq 'X-OWM-UID');
         $contact->{$xowmuid}{$propertyname} = $formdata->{$xowmuid}{$propertyname};
      }
   }

   # each supported propertyname should be represented so that
   # users can add values for that propertyname if they want
   foreach my $propertyname (keys %htmloutput) {
      $contact->{$xowmuid}{$propertyname}=[{VALUE=>''}] unless ($htmloutput{$propertyname}[0] < 0 || exists $contact->{$xowmuid}{$propertyname}[0]{VALUE});
   }

   ###########################################################################################################
   #                                $contact is not modified after this point                                #
   ###########################################################################################################

   print "<pre>addreditform CONTACT after all modifications now looks like:\n" . Dumper(\%{$contact}) . "</pre>" if $addrdebug;

   # find out composecharset
   my $composecharset = $contact->{$xowmuid}{'X-OWM-CHARSET'}[0]{VALUE} || $prefs{'charset'};
   # switch lang/charset from user prefs to en_US.UTF-8 temporarily, then display in $composecharset,
   # whatever that may be, so we can properly display the current contact
   my @tmp;
   if ($composecharset ne $prefs{'charset'}) {
      @tmp=($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'});
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=('en_US', $composecharset, 'en_US.UTF-8');
      loadlang($prefs{'locale'});
      charset($prefs{'charset'}) if ($CGI::VERSION>=2.58);  # setup charset of CGI module
   }

   # convert the contact vcard data structure to html
   # this conversion happens in the order defined in %htmloutput, undef last, -1's skipped
   my %vcardhtml = ();
   foreach my $propertyname ( sort { (exists $htmloutput{$a}?$htmloutput{$a}[0]:9999) <=> (exists $htmloutput{$b}?$htmloutput{$b}[0]:9999) }
                               map { exists $htmloutput{$_}?$htmloutput{$_}[0]>0?$_:():$_ } # skip -1's
                              keys %{$contact->{$xowmuid}} ) {
      if (exists $htmloutput{$propertyname} && defined $htmloutput{$propertyname}[1]) {
         # pass to special defined handler
         $vcardhtml{$propertyname} = $htmloutput{$propertyname}[1]->($propertyname, $contact->{$xowmuid}{$propertyname}, \%vcardhtml, $xowmuid, $abookfolder, \@targetagent);
      } else {
         # no special handler defined. Handle GENERIC.
         $vcardhtml{$propertyname} = addreditform_GENERIC($propertyname, $contact->{$xowmuid}{$propertyname});
      }
   }


   # build up the template
   my ($html, $temphtml);
   $html = applystyle(readtemplate((param('editgroupform')?'addreditgroupform.template':'addreditform.template')));

   if (param('editgroupform')) {
     # for the GoAddressWindow popup
     $temphtml = $prefs{'abook_width'} eq 'max'?'screen.availWidth':$prefs{'abook_width'};
     $html =~ s/\@\@\@ABOOKWIDTH\@\@\@/$temphtml/;

     $temphtml = $prefs{'abook_height'} eq 'max'?'screen.availHeight':$prefs{'abook_height'};
     $html =~ s/\@\@\@ABOOKHEIGHT\@\@\@/$temphtml/;

     $temphtml = $prefs{'abook_defaultfilter'}?ow::tool::escapeURL($prefs{'abook_defaultsearchtype'}):'';
     $html =~ s/\@\@\@ABOOKSEARCHTYPE\@\@\@/$temphtml/;

     $temphtml = $prefs{'abook_defaultfilter'}?ow::tool::escapeURL($prefs{'abook_defaultkeyword'}):'';
     $html =~ s/\@\@\@ABOOKKEYWORD\@\@\@/$temphtml/;
   }

   # menubar links
   my $editformcallerstr=ow::htmltext::str2html($lang_abookselectionlabels{$editformcaller}||(iconv($prefs{'fscharset'}, $composecharset, $editformcaller))[0]);
   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $editformcallerstr",
                        ($editformcaller eq 'readmessage' ?
                        qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession&amp;$webmail_urlparm"| :
                        qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;sessionid=$thissession&amp;abookfolder=$escapededitformcaller&amp;$abook_urlparm"|));
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   # start the form
   $temphtml = start_multipart_form(-name=>'editForm',
                                    -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
               ow::tool::hiddens(
                          action=>'addredit',
                          sessionid=>$thissession,
                          formchange=>'',
                          targetagent=>join(",",(0,@targetagent)),
                          rootxowmuid=>($targetdepth>0?param('rootxowmuid'):$xowmuid),
                          editformcaller=>ow::tool::escapeURL($editformcaller),
                          defined(param('editgroupform'))?('editgroupform'=>1):()
                         ). $abook_formparm.$webmail_formparm;
   $html =~ s/\@\@\@EDITFORMSTART\@\@\@/$temphtml/;

   # destination pulldown
   if ($xowmuid eq '') { 	# new entry
      if ($#writableabookfolders>=0) {
         my (@abookvalues, %abooklabels);
         foreach my $abook (@writableabookfolders) {
            my ($value, $label)=(ow::tool::escapeURL($abook), $abook);
            if (defined $lang_abookselectionlabels{$abook}) {
               $label=$lang_abookselectionlabels{$abook};
            } else {
               $label=(iconv($prefs{'fscharset'}, $composecharset, $abook))[0];
            }
            $label.=" *" if (is_abookfolder_global($abook));
            push(@abookvalues, $value); $abooklabels{$value}=$label;
         }
         $temphtml = qq|<table cellspacing=0 cellpadding=0 border=0><tr>|.
                     qq|<td><font color=$style{'titlebar_text'} face=$style{'fontface'} size="3"><b>$lang_text{'abook_editform_destination'}:&nbsp;</b></font></td><td>|.
                     popup_menu(-name=>'abookfolder',
                                -override=>1,
                                -values=>\@abookvalues,
                                -default=>ow::tool::escapeURL($abookfolder),
                                -labels=>\%abooklabels,
                               ).
                     qq|</td></tr></table>\n|;
         $html =~ s/\@\@\@ABOOKNAME\@\@\@/$temphtml/;
      } else {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_all_readonly'}");
      }
   } else {
      $temphtml = ow::tool::hiddens(abookfolder=>$escapedabookfolder).
                  qq|$lang_text{'addressbook'}: |.
                  ow::htmltext::str2html($lang_abookselectionlabels{$abookfolder}||(iconv($prefs{'fscharset'}, $composecharset, $abookfolder))[0]).
                  qq|&nbsp;|;
      $html =~ s/\@\@\@ABOOKNAME\@\@\@/$temphtml/;
   }

   my $agentpath_str;
   for my $i (0.. $#agentpath) {
      $agentpath_str.="&nbsp;".iconlink($nextgif)."&nbsp;" if ($agentpath_str ne'');
      if ($agentpath[$i] eq '_NEW_') {
         $agentpath[$i] = $lang_text{'abook_editform_new_agent'};
      } else {
         ($agentpath[$i])=iconv($agentpath_charset[$i], $composecharset, $agentpath[$i]) ;
      }
      $agentpath_str.= $agentpath[$i];
   }
   $html =~ s!\@\@\@AGENTPATH\@\@\@!<b>$agentpath_str</b>!;

   # charset conversion menu
   my %ctlabels=( $composecharset => "$composecharset *" );
   my @ctlist=($composecharset);
   my %allsets;
   foreach ((map { $ow::lang::charactersets{$_}[1] } keys %ow::lang::charactersets), keys %charset_convlist) {
      $allsets{$_}=1 if (!defined $allsets{$_});
   }
   delete $allsets{$composecharset};

   if (defined $charset_convlist{$composecharset}) {
      foreach my $ct (sort @{$charset_convlist{$composecharset}}) {
         if (is_convertible($composecharset, $ct)) {
            $ctlabels{$ct}="$composecharset > $ct";
            push(@ctlist, $ct);
            delete $allsets{$ct};
         }
      }
   }
   push(@ctlist, sort keys %allsets);

   $temphtml = popup_menu(-name=>'X-OWM-CHARSET.0.VALUE',
                          -values=>\@ctlist,
                          -labels=>\%ctlabels,
                          -default=>$composecharset,
                          -accesskey=>'I',
                          -onChange=>"javascript:document.editForm.formchange.value='X-OWM-CHARSET,0,0'; document.editForm.submit();",
                          -override=>'1').
               hidden(-name=>'convfrom', -default=>$composecharset, -override=>1);
   $html =~ s/\@\@\@CONVTOMENU\@\@\@/$temphtml/;


   # put each html block contained in vcardhtml in its proper class
   my @classhtml = ();
   my $classes = int((sort {$b <=> $a} map {$htmloutput{$_}[0]} keys %htmloutput)[0] / 100)+1; # how many classes?
   $htmloutput{'X-OWM-CUSTOM'}[0] = $classes*100; # push customs into the end of the custom class (always the last one)
   foreach my $propertyname (sort { (exists $htmloutput{$a}?$htmloutput{$a}[0]:9999) <=> (exists $htmloutput{$b}?$htmloutput{$b}[0]:9999) } keys %vcardhtml) {
      my $class = (exists $htmloutput{$propertyname} && $htmloutput{$propertyname}[0]>99)?int($htmloutput{$propertyname}[0]/100)-1:$classes-1;
      $classhtml[$class] .= $vcardhtml{$propertyname};
   }
   for(my $i=0;$i<=@classhtml;$i++) {
      my $class = ($i+1)*100;
      $html =~ s/\@\@\@$class\@\@\@/$classhtml[$i]/;
   }

   # file upload area
   my ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();
   my $availattspace = int($config{'abook_attlimit'} - ($attfiles_totalsize/1024) + .5);
   $html =~ s/\@\@\@AVAILABLEATTSPACE\@\@\@/$availattspace $lang_sizes{'kb'}/;

   my $webdisklink = '';
#   TO DO LATER!
#   if ($config{'enable_webdisk'}) {
#      $webdisklink = ow::tool::hiddens(webdisksel=>'').
#                     iconlink("webdisk.s.gif", $lang_text{'webdisk'}, qq|href="#" onClick="window.open('$config{ow_cgiurl}/openwebmail-webdisk.pl?sessionid=$thissession&amp;action=sel_addattachment', '_addatt','width=500,height=330,scrollbars=yes,resizable=yes,location=no'); return false;"|);
#   }
   $html =~ s/\@\@\@UPLOADWEBDISKLINK\@\@\@/$webdisklink/;

   # save and save and return to parents forms
   $temphtml = '';
   if ($targetdepth > 0) {
      my $agenttarget = join(",",(-1,@targetagent));
      $temphtml .= submit(-name=>$lang_text{'abook_editform_save_and_return'},
                          -class=>"medtext",
                          -onClick=>"document.editForm.targetagent.value='$agenttarget'; return (popupNotice('agentmustsave') && savecheck('editForm'));");
      $temphtml .= "&nbsp;";
   }
   if ($xowmuid eq '' ||			# new entry
       is_abookfolder_writable($abookfolder)) {	# old entry on writablebook
      $temphtml .= submit(-name=>$lang_text{'save'},
                          -class=>"medtext",
                          -onClick=> "return savecheck('editForm');");
   }
   $html =~ s/\@\@\@EDITFORMSUBMIT\@\@\@/$temphtml/;

   $temphtml = endform();
   $html =~ s/\@\@\@EDITFORMEND\@\@\@/$temphtml/;

   # cancel and return form
   $temphtml = '';
   if ($targetdepth > 0) {
      $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                             -name=>'cancelReturnToParent').
                  ow::tool::hiddens(action=>'addreditform',
                                    sessionid=>$thissession,
                                    abookfolder=>ow::tool::escapeURL($abookfolder),
                                    targetagent=>join(",",(-1,@targetagent)),
                                    rootxowmuid=>param('rootxowmuid'),
                                   ). $abook_formparm.$webmail_formparm.
                  submit(-name=>"$lang_text{'abook_editform_cancel_and_return'}",
                         -class=>"medtext",
                         -onClick=>"return popupNotice('cancelchanges');",
                        ).
                  end_form();
      $html =~ s/\@\@\@CANCELANDRETURNFORM\@\@\@/$temphtml/;
   } else {
      $temphtml = "&nbsp;";
      $html =~ s/\@\@\@CANCELANDRETURNFORM\@\@\@/$temphtml/;
   }

   # cancel form
   $temphtml = start_form(
                          -action => ( $editformcaller eq 'readmessage' ?
                                       "$config{'ow_cgiurl'}/openwebmail-read.pl" :
                                       "$config{'ow_cgiurl'}/openwebmail-abook.pl" ),
                          -name   => 'cancelEditForm').
               ow::tool::hiddens(action      => ( $editformcaller eq 'readmessage' ? 'readmessage' : 'addrlistview' ),
                                 sessionid   => $thissession,
                                 abookfolder => ow::tool::escapeURL($editformcaller),
                                ). $abook_formparm.$webmail_formparm.
               submit(-name=>"$lang_text{'cancel'}",
                      -class=>"medtext").
               end_form();
   $html =~ s/\@\@\@CANCELEDITFORM\@\@\@/$temphtml/;

   foreach my $anchor ('EMAIL', 'TEL', 'ADR', 'ORG', 'URL', 'X-OWM-CUSTOM') {
      if (param('formchange') =~ /^$anchor/) {
         $html .= qq|<script language="JavaScript">\n<!--\n|.
                  qq|location.hash = '$anchor';\n|.
                  qq|//-->\n</script>\n|;
         last;
      }
   }

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);

   # switch lang/charset back to user prefs
   if ($#tmp>=1) {
      ($prefs{'language'}, $prefs{'charset'}, $prefs{'locale'})=@tmp;
   }
}
########## END ADDREDITFORM ######################################


########## ADDREDITFORM_GENERIC ##################################
sub addreditform_GENERIC {
   my ($name, $r_data) = @_;
   my $htmlout;
   @{$r_data} = map { $_->[3] }
                sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2]}
                map { [ exists($_->{TYPES})?(exists($_->{TYPES}{PREF})?0:1):1, exists($_->{GROUP})?lc($_->{GROUP}):'~~~', $_->{VALUE}?lc($_->{VALUE}):'~~~', $_] }
                @{$r_data};
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = applystyle(readtemplate("addreditform_GENERIC.template"));
      my $namelabel = $lang_text{"abook_editform_namelabel_$name"} || $name;
      $namelabel = '' if $index > 0;
      $template =~ s/\@\@\@NAMELABEL\@\@\@/$namelabel/;
      addreditform_GENERIC_VALUE($name, $r_data, $index, \$template);
      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);
      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_GENERIC ##############################


########## ADDREDITFORM_GENERIC_VALUE ############################
sub addreditform_GENERIC_VALUE {
   my ($name, $r_data, $index, $r_html) = @_;
   my $valuelabel = $lang_text{"abook_editform_valuelabel_$name"} || $lang_text{'abook_editform_valuelabel'};
   my $valuehtml = textfield(-name=>"$name.$index.VALUE", -default=>$r_data->[$index]{VALUE}, -size=>"35", -override=>"1", -class=>"mono");
   if (@{$r_data} > 1) {
      $valuehtml .= qq|&nbsp;&nbsp;|.iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|);
   }
   my $addmorelink = qq|<a href="javascript:document.editForm.formchange.value='$name,0,1'; document.editForm.submit();">+</a>|;
   ${$r_html} =~ s/\@\@\@ADDMORELINK\@\@\@/$addmorelink/;
   ${$r_html} =~ s/\@\@\@VALUE\@\@\@/$valuehtml/;
   ${$r_html} =~ s/\@\@\@VALUELABEL\@\@\@/$valuelabel/;
}
########## END ADDREDITFORM_GENERIC_VALUE ########################


########## ADDREDITFORM_GENERIC_TYPES ############################
sub addreditform_GENERIC_TYPES {
   my ($name, $r_data, $index, $r_html) = @_;
   my $typehtml = hidden(-name=>"$name.$index.TYPE", -default=>[map {$_} keys %{$r_data->[$index]{TYPES}}], -override=>1);
   $typehtml = '' if keys %{$r_data->[$index]{TYPES}} < 1;
   ${$r_html} =~ s/\@\@\@TYPES\@\@\@/$typehtml/;
}
########## END ADDREDITFORM_GENERIC_TYPES ########################


########## ADDREDITFORM_GENERIC_GROUP ############################
sub addreditform_GENERIC_GROUP {
   my ($name, $r_data, $index, $r_html) = @_;
   my ($grouphtml,$grouplabel) = ();
   if ($r_data->[$index]{GROUP} ne '') {
      $grouphtml = textfield(-name=>"$name.$index.GROUP", -default=>ow::htmltext::str2html($r_data->[$index]{GROUP}), -size=>"12", -override=>"1", -class=>"mono")."&nbsp;&nbsp;";
      $grouplabel = $lang_text{'abook_editform_grouplabel'};
   }
   ${$r_html} =~ s/\@\@\@GROUP\@\@\@/$grouphtml/;
   ${$r_html} =~ s/\@\@\@GROUPLABEL\@\@\@/$grouplabel/;
}
########## END ADDREDITFORM_GENERIC_GROUP ########################


########## ADDREDITFORM_HIDDEN ###################################
sub addreditform_HIDDEN {
   my ($name, $r_data) = @_;
   my $htmlout = qq|<tr><td>|.
                 hidden(-name=>"$name.0.VALUE", -default=>$r_data->[0]{VALUE}, -override=>1).
                 qq|</td></tr>\n|;
   return $htmlout;
}
########## END ADDREDITFORM_HIDDEN ###############################


########## ADDREDITFORM_N ########################################
sub addreditform_N {
   my ($name, $r_data) = @_;
   my $htmlout;
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = applystyle(readtemplate("addreditform_N.template"));
      # SPECIAL
      $template =~ s/\@\@\@FN.NAME\@\@\@/FN.$index.VALUE/;
      # VALUE
      if (ref $r_data->[$index]{VALUE} ne 'HASH') {
         # N is blank (a new contact)
         $r_data->[$index]{VALUE} = { NAMEPREFIX => '',
                                      GIVENNAME => '',
                                      ADDITIONALNAMES => '',
                                      FAMILYNAME => '',
                                      NAMESUFFIX => '' }
      }
      foreach my $fieldname (qw(NAMEPREFIX GIVENNAME ADDITIONALNAMES FAMILYNAME NAMESUFFIX)) {
         $template =~ s/\@\@\@$fieldname.NAME\@\@\@/$name.$index.VALUE.$fieldname/g;
         my $escapedvalue = ow::htmltext::str2html($r_data->[$index]{VALUE}{$fieldname});
         $template =~ s/\@\@\@$fieldname.VALUE\@\@\@/$escapedvalue/;
      }
      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);
      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_N ####################################


########## ADDREDITFORM_FNGROUP ##################################
sub addreditform_FNGROUP {
   my ($name, $r_data) = @_;
   my $htmlout;
   @{$r_data} = map { $_->[3] }
                sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2]}
                map { [ exists($_->{TYPES})?(exists($_->{TYPES}{PREF})?0:1):1, exists($_->{GROUP})?lc($_->{GROUP}):'~~~', $_->{VALUE}?lc($_->{VALUE}):'~~~', $_] }
                @{$r_data};
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = applystyle(readtemplate("addreditform_GENERIC.template"));
      my $namelabel = $lang_text{"abook_editform_namelabel_GROUPNAME"};
      $namelabel = '' if $index > 0;
      $template =~ s/\@\@\@NAMELABEL\@\@\@/$namelabel/;
      addreditform_GENERIC_VALUE($name, $r_data, $index, \$template);
      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);
      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_FNGROUP ##############################


########## ADDREDITFORM_ORG ######################################
sub addreditform_ORG {
   my ($name, $r_data) = @_;
   my $htmlout;
   my $ORGtemplate = applystyle(readtemplate("addreditform_ORG.template"));
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = $ORGtemplate;
      if (ref $r_data->[$index]{VALUE} ne 'HASH') { # ORG is blank (a new contact)
         $r_data->[$index]{VALUE} = { ORGANIZATIONNAME => '',
                                      TITLE => '',
                                      ROLE => '' }
      }
      foreach my $field (qw(ORGANIZATIONNAME TITLE ROLE)) {
         # VALUE
         my $valuelabel = $lang_text{"abook_editform_valuelabel_$field"} || $lang_text{'abook_editform_valuelabel'};
         $template =~ s/\@\@\@$field.VALUELABEL\@\@\@/$valuelabel/;
         my $valuehtml = textfield(-name=>"ORG.$index.VALUE.$field", -default=>$r_data->[$index]{VALUE}{$field}, -size=>"30", -override=>"1", -class=>"mono");
         $template =~ s/\@\@\@$field.VALUE\@\@\@/$valuehtml/;
      }
      my $delete;
      if (@{$r_data} > 1) {
         $delete = iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|);
      }
      $template =~ s/\@\@\@DELETE\@\@\@/$delete/;
      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      # ORGANIZATIONALUNITS.VALUE
      my $valuehtml = '';
      my $valuelabel = $lang_text{"abook_editform_valuelabel_ORGANIZATIONALUNITS"} || $lang_text{'abook_editform_valuelabel'};
      $r_data->[$index]{VALUE}{ORGANIZATIONALUNITS} = [''] if (ref($r_data->[$index]{VALUE}{ORGANIZATIONALUNITS}) ne 'ARRAY');
      for(my $pos=0;$pos<@{$r_data->[$index]{VALUE}{ORGANIZATIONALUNITS}};$pos++) {
         $template =~ s/\@\@\@ADDORGANIZATIONALUNITS\@\@\@/ORG.$index.VALUE.ORGANIZATIONALUNITS/;
         if (ref($r_data->[$index]{VALUE}{ORGANIZATIONALUNITS}[$pos]) eq 'HASH') {
            # a new field was added (adds as {VALUE => ''} by default, which in this case we don't want)
            $r_data->[$index]{VALUE}{ORGANIZATIONALUNITS}[$pos] = '';
         }
         $valuehtml .= qq|<tr><td>|.
                       textfield(-name=>"ORG.$index.VALUE.ORGANIZATIONALUNITS.$pos", -default=>$r_data->[$index]{VALUE}{ORGANIZATIONALUNITS}[$pos], -size=>"30", -override=>"1", -class=>"mono");
         if (@{$r_data->[$index]{VALUE}{ORGANIZATIONALUNITS}} > 1) {
            $valuehtml .= qq|&nbsp;&nbsp;|.
                          iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='ORG.$index.VALUE.ORGANIZATIONALUNITS,$pos,-1'; document.editForm.submit();"|);
         }
         $valuehtml .= qq|</td></tr>\n|;
         $valuehtml .= $pos==$#{$r_data->[$index]{VALUE}{ORGANIZATIONALUNITS}}?qq|<tr><td class="smalltext">$valuelabel</td></tr>\n|:qq|<tr><td></td></tr>\n|;
      }
      $template =~ s/\@\@\@ORGANIZATIONALUNITS.VALUE\@\@\@/$valuehtml/;

      $htmlout .= $template;
   }

   return $htmlout;
}
########## END ADDREDITFORM_ORG ##################################


########## ADDREDITFORM_TZ #######################################
sub addreditform_TZ {
   my ($name, $r_data) = @_;
   my $htmlout;
   my $TZtemplate = applystyle(readtemplate("addreditform_GENERIC.template"));
   my @tzoffsets = qw( -1200 -1100 -1000 -0900 -0800 -0700 -0600 -0500 -0400 -0330 -0300 -0230 -0200 -0100
                       +0000 +0100 +0200 +0300 +0330 +0400 +0500 +0530 +0600 +0630 +0700 +0800 +0900 +0930
                       +1000 +1030 +1100 +1200 +1300 );
   my %tzoffsetlabels = map { $_ => "$_ -  $lang_timezonelabels{$_}"} keys %lang_timezonelabels;
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = $TZtemplate;
      # VALUE
      my $valuehtml = popup_menu(
                                 -name=>"$name.$index.VALUE",
                                 -default=>$r_data->[$index]{VALUE} || $prefs{'timeoffset'},
                                 -values=>\@tzoffsets,
                                 -labels=>\%tzoffsetlabels,
                                 -class=>'mono',
                                 -override=>1,
                                ).
                      qq|&nbsp;|.
                      iconlink("earth.gif", $lang_text{'tzmap'}, qq|href="$config{'ow_htmlurl'}/images/timezone.jpg" target="_timezonemap"|);
      $template =~ s/\@\@\@VALUE\@\@\@/$valuehtml/;
      $template =~ s/\@\@\@VALUELABEL\@\@\@//;
      my $namelabel = $lang_text{"abook_editform_namelabel_$name"} || $name;
      $namelabel = '' if $index > 0;
      $template =~ s/\@\@\@NAMELABEL\@\@\@/$namelabel/;

      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_TZ ###################################


########## ADDREDITFORM_CLASS ####################################
sub addreditform_CLASS {
   my ($name, $r_data) = @_;
   my $htmlout;
   my $CLASStemplate = applystyle(readtemplate("addreditform_GENERIC.template"));
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = $CLASStemplate;
      # VALUE
      my %classvalues = (
                          'PUBLIC' => 1,
                          'PRIVATE' => 1,
                          uc($r_data->[$index]{VALUE}) => 1,
                        );
      my $valuehtml = popup_menu(
                                 -name=>"$name.$index.VALUE",
                                 -default=>uc($r_data->[$index]{VALUE}) || 'PUBLIC',
                                 -values=>[sort keys %classvalues],
                                 -labels=>\%lang_abookclasslabels,
                                 -class=>'mono',
                                 -override=>1,
                                );
      $template =~ s/\@\@\@VALUE\@\@\@/$valuehtml/;
      $template =~ s/\@\@\@VALUELABEL\@\@\@//;
      my $namelabel = $lang_text{"abook_editform_namelabel_$name"} || $name;
      $namelabel = '' if $index > 0;
      $template =~ s/\@\@\@NAMELABEL\@\@\@/$namelabel/;

      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_CLASS ################################


########## ADDREDITFORM_GEO ######################################
sub addreditform_GEO {
   my ($name, $r_data) = @_;
   my $htmlout;
   my $GEOtemplate = applystyle(readtemplate("addreditform_GEO.template"));
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = $GEOtemplate;
      $template =~ s/\@\@\@INDEX\@\@\@/$index/g;
      # VALUE
      if (ref $r_data->[$index]{VALUE} ne 'HASH') {
         # GEO is blank (a new contact)
         $r_data->[$index]{VALUE} = { LONGITUDE => '',
                                      LATITUDE => '' }
      }
      foreach my $fieldname (qw(LONGITUDE LATITUDE)) {
         $template =~ s/\@\@\@$fieldname.NAME\@\@\@/$name.$index.VALUE.$fieldname/g;
         my $escapedvalue = ow::htmltext::str2html($r_data->[$index]{VALUE}{$fieldname});
         $template =~ s/\@\@\@$fieldname.VALUE\@\@\@/$escapedvalue/g;
      }
      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      my $findlink = iconlink("abookgeofind.gif", "$lang_text{'abook_editform_GEO_find'}", qq|href="$lang_text{'abook_editform_GEO_findurl'}" target="_new"|);
      $template =~ s/\@\@\@FINDLINK\@\@\@/$findlink/;
      my $maplink = iconlink("abookglobalicon.gif", "$lang_text{'abook_editform_GEO_map'}", qq|href="javascript:showGeo('editForm',$index,'map');"|);
      $template =~ s/\@\@\@MAPLINK\@\@\@/$maplink/;
      my $photolink = iconlink("abookgeocamera.gif", "$lang_text{'abook_editform_GEO_photo'}", qq|href="javascript:showGeo('editForm',$index,'photo');"|);
      $template =~ s/\@\@\@PHOTOLINK\@\@\@/$photolink/;

      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_GEO ##################################


########## ADDREDITFORM_NOTE #####################################
sub addreditform_NOTE {
   my ($name, $r_data) = @_;
   my $htmlout;
   my $NOTEtemplate = applystyle(readtemplate("addreditform_GENERIC.template"));
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = $NOTEtemplate;
      # VALUE
      my $valuehtml = textarea(
                               -name=>"$name.$index.VALUE",
                               -rows=>8,
                               -columns=>60,
                               -default=>$r_data->[$index]{VALUE},
                               -override=>1,
                              );
      $template =~ s/\@\@\@VALUE\@\@\@/$valuehtml/;
      $template =~ s/\@\@\@VALUELABEL\@\@\@//;
      my $namelabel = $lang_text{"abook_editform_namelabel_$name"} || $name;
      $namelabel = '' if $index > 0;
      $template =~ s/\@\@\@NAMELABEL\@\@\@/$namelabel/;
      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_NOTE #################################


########## ADDREDITFORM_KEYAGENT #################################
sub addreditform_KEYAGENT {
   my ($name, $r_data, $r_vcardhtml, $xowmuid, $abookfolder, $r_targetagent) = @_;
   my $htmlout;
   my @bgcolor = ($style{"tablerow_dark"}, $style{"tablerow_light"});
   my $colornum = 1;
   my $writable=is_abookfolder_writable($abookfolder);

   for(my $index=0;$index<@{$r_data};$index++) {
      # take the first type as the filetype (this has a chance of being wrong, but 99.9% will be right)
      my $type = lc((grep {!m/(?:BASE64|URI)/} keys %{$r_data->[$index]{TYPES}})[0]);

      # VALUE
      my $tablehtml = qq|<tr>\n<td bgcolor=$bgcolor[$colornum]>|;
      if ($r_data->[$index]{VALUE}) {
         my $valuestring = "&nbsp;&nbsp;" . (exists($lang_text{"abook_editform_$type\_$name"})?$lang_text{"abook_editform_$type\_$name"}:$lang_text{"abook_editform_unknown_$name"});

         if (exists $r_data->[$index]{TYPES}{URI}) {
            my $uri=$r_data->[$index]{VALUE}; $uri=~s/\%THISSESSION\%/$thissession/;	# replace '%THISSESSION%' with $thissession for OWM link
            my $escapedvalue = ow::htmltext::str2html($uri);
            $tablehtml .= iconlink(lc($name).".gif", $lang_text{"abook_editform_view_$name"}, qq|href="$escapedvalue" target="_new"|).qq|\n|.
                          qq|<a href="$escapedvalue" target="_new">$valuestring</a>\n|;
         } elsif (exists $r_data->[$index]{TYPES}{VCARD}) {
            # AGENT card got pulled off into a file in the sessions dir. Retrieve it so that we can get its full name.
            my $targetfile = ow::tool::untaint("$config{'ow_sessionsdir'}/$thissession-vcard$r_data->[$index]{VALUE}");
            my $agentvcard = readadrbook($targetfile, undef, undef);
            my $escapedabookfolder = ow::tool::escapeURL($abookfolder);
            foreach my $agentowmuid (keys %{$agentvcard}) {
               $valuestring = "&nbsp;&nbsp;".(iconv($agentvcard->{$agentowmuid}{'X-OWM-CHARSET'}[0]{VALUE}, $prefs{'charset'}, $agentvcard->{$agentowmuid}{FN}[0]{VALUE}))[0];
            }
            my $agenttarget = join(",",(1,(@{$r_targetagent}?@{$r_targetagent}:()),$index)); # the leading 1 sets 'access agent' mode
            $tablehtml .= iconlink("abook".lc($name).".gif", $lang_text{"abook_editform_download_$name"}, qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrviewatt&amp;sessionid=$thissession&amp;file=$r_data->[$index]{VALUE}&amp;type=$type" target="_new"|).qq|\n|;
            $tablehtml .= ($writable)?qq|<a href="javascript:document.editForm.targetagent.value='$agenttarget'; document.editForm.submit();" onClick="return (popupNotice('agentmustsave') && savecheck('editForm'));">$valuestring</a>\n|:qq|$valuestring\n|;
         } else { # binary data
            $tablehtml .= iconlink("abook".lc($name).".gif", $lang_text{"abook_editform_view_$name"}, qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrviewatt&amp;sessionid=$thissession&amp;file=$r_data->[$index]{VALUE}&amp;type=$type" target="_new"|).qq|\n|.
                          qq|<a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrviewatt&amp;sessionid=$thissession&amp;file=$r_data->[$index]{VALUE}&amp;type=$type" target="_new">$valuestring</a>\n|;
         }
         $tablehtml .= hidden(-name=>"$name.$index.GROUP", -default=>$r_data->[$index]{GROUP}, -override=>1).qq|\n|.
                       hidden(-name=>"$name.$index.VALUE", -default=>$r_data->[$index]{VALUE}, -override=>1).qq|\n|.
                       hidden(-name=>"$name.$index.TYPE", -default=>[map {$_ eq 'PREF'?():$_} keys %{$r_data->[$index]{TYPES}}], -override=>1).qq|\n|;
         if ($writable && $r_data->[$index]{VALUE}) {
            $tablehtml .= qq|&nbsp;&nbsp;|.
                          iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|);
         }
      } else {
         $tablehtml .= "&nbsp;".$lang_text{"abook_editform_undef_$name"};
         splice(@{$r_data},$index,1); # so that the nextagentposition number is correct
      }
      $tablehtml .= qq|</td>\n</tr>\n|;
      $colornum=($colornum+1)%2; # alternate the bgcolor
      $htmlout .= $tablehtml;
   }
   my $template = applystyle(readtemplate("addreditform_KEYAGENT.template"));
   $template =~ s/\@\@\@TABLE\@\@\@/$htmlout/;
   my $namelabel = $lang_text{"abook_editform_namelabel_$name"} || $name;
   $template =~ s/\@\@\@NAMELABEL\@\@\@/$namelabel/;
   if ($writable && $name eq 'AGENT') {
      my $nextagentposition = @{$r_data};
      my $agenttarget = join(",",(1,(@{$r_targetagent}?@{$r_targetagent}:()),$nextagentposition));
      my $newagentlink = qq|<a href="javascript:document.editForm.targetagent.value='$agenttarget'; document.editForm.submit();" onClick="return (popupNotice('agentmustsave') && savecheck('editForm'));">$lang_text{'abook_editform_new_agent_link'}</a>|;
      $template =~ s/\@\@\@NEWAGENTLINK\@\@\@/$newagentlink/;
   } else {
      $template =~ s/\@\@\@NEWAGENTLINK\@\@\@/&nbsp;/;
   }
   return $template;
}
########## END ADDREDITFORM_KEYAGENT #############################


########## ADDREDITFORM_EMAIL ####################################
sub addreditform_EMAIL {
   my ($name, $r_data) = @_;
   my $htmlout;
   @{$r_data} = map { $_->[3] }
                sort { $a->[0] <=> $b->[0] || $a->[1] cmp $b->[1] || $a->[2] cmp $b->[2]}
                map { [ exists($_->{TYPES})?(exists($_->{TYPES}{PREF})?0:1):1, exists($_->{GROUP})?lc($_->{GROUP}):'~~~', $_->{VALUE}?lc($_->{VALUE}):'~~~', $_] }
                @{$r_data};
   my $EMAILtemplate = applystyle(readtemplate("addreditform_GENERIC.template"));
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = $EMAILtemplate;
      # VALUE
      my $valuehtml = textfield(-name=>"$name.$index.VALUE", -default=>$r_data->[$index]{VALUE}, -size=>"35", -override=>"1", -class=>"mono").
                      qq|&nbsp;<input type="radio" name="$name.PREF" value="$index" |.(exists($r_data->[$index]{TYPES})?exists($r_data->[$index]{TYPES}{PREF})?'checked':():()).qq|>|;
      if (@{$r_data} > 1) {
         $valuehtml .= qq|&nbsp;&nbsp;| . iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|);
      }
      $template =~ s/\@\@\@VALUE\@\@\@/$valuehtml/;
      $template =~ s/\@\@\@VALUELABEL\@\@\@//;
      $template =~ s/\@\@\@NAMELABEL\@\@\@//;
      # TYPES
      my $typehtml = hidden(-name=>"$name.$index.TYPE", -default=>[map {$_ eq 'PREF'?():$_} keys %{$r_data->[$index]{TYPES}}], -override=>1);
      $typehtml = '' if keys %{$r_data->[$index]{TYPES}} < 1;
      $template =~ s/\@\@\@TYPES\@\@\@/$typehtml/;
      # GROUP
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_EMAIL ################################


########## ADDREDITFORM_EMAILGROUP ###############################
sub addreditform_EMAILGROUP {
   my ($name, $r_data) = @_;
   my $htmlout;
   my $template = applystyle(readtemplate("addreditform_GENERIC.template"));
   # VALUE - a textarea with each email address on its own line
   my $emailaddresses = '';
   for(my $index=0;$index<@{$r_data};$index++) {
      next if ($r_data->[$index]{VALUE} eq 'All Members');
      $emailaddresses .= "\n$r_data->[$index]{VALUE}";
   }
   my $valuehtml = textarea(
                            -name=>"$name.0.VALUE",
                            -rows=>8,
                            -columns=>60,
                            -default=>$emailaddresses,
                            -override=>1,
                           );
   $template =~ s/\@\@\@VALUE\@\@\@/$valuehtml/;
   $template =~ s/\@\@\@VALUELABEL\@\@\@//;
   my $namelabel = $lang_text{"abook_editform_namelabel_$name"} || $name;
   $namelabel .= "&nbsp;&nbsp;&nbsp;&nbsp;" . iconlink('addrbook.s.gif', $lang_text{'addressbook'}, qq|href="javascript:GoAddressWindow()"|);
   $template =~ s/\@\@\@NAMELABEL\@\@\@/$namelabel/;
   addreditform_GENERIC_TYPES($name, $r_data, 0, \$template);
   addreditform_GENERIC_GROUP($name, $r_data, 0, \$template);

   $htmlout .= $template;
   return $htmlout;
}
########## END ADDREDITFORM_EMAILGROUP ###########################


########## ADDREDITFORM_TEL ######################################
sub addreditform_TEL {
   my ($name, $r_data) = @_;
   my $htmlout;

   my %typemap = ( 'PREF' => 0,
                   'HOME' => 1,
                   'WORK' => 2,
                   'CELL' => 3,
                    'CAR' => 4,
                  'VIDEO' => 5,
                  'PAGER' => 6,
                  'VOICE' => 7,
                    'FAX' => 8,
                   'ISDN' => 9,
                    'BBS' => 10,
                  'MODEM' => 11,
                    'MSG' => 12 );

   @{$r_data} = map { $_->[4] }
                sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || $a->[2] cmp $b->[2] || $a->[3] cmp $b->[3]}
                map { [ exists($_->{TYPES})?$typemap{(sort {$typemap{$a} <=> $typemap{$b}} keys %{$_->{TYPES}})[0]}:100,
                        exists($_->{TYPES})?$typemap{(sort {$typemap{$a} <=> $typemap{$b}} keys %{$_->{TYPES}})[1]}:100,
                        exists($_->{GROUP})?lc($_->{GROUP}):'~~~', $_->{VALUE}?lc($_->{VALUE}):'~~~', $_ ] }
                @{$r_data};
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = applystyle(readtemplate("addreditform_TEL.template"));
      # VALUE
      my $valuehtml = textfield(-name=>"$name.$index.VALUE", -default=>$r_data->[$index]{VALUE}, -size=>"25", -override=>"1", -class=>"mono").
                      qq|&nbsp;<input type="radio" name="$name.PREF" value="$index" |.(exists($r_data->[$index]{TYPES})?exists($r_data->[$index]{TYPES}{PREF})?'checked':():()).qq|>|;
      $template =~ s/\@\@\@VALUE\@\@\@/$valuehtml/;
      my $delete;
      if (@{$r_data} > 1) {
         $delete = iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|);
      }
      $template =~ s/\@\@\@DELETE\@\@\@/$delete/;
      # TYPES
      foreach my $type (keys %typemap) {
         $template =~ s/\@\@\@$type.NAME\@\@\@/$name.$index.TYPE.$type/g;
         my $checked = exists($r_data->[$index]{TYPES})?exists($r_data->[$index]{TYPES}{$type})?'checked':'':'';
         $template =~ s/\@\@\@$type.VALUE\@\@\@/$checked/g;
      }
      # GROUP
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_TEL ##################################


########## ADDREDITFORM_ADR ######################################
sub addreditform_ADR {
   my ($name, $r_data) = @_;
   my $htmlout;

   my %typemap = ( 'PREF' => 0,
                   'HOME' => 1,
                   'WORK' => 2,
                    'DOM' => 3,
                   'INTL' => 4,
                 'POSTAL' => 5,
                 'PARCEL' => 6 );

   for (@{$r_data}) { $_->{VALUE} = {} if (ref $_->{VALUE} ne 'HASH') };

   # sort - the ~~~ sorts last in perl
   @{$r_data} = map { $_->[4] }
                sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || $a->[2] cmp $b->[2] || $a->[3] cmp $b->[3]}
                map { [ exists($_->{TYPES})?$typemap{(sort {$typemap{$a} <=> $typemap{$b}} keys %{$_->{TYPES}})[0]}:100,
                        exists($_->{TYPES})?$typemap{(sort {$typemap{$a} <=> $typemap{$b}} keys %{$_->{TYPES}})[1]}:100,
                        exists($_->{GROUP})?lc($_->{GROUP}):'~~~', exists($_->{VALUE}{STREET})?lc($_->{VALUE}{STREET}):'~~~', $_ ] }
                @{$r_data};
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = applystyle(readtemplate("addreditform_ADR.template"));
      # VALUE
      $r_data->[$index]{VALUE} = {} if (ref $r_data->[$index]{VALUE} ne 'HASH');
      foreach my $field (qw(STREET EXTENDEDADDRESS POSTOFFICEADDRESS LOCALITY REGION POSTALCODE COUNTRY LABEL)) {
         $template =~ s/\@\@\@$field.NAME\@\@\@/$name.$index.VALUE.$field/g;
         my $value = exists($r_data->[$index]{VALUE}{$field})?ow::htmltext::str2html($r_data->[$index]{VALUE}{$field}):'';
         $template =~ s/\@\@\@$field.VALUE\@\@\@/$value/;
      }
      my $pref = qq|<input type="radio" name="$name.PREF" value="$index" |.(exists($r_data->[$index]{TYPES})?exists($r_data->[$index]{TYPES}{PREF})?'checked':():()).qq|>|;
      $template =~ s/\@\@\@PREF\@\@\@/$pref/;
      my $delete;
      if (@{$r_data} > 1) {
         $delete = iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|);
      }
      $template =~ s/\@\@\@DELETE\@\@\@/$delete/;
      $template =~ s/\@\@\@LABEL.INDEX\@\@\@/$index/g;
      # TYPES
      foreach my $type (keys %typemap) {
         $template =~ s/\@\@\@$type.NAME\@\@\@/$name.$index.TYPE.$type/g;
         my $checked = exists($r_data->[$index]{TYPES})?exists($r_data->[$index]{TYPES}{$type})?'checked':'':'';
         $template =~ s/\@\@\@$type.VALUE\@\@\@/$checked/g;
      }
      # GROUP
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_ADR ##################################


########## ADDREDITFORM_BDAY #####################################
sub addreditform_BDAY {
   my ($name, $r_data) = @_;
   my $htmlout;
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = applystyle(readtemplate("addreditform_BDAY.template").
                                readtemplate("bdaypopup.js"));
      # SPECIAL
      my $calpopup = iconlink("cal-popup.gif", $lang_text{'calendar'}, qq|href="javascript:{;}" onClick="calPopup(this,'bdaycalpopupDiv',50,0,'editForm',null);"|);
      $template =~ s/\@\@\@BDAYCALPOPUP\@\@\@/$calpopup/;

      # replace @@@ labels with $lang vars in bdaycalpopup javascript
      my $langlabel = qq|'$lang_wday{0}','$lang_wday{1}','$lang_wday{2}','$lang_wday{3}','$lang_wday{4}','$lang_wday{5}','$lang_wday{6}'|;
      $template =~ s/\@\@\@WDAY_ARRAY\@\@\@/$langlabel/;
      $langlabel = qq|'$lang_order{1}','$lang_order{2}','$lang_order{3}','$lang_order{4}','$lang_order{5}'|;
      $template =~ s/\@\@\@WORDER_ARRAY\@\@\@/$langlabel/;
      $langlabel = qq|'$lang_wday_abbrev{0}','$lang_wday_abbrev{1}','$lang_wday_abbrev{2}','$lang_wday_abbrev{3}','$lang_wday_abbrev{4}','$lang_wday_abbrev{5}','$lang_wday_abbrev{6}'|;
      $template =~ s/\@\@\@WDAYABBREV_ARRAY\@\@\@/$langlabel/;
      $langlabel = qq|'$lang_month{1}','$lang_month{2}','$lang_month{3}','$lang_month{4}','$lang_month{5}','$lang_month{6}','$lang_month{7}','$lang_month{8}','$lang_month{9}','$lang_month{10}','$lang_month{11}','$lang_month{12}'|;
      $template =~ s/\@\@\@WMONTH_ARRAY\@\@\@/$langlabel/;
      $template =~ s/\@\@\@WSTART\@\@\@/$prefs{'calendar_weekstart'}/g;
      $template =~ s/\@\@\@TODAY\@\@\@/$lang_text{'today'}/g;

      # VALUE
      if (ref $r_data->[$index]{VALUE} ne 'HASH') {
         # BDAY is blank (a new contact)
         $r_data->[$index]{VALUE} = { DAY => '',
                                      MONTH => '',
                                      YEAR => '' }
      }
      $r_data->[$index]{VALUE}{AGE} = addreditform_BDAY2AGE($r_data->[$index]{VALUE}{YEAR}, $r_data->[$index]{VALUE}{MONTH}, $r_data->[$index]{VALUE}{DAY});
      foreach my $fieldname (qw(DAY MONTH YEAR AGE)) {
         $template =~ s/\@\@\@$fieldname.NAME\@\@\@/$name.$index.VALUE.$fieldname/g;
         my $escapedvalue = ow::htmltext::str2html($r_data->[$index]{VALUE}{$fieldname});
         $template =~ s/\@\@\@$fieldname.VALUE\@\@\@/$escapedvalue/;
      }
      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);
      $htmlout .= $template;
   }
   return $htmlout;
}
########## END ADDREDITFORM_BDAY #################################


########## ADDREDITFORM_BDAY2AGE #################################
sub addreditform_BDAY2AGE() {
   my ($bdayyear,$bdaymonth,$bdayday) = @_;

   my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($currentyear, $currentmonth, $currentday)=(ow::datetime::seconds2array($localtime))[5,4,3];
   $currentyear+=1900; $currentmonth++;

   my $age = 0;
   if ($bdayyear ne '') {
      $age = $currentyear - $bdayyear;
      if ($bdaymonth ne '') {
         if ($currentmonth < $bdaymonth) {
            $age--; # birthday hasn't happened yet
         } elsif ($bdaymonth == $currentmonth && $bdayday ne '' && $currentday < $bdayday) {
            $age--; # birthday hasn't happened yet
         }
      }
   }
   if ($age < 0) {
      $age = 0;
   }
   return $age?$age:'';
}
########## END ADDREDITFORM_BDAY2AGE #############################


########## ADDREDITFORM_SOUND ####################################
sub addreditform_SOUND {
   # SOUND is always processed after FN because of the order defined in
   # %htmloutput. FN contains @@@SOUND@@@, which will be replaced with
   # links to the actual sound files. FN is always defined.
   my ($name, $r_data, $r_vcardhtml) = @_;
   my $soundhtml;
   for(my $index=0;$index<@{$r_data};$index++) {
      my $inputfields = hidden(-name=>"$name.$index.TYPE", -default=>[map {$_} keys %{$r_data->[$index]{TYPES}}], -override=>1).
                        hidden(-name=>"$name.$index.VALUE", -default=>$r_data->[$index]{VALUE}, -override=>1).
                        hidden(-name=>"$name.$index.GROUP", -default=>$r_data->[$index]{GROUP}, -override=>1);
      # take the first type as the filetype (this has a chance of being wrong, but 99.9% will be right)
      my $type = (grep {!m/(?:BASE64|URI)/} keys %{$r_data->[$index]{TYPES}})[0];
      if (exists $r_data->[$index]{TYPES}{URI}) {
         my $uri=$r_data->[$index]{VALUE}; $uri=~s/\%THISSESSION\%/$thissession/;	# replace '%THISSESSION%' with $thissession for OWM link
         my $escapedvalue = ow::htmltext::str2html($uri);
         if ($escapedvalue =~ m#^(?:https?|ftp|mms|nntp|news|gopher|telnet|file)://#i) {
            $soundhtml .= iconlink("abooksound.gif", "$lang_text{'abook_editform_playsound'}", qq|href="$escapedvalue" target="_new"|)."&nbsp;".
                          iconlink("cal-delete.gif", "$lang_text{'abook_editform_deletesound'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|).
                          "$inputfields&nbsp;&nbsp;&nbsp;&nbsp;";
         } else {
            $soundhtml .= qq|<span class="smalltext">$escapedvalue$inputfields&nbsp;&nbsp;&nbsp;&nbsp;</span>|; # phonetic pronunciation
         }
      } elsif (exists $r_data->[$index]{TYPES}{BASE64}) {
         $soundhtml .= iconlink("abooksound.gif", "$lang_text{'abook_editform_playsound'}", qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrviewatt&amp;sessionid=$thissession&amp;file=$r_data->[$index]{VALUE}&amp;type=$type" target="_new"|)."&nbsp;".
                       iconlink("cal-delete.gif", "$lang_text{'abook_editform_deletesound'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|).
                       "$inputfields&nbsp;&nbsp;&nbsp;&nbsp;";
      }
   }
   $r_vcardhtml->{FN} =~ s/\@\@\@SOUND\@\@\@/$soundhtml/;
   return undef;
}
########## END ADDREDITFORM_SOUND ################################


########## ADDREDITFORM_PHOTO ####################################
sub addreditform_PHOTO {
   my ($name, $r_data, $r_vcardhtml) = @_;
   my $htmlout;
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = applystyle(readtemplate("addreditform_PHOTO.template"));

      # take the first type as the filetype (this has a chance of being wrong, but 99.9% will be right)
      my $type = (grep {!m/(?:BASE64|URI)/} keys %{$r_data->[$index]{TYPES}})[0];

      my $photo;
      if (exists $r_data->[$index]{TYPES}{URI}) {
         my $uri=$r_data->[$index]{VALUE}; $uri=~s/\%THISSESSION\%/$thissession/;	# replace '%THISSESSION%' with $thissession for OWM link
         my $escapedvalue = ow::htmltext::str2html($uri);
         if ($type =~ m/^(?:GIF|JPE?G|PNG)$/) {
            $photo = qq|<td><a href="$escapedvalue" target="_new"><img src="$escapedvalue" border="1"></a></td>|; # display inline and as a link
         } else {
            $photo = qq|<td width="52" height="52" bgcolor="#000000" align="center">|.
                     qq|<table cellspacing="0" cellpadding="0" border="0"><tr><td align="center" width="50" height="50" bgcolor=$style{'tablerow_light'}>|.
                     iconlink("cal-link.gif", "$escapedvalue", qq|href="$escapedvalue" target="_new"|). # just a url link
                     qq|</td></tr></table></td>|;
         }
      } elsif (exists $r_data->[$index]{TYPES}{BASE64}) {
         $photo = qq|<td><a href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrviewatt&amp;sessionid=$thissession&amp;file=$r_data->[$index]{VALUE}&amp;type=$type" target="_new">|.
                  qq|<img src="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrviewatt&amp;sessionid=$thissession&amp;file=$r_data->[$index]{VALUE}&amp;type=$type" border="1"></a></td>|;
      } else {
         $template = '';
      }
      $template =~ s/\@\@\@PHOTO\@\@\@/$photo/;
      my $delete = qq|&nbsp;&nbsp;|.iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|);
      $template =~ s/\@\@\@PHOTO.DELETE\@\@\@/$delete/;

      my $photovalue = hidden(-name=>"$name.$index.VALUE", -default=>$r_data->[$index]{VALUE}, -override=>1);
      $template =~ s/\@\@\@PHOTO.VALUE\@\@\@/$photovalue/;
      my $phototypes = hidden(-name=>"$name.$index.TYPE", -default=>[map {$_} keys %{$r_data->[$index]{TYPES}}], -override=>1);
      $template =~ s/\@\@\@PHOTO.TYPES\@\@\@/$phototypes/;
      my $photogroup = hidden(-name=>"$name.$index.GROUP", -default=>$r_data->[$index]{GROUP}, -override=>1);
      $template =~ s/\@\@\@PHOTO.GROUP\@\@\@/$photogroup/;

      $htmlout .= $template;
   }

   return $htmlout;
}
########## END ADDREDITFORM_PHOTO ################################


########## ADDREDITFORM_X-OWM-CUSTOM #############################
sub addreditform_X_OWM_CUSTOM {
   my ($name, $r_data) = @_;
   my $htmlout;
   my $X_OWM_CUSTOMtemplate = applystyle(readtemplate('addreditform_X-OWM-CUSTOM.template'));
   for(my $index=0;$index<@{$r_data};$index++) {
      my $template = $X_OWM_CUSTOMtemplate;
      if (ref $r_data->[$index]{VALUE} ne 'HASH') { # X_OWM_CUSTOM is blank (a new contact)
         $r_data->[$index]{VALUE} = { CUSTOMNAME => '' }
      }
      foreach my $field (qw(CUSTOMNAME)) {
         # VALUE
         my $valuelabel = $lang_text{"abook_editform_valuelabel_$field"} || $lang_text{'abook_editform_valuelabel'};
         $template =~ s/\@\@\@$field.VALUELABEL\@\@\@/$valuelabel/;
         my $valuehtml = textfield(-name=>"X-OWM-CUSTOM.$index.VALUE.$field", -default=>$r_data->[$index]{VALUE}{$field}, -size=>"30", -override=>"1", -class=>"mono");
         $template =~ s/\@\@\@$field.VALUE\@\@\@/$valuehtml/;
      }
      my $delete;
      if (@{$r_data} > 1) {
         $delete = iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='$name,$index,-1'; document.editForm.submit();"|);
      }
      $template =~ s/\@\@\@DELETE\@\@\@/$delete/;
      addreditform_GENERIC_TYPES($name, $r_data, $index, \$template);
      addreditform_GENERIC_GROUP($name, $r_data, $index, \$template);

      # CUSTOMVALUES.VALUE
      my $valuehtml = '';
      my $valuelabel = $lang_text{"abook_editform_valuelabel_CUSTOMVALUES"} || $lang_text{'abook_editform_valuelabel'};
      $r_data->[$index]{VALUE}{CUSTOMVALUES} = [''] if (ref($r_data->[$index]{VALUE}{CUSTOMVALUES}) ne 'ARRAY');
      for(my $pos=0;$pos<@{$r_data->[$index]{VALUE}{CUSTOMVALUES}};$pos++) {
         $template =~ s/\@\@\@ADDCUSTOMVALUES\@\@\@/X-OWM-CUSTOM.$index.VALUE.CUSTOMVALUES/;
         if (ref($r_data->[$index]{VALUE}{CUSTOMVALUES}[$pos]) eq 'HASH') {
            # a new field was added (adds as {VALUE => ''} by default, which in this case we don't want)
            $r_data->[$index]{VALUE}{CUSTOMVALUES}[$pos] = '';
         }
         $valuehtml .= qq|<tr><td>|.
                       textfield(-name=>"X-OWM-CUSTOM.$index.VALUE.CUSTOMVALUES.$pos", -default=>$r_data->[$index]{VALUE}{CUSTOMVALUES}[$pos], -size=>"30", -override=>"1", -class=>"mono");
         if (@{$r_data->[$index]{VALUE}{CUSTOMVALUES}} > 1) {
            $valuehtml .= qq|&nbsp;&nbsp;|.
                          iconlink("cal-delete.gif", "$lang_text{'delete'}", qq|href="javascript:document.editForm.formchange.value='X-OWM-CUSTOM.$index.VALUE.CUSTOMVALUES,$pos,-1'; document.editForm.submit();"|);
         }
         $valuehtml .= qq|</td></tr>\n|;
         $valuehtml .= $pos==$#{$r_data->[$index]{VALUE}{CUSTOMVALUES}}?qq|<tr><td class="smalltext">$valuelabel</td></tr>\n|:qq|<tr><td></td></tr>\n|;
      }
      $template =~ s/\@\@\@CUSTOMVALUES.VALUE\@\@\@/$valuehtml/;

      $htmlout .= $template;
   }

   return $htmlout;
}
########## END ADDREDITFORM_X-OWM-CUSTOM #########################


########## ADDREDITFORM_MERGE_NESTED #############################
sub addreditform_merge_nested {
   my ($r_target, $r_source) = @_;
   # merges source data structure into target. Allows multiple nests to
   # be processed onto the same target - filling the array slots instead
   # of overwriting them with undef values.
   # Needed mostly for the ORG and X-OWM-CUSTOM datatypes that have
   # nested arrays in their data structure.
   # Be careful if you're changing this, its recursive and infinite!

#   print "<pre>SOURCE DUMP PRE:\n".Dumper($r_source)."</pre>\n";
#   print "<pre>TARGET DUMP PRE:\n".Dumper($r_target)."</pre>\n";

   if (ref($r_source) eq 'HASH') {
      foreach my $key (keys %{$r_source}) {
         if (!exists $r_target->{$key}) {
            $r_target->{$key} = $r_source->{$key};
         }
         if (ref($r_source->{$key}) eq 'HASH') {
            addreditform_merge_nested(\%{$r_target->{$key}}, \%{$r_source->{$key}});
         } elsif (ref($r_source->{$key}) eq 'ARRAY') {
            addreditform_merge_nested(\@{$r_target->{$key}}, \@{$r_source->{$key}});
         } elsif (ref($r_source->{$key}) eq 'SCALAR') {
            addreditform_merge_nested(\${$r_target->{$key}}, \${$r_source->{$key}});
         } else {
            $r_target->{$key} = $r_source->{$key};
         }
      }
   } elsif (ref($r_source) eq 'ARRAY') {
      for(my $pos=0;$pos<@{$r_source};$pos++) {
         if (defined $r_source->[$pos]) {
            if (!defined $r_target->[$pos]) { # no danger of array overwrite
               $r_target->[$pos] = $r_source->[$pos];
            }
         } else {
            if (defined $r_target->[$pos]) {
               next; # preserve the value in the target
            } else {
               $r_target->[$pos] = $r_source->[$pos];
            }
         }
         if (ref($r_source->[$pos]) eq 'HASH') {
            addreditform_merge_nested(\%{$r_target->[$pos]}, \%{$r_source->[$pos]});
         } elsif (ref($r_source->[$pos]) eq 'ARRAY') {
            addreditform_merge_nested(\@{$r_target->[$pos]}, \@{$r_source->[$pos]});
         } elsif (ref($r_source->[$pos]) eq 'SCALAR') {
            addreditform_merge_nested(\${$r_target->[$pos]}, \${$r_source->[$pos]});
         } else {
            $r_target->[$pos] = $r_source->[$pos];
         }
      }
   } elsif (ref($r_source) eq 'SCALAR') {
      if (defined ${$r_source}) {
         ${$r_target} = ${$r_source};
      }
   } else {
#      print "<pre>SOURCE NOT H.A.S:\n".Dumper($r_source)."</pre>\n";
#      print "<pre>TARGET NOT H.A.S:\n".Dumper($r_target)."</pre>\n";
      $r_target = $r_source;
   }

#   print "<pre>SOURCE DUMP POST:\n".Dumper($r_source)."</pre>\n";
#   print "<pre>TARGET DUMP POST:\n".Dumper($r_target)."</pre>\n";
}
########## END ADDREDITFORM_MERGE_NESTED #########################


########## ADDREDITFORM_TO_VCARD #################################
sub addreditform_to_vcard {
   # prepare to convert the character set if needed
   my $convfrom = param('convfrom');
   my $convto = param('X-OWM-CHARSET.0.VALUE');

   print "<pre>INSIDE addreditform_to_vcard:\n</pre>" if $addrdebug;

   # we need to force the FN value into N to make the card valid if its a group.
   if (param('editgroupform')) {
      param(-name=>'N.0.VALUE.GIVENNAME', -value=>ucfirst($lang_text{'group'}));
      param(-name=>'N.0.VALUE.FAMILYNAME', -value=>param('FN.0.VALUE'));
   }

   # load the information coming from the html form
   # and return it as a vcard hash structure.
   my $formdata = ();
   my $xowmuid = param('rootxowmuid');
   my @form = param(); # list of form values
   foreach my $field (sort @form) {
      my ($propertyname,$index,$datatype,$nested) = $field =~ m/^(\S+?)\.(\d+)\.(VALUE|GROUP|TYPE)\.?(\S+)?$/;

      # catch PREF values - they are the only exception to the
      # PROPERTYNAME.INDEX.DATATYPE.NESTED1.NESTED2 rule since
      # PREFs are like EMAIL.PREF or TEL.PREF
      if ($propertyname eq '') {
         ($propertyname, $index) = $field =~ m/^(\S+?)\.(PREF)$/;
         if ($index eq 'PREF') {
            $index = param("$propertyname.PREF");
            $formdata->{$xowmuid}{$propertyname}[$index]{TYPES}{'PREF'} = 'TYPE';
         }
         next;
      }

      # a non-vcard form element (like action)?
      next unless defined $datatype;

      my $value = param($field);

      if ($datatype eq 'VALUE') {
         if (defined $nested) {
            # create the nested data structure
            my %nest;
            my @nestkeys = split(/\./,$nested); # ORG.0.VALUE.ORGANIZATIONALUNITS.0
            for(my $pos=$#nestkeys;$pos>=0;$pos--) { # start from the end of nestkeys
               if ($nestkeys[$pos] =~ m/^\d+$/) { # this is an array nest
                  if (defined $nestkeys[$pos+1]) { # there is a next one
                     # this one should ref to the next one
                     $nest{$nestkeys[$pos]}[$nestkeys[$pos]] = $nest{$nestkeys[$pos+1]};
                     delete $nest{$nestkeys[$pos+1]};
                  } else { # there is no next one - assign value
                     $nest{$nestkeys[$pos]}[$nestkeys[$pos]] = (iconv($convfrom, $convto, $value))[0];
                  }
               } else { # this is a hash nest
                  if (defined $nestkeys[$pos+1]) { # there is a next one
                     $nest{$nestkeys[$pos]}{$nestkeys[$pos]} = $nest{$nestkeys[$pos+1]};
                     delete $nest{$nestkeys[$pos+1]};
                  } else { # there is no next one - assign value
                     $nest{$nestkeys[$pos]}{$nestkeys[$pos]} = (iconv($convfrom, $convto, $value))[0];
                  }
               }
               if ($pos == 0) {
                  %nest = %{$nest{$nestkeys[0]}};
                  #print "<pre>addreditform NESTKEYS:\n" . Dumper(\@nestkeys) . "</pre>";
                  #print "<pre>addreditform NEST:\n" . Dumper(\%nest) . "</pre>";
                  addreditform_merge_nested(\%{$formdata->{$xowmuid}{$propertyname}[$index]{VALUE}}, \%nest);
               }
            }
         } else {
            $formdata->{$xowmuid}{$propertyname}[$index]{VALUE} = (iconv($convfrom, $convto, $value))[0];
         }
         #print "<pre>$field VALUE IS: " . Dumper($value) . "</pre>";
      } elsif ($datatype eq 'GROUP') {
         #print "<pre>$field GROUP IS: " . Dumper($value) . "</pre>";
         $formdata->{$xowmuid}{$propertyname}[$index]{GROUP} = (iconv($convfrom, $convto, $value))[0];
      } elsif ($datatype eq 'TYPE') {
         my @types = param($field);
         foreach my $type (@types) {
            #print "<pre>$field TYPE: $type</pre>";
            $formdata->{$xowmuid}{$propertyname}[$index]{TYPES}{(iconv($convfrom, $convto, $type))[0]} = 'TYPE';
         }
      } else {
         openwebmailerror(__FILE__, __LINE__, "datatype $datatype is not supported");
      }
   }

   # process form changes
   if (param('formchange')) {
      my ($formchange,$formchangeindex,$formchangeamount) = split(/,/,param('formchange')); # add (EMAIL,0,1) or remove (EMAIL,5,-1)
      print "<pre>FORMCHANGE REQUEST: $formchange,$formchangeindex,$formchangeamount</pre>\n" if $addrdebug;
      if ($formchangeamount>0 || $formchangeamount<0) {
         # figure out the form target
         my $formchangetarget = \%{$formdata->{$xowmuid}};
         my @target = split(/\./,$formchange);

         for(my $pos=0;$pos<@target;$pos++) {
            if ($target[$pos] =~ m/^\d+$/) { # this one is an array
               if ($pos eq $#target) { # this is the last one - must always be array
                  $formchangetarget = \@{$formchangetarget->[$target[$pos]]};
               } else {
                  if (ref($formchangetarget->[$target[$pos]]) eq 'ARRAY') {
                     $formchangetarget = \@{$formchangetarget->[$target[$pos]]};
                  } else {
                     $formchangetarget = \%{$formchangetarget->[$target[$pos]]};
                  }
               }
            } else { # (assume) this one is a hash
               if ($pos eq $#target) { # this is the last one - must always be array
                  $formchangetarget = \@{$formchangetarget->{$target[$pos]}};
               } else {
                  if (ref($formchangetarget->{$target[$pos]}) eq 'ARRAY') {
                     $formchangetarget = \@{$formchangetarget->{$target[$pos]}};
                  } else {
                     $formchangetarget = \%{$formchangetarget->{$target[$pos]}};
                  }
               }
            }
         }

         if ($formchangeamount>0) {
            push(@{$formchangetarget},{VALUE => ''}); # add an item
         } else {
            splice(@{$formchangetarget},$formchangeindex,1); # remove an item
         }
      }
   }

   print "EXITING addreditform_to_vcard:\n" if $addrdebug;
   return($formdata);
}
########## END ADDREDITFORM_TO_VCARD #############################


########## ADDREDIT ##############################################
sub addredit {
   my $composecharset = param('X-OWM-CHARSET.0.VALUE');

   my $formchange = param('formchange');

   my $editformcaller = safefoldername(ow::tool::unescapeURL(param('editformcaller')));

   print header() if $addrdebug;
   if ($formchange ne '') {
      #################################################
      # not ready to process yet, just modifying form #
      #################################################
      print "<pre>GOING TO THE ADDREDITFORM via FORMCHANGE\n</pre>" if $addrdebug;
      addreditform();
   } elsif (defined param('EDITFORMUPLOAD') ||		# user press 'add' button
                    param('webdisksel') ) {		# file selected from webdisk

      #################################################
      # not ready to process yet, uploading something #
      #################################################

      my $uploadtype = param('UPLOAD.FILE.TYPE');
      if ($uploadtype !~ m/(?:PHOTO|SOUND|LOGO|KEY|AGENT)/) { # someone is playing around
         openwebmailerror(__FILE__, __LINE__, "$uploadtype $lang_err{'func_notsupported'}!");
      }

      # list of extensions we will accept
      my %approvedext = ( 'PHOTO' => { # according to vCard RFC
                                       'GIF' => 'Graphics Interchange Format',
                                       'CGM' => 'ISO Computer Graphics Metafile',
                                       'WMF' => 'Microsoft Windows Metafile',
                                       'BMP' => 'Microsoft Windows Bitmap',
                                       'MET' => 'IBM PM Metafile',
                                       'PMB' => 'IBM PM Bitmap',
                                       'DIB' => 'MS Windows DIB',
                                       'PICT' => 'Apple Picture Format',
                                       'TIFF' => 'Tagged Image File Format',
                                       'PS' => 'Adobe Postscript Format',
                                       'PDF' => 'Adobe Page Description Format',
                                       'JPEG' => 'ISO JPEG Format',
                                       'MPEG' => 'ISO MPEG Format',
                                       'MPEG2' => 'ISO MPEG Version 2 Format',
                                       'AVI' => 'Intel AVI Format',
                                       'QTIME' => 'Apple Quicktime Format',
                                       # approved by OWM (movies for pictures are fun!)
                                       'PIC' => 'Apple Picture Format',
                                       'TIF' => 'Tagged Image File Format',
                                       'JPG' => 'ISO JPEG Format',
                                       'MPG' => 'ISO MPEG Format',
                                       'MPG2' => 'ISO MPEG Version 2 Format',
                                       'MOV' => 'Apple Quicktime Format',
                                       'SWF' => 'Macromedia Shockwave Flash',
                                       'PNG' => 'Portable Network Graphics',
                                     },
                          'SOUND' => { # according to vCard RFC
                                       'WAVE' => 'Microsoft WAVE Format',
                                       'PCM' => 'MIME basic audio type',
                                       'AIFF' => 'AIFF Format',
                                       # approved by OWM
                                       'WAV' => 'Microsoft WAVE Format',
                                       'AIFC' => 'AIFF Format',
                                       'AIF' => 'AIFF Format',
                                       'AU' => 'Sun Audio Format',
                                     },
                            'KEY' => { # according to vCard RFC
                                       'X509' => 'X.509 Public Key Certificate',
                                       'PGP' => 'IETF Pretty Good Privacy Key',
                                       # approved by OWM
                                       'GPG' => 'GNU Privacy Guard',
                                     },
                           'LOGO' => { # according to vCard RFC
                                       'GIF' => 'Graphics Interchange Format',
                                       'CGM' => 'ISO Computer Graphics Metafile',
                                       'WMF' => 'Microsoft Windows Metafile',
                                       'BMP' => 'Microsoft Windows Bitmap',
                                       'MET' => 'IBM PM Metafile',
                                       'PMB' => 'IBM PM Bitmap',
                                       'DIB' => 'MS Windows DIB',
                                       'PICT' => 'Apple Picture Format',
                                       'TIFF' => 'Tagged Image File Format',
                                       'PS' => 'Adobe Postscript Format',
                                       'PDF' => 'Adobe Page Description Format',
                                       'JPEG' => 'ISO JPEG Format',
                                       'MPEG' => 'ISO MPEG Format',
                                       'MPEG2' => 'ISO MPEG Version 2 Format',
                                       'AVI' => 'Intel AVI Format',
                                       'QTIME' => 'Apple Quicktime Format',
                                       # approved by OWM
                                       'PIC' => 'Apple Picture Format',
                                       'TIF' => 'Tagged Image File Format',
                                       'JPG' => 'ISO JPEG Format',
                                       'MPG' => 'ISO MPEG Format',
                                       'MPG2' => 'ISO MPEG Version 2 Format',
                                       'MOV' => 'Apple Quicktime Format',
                                       'SWF' => 'Macromedia Shockwave Flash',
                                       'PNG' => 'Portable Network Graphics',
                                     },
                          'AGENT' => { 'VCF' => 'Versit Card Format' },
                        );

      my ($attfiles_totalsize, $r_attfiles) = getattfilesinfo();

      my $uri = param('UPLOAD.URI') || '';
      $uri=~s/\Q$thissession\E/\%THISSESSION\%/;	# remove $thissession from uri if it is a OWM link

      my $attachment = param('UPLOAD.FILE') || '';
      my $webdisksel = param('webdisksel') || '';

      my ($attname, $attcontenttype);

      if ($webdisksel || $attachment) {
         if ($attachment) {
            # Convert :: back to the ' like it should be.
            $attname = $attachment;
            $attname =~ s/::/'/g;
            # Trim the path info from the filename
            if ($composecharset eq 'big5' || $composecharset eq 'gb2312') {
               $attname = ow::tool::zh_dospath2fname($attname); # dos path
            } else {
               $attname =~ s|^.*\\||;   # dos path
            }
            $attname =~ s|^.*/||;       # unix path
            $attname =~ s|^.*:||;       # mac path and dos drive

            if (defined uploadInfo($attachment)) {
               $attcontenttype = ${uploadInfo($attachment)}{'Content-Type'} || 'application/octet-stream';
            } else {
               $attcontenttype = 'application/octet-stream';
            }

            if ($attcontenttype eq 'application/octet-stream') {
               # browser didn't tell us. Can we figure it out?
               my $ext = uc(ow::tool::contenttype2ext(ow::tool::ext2contenttype($attname)));
               if (exists $approvedext{$uploadtype}{$ext}) {
                  $attcontenttype = ow::tool::ext2contenttype($attname);
               }
            }
         } elsif ($webdisksel && $config{'enable_webdisk'}) {
            my $webdiskrootdir=ow::tool::untaint($homedir.absolute_vpath("/", $config{'webdisk_rootpath'}));
            my $vpath=absolute_vpath('/', $webdisksel);
            my $vpathstr=f2u($vpath);
            my $err=verify_vpath($webdiskrootdir, $vpath);
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'access_denied'} ($vpathstr: $err)") if ($err);
            openwebmailerror(__FILE__, __LINE__, "$lang_text{'file'} $vpathstr $lang_err{'doesnt_exist'}") if (!-f "$webdiskrootdir/$vpath");

            $attachment=do { local *FH };
            sysopen($attachment, "$webdiskrootdir/$vpath", O_RDONLY) or
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $lang_text{'webdisk'} $vpathstr! ($!)");
            $attname=$vpath; $attname=~s|/$||; $attname=~s|^.*/||;
            $attcontenttype=ow::tool::ext2contenttype($vpath);
         }

         if ($attachment) {
            if ( ($config{'abook_attlimit'}>0) && ( ($attfiles_totalsize + (-s $attachment)) > ($config{'abook_attlimit'}*1024) ) ) {
               close($attachment);
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'att_overlimit'} $config{'abook_attlimit'} $lang_sizes{'kb'}!");
            }
            my $attserial = time() . join("",map { int(rand(10)) }(1..9));
            sysopen(ATTFILE, "$config{'ow_sessionsdir'}/$thissession-vcard$attserial", O_WRONLY|O_TRUNC|O_CREAT);
            binmode ATTFILE; # to ensure images don't corrupt
            my ($buff, $attsize);
            while (read($attachment, $buff, 400*57)) {
               $attsize += length($buff);
               print ATTFILE $buff;
            }
            close ATTFILE;
            close($attachment); # close tmpfile created by CGI.pm

            # Check that agents only contain a single contact and are valid file
            if ($uploadtype eq 'AGENT') {
               my $test = readadrbook("$config{'ow_sessionsdir'}/$thissession-vcard$attserial", undef, undef);
               if (keys %{$test} > 1) {
                  openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_agent_one_contact'}");
               }
            }

            $attfiles_totalsize+=$attsize;

            my $uploadextension = uc(ow::tool::contenttype2ext($attcontenttype));

            if (exists $approvedext{$uploadtype}{$uploadextension}) {
               # what is the index number for this new upload?
               my @form = param();
               my $newindex = 0;
               foreach my $field ( sort @form ) {
                  my ($propertyname,$index,$datatype,$nestedhashes) = $field =~ m/^(\S+?)\.(\d+)\.(VALUE|GROUP|TYPE)\.?(\S+)?$/;
                  $newindex++ if $index == $newindex && $propertyname eq $uploadtype;
               }
               # add this value to the param list for later processing
               param(-name=>"$uploadtype.$newindex.VALUE", -value=>$attserial);
               if ($uploadtype eq 'AGENT') {
                  param(-name=>"$uploadtype.$newindex.TYPE", -value =>[$uploadextension, 'VCARD']);
               } else {
                  param(-name=>"$uploadtype.$newindex.TYPE", -value =>[$uploadextension, 'BASE64']);
               }
            } else {
               unlink("$config{'ow_sessionsdir'}/$thissession-vcard$attserial");
               openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_ext_notsupported'} $uploadtype ($attcontenttype $uploadextension)!");
            }
         }
      } elsif ($uri) {
         # what is the index number for this new upload?
         my @form = param();
         my $newindex = 0;
         # which index is this upload going to be of this type? i.e. - is this picture #2,#3,etc?
         foreach my $field ( sort @form ) {
            my ($propertyname,$index,$datatype,$nestedhashes) = $field =~ m/^(\S+?)\.(\d+)\.(VALUE|GROUP|TYPE)\.?(\S+)?$/;
            $newindex++ if $index == $newindex && $propertyname eq $uploadtype;
         }
         # url may be something like http://www.site.com/pic.pl?number=5
         # in which case we will have no idea what the extension is - so just blindly accept the value
         param(-name=>"$uploadtype.$newindex.VALUE", -value=>$uri);
         # can we figure out the extension?
         my $uploadextension = uc(ow::tool::contenttype2ext(ow::tool::ext2contenttype(lc($uri))));
         if (exists $approvedext{$uploadtype}{$uploadextension}) {
            param(-name=>"$uploadtype.$newindex.TYPE", -value =>[$uploadextension, 'URI']);
         } else {
            param(-name=>"$uploadtype.$newindex.TYPE", -value =>['URI']);
         }
      }
      print "GOING TO THE ADDREDITFORM via EDITFORMUPLOAD\n" if $addrdebug;
      addreditform();
   } else {
      ######################################################################
      # Finally, ready to process form data.                               #
      # We're here for one of two possible reasons:                        #
      #  - we want to save the form data to a card. Simple. In this case   #
      #    we are here from addreditform or we are here from quickadd.     #
      #  - we want to access an agent. Before we do so we need to save the #
      #    the data of the card we're currently on.                        #
      ######################################################################
      print header() if $addrdebug;

      my $completevcard;  # will contain all of the data for this card
      my $contact;        # will be a pointer to a level of data in $completevcard

      my $xowmuid = param('rootxowmuid');
      $abookfolder = ow::tool::untaint(safefoldername($abookfolder));

      my $abookfile = abookfolder2file($abookfolder);
      if (is_abookfolder_global($abookfolder) && !is_abookfolder_writable($abookfolder)) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_global_denied'}");
      }

      if ($xowmuid ne '') {
         # read in the completecard
         my %searchterms = ( 'X-OWM-UID' => [ { 'VALUE' => $xowmuid } ] ); # only pull this card
         my %only_return = ();

         print "<pre>addredit XOWMUID is $xowmuid, reading completevcard:\n" if $addrdebug;
         $completevcard = readadrbook($abookfile, (keys %searchterms?\%searchterms:undef), (keys %only_return?\%only_return:undef));
         print "</pre>\n" if $addrdebug;
      }

      if ($addrdebug) { # DEBUG DUMP
         my $outfile = "$config{'ow_sessionsdir'}/DUMP_BEFORE";
         sysopen(FILE, $outfile, O_WRONLY|O_TRUNC|O_CREAT) || openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $outfile ($!)\n");
         print FILE Dumper(\%{$completevcard});
         close FILE || openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $outfile ($!)\n");
      }

      # To access AGENT nested data we will need to know what the targetagent is.
      # Targetagent looks like: <traversedirection>,<agent position(s)>,[<last position accessed>]
      # Traverse direction can be 'access agent'(1) or 'access parent'(-1).
      # Last should only be used if traversedirection is -1 (so we know what card to save the form
      # data to before we traverse to the parent).
      my @targetagent = split(/,/,param('targetagent')); # a map to the target: 1,0,2,0,1
      print "<pre>\n\nTARGETAGENT:\n".Dumper(\@targetagent)."</pre>\n" if $addrdebug;
      my $traversedirection = shift(@targetagent);
      if ($traversedirection == 1) {
         # if we're going into an agent we want to save the level above it
         pop(@targetagent); # so remove the last entry in the targetagent
      }

      my $targetdepth = @targetagent || 0;
      print "<pre>addredit TARGETDEPTH: $targetdepth\nTRAVERSEDIRECTION: $traversedirection\nTARGETAGENT:\n".Dumper(\@targetagent)."</pre>\n" if $addrdebug;

      # Align $contact so it is pointing to the completevcard data we want to modify.
      my $target = \%{$completevcard->{$xowmuid}};
      for(my $depth=1;$depth<=$targetdepth;$depth++) {
         if (exists $target->{AGENT}[$targetagent[$depth-1]]{VALUE}) {
            foreach my $agentxowmuid (keys %{$target->{AGENT}[$targetagent[$depth-1]]{VALUE}}) {
               $target = \%{$target->{AGENT}[$targetagent[$depth-1]]{VALUE}{$agentxowmuid}};
            }
         } else {
            # we're creating a new agent from scratch
            $target->{AGENT}[$targetagent[$depth-1]]{TYPES}{VCARD} = 'TYPE';
            $target = \%{$target->{AGENT}[$targetagent[$depth-1]]{VALUE}{''}};
         }
      }
      $contact->{$xowmuid} = $target;

      print "<pre>addredit CONTACT has been aligned to:\n".Dumper(\%{$contact})."</pre>\n" if $addrdebug;

      # clear out $contact so we can populate it with the form data - keep 'X-OWM-UID'
      foreach my $propertyname (keys %{$contact->{$xowmuid}}) {
         delete $contact->{$xowmuid}{$propertyname} unless ($propertyname eq 'X-OWM-UID');
      }

      print "<pre>addredit CONTACT has been cleaned out to make way for the form data:\n".Dumper(\%{$contact})."</pre>\n" if $addrdebug;

      print "<pre>FORM DUMP:\n".Dump()."\n</pre>\n\n\n" if $addrdebug;

      # populate $contact with the form data
      my $formdata = addreditform_to_vcard();
      foreach my $propertyname (keys %{$formdata->{$xowmuid}}) {
         next if ($propertyname eq 'X-OWM-UID');
         $contact->{$xowmuid}{$propertyname} = $formdata->{$xowmuid}{$propertyname};
      }

      # if we are coming from an editgroupform we need to break EMAIL.0.VALUE
      # into each individual email entry before we write out the card.
      if (param('editgroupform')) {
         my $index = 0;
         foreach my $email (split(/\n/,$contact->{$xowmuid}{EMAIL}[0]{VALUE})) {
            $contact->{$xowmuid}{EMAIL}[$index]{VALUE} = $email;
            $index++;
         }
      }

      print "<pre>addredit CONTACT has been made from the form data:\n".Dumper(\%{$contact})."</pre>\n" if $addrdebug;

      # Convert all BASE64 and VCARD files in the sessions directories to be included in the vcard.
      foreach my $propertyname (qw(PHOTO LOGO SOUND KEY AGENT)) {
         if (exists $contact->{$xowmuid}{$propertyname}) {
            for(my $index=0;$index<@{$contact->{$xowmuid}{$propertyname}};$index++) {
               if (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}) {
                  if (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{BASE64} ||
                      exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{VCARD}) {
                     my $fileserial = $contact->{$xowmuid}{$propertyname}[$index]{VALUE};
                     # make fileserial safe in case someone is getting tricky
                     $fileserial = ow::tool::untaint(safefoldername($fileserial));
                     my $targetfile = "$config{'ow_sessionsdir'}/$thissession-vcard$fileserial";
                     if (exists $contact->{$xowmuid}{$propertyname}[$index]{TYPES}{VCARD}) {
                        $contact->{$xowmuid}{$propertyname}[$index]{VALUE} = readadrbook("$targetfile",undef,undef); # attach vcard file
                     } else {
                        sysopen(FILE, $targetfile, O_RDWR|O_CREAT) || openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_create'} $targetfile ($!)\n");
                        $contact->{$xowmuid}{$propertyname}[$index]{VALUE} = do { local $/; <FILE> }; # attach binary file
                        close FILE || openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $targetfile ($!)\n");
                     }
                     unlink($targetfile);
                  }
               }
            }
         }
      }

      # unbundle the propertynames we bundled previously
      my %unbundlemap = ( 'ADR' => ['LABEL'], 'ORG' => ['TITLE','ROLE'] );
      foreach my $key (keys %unbundlemap) {
         if (exists $contact->{$xowmuid}{$key}) {
            for(my $index=0;$index<@{$contact->{$xowmuid}{$key}};$index++) {
               foreach my $target (@{$unbundlemap{$key}}) {
                  if (exists $contact->{$xowmuid}{$key}[$index]{VALUE}{$target}) {
                     $contact->{$xowmuid}{$target}[$index]{VALUE} = $contact->{$xowmuid}{$key}[$index]{VALUE}{$target};
                     delete $contact->{$xowmuid}{$key}[$index]{VALUE}{$target};
                  }
                  if (exists $contact->{$xowmuid}{$key}[$index]{GROUP}) {
                     $contact->{$xowmuid}{$target}[$index]{GROUP} = $contact->{$xowmuid}{$key}[$index]{GROUP};
                  }
                  if (exists $contact->{$xowmuid}{$key}[$index]{TYPES}) {
                     $contact->{$xowmuid}{$target}[$index]{TYPES} = $contact->{$xowmuid}{$key}[$index]{TYPES};
                  }
                  # special cases
                  if ($target eq 'LABEL') {
                     $contact->{$xowmuid}{$target}[$index]{TYPES}{BASE64} = 'ENCODING';
                  }
               }
            }
         }
      }

      ################################################################################
      # The form has been laid into $contact (and by reference into $completevcard). #
      # Time to output the completecard.                                             #
      ################################################################################

      print "<pre>addredit COMPLETEVCARD after form merged into it:\n".Dumper(\%{$completevcard})."</pre>\n" if $addrdebug;

      # outputvfile will check values and add X-OWM-UID if needed.
      # readvfilesfromstring will make it a hash, double check values,
      # and add any missing propertynames.
      print "<pre>USING OUTPUTVFILE TO VALIDATE THE DATA:\n" if $addrdebug;
      $completevcard = readvfilesfromstring(outputvfile('vcard',$completevcard));
      print "</pre>\n" if $addrdebug;

      print "<pre>XOWMUID before reset is: $xowmuid\n</pre>" if $addrdebug;
      # reset $xowmuid in case outputvfile assigned one because it was blank before.
      # $xowmuid would be blank if we were coming from a new card.
      my $oldxowmuid = $xowmuid;
      foreach my $key (keys %{$completevcard}) {
         $xowmuid = $key;
      }
      if ($oldxowmuid eq '' && param('rootxowmuid') eq '') {
         # we were blank before everywhere - must be our first card.
         # set param to remember in case we are traversing into an agent.
         param(-name=>'rootxowmuid', -value=>$xowmuid, -override=>1);
      }
      print "<pre>XOWMUID reset is now: $xowmuid\n</pre>" if $addrdebug;

      # update the revision time of this card
      update_revision_time(\%{$completevcard->{$xowmuid}{REV}[0]});

      if ($addrdebug) { # DEBUG DUMP
         my $outfile = "$config{'ow_sessionsdir'}/DUMP_AFTER";
         sysopen(FILE, $outfile, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} $outfile ($!)\n");
         print FILE Dumper(\%{$completevcard});
         close FILE || openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $outfile ($!)\n");
         print "<pre>addredit COMPLETEVCARD has been validated and is about to writeout:\n".Dumper(\%{$completevcard})."</pre>\n";
      }

      # load up the entire addressbook...
      my (%searchterms, %only_return) = ();
      print "<pre>LOADING THE COMPLETE BOOK IN ORDER TO SAVE OUT CARD $xowmuid\n" if $addrdebug;
      my $completebook = readadrbook($abookfile, (keys %searchterms?\%searchterms:undef), (keys %only_return?\%only_return:undef));
      print "</pre>\n" if $addrdebug;

      # and overwrite the target card with the new data...
      $completebook->{$xowmuid} = $completevcard->{$xowmuid};

      # and write it out!
      my $writeoutput = outputvfile('vcard',$completebook);
      ow::filelock::lock($abookfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($abookfile));
      sysopen(TARGET, $abookfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} ".f2u($abookfile)." ($!)\n");
      print TARGET $writeoutput;
      close(TARGET) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} ".f2u($abookfile)." ($!)\n");
      ow::filelock::lock($abookfile, LOCK_UN);

      writelog("edit contact - $xowmuid from $abookfolder");
      writehistory("edit contact - $xowmuid from $abookfolder");

      # display
      if ($traversedirection == 1 || $traversedirection == -1) {
         print "<pre>WE'RE TRAVERSING AGENTS - GOING TO THE ADDREDITFORM...\n</pre>" if $addrdebug;
         addreditform(); # continue on to display that targetagent now that this level is saved.
      } else {
         if ($editformcaller eq 'readmessage') {
            print redirect(-location=>"$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;sessionid=$thissession&amp;$webmail_urlparm");
         } else {
            addrlistview();
         }
      }
   }
}
########## END ADDREDIT ##########################################


########## ADDRMOVECOPYDELETE ####################################
sub addrmovecopydelete {
   my $targetfolder = param('destinationabook');
   $targetfolder=ow::tool::unescapeURL($targetfolder);	# just in case the parm is escape because of fscharset support

   return addrlistview() if (param('addrcopyaddresses') && $targetfolder eq 'DELETE');

   # Build a hash of the email addresses user checked and just take the xowmuids
   my %waschecked = ();
   for (ow::tool::str2list(join(",",param('to'))), ow::tool::str2list(param('checkedto')) ) { if ($_ ne '') { $_ =~ s/^(?:.*)%@#//; $waschecked{LIST}{$_} = 1 } };
   for (ow::tool::str2list(join(",",param('cc'))), ow::tool::str2list(param('checkedcc')) ) { if ($_ ne '') { $_ =~ s/^(?:.*)%@#//; $waschecked{LIST}{$_} = 1 } };
   for (ow::tool::str2list(join(",",param('bcc'))), ow::tool::str2list(param('checkedbcc')) ) { if ($_ ne '') { $_ =~ s/^(?:.*)%@#//; $waschecked{LIST}{$_} = 1 } };

   # clear the form so nothing is checked anymore
   param(-name=>"to", -value=>'');
   param(-name=>"cc", -value=>'');
   param(-name=>"bcc", -value=>'');
   param(-name=>"checkedto", -value=>'');
   param(-name=>"checkedcc", -value=>'');
   param(-name=>"checkedbcc", -value=>'');

   # load up the needed source books
   my %allabookfolders;
   if ($abookfolder eq 'ALL') {
      %allabookfolders = map { $_ => abookfolder2file($_) }
                         grep { /^[^.]/ && !/^categories\.cache$/ }
                         get_readable_abookfolders();
   } else {
      $allabookfolders{$abookfolder} = abookfolder2file($abookfolder);
      if (!-f $allabookfolders{$abookfolder}) {
         my $abookfolderstr=f2u($abookfolder);
         my $msg=$lang_err{'abook_doesnt_exist'}; $msg=~s/\@\@\@ADDRESSBOOK\@\@\@/$abookfolderstr/;
         openwebmailerror(__FILE__, __LINE__, $msg);
      }
   }

   # calculate the available free space
   my $availfreespace = $config{'abook_maxsizeallbooks'} - userabookfolders_totalsize();

   # load the destination book
   my ($targetfile, $targetbook, $changedtarget);
   if ($targetfolder ne 'DELETE') {
      $targetfile = abookfolder2file($targetfolder);
      if (!-f $targetfile) {
         my $targetfolderstr=f2u($targetfolder);
         my $msg=$lang_err{'abook_doesnt_exist'}; $msg =~ s/\@\@\@ADDRESSBOOK\@\@\@/$targetfolderstr/;
         openwebmailerror(__FILE__, __LINE__, $msg);
      }
      if (!-w $targetfile) {
         openwebmailerror(__FILE__, __LINE__, "$targetfolder is readonly");	# tung
      }
      $targetbook = readadrbook($targetfile, undef, undef);
      $changedtarget = 0;
   }

   # load the addressbooks and perform the move/copy/delete
   foreach my $abookfolder (keys %allabookfolders) {
      my $sourcefile = ow::tool::untaint($allabookfolders{$abookfolder});
      my $sourcebook = readadrbook($sourcefile, undef, undef);
      my $changedsource = 0;
      foreach my $xowmuid (keys %{$waschecked{LIST}}) {
         if (exists $sourcebook->{$xowmuid}) {
            if (param('addrmoveaddresses')) {
               next if ($sourcefile eq $targetfile); # nothing to do
               if (is_abookfolder_global($abookfolder) && !is_abookfolder_writable($abookfolder)) {
                  openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_global_denied'}");
               }
               if ($targetfolder ne 'DELETE') {
                  $targetbook->{$xowmuid} = $sourcebook->{$xowmuid}; # copy ref
               }
               delete $sourcebook->{$xowmuid};
               writelog("move contact - $xowmuid from $abookfolder to $targetfolder");
               writehistory("move contact - $xowmuid from $abookfolder to $targetfolder");
               $changedsource++; $changedtarget++;
            } elsif (param('addrcopyaddresses')) {
               # generate a new xowmuid foreach one being copied
               my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
               my @chars = ( 'A' .. 'Z', 0 .. 9 );
               my $longrandomstring = join '', map { $chars[rand @chars] } 1..12;
               my $shortrandomstring = join '', map { $chars[rand @chars] } 1..4;
               my $newxowmuid = ($uid_year+1900).sprintf("%02d",($uid_mon+1)).sprintf("%02d",$uid_mday)."-".
                                 sprintf("%02d",$uid_hour).sprintf("%02d",$uid_min).sprintf("%02d",$uid_sec)."-".
                                 $longrandomstring."-".$shortrandomstring;

               if ($sourcefile eq $targetfile) {
                  $sourcebook->{$newxowmuid} = deepcopy($sourcebook->{$xowmuid}); # de-reference and copy
                  $sourcebook->{$newxowmuid}{'X-OWM-UID'}[0]{VALUE} = $newxowmuid;
                  $changedsource++;
               } else {
                  $targetbook->{$newxowmuid} = deepcopy($sourcebook->{$xowmuid}); # de-reference and copy
                  $targetbook->{$newxowmuid}{'X-OWM-UID'}[0]{VALUE} = $newxowmuid;
                  $changedtarget++;
               }
               writelog("copy contact - $xowmuid from $abookfolder to ".param('destinationbook'));
               writehistory("copy contact - $xowmuid from $abookfolder to ".param('destinationbook'));
            }
         }
      }

      # save out the source book IF it was changed
      if ($changedsource) {
         my $writeoutput = outputvfile('vcard',$sourcebook);

         ow::filelock::lock($sourcefile, LOCK_EX|LOCK_NB) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($sourcefile));
         sysopen(TARGET, $sourcefile, O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} ".f2u($sourcefile)." ($!)\n");
         print TARGET $writeoutput;
         close(TARGET) or
            openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} ".f2u($sourcefile)." ($!)\n");
         ow::filelock::lock($sourcefile, LOCK_UN);
      }
   }

   if ($changedtarget && $targetfolder ne 'DELETE') {
      # save out the targetbook
      my $writeoutput = outputvfile('vcard',$targetbook);

      # check for space
      # during a move the size will be exactly the same overall
      # during a copy this may croak - but no information will be lost
      my $writesizekb = length($writeoutput)/1024;
      if (($writesizekb > $availfreespace) || !is_quota_available($writesizekb)) {
         openwebmailerror(__FILE__, __LINE__,"$lang_err{'abook_toobig'} $lang_err{'back'}\n");
      }

      ow::filelock::lock($targetfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($targetfile));
      sysopen(TARGET, $targetfile, O_WRONLY|O_TRUNC|O_CREAT) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} ".f2u($targetfile)." ($!)\n");
      print TARGET $writeoutput;
      close(TARGET) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} ".f2u($targetfile)." ($!)\n");
      ow::filelock::lock($targetfile, LOCK_UN);
   }

   addrlistview();
}
########## END ADDRMOVECOPYDELETE ################################


########## ADDRSHOWCHECKED #######################################
sub addrshowchecked {
   my $listviewmode = param('listviewmode');
   my ($html, $temphtml);

   if ($listviewmode eq 'grabopenerdata') {
      # This is a hack boys and girls. We do this because the list of checked addresses may be very large,
      # and so we need to force submit that list through a POST since it is too long for a GET. It takes
      # about 45 addresses or xowmuids before GET fails. POST has no limit at all. So we pop open this window
      # and grab all of the address information from the window.opener, then resubmit this form so that all
      # the data shows up in our popup window. Don't cry, IT WORKS.
      my $aftergrabmode = param('aftergrabmode');
      print header();
      $html = qq|<html>\n|.
              qq|<head>\n|.
              qq|<title></title>\n|.
              qq|<script language="javascript">\n|.
              qq|<!--\n|.
              qq|function getOpenerData(sourceForm) {\n|.
              qq|   document.grabForm.checkedto.value = window.opener.document.forms[sourceForm].checkedto.value;\n|.
              qq|   document.grabForm.checkedcc.value = window.opener.document.forms[sourceForm].checkedcc.value;\n|.
              qq|   document.grabForm.checkedbcc.value = window.opener.document.forms[sourceForm].checkedbcc.value;\n|.
              qq|   for (var a=1; a<arguments.length; a++) {\n|.
              qq|      var elementName = arguments[a];\n|.
              qq|      for (var i=0;i<window.opener.document.forms[sourceForm].elements.length;i++) {\n|.
              qq|         var e = window.opener.document.forms[sourceForm].elements[i];\n|.
              qq|         if (e.type == 'checkbox') {\n|.
              qq|            if (e.name == elementName && e.checked == 1 && e.value != '') {\n|.
              qq|               document.forms['grabForm'].elements[elementName].value += e.value+',';\n|.
              qq|            }\n|.
              qq|         }\n|.
              qq|      }\n|.
              qq|   }\n|.
              qq|   self.focus();\n|.
              qq|   document.grabForm.submit();\n|.
              qq|}\n|.
              qq|//-->\n|.
              qq|</script>\n|.
              qq|</head>\n|.
              qq|<body onLoad=getOpenerData('contactsForm','to','cc','bcc');>\n|.
              start_form(-name=>'grabForm',
                         -action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl").
              ow::tool::hiddens(action=>'addrshowchecked',
                                sessionid=>$thissession,
                                listviewmode=>$aftergrabmode,
                                # javascript will populate these before submit
                                # from values in the contactsForm
                                checkedto=>'',
                                checkedcc=>'',
                                checkedbcc=>'',
                                to=>'',
                                cc=>'',
                                bcc=>'',
                                ).
              end_form().
              qq|\n</body>\n</html>|;
      print $html;
      return 1;
   } else {
      my %waschecked = ();

      # commence with the html
      $html = applystyle(readtemplate("addrshowchecked.template"));

      my @bgcolor = ($style{"tablerow_dark"}, $style{"tablerow_light"});
      my $colornum = 0;

      if ($listviewmode eq 'export') {
         # Our list of checked addresses is actually a list of checked xowmuids
         # Merge them into one big hash
         for (ow::tool::str2list(join(",",param('to'))), ow::tool::str2list(param('checkedto')) ) { $waschecked{$_} = 1 if ($_ ne '') };
         for (ow::tool::str2list(join(",",param('cc'))), ow::tool::str2list(param('checkedcc')) ) { $waschecked{$_} = 1 if ($_ ne '') };
         for (ow::tool::str2list(join(",",param('bcc'))), ow::tool::str2list(param('checkedbcc')) ) { $waschecked{$_} = 1 if ($_ ne '') };

         # load the addresses - only the required information
         my %addresses=();
         my %searchterms = ();
         my %only_return = ( 'FN' => 1 );

         my @allabookfolders = get_readable_abookfolders();
         foreach my $abookfolder (@allabookfolders) {
            my $abookfile=abookfolder2file($abookfolder);
            my $thisbook = readadrbook($abookfile, (keys %searchterms?\%searchterms:undef), \%only_return);
            # remember what book this address came from
            foreach my $xowmuid (keys %{$thisbook}) {
               ${$thisbook}{$xowmuid}{'X-OWM-BOOK'}[0]{VALUE} = $abookfolder;
               # add it to addresses
               $addresses{$xowmuid} = ${$thisbook}{$xowmuid};
            }
         }

         $temphtml .= qq|<tr><td bgcolor=$bgcolor[$colornum] colspan="2"><b>$lang_text{'abook_showchecked_export'}</b></td></tr>|;
         $colornum=($colornum+1)%2; # alternate the bgcolor
         if (keys %waschecked < 1) {
            $temphtml .= qq|<tr><td bgcolor=$bgcolor[$colornum] colspan="2">&nbsp;</td></tr>|;
         } else {
            my $num = 1;
            foreach my $fullname ( sort { lc($a) cmp lc($b) }
                                    map { $addresses{$_}{FN}[0]{VALUE} } keys %waschecked) {
               $temphtml .= qq|<tr><td bgcolor=$bgcolor[$colornum]><b>$num&nbsp;&nbsp;</b></td><td bgcolor=$bgcolor[$colornum] nowrap>|.ow::htmltext::str2html($fullname).qq|</td></tr>|;
               $colornum=($colornum+1)%2; # alternate the bgcolor
               $num++;
            }
         }
      } else {
         # our waschecked is a bunch of email addresses with %@#xowmuid after it
         for (ow::tool::str2list(join(",",param('to'))), ow::tool::str2list(param('checkedto')) ) { $waschecked{TO}{$_} = 1 if ($_ ne '') };
         for (ow::tool::str2list(join(",",param('cc'))), ow::tool::str2list(param('checkedcc')) ) { $waschecked{CC}{$_} = 1 if ($_ ne '') };
         for (ow::tool::str2list(join(",",param('bcc'))), ow::tool::str2list(param('checkedbcc')) ) { $waschecked{BCC}{$_} = 1 if ($_ ne '') };

         # addresses arrive from editgroupform as '\n' delimited.
         # separate them into each individual addresses and put them
         # in %waschecked.
         foreach my $key (qw(TO CC BCC)) {
            foreach my $email (keys %{$waschecked{$key}}) {
               delete $waschecked{$key}{$email};
               foreach my $line (split(/\n/,$email)) {
                  $line =~ s/^\s+//; $line =~ s/\s+$//;
                  $waschecked{$key}{$line} = 1 if ($line ne '');
               }
            }
         }

         foreach my $key (qw(TO CC BCC)) {
            $temphtml .= qq|<tr><td bgcolor=$bgcolor[$colornum] colspan="2"><b>$lang_text{lc($key)}</b></td></tr>|;
            $colornum=($colornum+1)%2; # alternate the bgcolor
            if (keys %{$waschecked{$key}} < 1) {
               $temphtml .= qq|<tr><td bgcolor=$bgcolor[$colornum] colspan="2">&nbsp;</td></tr>|;
            } else {
               my $num = 1;
               foreach my $email (sort { lc($a) cmp lc($b) } keys %{$waschecked{$key}}) {
                  ($email) = split(/%@#/,$email);
                  $temphtml .= qq|<tr><td bgcolor=$bgcolor[$colornum]><b>$num&nbsp;&nbsp;</b></td><td bgcolor=$bgcolor[$colornum] nowrap>|.ow::htmltext::str2html($email).qq|</td></tr>|;
                  $colornum=($colornum+1)%2; # alternate the bgcolor
                  $num++;
               }
            }
            $temphtml .= qq|<tr><td height="10" colspan="2">&nbsp;</td></tr>|;
            $colornum = 0;
         }
      }

      $temphtml .= qq|<tr><td align="center" colspan="2">|.
                   start_form(-action=>"#", -name=>'closeShowWindow').
                   button(-name=>$lang_text{'close'},
                          -accesskey=>'X',
                          -onClick=>'javascript:window.close();',
                          -class=>"medtext").
                   endform().
                   qq|</td></tr>|;
      $temphtml .= qq|<tr><td height="10" colspan="2">&nbsp;</td></tr>|;

      $html =~ s/\@\@\@LISTOFCHECKED\@\@\@/$temphtml/;
   }

   httpprint([], [htmlheader(), $html, htmlfooter(1)]);
}
########## END ADDRSHOWCHECKED ###################################


########## ADDRVIEWATT ###########################################
sub addrviewatt {
   my $file = param('file');
   openwebmailerror(__FILE__, __LINE__, "No named file to view") if (!defined $file);
   my $type = lc(param('type')) || ''; # undef makes application/octet-stream

   my $contenttype = ow::tool::ext2contenttype($type);
   my $ext = ow::tool::contenttype2ext($contenttype);
   $ext = 'unknown' if ($ext eq 'bin');

   my $target = ow::tool::untaint("$config{'ow_sessionsdir'}/$thissession-vcard$file");
   sysopen(FILE, $target, O_RDONLY) || openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $target! ($!)");
   my $attbody = do {local $/; <FILE> }; # slurp
   close FILE || openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $target! ($!)");
   my $length = length($attbody);
   if ($length>512 && is_http_compression_enabled()) {
      my $zattbody=Compress::Zlib::memGzip($attbody);
      my $zlen=length($zattbody);
      my $zattheader=qq|Content-Encoding: gzip\n|.
                     qq|Vary: Accept-Encoding\n|.
                     qq|Content-Length: $zlen\n|.
                     qq|Connection: close\n|.
                     qq|Content-Type: $contenttype; name="inline.$ext"\n|.
                     qq|Content-Disposition: inline; filename="$file.$ext"\n|;
      print $zattheader, "\n", $zattbody;
   } else {
      my $attheader=qq|Content-Length: $length\n|.
                    qq|Connection: close\n|.
                    qq|Content-Type: $contenttype; name="inline.$ext"\n|.
                    qq|Content-Disposition: inline; filename="$file.$ext"\n|;
      print $attheader, "\n", $attbody;
   }

   return;
}
########## END ADDRVIEWATT #######################################


########## UPDATE_REVISION_TIME ##################################
sub update_revision_time {
   my ($r_rev) = @_;
   my ($rev_sec,$rev_min,$rev_hour,$rev_mday,$rev_mon,$rev_year,$rev_wday,$rev_yday,$rev_isdst) = gmtime(time);
   $rev_mon++; $rev_year+=1900;
   $r_rev->{VALUE}{SECOND} = $rev_sec;
   $r_rev->{VALUE}{MINUTE} = $rev_min;
   $r_rev->{VALUE}{HOUR} = $rev_hour;
   $r_rev->{VALUE}{DAY} = $rev_mday;
   $r_rev->{VALUE}{MONTH} = $rev_mon;
   $r_rev->{VALUE}{YEAR} = $rev_year;
}
########## END UPDATE_REVISION_TIME ##############################


########## DELETEATTACHMENTS #####################################
sub deleteattachments {
   my (@delfiles, @sessfiles);

   opendir(SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_sessionsdir'}! ($!)");
      @sessfiles=readdir(SESSIONSDIR);
   closedir(SESSIONSDIR);

   foreach my $attfile (@sessfiles) {
      if ($attfile =~ /^(\Q$thissession\E\-vcard\d+)$/) {
         push(@delfiles, ow::tool::untaint("$config{'ow_sessionsdir'}/$attfile"));
      }
   }
   unlink(@delfiles) if ($#delfiles>=0);
}
########## END DELETEATTACHMENTS #################################


########## GETATTFILESINFO #######################################
sub getattfilesinfo {
   my (@attfiles, @sessfiles);
   my $totalsize = 0;

   print "<pre>Getting attachments info\n</pre>" if $addrdebug;

   opendir(SESSIONSDIR, "$config{'ow_sessionsdir'}") or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_sessionsdir'}! ($!)");
      @sessfiles=readdir(SESSIONSDIR);
   closedir(SESSIONSDIR);

   foreach my $currentfile (@sessfiles) {
      if ($currentfile =~ /^(\Q$thissession\E\-vcard\d+)$/) {
         my (%att, $attheader);

         push(@attfiles, \%att);
         $att{file}=$1;
         $att{size}=(-s "$config{'ow_sessionsdir'}/$currentfile");

         $totalsize += $att{size};
      }
   }

   print "<pre>Dumping attachments info:\n".Dumper(\@attfiles)."</pre>\n\n" if $addrdebug;

   return ($totalsize, \@attfiles);
}
########## END GETATTFILESINFO ###################################


########## MAKE_X_OWM_UID ########################################
# This is required to generate the keys for hashes when importing multiple
# vCard objects.
sub make_x_owm_uid {
   my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
   my @chars = ( 'A' .. 'Z', 0 .. 9 );
   my $longrandomstring = join '', map { $chars[rand @chars] } 1..12;
   my $shortrandomstring = join '', map { $chars[rand @chars] } 1..4;
   my $uid = ($uid_year+1900).sprintf("%02d",($uid_mon+1)).sprintf("%02d",$uid_mday)."-".
              sprintf("%02d",$uid_hour).sprintf("%02d",$uid_min).sprintf("%02d",$uid_sec)."-".
              $longrandomstring."-".$shortrandomstring;
   return $uid;
}
########## END MAKE_X_OWM_UID ####################################


########## APPLYTEMPLATEMODE #####################################
sub applytemplatemode {
   my ($r_html, $modetemplate) = @_;
   my $thistemplate = applystyle(readtemplate($modetemplate));
   my ($beforelistview) = $thistemplate =~ m/\@\@\@BEFORELISTVIEWSTART\@\@\@(.*)\@\@\@BEFORELISTVIEWEND\@\@\@/s;
   my ($afterlistview) = $thistemplate =~ m/\@\@\@AFTERLISTVIEWSTART\@\@\@(.*)\@\@\@AFTERLISTVIEWEND\@\@\@/s;
   my ($extrajavascript) = $thistemplate =~ m/\@\@\@JAVASCRIPTSTART\@\@\@(.*)\@\@\@JAVASCRIPTEND\@\@\@/s;
   ${$r_html} =~ s/\@\@\@BEFORELISTVIEWEXTRAHTML\@\@\@/$beforelistview/;
   ${$r_html} =~ s/\@\@\@AFTERLISTVIEWEXTRAHTML\@\@\@/$afterlistview/;
   ${$r_html} =~ s/\@\@\@EXTRAJAVASCRIPT\@\@\@/$extrajavascript/;
}
########## END APPLYTEMPLATEMODE #################################


########## IS_GROUPBOX_CHECKED ###################################
sub is_groupbox_checked {
   my ($key,$r_is_checked,$r_allemails,$xowmuidtrack) = @_;
   my $checked = 'checked';
   # if we're in editgroupform mode $r_allemails will be delimited by a '\n',
   # instead of the normal ', '. To make it easy to test if the box should be
   # checked lets put the $r_allmails back to a ', ' delimited list just for
   # this sub.
   ${$r_allemails} =~ s/\n/, /g if (param('editgroupform'));

   # test if this box should be checked or not
   foreach my $email (ow::tool::str2list(${$r_allemails})) {
      $checked = exists $r_is_checked->{$key}{"$email$xowmuidtrack"}?'checked':undef;
      last unless defined $checked;
   }

   # now we know if this box is checked or not, so lets return $r_allemails back
   # to the '\n' delimited list it was if we are in editgroupform mode.
   ${$r_allemails} = join("\n",(ow::tool::str2list(${$r_allemails}))) if (param('editgroupform'));

   return $checked;
}
########## END IS_GROUPBOX_CHECKED ###############################


########## GETADDRBOOKS_.... #####################################
sub is_abookfolder_global {
   return 1 if ($_[0] eq 'global' or $_[0] eq 'ldapcache');
   return 1 if (-f "$config{'ow_addressbooksdir'}/$_[0]");
   return 0;
}

sub is_abookfolder_writable {
   my $webaddrdir = dotpath('webaddr');
   if ($_[0] eq 'ALL') {
      return 0;
   } elsif (-f "$config{'ow_addressbooksdir'}/$_[0]") {	# global abook
      return 1 if ($config{'abook_globaleditable'} && -w "$config{'ow_addressbooksdir'}/$_[0]");
   } else {						# user abook
      return 1 if (-w "$webaddrdir/$_[0]");
   }
   return 0;
}

sub get_user_abookfolders {
   my $webaddrdir = dotpath('webaddr');
   opendir(WEBADDR, $webaddrdir) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $webaddrdir ($!)");
   my @books = sort {$a cmp $b}
               map { (!-f "$config{'ow_addressbooksdir'}/$_" && -r "$webaddrdir/$_")?$_:() }
               grep { /^[^.]/ && !/^categories\.cache$/ }
               readdir(WEBADDR);
   closedir(WEBADDR) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $webaddrdir! ($!)");

   return @books;
}

sub get_global_abookfolders {
   my @books;
   opendir(WEBADDR, $config{'ow_addressbooksdir'}) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} $config{'ow_addressbooksdir'} ($!)");
   while (($_=readdir(WEBADDR))) {
      next if ((/^\./) ||
               (!-r "$config{'ow_addressbooksdir'}/$_") ||
               (!$config{'enable_ldap_abook'} && $_ eq 'ldapcache') );
      push(@books, $_);
   }
   closedir(WEBADDR) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} $config{'ow_addressbooksdir'}! ($!)");

   return (sort {$a cmp $b} @books);
}

sub get_readable_abookfolders {
   my @userbooks=get_user_abookfolders();
   my @globalbooks=get_global_abookfolders();
   return(@userbooks, @globalbooks );
}

sub get_writable_abookfolders {
   my (@userbooks, @globalbooks);
   foreach (get_user_abookfolders()) {
      push (@userbooks, $_) if (is_abookfolder_writable($_));
   }
   foreach (get_global_abookfolders()) {
      push (@globalbooks, $_) if (is_abookfolder_writable($_));
   }
   return(@userbooks, @globalbooks);
}

sub abookfolder2file {
   if ($_[0] eq 'ALL') {
      return "/nonexistent";
   } elsif (is_abookfolder_global($_[0])) {
      return ow::tool::untaint("$config{'ow_addressbooksdir'}/$_[0]");
   } else {
      my $webaddrdir = dotpath('webaddr');
      return ow::tool::untaint("$webaddrdir/$_[0]");
   }
}

sub userabookfolders_totalsize {
   my $totalsize=0;
   foreach (get_user_abookfolders()) {
      $totalsize += (-s abookfolder2file($_)) || 0;
   }
   return int($totalsize/1024+0.5);	# unit:kbyte
}
########## END GETADDRBOOKS_.... #################################


########## IS_QUOTA_AVAILABLE ####################################
sub is_quota_available {
   my $writesize=$_[0];
   if ($quotalimit>0 && $quotausage+$writesize>$quotalimit) {
      $quotausage=(ow::quota::get_usage_limit(\%config, $user, $homedir, 1))[2];
      return 0 if ($quotausage+$writesize>$quotalimit);
   }
   return 1;
}
########## END IS_QUOTA_AVAILABLE ################################


########## DEEPCOPY ##############################################
sub deepcopy {
    # a shameless rip from http://www.stonehenge.com/merlyn/UnixReview/col30.html
    # this should probably be moved to the ow::tool at some point.
    my $this = shift;
    if (not ref $this) {
       $this;
    } elsif (ref $this eq "ARRAY") {
       [map deepcopy($_), @$this];
    } elsif (ref $this eq "HASH") {
       scalar { map { $_ => deepcopy($this->{$_}) } keys %$this };
    } else {
       croak("what type is $_?");
    }
}
########## END DEEPCOPY ##########################################


########## REFRESH_LDAPCACHE_ABOOKFILE ###########################
#
# LDAP addressbook support
# by Luigi Mazzieri, lmazzieri.AT.emerenzio.net
#
sub refresh_ldapcache_abookfile {
   my $ldapcachefile=abookfolder2file('ldapcache');

   return 0 if (!$config{'enable_ldap_abook'});
   return 0 if (!ow::tool::has_module('Net/LDAP.pm'));

   if (-f $ldapcachefile) {
      my $nowtime=time();
      my $filetime=(stat($ldapcachefile))[9];
      return 0 if ($nowtime-$filetime < $config{'ldap_abook_cachelifetime'}*60);	# file is up to date

      # mark file with current time, so no other process will try to update this file
      my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
      utime($nowtime, $nowtime, $ldapcachefile);
      ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);
   }

   # below handler is not necessary, as we call zombie_cleaner at end of each request
   #local $SIG{CHLD}=\&ow::tool::zombie_cleaner;

   local $|=1; 			# flush all output
   if ( fork() == 0 ) {		# child
      close(STDIN); close(STDOUT); close(STDERR);
      writelog("debug - refresh_ldapcache_abookfile process forked - " .__FILE__.":". __LINE__) if ($config{'debug_fork'});

      my @ldaplist=();  # keep the order in global addressbook
      my $ldap = Net::LDAP->new( $config{'ldap_abook_host'} ) or openwebmail_exit(1);
      my $mesg = $ldap->bind($config{'ldap_abook_user'},
                             password => $config{'ldap_abook_password'}) ;
      if ($config{'ldap_abook_container'} ne ""){
         $mesg = $ldap->search( # perform a search
                               base   => $config{'ldap_abook_container'}.",".$config{'ldap_abook_base'},
                               filter => "($config{'ldap_abook_prefix'}=*)",
                               scope  => 'one' );
      } else {
         $mesg = $ldap->search( # perform a search
                               base   => $config{'ldap_abook_base'},
                               filter => "($config{'ldap_abook_prefix'}=*)",
                               scope  => 'one' );
      }
      foreach my $ou ($mesg->sorted()) {
         my $ouname = $ou->get_value($config{'ldap_abook_prefix'});
         my $mesg2;
         if ($config{'ldap_abook_container'} ne ""){
            $mesg2 = $ldap->search( # perform a search
                                   base   => "$config{'ldap_abook_prefix'}=".$ou->get_value($config{'ldap_abook_prefix'}).",".
                                             $config{'ldap_abook_container'}.",".$config{'ldap_abook_base'},
                                   filter => "(cn=*)" );
         } else {
            $mesg2 = $ldap->search( # perform a search
                                   base   => "$config{'ldap_abook_prefix'}=".$ou->get_value($config{'ldap_abook_prefix'}).",".
                                             $config{'ldap_abook_base'},
                                   filter => "(cn=*)" );
         }

         foreach my $entry ($mesg2->sorted()) {
            my $name=$entry->get_value("cn");
            my $email=$entry->get_value("mail");
            my $note=$entry->get_value("note");
            next if ($email=~/^\s*$/);	# skip if email is null
            push(@ldaplist, [ $name, $email, $note ]);
         }
      }

      undef $ldap;		# release LDAP connection

      my @entries=();
      foreach my $r_a (@ldaplist) {
         my ($name, $email, $note)=@{$r_a}[0,1,2];

         # X-OWM-ID
         #my $x_owm_uid=make_x_owm_uid();

         # generate deterministic x_owm_uid for entries on LDAP
         # since ldapcache may be refreshed between user accesses
         my $k=$name.$email; $k=ow::tool::calc_checksum(\$k); $k=~s/(.)/sprintf("%02x",ord($1))/eg; $k=uc($k.$k);
         my $x_owm_uid=substr($k, 0,8).'-'.substr($k,8,6).'-'.substr($k,14,12).'-'.substr($k,26,4);

         # REV
         my ($uid_sec,$uid_min,$uid_hour,$uid_mday,$uid_mon,$uid_year) = gmtime(time);
         my $rev = ($uid_year+1900).($uid_mon+1).$uid_mday."T".$uid_hour.$uid_min.$uid_sec."Z";

         # Name MUST be defined
         if ($name eq "" || $name =~ m/^\s+$/) {
            $name = $lang_text{'name'};
         }

         # Start output
         my ($first, $mid, $last, $nick)=_parse_username($name);
         foreach ($first, $mid, $last, $nick) { $_.=' ' if ($_=~/\\$/); }
         push(@entries, qq|BEGIN:VCARD\r\n|.
                        qq|VERSION:3.0\r\n|.
                        qq|N:$last;$first;$mid;;\r\n|);
         push(@entries,"NICKNAME:$nick\r\n") if ($nick ne '');

         # get all the emails
         my @emails = split(/,/,$email);
         foreach my $e (sort @emails) {
            $e =~ s/\\$//; # chop off trailing slash that escaped comma char
            push(@entries,"EMAIL:$e\r\n") if defined $e;
         }
         # how we handle distribution lists
         if (@emails > 1) {
            push(@entries, "X-OWM-GROUP:$name\r\n");
         }

         push(@entries, "NOTE:$note\r\n") if ($note ne '');
         push(@entries, qq|REV:$rev\r\n|.
                        qq|X-OWM-UID:$x_owm_uid\r\n|.
                        qq|END:VCARD\r\n\r\n|);
      }

      # write out the new converted addressbook
      my ($origruid, $origeuid, $origegid)=ow::suid::set_uid_to_root();
      if (ow::filelock::lock($ldapcachefile, LOCK_EX|LOCK_NB)) {
         if (sysopen(ADRBOOK, $ldapcachefile, O_WRONLY|O_TRUNC|O_CREAT)) {
            print ADRBOOK @entries;
            close(ADRBOOK);
         }
         ow::filelock::lock($ldapcachefile, LOCK_UN);
      }
      chmod(0444, $ldapcachefile);	# set it to readonly
      ow::suid::restore_uid_from_root($origruid, $origeuid, $origegid);

      openwebmail_exit(0);
   }
   return 1;
}
########## END REFRESH_LDAPCACHE_ABOOKFILE #######################



#================================== IMPORTANT =====================================
# Developers should familiarize themselves with the vCard hash data structure
# format before writing an import or export module. Set vcarddebug=1 in
# shares/vcard.pl or addrdebug=1 in this file.
#
# Also see:
# http://www.acatysmoof.com/posting/openwebmail-patches/041025/vCard_data_structure
#================================== IMPORTANT =====================================



########## ADDRIMPORTFORM ########################################
sub addrimportform {
   my @allabookfolders = get_readable_abookfolders();
   # calculate the available free space
   my $availfreespace = $config{'abook_maxsizeallbooks'} - userabookfolders_totalsize();

   # start the html
   my ($html, $temphtml);
   $html = applystyle(readtemplate("addrimportbook.template"));
   $html =~ s/\@\@\@AVAILFREESPACE\@\@\@/$availfreespace $lang_sizes{'kb'}/g;
   $html =~ s/\@\@\@ABOOKIMPORTLIMIT\@\@\@/$config{'abook_importlimit'} $lang_sizes{'kb'}/g;

   # menubar links
   my $abookfolderstr=ow::htmltext::str2html($lang_abookselectionlabels{$abookfolder}||f2u($abookfolder));
   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $abookfolderstr",
                        qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;$urlparm"|);
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   $temphtml = start_multipart_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                                    -name=>'importForm').
               ow::tool::hiddens(action=>'addrimport',
                                 sessionid=>$thissession,
                                 abookcollapse=>$abookcollapse,
                                ). $webmail_formparm;
   $html =~ s/\@\@\@STARTIMPORTFORM\@\@\@/$temphtml/;

   $temphtml = filefield(-name=>'importfile',
                         -default=>'',
                         -size=>'30',
                         -override=>'1');
   $html =~ s/\@\@\@IMPORTFILEFIELD\@\@\@/$temphtml/;

   my %supportedlabels = ();
   for (keys %supportedimportexportformat) { $supportedlabels{$_} = $supportedimportexportformat{$_}[2] };
   $temphtml = popup_menu(-name=>'importformat',
                          -values=>[sort keys %supportedimportexportformat],
                          -default=>'vcard3.0',
                          -labels=>\%supportedlabels,
                          -onChange=>"javascript:importOptionsToggle(document.forms['importForm'].elements['importformat'].options[document.forms['importForm'].elements['importformat'].selectedIndex].value,'importForm');",
                          -override=>1);
   $html =~ s/\@\@\@FORMATSMENU\@\@\@/$temphtml/;

   my @charset = sort map { $ow::lang::charactersets{$_}[1] } keys %ow::lang::charactersets;
   my $defaultcharset = $prefs{'charset'};
   $temphtml = "$lang_text{'charset'}:";
   $temphtml .= popup_menu(-name=>'importcharset',
                          -values=>\@charset,
                          -default=>$defaultcharset,
                          -override=>'1',
                          -disabled=>'1');
   $html =~ s/\@\@\@IMPORTCHARSETMENU\@\@\@/$temphtml/;

   my @choices = qw(fullname prefix first middle last suffix email phone note none);

   # build the labels from the choices
   my %addrfieldorderlabels = ();
   $addrfieldorderlabels{"$_"} = $lang_text{"abook_listview_$_"} for @choices;

   $temphtml = '';
   for (my $i = 1; $i <= $importfieldcount; $i++) {
      $temphtml.= '<td>'.
                  popup_menu(-name=>"importfieldorder$i",
                             -default=>'none',
                             -values=>\@choices,
                             -labels=>\%addrfieldorderlabels,
                             -override=>'1',
                             -disabled=>'1').
                  '</td>';
   }
   $html =~ s/\@\@\@FIELDCHOICESMENU\@\@\@/$temphtml/g;

   my @writableabookfolders = get_writable_abookfolders(); # export destination must be writable
   $temphtml = popup_menu(-name=>'importdest',
                          -values=>[$lang_text{'abook_importdest'}, @writableabookfolders],
                          -override=>1,
                         );
   $html =~ s/\@\@\@ADDRBOOKSMENU\@\@\@/$temphtml/;


   $temphtml = submit(-name=>"$lang_text{'import'}",
                      -class=>"medtext");
   $html =~ s/\@\@\@IMPORTBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDIMPORTFORM\@\@\@/$temphtml/g;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-abook.pl",
                          -name=>'cancelForm').
               ow::tool::hiddens(action=>'addrlistview').
               $formparm;
   $html =~ s/\@\@\@STARTCANCELFORM\@\@\@/$temphtml/;

   $temphtml = submit(-name=>"$lang_text{'cancel'}",
                      -class=>"medtext");
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDCANCELFORM\@\@\@/$temphtml/g;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END ADDRIMPORTFORM ####################################


########## ADDRIMPORT ############################################
sub addrimport {
   my $importfile = param('importfile') ||
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_import_nofile'}! ($!)");
   my $importfilesize = (-s $importfile);
   my $importformat = param('importformat') ||
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_import_noformat'}! ($!)");
   if (!exists $supportedimportexportformat{$importformat}) {
      $lang_err{'abook_import_unsupfmt'} =~ s/\@\@\@FORMAT\@\@\@/$importformat/;
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_import_unsupfmt'}! ($!)");
   }
   my ($importfileext) = $importfile =~ m/\.(\S+)$/;
   if (lc($importfileext) ne $supportedimportexportformat{$importformat}[3]) {
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_ext_notsupported'} $supportedimportexportformat{$importformat}[2]!");
   }
   my $importdest = param('importdest') ||
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_import_nodest'}! ($!)");

   my $importfilesizekb = sprintf("%0.2f",$importfilesize/1024);
   if (!is_quota_available($importfilesizekb)) {
      openwebmailerror(__FILE__, __LINE__,"$lang_err{'quotahit_alert'}\n");
   }
   if ($config{'abook_importlimit'}>0 &&
       $importfilesizekb>$config{'abook_importlimit'} ) {
      openwebmailerror(__FILE__, __LINE__,"$importfilesizekb $lang_sizes{'kb'} $lang_err{'upload_overlimit'} $config{'abook_importlimit'} $lang_sizes{'kb'}\n");
   }
   if ($config{'abook_maxsizeallbooks'}>0) {
      # load up the list of all books
      my @allabookfolders = get_readable_abookfolders();
      # calculate the available free space
      my $availfreespace = $config{'abook_maxsizeallbooks'} - userabookfolders_totalsize();
      if ($importfilesizekb > $availfreespace) {
          openwebmailerror(__FILE__, __LINE__,"$importfilesizekb $lang_sizes{'kb'} > $availfreespace $lang_sizes{'kb'}. $lang_err{'abook_toobig'} $lang_err{'back'}\n");
      }
   }
   if ($importfilesize == 0) {
      openwebmailerror(__FILE__, __LINE__,"$lang_wdbutton{'upload'} $lang_text{'failed'} ($!)\n");
   }

   # get the imported data into a string. This slurps the whole upload file into memory. :(
   my $importfilecontents = '';
   while (<$importfile>) {
      $importfilecontents .= $_;
   }

   # translate the uploaded data into our preferred data structure
   my $newaddrinfo = '';
   $newaddrinfo = $supportedimportexportformat{$importformat}[0]->($importfilecontents);

   # remember old settings so we can change them
   my $oldabookfolder = $abookfolder;
   my $oldescapedabookfolder = $escapedabookfolder;

   # write the import to the destination
   if ($importdest eq $lang_text{'abook_importdest'}) { # To a new book
      my $fname = $importfile;

      # Convert :: back to the ' like it should be.
      $fname =~ s/::/'/g;

      # Trim the path info from the filename
      if ($prefs{'charset'} eq 'big5' || $prefs{'charset'} eq 'gb2312') {
         $fname=ow::tool::zh_dospath2fname($fname);	# dos path
      } else {
         $fname =~ s|^.*\\||;   # dos path
      }
      $fname =~ s|^.*/||;	# unix path
      $fname =~ s|^.*:||;	# mac path and dos drive

      my $newbookfile = ow::tool::untaint(abookfolder2file($fname));
      if (-e "$newbookfile" || $fname=~/^(?:ALL|DELETE)$/ ) {
         openwebmailerror(__FILE__, __LINE__, f2u($fname)." $lang_err{'already_exists'}\n");
      }

      my $writeoutput = outputvfile('vcard',$newaddrinfo);

      if (sysopen(IMPORT, $newbookfile, O_WRONLY|O_TRUNC|O_CREAT)) {
         print IMPORT $writeoutput;
         close(IMPORT);
         writelog("import addressbook - upload new book $fname");
         writehistory("import addressbook - upload new book $fname");
         $abookfolder = $fname;
         $escapedabookfolder = ow::tool::escapeURL($fname);
      } else {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} ".f2u($fname)." ($!)\n");
      }
   } else { # append it to a selected book
      # load the existing book
      my $targetfile = ow::tool::untaint(abookfolder2file($importdest));
      my $targetbook = readadrbook($targetfile, undef, undef);

      # merge the new data
      foreach my $xowmuid (keys %{$newaddrinfo}) {
         ${$targetbook}{$xowmuid} = ${$newaddrinfo}{$xowmuid};
      }

      # stringify it
      my $writeoutput = outputvfile('vcard',$targetbook);

      # overwrite the targetfile with the new data
      ow::filelock::lock($targetfile, LOCK_EX|LOCK_NB) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($targetfile));
      sysopen(TARGET, $targetfile, O_WRONLY|O_TRUNC|O_CREAT) or
        openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_write'} ".f2u($targetfile)." ($!)\n");
      print TARGET $writeoutput;
      close(TARGET) or
        openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_close'} ".f2u($targetfile)." ($!)\n");
      ow::filelock::lock($targetfile, LOCK_UN);

      writelog("import addressbook - ".keys(%{$newaddrinfo})." contacts to $importdest");
      writehistory("import addressbook - ".keys(%{$newaddrinfo})." contacts to $importdest");

      # done
      $abookfolder = $importdest;
      $escapedabookfolder = ow::tool::escapeURL($importdest);
   }

   # import done - go back to the listing
   # (maybe a http redirect is more clean here? tung)
   foreach ($abook_urlparm_with_abookfolder, $urlparm) {
      s/abookfolder=$oldescapedabookfolder&amp;/abookfolder=$escapedabookfolder&amp;/g;
   }
   foreach ($abook_formparm_with_abookfolder, $formparm) {
      s/NAME="abookfolder" VALUE="$oldabookfolder"/NAME="abookfolder" VALUE="$abookfolder"/gi;
   }
   addrlistview();
}
########## END ADDRIMPORT ########################################


########## IMPORTVCARD ###########################################
sub importvcard {
   # accepts a vCard string and returns a vCard hash data structure

   # shares/adrbook.pl already loads shares/vfile.pl which contains
   # the routine we need for parsing vcard data. So this import is
   # the easiest one to do.
   my $importdata = $_[0];
   return readvfilesfromstring($importdata);
}
########## END IMPORTVCARD #######################################


######################### IMPORTTXT #################################
sub importtxt {
   # accepts a csv or tab string and returns a vCard hash data structure

   my $importdata = $_[0];
   my $fs = $_[1];

   # NOTE: There may be fields which have double-quotes,
   # linebreaks, commas, and tabs inside them, inside double-quotes!
   # We can try to sanitize that:

   $importdata =~ s/\r?\n|\r/::safe_newline::/g;			# DOS/UNIX independent line breaks
   $importdata =~ s/"($fs|::safe_newline::)/::safe_qfend::$1/g;	# end of a quoted field
   $importdata =~ s/(^|$fs|::safe_newline::)"/$1::safe_qfstart::/g;	# start of a quoted field
   $importdata =~ s/""/::safe_quote::/g;				# quotes inside a field

   while ($importdata =~ s/(::safe_qfstart::(?:(?!::safe_qfend::).)*?)$fs(.+?::safe_qfend::)/$1::safe_infs::$2/g) {}
   while ($importdata =~ s/(::safe_qfstart::(?:(?!::safe_qfend::).)*?)::safe_newline::(.+?::safe_qfend::)/$1\n$2/gs) {}

   $importdata =~ s/$fs/::safe_fs::/g;			# unique field separator
   $importdata =~ s/::safe_infs::/$fs/g;		# restore tab/quote inside fields
   $importdata =~ s/::safe_quote::/"/g;			# restore quotes inside fields
   $importdata =~ s/::safe_(?:qfstart|qfend):://g;	# rm field-delimiting quotes (not needed anymore)

   my @recs = split (/::safe_newline::/, $importdata);

   my @import_order;
   if (param('importformat') =~ / auto/) {
      @import_order = split (/::safe_fs::/, lc(shift(@recs))); # First line has the field names
      map { s/^ +| +$|'//g } @import_order
   } else {
      for (my $i = 1; $i <= $importfieldcount; $i++) {
         # user specified from a form up to $importfieldorder fields for now.
         push @import_order, param("importfieldorder$i");
      }
   }

   # Iterate records from txt file
   my %vcardhash = ();
   foreach my $rec (@recs) {
      my @values = split (/::safe_fs::/, $rec);
      map { s/^ +| +$//g } @values;
      my %txt = ();
      map {
         $txt{$_} = shift (@values);
         chomp ($txt{$_});
      } @import_order;

      my $x_owm_uid=make_x_owm_uid();
      $vcardhash{$x_owm_uid} = make_vcard(\%txt, $x_owm_uid);
   }

   return \%vcardhash;
}
########################## END IMPORTTXT ###########################


########################## IMPORTCSV ################################
sub importcsv {
   # accepts a csv string and returns a vCard hash data structure
   return importtxt($_[0], ",");
}
######################### END IMPORTCSV #############################


########################## IMPORTTAB ################################
sub importtab {
   # accepts a tab delimited string and returns a vCard hash data structure
   return importtxt($_[0], "\t");
}
######################### END IMPORTTAB #############################


########## IMPORTPINE ############################################
sub importpine {
   # TO BE DONE
   # accepts a pine addressbook string and returns a vCard hash data structure
   my $importdata = $_[0];
}
########## END IMPORTPINE ########################################


########## IMPORTLDIF ############################################
sub importldif {
   # TO BE DONE
   # accepts a ldif addressbook string and returns a vCard hash data structure
   my $importdata = $_[0];
}
########## END IMPORTLDIF ########################################


########## ADDREXPORT ############################################
sub addrexport {
   # This sub does the actual exporting. The export form is actually
   # the 'export' mode of the listview subroutine.
   my $exportformat = param('exportformat') || 'vcard3.0';

   my ($exportbody, $exportcontenttype, $exportfilename) = ();
   if (!exists $supportedimportexportformat{$exportformat}) {
      $lang_err{'abook_export_unsupfmt'} =~ s/\@\@\@FORMAT\@\@\@/$exportformat/;
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_import_unsupfmt'}! ($!)");
   } else {
      # the param lists received here are xowmuids, not email addresses!
      my %waschecked = ();
      for (ow::tool::str2list(join(",",param('to'))), ow::tool::str2list(param('checkedto')) ) { $waschecked{$_} = 1 if ($_ ne '') };
      for (ow::tool::str2list(join(",",param('cc'))), ow::tool::str2list(param('checkedcc')) ) { $waschecked{$_} = 1 if ($_ ne '') };
      for (ow::tool::str2list(join(",",param('bcc'))), ow::tool::str2list(param('checkedbcc')) ) { $waschecked{$_} = 1 if ($_ ne '') };

      if (keys %waschecked == 0) {
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'abook_export_undef'}!");
      }

      # load up the list of available books
      my @allabookfolders = get_readable_abookfolders();
      # The exports should have Product ID of the version of OWM they were exported from
      my $prodid_string = "$config{'name'} $config{'version'} $config{'releasedate'}";

      # load the addresses - only the required information
      my %addresses=();
      my %searchterms = ();
      $searchterms{'X-OWM-UID'}[0]{'VALUE'} = join("|", keys %waschecked);

      foreach my $abookfolder (@allabookfolders) {
         my $abookfile=abookfolder2file($abookfolder);
         my $thisbook = readadrbook($abookfile, (keys %searchterms?\%searchterms:undef), undef);
         # remember what book this address came from
         foreach my $xowmuid (keys %{$thisbook}) {
            $addresses{$xowmuid} = ${$thisbook}{$xowmuid};
            # stamp the PRODID as OpenWebmail
            $addresses{$xowmuid}{PRODID}[0]{VALUE} = $prodid_string;
         }
      }

      # figure the version request
      my ($version) = $exportformat =~ m/^vcard(.*)/;

      # now send the vCard hash structure to the exporter
      ($exportbody, $exportcontenttype, $exportfilename) = $supportedimportexportformat{$exportformat}[1]->(\%addresses, $version);
   }

   # send it to the browser
   my $exportlength = length($exportbody);
   my $exportheader .= qq|Connection: close\n|.
                       qq|Content-Type: $exportcontenttype; name="$exportfilename"\n|;

   # ie5.5 is broken with content-disposition: attachment
   if ( $ENV{'HTTP_USER_AGENT'}=~/MSIE 5.5/ ) {
      $exportheader .= qq|Content-Disposition: filename="$exportfilename"\n|;
   } else {
      $exportheader .= qq|Content-Disposition: attachment; filename="$exportfilename"\n|;
   }

   # should we gzip it?
   if ($exportlength>512 && is_http_compression_enabled()) {
      $exportbody = Compress::Zlib::memGzip($exportbody);
      $exportlength = length($exportbody);
      $exportheader .= qq|Content-Encoding: gzip\n|.
                       qq|Vary: Accept-Encoding\n|;
   }

   $exportheader .= qq|Content-Length: $exportlength\n|;
   print $exportheader, "\n", $exportbody;
}
########## END ADDREXPORT ########################################


########## EXPORTVCARD ###########################################
sub exportvcard {
   # accepts a vCard hash data structure and returns a vCard format string.
   # shares/adrbook.pl autoloads /shares/vfile.pl which contains outputvfile
   my ($r_addresses, $version) = @_;
   my ($exportcontenttype, $exportfilename) = ('application/x-vcard', "$lang_text{'export'}.vcf");
   my %exclude_propertynames = ('X-OWM-UID'=>1);
   return (outputvfile('vcard',$r_addresses,$version,\%exclude_propertynames),$exportcontenttype, $exportfilename);
}
########## END EXPORTVCARD #######################################


####################### MAKE VCARD ############################
sub make_vcard {
   # This sub gets a hash ref with the fields for each record of
   # the imported file (csv/tab, or others), and returns one vcard hash.
   my ($ref, $x_owm_uid) = @_;
   my %data = %{$ref};  #just for easier typing on the structure...
   my ($rev_sec,$rev_min,$rev_hour,$rev_mday,$rev_mon,$rev_year) =
            gmtime(ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'}));

   # Field mapping: Key is the 'foreign' field name, value is the local, used on the $vcard assignment below.
   # If new csv/tab sources are to be supported, and there are foreign field names to be associated to ones
   # already here, just add it there will be two elements on the hash with different keys, same values, no problem.
   my %fieldmap = (
      'e-mail address' => 'email',
      'middle name' => 'middle',
      'last name' => 'last',
      'first name' => 'first',
      'title' => 'prefix',
      'notes' => 'note',
      'primary phone' => 'phone'
   );

   map {
       unless ($data{$fieldmap{$_}}) {
          $data{$fieldmap{$_}} = $data{$_};
          delete $data{$_};
       }
   } keys(%fieldmap);

   if ($data{'first'}.$data{'middle'}.$data{'last'} eq '') {
      if ($data{'fullname'} ne '') {
         # Split Full Name if First, Middle, Last not provided
         my @splitname = split(/ /, $data{'fullname'});
         $data{'first'} = shift(@splitname);
         if ($#splitname > -1) {
            $data{'last'} = pop(@splitname);
            $data{'middle'} = join(" ", @splitname) if ($#splitname > -1);
         } else {
            # If Full Name was not provided either, nor Prefix, Title, Suffix, something must be there
            $data{'first'} = $lang_text{'none'} if ($data{'prefix'}.$data{'title'}.$data{'suffix'} eq '');
         }
      }
   }

   if ($data{'birthday'} && !($data{'birthday'} =~ /0.0.00/) && ($data{'birthday'} =~ /(\d{1,2})\D(\d{1,2})\D(\d{2,4})/)) {
      my ($m, $d, $y) = ($1, $2, $3);
      if ($m >= 1 && $m <= 12 && $d >=1 && $d <= 31) {
         ($data{'bmonth'}, $data{'bday'}, $data{'byear'}) = ($m, $d, $y);
         $data{'byear'} += ($y > 10)?1900:2000 if ($y < 1900);
      }
   }
   $data{'private'} = (exists($data{'private'}) && (lc($data{'private'}) eq 'false'))?"Public":"Private";

   my $vcard;

   # ADR - Left here for future reference
   #
   # ${$vcard}{ADR}[x]{TYPES} = {
   #                             'BASE64' => 'ENCODING',
   #                             'DOM' => 'TYPE',
   #                             'HOME' => 'TYPE',
   #                             'INTL' => 'TYPE',
   #                             'PARCEL' => 'TYPE',
   #                             'POSTAL' => 'TYPE',
   #                             'WORK' => 'TYPE'
   #                            };
   # ${$vcard}{ADR}[x]{VALUE} = {
   #                             'COUNTRY' => '',
   #                             'EXTENDEDADDRESS' => '',
   #                             'LOCALITY' => '',
   #                             'POSTALCODE' => '',
   #                             'POSTOFFICEADDRESS' => '',
   #                             'REGION' => '',
   #                             'STREET' => ''
   #                            };

   # OL2k's exported po box is not associated to business/home/other, we'll have to arbitrarily
   # assign it:
   if ($data{'po box'}) {
      if ($data{'business country'}) {
         $data{'business po box'} = $data{'po box'};
      } elsif ($data{'home country'}) {
         $data{'home po box'} = $data{'po box'};
      } else {
         $data{'other po box'} = $data{'po box'};
      }
   }

   my %eaddr;
   map {
       if ($data{"$_ street 2"} || $data{"$_ street 3"}) {
          $eaddr{$_} = $data{"$_ street 2"}.", ".$data{"$_ street 3"};
          $eaddr{$_} =~ s/^, |, $//;
          delete @data{("$_ street 2", "$_ street 3")};
       }
      my %adr;
      $adr{TYPES} = {
                     'BASE64' => 'ENCODING',
                     'WORK' => 'TYPE'
                    };
      $adr{VALUE} = {
                     'COUNTRY' => $data{"$_ country"},
                     'EXTENDEDADDRESS' => $eaddr{"$_"},
                     'LOCALITY' => $data{"$_ city"},
                     'POSTALCODE' => $data{"$_ postal code"},
                     'POSTOFFICEADDRESS' => $data{"$_ po box"},
                     'REGION' => $data{"$_ state"},
                     'STREET' => $data{"$_ street"}
                    };
      push @{${$vcard}{ADR}}, \%adr;
      delete @data{("$_ country", "$_ city", "$_ postal code", "$_ po box", "$_ state", "$_ street")};
   } qw(business home other);

   ${$vcard}{BDAY}[0]{VALUE} = {
                                'DAY' => $data{'bday'},
                                'MONTH' => $data{'bmonth'},
                                'YEAR' => $data{'byear'}
                               };
   @{${$vcard}{CATEGORIES}[0]{VALUE}{CATEGORIES}} = split(/;/, $data{'categories'});
   ${$vcard}{CLASS}[0]{VALUE} = $data{'private'};
   ${$vcard}{EMAIL}[0]{TYPES} = {
                                 'PREF' => 'TYPE'
                                };
   ${$vcard}{EMAIL}[0]{VALUE} = $data{'email'};
   ${$vcard}{EMAIL}[1]{VALUE} = $data{'email 2 address'};
   ${$vcard}{EMAIL}[2]{VALUE} = $data{'email 3 address'};
   ${$vcard}{EMAIL}[3]{TYPES} = {
                                 'TLX' => 'TYPE'
                                };
   ${$vcard}{EMAIL}[3]{VALUE} = $data{'telex'};

   # ${$vcard}{FN}[0]{VALUE} = '';
   # ${$vcard}{GEO}[0]{VALUE} = {
   #                             'LATITUDE' => '',
   #                             'LONGITUDE' => ''
   #                            };
   # ${$vcard}{LABEL}[0]{TYPES} = {
   #                               'BASE64' => 'ENCODING',
   #                               'DOM' => 'TYPE',
   #                               'HOME' => 'TYPE',
   #                               'INTL' => 'TYPE',
   #                               'PARCEL' => 'TYPE',
   #                               'POSTAL' => 'TYPE',
   #                               'WORK' => 'TYPE'
   #                              };
   # ${$vcard}{LABEL}[0]{VALUE} = '';

   ${$vcard}{MAILER}[0]{VALUE} = 'OpenWebmail';
   ${$vcard}{N}[0]{VALUE} = {
                             'ADDITIONALNAMES' => $data{'middle'},
                             'FAMILYNAME' => $data{'last'},
                             'GIVENNAME' => $data{'first'},
                             'NAMEPREFIX' => $data{'prefix'},
                             'NAMESUFFIX' => $data{'suffix'}
                            };
   ${$vcard}{NAME}[0]{VALUE} =  "vCard for $data{'first'} $data{'last'}" if ($data{'first'} || $data{'last'});
   ${$vcard}{NICKNAME}[0]{VALUE} = $data{'nickname'};
   ${$vcard}{NOTE}[0]{VALUE} = $data{'note'};
   ${$vcard}{ORG}[0]{VALUE} = {
                               'ORGANIZATIONALUNITS' => [ $data{'department'} ],
                               'ORGANIZATIONNAME' => $data{'company'}
                              };
   ${$vcard}{PRODID}[0]{VALUE} = "OpenWebmail $config{'version'} $config{'releasedate'}";
   ${$vcard}{REV}[0]{VALUE} = {
                               'DAY' => $rev_mday,
                               'HOUR' => $rev_hour,
                               'MINUTE' => $rev_min,
                               'MONTH' => $rev_mon,
                               'SECOND' => $rev_sec,
                               'YEAR' => $rev_year
                              };
   ${$vcard}{ROLE}[0]{VALUE} = $data{'job title'};
   ${$vcard}{'SORT-STRING'}[0]{VALUE} = $data{'last'};
   # ${$vcard}{SOURCE}[0]{VALUE} = '';
   ${$vcard}{TEL}[0]{TYPES} = {
                               'PREF' => 'TYPE',
                               'VOICE' => 'TYPE'
                              };
   ${$vcard}{TEL}[0]{VALUE} = $data{'phone'};
   ${$vcard}{TEL}[1]{TYPES} = {
                               'HOME' => 'TYPE',
                               'VOICE' => 'TYPE'
                              };
   ${$vcard}{TEL}[1]{VALUE} = $data{'home phone'};
   ${$vcard}{TEL}[2]{TYPES} = {
                               'HOME' => 'TYPE',
                               'VOICE' => 'TYPE'
                              };
   ${$vcard}{TEL}[2]{VALUE} = $data{'home phone 2'};
   ${$vcard}{TEL}[3]{TYPES} = {
                               'VOICE' => 'TYPE'
                              };
   ${$vcard}{TEL}[3]{VALUE} = $data{'radio phone'};
   ${$vcard}{TEL}[4]{TYPES} = {
                               'VOICE' => 'TYPE'
                              };
   ${$vcard}{TEL}[4]{VALUE} = $data{'other phone'};
   ${$vcard}{TEL}[5]{TYPES} = {
                               'HOME' => 'TYPE',
                               'FAX' => 'TYPE'
                              };
   ${$vcard}{TEL}[5]{VALUE} = $data{'home fax'};
   ${$vcard}{TEL}[6]{TYPES} = {
                               'FAX' => 'TYPE'
                              };
   ${$vcard}{TEL}[6]{VALUE} = $data{'other fax'};
   ${$vcard}{TEL}[7]{TYPES} = {
                               'CELL' => 'TYPE',
                               'VOICE' => 'TYPE'
                              };
   ${$vcard}{TEL}[7]{VALUE} = $data{'mobile phone'};
   ${$vcard}{TEL}[8]{TYPES} = {
                               'WORK' => 'TYPE',
                               'VOICE' => 'TYPE'
                              };
   ${$vcard}{TEL}[8]{VALUE} = $data{'company main phone'};
   ${$vcard}{TEL}[9]{TYPES} = {
                               'WORK' => 'TYPE',
                               'VOICE' => 'TYPE'
                              };
   ${$vcard}{TEL}[9]{VALUE} = $data{'business phone'};
   ${$vcard}{TEL}[10]{TYPES} = {
                                'WORK' => 'TYPE',
                                'VOICE' => 'TYPE'
                               };
   ${$vcard}{TEL}[10]{VALUE} = $data{'business phone 2'};
   ${$vcard}{TEL}[11]{TYPES} = {
                                'CAR' => 'TYPE',
                                'VOICE' => 'TYPE'
                               };
   ${$vcard}{TEL}[11]{VALUE} = $data{'car phone'};
   ${$vcard}{TEL}[12]{TYPES} = {
                                'PAGER' => 'TYPE'
                               };
   ${$vcard}{TEL}[12]{VALUE} = $data{'pager'};
   ${$vcard}{TEL}[13]{TYPES} = {
                                'MODEM' => 'TYPE'
                               };
   ${$vcard}{TEL}[13]{VALUE} = $data{'tty/tdd phone'};
   ${$vcard}{TEL}[14]{TYPES} = {
                                'MSG' => 'TYPE',
                                'WORK' => 'TYPE',
                                'VOICE' => 'TYPE'
                               };
   ${$vcard}{TEL}[14]{VALUE} = $data{'assistants phone'};
   ${$vcard}{TEL}[15]{TYPES} = {
                                'MSG' => 'TYPE',
                                'VOICE' => 'TYPE'
                               };
   ${$vcard}{TEL}[15]{VALUE} = $data{'callback'};
   ${$vcard}{TEL}[16]{TYPES} = {
                                'FAX' => 'TYPE',
                                'WORK' => 'TYPE'
                               };
   ${$vcard}{TEL}[16]{VALUE} = $data{'business fax'};
   ${$vcard}{TEL}[17]{TYPES} = {
                                'ISDN' => 'TYPE'
                               };
   ${$vcard}{TEL}[17]{VALUE} = $data{'isdn'};
   # ${$vcard}{TITLE}[0]{VALUE} = ''; #Don't use $data{'title'} here; OL2k uses 'title' as the name prefix
   ${$vcard}{TZ}[0]{VALUE} = $prefs{'timeoffset'};
   # ${$vcard}{UID}[0]{VALUE} = '';
   ${$vcard}{URL}[0]{VALUE} = $data{'web page'};
   ${$vcard}{VERSION}[0]{VALUE} = '3.0';
   ${$vcard}{'X-OWM-UID'}[0]{VALUE} = $x_owm_uid;
   ${$vcard}{'X-OWM-CHARSET'}[0]{VALUE} = param('importcharset');
   ${$vcard}{'X-MICROSOFT-FBURL'}[0]{VALUE} = $data{'internet free busy'};

   # Delete imported elements (note: some were deleted above on map{} cases).
   delete @data{(
      'assistants phone', 'bday', 'birthday', 'bmonth', 'business fax', 'business phone',
      'business phone 2', 'byear', 'callback', 'car phone', 'categories', 'company',
      'company main phone', 'department', 'email', 'email 2 address', 'email 3 address',
      'first', 'home fax', 'home phone', 'home phone 2', 'internet free busy', 'isdn',
      'job title', 'last', 'middle', 'mobile phone', 'nickname', 'note', 'other fax',
      'other phone', 'pager', 'phone', 'po box', 'prefix', 'private', 'radio phone',
      'suffix', 'telex', 'tty/tdd phone', 'web page'
   )};

   # These ones (from OL2k) we don't want:
   delete @data{(
      'e-mail type', 'e-mail 2 type', 'e-mail 3 type', 'priority', 'sensitivity'
   )};

   # Custom fields: Whatever is in the imported file, not mapped to an OWM field.
   foreach (sort(keys(%data))) {
      next unless ($data{$_});
      next if (($data{$_} =~ /^0{1,2}\D0{1,2}\D0{2,4}$/) || ($data{$_} eq 'Unspecified'));
      my %custom;
      $custom{VALUE}{CUSTOMNAME} = uc($_);
      ${$custom{VALUE}{CUSTOMVALUES}}[0] = $data{$_};
      push @{${$vcard}{'X-OWM-CUSTOM'}}, \%custom;
   }

   return $vcard;
}
########################### END MAKE VCARD ##########################


########################### MAKE FLATHASH ##########################
sub make_flathash {
   # This sub will get one vcard structure and make a "flat" hash
   # (i.e., one key per scalar value), which is then used to export to
   # the other formats.
   my %flathash = ();
   my $vcard = $_[0];

   foreach my $propertyname (keys %{ $vcard }) {
      next if ($propertyname =~ /^(?:PHOTO|LOGO|SOUND|KEY|AGENT)$/);
      my @instances = @{ ${ $vcard }{$propertyname} };
      for (my $i = 0; $i <= $#instances; $i++) {
         my $index = ($#instances > 0)?'_'.sprintf("%02d", $i):'';
         my %instance = %{ $instances[$i] };
         my $hasvalue = 0;
         if (ref($instance{VALUE})) {
            foreach (sort keys %{ $instance{VALUE} }) {
               if (${ $instance{VALUE} }{$_}) {
                  if (ref(${ $instance{VALUE} }{$_})) {
                     my @values = @{ ${ $instance{VALUE} }{$_} };
                     for (my $j = 0; $j <= $#values; $j++) {
                        my $vindex = ($#values > 0)?'_'.sprintf("%02d", $j):'';
                        $flathash{$propertyname.$index."_$_".$vindex} = ${ ${ $instance{VALUE} }{$_} }[$j];
                     }
                  } else {
                     $flathash{$propertyname.$index."_$_"} = ${ $instance{VALUE} }{$_};
                  }
                  $hasvalue++;
               }
            }
         } elsif ($instance{VALUE}) {
            $flathash{$propertyname.$index} = $instance{VALUE};
            $hasvalue++;
         }
         if ($hasvalue) {
            if (exists($instance{TYPES}) && scalar(%{ $instance{TYPES} })) {
               $flathash{$propertyname.$index.'_TYPE'} = join("; ", sort(keys(%{ $instance{TYPES} })));
            }
            if (exists($instance{GROUP})) {
               $flathash{$propertyname.$index.'_GROUP'} = $instance{GROUP};
            }
         }
      }
   }
   $flathash{'X-OWM-CHARSET'} = $prefs{'charset'} unless (exists $flathash{'X-OWM-CHARSET'});

   if ((param('exportcharset') ne $lang_text{'abook_noconversion'}) &&
       ($flathash{'X-OWM-CHARSET'} ne param('exportcharset')) &&
       is_convertible($flathash{'X-OWM-CHARSET'}, param('exportcharset'))) {

      my %convertedflathash= ();
      my ($convfrom, $convto) = ($flathash{'X-OWM-CHARSET'}, param('exportcharset'));
      $flathash{'X-OWM-CHARSET'} = param('exportcharset');
      foreach (keys(%flathash)) {
         ($convertedflathash{$_}) = iconv($convfrom, $convto, $flathash{$_});
      }
      return \%convertedflathash;

   }
   return \%flathash;
}
########################## END MAKE FLATHASH #######################


########################## EXPORTTXT ################################
sub exporttxt {
   # accepts a vCard hash data structure passed in and returns a csv format string.
   # The export order is up to you. User can't pick export order for now.
   my ($r_addresses, $version, $fs) = @_; # r_addresses is a ref to a vcard_hash_structure
                                          # version is blank for this export type
   my $ext = ($fs eq ',')?"csv":"tab";
   my ($exportcontenttype, $exportfilename) = ('application/', "$lang_text{'export'}.$ext");

   #### iterate through the vcard hash converting data ####
   my %fields = ();
   my @records = ();

   foreach my $x_owm_uid (keys %{ $r_addresses }) {
      my $vcard = ${ $r_addresses }{$x_owm_uid};
      my $flathash = make_flathash($vcard);
      map { $fields{$_} = 1 } keys(%{ $flathash });   # It is possible that not all vcards have all properties/values
      push @records, $flathash;                       # so we need to see them all before knowing which columns exist
   }                                                  # or export a LOT of empty csv columns, exporting them all.

   my @columns = sort(keys(%fields));
   undef(%fields);
   my $exportdata = join($fs, @columns)."\n";
   foreach my $record (@records) {
      my @values = ();
      foreach my $key (@columns) {
         $_ = ${ $record }{$key} || '';
         s/"/""/g;
         if (/$fs|\n/) {
            $_ = qq|"$_"|;
         }
         push @values, $_;
      }
      $exportdata .= join($fs, @values)."\n";
   }
   return ($exportdata, $exportcontenttype, $exportfilename);
}
######################### END EXPORTTXT #############################


########## EXPORTCSV #############################################
sub exportcsv {
   # accepts a vCard hash data structure and returns a csv format string
   my ($r_addresses, $version) = @_;
   return exporttxt($r_addresses, $version, ",");
}
########## END EXPORTCSV #########################################


########## EXPORTTAB #############################################
sub exporttab {
   # accepts a vCard hash data structure and returns a tab delimited format string
   my ($r_addresses, $version) = @_;
   return exporttxt($r_addresses, $version, "\t");
}
########## END EXPORTTAB #########################################


########## EXPORTPINE ############################################
sub exportpine {
   # TO BE DONE
   # accepts a vCard hash data structure and returns a pine addressbook format string
   my ($r_addresses, $version) = @_;
   my ($exportcontenttype, $exportfilename) = ('application/', "$lang_text{'export'}.pine");
}
########## END EXPORTPINE ########################################


########## EXPORTLDIF ############################################
sub exportldif {
   # TO BE DONE
   # accepts a vCard hash data structure and an ldif format string
   my ($r_addresses, $version) = @_;
   my ($exportcontenttype, $exportfilename) = ('application/', "$lang_text{'export'}.ldif");
}
########## END EXPORTLDIF ########################################


# The old pine routines for the developer who writes the new import/export routines for pine
########## IMPORT/EXPORTABOOK PINE ###############################
#sub importabook_pine {
#   my $addrbookfile=dotpath('address.book');
#
#   if ( ! -f $addrbookfile ) {
#      sysopen(ABOOK, $addrbookfile, O_WRONLY|O_APPEND|O_CREAT); # Create if nonexistent
#      close(ABOOK);
#   }
#
#   if (sysopen(PINEBOOK,"$homedir/.addressbook", O_RDONLY) ) {
#      my ($name, $email, $note);
#      my (%addresses, %notes);
#      my $abooktowrite='';
#
#      ow::filelock::lock($addrbookfile, LOCK_EX|LOCK_NB) or
#         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $addrbookfile!");
#
#      my ($stat,$err,@namelist)=read_abook($addrbookfile, \%addresses, \%notes);
#      openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);
#
#      while (<PINEBOOK>) {
#         my ($name, $email, $note) = (split(/\t/, $_,5))[1,2,4];
#         chomp($email);
#         chomp($note);
#         next if ($email=~/^\s*$/);  # skip if email is null
#         $addresses{"$name"} = $email;
#         $notes{"$name"}=$note;
#      }
#      close(PINEBOOK);
#
#      # replace the address book
#      ($stat,$err)=write_abook($addrbookfile,$config{'maxbooksize'},\%addresses,\%notes);
#      openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);
#
#      ow::filelock::lock($addrbookfile, LOCK_UN);
#
#      writelog("import pine addressbook - $homedir/.addressbook");
#      writehistory("import pine addressbook - $homedir/.addressbook");
#   }
#   editaddresses();
#}
#
#sub exportabook_pine {
#   my $addrbookfile=dotpath('address.book');
#
#   if (-f $addrbookfile) {
#      ow::filelock::lock($addrbookfile, LOCK_SH) or
#         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $addrbookfile!");
#
#      my (%nicknames, %emails, %fccs, %notes);
#      my ($nickname, $name, $email, $fcc, $note);
#      my $abooktowrite='';
#
#      my ($stat,$err,@namelist)=read_abook($addrbookfile, \%emails, \%notes);
#      openwebmailerror(__FILE__, __LINE__, $err) if ($stat<0);
#
#      ow::filelock::lock($addrbookfile, LOCK_UN);
#
#      ow::filelock::lock("$homedir/.addressbook", LOCK_EX) or
#         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} $homedir/.addressbook!");
#
#      if (sysopen(PINEBOOK, "$homedir/.addressbook", O_RDONLY)) {
#         while (<PINEBOOK>) {
#            my ($nickname, $name, $email, $fcc, $note) = (split(/\t/, $_,5))[1,2,4];
#            foreach ($nickname, $name, $email, $fcc, $note) { chomp; }
#            next if ($email=~/^\s*$/);  # skip if email is null
#            $nicknames{$name}=$nickname;
#            $emails{$name} = $email;
#            $fccs{$name}=$fcc;
#            $notes{$name}=$note;
#         }
#         close(PINEBOOK);
#      }
#
#      sysopen(PINEBOOK,"$homedir/.addressbook", O_WRONLY|O_TRUNC|O_CREAT) or
#         openwebmailerror(__FILE__, __LINE__, "couldnt_write $homedir/.address.book! ($!)");
#
#      foreach (sort keys %emails) {
#         $abooktowrite .= join("\t", $nicknames{$_}, $_,
#                                     $emails{$_}, $fccs{$_}, $notes{$_})."\n";
#      }
#      print PINEBOOK $abooktowrite;
#      close(PINEBOOK);
#      ow::filelock::lock("$homedir/.addressbook", LOCK_UN);
#
#      writelog("emport addressbook to pine, $homedir/.addressbook");
#      writehistory("emport addressbook to pine, $homedir/.addressbook");
#   }
#   editaddresses();
#}
########## END IMPORT/EXPORTABOOK PINE ###########################
