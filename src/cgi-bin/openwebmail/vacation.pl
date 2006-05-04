#!/usr/bin/perl
#
# vacation.pl - vacation program
#
# Larry Wall <lwall.AT.jpl-devvax.jpl.nasa.gov>
# updates by Tom Christiansen <tchrist.AT.convex.com>
# updates by Chung-Kie Tung <tung.AT.turtle.ee.ncku.edu.tw>
# updates by Scott Mazur <scott.AT.littlefish.ca> - added -p path option
#

#
# syntax:
#
#   vacation.pl [ -I|-i ]
#      init vacation db
#
#   vacation.pl [ -j ] [ -a alias ] [-f ifile] [ -tN ] [-d] [-p homepath] username
#      used in ~/.forward file to auto-generate reply message
#
#    username     A message will be replied only if the username
#                 appears as an recipient in To: or Cc:
#
#    -j           Do not check whether the username appears as an
#                 recipient in the To: or the Cc: line.
#
#    -a alias     Indicate that alias is one of the valid names of the
#                 username, so the reply will be generated if the alias
#                 appears in To: or Cc:
#
#    -f ifile     Specify a file containing ignored users. Mails sent
#                 from the ignored users won't be auto-replied
#
#    -tN          Change the interval between repeat replies to  the
#                 same  sender.   The default is 1 week.  A trailing
#                 s, m, h, d, or w scales  N  to  seconds,  minutes,
#                 hours, days, or weeks respectively.
#
#    -p homepath  Specify a directory for the user home.
#                 (mostly for virtual user with no real unix home)
#
#    -d           log debug information to /tmp/vacation.debug
#
#   The options -a and -f can be specified for more than one times.
#
#
#   .forward file will contain a line of the form:
#
#      \username, "|/usr/local/bin/vacation.pl -t1d username"
#
#   .vacation.msg should include a header with at least Subject: line
#
#   For example:
#
#      Subject: I am on vacation
#
#      I am on vacation until July 22.
#      If you have something urgent,
#      please contact cilen (cilen@somehost).
#      --tung
#
#   If the string $SUBJECT appears in the .vacation.msg file, it
#   is  replaced  with  the subject of the original message when
#   the reply is sent; thus, a .vacation.msg file such as
#
#      Subject: I am on vacation
#
#      I am on vacation until July 22.
#      Your mail regarding "$SUBJECT" will be read when I return.
#      If you have something urgent,
#      please contact cilen (cilen@somehost).
#      --tung
#
#   will include the subject of the message in the reply.
#

use strict;
use Fcntl qw(:DEFAULT :flock);

foreach (qw(ENV BASH_ENV CDPATH IFS TERM)) {delete $ENV{$_}}; $ENV{PATH}='/bin:/usr/bin'; # secure ENV

my $myname = $0;
if ($myname !~ m!^/! || ! -x $myname) {
   print "Please execute vacation.pl with full path.\n";
   exit 1;
}

my $sendmail;
if ( -x '/usr/sbin/sendmail') {
   $sendmail='/usr/sbin/sendmail';
} elsif ( -x '/usr/lib/sendmail') {
   $sendmail='/usr/lib/sendmail';
} else {
   die "Sendmail binary not found";
}

my $usage = qq|Usage: vacation.pl -i\n|.
            qq|       vacation.pl [-j] [-a alias] [-tN] username\n|;

my $timeout = 7 * 24 * 60 * 60;      # unit: second, default 1 week

my %scale = (			# set-up time scale suffix ratios
         's', 1,
         'm', 60,
         'h', 60 * 60,
         'd', 24 * 60 * 60,
         'w', 7 * 24 * 60 * 60,
         );

my @ignores = (
           'daemon',
           'postmaster',
           'mailer-daemon',
           'mailer',
           'root',
           );
my @aliases = ();

my ($opt_i, $opt_d, $opt_j, $home_path)=(0,0,0,0);

########## MAIN ##################################################

if (defined $ENV{'GATEWAY_INTERFACE'}) {	# cgi mode
   my $clientip=clientip();
   my $info=$ENV{'HTTP_ACCEPT_LANGUAGE'}; $info.=', ' if ($info ne '');
   $info.=$ENV{'HTTP_USER_AGENT'}; $info=" ($info)" if ($info ne '');
   log_debug("$clientip$info is cracking the system by calling vacation.pl as CGI?");
   sleep 10;
   die "This program should not be called as CGI!\n";
}

# parse options, handle initialization or interactive mode
while (defined $ARGV[0] && $ARGV[0] =~ /^-/) {
   $_ = shift;
   if (/^-I/i) {  # eric allman's source has both cases
      $opt_i=1;
   } elsif (/^-d/) {      # log debug information to /tmp/vacation.debug
      $opt_d=1;
   } elsif (/^-j/) {      # don't check if user is a valid receiver
      $opt_j=1;
   } elsif (/^-f(.*)/) {   # read ignorelist from file
      push(@ignores, read_list_from_file($1 ? $1 : shift));
   } elsif (/^-a(.*)/) {   # specify alias name
      push(@aliases, $1 ? $1 : shift);
   } elsif (/^-t([\d.]*)([smhdw])/) {   # specify reply once interval
      $timeout = $1;
      $timeout *= $scale{$2} if $2;
   } elsif (/^-p(.*)/) {      # use an alternate home path
      $home_path=$1;
   } else {
      die $usage;
   }
}

if ($opt_i) {
   log_debug($0, "init mode with arg: ", @ARGV,
             "ruid=$<, euid=$>, rgid=$(, egid=$)" ) if ($opt_d);
   init_mode();
} elsif (@ARGV) {
   log_debug($0, "piped mode with arg: ", @ARGV,
             "ruid=$<, euid=$>, rgid=$(, egid=$)" ) if ($opt_d);
   push(@ignores, $ARGV[0]);
   push(@aliases, $ARGV[0]);
   pipe_mode($ARGV[0]);
} else {
   log_debug($0, "interactive mode(no arg)",
             "ruid=$<, euid=$>, rgid=$(, egid=$)") if ($opt_d);
   interactive_mode();
}
exit 0;


########## INIT MODE #############################################
sub init_mode {
   my $user = $ENV{'USER'} || $ENV{'LOGNAME'} || getlogin || (getpwuid($>))[0];
   my $uid=(getpwnam($user))[2];
   if ($uid != $>) {
      $<=$> if ($>==0);
      $>=$uid;
      log_debug("change to $user euid: ruid=$<, euid=$>") if ($opt_d);
   }
   my $home = $home_path || $ENV{'HOME'} || (getpwnam($user))[7] or die "No home directory for user $user\n";

   # guess real homedir if under automounter
   $home="/export$home" if ( -d "/export$home" );
   $home=untaint($home);

   chdir $home or die "Can't chdir to $home: $!\n";

   init_vacation_db();
}

sub init_vacation_db {
   my %VAC;
   unlink(".vacation", ".vacation.db", ".vacation.pag", ".vacation.dir");
   dbmopen(%VAC, ".vacation", 0600) or die "Can't open vacation dbm files: $!\n";
   %VAC=();
   dbmclose(%VAC);
}

########## INTERACTIVE MODE ######################################
sub interactive_mode {
   my $user = $ENV{'USER'} || $ENV{'LOGNAME'} || getlogin || (getpwuid($>))[0];
   my $uid=(getpwnam($user))[2];
   if ($uid != $>) {
      $<=$> if ($>==0);
      $>=$uid;
      log_debug("change to $user euid: ruid=$<, euid=$>") if ($opt_d);
   }
   my $home = $home_path || $ENV{'HOME'} || (getpwnam($user))[7] or die "No home directory for user $user\n";
   my $editor = $ENV{'VISUAL'} || $ENV{'EDITOR'} || 'vi';
   my $pager = 'more'; $pager=$ENV{'PAGER'} if (-f $ENV{'PAGER'});

   # guess real homedir if under automounter
   $home="/export$home" if ( -d "/export$home" );
   $home=untaint($home);
   chdir $home or die "Can't chdir to $home: $!\n";

   print qq|This program can be used to answer your mail automatically\n|,
         qq|when you go away on vacation.\n|;

   if (-f '.forward') {
      print "\nYou already have a $home/.forward file containing:\n",
            "------------------------------------------------------\n",
            `cat .forward`, "\n",
            "------------------------------------------------------\n";
      if (yorn("Would you like to remove it and disable the vacation feature? ")) {
         my (%VAC, @keys);
         unlink('.forward') or die "Can't unlink .forward: $!\n";
         if (dbmopen(%VAC, '.vacation', undef)) {
            if (@keys = sort { $VAC{$a} <=> $VAC{$b}; } keys %VAC) {
               require 'ctime.pl';
               print "While you were away, mail was sent to the following addresses:\n\n";
               open(PAGER, "|-") or do { exec(split(/\s+/, $pager)); exit 9 };
               foreach (@keys) {
                  my ($when) = unpack("L", $VAC{$_});
                  printf PAGER "%-20s %s", $_, ctime($when);
               }
               print PAGER "\n";
               close PAGER or die "$pager die unexpectedly: $!";;
            }
            dbmclose(%VAC);
         } else {
            unlink(".vacation", ".vacation.db", ".vacation.pag", ".vacation.dir");
         }
         print "Back to normal reception of mail.\n";
      } else {
         print "Ok, vacation feature NOT disabled.\n";
      }
      return;
   }

   if (-f '.vacation.msg') {
      print "\nYou already have a $home/.vacation.msg containing:\n",
            "------------------------------------------------------\n",
            `cat .vacation.msg`, "\n",
            "------------------------------------------------------\n";
      if ( yorn("Would you like to edit it? ") ) {
         system $editor, '.vacation.msg';
      }
   } else {
      create_default_vacation_msg();
      print qq|\n|,
            qq|I've created a default vacation message in ~/.vacation.msg.\n|,
            qq|This message will be automatically returned to anyone sending you mail\n|,
            qq|while you're out.\n|,
            qq|\n|,
            qq|Press return when ready to continue, and you will enter your favorite\n|,
            qq|editor ($editor) to edit the messasge to your own tastes.\n|;
      local $| = 1;
      print "Press return to continue: ";
      <STDIN>;
      system $editor, '.vacation.msg';
   }

   print qq|\nTo enable the vacation feature a ".forward" file will be created.\n|;
   if (yorn("Would you like to enable the vacation feature now? ")) {
      init_vacation_db();
      create_dot_forward($user, $myname) if (! -f ".forward");
      create_default_vacation_msg() if (! -f ".vacation.msg");
      print qq|\n|,
            qq|Ok, vacation feature ENABLED.\n|,
            qq|Please remember to turn it off when you get back from vacation.\n|,
            qq|Bon voyage!\n|;
   } else {
      print qq|Ok, vacation feature NOT enabled.\n|;
   }

   return;
}

sub create_dot_forward {
   my ($user, $vacation)=@_;
   open(FOR, ">.forward") or die "Can't create .forward: $!\n";
   print FOR qq!\\$user, "|$vacation $user"\n!;
   close FOR;
   return;
}

sub create_default_vacation_msg {
   open(MSG, ">.vacation.msg") or die "Can't create .vacation.msg: $!\n";
   print MSG qq|Subject: This is an autoreply...[Re: \$SUBJECT]\n|,
             qq|\n|,
             qq|I will not be reading my mail for a while.\n|,
             qq|Your mail regarding '\$SUBJECT' will be read when I return.\n|;
   close MSG;
   return;
}

sub yorn {
   my $answer;
   for (;;) {
      print $_[0]; $answer = <STDIN>;
      last if $answer =~ /^[yn]/i;
      print qq|Please answer "yes" or "no" ('y' or 'n')\n|;
   }
   return($answer =~ /^y/i);
}

########## PIPE MODE #############################################
sub pipe_mode {
   my $user = $_[0];
   my ($uid,$home) = (getpwnam($user))[2,7];
   if ($uid != $>) {
      $<=$> if ($>==0);
      $>=$uid;
      log_debug("change to $user euid: ruid=$<, euid=$>") if ($opt_d);
   }
   $home = $home_path if ($home_path);
   if (!$home) {
      log_debug("Error! No home directory for user $user\n") if ($opt_d);
      die "No home directory for user $user\n";
   }

   # guess real homedir if under automounter
   $home="/export$home" if ( -d "/export$home" );
   $home=untaint($home);
   if (! chdir $home) {
      log_debug("Error! Can't chdir to $home: $!\n") if ($opt_d);
      die "Can't chdir to $home: $!\n";
   }

   my ($header, $from, $subject, $to, $cc);

   $/ = ''; # paragraph mode, readin until blank line
   $header = <STDIN>;
   $header =~ s/\n\s+/ /g; # fix continuation lines
   $/ = "\n";

   ($from) = ($header =~ /^From\s+(\S+)/);   # that's the Unix-style From line
   if ($from eq "") {
      log_debug("Error! No 'From ' line!\n") if ($opt_d);
      die "No 'From ' line!\n";
   }

   if ($header =~ /^Precedence:\s*(bulk|junk)/im || $from =~ /-REQUEST@/i ) {
      log_debug("Junk mail, autoreply canceled\n") if ($opt_d);
      exit 0;
   }
   for (@ignores) {
      if ($from =~ /^$_$/i ) {
         log_debug("Message from ignored user $_, autoreply canceled\n") if ($opt_d);
         exit 0;
      }
   }

   ($subject) = ($header =~ /^Subject: +(.*)$/im);
   $subject = "(No subject)" unless $subject;
   $subject =~ s/\s+$//;
   $subject= decode_mimewords($subject);

   ($to) = ($header =~ /^To:\s+(.*)$/im);
   ($cc) = ($header =~ /^Cc:\s+(.*)$/im);
   $to .= ', '.$cc if $cc;

   if (!$opt_j) {
      my $found=0;
      foreach my $name (@aliases) {
         if ($to =~ /\b$name\b/i) {
            $found=1; $to=$name; last;
         }
      }
      if (!$found) {
         log_debug("User", @aliases, "not found in to: and cc:, autoreply canceled\n") if ($opt_d);
         exit 0;
      }
   }

   my (%VAC, $now, $lastdate);
   $now = time;
   if (!dbmopen(%VAC, ".vacation", 0600)) {
      unlink(".vacation", ".vacation.db", ".vacation.pag", ".vacation.dir");
      dbmopen(%VAC, ".vacation", 0600) or die "Can't open vacation dbm files: $!\n";
   }
   $lastdate = $VAC{$from};
   if ($lastdate ne '') {
      ($lastdate) = unpack("L",$lastdate);
      if ($lastdate) {
        if ($now < $lastdate + $timeout) {
           log_debug("Time too short from last reply, autoreply canceled\n") if ($opt_d);
           exit 0;
        }
      } else { # unpack failed, data format error!
        log_debug("Error! Invalid data format in .vacation dbm\n") if ($opt_d);
        exit 1;
      }
   }
   $VAC{$from} = pack("L", $now);
   dbmclose(%VAC);

   create_default_vacation_msg() if (! -f ".vacation.msg");
   my $msg;
   if (open(MSG,'.vacation.msg')) {
      local $/; undef $/; $msg = <MSG>;	# read whole file at once
      close MSG;
   }
   $msg=adjust_replymsg($msg, $from, $subject);

   open(MAIL, "|-") or
      do { open(STDERR, ">/dev/null"); exec($sendmail, "-oi", "-f $to", "$from"); exit 9 };
   print MAIL $msg;
   close MAIL or die "Sendmail died unexpectedly: $!\n";

   log_debug("Auto reply for message $subject is sent to $from\n") if ($opt_d);
}

sub read_list_from_file {
   my $file=$_[0];
   die "File $file doesn't exist!\n" if (! -f "$file");

   my @list=();
   if ( sysopen(FILE, $file, O_RDONLY) ) {
      while (<FILE>) {
         push(@list, split);
      }
      close(FILE);
   }
   return(@list);
}

# add proper header to .vacation.msg
# it assumes each header in .vacation.msg takes only 1 line
sub adjust_replymsg {
   my ($msg, $from, $subject)=@_;
   my ($header, $body)=("","");
   my ($has_subject, $has_to, $has_precedence)=(0,0,0);
   my $inheader=1;

   foreach (split(/\n/,$msg)) {
      if ($inheader==0) {
         $body.="$_\n";
         next;
      }
      if (/^Subject: /i) {
         $has_subject=1;
         $header.="$_\n";
      } elsif (/^X\-Spam\-Level\:\ \*\*\*\*\*\*/) {
         # don't reply to this spammy spam message
         log_debug("Abort message $subject due to X-Spam-Level header threshold exceeded.\n") if ($opt_d);
         exit 0; # exit success status
      } elsif (/^To: /i) {
         $has_to=1;
         $header.="$_\n";
      } elsif (/^Precedence: /i) {
         $has_precedence=1;
         $header.="$_\n";
      } elsif (/^[A-Za-z0-9\-]+: /i) {
         $header.="$_\n";
      } else {
         $inheader=0;
         $body.="$_\n";
      }
   }

   if (!$has_to) {
      $header=qq|To: $from\n|.$header;
   }
   if (!$has_subject) {
      $header=qq|Subject: This is an autoreply...[Re: $subject]\n|.$header;
   }
   if (!$has_precedence) {
      $header=$header.qq|Precedence: junk\n|;
   }

   if ($body=~/^\n/) {
      $msg=$header.$body;
   } else {
      $msg=$header."\n".$body;
   }

   # replace '$SUBJECT' token with real subject in original message
   $msg =~ s/\$SUBJECT/$subject/g;   # Sun's vacation does this
   return($msg);
}

########## MIME and DEBUG routines ###############################

# decode_mimewords, decode_base64 and _decode_q are blatantly snatched
# from parts of the MIME-Base64 Perl modules.
sub decode_mimewords {
    my $encstr = shift;
    my %params = @_;
    my @tokens;
    $@ = '';           ### error-return

    ### Collapse boundaries between adjacent encoded words:
    $encstr =~ s{(\?\=)\s*(\=\?)}{$1$2}gs;
    pos($encstr) = 0;
    ### print STDOUT "ENC = [", $encstr, "]\n";

    ### Decode:
    my ($charset, $encoding, $enc, $dec);
    while (1) {
	last if (pos($encstr) >= length($encstr));
	my $pos = pos($encstr);               ### save it

	### Case 1: are we looking at "=?..?..?="?
	if ($encstr =~    m{\G             # from where we left off..
			    =\?([^?]*)     # "=?" + charset +
			     \?([bq])      #  "?" + encoding +
			     \?([^?]+)     #  "?" + data maybe with spcs +
			     \?=           #  "?="
			    }xgi) {
	    ($charset, $encoding, $enc) = ($1, lc($2), $3);
	    $dec = (($encoding eq 'q') ? _decode_Q($enc) : _decode_B($enc));
	    push @tokens, [$dec, $charset];
	    next;
	}

	### Case 2: are we looking at a bad "=?..." prefix?
	### We need this to detect problems for case 3, which stops at "=?":
	pos($encstr) = $pos;               # reset the pointer.
	if ($encstr =~ m{\G=\?}xg) {
	    $@ .= qq|unterminated "=?..?..?=" in "$encstr" (pos $pos)\n|;
	    push @tokens, ['=?'];
	    next;
	}

	### Case 3: are we looking at ordinary text?
	pos($encstr) = $pos;               # reset the pointer.
	if ($encstr =~ m{\G                # from where we left off...
			 ([\x00-\xFF]*?    #   shortest possible string,
			  \n*)             #   followed by 0 or more NLs,
		         (?=(\Z|=\?))      # terminated by "=?" or EOS
			}xg) {
	    length($1) or die "mime: empty token";
	    push @tokens, [$1];
	    next;
	}

	### Case 4: bug!
	die "mime: unexpected case:\n($encstr) pos $pos";
    }
    return (wantarray ? @tokens : join('',map {$_->[0]} @tokens));
}

sub _decode_B {
   local($^W) = 0; # unpack("u",...) gives bogus warning in 5.00[123]

   my $str = shift;
   my $res = "";

   $str =~ tr|A-Za-z0-9+=/||cd;         # remove non-base64 chars
   $str =~ s/=+$//;                  # remove padding
   $str =~ tr|A-Za-z0-9+/| -_|;         # convert to uuencoded format
   while ($str =~ /(.{1,60})/gs) {
      my $len = chr(32 + length($1)*3/4); # compute length byte
      $res .= unpack("u", $len . $1 );   # uudecode
   }
   $res;
}

sub _decode_Q {
   my $str = shift;
   $str =~ s/=([\da-fA-F]{2})/pack("C", hex($1))/ge;  # RFC-1522, Q rule 1
   $str =~ s/_/\x20/g;                        # RFC-1522, Q rule 2
   $str;
}

sub clientip {
   my $clientip;
   if (defined $ENV{'HTTP_CLIENT_IP'}) {
      $clientip=$ENV{'HTTP_CLIENT_IP'};
   } elsif (defined $ENV{'HTTP_X_FORWARDED_FOR'} &&
            $ENV{'HTTP_X_FORWARDED_FOR'} !~ /^(?:10\.|172\.(?:1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.0\.)/ ) {
      $clientip=(split(/,/,$ENV{'HTTP_X_FORWARDED_FOR'}))[0];
   } else {
      $clientip=$ENV{'REMOTE_ADDR'}||"127.0.0.1";
   }
   return $clientip;
}

sub untaint {
   local $_ = shift;	# this line makes param into a new variable. don't remove it.
   local $1; 		# fix perl $1 taintness propagation bug
   m/^(.*)$/s;
   return $1;
}

sub log_debug {
   my @msg=@_;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
   my ($today, $time);

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime;
   $today=sprintf("%4d%02d%02d", $year+1900, $mon+1, $mday);
   $time=sprintf("%02d%02d%02d",$hour,$min, $sec);

   open(Z, ">> /tmp/vacation.debug");

   # unbuffer mode
   select(Z); local $| = 1;
   select(STDOUT);

   print Z "$today $time ", join(" ",@msg), "\n";
   close(Z);

   chmod(0666, "/tmp/vacation.debug");
}

