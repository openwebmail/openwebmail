package ow::tool;
#
# tool.pl - routines independent with openwebmail systems
#

use strict;
use Fcntl qw(:DEFAULT :flock);
use Digest::MD5 qw(md5);
use POSIX qw(:sys_wait_h);	# for WNOHANG in waitpid()
use Carp;
$Carp::MaxArgNums = 0; # return all args in Carp output

use vars qw(%_bincache);
sub findbin {
   return $_bincache{$_[0]} if (defined $_bincache{$_[0]});
   foreach my $p ('/usr/local/bin', '/usr/bin', '/bin', '/usr/X11R6/bin/', '/opt/bin') {
      return(untaint($_bincache{$_[0]}="$p/$_[0]")) if (-x "$p/$_[0]");
   }
   return ($_bincache{$_[0]}='');
}

use vars qw(%_sbincache);
sub findsbin {
   return $_sbincache{$_[0]} if (defined $_sbincache{$_[0]});
   foreach my $p ('/usr/local/sbin', '/usr/sbin', '/sbin', '/usr/X11R6/sbin/', '/opt/sbin') {
      return(untaint($_sbincache{$_[0]}="$p/$_[0]")) if (-x "$p/$_[0]");
   }
   return ($_sbincache{$_[0]}='');
}

sub find_configfile {
   my @configfiles=@_;
   my $cgi_bin = $INC[$#INC];		# get cgi-bin/openwebmail path from @INC
   foreach (@configfiles) {
      if (m!^/!) {			# absolute path
         return($_) if (-f $_);
      } else {
         return("$cgi_bin/$_") if (-f "$cgi_bin/$_");
      }
   }
   return ('');
}

sub load_configfile {
   my ($configfile, $r_config)=@_;

   sysopen(CONFIG, $configfile, O_RDONLY) or return(-1, $!);

   my ($line, $key, $value, $blockmode);
   $blockmode=0;
   while (($line=<CONFIG>)) {
      chomp $line;
      $line=~s/\s+$//;
      if ($blockmode) {
         if ( $line =~ m!</$key>! ) {
            $blockmode=0;
            ${$r_config}{$key}=untaint($value);
         } else {
            $value .= "$line\n";
         }
      } else {
         $line=~s/\s*#.*$//;
         $line=~s/^\s+//;
         next if ($line eq '');
         if ( $line =~ m!^<\s*(\S+)\s*>$! ) {
            $blockmode=1;
            $key=$1; $value='';
         } elsif ( $line =~ m!(\S+)\s+(.+)! ) {
            ${$r_config}{$1}=untaint($2);
         }
      }
   }
   close(CONFIG);
   if ($blockmode) {
      return(-2, "unclosed $key block");
   }

   return 0;
}

# use 'require' to load the package ow::$file
# then alias ow::$file::symbol to $newpkg::symbol
# through Glob and 'tricky' symbolic reference feature
sub loadmodule {
   my ($newpkg, $moduledir, $modulefile, @symlist)=@_;
   $modulefile=~s|/||g; $modulefile=~s|\.\.||g; # remove / and .. for path safety

   # this would be done only once because of %INC
   my $modulepath=ow::tool::untaint("$moduledir/$modulefile");
   require $modulepath;

   # . - is not allowed for package name
   my $modulepkg='ow::'.$modulefile;
   $modulepkg=~s/\.pl//;
   $modulepkg=~s/[\.\-]/_/g;

   # release strict refs until block end
   no strict 'refs';
   # use symbol table of package $modulepkg if no symbol passed in
   @symlist=keys %{$modulepkg.'::'} if ($#symlist<0);

   foreach my $sym (@symlist) {
      # alias symbol of sub routine into current package
      *{$newpkg.'::'.$sym}=*{$modulepkg.'::'.$sym};
   }

   return;
}

sub hostname {
   my $hostname=`/bin/hostname`; chomp ($hostname);
   return($hostname) if ($hostname=~/\./);

   my $domain="unknown";
   open(R, "/etc/resolv.conf");
   while (<R>) {
      chomp;
      if (/domain\s+\.?(.*)/i) {$domain=$1;last;}
   }
   close(R);
   return("$hostname.$domain");
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

use vars qw(%_has_module_err);
sub has_module {
   my $module=$_[0];
   return 1 if (defined $INC{$module});
   return 0 if ($_has_module_err{$module});
   eval { require $module; };	# test module existance and load if it exists
   if ($@) {
      $_has_module_err{$module}=1; return 0;
   } else {
      return 1;
   }
}

# return a string composed by the modify time & size of a file
sub metainfo {
   return '' if (!-e $_[0]);
   # dev, ino, mode, nlink, uid, gid, rdev, size, atime, mtime, ctime, blksize, blocks
   my @a=stat($_[0]);
   return("mtime=$a[9] size=$a[7]");
}

# generate a unique (well nearly) checksum through MD5
sub calc_checksum {
   my $checksum = md5(${$_[0]});
   # remove any \n so it doesn't react with ow folder db index delimiter
   $checksum =~ s/[\r\n]/./sg;
   return $checksum;
}

# escape & unescape routine are not available in CGI.pm 3.0
# so we borrow the 2 routines from 2.xx version of CGI.pm
sub unescapeURL {
    my $todecode = shift;
    return undef if (!defined $todecode);
    $todecode =~ tr/+/ /;       # pluses become spaces
    $todecode =~ s/%([0-9a-fA-F]{2})/pack("c",hex($1))/ge;
    return $todecode;
}

sub escapeURL {
    my $toencode = shift;
    return undef if (!defined $toencode);
    $toencode=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
    return $toencode;
}

# convert UCS4 to UTF8:
# string passed by with javascript escape() will encode CJK char to unicode
# like %u5B78%u9577, this is used to turn %u.... back to the CJK char
# eg: $str=~ s/%u([0-9a-fA-F]{4})/ucs4_to_utf8(hex($1))/ge;
sub ucs4_to_utf8 {
   my ($val)=@_;
   my $c;
   if ($val < 0x7f){		#0000-007f
      $c .= chr($val);
   } elsif ($val < 0x800) {	#0080-0800
      $c .= chr(0xC0 | ($val / 64));
      $c .= chr(0x80 | ($val % 64));
   } else {			#0800-ffff
      $c .= chr(0xe0 | (($val / 64) / 64));
      $c .= chr(0x80 | (($val / 64) % 64));
      $c .= chr(0x80 | ($val % 64));
   }
}

# generate html code for hidden options, faster than the one in CGI.pm
# limitation: no escape for keyname, value can not be an array
sub hiddens {
   my %h=@_;
   my ($temphtml, $key);
   foreach my $key (sort keys %h) {
      $temphtml.=qq|<INPUT TYPE="hidden" NAME="$key" VALUE="$h{$key}">\n|;
   }
   return $temphtml;
}

# big5: hi 81-FE, lo 40-7E A1-FE, range a440-C67E C940-F9D5 F9D6-F9FE
# gbk : hi 81-FE, lo 40-7E 80-FE, range hi*lo
sub zh_dospath2fname {
   my ($dospath, $newdelim)=@_;
   my $buff='';
   while ( 1 ) {
      # this line can't be put inside while or will go wrong in perl 5.8.0
      if ($dospath=~m!([\x81-\xFE][\x40-\x7E\x80-\xFE]|.)!g) {
         if ($1 eq '\\') {
            if ($newdelim ne '') {
               $buff.=$newdelim;
            } else {
               $buff='';
            }
         } else {
            $buff.=$1;
         }
      } else {
         last;
      }
   }
   return $buff;
}

sub mktmpfile {
   my $fh= do { local *FH };
   for (1..5) {
      my $n=rand(); $n=~s/^0.0*//; $n=substr($n,0,8);
      my $fname=untaint("/tmp/.ow.$_[0].$$-$n");
      return($fh, $fname) if (sysopen($fh, $fname, O_RDWR|O_CREAT|O_EXCL));
   }
   return;
}

sub mktmpdir {
   for (1..5) {
      my $n=rand(); $n=~s/^0.0*//; $n=substr($n,0,8);
      my $dirname=untaint("/tmp/.ow.$_[0].$$-$n");
      return($dirname) if (mkdir($dirname, 0700));
   }
   return;
}

# rename fname.ext   to fname.0.ext
#        fname.0.ext to fname.1.ext
#        .....
#        fname.8.ext to fname.9.ext
# so fname.ext won't be overwritten by uploaded file if duplicated name
sub rotatefilename {
   my ($base, $ext)=($_[0], ''); ($base,$ext)=($1,$2) if ($_[0]=~/(.*)(\..*)/);
   my (%from, %to); $to{0}=1;
   for my $i (0..9) {
      $from{$i}=1 if (-f "$base.$i$ext");
      $to{$i+1}=1 if ($to{$i} && $from{$i});
   }
   for (my $i=9; $i>=0; $i--) {
      if ($from{$i} && $to{$i+1}) {
         rename(ow::tool::untaint("$base.$i$ext"), ow::tool::untaint("$base.".($i+1).$ext));
      }
   }
   rename(ow::tool::untaint("$base$ext"), ow::tool::untaint("$base.0$ext"));
}

sub ext2contenttype {
   my $ext=lc($_[0]); $ext=~s/^.*\.//;	# remove part before .

   return("text/plain")			if ($ext =~ /^(?:asc|te?xt|cc?|h|cpp|asm|pas|f77|lst|sh|pl)$/);
   return("text/html")			if ($ext =~ /^html?$/);
   return("text/xml")			if ($ext =~ /^(?:xml|xsl)$/);
   return("text/richtext")		if ($ext eq "rtx");
   return("text/sgml")			if ($ext =~ /^sgml?$/);
   return("text/vnd.wap.wml")		if ($ext eq "wml");
   return("text/vnd.wap.wmlscript")	if ($ext eq "wmls");
   return("text/x-vcard")		if ($ext =~ /^(?:vcf|vcard)$/);
   return("text/$1")			if ($ext =~ /^(?:css|rtf)$/);

   return("model/vrml")			if ($ext =~ /^(?:wrl|vrml)$/);

   return("image/jpeg")			if ($ext =~ /^(?:jpe?g?)$/);
   return("image/$1")			if ($ext =~ /^(bmp|gif|ief|png|psp)$/);
   return("image/tiff")			if ($ext =~ /^tiff?$/);
   return("image/x-xbitmap")		if ($ext eq "xbm");
   return("image/x-xpixmap")		if ($ext eq "xpm");
   return("image/x-cmu-raster")		if ($ext eq "ras");
   return("image/x-portable-anymap")	if ($ext eq "pnm");
   return("image/x-portable-bitmap")	if ($ext eq "pbm");
   return("image/x-portable-grayma")	if ($ext eq "pgm");
   return("image/x-portable-pixmap")	if ($ext eq "ppm");
   return("image/x-rgb")		if ($ext eq "rgb");

   return("video/mpeg")			if ($ext =~ /^(?:mpeg?|mpg|mp2)$/);
   return("video/x-msvideo")		if ($ext =~ /^(?:avi|dl|fli)$/);
   return("video/quicktime")		if ($ext =~ /^(?:mov|qt)$/);

   return("audio/x-wav")		if ($ext eq "wav");
   return("audio/mpeg")			if ($ext =~ /^(?:mp[23]|mpga)$/);
   return("audio/midi")			if ($ext =~ /^(?:midi?|kar)$/);
   return("audio/x-realaudio")		if ($ext eq "ra");
   return("audio/basic")		if ($ext =~ /^(?:au|snd|pcm)$/);
   return("audio/x-mpegurl")		if ($ext eq "m3u");
   return("audio/x-aiff")		if ($ext =~ /^aif[fc]?$/);
   return("audio/x-pn-realaudio")	if ($ext =~ /^ra?m$/);

   return("application/msword") 	if ($ext eq "doc");
   return("application/x-mspowerpoint") if ($ext eq "ppt");
   return("application/x-msexcel") 	if ($ext eq "xls");
   return("application/x-msvisio")	if ($ext eq "visio");

   return("application/postscript")	if ($ext =~ /^(?:ps|eps|ai)$/);
   return("application/mac-binhex40")	if ($ext eq "hqx");
   return("application/xhtml+xml")	if ($ext =~ /^(?:xhtml|xht)$/);
   return("application/x-javascript")	if ($ext eq "js");
   return("application/x-httpd-php")	if ($ext =~ /^php[34]?$/);
   return("application/x-shockwave-flash") if ($ext eq "swf");
   return("application/x-texinfo")	if ($ext =~ /^(?:texinfo|texi)$/);
   return("application/x-troff")	if ($ext =~ /^(?:tr|roff)$/);
   return("application/x-troff-$1")     if ($ext =~ /^(man|me|ms)$/);
   return("application/x-$1")		if ($ext =~ /^(dvi|latex|shar|tar|tcl|tex)$/);
   return("application/ms-tnef")        if ($ext =~ /^tnef$/);
   return("application/$1")		if ($ext =~ /^(pdf|zip|pgp|gpg)$/);

   return("application/x-x509-user-cert")	if ($ext =~ /^(?:x509)$/);

   return("application/octet-stream");
}

sub contenttype2ext {
   my $contenttype=$_[0];

   return("txt")  if ($contenttype eq "N/A");
   return("au")   if ($contenttype =~ m!audio/x\-sun!i);
   return("mp3")  if ($contenttype =~ m!audio/mpeg!i);
   return("vcf")  if ($contenttype =~ m!(?:text|application)/x?\-?vcard!i);
   return("x509") if ($contenttype =~ m!application/x?\-?x509-(?:ca|user)-cert!i);

   my ($class, $ext, $dummy)=split(/[\/\s;,]+/, $contenttype);

   $ext=~s/^x-//i;
   return(lc($ext))  if length($ext) <=4;

   return("txt")  if ($class =~ /text/i);
   return("msg")  if ($class =~ /message/i);

   # image/????
   return("jpg")  if ($ext =~ /p?jpe?g/i);

   # audio/????
   return("au")   if ($ext =~ /basic/i);
   return("ra")   if ($ext =~ /realaudio/i);

   return("doc")  if ($ext =~ /msword/i);
   return("ppt")  if ($ext =~ /powerpoint/i);
   return("xls")  if ($ext =~ /excel/i);
   return("vsd")  if ($ext =~ /visio/i);
   return("tar")  if ($ext =~ /tar/i);
   return("zip")  if ($ext =~ /zip/i);
   return("avi")  if ($ext =~ /msvideo/i);
   return("mov")  if ($ext =~ /quicktime/i);
   return("swf")  if ($ext =~ /shockwave\-flash/i);
   return("hqx")  if ($ext =~ /mac\-binhex40/i);
   return("ps")   if ($ext =~ /postscript/i);
   return("js")   if ($ext =~ /javascript/i);
   return("tnef") if ($ext =~ /ms\-tnef/i);
   return("bin");
}

sub email2nameaddr {	# name, addr are guarentee to not null
   my ($name, $address)=_email2nameaddr($_[0]);
   if ($name eq "") {
      $name=$address; $name=~s/\@.*$//;
      $name=$address if (length($name)<=2);
   }
   return($name, $address);
}

sub _email2nameaddr {	# name may be null
   my $email=$_[0];
   my ($name, $address);

   if ($email=~/^\s*"?<?(.+?)>?"?\s*<(.*)>$/) {
      $name = $1; $address = $2;
   } elsif ($email=~/<?(.*?@.*?)>?\s+\((.+?)\)/) {
      $name = $2; $address = $1;
   } elsif ($email=~/<(.+)>/) {
      $name = ""; $address = $1;
   } elsif ($email=~/(.+)/) {
      $name = "" ; $address = $1;
   }
   $name=~s/^\s+//; $name=~s/\s+$//;
   $address=~s/^\s+//; $address=~s/\s+$//;
   return($name, $address);
}

sub str2list {
   my ($str, $keepnull)=@_;
   my (@list, @tmp, $delimiter, $prevchar, $postchar);

   if ($str=~/,/) {
      @tmp=split(/,/, $str);
      $delimiter=',';
   } elsif ($str=~/;/) {
      @tmp=split(/;/, $str);
      $delimiter=';';
   } else {
      return($str);
   }

   my $pairmode=0;
   foreach my $token (@tmp) {
      next if ($token=~/^\s*$/ && !$keepnull);
      if ($pairmode) {
         push(@list, pop(@list).$delimiter.$token);
         $pairmode=0 if ($token=~/\Q$postchar\E/ && $token!~/\Q$prevchar\E.*\Q$postchar\E/);
      } else {
         push(@list, $token);
         if ($token=~/^.*?(['"\(])/) {
            $prevchar=$postchar=$1;
            $postchar=')' if ($prevchar eq '(' );
            $pairmode=1 if ($token!~/\Q$prevchar\E.*\Q$postchar\E/);
         }
      }
   }

   foreach (@list) {
      s/^\s+//; s/\s+$//;
   }
   return(@list);
}

sub untaint {
   local $_ = shift;	# this line makes param into a new variable. don't remove it.
   local $1; 		# fix perl $1 taintness propagation bug
   m/^(.*)$/s;
   return $1;
}

sub is_tainted {
   return ! eval { join('',@_), kill 0; 1; };
}

sub is_regex {
   return eval { m!$_[0]!; 1; };
}

sub zombie_cleaner {
   while (waitpid(-1,WNOHANG)>0) {}
}
#
# Note: zombie_cleaner is called at the begin/end of each request
#
# Openwebmail doesn't put zombie_cleaner() into $SIG{CHLD} because
# 1. if $SIG{CHLD} is set some signal handler, even a very simple one,
#    we got "recursive call...,out of memory!" in httpd error log occasionally
# 2. if $SIG{CHLD} is set to 'IGNORE', we got warning in system log
#    "application bug: perl5.8.3 has SIGCHLD set to SIG_IGN but calls wait()..."
#

sub stacktrace {
   return Carp::longmess(join(' ', @_));
}

# for profiling and debugging
sub log_time {
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
   my ($today, $time);

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =localtime;
   $today=sprintf("%4d%02d%02d", $year+1900, $mon+1, $mday);
   $time=sprintf("%02d%02d%02d",$hour,$min, $sec);

   open(Z, ">> /tmp/openwebmail.debug");

   # unbuffer mode
   select(Z); local $| = 1;
   select(STDOUT);

   print Z "$today $time ", join(" ",@_), "\n";	# @_ contains msgs to log
   close(Z);
   chmod(0666, "/tmp/openwebmail.debug");
}

# dump data stru with its reference for debugging
sub dumpref {
   my ($var, $c)=@_;
   return("too many levels") if ($c>128);
   my $type=ref($var);
   my $prefix=' 'x$c;
   my $output="$type\n";
   if ($type =~/SCALAR/) {
      $output.=$prefix.dumpref(${$var}, $c)."\n";
   } elsif ($type=~/HASH/) {
      foreach my $key (sort keys %{$var}) {
         $output.=$prefix." "."$key =>".dumpref(${$var}{$key}, length("$key =>")+$c+1)."\n";
      }
   } elsif ($type=~/ARRAY/) {
      foreach my $member (@{$var}) {
         $output.=$prefix." ".dumpref($member, $c+1)."\n";
      }
   } else {
      return("$var (untaint)") if (!is_tainted($_[0]));
      return($var);
   }
   $output=~s/\n\n+/\n/sg;
   return $output;
}

1;
