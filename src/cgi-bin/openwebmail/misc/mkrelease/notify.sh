#
# this is used by author to mail tarball to mirror
#
# translation maintainer email
ar=isam@planet.edu
bg=vess@slavof.net
ca=mikaku@fiwix.org
cs=milan.kerslager@pslib.cz
gb2312=wjun@mail.iap.ac.cn
big5=openwebmail@turtle.ee.ncku.edu.tw
da=
nl=openwebmail@forty-two.nl
fi=pasi.sjoholm@tieto-x.fi
fr=dominique.fournier@grenoble.cnrs.fr
de=martin@bronk.de
el=dimitris@michelinakis.gr
he=yehuda@whatsup.org.il
hr=igor@linuxfromscratch.org
hu=ful_s@fazekas.hu
id=liangs@kunchang.com.tw
it=marvi@menhir.biz
jp=james@ActionMessage.com
ko=psj@soosan.co.kr
lt=dvm382@takas.lt
no=are@valinor.dolphinics.no
pl=pjf@asn.pl
pt=jferra@sfconsultores.pt
ptbr=julio@cnm.org.br
ro=gabriel.hojda@gmail.com
ru=dzoleg@mail.ru
sr=alexa@yunord.net
sk=pese@us.svf.stuba.sk
sl=copatek@yahoo.com
es=javier@diff.com.ar
sv=tryfan@telia.com
th=joke@nakhon.net
tr=eguler@aegee.metu.edu.tr
uk=lvm@mystery.lviv.net
ur=umair@khi.wol.net.pk

# port/package/service maintainer email
cobalt=brian@nuonce.net
freebsd=leeym@leeym.com
openbsd=kevlo@openbsd.org
debian=srua@debian.org
webmin=Helmut.Grund@fh-furtwangen.de
ipspace=1073075441@cyruslesser.com


releasedate=`grep '^releasedate' /usr/local/www/cgi-bin/openwebmail/etc/defaults/openwebmail.conf | cut -f3`
version=`grep '^version.*[2-9]\.' /usr/local/www/cgi-bin/openwebmail/etc/defaults/openwebmail.conf | cut -f4`
currentmd5=`md5 -q /usr/local/www/data/openwebmail/download/current/openwebmail-current.tar.gz`
releasemd5=`md5 -q /usr/local/www/data/openwebmail/download/release/openwebmail-$version.tar.gz`

#################################################################

echo "send openwebmail-current.tar.gz to openwebmail.org? (y/N)"
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo sending to mirror sites...

  head -100 /usr/local/www/data/openwebmail/doc/changes.txt \
  | perl -e '$/="\n\n\n"; print $_=<>;' | \
  /usr/local/bin/mutt -s "openwebmail current $releasedate" \
  -a /usr/local/www/data/openwebmail/doc/changes.txt \
  -a /usr/local/www/data/openwebmail/download/current/openwebmail-current.tar.gz \
  openwebmail@turtle.ee.ncku.edu.tw \
  tchung@openwebmail.org
#  elitric@hotmail.com
fi

#################################################################

echo "send translation diff to translators? (y/N)"
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo "Dear translation maintainer,

We are happy to announce that we are going to release the next
version of openwebmail. And we would like to request for your
help to make the translation up to date.

The latest tarball is available at
http://turtle.ee.ncku.edu.tw/openwebmail/download/current/openwebmail-current.tar.gz

The latest changes is available at
http://turtle.ee.ncku.edu.tw/openwebmail/download/doc/changes.txt

The difference of language and templates between last release and the
latest current $releasedate is attached in this message.

Finally, thank you for your efforts in openwebmail.

Best Regards.

tung
" >/tmp/notify.tmp.$$

  q /tmp/notify.tmp.$$

  echo "Really send translation diff to translators? (y/N)"
  read ans
  if [ "$ans" = "y" -o "$ans" = "Y" ]; then
    echo sending to translators...

    cat /tmp/notify.tmp.$$| \
    /usr/local/bin/mutt -s "OWM $releasedate translation update request" \
    -a /usr/local/www/data/openwebmail/download/current/*-lang-templates.diff \
    $ar $bg $ca $cs $gb2312 $big5 $da $nl $fi $fr $de $el $he $hr $hu $id \
    $it $jp $ko $lt $no $pl $pt $ptbr $ro $ru $sr $sk $sl $es $sv $th $tr $uk $ur webmail
  fi
  rm /tmp/notify.tmp.$$
fi

#################################################################

echo "send release announcement to port maintainer? (y/N)"
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo "Dear sir,

The new release of Open WebMail is available now.
Since your are one of the package/port or service maintainer of openwebmail,
so we send you this message for notification.

The latest release is available at
http://openwebmail.org/openwebmail/download/release/openwebmail-$version.tar.gz
http://turtle.ee.ncku.edu.tw/openwebmail/download/release/openwebmail-$version.tar.gz

The MD5 is $releasemd5

And thanks for all your efforts in openwebmail.

Best Regards.

tung
" >/tmp/notify.tmp.$$

  q /tmp/notify.tmp.$$

  echo "Really send release announcement to port maintainer? (y/N)"
  read ans
  if [ "$ans" = "y" -o "$ans" = "Y" ]; then
    echo sending to pkg/port maintainer...
    cat /tmp/notify.tmp.$$| \
    /usr/local/bin/mutt -s "OWM new release announcement" \
    $cobalt $freebsd $openbsd $debian $webmin $ipspace
  fi
  rm /tmp/notify.tmp.$$
fi
