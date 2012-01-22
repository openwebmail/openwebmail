
#                              The BSD License
#
#  Copyright (c) 2009-2012, The OpenWebMail Project
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

# tool.pl - routines independent with openwebmail systems

package ow::tool;

use strict;
use warnings FATAL => 'all';

use Fcntl qw(:DEFAULT :flock);
use Digest::MD5 qw(md5);
use POSIX qw(:sys_wait_h); # for WNOHANG in waitpid()
use Carp;

$Carp::MaxArgNums = 0; # return all args in Carp output

use vars qw(%_bincache);
use vars qw(%_has_module_err);
use vars qw(%_sbincache);

sub findbin {
   return $_bincache{$_[0]} if (defined $_bincache{$_[0]});
   foreach my $p ('/usr/local/bin', '/usr/bin', '/bin', '/usr/X11R6/bin/', '/opt/bin') {
      return(untaint($_bincache{$_[0]}="$p/$_[0]")) if (-x "$p/$_[0]");
   }
   return ($_bincache{$_[0]}='');
}

sub findsbin {
   return $_sbincache{$_[0]} if (defined $_sbincache{$_[0]});
   foreach my $p ('/usr/local/sbin', '/usr/sbin', '/sbin', '/usr/X11R6/sbin/', '/opt/sbin') {
      return(untaint($_sbincache{$_[0]}="$p/$_[0]")) if (-x "$p/$_[0]");
   }
   return ($_sbincache{$_[0]}='');
}

sub find_configfile {
   my @configfiles = @_;

   # get cgi-bin/openwebmail path from @INC
   my $cgi_bin = defined $main::SCRIPT_DIR ? $main::SCRIPT_DIR : $INC[$#INC];

   foreach my $file (@configfiles) {
      # absolute path
      return $file if $file =~ m!^/! && -f $file;

      return "$cgi_bin/$file" if -f "$cgi_bin/$file";
   }

   return '';
}

sub loadmodule {
   # use 'require' to load the package ow::$file
   # then alias ow::$file::symbol to $newpkg::symbol
   # through Glob and 'tricky' symbolic reference feature
   my ($newpkg, $moduledir, $modulefile, @symlist) = @_;

   # remove / and .. for path safety
   $modulefile =~ s!/!!g;
   $modulefile =~ s!\.\.!!g;

   # this would be done only once because of %INC
   my $modulepath = ow::tool::untaint("$moduledir/$modulefile");
   require $modulepath;

   # . - is not allowed for package name
   my $modulepkg = 'ow::' . $modulefile;
   $modulepkg =~ s/\.pl//;
   $modulepkg =~ s/[\.\-]/_/g;

   # release strict refs until block end
   no strict 'refs';
   # use symbol table of package $modulepkg if no symbol passed in
   @symlist = keys %{$modulepkg . '::'} if scalar @symlist < 1;

   foreach my $sym (@symlist) {
      # alias symbol of sub routine into current package
      *{$newpkg . '::' . $sym} = *{$modulepkg . '::' . $sym};
   }

   return;
}

sub load_configfile {
   # open and parse an openwebmail style configuration
   # file into a hash of keys and values
   my ($configfile, $r_config) = @_;

   my $blockmode = 0;
   my ($key, $value) = ('','');

   sysopen(CONFIG, $configfile, O_RDONLY) or return(-1, $!);

   while (my $line = <CONFIG>) {
      chomp $line;
      $line =~ s/\s+$//;
      if ($blockmode) {
         if ($line =~ m#</$key>#) {
            $blockmode = 0;
            $r_config->{$key} = untaint($value);
         } else {
            $value .= "$line\n";
         }
      } else {
         $line =~ s/\s*#.*$//;
         $line =~ s/^\s+//;
         next if $line eq '';
         if ($line =~ m#^<\s*(\S+)\s*>$#) {
            $blockmode = 1;
            $key   = $1;
            $value = '';
         } elsif ($line =~ m#(\S+)\s+(.+)#) {
            $r_config->{$1} = untaint($2);
         }
      }
   }

   close(CONFIG);

   return(-2, "unclosed $key block") if $blockmode;

   return 0;
}

sub hostname {
   my $hostname = `/bin/hostname`;
   chomp($hostname);
   return($hostname) if $hostname =~ m/\./;

   my $domain = 'unknown';
   open(R, '/etc/resolv.conf');
   while (<R>) {
      chomp;
      if (/domain\s+\.?(.*)/i) {
        $domain = $1;
        last;
      }
   }
   close(R);
   return("$hostname.$domain");
}

sub clientip {
   my $clientip = '';

   if (exists $ENV{HTTP_CLIENT_IP} && defined $ENV{HTTP_CLIENT_IP}) {
      $clientip = $ENV{HTTP_CLIENT_IP};
   } elsif (
              exists $ENV{HTTP_X_FORWARDED_FOR}
              && defined $ENV{HTTP_X_FORWARDED_FOR}
              && $ENV{HTTP_X_FORWARDED_FOR} !~ m/^(?:10\.|172\.(?:1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.0\.)/
           ) {
      $clientip = (split(/,/,$ENV{HTTP_X_FORWARDED_FOR}))[0];
   } else {
      $clientip = exists $ENV{REMOTE_ADDR} && defined $ENV{REMOTE_ADDR}
                  ? $ENV{REMOTE_ADDR}
                  : '127.0.0.1';
   }

   return $clientip;
}

sub has_module {
   my $module = shift;
   return 1 if (defined $INC{$module});
   return 0 if ($_has_module_err{$module});

   eval {
           # test module existance and load if it exists
           no warnings 'all';
           local $SIG{'__DIE__'};
           require $module;
        };

   if ($@) {
      $_has_module_err{$module} = 1;
      return 0;
   } else {
      return 1;
   }
}

sub metainfo {
   # given the full path to a file, return a string describing the file modification time and size
   my $file = shift;
   return '' unless defined $file && -e $file;

   my @stats = stat($file);
   return("mtime=$stats[9] size=$stats[7]");
}

sub calc_checksum {
   my $r_string = shift;             # a scalar reference to a string to be MD5 checksummed
   my $checksum = md5(${$r_string}); # generate the unique checksum for this string
   $checksum =~ s/[\r\n]/./sg;       # remove any \n so it does not react with ow folder db index delimiter
   return $checksum;
}

sub unescapeURL {
   # escape & unescape routine are not available in CGI.pm 3.0
   # so we borrow the 2 routines from 2.xx version of CGI.pm
   my $todecode = shift;
   return undef if (!defined $todecode);
   $todecode =~ tr/+/ /;       # pluses become spaces
   $todecode =~ s/%([0-9a-fA-F]{2})/pack("C",hex($1))/ge;
   return $todecode;
}

sub escapeURL {
    my $toencode = shift;
    return undef if (!defined $toencode);
    $toencode=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
    return $toencode;
}

sub ucs4_to_utf8 {
   # convert UCS4 to UTF8:
   # string passed by with javascript escape() will encode CJK char to unicode
   # like %u5B78%u9577, this is used to turn %u.... back to the CJK char
   # eg: $str=~ s/%u([0-9a-fA-F]{4})/ucs4_to_utf8(hex($1))/ge;
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

sub hiddens {
   # generate html code for hidden options, faster than the one in CGI.pm
   # limitation: no escape for keyname, value can not be an array
   my %h=@_;
   my ($temphtml, $key);
   foreach my $key (sort keys %h) {
      $temphtml.=qq|<INPUT TYPE="hidden" NAME="$key" VALUE="$h{$key}">\n|;
   }
   return $temphtml;
}

sub zh_dospath2fname {
   # big5: hi 81-FE, lo 40-7E A1-FE, range a440-C67E C940-F9D5 F9D6-F9FE
   # gbk : hi 81-FE, lo 40-7E 80-FE, range hi*lo
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
   my $n = rand();
   $n =~ s/^0.0*//;
   $n = substr($n,0,8);
   my $fname = untaint("/tmp/.ow.$_[0].$$-$n");
   sysopen($fh, $fname, O_RDWR|O_CREAT|O_EXCL) || croak("Cannot open filehandle $fname ($!)");
   return($fh, $fname);
}

sub mktmpdir {
   my $n = rand();
   $n =~ s/^0.0*//;
   $n = substr($n,0,8);
   my $dirname = untaint("/tmp/.ow.$_[0].$$-$n");
   mkdir($dirname, 0700) || croak("Cannot make directory $dirname ($!)");
   return($dirname);
}

sub rotatefilename {
   # rename fname.ext   to fname.0.ext
   #        fname.0.ext to fname.1.ext
   #        .....
   #        fname.8.ext to fname.9.ext
   # so fname.ext won't be overwritten by uploaded file if duplicated name
   my ($base, $ext) = ($_[0], '');
   ($base,$ext) = ($1,$2) if ($_[0]=~/(.*)(\..*)/);
   my (%from, %to);
   $to{0}=1;
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
   my $ext = shift;

   return 'application/octet-stream' unless defined $ext;

   $ext =~ s/^.*\.//; # remove part before .
   $ext =~ lc $ext;

   return 'text/plain'                    if $ext =~ m/^(?:asc|te?xt|cc?|h|cpp|asm|pas|f77|lst|sh|pl)$/;
   return 'text/html'                     if $ext =~ m/^(?:html?)$/;
   return 'text/xml'                      if $ext =~ m/^(?:xml|xsl)$/;
   return 'text/richtext'                 if $ext =~ m/^(?:rtx)$/;
   return 'text/sgml'                     if $ext =~ m/^(?:sgml?)$/;
   return 'text/vnd.wap.wml'              if $ext =~ m/^(?:wml)$/;
   return 'text/vnd.wap.wmlscript'        if $ext =~ m/^(?:wmls)$/;
   return 'text/x-vcard'                  if $ext =~ m/^(?:vcf|vcard)$/;
   return "text/$1"                       if $ext =~ m/^(css|rtf)$/;

   return 'model/vrml'                    if $ext =~ m/^(?:wrl|vrml)$/;

   return 'image/jpeg'                    if $ext =~ m/^(?:jpe?g?)$/;
   return "image/$1"                      if $ext =~ m/^(bmp|gif|ief|png|psp)$/;
   return 'image/tiff'                    if $ext =~ m/^tiff?$/;
   return 'image/x-xbitmap'               if $ext =~ m/^xbm$/;
   return 'image/x-xpixmap'               if $ext =~ m/^xpm$/;
   return 'image/x-cmu-raster'            if $ext =~ m/^ras$/;
   return 'image/x-portable-anymap'       if $ext =~ m/^pnm$/;
   return 'image/x-portable-bitmap'       if $ext =~ m/^pbm$/;
   return 'image/x-portable-graymap'      if $ext =~ m/^pgm$/;
   return 'image/x-portable-pixmap'       if $ext =~ m/^ppm$/;
   return 'image/x-rgb'                   if $ext =~ m/^rgb$/;

   return 'video/mpeg'                    if $ext =~ m/^(?:mpeg?|mpg|mp2)$/;
   return 'video/x-msvideo'               if $ext =~ m/^(?:avi|dl|fli)$/;
   return 'video/quicktime'               if $ext =~ m/^(?:mov|qt)$/;

   return 'audio/x-wav'                   if $ext =~ m/^wav$/;
   return 'audio/mpeg'                    if $ext =~ m/^(?:mp[23]|mpga)$/;
   return 'audio/midi'                    if $ext =~ m/^(?:midi?|kar)$/;
   return 'audio/x-realaudio'             if $ext =~ m/^ra$/;
   return 'audio/basic'                   if $ext =~ m/^(?:au|snd|pcm)$/;
   return 'audio/x-mpegurl'               if $ext =~ m/^m3u$/;
   return 'audio/x-aiff'                  if $ext =~ m/^aif[fc]?$/;
   return 'audio/x-pn-realaudio'          if $ext =~ m/^ra?m$/;

   return 'application/msword'            if $ext =~ m/^doc$/;
   return 'application/x-mspowerpoint'    if $ext =~ m/^ppt$/;
   return 'application/x-msexcel'         if $ext =~ m/^xls$/;
   return 'application/x-msvisio'         if $ext =~ m/^visio$/;
   return 'application/postscript'        if $ext =~ m/^(?:ps|eps|ai)$/;
   return 'application/mac-binhex40'      if $ext =~ m/^hqx$/;
   return 'application/xhtml+xml'         if $ext =~ m/^(?:xhtml|xht)$/;
   return 'application/x-javascript'      if $ext =~ m/^js$/;
   return 'application/x-httpd-php'       if $ext =~ m/^php[34]?$/;
   return 'application/x-shockwave-flash' if $ext =~ m/^swf$/;
   return 'application/x-texinfo'         if $ext =~ m/^(?:texinfo|texi)$/;
   return 'application/x-troff'           if $ext =~ m/^(?:tr|roff)$/;
   return "application/x-troff-$1"        if $ext =~ m/^(man|me|ms)$/;
   return "application/x-$1"              if $ext =~ m/^(dvi|latex|shar|tar|tcl|tex)$/;
   return 'application/ms-tnef'           if $ext =~ m/^tnef$/;
   return "application/$1"                if $ext =~ m/^(pdf|zip|pgp|gpg)$/;
   return 'application/x-x509-user-cert'  if $ext =~ m/^(?:x509|pem|crt|p7b|p7c|p12)$/;

   return 'application/octet-stream';
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

sub email2nameaddr {
   # separates the email name from the email address.
   # always returns defined values, although name may be ''
   my ($name, $address) = _email2nameaddr(shift);

   if ($name eq '') {
      $name = $address;
      $name =~ s/\@.+$//;
      $name = $address if (length($name) <= 2);
   }

   return ($name, $address);
}

sub _email2nameaddr {
   # name may be coming in null
   my $email = shift;

   my $name    = '';
   my $address = '';

   if ($email =~ m/^\s*"?<?(.+?)>?"?\s*<(.*)>$/) {
      $name    = $1;
      $address = $2;
   } elsif ($email =~ m/<?(.+?\@.+?)>?\s+\((.+?)\)/) {
      $name    = $2;
      $address = $1;
   } elsif ($email =~ m/<(.+)>/) {
      $name    = '';
      $address = $1;
   } elsif ($email =~ m/(.+)/) {
      $name    = '';
      $address = $1;
   }

   $name =~ s/^\s+//;
   $name =~ s/\s+$//;
   $name =~ s#^['"](.+)['"]$#$1#; # eliminate enclosing quotes

   $address =~ s/^\s+//;
   $address =~ s/\s+$//;

   return ($name, $address);
}

sub str2list {
   # given a string of email addresses from user-generated to,cc,or bcc lines,
   # return an array of the individual addresses
   my $str = shift || '';

   my @list = ();

   $str =~ s/\n/, /gs;

   if ($str !~ m/[,;]/) {
      push(@list, $str);
      return @list;
   }

   # escape internal commas, semicolons, singlequotes, and doublequotes
   # for all the addresses contained in the string
   $str =~ s/(?:^|(?<=;|,|\s))('|")([^'"]*)\1/{
         $b = $1;
         $a = $2;
         $a =~ s',':#comma#:'g;
         $a =~ s';':#semic#:'g;
         $b eq "'" ? ":#squote#:$a:#squote#:" : ":#dquote#:$a:#dquote#:";
         }/ge;

   $str =~ s/(?:^|(?<=;|,|\s))\(([^\)]*)\)/{
         $a = $1;
         $a =~ s',':#comma#:'g;
         $a =~ s';':#semic#:'g;
         "($a)";
         }/ge;

   # split the string into individual addresses
   @list = grep { !m/^$/ }
            map {
                  s/^\s+//;
                  s/\s+$//;
                  s/:#comma#:/,/g;
                  s/:#semic#:/;/g;
                  s/:#squote#:/'/g;
                  s/:#dquote#:/"/g;
                  $_;
                }
           split(/[,;]/, $str);

   return @list;
}

sub untaint {
   local $_ = shift; # this line makes param into a new variable. do not remove it.
   local $1;         # fix perl $1 taintness propagation bug
   m/^(.*)$/s;
   return $1;
}

sub is_tainted {
   # this subroutine comes from the perlsec documentation
   return ! eval {
                    no warnings 'all';
                    local $SIG{'__DIE__'};
                    eval('#' . substr(join('', @_), 0, 0));
                    1;
                 };
}

sub is_regex {
   my $teststring = shift;
   return 0 unless defined $teststring && $teststring !~ m/^\s*$/;
   return eval {
                  no warnings 'all';
                  local $SIG{'__DIE__'};
                  my $is_valid = qr/$teststring/;
                  1;
               };
}

sub zombie_cleaner {
   #
   # Note: zombie_cleaner is called at the begin/end of each request
   #
   # OpenWebMail doesn't put zombie_cleaner() into $SIG{CHLD} because
   # 1. if $SIG{CHLD} is set some signal handler, even a very simple one,
   #    we got "recursive call...,out of memory!" in httpd error log occasionally
   # 2. if $SIG{CHLD} is set to 'IGNORE', we got warning in system log
   #    "application bug: perl5.8.3 has SIGCHLD set to SIG_IGN but calls wait()..."
   #
   while (waitpid(-1,WNOHANG) > 0) {}
}

sub stacktrace {
   my @error_messages = @_;
   my @stacktrace = grep { defined } Carp::longmess(join(' ', @error_messages));
   return (scalar @stacktrace > 0 ? @stacktrace : (''));
}

sub log_time {
   # for profiling and debugging
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
   my $today = sprintf("%4d%02d%02d", $year+1900, $mon+1, $mday);
   my $time  = sprintf("%02d%02d%02d", $hour, $min, $sec);

   open(Z, ">> /tmp/openwebmail.debug");

   # unbuffer mode
   select(Z);
   local $| = 1;
   select(STDOUT);

   print Z "$today $time ", join(' ',@_), "\n";	# @_ contains msgs to log
   close(Z);
   chmod(0666, "/tmp/openwebmail.debug");
}

sub dumpref {
   # dump data stru with its reference for debugging
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
