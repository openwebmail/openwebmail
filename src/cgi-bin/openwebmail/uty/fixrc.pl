#!/usr/bin/perl
#
#  fixrc.pl - fix .openwebmailrc files
#
# 2003-04-14   Scott A. Mazur, scott@littlefish.ca
#        
#  This script takes takes two arguments.  A search string and a replace string
#
#  The home directories defined in @homepaths and @virtualpaths are scanned
#  looking for a files which match the $rctarget value.
#
#  When a matching target file is found, the file is scanned and all occurances
#  of search string (1st argument) are replaced with the replace string (2nd argument).
#
#  The only difference between @homepaths and @virtualpaths is that paths defined
#  in @virtualpaths are searched one level deeper (as per virtual domain layout)
#
#  Comments, questions to scott@littlefish.ca
#

use strict;

my @homepaths = ( '/home', '/home/mailusers' );
my @virtualpaths = ('/home/virtual');

my $rctarget = '.openwebmail/openwebmailrc';

if ( @ARGV != 2 ) {
   print "Usage:  fixrc.pl   <searchstring>   <replacestring>\n";
   exit 1;
}

sub FIXRC { my ($file)=@_;
  if ( ! open( MYFILE, $file ) ) { print "failed to open file: $file $!\nScript aborted\n"; exit; }
  my @lines = <MYFILE>; close MYFILE;

  print "scanning $file";
  my $chg = 0;
  foreach( @lines ){
    if ( s/${ARGV[0]}/${ARGV[1]}/g ) { $chg=1 }
  }
  if ( $chg ) {
    print " --changed\n";
    if (! open FILE, ">$file"){ die "Can't open file: $file\nScript aborted\n"; }
    foreach( @lines ) { print FILE $_; } close FILE;
  } else { print "\n"; }
}

sub READDIR { my ($dir) = @_;
  if ( ! opendir( MYDIR, $dir ) ) { print "failed to read directory: $dir $!\nScript aborted\n"; exit;}
  my @files;
  while ( $_ = readdir(MYDIR) ) {
    if ( /^\.\.?$/ ) { next }
    push @files, "$dir/$_";
  }
  closedir MYDIR;
  return @files;
}

foreach ( @homepaths ) {
  foreach( READDIR($_) ) { if ( -f "$_/$rctarget" ) {FIXRC("$_/$rctarget");} }
}
foreach ( @virtualpaths ) {
  foreach ( READDIR($_) ) { foreach( READDIR($_) ){ if ( -f "$_/$rctarget" ) {FIXRC("$_/$rctarget");} } }
}

print "\ndone\n";
exit;
