#!/usr/bin/suidperl -T
#
# openwebmail-spell.pl - spell check program
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

my %dictionary_letters =
   (
   english   => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',
   br        => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzáÁéÉíÍóÓúÚüÜõÕãÃàÀôÔêÊÇç',
   czech     => 'AÁBCÈDÏEÉÌFGHIÍJKLMNÒOÓPQRØS©T«UÚÙVWXYÝZ®aábcèdïeéìfghiíjklmnòoópqrøs¹t»uúùvwxyýz¾',
   dansk     => 'ABCDEFGHIJKLMNOPQRSTUVWXYZÆØÅabcdefghijklmnopqrstuvwxyzæøå',
   deutsch   => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzäÄöÖüÜß',
   magyar    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzáÁéÉíÍóÓúÚüÜõÕûÛÀÁÈÉÌÍÒÓÔÕÖÙÚÛÜàáèéêëìíòóôõö¢~ûü',
   polski    => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz±æê³ñó¶¼¿¡ÆÊ£ÑÓ¦¬¯',
   ukrainian => 'ÊÃÕËÅÎÇÛÝÚÈ§Æ¦×ÁÐÒÏÌÄÖ¤­ÑÞÓÍÉÔØÂÀ\'êãõëåîçûýúè·æ¶÷áðòïìäö´½ñþóíéôøâà',
   );


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
use IPC::Open3;
use CGI qw(-private_tempfiles :standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

require "ow-shared.pl";
require "filelock.pl";

use vars qw(%config %config_raw);
use vars qw($thissession);
use vars qw($loginname $domain $user $userrealname $uuid $ugid $homedir);
use vars qw(%prefs %style);
use vars qw($folderdir @validfolders $folderusage);
use vars qw($folder $printfolder $escapedfolder);

openwebmail_init();
verifysession();

# extern vars
use vars qw(%lang_text %lang_err);	# defined in lang/xy

################################ MAIN #################################

use vars qw(*spellREAD *spellWRITE *spellERROR);

my $form = param('form');
my $field = param('field');
my $dictionary = param('dictionary') || $prefs{'dictionary'};
my $dicletters = $dictionary_letters{$dictionary} || $dictionary_letters{'english'};

($dictionary =~ /^([\w\d\._]+)$/) && ($dictionary = $1);

$|=1;	# fix the duplicate output problem caused by fork in spellcheck

if (! -x $config{'spellcheck'}) {
   openwebmailerror("Spellcheck is not available.<br>( $config{'spellcheck'} not found )");
}

if (defined(param('string'))) {
   my $pid = open3(\*spellWRITE, \*spellREAD, \*spellERROR, "$config{'spellcheck'} -a -S -d $dictionary");
   text2words(param('string'));
   docheck($form,$field);
   close spellREAD;
   close spellWRITE;
   wait;
} elsif (defined(param($lang_text{'checkagain'}))) {
   my $pid = open3(\*spellWRITE, \*spellREAD, \*spellERROR,"$config{'spellcheck'} -a -S -d $dictionary");
   cgiparam2words();
   docheck($form,$field);
   close spellREAD;
   close spellWRITE;
   wait;
} elsif (defined(param($lang_text{'finishchecking'}))) {
   cgiparam2words();
   final($form,$field);
} else {
   printheader();
   print "What the heck? Invalid input for Spellcheck!";
   printfooter(1);
}

exit;

############################### ROUTINES ##############################
my @words=();
my $wordframe="";
my $wordcount=0;
my $worderror=0;
my $wordignore="";

sub docheck {
   my ($formname, $fieldname) = @_;
   my $html = '';
   my $temphtml;
   my $escapedwordframe;
   local $_;

   $html=readtemplate("spellcheck.template");
   $html = applystyle($html);

   $html =~ s/\@\@\@FORMNAME\@\@\@/$formname/;
   $html =~ s/\@\@\@FIELDNAME\@\@\@/$fieldname/;
   $html =~ s/\@\@\@DICTIONARY\@\@\@/$dictionary/;

   $temphtml=words2html();
   $html =~ s/\@\@\@WORDSHTML\@\@\@/$temphtml/;

   # escapedwordframe must be done after words2html()
   # since $wordframe may changed in words2html()
   $escapedwordframe=escapeURL($wordframe);

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
               hidden(-name=>'wordframe',
                      -default=>$escapedwordframe,
                      -override=>'1') .
               hidden(-name=>'wordcount',
                      -default=>$wordcount,
                      -override=>'1');
   $html =~ s/\@\@\@STARTSPELLCHECKFORM\@\@\@/$temphtml/;

   if ( defined(param($lang_text{'checkagain'})) ) {
      $temphtml = button(-name=>"backbutton",
                         -value=>$lang_err{'back'},
                         -onclick=>'window.history.back();',
                         -override=>'1');
   } else {	# first time check, no history to back
      $temphtml = "";
   }
   if (defined(param($lang_text{'checkagain'})) && $worderror>0) {
      $temphtml .= "&nbsp;&nbsp;&nbsp;&nbsp;";
   }
   if ($worderror>0) {
      $temphtml .= submit("$lang_text{'checkagain'}");
   }
   $html =~ s/\@\@\@CHECKAGAINBUTTON\@\@\@/$temphtml/;

   $temphtml = submit("$lang_text{'finishchecking'}");
   $html =~ s/\@\@\@FINISHCHECKINGBUTTON\@\@\@/$temphtml/;

   $temphtml = button(-name=>"can11celbutton",
                      -value=>$lang_text{'cancel'},
                      -onclick=>'window.close();',
                      -override=>'1');
   $html =~ s/\@\@\@CANCELBUTTON\@\@\@/$temphtml/;

   $temphtml = end_form();
   $html =~ s/\@\@\@ENDFORM\@\@\@/$temphtml/;

   printheader();
   print $html;
   printfooter(2);
}


sub final {
   my ($formname, $fieldname) = @_;
   my $escapedfinalstring;

   $escapedfinalstring=words2text();

   # since jscript has problem in unescape doublebyte char string,
   # we only escape " to !QUOT! and unescape in jscript by RegExp
   # $escapedfinalstring=escapeURL(words2text());
   $escapedfinalstring=~s/"/!QUOT!/g;

   print qq|Content-type: text/html

<html><body>
<form name="spellcheck">
<input type="hidden" name="finalstring" value="$escapedfinalstring">
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


########################## article split/join #########################

sub _word2label {
   my $word=$_[0];
   my $label='%%WORD'.$wordcount.'%%';

   if ($wordignore=~/\Q$word\E/i || $word =~/^WORD/) {
       return($word);
   }
   $words[$wordcount]=$word;
   $wordcount++;
   return($label);
}

# fill $wordframe and @words by spliting an article
sub text2words {
   my $text=$_[0];
   local $_;

   # init don't care term
   $wordignore  = "they'll we'll you'll she'll he'll i'll ".
                  "they've we've you've I've ".
                  "can't couldn't won't wouldn't shouldn't ".
                  "don't doesn't didn't hasn't hadn't ".
                  "isn't wasn't aren't weren't ".
                  "http https ftp nntp smtp nfs html xml sgml mailto ".
                  "freebsd linux solaris gnu gpl bsd openwebmail";

   # put url to ignore
   foreach ($text=~m![A-Za-z]+tp://[A-Za-z\d\.]+!ig) {
      $wordignore.=" $_";
   }
   # put email to ignore
   foreach ($text=~m![A-Za-z\d]+\@[A-Za-z\d]+!ig) {
      $wordignore.=" $_";
   }
   # put FQDN to ignore
   foreach ($text=~m![A-Za-z\d\.]+\.(com|org|edu|net|gov)[A-Za-z\d\.]*!ig) {
      $wordignore.=" $_";
   }

   @words=();
   $wordcount=0;
   $wordframe=$text;
   $wordframe=~s/([$dicletters][$dicletters\-]*[$dicletters])|(~~[$dicletters][$dicletters\-]*[$dicletters])/_word2label($1)/ge;
   return $wordcount;
}

# fill $wordframe and @words by CGI $query
sub cgiparam2words {
   my $q=$_[0];
   my $i;

   @words=();
   $wordcount=param('wordcount');
   $wordframe=unescapeURL(param('wordframe'));
   for ($i=0; $i<$wordcount; $i++) {
      $words[$i]=param($i) if (defined(param($i)));
   }
   return;
}

# rebuilt article from $wordframe and @words
sub words2text {
   my $text=$wordframe;
   $text=~s/%%WORD(\d+)%%/$words[$1]/g;
   $text=~s/~~([$dicletters]*)/$1/g;		# covert manualfix to origword
   return($text);
}

# generate html from $wordframe and @words and spellcheck()
sub words2html {
   my $html=$wordframe;
   my $i;

   # conversion make html display happy
   $html=~s/&/&amp;/g;
   $html=~s/</&lt;/g;
   $html=~s/>/&gt;/g;
   $html=~s/\n/<BR>/g;
   $html=~s/"/&quot;/g;
   $html=~s/  /&nbsp;&nbsp;/g;

   $worderror=0;
   for ($i=0; $i<$wordcount; $i++) {
      my $wordhtml="";

      if ( $words[$i]=~/^~~/ ) {	# check if manualfix
         my $origword=substr($words[$i],2);
         my $len=length($origword);
         $wordhtml=qq|<input type="text" size="$len" name="$i" value="$origword">\n|;
         $worderror++;

      } else {				# normal word
         my ($r) = spellcheck($words[$i]);

         if ($r->{'type'} eq 'none' || $r->{'type'} eq 'guess') {
            my $len=length($words[$i]);
            $wordhtml=qq|<input type="text" size="$len" name="$i" value="$words[$i]">\n|;
            $worderror++;

         } elsif ($r->{'type'} eq 'miss')  {
            my $sugg;
            $wordhtml=qq|<select size="1" name="$i">\n|.
                      qq|<option>$words[$i]</option>\n|.
                      qq|<option value="~~$words[$i]">--$lang_text{'manuallyfix'}--</option>\n|;
            foreach $sugg (@{$r->{'misses'}}) {
               $wordhtml.=qq|<option>$sugg</option>\n|;
            }
            $wordhtml.=qq|</select>\n|;
            $worderror++;

         } else {	# type= ok, compound, root
            $wordhtml=qq|$words[$i]|;
            $wordframe=~s/%%WORD$i%%/$words[$i]/; # remove the word symbo from wordframe
         }

      }
      $html=~s/%%WORD$i%%/$wordhtml/;
   }
   return($html);
}

########################## spellcheck #########################

sub spellcheck {
   my $word = shift(@_);
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

   print spellWRITE "!\n";
   print spellWRITE "^$word\n";

   while (<spellREAD>) {
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
