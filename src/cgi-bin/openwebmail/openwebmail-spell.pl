#!/usr/bin/suidperl -T
#
# openwebmail-spell.pl - spell check program
#
# 2003/02/19 Scott E. Campbell, scampbel.AT.gvpl.ca
#            add personal dictionary support
#
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
%dictionary_letters =
   (
   english   => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',
   br        => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz������������������������',
   czech     => 'A�BC�D�E��FGHI�JKLMN�O�PQR�S�T�U��VWXY�Z�a�bc�d�e��fghi�jklmn�o�pqr�s�t�u��vwxy�z�',
   dansk     => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ���abcdefghijklmnopqrstuvwxyz���',
   deutsch   => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz�������',
   french    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz����������������������������������������',
   magyar    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz���������������������������������������������~��',
   polski    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz����󶼿��ʣ�Ӧ��',
   ukrainian => '����������ȧƦ�������֤����������\'�������������������������������',
   );


use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(\S*)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^(\S*)/) { $SCRIPT_DIR=$1; }
}
if (!$SCRIPT_DIR) { print "Content-type: text/html\n\nSCRIPT_DIR not set in /etc/openwebmail_path.conf !\n"; exit 0; }
push (@INC, $SCRIPT_DIR);

$ENV{PATH} = ""; # no PATH should be needed
$ENV{ENV} = "";      # no startup script for sh
$ENV{BASH_ENV} = ""; # no startup script for bash
umask(0002); # make sure the openwebmail group can write

use strict;
use Fcntl qw(:DEFAULT :flock);
use IPC::Open3;
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser carpout);

require "ow-shared.pl";
require "filelock.pl";
require "htmltext.pl";

# common globals
use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

# extern vars
use vars qw(%lang_text %lang_err);	# defined in lang/xy

# local globals
use vars qw(*spellIN *spellOUT *spellERR);

################################ MAIN #################################
openwebmail_requestbegin();
$SIG{PIPE}=\&openwebmail_exit;	# for user stop
$SIG{TERM}=\&openwebmail_exit;	# for user stop

userenv_init();

if (!$config{'enable_webmail'}) {
   openwebmailerror(__FILE__, __LINE__, "$lang_text{'webmail'} $lang_err{'access_denied'}");
}

# whether we are checking a html
my $htmlmode = param('htmlmode');

my $form = param('form');
my $field = param('field');
my $dictionary = param('dictionary') || $prefs{'dictionary'};
my $dicletters=$dictionary_letters{'english'};
$dicletters=$dictionary_letters{$dictionary} if (defined($dictionary_letters{$dictionary}));

if (! -x $config{'spellcheck'}) {
   openwebmailerror(__FILE__, __LINE__, "Spellcheck is not available.<br>( $config{'spellcheck'} not found )");
}

if (defined(param('string'))) {
   my ($wordcount, $wordframe, @words)=text2words($htmlmode, param('string'), $dicletters);
   my ($wordshtml, $error)=spellcheck_words2html($htmlmode, $wordcount, \$wordframe, \@words, $dictionary);
   docheckform($htmlmode, $form, $field, $dictionary, $wordshtml, $error, $wordcount, $wordframe);

} elsif (defined(param('checkagainbutton'))) {
   my ($wordcount, $wordframe, @words)=cgiparam2words();
   my ($wordshtml, $error)=spellcheck_words2html($htmlmode, $wordcount, \$wordframe, \@words, $dictionary);
   docheckform($htmlmode, $form, $field, $dictionary, $wordshtml, $error, $wordcount, $wordframe);

} elsif (defined(param('finishcheckingbutton'))) {
   my ($wordcount, $wordframe, @words)=cgiparam2words();
   spellcheck_words2html($htmlmode, $wordcount, \$wordframe, \@words, $dictionary);	# for updating pdict
   my $finalstring=words2text(\$wordframe, \@words, $dicletters);
   finalform($form, $field, $finalstring);

} elsif (defined(param('editpdictbutton'))) {
   editpdict(param('dictword2delete'), $dictionary);

} else {
   httpprint([], [htmlheader(), "What the heck? Invalid input for Spellcheck!", htmlfooter(1)]);
}

openwebmail_requestend();
############################### END MAIN #################################

############################### CGI FORM ROUTINES ##############################
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

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-spell.pl",
                         -name=>'spellcheck') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
                      -override=>'1') .
               hidden(-name=>'htmlmode',
                      -default=>$htmlmode,
                      -override=>'1') .
               hidden(-name=>'form',
                      -default=>$formname,
                      -override=>'1') .
               hidden(-name=>'field',
                      -default=>$fieldname,
                      -override=>'1') .
               hidden(-name=>'dictionary',
                      -default=>$dictionary,
                      -override=>'1') .
               hidden(-name=>'wordcount',
                      -default=>$wordcount,
                      -override=>'1') .
               hidden(-name=>'wordframe',
                      -default=>escapeURL($wordframe),
                      -override=>'1');
   $html =~ s/\@\@\@STARTSPELLCHECKFORM\@\@\@/$temphtml/;

   if ( defined(param('checkagainbutton')) ) {
      $temphtml = button(-name=>"backbutton",
                         -value=>$lang_err{'back'},
                         -onclick=>'window.history.back();',
                         -override=>'1');
   } else {	# first time check, no history to back
      $temphtml = "";
   }
   if ($error>0) {
      $temphtml .= "&nbsp;&nbsp;" if (defined(param('checkagainbutton')));
      $temphtml .= submit(-name=>'checkagainbutton',
                          -value=>"$lang_text{'checkagain'}",
                          -override=>'1');
   }
   $html =~ s/\@\@\@CHECKAGAINBUTTON\@\@\@/$temphtml/;

   $temphtml = submit(-name=>"finishcheckingbutton",
                      -value=>"$lang_text{'finishchecking'}",
                      -override=>'1');
   $html =~ s/\@\@\@FINISHCHECKINGBUTTON\@\@\@/$temphtml/;

   $temphtml = button(-name=>"editpdictbutton",
                      -value=>$lang_text{'editpdict'},
                      -onclick=>"window.open('$config{'ow_cgiurl'}/openwebmail-spell.pl?editpdictbutton=yes&amp;sessionid=$thissession','_personaldict','width=300,height=350,resizable=yes,menubar=no,scrollbars=yes');",
                      -override=>'1');
   $html =~ s/\@\@\@EDITPERSDICTIONARYBUTTON\@\@\@/$temphtml/;

   $temphtml = button(-name=>"cancelbutton",
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
   my ($spellerdict) = $config{'spellcheck'} =~ m/\/?(\w+)\s*$/;
   my $bgcolor = $style{"tablerow_light"};
   my $count = 1;

   my ($html, $temphtml);
   $html= applystyle(readtemplate("editdictionary.template"));

   if ($dictword2delete) {
      my ($pdicwordcount, $pdicwordstr)=(0, "");
      open(PERSDICT,"<$homedir/.ispell_words");
      while (<PERSDICT>) {
         chomp($_);
         next if (/^personal_ws/);  # to get past aspell's first line
         next if ($_ eq $dictword2delete);
         $pdicwordcount++; $pdicwordstr.="$_\n";
      }
      close(PERSDICT);

      open(NEWPERSDICT,">$homedir/.ispell_words.new");
      print NEWPERSDICT "personal_ws-1.1 en $pdicwordcount\n" if ($config{'spellcheck'}=~/aspell/);
      print NEWPERSDICT $pdicwordstr;
      close(NEWPERSDICT);

      rename("$homedir/.ispell_words",     "$homedir/.ispell_words.bak");
      rename("$homedir/.ispell_words.new", "$homedir/.ispell_words");
   }

   open(PERSDICT,"$homedir/.ispell_words");
   $temphtml = "";

   while (<PERSDICT>) {
      my $dictword = $_;
      chomp($dictword);
      next if ($dictword=~m/personal_ws/);  # to get past aspell's first line

      $bgcolor=($style{"tablerow_dark"},$style{"tablerow_light"})[$count%2];
      $temphtml .= qq|<tr><td bgcolor=$bgcolor>$dictword</td>\n<td bgcolor=$bgcolor align=center>|.
                   button(-name=>"dictword2delete",
                          -value=>$lang_text{'delete'},
                          -onclick=>"window.location.href='$config{ow_cgiurl}/openwebmail-spell.pl?editpdictbutton=yes&amp;dictword2delete=$dictword&amp;sessionid=$thissession';",
                          -class=>"medtext",
                          -override=>'1').    
                   qq|</td></tr>\n|;
      $count++;
   }
   close(PERSDICT);
   $html =~ s/\@\@\@DICTIONARYWORDS\@\@\@/$temphtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-spell.pl",
                         -name=>'spellcheck') .
                  hidden(-name=>$lang_text{'editpdict'},
                         -default=>'yes',
                         -override=>'1') .
                  hidden(-name=>'sessionid',
                         -default=>$thissession,
                         -override=>'1') .
                  hidden(-name=>'dictionary',
                         -default=>$dictionary,
                         -override=>'1');
   $html =~ s/\@\@\@STARTFORM\@\@\@/$temphtml/;

   $temphtml = button(-name=>"closebutton",
                      -value=>$lang_text{'close'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CLOSEBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   httpprint([], [htmlheader(), $html, htmlfooter(0)]);
}


########################## TEXT SPLIT/JOIN #########################
# $wordframe is a rough structure of the original text, containing no word in it.
# words of the orgignal text are put into @words.

# text -> $wordframe and @words
sub text2words {
   my ($htmlmode, $text, $dicletters)=@_;
   my $ignore = "they'll we'll you'll she'll he'll i'll ".	# init don't care term
		"they've we've you've I've ".
		"can't couldn't won't wouldn't shouldn't ".
		"don't doesn't didn't hasn't hadn't ".
		"isn't wasn't aren't weren't ".
		"http https ftp nntp smtp nfs html xml sgml mailto ".
		"freebsd linux solaris gnu gpl bsd openwebmail";
   # put url to ignore
   foreach my $word ($text=~m![A-Za-z]+tp://[A-Za-z\d\.]+!ig) {
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

   if ($htmlmode) {	# escape html tag so they won't be spellchecked
      my $tagcount=0;
      my @tags=();
      $wordframe=~s/(<[^\<\>]*?>|&nbsp;|&amp;|&quot;|&gt;|&lt;|&#\d\d+;)/_tag2label($1, \$tagcount, \@tags)/ige;
      $wordframe=~s/([$dicletters][$dicletters\-]*[$dicletters])|(~~[$dicletters][$dicletters\-]*[$dicletters])/_word2label($1, $ignore, \$wordcount, \@words)/ge;
      $wordframe=~s/%%TAG(\d+)%%/$tags[$1]/g;
   } else {
      $wordframe=~s/([$dicletters][$dicletters\-]*[$dicletters])|(~~[$dicletters][$dicletters\-]*[$dicletters])/_word2label($1, $ignore, \$wordcount, \@words)/ge;
   }
   return($wordcount, $wordframe, @words);
}

sub _tag2label {
   my ($tag, $r_tagcount, $r_tags)=@_;
   my $label='%%TAG'.${$r_tagcount}.'%%';
   ${$r_tags}[${$r_tagcount}]=$tag;
   ${$r_tagcount}++;
   return($label);
}

sub _word2label {
   my ($word, $wordignore, $r_wordcount, $r_words)=@_;
   return($word) if ($wordignore=~/\Q$word\E/i || $word =~/^WORD/ || $word =~/^TAG/ );

   my $label='%%WORD'.${$r_wordcount}.'%%';
   ${$r_words}[${$r_wordcount}]=$word;
   ${$r_wordcount}++;
   return($label);
}

# cgi param -> $wordframe and @words
sub cgiparam2words {
   my $wordframe=unescapeURL(param('wordframe'));
   my $wordcount=param('wordcount');
   my @words=();
   for (my $i=0; $i<$wordcount; $i++) {
      $words[$i]=param($i) if (defined(param($i)));
   }
   return($wordcount, $wordframe, @words);
}

# rebuilt article from $wordframe and @words
sub words2text {
   my ($r_wordframe, $r_words, $dicletters)=@_;

   my $text=${$r_wordframe};
   $text=~s/%%WORD(\d+)%%/${$r_words}[$1]/g;
   $text=~s/~~([$dicletters]*)/$1/g;		# covert manualfix to origword
   $text=~s/~!~([$dicletters]*)/$1/g;		# covert addtodict to origword
   return($text);
}

# spellcheck @words, 
# put correct word back to word frame, 
# and generate query html for incorrect word
sub spellcheck_words2html {
   my ($htmlmode, $wordcount, $r_wordframe, $r_words, $dictionary)=@_;
   my @cmd=($config{'spellcheck'}, '-a', '-S', '-d', $dictionary, '-p', "$homedir/.ispell_words", '-w', '"-"');

   # check personal dic for aspell compatibility, or aspell will quit
   if ($config{'spellcheck'}=~/aspell/) {
      my $aspell_compatible=0;
      my ($pdicwordcount, $pdicwordstr)=(0, "");
      open(PERSDICT,"<$homedir/.ispell_words");
      while (<PERSDICT>) {
         if (/^personal_ws/) {
            $aspell_compatible=1; last;
         }
         chomp($_);
         $pdicwordcount++; $pdicwordstr.="$_\n"; 
      }
      close(PERSDICT);
      if (!$aspell_compatible) {
         open(PERSDICT,">$homedir/.ispell_words");
         print PERSDICT "personal_ws-1.1 en $pdicwordcount\n$pdicwordstr";
         close(PERSDICT);
      }
   }

   foreach (@cmd) { (/^(.*)$/) && ($_=$1) }	# untaint all argument
   local $SIG{CHLD}; undef $SIG{CHLD};	# disable outside $SIG{CHLD} handler temporarily for wait()
   local $|=1;				# flush CGI related output in parent
   my $pid = open3(\*spellIN, \*spellOUT, \*spellERR, @cmd);

   my $html=${$r_wordframe};
   if ($htmlmode) {	
      # remove html tage from wordframe 
      # so they won't be displayed during spellchecking
      $html=html2text($html);
   }

   # conversion make text for happy html display
   $html=~s/&/&amp;/g;
   $html=~s/</&lt;/g;
   $html=~s/>/&gt;/g;
   $html=~s/\n/<BR>/g;
   $html=~s/"/&quot;/g;
   $html=~s/  /&nbsp;&nbsp;/g;

   my $error=0;
   for (my $i=0; $i<$wordcount; $i++) {
      my $wordhtml="";

      if ( ${$r_words}[$i]=~/^~!~/ ) {         # check if addtodict
         my $origword=substr(${$r_words}[$i],3);
         $wordhtml= $origword;
         print spellIN "*$origword\n\#\n";		# add to person dict
         ${$r_words}[$i] = $origword;
         ${$r_wordframe}=~s/%%WORD$i%%/${$r_words}[$i]/;# remove the word symbol from wordframe

      } elsif ( ${$r_words}[$i]=~/^~~/ ) {	# check if manualfix
         my $origword=substr(${$r_words}[$i],2);
         my $len=length($origword);
         $wordhtml=qq|<input type="text" size="$len" name="$i" value="$origword">\n|;
         $error++;

      } else {				# normal word
         my ($r) = spellcheck(${$r_words}[$i]);

         if ($r->{'type'} eq 'none' || $r->{'type'} eq 'guess') {
            # my $len=length(${$r_words}[$i]);
            # $wordhtml=qq|<input type="text" size="$len" name="$i" value="$words[$i]">\n|;
            $wordhtml=qq|<select size="1" name="$i">\n|.
                      qq|<option>${$r_words}[$i]</option>\n|.
                      qq|<option value="~!~${$r_words}[$i]">--$lang_text{'addtodict'}--</option>\n|.
                      qq|<option value="~~${$r_words}[$i]">--$lang_text{'manuallyfix'}--</option>\n|.
                      qq|</select>\n|;
            $error++;

         } elsif ($r->{'type'} eq 'miss')  {
            $wordhtml=qq|<select size="1" name="$i">\n|.
                      qq|<option>${$r_words}[$i]</option>\n|.
                      qq|<option value="~!~${$r_words}[$i]">--$lang_text{'addtodict'}--</option>\n|.
                      qq|<option value="~~${$r_words}[$i]">--$lang_text{'manuallyfix'}--</option>\n|;
            foreach my $sugg (@{$r->{'misses'}}) {
               $wordhtml.=qq|<option>$sugg</option>\n|;
            }
            $wordhtml.=qq|</select>\n|;
            $error++;

         } else {	# type= ok, compound, root
            $wordhtml=${$r_words}[$i];
            ${$r_wordframe}=~s/%%WORD$i%%/${$r_words}[$i]/; # remove the word symbo from wordframe
         }

      }
      $html=~s/%%WORD$i%%/$wordhtml/;
   }

   close spellIN; close spellOUT; close spellERR;
   $pid=wait();

   return($html, $error);
}

########################## SPELLCHECK PIPE #########################
sub spellcheck {
   my $word = $_[0];;
   my @commentary;
   my @results;
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
   chomp $word;
   $word =~ s/\r//g;
   $word =~ /\n/ and warn "newlines not allowed";

   print spellIN "!\n";
   print spellIN "^$word\n";

   while (<spellOUT>) {
      chomp;
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
