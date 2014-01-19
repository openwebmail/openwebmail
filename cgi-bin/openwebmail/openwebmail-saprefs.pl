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
use HTML::Template 2.9;

# load OWM libraries
require "modules/dbm.pl";
require "modules/suid.pl";
require "modules/filelock.pl";
require "modules/tool.pl";
require "modules/datetime.pl";
require "modules/lang.pl";
require "modules/mime.pl";
require "modules/htmltext.pl";
require "auth/auth.pl";
require "quota/quota.pl";
require "shares/ow-shared.pl";
require "shares/iconv.pl";

# optional module
ow::tool::has_module('Compress/Zlib.pm');

# common globals
use vars qw(%config $thissession %prefs $icons $homedir);

# extern vars
use vars qw($htmltemplatefilters $po); # defined in ow-shared.pl

# local globals
use vars qw($folder $messageid $sort $msgdatetype $page $longpage $searchtype $keyword);
use vars qw($prefs_caller);


# BEGIN MAIN PROGRAM

openwebmail_requestbegin();
$SIG{PIPE} = \&openwebmail_exit;	# for user stop
$SIG{TERM} = \&openwebmail_exit;	# for user stop
userenv_init();

openwebmailerror(gettext('Access denied: the webmail module is not enabled.')) unless $config{enable_webmail};
openwebmailerror(gettext('Access denied: the spam preferences module is not enabled.')) unless $config{enable_saprefs};

$folder       = param('folder') || 'INBOX';
$keyword      = param('keyword') || '';
$longpage     = param('longpage') || 0;
$msgdatetype  = param('msgdatetype') || $prefs{msgdatetype};
$page         = param('page') || 1;
$searchtype   = param('searchtype') || $prefs{searchtype} || 'subject';
$sort         = param('sort') || $prefs{sort} || 'date_rev';
$messageid    = param('message_id')   || '';
$prefs_caller = param('prefs_caller') || '';

my $action    = param('action')       || '';

writelog("debug_request :: request saprefs begin, action=$action") if $config{debug_request};

$action eq 'editrules'        ? editrules()                    :
$action eq 'addrule'          ? modrule('add')                 :
$action eq 'deleterule'       ? modrule('delete')              :
$action eq 'editwhitelist'    ? editlist('whitelist')          :
$action eq 'editblacklist'    ? editlist('blacklist')          :
$action eq 'addwhitelist'     ? modlist('add', 'whitelist')    :
$action eq 'addblacklist'     ? modlist('add', 'blacklist')    :
$action eq 'deletewhitelist'  ? modlist('delete', 'whitelist') :
$action eq 'deleteblacklist'  ? modlist('delete', 'blacklist') :
openwebmailerror(gettext('Action has illegal characters.'));

writelog("debug_request :: request saprefs end, action=$action") if $config{debug_request};

openwebmail_requestend();

# BEGIN SUBROUTINES

sub editrules {
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = read_saprefs();

   my $rulesloop = [];
   my $rulecount = 1;

   foreach my $rulename (sort keys %{$r_rules}) {
      my %rule = %{$r_rules->{$rulename}};

      # modification on these records are not supported
      next if $rule{type} eq 'meta' || defined $rule{ifunset} || defined $rule{tflags};

      my $score = '';

      if (defined $rule{score}[0]) {
         $score = $rule{score}[0];
      } else {
         $score = 1;                           # default 1 for no score rule
         $score = 0.01 if $rulename =~ m/^T_/; # default 0.01 if rule is for testing only
      }

      push(@{$rulesloop}, {
                             url_cgi         => $config{ow_cgiurl},
                             folder          => $folder,
                             page            => $page,
                             sort            => $sort,
                             message_id      => $messageid,
                             sessionid       => $thissession,
                             prefs_caller    => $prefs_caller,
                             uselightbar     => $prefs{uselightbar},
                             odd             => $rulecount % 2,
                             rulenumber      => $rulecount,
                             rulename        => $rulename,
                             ruledescription => $rule{desc},
                             ruletype        => $rule{type},
                             ruleheaderattr  => $rule{headerattr},
                             ruleop          => $rule{op},
                             pattern         => $rule{pattern},
                             ignorecase      => $rule{modifier} =~ m/i/ ? 1 : 0,
                             singleline      => $rule{modifier} =~ m/s/ ? 1 : 0,
                             score           => $score,
                         }
          );

      $rulecount++;
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("sa_editrules.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html                   => $config{ow_htmlurl},
                      url_cgi                    => $config{ow_cgiurl},
                      iconset                    => $prefs{iconset},
                      sessionid                  => $thissession,
                      message_id                 => $messageid,
                      folder                     => $folder,
                      sort                       => $sort,
                      page                       => $page,
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # sa_editrules.pl
                      prefs_caller               => $prefs_caller,
                      is_callerfolderdefault     => is_defaultfolder($folder) ? 1 : 0,
                      "callerfoldername_$folder" => 1,
                      callerfoldername           => f2u($folder),
                      rulesloop                  => $rulesloop,

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub modrule {
   my $mode     =  shift;
   my $rulename =  param('rulename') || '';
   $rulename    =~ s/^\s*//;
   $rulename    =~ s/\s*$//;
   $rulename    =~ s/[^A-Z0-9_]/_/ig; # convert anything not letters, numbers, or underscore to underscore
   return editrules() unless $rulename;

   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = read_saprefs();

   my %rule = ();
   if ($mode eq 'add') {
      $rule{type} =  param('ruletype') || '';
      $rule{type} =~ s/^\s*//;
      $rule{type} =~ s/\s*$//;

      $rule{pattern} = param('pattern') || '';
      $rule{pattern} =~ s/^\s*\///; # remove leading whitespace and slashes
      $rule{pattern} =~ s/\/\s*$//; # remove trailing whitespace and slashes
      $rule{pattern} =~ s#\\/#/#g;  # escape internal slashes
      $rule{pattern} =~ s#/#\\/#g;  # escape internal backslashes

      if ($rule{type} ne '' && $rule{pattern} ne '' && ow::tool::is_regex($rule{pattern})) {
         $rule{desc} = param('ruledescription') || '';

         if ($rule{type} eq 'header') {
            $rule{headerattr} = param('ruleheaderattr') || 'ALL';
            $rule{op}         = param('ruleoperation')  || '=~';
         }

         $rule{modifier}  =  '';
         $rule{modifier} .= 'i' if param('ignorecase');
         $rule{modifier} .= 's' if param('singleline');

         $rule{score} = [ sprintf("%4.2f", (param('score') || 0)) ];

         $r_rules->{$rulename} = \%rule;
         write_saprefs($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   } elsif ($mode eq 'delete') {
      if (defined $r_rules->{$rulename}) {
         delete $r_rules->{$rulename};
         write_saprefs($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   }

   return editrules();
}

sub editlist {
   my $listtype = shift || 'whitelist';

   $listtype = 'whitelist' if $listtype ne 'whitelist' && $listtype ne 'blacklist';

   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = read_saprefs();

   my $listcount = 1;
   my $listloop  = [];

   foreach my $email ($listtype eq 'whitelist' ? sort keys %{$r_whitelist_from} : sort keys %{$r_blacklist_from}) {
      next if $email !~ m/^(?:[a-zA-Z0-9!#\$%&'*+-\/=?^_`.{|}~]{1,64}@)?[%*a-zA-Z0-9.-]{4,255}$/; # rfc3696

      push(@{$listloop}, {
                           url_cgi      => $config{ow_cgiurl},
                           folder       => $folder,
                           page         => $page,
                           sort         => $sort,
                           message_id   => $messageid,
                           sessionid    => $thissession,
                           prefs_caller => $prefs_caller,
                           uselightbar  => $prefs{uselightbar},
                           odd          => $listcount % 2,
                           email        => $email,
                           is_whitelist => $listtype eq 'whitelist' ? 1 : 0
                         }
          );

      $listcount++;
   }

   # build the template
   my $template = HTML::Template->new(
                                        filename          => get_template("sa_editlist.tmpl"),
                                        filter            => $htmltemplatefilters,
                                        die_on_bad_params => 0,
                                        loop_context_vars => 0,
                                        global_vars       => 0,
                                        cache             => 0,
                                     );

   $template->param(
                      # header.tmpl
                      header_template            => get_header($config{header_template_file}),

                      # standard params
                      use_texticon               => $prefs{iconset} =~ m/^Text$/ ? 1 : 0,
                      url_html                   => $config{ow_htmlurl},
                      url_cgi                    => $config{ow_cgiurl},
                      iconset                    => $prefs{iconset},
                      sessionid                  => $thissession,
                      message_id                 => $messageid,
                      folder                     => $folder,
                      sort                       => $sort,
                      page                       => $page,
                      (map { $_, $icons->{$_} } keys %{$icons}),

                      # sa_edittest.pl
                      prefs_caller               => $prefs_caller,
                      is_callerfolderdefault     => is_defaultfolder($folder) ? 1 : 0,
                      "callerfoldername_$folder" => 1,
                      callerfoldername           => f2u($folder),
                      listloop                   => $listloop,
                      is_whitelist               => $listtype eq 'whitelist' ? 1 : 0,

                      # footer.tmpl
                      footer_template            => get_footer($config{footer_template_file}),
                   );

   httpprint([], [$template->output]);
}

sub modlist {
   my ($mode, $listtype) = @_;

   return editlist() if $listtype ne 'whitelist' && $listtype ne 'blacklist';

   my $email =  param('email') || '';
   $email    =~ s/^\s*//;
   $email    =~ s/\s*$//;
   return editlist($listtype) if $email eq '' || $email !~ m/^(?:[a-zA-Z0-9!#\$%&'*+-\/=?^_`.{|}~]{1,64}@)?[%*a-zA-Z0-9.-]{4,255}$/; # rfc3696

   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = read_saprefs();

   my $r_list = $listtype eq 'whitelist' ? $r_whitelist_from : $r_blacklist_from;

   if ($mode eq 'add') {
      if (!defined $r_list->{$email}) {
         $r_list->{$email} = 1;
         write_saprefs($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   } elsif ($mode eq 'delete') {
      if (defined $r_list->{$email}) {
         delete $r_list->{$email};
         write_saprefs($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from);
      }
   }

   return editlist($listtype);
}

sub read_saprefs {
   my $saprefsfile = "$homedir/.spamassassin/user_prefs";

   my @lines          = ();
   my @datas          = ();
   my %rules          = ();
   my %whitelist_from = ();
   my %blacklist_from = ();

   ow::filelock::lock($saprefsfile, LOCK_SH) or
      openwebmailerror(gettext('Cannot lock file:') . " $saprefsfile");

   if (!sysopen(F, $saprefsfile, O_RDONLY)) {
      ow::filelock::lock($saprefsfile, LOCK_UN) or
         openwebmailerror(gettext('Cannot unlock file:') . " $saprefsfile");

      writelog("Cannot open file: $saprefsfile ($!)");

      return (\@datas, \%rules, \%whitelist_from, \%blacklist_from);
   }

   while (defined(my $line = <F>)) {
      $line =~ s/\s*$//;
      push(@lines, $line);
   }

   close(F) or
      openwebmailerror(gettext('Cannot close file:') . " $saprefsfile ($!)");

   ow::filelock::lock($saprefsfile, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . " $saprefsfile");

   for (my $i = 0; $i <= $#lines; $i++) {
      my $line = $lines[$i];

      # parse ruleset related lines
      if ($line =~ m/^(?:score|describe|tflags|header|uri|body|full|rawbody|meta)\s/) {
         while (defined $lines[$i + 1] && $lines[$i + 1] =~ /^ /) {
            # part of a multi-line rule
            $i++;
            $line .= $lines[$i];
            $line =~ s/\s*$//;
         }

         my ($key, $rulename, $value) = split(/\s+/, $line, 3);

         $key      ||= '';
         $rulename ||= '';
         $value    ||= '';

         if ($key eq 'score') {
            $rules{$rulename}{score} = [split(/\s+/, $value)];
         } elsif ($key eq 'describe') {
            $rules{$rulename}{desc} = $value;
         } elsif ($key eq 'tflags') {
            $rules{$rulename}{tflags} = [split(/\s+/, $value)];
         } elsif ($key =~ m/^(?:header|uri|body|full|rawbody|meta)$/) {
            $rules{$rulename}{type} = $key;

            if ($key eq 'meta') {
               $rules{$rulename}{expression} = $value;
            } else {
               my $headerattr = '';
               my $op         = '';
               my $pattern    = '';

               if ($key eq 'header') {
                  ($headerattr, $op, $pattern) = split(/\s+/, $value, 3);
                  $rules{$rulename}{headerattr} = $headerattr;
                  $rules{$rulename}{op} = $op;
               } else {
                  $pattern = $value;
               }

               $rules{$rulename}{ifunset}  = $1 if $pattern =~ s/\s*\[\s*if-unset:\s(.*)\]$//;
               $rules{$rulename}{modifier} = "";
               $rules{$rulename}{modifier} = $1 if $pattern =~ s/\/([oigms]+)$/\//;

               $pattern =~ s/^\s*\///;
               $pattern =~ s/\/\s*$//;

               $rules{$rulename}{pattern} = $pattern;
            }
         }
      } elsif ($line =~ m/^whitelist_from\s/) {
         my @list = split(/\s+/, $line);
         shift @list;
         $whitelist_from{$_} = 1 for @list;
      } elsif ($line =~ m/^blacklist_from\s/) {
         my @list = split(/\s+/, $line);
         shift @list;
         $blacklist_from{$_} = 1 for @list;
      } else {
         push(@datas, $line);
      }
   }

   return(\@datas, \%rules, \%whitelist_from, \%blacklist_from);
}

sub write_saprefs {
   my ($r_datas, $r_rules, $r_whitelist_from, $r_blacklist_from) = @_;

   my $saprefsfile = "$homedir/.spamassassin/user_prefs";

   my @p = split(m#/#, $saprefsfile);
   pop @p;
   my $dir = join('/', @p);
   mkdir($dir, 0700) unless -d $dir;

   ow::filelock::lock($saprefsfile, LOCK_EX|LOCK_NB) or
      openwebmailerror(gettext('Cannot lock file:') . " $saprefsfile");

   if (!sysopen(F, $saprefsfile, O_WRONLY|O_TRUNC|O_CREAT)) {
      writelog("Cannot open file: $saprefsfile ($!)");

      ow::filelock::lock($saprefsfile, LOCK_UN) or
         writelog("Cannot unlock file: $saprefsfile");

      return -1;
   }

   my $data = join("\n", @{$r_datas});
   $data =~ s/\n\n+/\n\n/g;
   print F $data;

   my $whitelist_string = '';

   foreach my $email (sort keys %{$r_whitelist_from}) {
      if (length($whitelist_string) + length($email) > 60) {
         print F "whitelist_from $whitelist_string\n";
         $whitelist_string = '';
      }

      $whitelist_string .= ' ' if $whitelist_string ne '';
      $whitelist_string .= $email;
   }

   print F "whitelist_from $whitelist_string\n" if $whitelist_string ne '';
   print F "\n";

   my $blacklist_string = '';

   foreach my $email (sort keys %{$r_blacklist_from}) {
      if (length($blacklist_string) + length($email) > 60) {
         print F "blacklist_from $blacklist_string\n";
         $blacklist_string = '';
      }
      $blacklist_string .= ' ' if $blacklist_string ne '';
      $blacklist_string .= $email;
   }

   print F "blacklist_from $blacklist_string\n" if $blacklist_string ne '';
   print F "\n";

   foreach my $rulename (sort keys %{$r_rules}) {
      my %rule = %{$r_rules->{$rulename}};
      if (defined $rule{type}) {
         if ($rule{type} eq 'meta') {
            print "meta $rulename\t\t$rule{expression}\n";
         } else {
            my $pattern = '/' . $rule{pattern} . '/';
            $pattern   .= $rule{modifier} if defined $rule{modifier};
            $pattern   .= " [if-unset: $rule{ifunset}]" if defined $rule{ifunset};

            if ($rule{type} eq 'header') {
               print F "header\t\t$rulename\t\t$rule{headerattr} $rule{op} $pattern\n";
            } else {
               print F "$rule{type}\t\t$rulename\t\t$pattern\n";
            }
         }
      }

      if (defined $rule{score}) {
         print F "score\t\t$rulename\t\t" . join(' ', @{$rule{score}}) . "\n";
      }

      if (defined $rule{tflags}) {
         print F "tflags\t\t$rulename\t\t" . join(' ', @{$rule{tflags}}) . "\n";
      }

      if (defined $rule{desc}) {
         print F "describe\t$rulename\t\t$rule{desc}\n";
      }

      print F "\n";
   }

   close(F) or
      openwebmailerror(gettext('Cannot close file:') . " $saprefsfile ($!)");

   ow::filelock::lock($saprefsfile, LOCK_UN) or
      openwebmailerror(gettext('Cannot unlock file:') . " $saprefsfile");

   return 0;
}
