#!/usr/bin/suidperl -T
#
# openwebmail-adsearch.pl - advanced search program
#
# 2002/06/29 filippo@sms.it
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
use MIME::Base64;
use MIME::QuotedPrint;

require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "modules/mailparse.pl";
require "modules/htmltext.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";
require "shares/maildb.pl";
require "shares/getmsgids.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);

# extern vars
use vars qw($_OFFSET $_SIZE $_HEADERSIZE $_HEADERCHKSUM $_RECVDATE $_DATE
            $_FROM $_TO $_SUBJECT $_CONTENT_TYPE $_CHARSET $_STATUS $_REFERENCES);	# defined in maildb.pl
use vars qw(%lang_folders %lang_searchtypelabels %lang_searchdaterangelabels
            %lang_text %lang_err);	# defined in lang/xy

# local vars
use vars qw($folder);
use vars qw(%placeorder);

%placeorder= (
   from => 1,
   to => 2,
   subject => 3,
   date => 4,
   header => 5,
   all => 6,
   attfilename => 7,
   textcontent => 8
);

########## MAIN ##################################################
openwebmail_requestbegin();
userenv_init();

if (!$config{'enable_webmail'} || !$config{'enable_advsearch'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'advsearch'} $lang_err{'access_denied'}");
}

$folder = ow::tool::unescapeURL(param('folder')) || 'INBOX';

my $action = param('action')||'';
writelog("debug - request advsearch begin, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if ($action eq "advsearch") {
   advsearch();
} else {
   openwebmailerror(__FILE__, __LINE__, "Action $lang_err{'has_illegal_chars'}");
}
writelog("debug - request advsearch end, action=$action - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## ADVSEARCH #############################################
sub advsearch {
   my @search;
   for (my $i=0; $i<3; $i++) {
      my $text=param('searchtext'.$i); $text=~s/^\s*//; $text=~s/\s*$//;
      push(@search, {where=>param('where'.$i)||'', type=>param('type'.$i)||'', text=>$text||''} );
   }

   my $resline = param('resline') || $prefs{'msgsperpage'} || 10;
   my @folders = param('folders');
   for (my $i=0; $i<=$#folders; $i++) {
      $folders[$i]=safefoldername(ow::tool::unescapeURL($folders[$i]));
   }

   my ($html, $temphtml);
   $html = applystyle(readtemplate("advsearch.template"));

   ## replace @@@MENUBARLINKS@@@ ##
   my $folderstr=$lang_folders{$folder}||f2u($folder);
   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $folderstr", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;folder=|.ow::tool::escapeURL($folder).qq|"|). qq| \n|;
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   ## replace @@@STARTADVSEARCHFORM@@@ ##
   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-advsearch.pl",
                          -name=>'advsearchform').
               ow::tool::hiddens(action=>'advsearch',
                                 sessionid=>$thissession);
   $html =~ s/\@\@\@STARTADVSEARCHFORM\@\@\@/$temphtml/;


   my $localtime=ow::datetime::time_gm2local(time(), $prefs{'timeoffset'}, $prefs{'daylightsaving'}, $prefs{'timezone'});
   my ($current_year, $current_month, $current_day)=(ow::datetime::seconds2array($localtime))[5,4,3];
   $current_year+=1900; $current_month++;

   $html =~ s/\@\@\@CURRENTYEAR\@\@\@/$current_year/;
   $html =~ s/\@\@\@CURRENTMONTH\@\@\@/$current_month/;
   $html =~ s/\@\@\@CURRENTDAY\@\@\@/$current_day/;

   my $datehtml=$prefs{'dateformat'};
   $temphtml = popup_menu(-name=>"year1",
                          -values=>[1990..$current_year],
                          -default=>param('year1')||'1990');
   $datehtml =~ s/yyyy/$temphtml/;
   $temphtml = popup_menu(-name=>"month1",
                          -values=>[1..12],
                          -default=>param('month1')||'1');
   $datehtml =~ s/mm/$temphtml/;
   $temphtml = popup_menu(-name=>"day1",
                          -values=>[1..31],
                          -default=>param('day1')||'1');
   $datehtml =~ s/dd/$temphtml/;
   $html =~ s/\@\@\@STARTDATE\@\@\@/$datehtml/;

   $datehtml=$prefs{'dateformat'};
   $temphtml = popup_menu(-name=>"year2",
                          -values=>[1990..$current_year],
                          -default=>param('year2')||$current_year);
   $datehtml =~ s/yyyy/$temphtml/;
   $temphtml = popup_menu(-name=>"month2",
                          -values=>[1..12],
                          -default=>param('month2')||$current_month);
   $datehtml =~ s/mm/$temphtml/;
   $temphtml = popup_menu(-name=>"day2",
                          -values=>[1..31],
                          -default=>param('day2')||$current_day);
   $datehtml =~ s/dd/$temphtml/;
   $html =~ s/\@\@\@ENDDATE\@\@\@/$datehtml/;

   $temphtml = popup_menu(-name=>"daterange",
                          -values=>['all', 'today', 'oneweek', 'twoweeks',
                                    'onemonth', 'threemonths', 'sixmonths',
                                    'oneyear'],
                          -labels=>\%lang_searchdaterangelabels,
                          -onChange=>"setdaterange(this.value)",
                          -default=>param('daterange')||'all');
   $html =~ s/\@\@\@DATERANGEMENU\@\@\@/$temphtml/;

   my ($startserial, $endserial, $seconds);

   if (defined param('year1')) {
      $seconds=ow::datetime::array2seconds(0,0,0, param('day1'),param('month1')-1,param('year1')-1900);
   } else {
      $seconds=ow::datetime::array2seconds(0,0,0, 1,0,90);	# 1990/1/1
   }
   $startserial=ow::datetime::gmtime2dateserial(ow::datetime::time_local2gm($seconds, $prefs{'timeoffset'}, $prefs{'daylighsaving'}, $prefs{'timezone'}));

   if (defined param('year2')) {
      $seconds=ow::datetime::array2seconds(59,59,23, param('day2'),param('month2')-1,param('year2')-1900);
   } else {
      $seconds=ow::datetime::array2seconds(59,59,23, $current_day,$current_month-1,$current_year-1900);
   }
   $endserial=ow::datetime::gmtime2dateserial(ow::datetime::time_local2gm($seconds, $prefs{'timeoffset'}, $prefs{'daylighsaving'}, $prefs{'timezone'}));

   for(my $i=0; $i<=2; $i++) {
      my %labels = ('from'=>$lang_text{'from'},
                    'to'=>$lang_text{'to'},
                    'subject'=>$lang_text{'subject'},
                    'date'=>$lang_text{'date'},
                    'attfilename'=>$lang_text{'attfilename'},
                    'header'=>$lang_text{'header'},
                    'textcontent'=>$lang_text{'textcontent'},
                    'all'=>$lang_text{'all'});
      $temphtml = popup_menu(-name=>"where$i",
                             -values=>['from', 'to', 'subject', 'date', 'attfilename', 'header', 'textcontent' ,'all'],
                             -default=>${$search[$i]}{'where'}|| 'subject',
                             -labels=>\%labels);
      $html =~ s/\@\@\@WHEREMENU$i\@\@\@/$temphtml/;

      $temphtml = popup_menu(-name=>"type$i",
                             -values=>['contains', 'notcontains', 'is', 'isnot', 'startswith', 'endswith', 'regexp'],
                             -default=>${$search[$i]}{'type'} || 'contains',
                             -labels=>\%lang_searchtypelabels);
      $html =~ s/\@\@\@TYPEMENU$i\@\@\@/$temphtml/;

      $temphtml = textfield(-name=>"searchtext$i",
                            -default=>${$search[$i]}{'text'},
                            -size=>'40',
                            -accesskey=>$i+1,
                            -override=>'1');
      $html =~ s/\@\@\@SEARCHTEXT$i\@\@\@/$temphtml/;
   }

   $temphtml = submit(-name=>$lang_text{'search'},
                      -accesskey=>'S',
                      -class=>"medtext");
   $html =~ s/\@\@\@BUTTONSEARCH\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>'resline',
                         -default=>"$resline",
                         -size=>'5',
                         -accesskey=>'L',
                         -override=>'1');
   $html =~ s/\@\@\@RESLINE\@\@\@/$temphtml/;

   $temphtml = qq|<table cols=4 width="100%">\n|;

   my (@validfolders, $inboxusage, $folderusage);
   getfolders(\@validfolders, \$inboxusage, \$folderusage);

   for(my $i=0; $i<=$#validfolders; $i++) {
      my $folderstr=(defined $lang_folders{$validfolders[$i]})?
                    $lang_folders{$validfolders[$i]}:f2u($validfolders[$i]);
      $temphtml.=qq|<tr>| if ($i%4==0);
      $temphtml.=qq|<td>|.
                 checkbox(-name=>'folders',
                          -value=>ow::tool::escapeURL($validfolders[$i]),
                          -label=>'').
                 $folderstr.
                 qq|</td>|;
      $temphtml.=qq|</tr>\n| if ($i%4==3);
   }
   $temphtml.=qq|</table>|;
   $html =~ s/\@\@\@FOLDERLIST\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/g;

   $temphtml = $lang_text{'folder'};
   $html =~ s/\@\@\@FOLDER\@\@\@/$temphtml/g;
   $temphtml = $lang_text{'date'};
   $html =~ s/\@\@\@DATE\@\@\@/$temphtml/g;
   $temphtml = $lang_text{'sender'};
   $html =~ s/\@\@\@SENDER\@\@\@/$temphtml/g;
   $temphtml = $lang_text{'recipient'};
   $html =~ s/\@\@\@RECIPIENT\@\@\@/$temphtml/g;
   $temphtml = $lang_text{'subject'};
   $html =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/g;
   $temphtml = $lang_text{'size'};
   $html =~ s/\@\@\@SIZE\@\@\@/$temphtml/g;

   my ($totalfound, $resulthtml);
#   if( ${$search[0]}{'text'} eq '' && ${$search[1]}{'text'}  eq '' && ${$search[2]}{'text'}  eq '') {
   if( $startserial!~/^\d\d\d\d\d\d\d\d\d\d\d\d\d\d$/ ||
       $endserial!~/^\d\d\d\d\d\d\d\d\d\d\d\d\d\d$/ ||
       $startserial gt $endserial) {
      $temphtml = "";
      $html =~ s/\@\@\@TOTALFOUND\@\@\@/$temphtml/g;
      $html =~ s/\@\@\@SEARCHRESULT\@\@\@/$temphtml/g;
   } elsif ($#folders < 0) {
      $temphtml = $lang_text{'nofoldersel'};
      $html =~ s/\@\@\@TOTALFOUND\@\@\@/$temphtml/g;
      $temphtml = "";
      $html =~ s/\@\@\@SEARCHRESULT\@\@\@/$temphtml/g;
   } else {
      my $r_result = search_folders($startserial, $endserial, \@search, \@folders, dotpath('search.cache'));
      my $totalfound= $#{$r_result}+1;
      my $totalsize=0;
      my $r_abookemailhash;

      $r_abookemailhash=get_abookemailhash() if ($totalfound>0);
      $temphtml='';
      for (my $i=0; $i<$totalfound; $i++) {
         last if ($i>$resline);
         my $r_msg=${$r_result}[$i];
         $totalsize+=${${$r_msg}{attr}}[$_SIZE];
         $temphtml.=genline($i%2, ${$r_msg}{folder}, ${$r_msg}{msgid}, ${$r_msg}{attr}, $r_abookemailhash);
      }
      $html =~ s/\@\@\@SEARCHRESULT\@\@\@/$temphtml/g;

      $totalsize=lenstr($totalsize,1);

      if ($totalfound <= $resline) {
         $html =~ s/\@\@\@TOTALFOUND\@\@\@/$totalfound ( $totalsize )/g;
      } else {
         my $escapedfolders;
         foreach (@folders) {
            $escapedfolders .= "folders=".ow::tool::escapeURL($_)."&amp;";
         }
         my $showall_url=qq|$config{'ow_cgiurl'}/openwebmail-advsearch.pl?sessionid=$thissession|.
                         qq|&amp;action=advsearch|.
                         qq|&amp;where0=${$search[0]}{'where'}&amp;type0=${$search[0]}{'type'}&amp;searchtext0=|.ow::tool::escapeURL(${$search[0]}{'text'}).
                         qq|&amp;where1=${$search[1]}{'where'}&amp;type1=${$search[1]}{'type'}&amp;searchtext1=|.ow::tool::escapeURL(${$search[1]}{'text'}).
                         qq|&amp;where2=${$search[2]}{'where'}&amp;type2=${$search[2]}{'type'}&amp;searchtext2=|.ow::tool::escapeURL(${$search[2]}{'text'}).
                         qq|&amp;resline=$totalfound&amp;$escapedfolders|;
         foreach (qw(year1 month1 day1 year2 month2 day2 daterange)) {
            $showall_url.=qq|&amp;$_=|.param($_);
         }
         $temphtml=qq|$totalfound ( $totalsize ) &nbsp;<a href="$showall_url">[$lang_text{'showall'}]</a>|;
         $html =~ s/\@\@\@TOTALFOUND\@\@\@/$temphtml/g;
      }

   }

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}
########## END ADVSEARCH #########################################

########## SEARCH_FOLDERS ########################################
sub search_folders {
   my ($startserial, $endserial, $r_search, $r_folders, $cachefile)=@_;
   my ($metainfo, $cache_metainfo, $r_result);

   $metainfo=$startserial.'@@@'.$endserial.'@@@';
   foreach my $search (@{$r_search}) {
      if (${$search}{'text'} ne "") {
         $metainfo.=join("@@@", ${$search}{'where'}, ${$search}{'type'}, ${$search}{'text'});
      }
   }
   $metainfo.="@@@".join("@@@", @{$r_folders});

   $cachefile=ow::tool::untaint($cachefile);
   ow::filelock::lock($cachefile, LOCK_EX) or
      openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_writelock'} ".f2u($cachefile));
   if ( -e $cachefile ) {
      sysopen(CACHE, $cachefile, O_RDONLY) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_read'} ".f2u($cachefile)."! ($!)");
      $cache_metainfo=<CACHE>; chomp($cache_metainfo);
      close(CACHE);
   }

   if ( $cache_metainfo ne $metainfo ) {
      sysopen(CACHE, $cachefile, O_WRONLY|O_TRUNC|O_CREAT);
      print CACHE $metainfo, "\n";
      $r_result=search_folders2($startserial, $endserial, $r_search, $r_folders);
      print CACHE $#{$r_result}+1, "\n";
      foreach (@{$r_result}) {
         my $r_msg=$_;
         print CACHE join('@@@', ${$r_msg}{folder}, ${$r_msg}{msgid}, @{${$r_msg}{attr}}), "\n";
      }
      close(CACHE);

   } else {
      my @result;
      sysopen(CACHE, $cachefile, O_RDONLY);
      $_=<CACHE>;
      my $totalfound=<CACHE>;
      while (<CACHE>) {
         chomp;
         my ($folder, $messageid, @attr)=split(/\@\@\@/);
         push (@result, { folder=>$folder,
                          msgid=>$messageid,
                          attr=>\@attr } );
      }
      close(CACHE);
      $r_result=\@result;
   }

   ow::filelock::lock($cachefile, LOCK_UN);

   return($r_result);
}

sub search_folders2 {
   my ($startserial, $endserial, $r_search, $r_folders)=@_;
   my (@validsearch, @result);

   # put faster search in front
   foreach my $search (sort { $placeorder{${$a}{'where'}} <=>  $placeorder{${$b}{'where'}} } @{$r_search}) {
      push(@validsearch, $search) if (${$search}{'text'} ne "");
   }

   # search for the messageid in selected folder, return @result
   foreach my $foldertosearch (@{$r_folders}) {
      my ($folderfile, $folderdb)=get_folderpath_folderdb($user, $foldertosearch);

      next if (!ow::filelock::lock($folderfile, LOCK_SH|LOCK_NB));

      if (!update_folderindex($folderfile, $folderdb)<0) {
         writelog("db error - Couldn't update index db $folderdb");
         writehistory("db error - Couldn't update index db $folderdb");
         ow::filelock::lock($folderfile, LOCK_UN);
         next;
      }
      my $r_messageids=get_messageids_sorted_by_sentdate($folderdb, 1);

      my (%FDB, %status);

      ow::dbm::open(\%FDB, $folderdb, LOCK_SH) or
         openwebmailerror(__FILE__, __LINE__, "$lang_err{'couldnt_readlock'} db ".f2u($folderdb));
      sysopen(FOLDER, $folderfile, O_RDONLY); # used in TEXTCONTENT search

      foreach my $messageid (@{$r_messageids}) {
         # begin the search
         my ($block, $header, $body, $r_attachments);
         my @attr=string2msgattr($FDB{$messageid});
         my $msgcharset=$attr[$_CHARSET];
         if ($msgcharset eq '' && $prefs{'charset'} eq 'utf-8') {
            # assume msg is from sender using same language as the recipient's browser
            $msgcharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{'available_locales'})))[6];
         }

         # skip this msg if is not within date range
         next if ($attr[$_DATE] lt $startserial || $attr[$_DATE] gt $endserial);

         my $total_matched=0;
         foreach my $search (@validsearch) {
            last if ($total_matched == $#validsearch+1);

            my $is_matched=0;
            my ($where, $type, $keyword) = (${$search}{'where'}, ${$search}{'type'}, ${$search}{'text'});
            my $regexvalid=ow::tool::is_regex($keyword);
            my @placetosearch;
            if ($where eq 'all') {
               @placetosearch=('subject', 'from', 'to', 'date', 'header', 'attfilename', 'textcontent');
            } else {
               push(@placetosearch, $where);
            }

            foreach $where (@placetosearch) {

               # check subject, from, to, date
               if ($where eq 'subject' || $where eq 'from' || $where eq 'to' || $where eq 'date') {
                  my %index=(
                            subject => $_SUBJECT,
                            from    => $_FROM,
                            to      => $_TO,
                            date    => $_DATE
                            );
                  my ($data)=iconv('utf-8', $prefs{'charset'}, $attr[$index{$where}]);

                  if ( ($type eq 'contains' && $data=~/\Q$keyword\E/i) ||
                       ($type eq 'notcontains' && $data!~/\Q$keyword\E/i) ||
                       ($type eq 'is' && $data=~/^\Q$keyword\E$/i) ||
                       ($type eq 'isnot' && $data!~/^\Q$keyword\E$/i) ||
                       ($type eq 'startswith' && $data=~/^\Q$keyword\E/i) ||
                       ($type eq 'endswith' && $data=~/\Q$keyword\E$/i) ||
                       ($type eq 'regexp' && $regexvalid && $data=~/$keyword/i) ) {
                        $is_matched=1; last;
                  }

               # check header
               } elsif ($where eq 'header') {
                  # check de-mimed header first since header in mail folder is raw format.
                  seek(FOLDER, $attr[$_OFFSET], 0);
                  $header="";
                  while(<FOLDER>) {
                     $header.=$_;
                     last if ($_ eq "\n");
                  }
                  $header = decode_mimewords_iconv($header, $prefs{'charset'});
                  $header=~s/\n / /g;   # handle folding roughly

                  if (($type eq 'contains' && $header=~/\Q$keyword\E/im) ||
                      ($type eq 'notcontains' && $header!~/\Q$keyword\E/im) ||
                      ($type eq 'is' && $header=~/^\Q$keyword\E$/im) ||
                      ($type eq 'isnot' && $header!~/^\Q$keyword\E$/im) ||
                      ($type eq 'startswith' && $header=~/^\Q$keyword\E/im) ||
                      ($type eq 'endswith' && $header=~/\Q$keyword\E$/im) ||
                      ($type eq 'regexp' && $regexvalid && $header=~/$keyword/im)) {
                     $is_matched=1; last;
                  }

               # read and parse message
               } elsif ($where eq 'textcontent' || $where eq 'attfilename') {
                  seek(FOLDER, $attr[$_OFFSET], 0);
                  read(FOLDER, $block, $attr[$_SIZE]);
                  ($header, $body, $r_attachments)=ow::mailparse::parse_rfc822block(\$block);

                  # check textcontent: text in body and attachments
                  if ($where eq 'textcontent') {
                     # check body
                     if ( $attr[$_CONTENT_TYPE] =~ /^text/i ||
                          $attr[$_CONTENT_TYPE] eq "N/A" ) { # read all for text/plain,text/html
                        if ($header =~ /content-transfer-encoding:\s+quoted-printable/i) {
                           $body = decode_qp($body);
                        } elsif ($header =~ /content-transfer-encoding:\s+base64/i) {
                           $body = decode_base64($body);
                        } elsif ($header =~ /content-transfer-encoding:\s+x-uuencode/i) {
                           $body = ow::mime::uudecode($body);
                        }
                        ($body)=iconv($msgcharset, $prefs{'charset'}, $body);

                        if (($type eq 'contains' && $body=~/\Q$keyword\E/im) ||
                            ($type eq 'notcontains' && $body!~/\Q$keyword\E/im) ||
                            ($type eq 'is' && $body=~/^\Q$keyword\E$/im) ||
                            ($type eq 'isnot' && $body!~/^\Q$keyword\E$/im) ||
                            ($type eq 'startswith' && $body=~/^\Q$keyword\E/im) ||
                            ($type eq 'endswith' && $body=~/\Q$keyword\E$/im) ||
                            ($type eq 'regexp' && $regexvalid && $body=~/$keyword/im)) {
                           $is_matched=1; last;
                        }
                     }

                     # check attachments
                     foreach my $r_attachment (@{$r_attachments}) {
                        if ( ${$r_attachment}{'content-type'} =~ /^text/i ||
                             ${$r_attachment}{'content-type'} eq "N/A" ) {   # read all for text/plain. text/html
                           my $content;
                           if ( ${$r_attachment}{'content-transfer-encoding'} =~ /^quoted-printable/i ) {
                              $content = decode_qp( ${${$r_attachment}{r_content}});
                           } elsif ( ${$r_attachment}{'content-transfer-encoding'} =~ /^base64/i ) {
                              $content = decode_base64( ${${$r_attachment}{r_content}});
                           } elsif ( ${$r_attachment}{'content-transfer-encoding'} =~ /^x-uuencode/i ) {
                              $content = ow::mime::uudecode( ${${$r_attachment}{r_content}});
                           } else {
                              $content=${${$r_attachment}{r_content}};
                           }
                           my $charset=${$r_attachment}{charset}||$msgcharset;
                           ($content)=iconv($charset, $prefs{'charset'}, $content);

                           if (($type eq 'contains' && $content=~/\Q$keyword\E/im) ||
                               ($type eq 'notcontains' && $content!~/\Q$keyword\E/im) ||
                               ($type eq 'is' && $content=~/^\Q$keyword\E$/im) ||
                               ($type eq 'isnot' && $content!~/^\Q$keyword\E$/im) ||
                               ($type eq 'startswith' && $content=~/^\Q$keyword\E/im) ||
                               ($type eq 'endswith' && $content=~/\Q$keyword\E$/im) ||
                               ($type eq 'regexp' && $regexvalid && $content=~/$keyword/im)) {
                              $is_matched=1; last;
                           }
                        }
                     }
                     last if ($is_matched);
                  }

                  # check attfilename
                  if ($where eq 'attfilename') {
                     foreach my $r_attachment (@{$r_attachments}) {
                        my $charset=${$r_attachment}{filenamecharset}||${$r_attachment}{charset}||$msgcharset;
                        my ($filename)=iconv($charset, $prefs{'charset'}, ${$r_attachment}{filename});
                        if (($type eq 'contains' && $filename=~/\Q$keyword\E/im) ||
                            ($type eq 'notcontains' && $filename!~/\Q$keyword\E/im) ||
                            ($type eq 'is' && $filename=~/^\Q$keyword\E$/im) ||
                            ($type eq 'isnot' && $filename!~/^\Q$keyword\E$/im) ||
                            ($type eq 'startswith' && $filename=~/^\Q$keyword\E/im) ||
                            ($type eq 'endswith' && $filename=~/\Q$keyword\E$/im) ||
                            ($type eq 'regexp' && $regexvalid && $filename=~/$keyword/im)) {
                           $is_matched=1; last;
                        }
                     }
                     last if ($is_matched);
                  }
               } # end block check texcontent & attfilename

               last if ($is_matched);	# should no need here but just in case ...

            } # end loop placetosearch

            last if (!$is_matched);	# this seach failed, stop continuing
            $total_matched++;

         } # end loop validsearch

         # generate messageid table line result if found
         if ($total_matched == $#validsearch+1) {
            push(@result, { folder=> $foldertosearch,
                            msgid=>$messageid,
                            attr=>\@attr});
         }

      } # end messageid loop

      ow::dbm::close(\%FDB, $folderdb);
      close(FOLDER);
      ow::filelock::lock($folderfile, LOCK_UN);
   } # end foldertosearch loop

   @result= sort { ${${$b}{attr}}[$_DATE] cmp ${${$a}{attr}}[$_DATE] } @result;

   return(\@result)
}
########## END SEARCH_FOLDERS ####################################

########## GENLINE ###############################################
# this routines generates one line table containing folder, msgid and @attr
sub genline {
   my ($colornum, $folder, $messageid, $r_attr, $r_abookemailhash) = @_;

   my $bgcolor = $colornum?$style{"tablerow_light"}:$style{"tablerow_dark"};
   my $folderstr = (defined $lang_folders{$folder})?$lang_folders{$folder}:f2u($folder);
   my $escapedfolder = ow::tool::escapeURL($folder);
   my $escapedmessageid = ow::tool::escapeURL($messageid);

   my $msgcharset=${$r_attr}[$_CHARSET];
   # convert from message charset to current user charset
   if ($msgcharset eq '' && $prefs{'charset'} eq 'utf-8') {
      # assume msg is from sender using same language as the recipient's browser
      $msgcharset = (ow::lang::localeinfo(ow::lang::guess_browser_locale($config{'available_locales'})))[6];
   }

   my ($from, $to, $subject)=iconv('utf-8', $prefs{'charset'}, ${$r_attr}[$_FROM], ${$r_attr}[$_TO], ${$r_attr}[$_SUBJECT]);

   my ($from_name, $from_address)=ow::tool::email2nameaddr($from);
   my $escapedfrom=ow::tool::escapeURL($from);
   $from = qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedfrom" title="$from_address">$from_name </a>|;

   my @recvlist = ow::tool::str2list($to,0);
   my (@namelist, @addrlist);
   foreach my $recv (@recvlist) {
      my ($n, $a)=ow::tool::email2nameaddr($recv);
      # if $n or $a has ", $recv may be an incomplete addr
      push(@namelist, $n) if ($n!~/"/);
      push(@addrlist, $a) if ($a!~/"/);;
   }
   my ($to_name, $to_address)=(join(",", @namelist), join(",", @addrlist));
   $to_name=substr($to_name, 0, 29)."..." if (length($to_name)>32);
   $to_address=substr($to_address, 0, 61)."..." if (length($to_address)>64);
   my $escapedto=ow::tool::escapeURL($to);
   $to = qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedto" title="$to_address">$to_name </a>|;

   my $friendstr;
   if ($config{'enable_addressbook'} &&
       defined ${$r_abookemailhash}{$from_address}) {
      $friendstr=iconlink("friend.gif", "$lang_text{'search'} $lang_text{'addressbook'}", qq|href="$config{'ow_cgiurl'}/openwebmail-abook.pl?action=addrlistview&amp;abookkeyword=$from_address&amp;abooksearchtype=email&amp;abookfolder=ALL&amp;sessionid=$thissession&amp;folder=$escapedfolder"|);
   }
   $subject=substr($subject, 0, 64)."..." if (length($subject)>67);
   $subject = ow::htmltext::str2html($subject);
   if ($subject !~ /[^\s]/) {   # Make sure there's SOMETHING clickable
      $subject = "N/A";
   }

   # Round message size and change to an appropriate unit for display
   my $sizestr=lenstr(${$r_attr}[$_SIZE],0);
   # convert dateserial(GMT) to localtime
   my $datestr=ow::datetime::dateserial2str(${$r_attr}[$_DATE],
                               $prefs{'timeoffset'}, $prefs{'daylightsaving'},
                               $prefs{'dateformat'}, $prefs{'hourformat'}, $prefs{'timezone'});

   return qq|<tr>|.
          qq|<td nowrap bgcolor=$bgcolor>$folderstr&nbsp;</td>\n|.
          qq|<td bgcolor=$bgcolor>$datestr</td>\n|.
          qq|<td bgcolor=$bgcolor>$friendstr $from</td>\n|.
          qq|<td bgcolor=$bgcolor>$to</td>\n|.
          qq|<td bgcolor=$bgcolor>|.
          qq|<a href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;|.
          qq|sessionid=$thissession&amp;folder=$escapedfolder&amp;|.
          qq|headers=|.($prefs{'headers'} || 'simple').qq|&amp;|.
          qq|message_id=$escapedmessageid" title="$lang_text{'charset'}: $msgcharset ">\n$subject \n</a></td>|.
          qq|<td bgcolor=$bgcolor>$sizestr</td>\n|.
          qq|</tr>\n|;
}
########## END GENLINE ###########################################
