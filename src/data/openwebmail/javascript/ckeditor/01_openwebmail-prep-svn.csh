#!/bin/tcsh

# STEPS TO PREPARE CKEDITOR SVN TO BE PUT INTO OPENWEBMAIL SVN
cd /home/alex/acatysmoof.com/services/webmail/openwebmail-svn/trunk/src/data/openwebmail/javascript

# pull down the full current SVN
svn export http://svn.ckeditor.com/CKEditor/trunk ckeditor_current

set BUILD = `svn info http://svn.ckeditor.com/CKEditor/trunk --revision HEAD | grep 'Revision: ' | awk '{print $2}'`

cd ckeditor_current

# remove stuff we know we do not want
rm -f .htaccess ckeditor.asp ckeditor.php ckeditor_php{4,5}.php CHANGES.html INSTALL.html ckeditor_basic_source.js ckeditor_basic.js ckeditor_source.js ckeditor.pack
rm -rf _samples _source/adapters _source/plugins/{adobeair,filebrowser,flash,newpage,pastefromword,print,preview,save,scayt,smiley,templates,wsc} _dev/{_thirdparty,docs_build,dtd_test,fixlineends,jslint,langtool} _source/skins/{office2003,v2}
rm _dev/packager/package* _dev/packager/ckpackager/ckpackager.exe _dev/releaser/lang* _dev/releaser/{release.bat,release.sh,ckreleaser.release} _dev/releaser/ckreleaser/ckreleaser.exe

# Add our license choice file
echo "This is a modified version of CKEditor SVN rev $BUILD and is distributed with OpenWebMail under the MPL license" >> LEGAL

echo "You can manually copy ckeditor_current over ckeditor with"
echo "cd ckeditor_current ; tar -cf - * | ( cd ../ckeditor ; tar -xvf - )"


