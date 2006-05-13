#!/usr/bin/suidperl -T
#
# openwebmail-spell.pl - spell check program
#
# 2003/02/19 Scott E. Campbell, scampbel.AT.gvpl.ca
#            add personal dictionary support
# 2001/09/27 tung.AT.turtle.ee.ncku.edu.tw
#            modified from WBOSS Version 1.50a
#
# WBOSS is available at http://www.dontpokebadgers.com/spellchecker/
# and is copyrighted by 2001, Joshua Cantara
#

# This is the table of valid letters for various dictionaries.
# If your dictionary checks vocabularies composed by characters other
# than english letters, you have to define new entry in below hash

use vars qw (%dictionary_letters);
if ($dictionary_letters{english} eq '') {
   %dictionary_letters =
   (
   english   => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',
   br        => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzáÁéÉíÍóÓúÚüÜõÕãÃàÀôÔêÊÇç',
   czech     => 'AÁBCÈDÏEÉÌFGHIÍJKLMNÒOÓPQRØS©T«UÚÙVWXYÝZ®aábcèdïeéìfghiíjklmnòoópqrøs¹t»uúùvwxyýz¾',
   dansk     => 'ABCDEFGHIJKLMNOPQRSTUVWXYZÆØÅabcdefghijklmnopqrstuvwxyzæøå',
   deutsch   => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzäÄöÖüÜß',
   greek     => 'ÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÓÔÕÖ×ØÙáâãäåæçèéêëìíîïðñóôõö÷øùòÜÝþÞýßü¶¸¿¹¾º¼ûúÛÚ',
   french    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzàáâäÀÁÂÄèéêëÈÉÊËìíîïÌÍÎÏòóôöÒÓÔÖùúûüÙÚÛÜ',
   magyar    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzáÁéÉíÍóÓúÚüÜõÕûÛÀÁÈÉÌÍÒÓÔÕÖÙÚÛÜàáèéêëìíòóôõö¢~ûü',
   polski    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz±æê³ñó¶¼¿¡ÆÊ£ÑÓ¦¬¯',
   slovensko => 'ABCÈDEFGHIJKLMNOPQRSŠTUVWXYZŽabcèdefghijklmnopqrsštuvwxyzž',
   spanish   => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzáÁéÉíÍóÓúÚüÜÑñ',
   ukrainian => 'ÊÃÕËÅÎÇÛÝÚÈ§Æ¦×ÁÐÒÏÌÄÖ¤­ÑÞÓÍÉÔØÂÀ\'êãõëåîçûýúè·æ¶÷áðòïìäö´½ñþóíéôøâà',
   );
}

use vars qw (%memdic);	# static dic in mem :)
if (!$memdic{a}) {
   foreach (qw(
      a an the this that one any none these those other another
      who what which when where why how
      i you he she it me him her my your his its whose
      am is are do does have has was were did had
      being doing having been done
      will would shall should may might can could able unable
      as if then since because so though however even anyway
      at on of to by in out for from over back under through just
      among between both all now begin end here there last next
      ok yes not no too either neither more less and or
      jan feb mar apr may jun jul aug sep oct nov dec
      mon tue wed thr fri sat sun today week time
      origional subject try tried found best regards thanks thank
      write wrote send sent reply replied forward forwarded
      email icq msn url web tel mobile ext eg mr dear
      http https ftp nntp smtp mime nfs html xml sgml mailto
      freebsd linux solaris gnu gpl bsd openwebmail webmail
   )) { $memdic{$_}=1;}
}

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
use IPC::Open3;

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

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);

# extern vars
use vars qw(%lang_text %lang_err);	# defined in lang/xy

########## MAIN ##################################################
openwebmail_requestbegin();
userenv_init();

if (!$config{'enable_webmail'} || !$config{'enable_spellcheck'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'spellcheck'} $lang_err{'access_denied'}");
}

# whether we are checking a html
my $htmlmode = param('htmlmode');

my $form = param('form')||'';
my $field = param('field')||'';
my $dictionary = param('dictionary') || $prefs{'dictionary'} || 'english';
$dictionary=~s!\.\.+!!g; $dictionary=~s![^A-Za-z0-9\.]!!;
my $dicletters=$dictionary_letters{'english'};
$dicletters=$dictionary_letters{$dictionary} if (defined $dictionary_letters{$dictionary});

my $spellbin=(split(/\s+/, $config{'spellcheck'}))[0];
if (! -x $spellbin) {
   openwebmailerror(__FILE__, __LINE__, "Spellcheck is not available. ( $spellbin not found )");
}

writelog("debug - request spell begin - " .__FILE__.":". __LINE__) if ($config{'debug_request'});
if (defined param('string')) {
   my ($wordcount, $wordframe, @words)=text2words($htmlmode, param('string')||'', $dicletters);
   my ($wordshtml, $error)=spellcheck_words2html($htmlmode, $wordcount, \$wordframe, \@words, $dictionary);
   docheckform($htmlmode, $form, $field, $dictionary, $wordshtml, $error, $wordcount, $wordframe);

} elsif (defined param('checkagainbutton')) {
   my ($wordcount, $wordframe, @words)=cgiparam2words();
   my ($wordshtml, $error)=spellcheck_words2html($htmlmode, $wordcount, \$wordframe, \@words, $dictionary);
   docheckform($htmlmode, $form, $field, $dictionary, $wordshtml, $error, $wordcount, $wordframe);

} elsif (defined param('finishcheckingbutton')) {
   my ($wordcount, $wordframe, @words)=cgiparam2words();
   spellcheck_words2html($htmlmode, $wordcount, \$wordframe, \@words, $dictionary);	# for updating pdict
   my $finalstring=words2text(\$wordframe, \@words, $dicletters);
   finalform($form, $field, $finalstring);

} elsif (defined param('editpdictbutton')) {
   editpdict(param('dictword2delete')||'', $dictionary);

} else {
   httpprint([], [htmlheader(), "What the heck? Invalid input for Spellcheck!", htmlfooter(1)]);
}
writelog("debug - request spell end - " .__FILE__.":". __LINE__) if ($config{'debug_request'});

openwebmail_requestend();
########## END MAIN ##############################################

########## CGI FORM ROUTINES #####################################
sub docheckform {
   my ($htmlmode, $formname, $fieldname, $dictionary,
       $wordshtml, $error, $wordcount, $wordframe) = @_;
   my $escapedwordframe;
   local $_;

   my ($html, $temphtml);
   $html = applystyle(readtemplate("spellcheck.template"));

#   $html =~ s/\@\@\@FORMNAME\@\@\@/$formname/;
#   $html =~ s/\@\@\@FIELDNAME\@\@\@/$fieldname/;
   $html =~ s/\@\@\@DICTIONARY\@\@\@/$dictionary/;
   $html =~ s/\@\@\@WORDSHTML\@\@\@/$wordshtml/;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-spell.pl",
                          -name=>'spellcheck') .
               ow::tool::hiddens(sessionid=>$thissession,
                                 htmlmode=>$htmlmode,
                                 form=>$formname,
                                 field=>$fieldname,
                                 dictionary=>$dictionary,
                                 wordcount=>$wordcount,
                                 wordframe=>ow::htmltext::str2html($wordframe));
   $html =~ s/\@\@\@STARTSPELLCHECKFORM\@\@\@/$temphtml/;

   if (defined param('checkagainbutton')) {
      $temphtml = button(-name=>'backbutton',
                         -value=>$lang_err{'back'},
                         -onclick=>'window.history.back();',
                         -override=>'1');
   } else {	# first time check, no history to back
      $temphtml = "";
   }
   if ($error>0) {
      $temphtml .= "&nbsp;&nbsp;" if (defined param('checkagainbutton'));
      $temphtml .= submit(-name=>'checkagainbutton',
                          -value=>$lang_text{'checkagain'},
                          -override=>'1');
   }
   $html =~ s/\@\@\@CHECKAGAINBUTTON\@\@\@/$temphtml/;

   $temphtml = submit(-name=>'finishcheckingbutton',
                      -value=>$lang_text{'finishchecking'},
                      -override=>'1');
   $html =~ s/\@\@\@FINISHCHECKINGBUTTON\@\@\@/$temphtml/;

   $temphtml = button(-name=>'editpdictbutton',
                      -value=>$lang_text{'editpdict'},
                      -onclick=>"window.open('$config{'ow_cgiurl'}/openwebmail-spell.pl?editpdictbutton=yes&amp;dictionary=$dictionary&amp;sessionid=$thissession','_personaldict','width=300,height=350,resizable=yes,menubar=no,scrollbars=yes');",
                      -override=>'1');
   $html =~ s/\@\@\@EDITPERSDICTIONARYBUTTON\@\@\@/$temphtml/;

   $temphtml = button(-name=>'cancelbutton',
                      -value=>$lang_text{'cancel'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(2)]);
}


sub finalform {
   my ($formname, $fieldname, $finalstring) = @_;

   # since jscript has problem in unescape doublebyte char string,
   # we only escape " to !QUOT! and unescape in jscript by RegExp
   $finalstring=~s/"/!QUOT!/g;

   print qq|Content-type: text/html

<html>
<head>
<meta HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=$prefs{'charset'}">
</head>
<body>
<form name="spellcheck">
<input type="hidden" name="finalstring" value="$finalstring">
</form>
<script language="JavaScript">
   <!--
   updateclose();

   function updateclose()
   {
      var quot = new RegExp("!QUOT!","g");

      //document.spellcheck.finalstring.value=unescape(document.spellcheck.finalstring.value);
      // unescape !QUOT! to "
      document.spellcheck.finalstring.value=(document.spellcheck.finalstring.value.replace(quot,'"'));
      window.opener.document.$formname.$fieldname.value=document.spellcheck.finalstring.value;
      window.opener.bodysethtml();
      window.close();
   }
   //-->
</script>
</body></html>|;
   return;
}


sub editpdict {
   my ($dictword2delete, $dictionary) = @_;
   local $_;

   my $html= applystyle(readtemplate("editdictionary.template"));
   my $temphtml = "";

   # use same pdicfile path as spellchecker default
   my $pdicname=$config{'spellcheck_pdicname'}; $pdicname=~s/\@\@\@DICTIONARY\@\@\@/$dictionary/;
   my $pdicfile=ow::tool::untaint("$homedir/$pdicname");

   if (-f $pdicfile) {
      if ($dictword2delete) {
         my $pdicwordstr="";
         sysopen(PERSDICT, $pdicfile, O_RDONLY) or
            openwebmailerror(__FILE__, __LINE__, "Could not open personal dictionary $pdicfile! ($!)");
         while (<PERSDICT>) {
            chomp($_);
            next if ($_ eq $dictword2delete);
            $pdicwordstr.="$_\n";
         }
         close(PERSDICT);

         sysopen(NEWPERSDICT, "$pdicfile.new", O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(__FILE__, __LINE__, "Could not open personal dictionary $pdicfile! ($!)");
         print NEWPERSDICT $pdicwordstr;
         close(NEWPERSDICT);

         rename($pdicfile, "$pdicfile.bak");
         rename("$pdicfile.new", $pdicfile);
      }

      my $count = 1;
      my $bgcolor = $style{"tablerow_light"};

      sysopen(PERSDICT, $pdicfile, O_RDONLY) or
         openwebmailerror(__FILE__, __LINE__, "Could not open personal dictionary $pdicfile! ($!)");
      while (<PERSDICT>) {
         my $dictword = $_;
         chomp($dictword);
         next if ($count==1 and $dictword=~m/personal_ws/);  # past aspell's first line

         $bgcolor=($style{"tablerow_dark"},$style{"tablerow_light"})[$count%2];
         $temphtml .= qq|<tr><td bgcolor=$bgcolor>$dictword</td>\n<td bgcolor=$bgcolor align=center>|.
                      button(-name=>'dictword2delete',
                             -value=>$lang_text{'delete'},
                             -onclick=>"window.location.href='$config{ow_cgiurl}/openwebmail-spell.pl?editpdictbutton=yes&amp;dictword2delete=$dictword&amp;sessionid=$thissession';",
                             -class=>"medtext",
                             -override=>'1').
                      qq|</td></tr>\n|;
         $count++;
      }
      close(PERSDICT);
   }
   $html =~ s/\@\@\@DICTIONARYWORDS\@\@\@/$temphtml/;

   $temphtml = start_form(-action=>"$config{'ow_cgiurl'}/openwebmail-spell.pl",
                          -name=>'spellcheck').
               ow::tool::hiddens($lang_text{'editpdict'}=>'yes',
                                 sessionid=>$thissession,
                                 dictionary=>$dictionary);
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   $temphtml = button(-name=>'closebutton',
                      -value=>$lang_text{'close'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CLOSEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(0)]);
}


########## TEXT SPLIT/JOIN #######################################
# $wordframe is a rough structure of the original text, containing no word in it.
# words of the orgignal text are put into @words.
# text -> $wordframe and @words
sub text2words {
   my ($htmlmode, $text, $dicletters)=@_;
   # init don't care term, reduce words passed to spellchecker
   my $ignore="they'll we'll you'll she'll he'll i'll ".
              "they've we've you've I've ".
              "can't couldn't won't wouldn't shouldn't ".
              "don't doesn't didn't hasn't hadn't ".
              "isn't wasn't aren't weren't ";

   # put url to ignore
   foreach my $word ($text=~m![A-Za-z]+tp://[^\s]+!ig) {
      $ignore.=" $word";
   }
   # put email to ignore
   foreach my $word ($text=~m![A-Za-z\d]+\@[A-Za-z\d]+!ig) {
      $ignore.=" $word";
   }
   # put FQDN to ignore
   foreach my $word ($text=~m![A-Za-z\d\.]+\.(?:com|org|edu|net|gov)[A-Za-z\d\.]*!ig) {
      $ignore.=" $word";
   }

   my $wordframe=$text;
   my $wordcount=0;
   my @words=();
   my %wordnums=();

   if ($htmlmode) {	# escape html tag so they won't be spellchecked
      my $tagcount=0;
      my @tags=();
      $wordframe=~s/(<[^\<\>]*?>|&nbsp;|&amp;|&quot;|&gt;|&lt;|&#\d\d+;)/_tag2label($1, \$tagcount, \@tags)/ige;
      $wordframe=~s/([$dicletters][$dicletters\-]*[$dicletters])|(~~[$dicletters][$dicletters\-]*[$dicletters])/_word2label($1, $ignore, \$wordcount, \@words, \%wordnums)/ge;
      $wordframe=~s/##TAG(\d+)##/$tags[$1]/g;
   } else {
      $wordframe=~s/([$dicletters][$dicletters\-]*[$dicletters])|(~~[$dicletters][$dicletters\-]*[$dicletters])/_word2label($1, $ignore, \$wordcount, \@words, \%wordnums)/ge;
   }
   return($wordcount, $wordframe, @words);
}

sub _tag2label {
   my ($tag, $r_tagcount, $r_tags)=@_;
   my $label='##TAG'.${$r_tagcount}.'##';
   ${$r_tags}[${$r_tagcount}]=$tag;
   ${$r_tagcount}++;
   return($label);
}

sub _word2label {
   my ($word, $wordignore, $r_wordcount, $r_words, $r_wordnums)=@_;
   return($word) if ($memdic{lc($word)} || $wordignore=~/\Q$word\E/i ||
                     $word =~/^WORD/ || $word =~/^TAG/);
   return('##WORD'.${$r_wordnums}{$word}.'##') if (defined ${$r_wordnums}{$word});

   my $label='##WORD'.${$r_wordcount}.'##';
   ${$r_words}[${$r_wordcount}]=$word;
   ${$r_wordnums}{$word}=${$r_wordcount};
   ${$r_wordcount}++;
   return($label);
}

# cgi param -> $wordframe and @words
sub cgiparam2words {
   my $wordframe=ow::tool::unescapeURL(param('wordframe'))||'';
   my $wordcount=param('wordcount')||0;
   my @words=();
   my %wordnums=();

   my $newwordcount=0;
   for (my $i=0; $i<$wordcount; $i++) {
      if (defined param($i)) {
         my $word=param($i);
         if (!defined $wordnums{$word}) {
            $words[$i]=$word;
            $wordnums{$word}=$i;
            $newwordcount=$i+1;
         } else {
            # duplication found, replace WORD$i in wordframe with WORD$wordnums{$word}
            $wordframe=~s/##WORD$i##/##WORD$wordnums{$word}##/g;
         }
      }
   }
   return($newwordcount, $wordframe, @words);
}

# rebuilt article from $wordframe and @words
sub words2text {
   my ($r_wordframe, $r_words, $dicletters)=@_;

   my $text=${$r_wordframe};
   $text=~s/##WORD(\d+)##/${$r_words}[$1]/g;
   $text=~s/~~([$dicletters]*)/$1/g;		# covert manualfix to origword
   $text=~s/~!~([$dicletters]*)/$1/g;		# covert addtodict to origword
   return($text);
}

# spellcheck @words,
# put correct word back to word frame,
# and generate query html for incorrect word
sub spellcheck_words2html {
   my ($htmlmode, $wordcount, $r_wordframe, $r_words, $dictionary)=@_;
   my $pdicname=$config{'spellcheck_pdicname'}; $pdicname=~s/\@\@\@DICTIONARY\@\@\@/$dictionary/;
   my $pdicfile=ow::tool::untaint("$homedir/$pdicname");

   # Below two is already done in userenv_init()
   # chdir($homedir);	  # in case spellchecker write pdic in ./
   # $ENV{'HOME'}=$homedir; # aspell/ispell refers this env to locate pdic file
   # we pass pdicname instead of pdicfile
   # because aspell won't work if it is fullpath?

   my $spellcheck=$config{'spellcheck'};
   $spellcheck=~s/\@\@\@DICTIONARY\@\@\@/$dictionary/;
   $spellcheck=~s/\@\@\@PDICNAME\@\@\@/$pdicname/;

   my ($stdout, $stderr)=pipeopen(split(/\s+/, $spellcheck));
   if ($stdout!~/^\@\(#\)/ && $stderr=~/[^\s]/) {
      pipeclose();
      openwebmailerror(__FILE__, __LINE__, "Spellcheck error: $stderr");
   }

   my $html=${$r_wordframe};
   if ($htmlmode) {
      # remove html tage from wordframe
      # so they won't be displayed during spellchecking
      $html=ow::htmltext::html2text($html);
   }

   # conversion make text for happy html display
   $html=ow::htmltext::text2html_nolink($html);

   # find all words leading with ~!~, remove ~!~ and add them to pdict
   my %pdicword=();
   foreach (@{$r_words}) {
      # check if leading with ~!~, replace with pure word
      $pdicword{$_}=1 if (s/^~!~// );
   }
   my $spellcmd='';
   foreach (keys %pdicword) {
      $spellcmd.="*$_\n";
   }
   if ($spellcmd ne '') {
      # add words to person dict
      # the 2nd \n guarentees we have output in piperead
      pipewrite($spellcmd."\#\n\n");
      ($stdout, $stderr)=piperead(2);

      # it seems adding words to pdict doesn't generate output on aspell 0.50,
      # so we comment out the result check here
      # if ($stderr=~/[^\s]/) {
      #    pipeclose();
      #    openwebmailerror(__FILE__, __LINE__, "Spellcheck error: $stderr");
      # }
   }

   my %dupwordhtml=();
   my $error=0;
   for (my $i=0; $i<$wordcount; $i++) {
      my $word=${$r_words}[$i];
      my $wordhtml='';

      if (defined $dupwordhtml{$word}) {	# different symbo with duplicate word
         $wordhtml=$dupwordhtml{$word};

      } elsif (defined $pdicword{$word}) {	# words already put into pdic
         $wordhtml=$dupwordhtml{$word}=$word;

      } elsif ( $word=~/^~~/ ) {	# check if manualfix
         my $pureword=substr($word,2);
         $wordhtml=qq|<input type="text" size="|.length($pureword).qq|" name="$i" value="$pureword">\n|;
         $dupwordhtml{$word}=qq|<font color="#cc0000"><b>$pureword</b></font>|;
         $error++;

      } else {				# word passed to spellchecker
         my ($r) = spellcheck($word);

         if ($r->{'type'} eq 'none' || $r->{'type'} eq 'guess') {
            $wordhtml=qq|<select size="1" name="$i">\n|.
                      qq|<option>$word</option>\n|.
                      qq|<option value="~!~$word">--$lang_text{'addtodict'}--</option>\n|.
                      qq|<option value="~~$word">--$lang_text{'manuallyfix'}--</option>\n|.
                      qq|</select>\n|;
            $dupwordhtml{$word}=qq|<font color="#0000cc"><b>$word</b></font>|;
            $error++;

         } elsif ($r->{'type'} eq 'miss')  {
            $wordhtml=qq|<select size="1" name="$i">\n|.
                      qq|<option>$word</option>\n|.
                      qq|<option value="~!~$word">--$lang_text{'addtodict'}--</option>\n|.
                      qq|<option value="~~$word">--$lang_text{'manuallyfix'}--</option>\n|;
            foreach my $sugg (@{$r->{'misses'}}) {
               $wordhtml.=qq|<option>$sugg</option>\n|;
            }
            $wordhtml.=qq|</select>\n|;
            $dupwordhtml{$word}=qq|<font color="#0000cc"><b>$word</b></font>|;
            $error++;

         } else {	# type= ok, compound, root
            $wordhtml=$dupwordhtml{$word}=$word;
         }

      }

      # remove the word from wordframe if it is an okay word
      ${$r_wordframe}=~s/##WORD$i##/$word/g if ($word eq $wordhtml);

      $html=~s/##WORD$i##/$wordhtml/;
      $html=~s/##WORD$i##/$dupwordhtml{$word}/g;
   }

   pipeclose();

   return($html, $error);
}

########## SPELLCHECK ############################################
sub spellcheck {
   my $word = $_[0]; $word =~ s/[\r\n]//g;
   return ({'type'=>'ok'}) if ($word eq "");

   my %types = (
	# correct words:
	'*' => 'ok',
	'-' => 'compound',
	'+' => 'root',
	# misspelled words:
	'#' => 'none',
	'&' => 'miss',
	'?' => 'guess',
   );
   my %modisp = (
	'root' => sub {
		my $h = shift;
		$h->{'root'} = shift;
		},
	'none' => sub {
		my $h = shift;
		$h->{'original'} = shift;
		$h->{'offset'} = shift;
		},
	'miss' => sub { # also used for 'guess'
		my $h = shift;
		$h->{'original'} = shift;
		$h->{'count'} = shift; # count will always be 0, when $c eq '?'.
		$h->{'offset'} = shift;
		my @misses  = splice @_, 0, $h->{'count'};
		my @guesses = @_;
		$h->{'misses'}  = \@misses;
		$h->{'guesses'} = \@guesses;
		},
   );
   $modisp{'guess'} = $modisp{'miss'}; # same handler.

   my ($stdout, $stderr, @commentary, @results);

   pipewrite("!\n^$word\n");
   ($stdout, $stderr)=piperead();
   if ($stderr=~/[^\s]/) {
      pipeclose();
      openwebmailerror(__FILE__, __LINE__, "Spellcheck error: $stderr");
   }

   foreach (split(/\n/, $stdout)) {
      last unless $_ gt '';
      push (@commentary, $_) if ( /^[\+\-\*\?\s\|#&]/ );
   }

   for my $i (0 .. $#commentary) {
      my %h = ('commentary' => $commentary[$i]);
      my @tail; # will get stuff after a colon, if any.

      if ($h{'commentary'} =~ s/:\s+(.*)//) {
         my $tail = $1;
	 @tail = split /, /, $tail;
      }

      my($c,@args) = split ' ', $h{'commentary'};
      my $type = $types{$c} || 'unknown';
      $modisp{$type} and $modisp{$type}->( \%h, @args, @tail );
      $h{'type'} = $type;
      $h{'term'} = $h{'original'};
      push @results, \%h;
   }
   return $results[0];
}

########## PIPE ROUTINES... ######################################
# local globals
use vars qw(*spellIN *spellOUT *spellERR);
use vars qw($mypid $pipepid $piperun $pipeexit $pipesig);
$mypid=$$;
sub pipeopen {
   local $1; # fix perl $1 taintness propagation bug
   my @cmd=@_; foreach (@cmd) { (/^(.*)$/) && ($_=$1) };	# untaint all argument
   local $|=1;				# flush CGI related output in parent
   ($piperun, $pipeexit, $pipesig)=(1,0,0);
   local $SIG{CHLD}=sub { wait; $pipeexit=$?>>8; $pipesig=$?&255; $piperun=0; }; # to get child status
   eval { $pipepid = open3(\*spellIN, \*spellOUT, \*spellERR, @cmd); };
   if ($@) {			# open3 return err only in child
      if ($$!=$mypid){ 		# child
         print STDERR $@;	# pass $@ to parent through stderr pipe
         exit 9;		# terminated
      }
   }
   return(piperead());
}

sub piperead {
   my $timeout=$_[0]; $timeout=10 if ($timeout<=0);

   my ($stdout, $stderr, $retry)=('', '', 0);
   while (1) {
      my ($rin, $rout, $ein, $eout)=('','','','');
      vec($rin, fileno(\*spellOUT), 1) = 1;
      vec($rin, fileno(\*spellERR), 1) = 1;
      $ein=$rin;

      # timeout is changed to 0.001 once any data in
      my $n=select($rout=$rin, undef, $eout=$ein, $timeout);

      if ($n>0) {	# fd is ready for reading
         my ($o, $e, $buf)=(-1, -1, '');
         if (vec($rout,fileno(\*spellOUT),1)) {
            $o=sysread(\*spellOUT, $buf, 65536);
            if ($o>0) { $stdout.=$buf; $timeout=0.001; }
         }
         if (vec($rout,fileno(\*spellERR),1)) {
            $e=sysread(\*spellERR, $buf, 65536);
            if ($e>0) { $stderr.=$buf; $timeout=0.001; }
         }
         last if ($o==0 && $e==0);	# os ensure there is no more data to read

      } elsif ($n==0) {	# read timeout
         if ($stdout=~/\n/||$stderr=~/\n/) {	# data line already in
            last;
         } elsif ($stdout eq "" && $stderr eq "") {	# 1st read timeout
            $stderr="piperead nothing"; last;
         } # else continue to read until line

      } else {	# n<0, read err => child dead?
         $stderr="piperead error $n"; last;
      }

      if ($retry++>100) {
         $stderr="piperead too many retries"; last;
      }
   }

   if (!$piperun) {
      $stderr="terminated abnormally" if ($stderr eq "");
      $stderr.=" (exit $pipeexit, sig $pipesig)";
   }

   return ($stdout, $stderr);
}

sub pipewrite {
   print spellIN $_[0];
}

sub pipeclose {
   close spellIN; close spellOUT; close spellERR;
}
