#!/usr/bin/suidperl -T
#
# openwebmail-adsearch.pl - advanced search program
#
# 2002/06/29 filippo@sms.it
#

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
use CGI::Carp qw(fatalsToBrowser carpout);
CGI::nph();   # Treat script as a non-parsed-header script

require "ow-shared.pl";
require "filelock.pl";
require "mime.pl";
require "iconv.pl";
require "maildb.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style %icontext);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

openwebmail_init();
verifysession();

# extern vars
use vars qw($_OFFSET $_FROM $_TO $_DATE $_SUBJECT $_CONTENT_TYPE $_STATUS $_SIZE $_REFERENCES $_CHARSET); # defined in maildb.pl
use vars qw(%lang_folders %lang_advsearchlabels %lang_text %lang_err);	# defined in lang/xy

########################## MAIN ##############################
my $action = param("action");
if ($action eq "advsearch") {
   advsearch();
} else {
   openwebmailerror("Action $lang_err{'has_illegal_chars'}");
}
###################### END MAIN ##############################

#################### ADVSEARCH ###########################
sub advsearch {
   my @search;

   for (my $i=0; $i<3; $i++) {
      my $text=param("searchtext$i"); $text=~s/^\s*//; $text=~s/\s*$//;
      push(@search, {where=>param("where$i")||'', type=>param("type$i")||'', text=>$text||''} );
   }

   my $resline = param("resline") || $prefs{'msgsperpage'};
   my @folders = param("folders");
   for (my $i=0; $i<=$#folders; $i++) {
      $folders[$i]=safefoldername($folders[$i]);
   }

   my ($html, $temphtml);

   printheader();

   $html=readtemplate("advsearch.template");
   $html = applystyle($html);

   ## replace @@@MENUBARLINKS@@@ ##
   $temphtml = iconlink("backtofolder.gif", "$lang_text{'backto'} $printfolder", qq|accesskey="B" href="$config{'ow_cgiurl'}/openwebmail-main.pl?action=listmessages&amp;sessionid=$thissession&amp;folder=$escapedfolder"|). qq| \n|;
   $html =~ s/\@\@\@MENUBARLINKS\@\@\@/$temphtml/g;

   ## replace @@@STARTADVSEARCHFORM@@@ ##
   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-advsearch.pl",
                         -name=>'advsearchform') .
                  hidden(-name=>'action',
                         -value=>'advsearch',
                         -override=>'1') .
                  hidden(-name=>'sessionid',
                         -value=>$thissession,
                         -override=>'1');
   $html =~ s/\@\@\@STARTADVSEARCHFORM\@\@\@/$temphtml/;

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
                             -labels=>\%lang_advsearchlabels);
      $html =~ s/\@\@\@TYPEMENU$i\@\@\@/$temphtml/;

      $temphtml = textfield(-name=>"searchtext$i",
                            -default=>${$search[$i]}{'text'},
                            -size=>'40',
                            -accesskey=>$i+1,
                            -override=>'1');
      $html =~ s/\@\@\@SEARCHTEXT$i\@\@\@/$temphtml/;
   }

   $temphtml = submit(-name=>"$lang_text{'search'}",
                      -accesskey=>'S',
                      -class=>"medtext");
   $html =~ s/\@\@\@BUTTONSEARCH\@\@\@/$temphtml/;

   $temphtml = textfield(-name=>"resline",
                         -default=>"$resline",
                         -size=>'5',
                         -accesskey=>'L',
                         -override=>'1');
   $html =~ s/\@\@\@RESLINE\@\@\@/$temphtml/;

   $temphtml = qq|<table cols=4 width="100%">\n|;
   for(my $i=0; $i<=$#validfolders; $i++) {
      $temphtml.=qq|<tr>| if ($i%4==0);
      $temphtml.=qq|<td>|;
      if($validfolders[$i] eq 'INBOX') {
         $temphtml .= checkbox(-name=>'folders',
                               -value=>$validfolders[$i],
                               -checked=>1,
                               -label=>'').
                      $lang_folders{$validfolders[$i]};
      } else {
         my $folderstr=$validfolders[$i];
         if ( defined($lang_folders{$validfolders[$i]}) ) {
            $folderstr=$lang_folders{$validfolders[$i]};
         }
         $temphtml .= checkbox(-name=>'folders',
                               -value=>$validfolders[$i],
                               -label=>'').
                      $folderstr;
      }
      $temphtml.=qq|</td>|;
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
   $temphtml = $lang_text{'subject'};
   $html =~ s/\@\@\@SUBJECT\@\@\@/$temphtml/g;

   my ($totalfound, $resulthtml);
   if( ${$search[0]}{'text'} eq '' && ${$search[1]}{'text'}  eq '' && ${$search[2]}{'text'}  eq '') {
      $temphtml = "";
      $html =~ s/\@\@\@TOTALFOUND\@\@\@/$temphtml/g;
      $html =~ s/\@\@\@SEARCHRESULT\@\@\@/$temphtml/g;
   } elsif ($#folders < 0) {
      $temphtml = $lang_text{'nofoldersel'};
      $html =~ s/\@\@\@TOTALFOUND\@\@\@/$temphtml/g;
      $temphtml = "";
      $html =~ s/\@\@\@SEARCHRESULT\@\@\@/$temphtml/g;
   } else {
      my $r_result = search_folders(\@search, \@folders, "$folderdir/.search.cache");
      my $totalfound= $#{$r_result}+1;
      if ($totalfound <= $resline) {
         $html =~ s/\@\@\@TOTALFOUND\@\@\@/$totalfound/g;
      } else {
         my $escapedfolders;
         foreach (@folders) {
            $escapedfolders .= "folders=".escapeURL($_)."&amp;";
         }
         my $showall_url=qq|$config{'ow_cgiurl'}/openwebmail-advsearch.pl?sessionid=$thissession|.
                         qq|&amp;action=advsearch|.
                         qq|&amp;where0=${$search[0]}{'where'}&amp;type0=${$search[0]}{'type'}&amp;searchtext0=|.escapeURL(${$search[0]}{'text'}).
                         qq|&amp;where1=${$search[1]}{'where'}&amp;type1=${$search[1]}{'type'}&amp;searchtext1=|.escapeURL(${$search[1]}{'text'}).
                         qq|&amp;where2=${$search[2]}{'where'}&amp;type2=${$search[2]}{'type'}&amp;searchtext2=|.escapeURL(${$search[2]}{'text'}).
                         qq|&amp;resline=$totalfound&amp;$escapedfolders|;
         $temphtml=qq|$totalfound &nbsp;<a href="$showall_url">[$lang_text{'showall'}]</a>|;
         $html =~ s/\@\@\@TOTALFOUND\@\@\@/$temphtml/g;
      }

      $temphtml="";
      for (my $i=0; $i<$totalfound; $i++) {
         last if ($i>$resline);
         $temphtml.=genline($i%2, split(/\@\@\@/, ${$r_result}[$i]));
      }
      $html =~ s/\@\@\@SEARCHRESULT\@\@\@/$temphtml/g;
   }

   print $html;

   printfooter(2);
}
################### END ADVSEARCH ########################

################### SEARCH_FOLDERS ########################
sub search_folders {
   my ($r_search, $r_folders, $cachefile)=@_;
   my ($metainfo, $cache_metainfo, $r_result);

   foreach my $search (@{$r_search}) {
      if (${$search}{'text'} ne "") {
         $metainfo.=join("@@@", ${$search}{'where'}, ${$search}{'type'}, ${$search}{'text'});
      }
   }
   $metainfo.="@@@".join("@@@", @{$r_folders});

   ($cachefile =~ /^(.+)$/) && ($cachefile = $1);		# untaint ...
   filelock($cachefile, LOCK_EX) or
      openwebmailerror("$lang_err{'couldnt_lock'} $cachefile");
   if ( -e $cachefile ) {
      open(CACHE, "$cachefile") ||  openwebmailerror("$lang_err{'couldnt_open'} $cachefile!");
      $cache_metainfo=<CACHE>; chomp($cache_metainfo);
      close(CACHE);
   }

   if ( $cache_metainfo ne $metainfo ) {
      open(CACHE, ">$cachefile");
      print CACHE $metainfo, "\n";
      $r_result=search_folders2($r_search, $r_folders);
      print CACHE join("\n", $#{$r_result}+1,  @{$r_result});
      close(CACHE);

   } else {
      my @result;
      open(CACHE, $cachefile);
      $_=<CACHE>;
      my $totalfound=<CACHE>;
      while (<CACHE>) {
         chomp;
         push (@result, $_)
      }
      close(CACHE);
      $r_result=\@result;
   }

   filelock($cachefile, LOCK_UN);

   return($r_result);
}

sub search_folders2 {
   my ($r_search, $r_folders)=@_;
   my (@validsearch, %found);
   my @result;

   foreach my $search (@{$r_search}) {
      push(@validsearch, $search) if (${$search}{'text'} ne "");
   }

   # search for the messageid in selected folder, return @result
   foreach my $foldertosearch (@{$r_folders}) {
      my ($folderfile, $headerdb)=get_folderfile_headerdb($user, $foldertosearch);
      my ($totalsize, $new, $r_messageids)=get_info_messageids_sorted_by_date($headerdb, 1);
      my (%HDB, %status);

      if (!$config{'dbmopen_haslock'}) {
         filelock("$headerdb$config{'dbm_ext'}", LOCK_SH) or
            openwebmailerror("$lang_err{'couldnt_locksh'} $headerdb$config{'dbm_ext'}");
      }
      dbmopen (%HDB, "$headerdb$config{'dbmopen_ext'}", undef);

      foreach my $messageid (@{$r_messageids}) {
         # begin the search
         my ($block, $header, $body, $r_attachments);
         my @attr=split(/@@@/, $HDB{$messageid});

         my $state=0;
         my $folderhandle=FileHandle->new();
         open ($folderhandle, "+<$folderfile"); # used in TEXTCONTENT search

         foreach my $search (@validsearch) {
            my ($where, $type, $keyword) = (${$search}{'where'}, ${$search}{'type'}, ${$search}{'text'});
            my $regexvalid=is_regex($keyword);
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
                  if ( ($type eq 'contains' && $attr[$index{$where}]=~/\Q$keyword\E/i) ||
                       ($type eq 'notcontains' && $attr[$index{$where}]!~/\Q$keyword\E/i) ||
                       ($type eq 'is' && $attr[$index{$where}]=~/^\Q$keyword\E$/i) ||
                       ($type eq 'isnot' && $attr[$index{$where}]!~/^\Q$keyword\E$/i) ||
                       ($type eq 'startswith' && $attr[$index{$where}]=~/^\Q$keyword\E/i) ||
                       ($type eq 'endswith' && $attr[$index{$where}]=~/\Q$keyword\E$/i) ||
                       ($type eq 'regexp' && $regexvalid && $attr[$index{$where}]=~/$keyword/i) ) {
                     if($state == $#validsearch) {
                        $found{$messageid}=1; $state = 0;
                     } else {
                        $state++;
                     }
                     @placetosearch = ();
                     next;
                  }

               # check header
               } elsif ($where eq 'header') {
                  # check de-mimed header first since header in mail folder is raw format.
                  seek($folderhandle, $attr[$_OFFSET], 0);
                  $header="";
                  while(<$folderhandle>) {
                     $header.=$_;
                     last if ($_ eq "\n");
                  }
                  $header = decode_mimewords($header);
                  $header=~s/\n / /g;   # handle folding roughly
                  if (($type eq 'contains' && $header=~/\Q$keyword\E/im) ||
                      ($type eq 'notcontains' && $header!~/\Q$keyword\E/im) ||
                      ($type eq 'is' && $header=~/^\Q$keyword\E$/im) ||
                      ($type eq 'isnot' && $header!~/^\Q$keyword\E$/im) ||
                      ($type eq 'startswith' && $header=~/^\Q$keyword\E/im) ||
                      ($type eq 'endswith' && $header=~/\Q$keyword\E$/im) ||
                      ($type eq 'regexp' && $regexvalid && $header=~/$keyword/im)) {
                     if($state == $#validsearch) {
                        $found{$messageid}=1; $state = 0;
                     } else {
                        $state++;
                     }
                     @placetosearch = ();
                     next;
                  }

               # read and parse message
               } elsif ($where eq 'textcontent' || $where eq 'attfilename') {
                  seek($folderhandle, $attr[$_OFFSET], 0);
                  read($folderhandle, $block, $attr[$_SIZE]);
                  ($header, $body, $r_attachments)=parse_rfc822block(\$block);

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
                           $body = uudecode($body);
                        }
                        if (($type eq 'contains' && $body=~/\Q$keyword\E/im) ||
                            ($type eq 'notcontains' && $body!~/\Q$keyword\E/im) ||
                            ($type eq 'is' && $body=~/^\Q$keyword\E$/im) ||
                            ($type eq 'isnot' && $body!~/^\Q$keyword\E$/im) ||
                            ($type eq 'startswith' && $body=~/^\Q$keyword\E/im) ||
                            ($type eq 'endswith' && $body=~/\Q$keyword\E$/im) ||
                            ($type eq 'regexp' && $regexvalid && $body=~/$keyword/im)) {
                           if($state == $#validsearch) {
                              $found{$messageid}=1; $state = 0;
                           } else {
                              $state++;
                           }
                           @placetosearch = ();
                           next;
                        }
                     }

                     # check attachments
                     foreach my $r_attachment (@{$r_attachments}) {
                        if ( ${$r_attachment}{contenttype} =~ /^text/i ||
                             ${$r_attachment}{contenttype} eq "N/A" ) {   # read all for text/plain. text/html
                           if ( ${$r_attachment}{encoding} =~ /^quoted-printable/i ) {
                              ${${$r_attachment}{r_content}} = decode_qp( ${${$r_attachment}{r_content}});
                           } elsif ( ${$r_attachment}{encoding} =~ /^base64/i ) {
                              ${${$r_attachment}{r_content}} = decode_base64( ${${$r_attachment}{r_content}});
                           } elsif ( ${$r_attachment}{encoding} =~ /^x-uuencode/i ) {
                              ${${$r_attachment}{r_content}} = uudecode( ${${$r_attachment}{r_content}});
                           }
                           if (($type eq 'contains' && ${${$r_attachment}{r_content}}=~/\Q$keyword\E/im) ||
                               ($type eq 'notcontains' && ${${$r_attachment}{r_content}}!~/\Q$keyword\E/im) ||
                               ($type eq 'is' && ${${$r_attachment}{r_content}}=~/^\Q$keyword\E$/im) ||
                               ($type eq 'isnot' && ${${$r_attachment}{r_content}}!~/^\Q$keyword\E$/im) ||
                               ($type eq 'startswith' && ${${$r_attachment}{r_content}}=~/^\Q$keyword\E/im) ||
                               ($type eq 'endswith' && ${${$r_attachment}{r_content}}=~/\Q$keyword\E$/im) ||
                               ($type eq 'regexp' && $regexvalid && ${${$r_attachment}{r_content}}=~/$keyword/im)) {
                              if($state == $#validsearch) {
                                 $found{$messageid}=1; $state = 0;
                              } else {
                                 $state++;
                              }
                              @placetosearch = ();
                              @{$r_attachments} = ();
                              next;
                           }
                        }
                     }
                  }

                  # check attfilename
                  if ($where eq 'attfilename') {
                     foreach my $r_attachment (@{$r_attachments}) {
                        if (($type eq 'contains' && ${$r_attachment}{filename}=~/\Q$keyword\E/im) ||
                            ($type eq 'notcontains' && ${$r_attachment}{filename}!~/\Q$keyword\E/im) ||
                            ($type eq 'is' && ${$r_attachment}{filename}=~/^\Q$keyword\E$/im) ||
                            ($type eq 'isnot' && ${$r_attachment}{filename}!~/^\Q$keyword\E$/im) ||
                            ($type eq 'startswith' && ${$r_attachment}{filename}=~/^\Q$keyword\E/im) ||
                            ($type eq 'endswith' && ${$r_attachment}{filename}=~/\Q$keyword\E$/im) ||
                            ($type eq 'regexp' && $regexvalid && ${$r_attachment}{filename}=~/$keyword/im)) {
                           if($state == $#validsearch) {
                              $found{$messageid}=1; $state = 0;
                           } else {
                              $state++;
                           }
                           @placetosearch = ();
                           @{$r_attachments} = ();
                           next;
                        }
                     }
                  }
               } # end block check texcontent & attfilename

            } # end block placetosearch
         } # end block multiple text search

         # generate messageid table line result if found
         if($found{$messageid}) { # create the line to print into resultsearch
            push(@result, join("@@@", $foldertosearch, $messageid, @attr));
         }

      } # end messageid loop

      dbmclose(%HDB);
      filelock("$headerdb$config{'dbm_ext'}", LOCK_UN) if (!$config{'dbmopen_haslock'});
      filelock($folderfile, LOCK_UN);
   } # end foldertosearch loop

   return(\@result)
}

################### END SEARCH_FOLDERS ########################

################ GENLINE #####################
# this routines generates one line table containing folder, msgid and @attr
sub genline {
   my ($colornum, $folder, $messageid, @attr) = @_;
   my ($escapedmessageid);
   my ($offset, $from, $to, $dateserial, $subject, $content_type, $status, $messagesize, $references, $charset);
   my ($bgcolor, $message_status,$temphtml,$folderstr,$escapedfolder);

   if ( defined($lang_folders{$folder}) ) {
      $folderstr = $lang_folders{$folder};
   } else {
      $folderstr = $folder;
   }

   if ( $colornum ) {
      $bgcolor = $style{"tablerow_light"};
   } else {
      $bgcolor = $style{"tablerow_dark"};
   }

   $escapedfolder = escapeURL($folder);
   $escapedmessageid = escapeURL($messageid);
   ($offset, $from, $to, $dateserial, $subject, $content_type, $status, $messagesize, $references, $charset) = @attr;

   # convert from mesage charset to current user charset
   if (is_convertable($charset, $prefs{'charset'})) {
      ($from, $to, $subject)=iconv($charset, $prefs{'charset'}, $from, $to, $subject);
   }

   my ($from_name, $from_address)=email2nameaddr($from);
   my $escapedfrom=escapeURL($from);
   $from = qq|<a href="$config{'ow_cgiurl'}/openwebmail-send.pl\?action=composemessage&amp;sessionid=$thissession&amp;composetype=sendto&amp;to=$escapedfrom" title="$from_address">$from_name </a>|;

   $subject=substr($subject, 0, 64)."..." if (length($subject)>67);
   $subject = str2html($subject);
   if ($subject !~ /[^\s]/) {   # Make sure there's SOMETHING clickable
      $subject = "N/A";
   }

   # Round message size and change to an appropriate unit for display
   $messagesize=lenstr($messagesize,0);

   # convert dateserial(GMT) to localtime
   my $datestr=dateserial2str(add_dateserial_timeoffset($dateserial, $prefs{'timeoffset'}), $prefs{'dateformat'});
   $temphtml = qq|<tr>|.
               qq|<td nowrap bgcolor=$bgcolor>$folderstr&nbsp;</td>\n|.
               qq|<td bgcolor=$bgcolor><font size=-1>$datestr</font></td>\n|.
               qq|<td bgcolor=$bgcolor>$from</td>\n|.
               qq|<td bgcolor=$bgcolor>|.
               qq|<a href="$config{'ow_cgiurl'}/openwebmail-read.pl?action=readmessage&amp;|.
               qq|sessionid=$thissession&amp;folder=$escapedfolder&amp;|.
               qq|headers=|.($prefs{'headers'} || 'simple').qq|&amp;|.
               qq|message_id=$escapedmessageid">\n$subject \n</a></td></tr>\n|;

   return $temphtml;
}
############### END GENLINE ##################
