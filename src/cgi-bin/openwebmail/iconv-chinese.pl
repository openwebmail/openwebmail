#
# iconv-chinese.pl - charset coversion for big5<->gb
#                    adopted from Encode::HanConvert written by
#                    Autrijus Tang <autrijus@autrijus.org>
#
# Since chinese conversion in iconv() is incomplete, we use this instead
#
use strict;
use vars qw(%config);

sub mkdb_b2g {
   my $b2gdb="$config{'ow_etcdir'}/b2g$config{'dbmopen_ext'}";
   ($b2gdb =~ /^(.+)$/) && ($b2gdb = $1);	# untaint ...
   my %B2G;
   dbmopen (%B2G, $b2gdb, 0644) || return -1;
   open (T, "$config{'b2g_map'}");
   $_=<T>; $_=<T>;
   while (<T>) {
      /^(..)\s(..)/;
      $B2G{$1}=$2;
   }
   close(T);
   dbmclose(%B2G);
   return 0;
}

sub mkdb_g2b {
   my $g2bdb="$config{'ow_etcdir'}/g2b$config{'dbmopen_ext'}";
   ($g2bdb =~ /^(.+)$/) && ($g2bdb = $1);	# untaint ...
   my %G2B;
   dbmopen (%G2B, $g2bdb, 0644) || return -1;
   open (T, "$config{'g2b_map'}");
   $_=<T>; $_=<T>;
   while (<T>) {
      /^(..)\s(..)/;
      $G2B{$1}=$2;
   }
   close(T);
   dbmclose(%G2B);
   return 0;
}

# big5: hi 81-FE, lo 40-7E A1-FE, range a440-C67E C940-F9D5 F9D6-F9FE
sub b2g {
   my $str = $_[0];
   if ( -f "$config{'ow_etcdir'}/b2g$config{'dbm_ext'}" &&
       !-z "$config{'ow_etcdir'}/b2g$config{'dbm_ext'}" ) {
      my %B2G;
      dbmopen (%B2G, "$config{'ow_etcdir'}/b2g$config{'dbmopen_ext'}", undef);
      $str =~ s/([\x81-\xFE][\x40-\x7E\xA1-\xFE])/$B2G{$1}/eg;
      dbmclose(%B2G);
   }
   return $str;
}

# gb2312-1980: hi A1-F7, lo A1-FE, range hi*lo
# gb12345    : hi A1-F9, lo A1-FE, range hi*lo
# gbk        : hi 81-FE, lo 40-7E 80-FE, range hi*lo
# please refer http://www.haiyan.com/steelk/navigator/ref/gbindex1.htm for more detail
sub g2b {
   my $str = $_[0];
   if ( -f "$config{'ow_etcdir'}/g2b$config{'dbm_ext'}" &&
       !-z "$config{'ow_etcdir'}/g2b$config{'dbm_ext'}" ) {
      my %G2B;
      dbmopen (%G2B, "$config{'ow_etcdir'}/g2b$config{'dbmopen_ext'}", undef);
      $str =~ s/([\xA1-\xF9][\xA1-\xFE])/$G2B{$1}/eg;
      dbmclose(%G2B);
   }
   return $str;
}

1;
