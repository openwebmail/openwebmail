#!/usr/bin/suidperl -T
#
# openwebmail-spell.pl - spell check program
#
# 2003/02/19 Scott E. Campbell, scampbel@gvpl.ca
#            add personal dictionary support
#
# 2001/09/27 tung@turtle.ee.ncku.edu.tw
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
   br        => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzáÁéÉíÍóÓúÚüÜõÕãÃàÀôÔêÊÇç',
   czech     => 'AÁBCÈDÏEÉÌFGHIÍJKLMNÒOÓPQRØS©T«UÚÙVWXYÝZ®aábcèdïeéìfghiíjklmnòoópqrøs¹t»uúùvwxyýz¾',
   dansk     => 'ABCDEFGHIJKLMNOPQRSTUVWXYZÆØÅabcdefghijklmnopqrstuvwxyzæøå',
   deutsch   => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzäÄöÖüÜß',
   french    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzàáâäÀÁÂÄèéêëÈÉÊËìíîïÌÍÎÏòóôöÒÓÔÖùúûüÙÚÛÜ',
   magyar    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzáÁéÉíÍóÓúÚüÜõÕûÛÀÁÈÉÌÍÒÓÔÕÖÙÚÛÜàáèéêëìíòóôõö¢~ûü',
   polski    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz±æê³ñó¶¼¿¡ÆÊ£ÑÓ¦¬¯',
   ukrainian => 'ÊÃÕËÅÎÇÛÝÚÈ§Æ¦×ÁÐÒÏÌÄÖ¤­ÑÞÓÍÉÔØÂÀ\'êãõëåîçûýúè·æ¶÷áðòïìäö´½ñþóíéôøâà',
   );


use vars qw($SCRIPT_DIR);
if ( $0 =~ m!^(.*?)/[\w\d\-\.]+\.pl! ) { $SCRIPT_DIR=$1; }
if (!$SCRIPT_DIR && open(F, '/etc/openwebmail_path.conf')) {
   $_=<F>; close(F); if ( $_=~/^([^\s]*)/) { $SCRIPT_DIR=$1; }
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
clearvars();
openwebmail_init();

my $form = param('form');
my $field = param('field');
my $dictionary = param('dictionary') || $prefs{'dictionary'};
($dictionary =~ /^([\w\d\.\-_]+)$/) && ($dictionary = $1);
my $dicletters=$dictionary_letters{'english'};
$dicletters=$dictionary_letters{$dictionary} if (defined($dictionary_letters{$dictionary}));

local $|=1;	# fix the duplicate output problem caused by fork in spellcheck

if (! -x $config{'spellcheck'}) {
   openwebmailerror("Spellcheck is not available.<br>( $config{'spellcheck'} not found )");
}

my @cmd=($config{'spellcheck'}, '-a', '-S', '-d', $dictionary, '-p', "$homedir/.ispell_words");
if (defined(param('string'))) {
   my $pid = open3(\*spellIN, \*spellOUT, \*spellERR, @cmd);
   my ($wordcount, $wordframe, @words)=text2words(param('string'), $dicletters);
   my ($wordshtml, $error)=spellcheck_words2html($wordcount, \$wordframe, \@words);
   docheckform($form, $field, $dictionary, $wordshtml, $error, $wordcount, $wordframe);
   close spellIN;
   close spellOUT;
   wait;

} elsif (defined(param('checkagainbutton'))) {
   my $pid = open3(\*spellIN, \*spellOUT, \*spellERR, @cmd);
   my ($wordcount, $wordframe, @words)=cgiparam2words();
   my ($wordshtml, $error)=spellcheck_words2html($wordcount, \$wordframe, \@words);
   docheckform($form, $field, $dictionary, $wordshtml, $error, $wordcount, $wordframe);
   close spellIN;
   close spellOUT;
   wait;

} elsif (defined(param('editpdictbutton'))) {
   editpdict(param('dictword2delete'), $dictionary);

} elsif (defined(param('finishcheckingbutton'))) {
   my ($wordcount, $wordframe, @words)=cgiparam2words();
   my $finalstring=words2text(\$wordframe, \@words, $dicletters);
   finalform($form, $field, $finalstring);

} else {
   print htmlheader(), "What the heck? Invalid input for Spellcheck!", htmlfooter(1);
}

# back to root if possible, required for setuid under persistent perl
$<=0; $>=0;
############################### END MAIN #################################

############################### ROUTINES ##############################
sub docheckform {
   my ($formname, $fieldname, $dictionary, 
       $wordshtml, $error, $wordcount, $wordframe) = @_;
   my $escapedwordframe;
   local $_;

   my ($html, $temphtml);
   $html = readtemplate("spellcheck.template");
   $html = applystyle($html);

   $html =~ s/\@\@\@FORMNAME\@\@\@/$formname/;
   $html =~ s/\@\@\@FIELDNAME\@\@\@/$fieldname/;
   $html =~ s/\@\@\@DICTIONARY\@\@\@/$dictionary/;
   $html =~ s/\@\@\@WORDSHTML\@\@\@/$wordshtml/;

   $temphtml = startform(-action=>"$config{'ow_cgiurl'}/openwebmail-spell.pl",
                         -name=>'spellcheck') .
               hidden(-name=>'sessionid',
                      -default=>$thissession,
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

   print htmlheader(), $html, htmlfooter(2);
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
   $html= readtemplate("editdictionary.template");
   $html = applystyle($html);

   if ($dictword2delete) {
      open(PERSDICT,"<$homedir/.ispell_words");
      open(NEWPERSDICT,">$homedir/.ispell_words.new");
      while (<PERSDICT>) {
         chop($_);
         if ($_ ne $dictword2delete) {
            print NEWPERSDICT "$_\n";
         }
      }
      close(PERSDICT);
      close(NEWPERSDICT);
      rename("$homedir/.ispell_words",     "$homedir/.ispell_words.bak");
      rename("$homedir/.ispell_words.new", "$homedir/.ispell_words");
   }

   open(PERSDICT,"$homedir/.ispell_words");
   $temphtml = "";

   while (<PERSDICT>) {
      my $dictword = $_;
      chop($dictword);

      next if ($dictword=~m/personal_ws/);  # to get past aspell's first line

      $bgcolor=($style{"tablerow_dark"},$style{"tablerow_light"})[$count%2];
      $temphtml .= qq|<tr><td bgcolor=$bgcolor>$dictword</td>\n<td bgcolor=$bgcolor align=center>|.
                   button(-name=>"dictword2delete",
                          -value=>$lang_text{'delete'},
                          -onclick=>"window.open('$config{'ow_cgiurl'}/openwebmail-spell.pl?editpdictbutton=yes&amp;dictword2delete=$dictword&amp;sessionid=$thissession','_self','width=300,height=350,resizable=yes,menubar=no,scrollbars=yes');",
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

   print htmlheader(), $html, htmlfooter();
}


########################## article split/join #########################
# $wordframe is a rough structure of the original text, containing no word in it.
# words of the orgignal text are put into @words.

# text -> $wordframe and @words
sub text2words {
   my ($text, $dicletters)=@_;
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
   foreach my $word ($text=~m![A-Za-z\d\.]+\.(com|org|edu|net|gov)[A-Za-z\d\.]*!ig) {
      $ignore.=" $word";
   }

   my $wordframe=$text;
   my $wordcount=0;
   my @words=();
   $wordframe=~s/([$dicletters][$dicletters\-]*[$dicletters])|(~~[$dicletters][$dicletters\-]*[$dicletters])/_word2label($1, $ignore, \$wordcount, \@words)/ge;
   return($wordcount, $wordframe, @words);
}
sub _word2label {
   my ($word, $wordignore, $r_wordcount, $r_words)=@_;
   return($word) if ($wordignore=~/\Q$word\E/i || $word =~/^WORD/);

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
   my ($wordcount, $r_wordframe, $r_words)=@_;

   # conversion make html display happy
   my $html=${$r_wordframe};
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
   return($html, $error);
}

########################## spellcheck #########################
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
      push (@commentary, $_) if substr($_,0,1) =~ /([*|-|+|#|&|?| ||])/;
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
