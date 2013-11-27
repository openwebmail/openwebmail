#!/usr/bin/perl

use strict;
use warnings;
$|++;

# RELEASE STEPS TO PREPARE CKEDITOR FOR DISTRIBUTION WITH OPENWEBMAIL

# get this ckeditor build number
open(FILE, "<LEGAL") or die "Cannot open file: LEGAL ($!)";
my $firstline = <FILE>;
close(FILE) or die "Cannot close file: LEGAL ($!)";

my ($build) = $firstline =~ m/^.*\s(\d+)\s.*$/;

print "Building CKEditor (rev$build)...\n";

# Roll Release (This destroys the SVN structure, so only use when you are ready!)
# run "java -jar _dev/releaser/ckreleaser/ckreleaser.jar -h" for help
system("java -jar _dev/releaser/ckreleaser/ckreleaser.jar _dev/releaser/openwebmail-ckreleaser.release . /home/alex/acatysmoof.com/services/webmail/openwebmail-current/ckeditor_build \"for OpenWebMail rev$build\" build_$build --verbose");

chdir('..') or die "Cannot change directory to: .. ($!)";

rename('ckeditor','ckeditor_svn')
  or die "Cannot rename directory: ckeditor -> ckeditor_svn ($!)";

rename('/home/alex/acatysmoof.com/services/webmail/openwebmail-current/ckeditor_build/release','ckeditor')
  or die "Cannot rename directory: /var/tmp/ckeditor_build/release -> ckeditor ($!)";

system('rm -rf ckeditor/_source ckeditor/ckeditor_basic.js ckeditor/openwebmail-*');
system('rm -rf /home/alex/acatysmoof.com/services/webmail/openwebmail-current/ckeditor_build');


