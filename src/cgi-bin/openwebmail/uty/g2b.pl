#!/usr/bin/perl
#
# script to convert chinese gb2312 to big5
#
my (%config, $content);
$config{'ow_etcdir'}="/usr/local/www/cgi-bin/openwebmail/etc";
$config{'dbm_ext'}=".db";
$config{'dbmopen_ext'}="";

while (<>) {
   $content.=$_;
}
print g2b($content);

# generic routines ##################################################################
sub g2b {
   my $str = $_[0];

   if ( -f "$config{'ow_etcdir'}/g2b$config{'dbm_ext'}") {
      my %G2B;
      dbmopen(%G2B, "$config{'ow_etcdir'}/g2b$config{'dbmopen_ext'}", undef);
      $str =~ s/([\xA1-\xF9][\xA1-\xFE])/$G2B{$1}/eg;
      dbmclose(%G2B);
   }
   return $str;
}
