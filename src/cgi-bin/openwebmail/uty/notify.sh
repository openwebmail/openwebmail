#
# this is used by author to mail tarball to mirror
#
date=`date "+%y%m%d"`

# translation maintainer email
ar=isam@planet.edu
bg=vess@vess.bnc.bg
ca=mikaku@fiwix.org
cs=milan.kerslager@pslib.cz
gb2312=wjun@mail.iap.ac.cn
big5=openwebmail@turtle.ee.ncku.edu.tw
da=
nl=openwebmail@forty-two.nl
fi=kari.paivarinta@viivatieto.fi
fr=admin@osmium-work.com
de=zander@datacontrol-online.de
el=dimitris@michelinakis.gr
he=yehuda@whatsup.org.il 
hu=ful_s@fazekas.hu
id=liangs@kunchang.com.tw
it=marvi@menhir.biz
jp=james@ActionMessage.com
kr=kmscom@snu.ac.kr
lt=dvm382@takas.lt
no=are@valinor.dolphinics.no
pl=pavcio@4lo.bytom.pl
pt=jferra@sfconsultores.pt
ptbr=julio@cnm.org.br
ro=zeno.popovici@ulbsibiu.ro
ru=duster@tpu.ru
sr=alexa@yunord.net
sk=lubos@klokner.sk
es=jsmaldone@yahoo.com
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


#################################################################

echo "send openwebmail-current.tgz to mirror sites? (y/N)"
read ans
if [ "$ans" = "y" -o "$ans" = "Y" ]; then
  echo sending to mirror sites...

  head -100 /usr/local/www/data/openwebmail/doc/changes.txt \
  | perl -e '$/="\n\n\n"; print $_=<>;' | \
  /usr/local/bin/mutt -s "openwebmail current $date" \
  -a /usr/local/www/data/openwebmail/doc/changes.txt \
  -a /usr/local/www/data/openwebmail/download/openwebmail-current.tgz \
  openwebmail@turtle.ee.ncku.edu.tw \
  tchung@openwebmail.com
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
http://turtle.ee.ncku.edu.tw/openwebmail/download/openwebmail-current.tgz
The latest changes is available at
http://turtle.ee.ncku.edu.tw/openwebmail/download/doc/changes.txt

The difference of language and templates between last release and the 
latest current $date is attached in this message.

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
    /usr/local/bin/mutt -s "OWM $date translation update request" \
    -a /usr/local/www/data/openwebmail/download/*-lang-templates.diff \
    $ar $bg $ca $cs $gb2312 $big5 $da $nl $fi $fr $de $el $he $hu $id \
    $it $jp $kr $lt $no $pl $pt $ptbr $ro $ru $sr $sk $es $sv $th $tr $uk $ur webmail
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
so I sent you this message for notification.

The latest release is available at
http://openwebmail.com/openwebmail/download/openwebmail-2.32.tgz
http://openwebmail.org/openwebmail/download/openwebmail-2.32.tgz
http://turtle.ee.ncku.edu.tw/openwebmail/download/openwebmail-2.32.tgz

The MD5 is xxxxxx

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
