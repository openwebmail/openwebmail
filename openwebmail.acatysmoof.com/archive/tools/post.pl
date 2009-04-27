#!/usr/bin/perl -w

#This script authenticates users via the Majordomo2 interface.
#Authenticated users are then allowed to post messages as if
#the messages are coming from their own email accounts to the
#Majordomo2 lists that they are subscribed to.
#By including this script in an iframe of an html message page,
#any mhonarc/majordomo2 installation can have a mailing list
#with functionality similar to a forum (ie: posting directly
#from the web).


BEGIN {
  $::LIBDIR = "/usr/local/majordomo/lib";
  $::LISTDIR= "/usr/local/majordomo/lists";
  $::TMPDIR = "/usr/local/majordomo/tmp";
  $::LOCKDIR= "/usr/local/majordomo/tmp/locks";
  $::UID    = "54";
  $::GID    = "54";
  $::UMASK  = "007";
  $SIG{__WARN__} = sub {print STDERR "--== $_[0]"};

  # Redirect standard error output.
  if (! -t STDERR) {
    open (STDERR, ">>$::TMPDIR/mj_wwwusr.debug");
  }

  # Croak if install was botched
  die("Not running as UID $::UID") unless $> == $::UID;
  die("Not running as GID $::GID") unless $) == $::GID;
  $< = $>; $( = $);
}

my $shutup_warnings = $::LIBDIR;

use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser carpout);
use HTML::Template;
use HTML::Scrubber;
use HTML::TreeBuilder;
use HTML::FormatText;
use HTML::Entities;
use MIME::QuotedPrint;
use Mail::Sendmail 0.75; # doesn't work with v. 0.74!;

# password auth through Majordomo
use lib $::LIBDIR;
use Majordomo;
use Mj::Log;

# a custom version of BBCode::Parser
# outputs special CODE and QUOTE tags
use lib 'post_lib';
use BBCode::Parser 0.22;

my ($cgi, $list, $msgid, $msgsubject, $contentsubject, $pathinfo, $domain, @domains, $tmp, $mj, $sess, $opass, $passw, $falseuser, $user, $ok, $mess, $addr);

#----- Initialize the Log -----#
&initialize_log;

#----- Initialize the CGI object -----#
$cgi = new CGI;

# which list?
$list = $cgi->param('list') || croak("List name is undefined");
$list = lc($list);
croak("Invalid list") if $list !~ m#^owm-(?:users|devel|test|announce|i18n)$#;

# which msgid?
$msgid = $cgi->param('msgid') || make_msgid($list);

# a subject replying to?
$msgsubject = $cgi->param('msgsubject') || "No Subject";
$contentsubject = $cgi->param('contentsubject') || $cgi->param('msgsubject') || "No Subject";

$pathinfo = '';
$domain = $cgi->param('domain') || '';

if (exists $ENV{'PATH_INFO'}) {
  $pathinfo = $ENV{'PATH_INFO'};
  while ($pathinfo =~ s#/domain=([^/]+)##) {
    $tmp = $1;
    next if ($tmp =~ /[^a-zA-Z0-9.-]/);
    # Use the first domain found.
    $domain = $tmp unless (length $domain);
  }

  $pathinfo =~ s#^/+##;
  $pathinfo =~ s#/+$##;
  if ($pathinfo =~ m#(.+\@[^/]+)#) {
    # The path appears to contain the subscriber's address.
    $pathinfo = $1;
  }
  else {
    $pathinfo = '';
  }
}

unless ($domain) {
  @domains = Majordomo::domains($::LISTDIR);
  ($domain) = grep { lc $_ eq lc $ENV{'HTTP_HOST'} } @domains;
  $domain = $domains[0] unless $domain;
}


#----- Make the Majordomo object -----#
$mj = new Majordomo "/usr/local/majordomo/lists", "openwebmail.acatysmoof.com";
croak("The mj object is not a ref. Bad initialization. $mj") unless (ref $mj);

#----- Generate the session information. -----#
for my $i ('REMOTE_ADDR','REMOTE_PORT', 'PATH_INFO') {
  $sess .= "X-$i: $ENV{$i}\n" if defined $ENV{$i};
}
$sess .= "Date: " . scalar(localtime(time)) . "\n";

#----- Determine the address of the user. -----#
$falseuser = "x$ENV{'REMOTE_ADDR'}\@example.com";
# Convert colons to underscores in IPv6 addresses
$falseuser =~ s/:/_/g;

if (defined $cgi->cookie($list)) {
   my %cookie = $cgi->cookie($list);
   $user = substr($cgi->cookie($list), 15); # remove token lead DI86-USJD-ISK8_
} else {
   $user = $cgi->param('user') || $falseuser;
}

#----- Determine the password -----#
if (defined $cgi->cookie($list)) {
   $opass = $passw = substr($cgi->cookie($list), 0, 14); # return token lead DI86-USJD-ISK8
} else {
   $opass = $cgi->param('passw');
   if (defined $opass and length $opass) {
     if ($opass =~ /(\S+)/) {
       $passw = $1;
     } else {
       $passw = '';
     }
   } else {
     $opass = $passw = '';
   }
}

#----- Connect to the server -----#
($ok, $mess) = $mj->connect('wwwusr', $sess, $user, $passw);
bad_server_connect($mess) unless $ok;


#----- Create a temporary password -----#
if (length $opass) {
  # makes the password into a token unless it already is one
  $passw = $mj->gen_latchkey($passw) unless ($mj->t_recognize($passw));
}

#print $cgi->header();
#my @list = $cgi->param();
#print join("<br>\n", map { "$_ = " . $cgi->param($_) } @list);


# Validate
if (defined $passw and length $passw) {
   $addr = new Mj::Addr($user);
   if ($mj->validate_passwd($addr, $passw, 'GLOBAL', 'show')) {
      if ($mj->is_subscriber($addr, $list)) {
         # how much latchkey time left?
         my $remainingtime = 0;
         $mj->_make_latchkeydb;
         if (defined $mj->{'latchkeydb'}) {
            my $lkdata = $mj->{'latchkeydb'}->lookup($passw);
            if (defined $lkdata) {
               $remainingtime = HHMMSS($lkdata->{'expire'} - time);
            }
         }

         if (defined $cgi->param('logout')) {
            $mj->del_latchkey($passw);
            my $cookie = $cgi->cookie(
                                       -name => $list,
                                       -value => $passw.'_'.$user,
                                       -expires => '-1d',
                                     );
            print httpheader($cookie);
            login_form($list, $msgid, $msgsubject, $user);
         } elsif ((defined $cgi->param('func') && $cgi->param('func') eq "compose") || defined $cgi->cookie($list)) {
            my $content = $cgi->param('content') || '';
            my $preview = '';

            $preview = content_to_HTML($content) if length $content;

            if ($cgi->param('send_message')) {
               my $userdata = $mj->_reg_lookup($addr);
               my $sender = $userdata->{'fulladdr'} || $user;
               send_message($list, $msgid, $sender, $contentsubject, $preview, $remainingtime);
            } else {
               compose_form($list, $msgid, $msgsubject, $contentsubject, $user, $passw, $content, $preview, $remainingtime);
            }
         } else {
            login_form($list, $msgid, $msgsubject, $user, $remainingtime);
         }
      } else {
         login_form($list, $msgid, $msgsubject, $user, "non-subscriber");
      }
   } else {
      login_form($list, $msgid, $msgsubject, $user, "bad_password");
   }
} else {
  login_form($list, $msgid, $msgsubject);
}



# Subroutines
sub login_form {
   my ($list, $msgid, $msgsubject, $user, $badpass) = @_;
   my $TEMPLATE = {
                    LIST => $list,
                    MSGID => $msgid,
                    MSGSUBJECT => $msgsubject,
                    USER => $user,
                    BADPASS => $badpass,
                    NEWTOPIC => $cgi->param('newtopic') || 0,
                  };
   print $cgi->header() unless defined $cgi->param('logout');
   my $template = HTML::Template->new(filename => "post_login.tmpl", loop_context_vars => 1, global_vars => 1);
   $template->param($TEMPLATE);
   print $template->output;
}

sub make_msgid {
  my ($list) = $_[0];
  my @alpha   = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
  my $firstpart = join '', map $alpha[rand @alpha], 0 .. 4;
  my $secondpart = join '', map $alpha[rand @alpha], 0 .. 4;
  return $list . $firstpart . $secondpart . "\@openwebmail.acatysmoof.com";
}

sub send_message {
   my ($list, $msgid, $sender, $contentsubject, $contenthtml) = @_;

   # convert the HTML version to text since we don't have a BBCode->Text converter
   my $htmltree = HTML::TreeBuilder->new();
   $htmltree->no_space_compacting(1);
   $htmltree->parse_content($contenthtml);
   my $formatter = HTML::FormatText->new(leftmargin => 0, rightmargin => 72);
   my $contenttext = $formatter->format($htmltree);

   # convert HTML::Entities to regular text
   $contenttext = decode_entities($contenttext);

   # goodbye leading whitespace
   $contenttext =~ s/^\s+//sg;

   # eliminate any From lines that break the mbox format
   $contenttext =~ s/[\r\n]From/\n From/gs;
   $contenttext =~ s/^From/\n From/gs;

   # qpencode ready for sending
   $contenttext = encode_qp($contenttext);
   $contenthtml = encode_qp($contenthtml);

   my $boundary = "====OWM_ARCHIVE" . time() . "====";

   my %mail = (
                 'Content-Type' => "multipart/alternative; boundary=\"$boundary\"",
                 'In-Reply-To' => "<".$msgid.">",
                 'X-Mailer' => "OWM Archive Post Interface",
                 Subject => $contentsubject,
                 To => "$list\@openwebmail.acatysmoof.com",
                 From => $sender,
              );

   $boundary = '--'.$boundary;

   $mail{Message} = <<END;
$boundary
Content-Type: text/plain; charset="iso-8859-1"
Content-Transfer-Encoding: quoted-printable

$contenttext

$boundary
Content-Type: text/html; charset="iso-8859-1"
Content-Transfer-Encoding: quoted-printable

<html>$contenthtml</html>
$boundary--
END

   if (sendmail(%mail)) {
      print $cgi->header();
      print "Your message was posted successfully. It will appear on the list within 20 minutes. Thank you.";
   } else {
      croak("Your message failed to post. Error output:\n\n$Mail::Sendmail::error");
   }


}

sub compose_form {
   my ($list, $msgid, $msgsubject, $contentsubject, $user, $passw, $content, $preview, $remainingtime) = @_;

   my $TEMPLATE = {
                    LIST => $list,
                    MSGID => $msgid,
                    MSGSUBJECT => $msgsubject,
                    CONTENTSUBJECT => $contentsubject,
                    USER => $user,
                    PASSW => $passw,
                    CONTENT => $content,
                    PREVIEW => $preview,
                    NEWTOPIC => $cgi->param('newtopic') || 0,
                    REMAININGTIME => $remainingtime,
                  };

   # write a cookie so this user doesn't have to login again
   my $cookie = '';
   unless (defined $cgi->cookie($list)) {
       $cookie = $cgi->cookie(
                              -name => $list,
                              -value => $passw.'_'.$user,
                              -expires => '+60m',
                             );
   }

   print httpheader($cookie);
   my $template = HTML::Template->new(filename => "post_compose.tmpl", loop_context_vars => 1, global_vars => 1);
   $template->param($TEMPLATE);
   print $template->output;
}

sub HHMMSS {
   my $secs = $_[0];
   my $hours = sprintf("%02d", int(int($secs / 60) / 60));
   my $minutes = sprintf("%02d", (($secs - int(($hours * 60) * 60)) / 60));
   my $seconds = sprintf("%02d", ($secs - (($hours * 60) * 60) - ($minutes * 60)));
   return "$hours:$minutes:$seconds";
}

sub httpheader {
   my ($cookie, $headertype) = @_;
   $headertype = 'text/html' unless defined $headertype and length $headertype;

   if (defined $cookie) {
      return $cgi->header(-type          => $headertype,
                          -cookie        => $cookie,
                          -expires       => '-1d',
                          -pragma        => 'no-cache',
                          -cache_control => 'no-cache');
   } else {
      return $cgi->header(-type          => $headertype,
                          -expires       => '-1d',
                          -pragma        => 'no-cache',
                          -cache_control => 'no-cache');
   }
}

sub content_to_HTML {
   my $content = $_[0];
   my $preview = '';

   # convert content to HTML, including BBCode
   my $parser = BBCode::Parser->new( follow_links => 1, css_direct_styles => 1, allow_image_bullets => 0 );
   my $tree = $parser->parse($content);
   $preview = $tree->toHTML;

   $preview =~ s#<br/>#<br>#g; # BBCode parser output cleanup

   # scrub the html for safety
   my $scrubber = HTML::Scrubber->new(
                                        allow => [ qw[ table tr td pre img a p b i u hr br ol ul li font span ] ],
                                        rules => [
                                                    table => {
                                                                border => 1,
                                                                cellpadding => 1,
                                                                cellspacing => 1,
                                                                width => 1,
                                                                height => 1,
                                                                bgcolor => 1,
                                                             },
                                                      pre => {
                                                               class => qr#^(?:code|quote)$#,
                                                               width => 1,
                                                               height => 1,
                                                             },
                                                       tr => {
                                                               class => 1,
                                                               width => 1,
                                                               height => 1,
                                                               bgcolor => 1,
                                                             },
                                                       td => {
                                                               class => 1,
                                                               width => 1,
                                                               height => 1,
                                                               bgcolor => 1,
                                                             },
                                                      img => {
                                                               src => qr{^(?!(?:java)?script)}i,
                                                               alt => 1,
                                                               title => 1,
                                                               width => 1,
                                                               height => 1,
                                                               border => 1,
                                                               class => 1,
                                                             },
                                                        a => {
                                                               href => qr{^(?!(?:java)?script)}i,
                                                               alt => 1,
                                                               title => 1,
                                                               class => 1,
                                                             },
                                                        p => {
                                                               class => 1,
                                                               width => 1,
                                                               height => 1,
                                                             },
                                                       hr => {
                                                               class => 1,
                                                               width => 1,
                                                               size => 1,
                                                             },
                                                     font => {
                                                               color => 1,
                                                               size => 1,
                                                               face => 1,
                                                             },
                                                     span => {
                                                               style => 1,
                                                             },
                                                  ]
                                       );
   $preview = $scrubber->scrub($preview);
   return $preview;
}

sub bad_server_connect {
   my $mess = $_[0];
   print $cgi->header();
   print "Can't connect to server: $mess";
   exit 0;
}

sub initialize_log {
  $ENV{'PATH'} = "/bin:/usr/bin:/usr/ucb";
  umask oct($::UMASK);
  # Change the log level to a higher number (500) for complete debugging
  $::log = new Mj::Log;
  $::log->add
    (
     method      => 'handle',
     id          => 'wwwusr',
     handle      => \*STDERR,
     level       => 20,
     subsystem   => 'mail',
     log_entries => 1,
     log_exits   => 1,
     log_args    => 1,
    );

  $::log->in(20, undef, "info", "owmlists post.pl - " . scalar(localtime) .  " from $ENV{'REMOTE_ADDR'}");
  $::log->startup_time();
}


