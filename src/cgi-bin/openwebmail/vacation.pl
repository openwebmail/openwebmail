#!/usr/bin/perl
#
# vacation program
#
# Larry Wall <lwall@jpl-devvax.jpl.nasa.gov>
#
# updates by Tom Christiansen <tchrist@convex.com>
# updates by Chung-Kie Tung <tung@turtle.ee.ncku.edu.tw>

# change below 3 lines to meet your configuration
$myname = '/usr/local/www/cgi-bin/openwebmail/vacation.pl';
$sendmail = '/usr/sbin/sendmail';
$defaulttimeout = 7 * 24 * 60 * 60;		# unit: second

# syntax:
#
#    vacation.pl [ -I|-i ]
#    	init vacation db
#
#    vacation.pl [ -j ] [ -a alias ] [ -tN ] username
#
#     -j        Do not check whether the recipient appears in  the
#               To:  or the Cc:  line.
#
#     -a alias  Indicate that alias is one of  the  valid  aliases
#               for  the  user  running  vacation,  so  that  mail
#               addressed to that alias generates a reply.
#
#     -tN       Change the interval between repeat replies to  the
#               same  sender.   The default is 1 week.  A trailing
#               s, m, h, d, or w scales  N  to  seconds,  minutes,
#               hours, days, or weeks respectively.
#
#    -j, -a or -t are options when vacation is used in .forward file         
#
#    .forward file will contain a line of the form:
#
#               \username, "|/usr/local/bin/vacation.pl -t1d username"  
#
#    .vacation.msg should include a header with at least Subject: line
#
#    For example:
#
#               Subject: I am on vacation
#
#               I am on vacation until July 22.  
#               If you have something urgent,
#               please contact cilen (cilen@somehost).
#               --tung
#
#    If the string $SUBJECT appears in the .vacation.msg file, it
#    is  replaced  with  the subject of the original message when
#    the reply is sent; thus, a .vacation.msg file such as
#
#               Subject: I am on vacation
#
#               I am on vacation until July 22.  
#               Your mail regarding "$SUBJECT" will be read when I return.
#               If you have something urgent,
#               please contact cilen (cilen@somehost).
#               --tung
#
#    will include the subject of the message in the reply. 

$vacation = $0;
$vacation = $myname unless $vacation =~ m#^/#;

$usage = qq|Usage: vacation.pl -i\n|.
         qq|       vacation.pl [-j] [-a alias] [-tN] username\n|;

$default_msg = qq|Subject: This is an autoreply...[Re: \$SUBJECT]\n|.
               qq|\n|.
               qq|I will not be reading my mail for a while.\n|.
               qq|Your mail regarding '\$SUBJECT' will be read when I return.\n|;

# set-up time scale suffix ratios
%scale = (
	's', 1,
	'm', 60,
	'h', 60 * 60,
	'd', 24 * 60 * 60,
	'w', 7 * 24 * 60 * 60,
	);

@ignores = ( 
	'daemon', 
	'postmaster', 
	'mailer-daemon', 
	'mailer',
	'root',
	);

@aliases = ();

$editor = $ENV{'VISUAL'} || $ENV{'EDITOR'} || 'vi';
$pager = $ENV{'PAGER'} || 'more';
$user = $ENV{'USER'} || $ENV{'LOGNAME'} || getlogin || (getpwuid($>))[0];
$home = $ENV{'HOME'} || (getpwnam($user))[7];
die "No home directory for user $user\n" unless $home;
($home =~ /^(.+)$/) && ($home = $1);  # untaint $home...
chdir $home || die "Can't chdir to $home: $!\n";

# parse options, handle initialization or interactive mode ##############
$opt_j=0;
while ($ARGV[0] =~ /^-/) {
    $_ = shift;
    if (/^-I/i) {  # eric allman's source has both cases
	&init_vacation_db;
	exit 0;
    } elsif (/^-j/) {			# don't check if user is a valid receiver
	$opt_j=1;
    } elsif (/^-f(.*)/) {		# read ignorelist from file
	push(@ignores, read_list_from_file($1 ? $1 : shift));
    } elsif (/^-a(.*)/) {		# specify alias name
	push(@aliases, $1 ? $1 : shift);
    } elsif (/^-t([\d.]*)([smhdw])/) {	# specify reply once interval
	$timeout = $1;
	$timeout *= $scale{$2} if $2;
    } else {
	die "Unrecognized switch: $_\n$usage";
    }
}

if (!@ARGV) {
    &interactive();
    exit 0;
}

# handle pipe mode, used in .forward ################################

$user = shift;
push(@ignores, $user);
push(@aliases, $user);
die $usage if $user eq '' || @ARGV;

$home = (getpwnam($user))[7];
die "No home directory for user $user\n" unless $home;
($home =~ /^(.+)$/) && ($home = $1);  # untaint $home...
chdir $home || die "Can't chdir to $home: $!\n";

$/ = '';			# paragraph mode, readin until blank line
$header = <>;
$header =~ s/\n\s+/ /g;		# fix continuation lines
$* = 1;
if ($header =~ /^Precedence:\s*(bulk|junk)/i ||
    $header =~ /^From.*-REQUEST@/i ) {
    exit 0;
}
for (@ignores) {
    exit 0 if $header =~ /^From.*\b$_\b/i;
} 


($from) = ($header =~ /^From\s+(\S+)/);	# that's the Unix-style From line
die "No \"From\" line!!!!\n" if $from eq "";

($subject) = ($header =~ /Subject: +(.*)/);
$subject = "(No subject)" unless $subject;
$subject =~ s/\s+$//;

($to) = ($header =~ /To:\s+(.*)/);
($cc) = ($header =~ /Cc:(\s+.*)/);
$to .= ', '.$cc if $cc;

if (!$opt_j) {
    my $found=0;
    foreach $name (@aliases) {
	if ($to =~ /\b$name\b/) {
            $found=1;last;
        }
    }
    exit 0 if(!$found);
}


$timeout = $defaulttimeout unless $timeout;

dbmopen(VAC, ".vacation", 0600) || die "Can't open vacation dbm files: $!\n";
$lastdate = $VAC{$from};
$now = time;
if ($lastdate ne '') {
    ($lastdate) = unpack("L",$lastdate);
    exit 1 unless $lastdate;	# unpack failed, data format error!
    exit 0 if $now < $lastdate + $timeout;
}
$VAC{$from} = pack("L", $now);
dbmclose(VAC);


if (open(MSG,'.vacation.msg')) {
    undef $/;
    $msg = <MSG>;
    close MSG;
} else {
    $msg = $default_msg;
} 

$msg=adjust_replymsg($msg, $from, $subject);

open(MAIL, "|$sendmail -oi -t $from") || die "Can't run sendmail: $!\n";
print MAIL $msg;
close MAIL;
exit 0;

# subs ###############################################################
sub yorn {
    local($answer);
    for (;;) {
	print $_[0];
	$answer = <STDIN>;
	last if $answer =~ /^[yn]/i;
	print "Please answer \"yes\" or \"no\" ('y' or 'n')\n";
    }
    $answer =~ /^y/i;
}

sub interactive {
    my $cwd;
    my @keys;

    print qq|This program can be used to answer your mail automatically\n|,
          qq|when you go away on vacation.\n|;

    if (-f '.forward') {
    	print "\nYou already have a $home/.forward file containing:\n",
              "------------------------------------------------------\n",
              `cat .forward`, "\n",
              "------------------------------------------------------\n";
    	if (&yorn("Would you like to remove it and disable the vacation feature? ")) {
    		unlink('.forward') || die "Can't unlink .forward: $!\n";
    		dbmopen(VAC, '.vacation', undef) || die "no .vacation dbmfile\n";
    		sub byvalue { $VAC{$a} <=> $VAC{$b}; }
    		if (@keys = sort byvalue keys %VAC) {
    		    require 'ctime.pl';
    		    print "While you were away, mail was sent to the following addresses:\n\n";
    		    open (PAGER, "|$pager") || die "can't open $pager: $!";
    		    foreach (@keys) {
    			my ($when) = unpack("L", $VAC{$_});
    			printf PAGER "%-20s %s", $key, &ctime($when);
    		    } 
    		    print PAGER "\n";
    		    close PAGER;
    		}
    	        dbmclose(VAC);
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
        &create_default_vacation_msg;
        print qq|\n|,
              qq|I've created a default vacation message in ~/.vacation.msg.\n|,
              qq|This message will be automatically returned to anyone sending you mail\n|,
              qq|while you're out.\n|,
              qq|\n|,
              qq|Press return when ready to continue, and you will enter your favorite\n|,
              qq|editor ($editor) to edit the messasge to your own tastes.\n|;

        $| = 1;
        print "Press return to continue: "; 
        <STDIN>;
        system $editor, '.vacation.msg';
    }

    print "\nTo enable the vacation feature a \".forward\" file will be created.\n";
    if (&yorn("Would you like to enable the vacation feature now? ")) {
	&init_vacation_db;
        if (! -f ".forward") {
            &create_dot_forward;
        }
        if (! -f ".vacation.msg") {
            &create_default_vacation_msg;
        }
	print qq|\n|,
              qq|Ok, vacation feature ENABLED.\n|,
              qq|Please remember to turn it off when you get back from vacation.\n|,
              qq|Bon voyage!\n|;
    } else {
	print qq|Ok, vacation feature NOT enabled.\n|;
    }

    return;
}

sub init_vacation_db {
    dbmopen(VAC, ".vacation", 0600) || die "Can't open vacation dbm files: $!\n";
    %VAC=();
    dbmclose(VAC);
} 

sub create_dot_forward {
    open(FOR, ">.forward") || die "Can't create .forward: $!\n";
    print FOR "\\$user, \"|$vacation $user\"\n";
    close FOR;
}

sub create_default_vacation_msg {
    open(MSG, ">.vacation.msg") || die "Can't create .vacation.msg: $!\n";
    print MSG $default_msg;
    close MSG;
} 

sub read_list_from_file {
    my $filename=$_[0];
    my @list=();
    if ( open (FILE, $filename) ) {
        while (<FILE>) {
    	    push(@list, split);
        } 
        close (FILE);
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
    $msg =~ s/\$SUBJECT/$subject/g;	# Sun's vacation does this
    return($msg);
}
