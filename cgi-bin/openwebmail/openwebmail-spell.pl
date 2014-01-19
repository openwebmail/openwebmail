#!/usr/bin/perl -T

#                              The BSD License
#
#  Copyright (c) 2009-2014, The OpenWebMail Project
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#      * Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of The OpenWebMail Project nor the
#        names of its contributors may be used to endorse or promote products
#        derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY The OpenWebMail Project ``AS IS'' AND ANY
#  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL The OpenWebMail Project BE LIABLE FOR ANY
#  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;
use warnings FATAL => 'all';

use vars qw($SCRIPT_DIR);

if (-f '/etc/openwebmail_path.conf') {
   my $pathconf = '/etc/openwebmail_path.conf';
   open(F, $pathconf) or die "Cannot open $pathconf: $!";
   my $pathinfo = <F>;
   close(F) or die "Cannot close $pathconf: $!";
   ($SCRIPT_DIR) = $pathinfo =~ m#^(\S*)#;
} else {
   ($SCRIPT_DIR) = $0 =~ m#^(\S*)/[\w\d\-\.]+\.pl#;
}

die 'SCRIPT_DIR cannot be set' if $SCRIPT_DIR eq '';
push (@INC, $SCRIPT_DIR);
push (@INC, "$SCRIPT_DIR/lib");

# secure the environment
delete $ENV{$_} for qw(ENV BASH_ENV CDPATH IFS TERM);
$ENV{PATH} = '/bin:/usr/bin';

# make sure the openwebmail group can write
umask(0002);

# load non-OWM libraries
use Fcntl qw(:DEFAULT :flock);
use CGI 3.31 qw(-private_tempfiles :cgi charset);
use CGI::Carp qw(fatalsToBrowser carpout);
use IPC::Open3;

# load OWM libraries
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
use vars qw(%prefs);

# extern vars
use vars qw($htmltemplatefilters $po); # defined in ow-shared.pl

# local globals
use vars qw(*spellIN *spellOUT *spellERR);
use vars qw($pipepid $piperun $pipeexit $pipesig);

# This is the table of valid letters for various dictionaries.
# If your dictionary checks vocabularies composed by characters other
# than english letters, you have to define new entry in the hash below
use vars qw(%dictionary_letters);

if (!exists $dictionary_letters{english} || !defined $dictionary_letters{english} || $dictionary_letters{english} eq '') {
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
   ); # we can probably replace this with use locale and the [:alpha:] character sets
}


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
userenv_init();

openwebmailerror(gettext('Access denied: the webmail module is not enabled.'))
  unless $config{enable_webmail} || $config{enable_spellcheck};

my $action = param('action') || '';

writelog("debug_request :: request spell begin, action=$action") if $config{debug_request};

defined param('body')       ? check('start')  :
defined param('checkagain') ? check('again')  :
defined param('finish')     ? check('finish') :
defined param('editpdict')  ? editpdict()     :
openwebmailerror(gettext('Action has illegal characters.'));

writelog("debug_request :: request spell end, action=$action") if $config{debug_request};

openwebmail_requestend();


# BEGIN SUBROUTINES

sub check {
   my $mode = shift || '';

   my $text  = get_text();
   my $words = text2words($text);

   if ($mode eq 'start') {
      $words = spellcheck_words($words);
      return spellcheckform($words);
   } elsif ($mode eq 'again') {
      $words = apply_corrections($words);
      $words = spellcheck_words($words);
      return spellcheckform($words);
   } elsif ($mode eq 'finish') {
      $words = apply_corrections($words);
      return finishcheck($words);
   } else {
      openwebmailerror(gettext('Unknown spellcheck mode:') . " ($mode)");
   }
}

sub get_text {
   # retreive the text that needs to be spellchecked
   my $text = {};

   my @subjectwords = param('subjectwords');
   my @bodywords    = param('bodywords');

   if (scalar @subjectwords > 0 || scalar @bodywords > 0) {
      # user is checking a text again, so use the text
      # coming in from the spellcheck form
      $text->{subject} = join('', @subjectwords);
      $text->{body}    = join('', @bodywords);
   } else {
      # this is the users first pass spellchecking this text
      # so use the text coming in from the send_compose screen
      $text->{subject} = param('subject') || '';
      $text->{body}    = param('body')    || '';
   }

   return $text;
}

sub text2words {
   # break the text to check into a hash of individual words
   # that can be spellchecked and iterated over via a loop
   # preserve all the formatting of the original text such that
   # join('', map { $_->{word} } @{$words})
   # reassembles the text back to its exact original form
   # text is a hash ref like $text->{subject} and $text->{body}
   my $text = shift;

   my $htmlmode   = param('htmlmode')   || ''; # are we are checking html?
   my $dictionary = param('dictionary') || $prefs{dictionary} || 'english';

   $dictionary =~ s#\.\.+##g;
   $dictionary =~ s#[^A-Za-z0-9\.]##;

   my $dicletters = exists $dictionary_letters{$dictionary} ? $dictionary_letters{$dictionary} : $dictionary_letters{english};

   # compile dictionary letters regex. ##TAG\d+## words are _tag2label escaped words
   my $dicletters_re = qr/(?:[$dicletters][$dicletters\-']*[$dicletters])|##TAG\d+##/;

   # indicate the words the spellchecker should ignore
   my %ignorelist = map { $_, 1 } qw(
                                       a an the this that one any none these those other another
                                       who what which when where why how
                                       i you he she it me him her my your his its whose we
                                       am is are do does have has was were did had
                                       being doing having been done
                                       will would shall should may might can could able unable
                                       as if then since because so though however even anyway
                                       at on of to by in out for from over back under through just
                                       among between both all now begin end here there last next
                                       ok yes not no too either neither more less and or
                                       jan feb mar apr may jun jul aug sep oct nov dec
                                       mon tue wed thr fri sat sun today week month day time
                                       origional subject try tried found best regards thanks thank
                                       write wrote send sent reply replied forward forwarded
                                       email icq msn url web tel mobile ext eg mr dear
                                       http https ftp nntp smtp mime nfs html xml sgml mailto
                                       freebsd linux solaris gnu gpl bsd openwebmail webmail
                                       they'll we'll you'll she'll he'll i'll they've we've you've I've
                                       they're we're you're
                                       can't couldn't won't wouldn't shouldn't don't doesn't didn't hasn't
                                       hadn't isn't wasn't aren't weren't
                                    );

   foreach my $key (sort keys %{$text}) {
      # add urls from the text to the ignore list
      $ignorelist{$_}++ for $text->{$key} =~ m#([a-z]+tp://[^\s]+)#ig;

      # add emails from the text to the ignore list
      $ignorelist{$_}++ for $text->{$key} =~ m#([a-z\d]+\@[a-z\d]+)#ig;

      # add FQDNs from the text to the ignore list
      $ignorelist{$_}++ for $text->{$key} =~ m#([a-z\d.]+\.(?:com?|org|edu|net|gov)[a-z\d.]*)#ig;
   }

   my $tags  = [];
   my $words = [];

   foreach my $key (reverse sort keys %{$text}) {
      # reverse sort so that subject gets checked before body

      # replace html tags with placeholders like ##TAG5## to avoid word matching
      $text->{$key} =~ s/(<[^<>]*?>|&nbsp;|&amp;|&quot;|&gt;|&lt;|&#\d+;)/_tag2label($1, $tags)/ige if $htmlmode;

      # split the text into an array of words and non-words
      # if this split is reassembled via join('', map { $_->{word} } @{$words}),
      # the result is the exact original text
      foreach my $word (split(/($dicletters_re)/, $text->{$key})) {
         my $is_tag = ($htmlmode && $word =~ s/##TAG(\d+)##/$tags->[$1]/g) ? 1 : 0;

         push(@{$words}, {
                            word       => $word,
                            is_subject => $key eq 'subject' ? 1 : 0,
                            is_tag     => $is_tag,
                            ignore     => (
                                             defined $word
                                             &&
                                             (
                                                $word !~ m/$dicletters_re/
                                                || exists $ignorelist{lc($word)}
                                                || $is_tag
                                             )
                                          )
                                          ? 1 : 0,
                         }
             );
      }
   }

   return $words;
}

sub _tag2label {
   # return a label like ##TAG5## to replace an html tag
   my ($tag, $r_tags) = @_;

   push(@{$r_tags}, $tag);

   return "##TAG$#{$r_tags}##";
}

sub apply_corrections {
   # loop through the words checking if a cgi parameter exists to correct it
   # apply the cgi parameter correction to the word
   my $words = shift;

   my $corrections = {};

   for (my $i = 0; $i < scalar @{$words}; $i++) {
      # have we already seen a correction for this word?
      $words->[$i]{word} = $corrections->{$words->[$i]{word}}
         if exists $corrections->{$words->[$i]{word}};

      # we have not seen this word - is there a cgi parameter correction?
      my $correction = param($i) || '';

      if ($correction eq '-- add to personal dictionary --') {
         $words->[$i]{pdictadd} = 1;
      } elsif ($correction eq '-- fix manually --') {
         $words->[$i]{manualfix} = 1;
      } elsif ($correction ne '') {
         # store this correction to apply to identical words
         $corrections->{$words->[$i]{word}} = $correction;

         # apply the correction to this word
         $words->[$i]{word} = $correction;
      }
   }

   return $words;
}

sub spellcheck_words {
   my $words = shift;

   my $dictionary = param('dictionary') || $prefs{dictionary} || 'english';

   $dictionary =~ s#\.\.+##g;
   $dictionary =~ s#[^A-Za-z0-9\.]##;

   # get the personal dictionary name
   my $personaldictionaryname = $config{spellcheck_pdicname};
   $personaldictionaryname =~ s/\@\@\@DICTIONARY\@\@\@/$dictionary/;

   # open the spellcheck pipe, including the personal dictionary
   my $spellbin = (split(/\s+/, $config{spellcheck}))[0];
   openwebmailerror(gettext('The spellcheck program cannot be found:') . " ($spellbin)") unless -x $spellbin;

   my $spellcheck = $config{spellcheck};
   $spellcheck =~ s/\@\@\@DICTIONARY\@\@\@/$dictionary/;
   $spellcheck =~ s/\@\@\@PDICNAME\@\@\@/$personaldictionaryname/;

   my ($stdout, $stderr) = pipeopen(split(/\s+/, $spellcheck));
   if ($stdout !~ m/^\@\(#\)/ && $stderr =~ /[^\s]/) {
      pipeclose();
      openwebmailerror(gettext('Spellcheck error:') . " $stderr");
   }

   # create a hash of the words the user has chosen to add to their personal dictionary
   my %personaldictionarywords = map  { $_->{word}, 1 }
                                 grep { exists $_->{pdictadd} && $_->{pdictadd} == 1 }
                                 @{$words};

   # add the new words to the personal dictionary before spellchecking
   my $spellcmd = '';
   $spellcmd .= "*$_\n" for keys %personaldictionarywords;

   if ($spellcmd ne '') {
      # add words to personal dictionary
      # the 2nd \n guarantees we have output from the piperead
      pipewrite($spellcmd . "\#\n\n");
      ($stdout, $stderr) = piperead(2);

      # it seems adding words to the personal dictionary does not generate
      # output on aspell 0.50, so do not error check the result
   }

   # now perform the spellchecking
   my %alreadychecked   = ();
   my %misspelled       = ();

   for (my $i = 0; $i < scalar @{$words}; $i++) {
      next if $words->[$i]{ignore} == 1;

      my $word = $words->[$i]{word};

      $words->[$i]{wordnumber} = $i;

      if (exists $alreadychecked{$word} && defined $alreadychecked{$word}) {
         $words->[$i]{alreadychecked} = 1;
         $words->[$i]{misspelled}     = exists $misspelled{$word} ? 1 : 0;
      } elsif (exists $personaldictionarywords{$word} && defined $personaldictionarywords{$word}) {
         next;
      } elsif (exists $words->[$i]{manualfix} && $words->[$i]{manualfix} == 1) {
         # this is a manual fix
         $words->[$i]{misspelled}        = 1;
         $words->[$i]{manualword}        = $word;
         $words->[$i]{manualword_length} = length($word);
         $alreadychecked{$word}          = 1;
         $personaldictionarywords{$word} = 1;
      } else {
         # spellcheck this word
         my $result = spellcheck($word);

         $result->{type} = 'unknown' unless defined $result->{type};

         if ($result->{type} eq 'none' || $result->{type} eq 'guess') {
            $words->[$i]{misspelled} = 1;
            $misspelled{$word} = 1;
         } elsif ($result->{type} eq 'miss')  {
            $words->[$i]{misspelled} = 1;
            $misspelled{$word} = 1;

            push(@{$words->[$i]{suggestionsloop}}, { suggestion => $_ }) for @{$result->{misses}};
         } else {
            # type = ok, compound, root
         }

         $alreadychecked{$word} = 1;
      }
   }

   pipeclose();

   return $words;
}

sub spellcheck {
   # given a single word, send it to the spellcheck program
   # (usually aspell or ispell) and return the result as a hash
   my $word = shift || '';

   $word =~ s/[\r\n]//g;

   return { type => 'ok' } if $word eq '' || $word =~ m/^\s*$/;

   my %types = (
                  # correct word prefixes
                  '*' => 'ok',
                  '-' => 'compound',
                  '+' => 'root',
                  # misspelled word prefixes
                  '#' => 'none',
                  '&' => 'miss',
                  '?' => 'guess',
               );

   # initiate the conversation with the spellchecker
   # one line of stdout looks like (for the sample misspelled word 'tst'):
   # & tst 22 1: test, tat, ST, St, st, ts, DST, SST, Tet, Tut, tit, tot, tut, CST, EST, HST, MST, PST, TNT, est, tsp, T's
   my @commentary = ();
   my @results    = ();

   pipewrite("!\n^$word\n");

   my ($stdout, $stderr) = piperead();
   if ($stderr =~ m/[^\s]/) {
      pipeclose();
      openwebmailerror(gettext('Spellcheck error:') . " $stderr");
   }

   foreach my $line (split(/\n/, $stdout)) {
      last unless $line gt '';
      # * ok, - compound, + root, # none, & miss, ? guess
      push (@commentary, $line) if $line =~ m/^[*\-+#?&\s\|]/;
   }

   my %modisp = (
                   'root' => sub {
                                    my $h = shift;
                                    $h->{root} = shift;
                                 },
                   'none' => sub {
                                    my $h = shift;
                                    $h->{original} = shift;
                                    $h->{offset}   = shift;
                                 },
                   'miss' => sub {
                                    # also used for 'guess'
                                    my $h = shift;
                                    $h->{original} = shift;
                                    $h->{count}    = shift; # count will always be 0, when $c eq '?'.
                                    $h->{offset}   = shift;
                                    my @misses     = splice(@_, 0, $h->{count});
                                    my @guesses    = @_;
                                    $h->{misses}   = \@misses;
                                    $h->{guesses}  = \@guesses;
                                 },
                );

   $modisp{guess} = $modisp{miss}; # same handler

   foreach my $i (0 .. $#commentary) {
      my %h = ('commentary' => $commentary[$i]);
      my @tail = (); # will get stuff after a colon, if any.

      if ($h{commentary} =~ s/:\s+(.*)//) {
         my $tail = $1;
	 @tail = split(/, /, $tail);
      }

      my($c, @args) = split(' ', $h{commentary});
      my $type = exists $types{$c} ? $types{$c} : 'unknown';

      # organize the results into a hash
      $modisp{$type}->(\%h, @args, @tail) if exists $modisp{$type};

      $h{type} = $type;
      $h{term} = $h{original};
      push(@results, \%h);
   }

   return $results[0];
}

sub spellcheckform {
   my $words = shift;

   my $htmlmode   = param('htmlmode')   || ''; # are we are checking html?
   my $dictionary = param('dictionary') || $prefs{dictionary} || 'english';

   $dictionary =~ s#\.\.+##g;
   $dictionary =~ s#[^A-Za-z0-9\.]##;

   # modify the word for display
   # preserve the formatting of the original message as closely as possible
   for (my $i = 0; $i < scalar @{$words}; $i++) {
      my $displayword = "$words->[$i]{word}";

      if ($words->[$i]{is_tag}) {
         if ($htmlmode && $displayword =~ s#^(?:\s*<br ?/?>\s*)+$#<br>#mg) {
            # display html line breaks
            $words->[$i]{ignore} = 0;
            $words->[$i]{is_tag} = 0;
         }
      } else {
         if ($htmlmode) {
            $displayword =~ s/^[ \t]([^ \t]+)[ \t]$/~!~$1~!~/sg;
            $displayword = ow::htmltext::html2text($displayword, 1);
            $displayword =~ s/^~!~([^ \t]+)~!~/&nbsp;$1&nbsp;/sg;
         } else {
            # preserve text line breaks
            $displayword = ow::htmltext::text2html($displayword, 1);
            $displayword =~ s#\s*<br ?/?>\s*#<br>#sg;
            $displayword =~ s/(?:\r\n|\r|\n)/<br>/sg;
         }
      }

      $words->[$i]{displayword} = $displayword;
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("spell_check.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      url_cgi         => $config{ow_cgiurl},

                      # spell_check.tmpl
                      htmlmode        => $htmlmode,
                      dictionary      => $dictionary,
                      words           => $words,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub finishcheck {
   my $words = shift;

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("spell_finish.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # spell_finish.tmpl
                      words                      => $words,
                   );

   httpprint([], [$template->output]);
}

sub editpdict {
   my $dictword2delete = param('dictword2delete') || '';
   my $htmlmode        = param('htmlmode')   || ''; # are we are checking html?
   my $dictionary      = param('dictionary') || $prefs{dictionary} || 'english';

   $dictionary =~ s#\.\.+##g;
   $dictionary =~ s#[^A-Za-z0-9\.]##;

   # use same personal dictionary file path as the spellchecker default
   my $personaldictionaryname = $config{spellcheck_pdicname};
   $personaldictionaryname =~ s/\@\@\@DICTIONARY\@\@\@/$dictionary/;

   my $personaldictionaryfile = ow::tool::untaint("$homedir/$personaldictionaryname");

   my $pdictloop = [];

   if (-f $personaldictionaryfile) {
      if ($dictword2delete ne '') {
         # user has submitted a word to delete from the personal dictionary
         my $personaldictionarywordstr = '';

         # read all the words from the personal dictionary except the word to delete
         sysopen(PDICT, $personaldictionaryfile, O_RDONLY) or
            openwebmailerror(gettext('Cannot open file:') . " $personaldictionaryfile ($!)");

         while (defined(my $line = <PDICT>)) {
            chomp($line);
            next if $line eq $dictword2delete;
            $personaldictionarywordstr .= "$line\n";
         }

         close(PDICT) or
            openwebmailerror(gettext('Cannot close file:') . " $personaldictionaryfile ($!)");

         # write the new dictionary to a temp file
         sysopen(NEWPDICT, "$personaldictionaryfile.new", O_WRONLY|O_TRUNC|O_CREAT) or
            openwebmailerror(gettext('Cannot open file:') . " $personaldictionaryfile.new ($!)");

         print NEWPDICT $personaldictionarywordstr;

         close(NEWPDICT) or
            openwebmailerror(gettext('Cannot close file:') . " $personaldictionaryfile.new ($!)");

         # backup the current dictionary
         rename($personaldictionaryfile, "$personaldictionaryfile.bak") or
            openwebmailerror(gettext('Cannot rename file:') . " $personaldictionaryfile -> $personaldictionaryfile.bak ($!)");

         # move the new dictionary to its position
         rename("$personaldictionaryfile.new", $personaldictionaryfile) or
            openwebmailerror(gettext('Cannot rename file:') . " $personaldictionaryfile.new -> $personaldictionaryfile ($!)");
      }

      # read the personal dictionary into the pdictloop
      sysopen(PDICT, $personaldictionaryfile, O_RDONLY) or
         openwebmailerror(gettext('Cannot open file:') . " $personaldictionaryfile ($!)");

      my $count = 1;

      while (defined(my $line = <PDICT>)) {
         chomp($line);

         # skip first aspell line
         next if $line =~ m/^personal_ws/;

         push(@{$pdictloop}, {
                                # standard params
                                sessionid => $thissession,
                                url_cgi   => $config{ow_cgiurl},

                                word      => $line,
                                is_odd    => $count++ % 2 == 0 ? 0 : 1,
                             }
             );
      }

      close(PDICT) or
         openwebmailerror(gettext('Cannot close file:') . " $personaldictionaryfile ($!)");
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("spell_editdictionary.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template => get_header($config{header_template_file}),

                      # standard params
                      sessionid       => $thissession,
                      url_cgi         => $config{ow_cgiurl},

                      # spell_editdictionary.tmpl
                      pdictloop       => $pdictloop,

                      # footer.tmpl
                      footer_template => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub pipeopen {
   my @cmd = @_;

   local $1;     # fix perl $1 taintness propagation bug
   local $| = 1; # flush CGI related output in parent

   # untaint all argument
   ($_) = $_ =~ m/^(.*)$/ for @cmd;

   my $cgipid = $$;

   ($piperun, $pipeexit, $pipesig) = (1,0,0);
   local $SIG{CHLD} = sub {
                             # to get child status
                             wait;
                             $pipeexit = $? >> 8;
                             $pipesig  = $? & 255;
                             $piperun  = 0;
                          };

   eval { $pipepid = open3(\*spellIN, \*spellOUT, \*spellERR, @cmd); };

   if ($@) {              # open3 return err only in child
      if ($$ != $cgipid){ # child
         print STDERR $@; # pass $@ to parent through stderr pipe
         exit 9;          # terminated
      }
   }

   return(piperead());
}

sub piperead {
   my $timeout = shift;
   $timeout = 10 if defined $timeout && $timeout <= 0;

   my ($stdout, $stderr, $retry) = ('', '', 0);
   while (1) {
      my ($rin, $rout, $ein, $eout) = ('','','','');
      vec($rin, fileno(\*spellOUT), 1) = 1;
      vec($rin, fileno(\*spellERR), 1) = 1;
      $ein = $rin;

      # timeout is changed to 0.001 once any data in
      my $n = select($rout = $rin, undef, $eout = $ein, $timeout);

      if ($n > 0) { # fd is ready for reading
         my ($o, $e, $buf) = (-1, -1, '');

         if (vec($rout,fileno(\*spellOUT),1)) {
            $o = sysread(\*spellOUT, $buf, 65536);
            if ($o > 0) {
               $stdout .= $buf;
               $timeout = 0.001;
            }
         }

         if (vec($rout,fileno(\*spellERR),1)) {
            $e = sysread(\*spellERR, $buf, 65536);
            if ($e > 0) {
               $stderr .= $buf;
               $timeout = 0.001;
            }
         }

         last if ($o == 0 && $e == 0); # os ensure there is no more data to read
      } elsif ($n == 0) { # read timeout
         if ($stdout =~ m/\n/ || $stderr =~ m/\n/) { # data line already in
            last;
         } elsif ($stdout eq '' && $stderr eq '') {  # 1st read timeout
            $stderr = 'piperead nothing';
            last;
         }
         # else continue to read until line
      } else {	# n < 0, read err => child dead?
         $stderr = "piperead error $n";
         last;
      }

      if ($retry++ > 100) {
         $stderr = 'piperead too many retries';
         last;
      }
   }

   if (!$piperun) {
      $stderr = 'terminated abnormally' if $stderr eq '';
      $stderr .= " (exit $pipeexit, sig $pipesig)";
   }

   return ($stdout, $stderr);
}

sub pipewrite {
   print spellIN shift;
}

sub pipeclose {
   close spellIN;
   close spellOUT;
   close spellERR;
}

