#!/usr/bin/perl -w
# spell check program by tung@turtle.ee.ncku.edu.tw
# modified from WBOSS Version 1.1.1d 
#
# WBOSS is available at http://www.dontpokebadgers.com/spellchecker/ 
# and is copyrighted by 2001, Joshua Cantara
#
use strict;
no strict 'vars';
use Lingua::Ispell qw(:all);
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
CGI::nph();   # Treat script as a non-parsed-header script

$ENV{PATH} = ""; # no PATH should be needed
umask(0007); # make sure the openwebmail group can write

push (@INC, '/usr/local/www/cgi-bin/openwebmail', ".");
require "etc/openwebmail.conf";
require "openwebmail-shared.pl";

local $thissession;
local $user;
local ($uid, $gid, $homedir);
local %prefs;
local %style;
local $lang;
local $folderdir;

$thissession = param("sessionid") || '';
$user = $thissession || '';
$user =~ s/\-session\-0.*$//; # Grab userid from sessionid
($user =~ /^(.+)$/) && ($user = $1);  # untaint $user...

if ($user) {
   if (($homedirspools eq 'yes') || ($homedirfolders eq 'yes')) {
      ($uid, $homedir) = (getpwnam($user))[2,7] or 
         openwebmailerror("User $user doesn't exist!");
   } else {
      $uid=$>; 
      $homedir = (getpwnam($user))[7] or 
         openwebmailerror("User $user doesn't exist!");
   }
   $gid=getgrnam('mail');

} else { # if no user specified
   openwebmailerror("No user specified!");
}

set_euid_egid_umask($uid, $gid, 0077);	

if ( $homedirfolders eq 'yes') {
   $folderdir = "$homedir/$homedirfolderdirname";
} else {
   $folderdir = "$openwebmaildir/users/$user";
}

%prefs = %{&readprefs};
%style = %{&readstyle};

$lang = $prefs{'language'} || $defaultlanguage;
($lang =~ /^(..)$/) && ($lang = $1);
require "etc/lang/$lang";
$lang_charset ||= 'iso-8859-1';

########################## MAIN ##############################
$Lingua::Ispell::path = "$spellcheck";
if (! -x $spellcheck) {
   printheader();
   print "<center>Spellcheck is not available. ( $spellcheck not found )";
   printfooter();
   exit;
}

$|=1;	# fix the duplicate output problem caused by fork in spellcheck

#print "Content-type: text/html\n\n";

my $form = param('form');
my $field = param('field');

if (defined(param('string'))) {
   text2words(param('string'));
   docheck($form,$field);
} elsif (defined(param($lang_text{'checkagain'}))) {
   cgiparam2words();
   docheck($form,$field);
} elsif (defined(param($lang_text{'finishchecking'}))) {
   cgiparam2words();
   final($form,$field);
} else {
   printheader();
   print "What the heck? Inavlid input for Spellcheck!";
   printfooter();
}

exit;

sub docheck {
   my ($formname, $fieldname) = @_;
   my $html = '';
   my $temphtml;
   my $escapedwordframe;

   open (SPELLCHECKTEMPLATE, "$openwebmaildir/templates/$lang/spellcheck.template") or
      openwebmailerror("$lang_err{'couldnt_open'} spellcheck.template");
   while (<SPELLCHECKTEMPLATE>) {
      $html .= $_;
   }
   close (IMPORTTEMPLATE);

   $html = applystyle($html);

   $html =~ s/\@\@\@FORMNAME\@\@\@/$formname/;
   $html =~ s/\@\@\@FIELDNAME\@\@\@/$fieldname/;

   $temphtml=words2html();
   $html =~ s/\@\@\@WORDSHTML\@\@\@/$temphtml/;

   # escapedwordframe must be done after words2html()
   # since $wordframe may changed in words2html()
   $escapedwordframe=CGI::escape($wordframe);	

   $temphtml = startform(-action=>$spellcheckurl,
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
   printfooter();
}


sub final {
   my ($formname, $fieldname) = @_;
   my $escapedfinalstring;

   $escapedfinalstring=words2text();

   # since jscript has problem in unescape doublebyte char string, 
   # we only escape " to !QUOT! and unescape in jscript by RegExp
   # $escapedfinalstring=CGI::escape(words2text());
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


###################### article split/join ######################
local @words=();	# global
local $wordframe="";	# global
local $wordcount=0;	# global 
local $worderror=0;	# global
local $wordignore="";	# global

sub _word2label {
   my $word=$_[0];
   my $label='%%WORD'.$wordcount.'%%';

   if ($wordignore=~/$word/i || $word =~/^WORD/) {
       return($word);
   }
   $words[$wordcount]=$word;
   $wordcount++;
   return($label);
}

# fill $wordframe and @words by spliting an article
sub text2words {
   my $text=$_[0];

   # init don't care term
   $wordignore="http ftp nntp smtp nfs html xml mailto bsd linux gnu gpl openwebmail";

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
   $wordframe=~s/([A-Za-z][A-Za-z\-]*[A-Za-z])|(~~[A-Za-z][A-Za-z\-]*[A-Za-z])/_word2label($1)/ge;
   return $wordcount;
}   

# fill $wordframe and @words by CGI $query
sub cgiparam2words {
   my $q=$_[0];
   my $i;

   @words=();
   $wordcount=param('wordcount');
   $wordframe=CGI::unescape(param('wordframe'));
   for ($i=0; $i<$wordcount; $i++) {
      $words[$i]=param($i) if (defined(param($i)));
   }
   return;
}

# rebuilt article from $wordframe and @words
sub words2text {
   my $text=$wordframe;
   $text=~s/%%WORD(\d+)%%/$words[$1]/g;
   $text=~s/~~([A-Za-z]*)/$1/g;		# covert manualfix to origword
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
