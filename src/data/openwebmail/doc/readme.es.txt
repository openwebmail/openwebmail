Este archivo es una traducción al español del original (readme.txt)
realizada por Javier Smaldone <javier.AT.diff.com.ar>

Última actualización: 12-11-2003

---------------------------------------------------------------------


Open Webmail es un sistema de webmail basado en
Neomail versión 1.14 de Ernie Miller.

Open Webmail está orientado a la operación con archivos de bandejas de
gran tamaño con un uso eficiente de la memoria. También provee varias
caraterísticas para ayudar a los usuarios a migrar desde Microsoft
Outlook sin problemas.

CARACTERÍSTICAS
---------------
Open Webmail tiene las siguientes características:

1.  acceso rápido a bandejas
2.  movimiento de mensajes eficiente
3.  poco uso de memoria
4.  manejo apropiado de bandejas y mensajes
5.  bloqueo de archivos elegante
6.  relaying de SMTP remoto
7.  virtual hosting
8.  alias de usuarios
9.  soporte de usuarios virtuales puros
10. capacidad de configuración por cada usuario
11. varios módulos de autenticación
12. soporte de pam
13. búsqueda por contenido
14. soporte completo de MIME (en presentación y redacción)
15. soporte de bandeja de borradores
16. soporte de respuestas con membrete
17. soporte de verificación ortográfica
18. soporte de correo POP3
19. soporte de filtros de correo
20. previsualización de cantidad de mensajes
21. soporte de confirmación de lectura
22. conversión automática de conjuntos de caracteres (charset)
23. soporte de calendario con recordatorio/notificación
24. soporte de disco web
25. ejecución persistente a través de SpeedyCGI
26. soporte de compresión HTTP


REQUERIMIENTOS
--------------
Servidor web Apache con cgi habilitado
Perl 5.005 o superior

CGI.pm-3.05.tar.gz        (requerido)
MIME-Base64-3.01.tar.gz   (requerido)
libnet-1.19.tar.gz        (requerido)
Text-Iconv-1.2.tar.gz     (requerido)
libiconv-1.9.1.tar.gz     (requerido si el sistema no soporta iconv)

CGI-SpeedyCGI-2.22.tar.gz (opcional)
Compress-Zlib-1.33.tar.gz (opcional)
ispell-3.1.20.tar.gz      (opcional)
Quota-1.4.10.tar.gz       (opcional)
Authen-PAM-0.14.tar.gz    (opcional)
ImageMagick-5.5.3.tar.gz  (opcional)


INSTALACIÓN DE LOS PAQUETES REQUERIDOS
--------------------------------------
Primero, debe descargar los paquetes requeridos desde
http://openwebmail.org/openwebmail/download/packages/
y copiarlos a /tmp


Para CGI.pm haga lo siguiente:

   cd /tmp
   tar -zxvf CGI.pm-3.05.tar.gz
   cd CGI.pm-3.05
   perl Makefile.PL
   make
   make install

ps: Se ha reportado que Open Webmail se cuelga en la carga de
    adjuntos cuando es utilizado con versiones viejas del módulo
    CGI. Recomendamos usar la versión 2.74 del módulo CGI o una
    superior para Open Webmail.
    Para verificar la versión de su módulo CGI:

    perl -MCGI -e 'print $CGI::VERSION'


Para MIME-Base64 haga lo siguiente:

   cd /tmp
   tar -zxvf MIME-Base64-3.01.tar.gz
   cd MIME-Base64-3.01
   perl Makefile.PL
   make
   make install

ps: Aunque quizás ya tenga el módulo perl MIME-Base64, le
    recomendamos instalar MIME-Base64 desde las fuentes.
    Esto debería habilitar el soporte de XS en este módulo,
    lo cual mejora sustancialmente la velocidad de codificación/
    decodificación de los adjuntos MIME.

Para libnet haga lo siguiente:

   cd /tmp
   tar -zxvf libnet-1.19.tar.gz
   cd libnet-1.19
   perl Makefile.PL (responda 'no' si se le pregunta sobre actualizar
                     la configuración)
   make
   make install


Para Text-Iconv-1.2 haga lo siguiente:

   Dado que Text-Iconv-1.2 es en realidad una interfaz al soporte subyacente
   de iconv(), debe verificar si el soporte de iconv() está disponible en su
   sistema. Por favor, tipee el siguiente comando:

   man iconv

   Si no hay una página del manual para iconv, sus sistema puede no soportar
   iconv(). No se preocupe, puede tener soporte de iconv() instalando el
   paquete libiconv.

   cd /tmp
   tar -zxvf libiconv-1.9.1.tar.gz
   cd libiconv-1.9.1
   ./configure
   make
   make install

   Tipee nuevamente 'man iconv' para asegurarse de que libiconv está
   correctamente instalado.
   Luego comience a instalar el paquete Text-Iconv

   cd /tmp
   tar -zxvf Text-Iconv-1.2.tar.gz
   cd Text-Iconv-1.2
   perl Makefile.PL

   ps: si su sistema es FreeBSD, o si ha instalado libiconv manualmente,
       por favor edite el archivo Makefile.PL y cambie las líneas LIBS
       e INC como siguen antes de ejecutar 'perl Makefile.PL'

       'LIBS'         => ['-L/usr/local/lib -liconv'], # e.g., '-lm'
       'INC'          => '-I/usr/local/include',      # e.g., '-I/usr/include/other'

   make
   make test

   ps: Si 'make test' falla, significa que ha puesto un valor incorrecto
       en LIBS e INC en Makefile.PL o su soporte de iconv no está completo.
       Puede copiar misc/patches/iconv.pl.fake a shares/iconv.pl para hacer que
       Open Webmail trabaje sin soporte de iconv.

   make install


INSTALACIÓN DE OPENWEBMAIL
--------------------------
La última versión o la versión actual están disponibles en
http://openwebmail.org/openwebmail/

Si está usando FreeBSD e instala apache con pkg_add,
simplemente haga lo siguiente

1. chmod 4555 /usr/bin/suidperl

2. cd /usr/local/www
   tar -zxvBpf openwebmail-X.XX.tar.gz

3. modique /usr/local/www/cgi-bin/openwebmail/etc/openwebmail.conf
   a sus necesidades.

4. ejecute /usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl --init


ps: Si está usando RedHat 7.x (o la mayoría de los Linux) con Apache

1. cd /var/www
   tar -zxvBpf openwebmail-X.XX.tar.gz
   mv data/openwebmail html/
   rmdir data

2. cd /var/www/cgi-bin/openwebmail/etc
   modique auth_unix.conf from defaults/auth_unix.conf
   a. cambie la opción passwdfile_encrypted a '/etc/shadow'
   b  cambie la opción passwdmkdb a 'none'

3. modifique /var/www/cgi-bin/openwebmail/etc/openwebmail.conf
   a. cambie mailspooldir a '/var/spool/mail'
   b. cambie ow_htmldir a '/var/www/html/openwebmail'
      cambie ow_cgidir  a '/var/www/cgi-bin/openwebmail'
   c. cambie spellcheck a '/usr/bin/ispell'
   d. cambie default_signature según sus necesidades
   e. otros cambios que desee

4. agregue
   /var/log/openwebmail.log {
       postrotate
           /usr/bin/killall -HUP syslogd
       endscript
   }
   a /etc/logrotate.d/syslog para habilitar la rotación de logs sobre
   openwebmail.log

5. ejecute /var/www/cgi-bin/openwebmail/openwebmail-tool.pl --init

Si está usando RedHat 6.2, por favor use /home/httpd en vez de /var/www

ps: Se recomienda altamente leer doc/RedHat-README.txt (contribuido por
    elitric.AT.yahoo.com, en inglés) si está instalando Open Webmail en
    RedHat Linux.

ps: Thomas Chung (tchung.AT.openwebmail.org) mantiene el rpm para todas
    las versiones de openwebmail. Está disponible en
    http://openwebmail.org/openwebmail/download/redhat/rpm/
    Puede tener a Open Webmail funcionnando en 5 minutos con esto :)

Si está usando otro UNIX con apache, está bien

Trate de encontrar el directorio padre de los directorios data y cgi-bin,
ej: /usr/local/apache/share, luego

1. cd /usr/local/apache/share
   tar -zxvBpf openwebmail-X.XX.tar.gz
   mv data/openwebmail htdocs/
   rmdir data

2. modifique /usr/local/apache/share/cgi-bin/openwebmail/etc/openwebmail.conf
   a. cambie mailspooldir a la ubicación de la cola de correo de su sistema
   b. cambie ow_htmldir a '/usr/local/apache/share/htdocs'
      cambie ow_cgidir  a '/usr/local/apache/share/cgi-bin'
   c. cambie spellcheck a '/usr/local/bin/ispell'
   d. cambie default_signature según sus necesidades
   e. otros cambios que desee

3. cd /usr/local/apache/share/cgi-bin/openwebmail

   modifique openwebmail*.pl
   cambie la línea #!/usr/bin/suidperl a la ubicación en donde se encuentra
   suidperl.

   modifique etc/auth_unix.conf from etc/defaults/auth_unix.conf
   a. cambie la opción passwdfile_encrypted a '/etc/shadow'
   b. cambie la opción passwdmkdb a 'none'

4. ejecute /usr/local/apache/share/cgi-bin/openwebmail/openwebmail-tool.pl --init

ps:Si está instalando Open Webmail en Solares, por favor coloque
   'el camino al directorio cgi de openwebmail' en la primera línea del
   archivo /etc/openwebmail_path.conf.

   Por ejemplo, si el script está ubicado en

   /usr/local/apache/share/cgi-bin/openwebmail/openwebmail.pl,

   entonces el contenido de /etc/openwebmail_path.conf debe ser:

   /usr/local/apache/share/cgi-bin/openwebmail

ps: Si está usando Apache server 2.0 o posterior,
    por favor edite su archivo de configuración de Apache, reemplazando

    AddDefaultCharset ISO-8859-1

    por

    AddDefaultCharset off


INICIALIZACIÓN DE OPENWEBMAIL
-----------------------------
En el último paso de la instalación de Open Webmail, ha hecho:

cd the_directory_of_openwebmail_cgi_scripts
./openwebmail-tool.pl --init

Esta inicialización creará las tablas de mapas asignación que serán usadas
por openwebmail en el futuro.
Si omite este paso, no será capaz de acceder a openwebmail a través de la
interfaz web.

Y dado que perl en varias plataformas puede utilizar un sistema de dbm
subyacente diferente, la rutina de inicialización los probará y tratará
de darle algunas sugerencias útiles.

1. Verifica las opciones dbm_ext, dbmopen_ext y dbmopen_haslock options en
   dbm.conf, si tienen un valor erroneo, puede ver una salida como
-------------------------------------------------------------
Please change the following 3 options in openwebmail.conf
from
	dbm_ext           .db
	dbmopen_ext       none
	dbmopen_haslock   no
to
	dbm_ext           .db
	dbmopen_ext       .db
	dbmopen_haslock   yes
-------------------------------------------------------------

2. Verifica si el sistema dbm usa DB_File.pm por defecto y le sugerirá
   el parche necesario para DN_File.pm, pudiendo ver una salida como esta
-------------------------------------------------------------
Please modify /usr/libdata/perl/5.00503/mach/DB_File.pm by adding

        $arg[3] = 0666 unless defined $arg[3];

before the following text (about line 247)

        # make recno in Berkeley DB version 2 work like recno in version 1
-------------------------------------------------------------

Por favor, siga la sugerencia ya que de lo contrario openwebmail puede
no funcionar apropiadamente.
Y no olvide volver a ejecutar './openwebmail-tool.pl --init' luego de
realizar las modificaciones.


USANDO OPENWEBMAIL CON OTRO SERVIDOR SMTP
-----------------------------------------
Para hacer que openwebmail utilice otro servidor SMTP para el envío de
mensajes, tiene que cambiar la opción 'smtpserver' en openwebmail.conf.
Solo cambie el valor por defecto '127.0.0.1' por el nombre o ip del
servidor SMTP.

Por favor, asegúsese de que el servidor SMTP permite reenvío de mensajes
(mail relaying) desde el host donde se encuentra openwebmail.


SOPORTE DE FILTROS
------------------
El filtro de mensajes verifica si los mensajes en la bandeja INBOX coinciden
con las reglas de filtrado definidas por el usuario. Si lo hacen, mueve/copia
el mensaje a la bandeja de destino.
Si mueve un mensaje a la bandeja DELETE, esto significa que está eliminando
mensajes de la bandeja. Si utiliza INBOX como la bandeja de destino en una
regla de filtrado, cualquier mensaje que coincida con esta regla será
mantenido en la bandeja INBOX y el resto de las reglas serán ignoradas.


LÍMITES DE ESPACIO DE USUARIO
-----------------------------
El espacio de disco usado por el webmail, el calendario o el disco web, se
cuentan en suma como el uso del límite de espacio (quota) de usuario. Hay
cinco opciones que pueden utilizarse para controlar el límite de espacio en
defaults/openwebmail.conf. Puede modificar los valores por defecto configurando
las opciones en openwebmail.conf.

1. quota_module

Esta opción se utiliza para elegir el sistema de límites para openwembail.
Hay dos módulos de límites disponibles en la actualidad.

a. quota_unixfs.pl

Este es el módulo de límites de espacio recomendado si el usuario de
openwebmail es el usuario real de unix y su sistema tiene habilitados los
límites de espacio (disk quota).
Produce una sobrecarga mínima.

ps:Debe instalar Quota-1.4.10.tar.gz para utilizar este módulo.

b. quota_du.pl

Este es el módulo recomendado solo si quota_unixfs.pl no puede ser utilizado
en su sistema (p.ej: el usuario de openwebmail no es un usuario estándar de
unix o no se dispone de soporte de límites de espacio (disk quota) en el
sistema unix), dado que usa 'du -sk' para obtener el uso de espacio del
usuario.

Dado que ejecutar 'du -sk' en un directorio de gran tamaño puede consumir
demasiado tiempo, este módulo almacenará el resultado de 'du -sk' para evitar
demasiada generar sobrecarga. El tiempo de vida de esta información es, por
defecto, de 60 segundos y puede ser cambiado en quota_du.pl

Si configura esta opción como 'none', entonces no se usará el sistema de
límites de espacio en openwebmail.

2. quota_limit

Esta opción fija el límite (en kb) para el uso de espacio del usuario.
La operación del webmail y del disco web está limitada a 'borrar' si se
alcanza el límite de espacio.
Esta opción no imposibilita la realización de una operación del usuario
que lleve el uso de espacio más allá del límite, simplemente inhibe el
almacenamiento de mensajes o archivos hasta que el uso de espacio esté
nuevamente por debajo del límite.

ps: El valor de esta opción es usado solo si el módolo de quota no soporta
    quotalimit. ( aquellos en los cuales la rutina quota_info() retorna
    el valor -1)

ps: Si utiliza el módulo quota_unixfs.pl, por favor asegúrese de que
    existe espacio entre el softlimit y el hardlimit (ej: 5mb)

    ej: filesystem quota softlimit=25000, hardlimit=30000

3. quota_threshold

Normalmente, la información del límite de espacio será colocada en el
título de la ventana del navegador.
Pero si el uso de espacio crece por encima del límite fijado por esta
opción, se mostrará un mensaje de mayor tamaño en la parte superior
del menú principal del webmail y del disco web.

4. delmail_ifquotahit

Configure esta opción a 'yes' para hacer que openwebmail elimine
automáticamente los mensajes más antiguos de las bandejas de mensajes
del usuario en caso de que alcance el límite de espacio. El nuevo espacio
en uso será de aproximadamente el 90% del valor de la opción quota_limit

5. delfile_ifquotahit

Configure esta opción a 'yes' para hacer que openwebmail elimine
automáticamente los archivos de la raíz del disco web del usuario
en caso de que alcance el límite de espacio. El nuevo espacio
en uso será de aproximadamente el 90% del valor de la opción quota_limit

ps:Las opciones anteriores son utilizadas para controlar el límite
   de espacio del directorio home del usuario.
   Si desea limitar el tamaño de la cola de mensajes del usuario
   (la bandeja INBO) debe usar la opción spool_limit.
   Por favor, vea el archivo openwebmail.conf.help (en inglés)
   para mayores detalles.


LA HERRAMIENTA openwebmail-tool.pl
--------------------------------
Dado que el filtrado de mensajes es activado sólo en Open Webmail,
esto significa que los mensajes permanecerán en INBOX hasta que el
usuario los lea con Open Webmail.
Por lo tanto 'finger' u otras utilidades de informe del estado
del correo pueden darle información errónea dado que no tienen
conocimento de los filtros.

La herramienta 'openwebmail-tool.pl' puede utilizarse como un reemplazo
de finger. Realiza el filtrado antes de reportar el estado de los
,ensajes.

Algunos fingerd le permiten especificar el nombre del programa finger
mediante la opción -p (ej: fingerd en FreeBSD). Cambiando el parámetro
de fingerd en /etc/inetd.conf, los usuarios pueden obtener el estado
de su correo desde un host remoto.

openwebmail-tool.pl puede utilizarse también en el crontab para descargar
el correo POP3 o verificar los índices de las bandejas de los usuarios.
Por ejemplo:

59 5 * * *  /usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl -q -a -p -i

La línea anterior en el crontab desgargará el correo POP3, filtrará
los mensajes y verificará los índices de las bandejas para todos los
usuarios a las 5:59 horas cada mañana.

Si tiene habilitada la opción calendar_email_notifyinterval en
openwebmail.conf,  también necesitará usar openwebmail-tool.pl
en el crontab para verificar los eventos del calendario y así enviar
los mensajes de notificación. Por ejemplo:

0 */2 * * *  /usr/local/www/cgi-bin/openwebmail/openwebmail-tool.pl -q -a -n

La línea anterior usará openwebmail-tool.pl para verificar los eventos
del calendario de todos los usuarios cada dos horas. Note que usamos esta
frecuencia porque el valor por defecto de calendar_email_notifyinterval
es de 120 (minutos).
Debe configurar el crontab de acuerdo al valor de calendar_email_notifyinterval.


LIBRETA DE DIRECCIONES, FILTROS Y CALENDARIO GLOBALES
-----------------------------------------------------
El soporte actual para libreta de direcciones/filtros/calendario global
el muy limitado.
El administrador debe hacer una copia de la libreta de direcciones/filtros/
calendario al archivo especificado por las opciones global_addressbook,
global_filterbook o global_calendarbook, respectivamente.

ps: Puede crearse una cuenta para mantener la libreta de direcciones/filtros/
    calendario global. Por ejemplo: 'global'

    ln -s su_libreta_global    ~global/.openwebmail/webmail/address.book
    ln -s sus_filtros_globales ~global/.openwebmail/webmail/filter.book
    ln -s su_calendario_global ~global/.openwebmail/webcal/calendar.book

    Asegúrese de que los archivos globales tienen permiso de escritura para
    el usuario 'global' y de lectura para el resto.


SOPORTE DE VERIFICACIÓN ORTOGRÁFICA
-----------------------------------
Para habilitar la verificación ortográfica en openwebmail, debe instalar
el paquete ispell o aspell.

1. descargue ispell-3.1.20.tar.gz desde
   http://www.cs.ucla.edu/ficus-members/geoff/ispell.html e instálelo.
   o puede instalar los binarios desde un paquete FreeBSD o un rpm Linux

ps: Si está compilando ispell desde los fuentes, puede extenderlo
    utilizando un diccionario mejorado (en inglés)
    a. descargue http://openwebmail.org/openwebmail/download/contrib/words.gz
    b. gzip -d words.gz
    c. mkdir /usr/dict; cp words /usr/dict/words
    d. comience a compilar su ispell leyendo el archivo README

2. verifique openwebmail.conf para ver si la opción spellcheck apunta
   al binario de ispell

3. Si ha instalado múltiples diccionarios para su ispell/aspell,
   puede colocarlos en la opción spellcheck_dictionaries en openwebmail.conf
   separando los nombres con comas.

ps: Para saber si un diccionario específico está correctamente instalado
    en su sistema, puede utilizar el siguiente comando

    ispell -d dictionaryname -a

4. Si el idioma usado por un diccionario tiene un juego de caracteres
   diferente al del inglés, debe definir dichos caracteres en
   %dictionary_letters en openwebmail-spell.pl para ese diccionario.


SOPORTE DE RESPUESTAS AUTOMÁTICAS
---------------------------------
La función de respuesta automática en Open Webmail es realizada mediante
la utilidad vacation.
Dado que vacation no está disponible para algunos unix, una versión perl
de vacation, 'vacation.pl' es distribuida con openwebmail.
vacation.pl tiene la misma sintáxis que la incluida en Solaris.

Si la respuesta automática no funciona en su sistema, puede depurarla
con la opción -d

1. elija un usuario, habilite su respuesta automática en la preferencia
   de openwebmail
2. edite el archivo ~usuario/.forward,
   agregue la opción '-d' luego de vacation.pl
3. envíe un mensaje a este usuario para verificar la respuesta automática
4. verifique el archivo /tmp/vacation.debug para ver información sobre
   el posible error.


SOPORTE DE DISCO WEB
--------------------
El módulo de disco web provee una interfaz web para que el usuario
pueda acceder a su directorio home como un disco virtual en la web.
También está diseñado como un almacenamiento de los archivos adjuntos
de mensajes de correo. Se puede copiar libremente los adjuntos
entre los mensajes y el disco web.

El directorio / del disco virtual se corresponde con el directorio
home del usuario, cualquier ítem mostrado en el disco web está
realmente ubicado dentro del directorio home del usuario.

El disco web soporta operaciones básicas sobre archivos (mkdir, rmdir,
copy, move, rm), carga y descarga (se soporta la descarga
de múltiples archivos o directorios, ya que el disco web los comprime
en un archivo zip al transmitirlos).
También puede manipular varios tipos de archivos, incluyendo zip, arj,
rar, tar.gz, tar.bz, tar.bz2, tgz, tbz, gz, z...

Obviamente, el disco web debe llamar a programas externos para proveer
las funciones antes citadas. Los programas externos se buscan en
/usr/local/bin, /usr/bin y /bin, respectivamente.

Los programas externos usados por el disco web son:

tareas básicas                - cp, mv, rm,
compresión/descompresión n    - gzip, bzip2,
utilidades                    - tar, zip, unzip, unrar, unarj, lha
imágenes de muestra           - convert (en el paquete ImageMagick)

ps: No necesita instalar todos los programas externos para utilizar el
    disco web. una función será desabilitada si el programa externo
    relacionado no está disponible.

Los comandos externos son invocados con exec() y los parámetros
son pasados en un arreglo, lo cual previene el uso de /bin/sh con
scaped characters con los riesgos de seguridad que esto implicaría.

Para limitar el uso de espacio en el disco web por parte de un usuario,
por favor remítase a la sección 'LÍMITES DE ESPACIO DE USUARIO'.


@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Nota del traductor:

En adelante, este archivo no se encuentra traducido al español.
En breve este trabajo estará finalizado. Por favor, sepa disculpar
las molestias.

                                                   Javier Smaldone
                                                javier.AT.diff.com.ar
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

VIRTUAL HOSTING
---------------
You can have as many virtual domains as you want on same server with only one
copy of openwebmail installed. Open Webmail supports per domain config file.
Each domain can have its own set of configuration options, including
domainname, authentication module, quota limit, mailspooldir ...

You can even setup mail accounts for users without creating real unix accounts
for them. Please refer to Kevin Ellis's webpage:
"How to setup virtual users on Open WebMail using Postfix & vm-pop3d"
(http://www.bluelavalamp.net/owmvirtual/)

eg: To create configuration file for virtualdomain 'sr1.domain.com'

1. cd cgi-bin/openwebmail/etc/sites.conf/
2. cp ../openwebmail.conf sr1.domain.com
3. edit options in file 'sr1.domain.com' for domain 'vr1.domain.com'


USER ALIAS MAPPING
------------------
Open Webmail can use the sendmail virtusertable for user alias mapping.
The loginname typed by user may be pure name or name@somedomain. And this
loginname can be mapped to another pure name or name@otherdomain in the
virtusertable. This gives you the great flexibility in account management.

Please refer to http://www.sendmail.org/virtual-hosting.html for more detail

When a user logins Open WebMail with a loginname,
this loginname will be checked in the following order:

if (loginname is in the form of 'someone@somedomain') {
   user=someone
   domain=somedomain
} else {  	# a purename
   user=loginname
   domain=HTTP_HOST	# hostname in url
}

is user@domain a virtualuser defined in virtusertable?
if not {
   if (domain is mail.somedomain) {
      is user@somedomain defined in virtusertable?
   } else {
      is user@mail.domain defined in virtusertable?
   }
}

if (no mapping found && loginname is pure name) {
   is loginname a virtualuser defined in virtusertable?
}

if (any mapping found) {
   if (mappedname is in the form of 'mappedone@mappeddomain') {
      user=mappedone
      domain=mappeddomain
   } else {
      user=mappedname
      domain=HTTP_HOST
   }
}

if (option auth_withdomain is on) {
   check_userpassword for user@domain
} else {
   if (domain == HTTP_HOST) {
      check_userpassword for user
   } else {
      user not found!
   }
}

ps: if any alias found in virtusertable,
    the alias will be used as default email address for user


Here is an example of /etc/virtusertable

projectmanager		pm
johnson@company1.com	john1
tom@company1.com	tom1
tom@company2.com	tom2
mary@company3.com	mary3

Assume the url of the webmail server is http://mail.company1.com/....

The above virtusertable means:
1. if a user logins as projectmanager,
   openwebmail checks  projectmanager@mail.company1.com
                       projectmanager@company1.com
                       projectmanager as virtualuser	---> pm

2. if a user logins as johnson@company1.com
   openwebmail checks  johnson@company1.com	---> john1

   if a user logins as johnson,
   openwebmail checks  johnson@mail.company1.com
                       johnson@company1.com	---> john1

3. if a user logins as tom@company1.com,
   openwebmail checks  tom@company1.com		---> tom1

   if a user logins as tom@company2.com,
   openwebmail checks  tom@company2.com		---> tom2

   if a user logins as tom,
   openwebmail checks  tom@mail.company1.com
                       tom@company1.com		---> tom1

4. if a user logins as mary,
   openwebmail checks  mary@mail.company1.com
                       mary@company1.com
                       mary as virtualuser	---> not an alias


PURE VIRTUAL USER SUPPORT
-------------------------
Pure virtual user means a mail user who can use pop3 or openwebmail
to access his mails on the mail server but actually has no unix account
on the server.

Openwebmail pure virtual user support is currently available for system
running vm-pop3d + postfix. The authentication module auth_vdomain.pl is
designed for this purpose. Openwebmail also provides the web interface
which can be used to manage(add/delete/edit) these virtual users under
various virtual domains.

Please refer to the description in auth_vdomain.pl and auth_vdomain.conf
for more detail.

ps: vm-pop3d : http://www.reedmedia.net/software/virtualmail-pop3d/
    PostFix  : http://www.postfix.org/

    Kevin L. Ellis (kevin.AT.bluelavalamp.net) has written a tutorial
    for openwebmail + vm-pop3d + postfix
    Iis available at http://www.bluelavalamp.net/owmvirtual/


PER USER CAPABILITY CONFIGURATION
---------------------------------
While options in system config file(openwebmail.conf) are applied to all
users, you may find it useful to set the options on per user basis sometimes.
For example, you may want to limit the client ip access for some users or
limit the domain which the user can sent to. This could be easily done with
the per user config file support in Open Webmail.

The user capability file is located in cgi-bin/openwebmail/etc/user.conf/
and named as the realusername of user. Options in this file are actually
a subset of options in openwebmail.conf. An example 'SAMPLE' is provided.

eg: To creat the capability file for user 'guest':

1. cd cgi-bin/openwebmail/etc/users.conf/
2. cp SAMPLE guest
3. edit options in file 'guest' for user guest

ps: Openwebmail loads configuration files in the following order

1. cgi-bin/openwebmail/etc/defaults/openwebmail.conf
2. cgi-bin/openwebmail/etc/openwebmail.conf
3. cgi-bin/openwebmail/etc/sites.conf/domainname if file exists

   a. authentication module is loaded
   b. user alias is mapped to real userid.
   c. userid is authenticated.

4. cgi-bin/openwebmail/etc/users.conf/username if file exists

Options set in the later files will override the previous ones


PAM SUPPORT
-----------
PAM (Pluggable Authentication Modules) provides a flexible mechanism
for authenticating users. More detail is available at Linux-PAM webpage.
http://www.kernel.org/pub/linux/libs/pam/

Solaris 2.6, Linux and FreeBSD 3.1 are known to support PAM.
To make Open WebMail use the support of PAM, you have to:

1. download the Perl Authen::PAM module (Authen-PAM-0.14.tar.gz)
   It is available at http://www.cs.kuleuven.ac.be/~pelov/pam/
2. cd /tmp
   tar -zxvf Authen-PAM-0.14.tar.gz
   cd Authen-PAM-0.14
   perl Makefile.PL
   make
   make install

ps: Doing 'make test' is recommended when making the Authen::PAM,
    if you encounter error in 'make test', the PAM on your system
    will probable-ly not work.

3. add the following 3 lines to your /etc/pam.conf

(on Solaris)
openwebmail   auth	required	/usr/lib/security/pam_unix.so.1
openwebmail   account	required	/usr/lib/security/pam_unix.so.1
openwebmail   password	required	/usr/lib/security/pam_unix.so.1

(on Linux)
openwebmail   auth	required	/lib/security/pam_unix.so
openwebmail   account	required	/lib/security/pam_unix.so
openwebmail   password	required	/lib/security/pam_unix.so

(on Linux without /etc/pam.conf, by protech.AT.protech.net.tw)
If you don't have /etc/pam.conf but the directory /etc/pam.d/,
please create a file /etc/pam.d/openwebmail with the following content

auth       required	/lib/security/pam_unix.so
account    required	/lib/security/pam_unix.so
password   required	/lib/security/pam_unix.so

(on FreeBSD)
openwebmail   auth	required	/usr/lib/pam_unix.so
openwebmail   account	required	/usr/lib/pam_unix.so
openwebmail   password	required	/usr/lib/pam_unix.so

ps: PAM support on some release of FreeBSD seems broken (eg:4.1)

4. change auth_module to 'auth_pam.pl' in the openwebmail.conf

5. check auth_pam.pl and auth_pam.conf for further information.

ps: Since the authentication module is loaded only once in persistent mode,
    you need to do 'touch openwebmail*pl' to make the modification active.
    To avoid this, you may change your openwebmail backto suid perl mode
    before you make the modifications.
ps: For more detail about PAM configuration, it is recommended to read
    "The Linux-PAM System Administrators' Guide"
    http://www.kernel.org/pub/linux/libs/pam/Linux-PAM-html/pam.html
    by Andrew G. Morgan, morgan.AT.kernel.org


ADD NEW AUTHENTICATION MODULE TO OPENWEBMAIL
--------------------------------------------
Various authentications are directly available for openwebmail, including

auth_ldap.pl
auth_mysql.pl
auth_mysql_vmail.pl
auth_pam.pl
auth_pg.pl
auth_pgsql.pl
auth_pop3.pl
auth_unix.pl
auth_vdomain.pl

In case you found these modules not suitable for your need,
you may write a new authentication module for your own.

To add new authentication module into openwebmail, you have to:

1. choose an abbreviation name for this new authentication, eg: xyz

2. declare the package name in the first line of file auth_xyz.pl

   package ow::auth_xyz;

3. implement the following 4 function:

   ($retcode, $errmsg, $realname, $uid, $gid, $homedir)=
    get_userinfo($r_config, $domain, $user);

   ($retcode, $errmsg, @userlist)=
    get_userlist($r_config, $domain);

   ($retcode, $errmsg)=
    check_userpassword($r_config, $domain, $user, $password);

   ($retcode, $errmsg)=
    change_userpassword($r_config, $domain, $user, $oldpassword, $newpassword);

   where $retcode means:
    -1 : function not supported
    -2 : parameter format error
    -3 : authentication system internal error
    -4 : username/password incorrect

   $errmsg is the message to be logged to openwebmail log file,
   this would ease the work for sysadm in debugging problem of openwebmail

   $r_config is the reference of the openwebmail %config,
   you may just leave it untouched

   ps: You may refer to auth_unix.pl or auth_pam.pl to start.
       And please read doc/auth_module.txt

4. modify option auth_module in openwebmail.conf to auth_xyz.pl

5. test your new authentication module :)

ps: If you wish your authentication module to be included in the next release
    of openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw.
ps: Since the authentication module is loaded only once in persistent mode,
    you need to do 'touch openwebmail*pl' to make the modification active.
    To avoid this, you may change your openwebmail backto suid perl mode
    before you make the modifications.


ADD SUPPORT FOR NEW LANGUAGE
-----------------------------
It is very simple to add support for your language into openwebmail

1. choose an abbreviation for your language, eg: xy

ps: You may choose the abbreviation by referencing the following url
    http://babel.alis.com/langues/iso639.en.htm
    http://www.unicode.org/unicode/onlinedat/languages.html
    http://www.w3.org/International/O-charset.html

2. cd cgi-bin/openwebmail/etc.
   cp lang/en lang/xy
   cp -R templates/en templates/xy

3. translate file lang/xy and templates/xy/* from English to your language

4. change the package name of you language file (in the first line)

   package ow::xy

5. add the name and charset of your language to %languagenames,
   %languagecharsets in ow-shared.pl, then set default_language
   to 'xy' in openwebmail.conf

6. check iconv.pl, if the charset is not listed, add a line for this charset
   in both %charset_localname and %charset_convlist.

7. translate the files used by HTML editor

   cd data/openwebmail/javascript/htmlarea.openwebmail/popups
   cd xy

   then translate htmlarea-lang.js, insert_image.html, insert_sound.html,
   insert_table.html and select_color.html  into language xy

   Some style sheel setting in insert*html may need to be adjusted to
   get the best layout for your language. They are

   a. the width and height of the pop window, defined in the first line
      <html style="width: 398; height: 243">

   b. the boxies for fieldsets, defined in middle of the file
      .fl { width: 9em; float: left; padding: 2px 5px; text-align: right; }
      .fr { width: 6em; float: left; padding: 2px 5px; text-align: right; }

      .fl is for box in the left and .fr is for box in the right,
      you may try wider width for better layout

8. If you want, you may create the holidays of your language with the
   openwebmail calendar, then copy the ~/.openwebmail/webcal/calendar.book into
   etc/holidaysdir/your_languagename. Them the holidays will be displayed
   to all users of this language

9. If you want, you may also translation help tutorial to your language
   the help files are located under data/openwebmail/help.

ps: if your language is Right-To-Left oriented and you can read Arabic,
    you can use the Arabic template instead of English as the start templates.
    And don't forget to mention it when you submit the templates
    to the openwebmail team.
ps: Since the language and templates are loaded only once in persistent mode,
    you need to do 'touch openwebmail*pl' to make the modification active.
    To avoid this, you may change your openwebmail backto suid perl mode
    before you make the modifications.

ps: If you wish your translation to be included in the next release of
    openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw.

    IMPORTANT!!!
    Please be sure your translation is based on the template files in the
    latest openwebmail-current.tar.gz. And please send both your tranlsation
    and english version files it based on to us. So we can check if there
    is any latest modification should be added your translation.


ADD NEW CHARSET TO AUTO CONVERSION LIST
---------------------------------------
Openwebmail can do charset conversion automatically if a message is written
with charset other than the one you are using. Openwebmail does this by calling
the iconv() charset conversion function, as defined by the Single UNIX Specification.

To make openwebmail do auto-convert a new charset for your language:
1. find the charset used by your language in %charset_convlist in charset_iconv.pl
2. put this new charset to the convlist of the charset of your language
3. define the localname of the new charset on your OS to the %charset_localname.
   (It is always the same as the name of charset but in capitals.)

Note: The possible conversions and the quality of the conversions depend on the
      available iconv conversion tables and algorithms, which are in most cases
      supplied by the operating system vendor.


ADD MORE BACKGROUNDS TO OPENWEBMAIL
-----------------------------------
If you would like to add some background images into openwebmail for your
user, you can copy them into %ow_htmldir%/images/backgrounds.
Then the user can choose these backgrounds from user preference menu.

ps: If you wish to share your wonderful backgrounds with others,
    please email it to openwebmail.AT.turtle.ee.ncku.edu.tw


DESIGN YOUR OWN ICONSET IN OPENWEBMAIL
---------------------------------------
If you are interested in designing your own image iconset in the openwebmail,
you have to

1. create a new sub directory in the %ow_htmldir%/images/iconsets/,
   eg: MyIconSet
   ps: %ow_htmldir% is the dir where openwebmail could find its html objects,
       it is defined in openwebmail.conf
2. copy all images from %ow_htmldir%/images/iconsets/Default to MyIconSet
3. modify the image files in the %ow_htmldir%/images/iconsets/MyIconSet
   for your need

ps:In case you want to design iconsets with text inside, the default font used
   in Default.English and Cool3D.English is 'Arial Narrow'.

If you are interested in designing your own text iconset in the openwebmail,
you have to

1. create a new sub directory started with Text. in the %ow_htmldir%/images/iconsets/,
   eg: Text.MyLang
   ps: %ow_htmldir% is the dir where openwebmail could find its html objects,
       it is defined in openwebmail.conf
2. copy %ow_htmldir%/images/iconsets/Text.English/icontext to Text.MyLnag/icontext
3. modify the Text.MyLang/icontext for your language

ps: If your are going to make Cool3D iconset for your language with Photoshop,
    you may start with the psd file created by Jan Bilik <jan.AT.bilik.org>,
    it could save some of your time. The psd file is available at
    http://openwebmail.org/openwebmail/contrib/Cool3D.iconset.Photoshop.template.zip

ps: If you wish the your new iconset to be included in the next release of
    openwebmail, please submit it to openwebmail.AT.turtle.ee.ncku.edu.tw


TEST
-----
1. chdir to openwebmail cgi dir (eg: /usr/local/www/cgi-bin/openwebmail)
   and check the owner, group and permission of the following files

   ~/openwebmail*.pl            - owner=root, group=mail, mode=4755
   ~/vacation.pl                - owner=root, group=mail, mode=0755
   ~/etc                        - owner=root, group=mail, mode=755
   ~/etc/sessions               - owner=root, group=mail, mode=771
   ~/etc/users                  - owner=root, group=mail, mode=771

   /var/log/openwebmail.log     - owner=root, group=mail, mode=660

2. test your webmail with http://your_server/cgi-bin/openwebmail/openwebmail.pl

If there is any problem, please check the faq.txt.
The latest version of FAQ will be available at
http://openwebmail.org/openwebmail/download/doc/faq.txt


PERSISTENT RUNNING through SpeedyCGI
------------------------------------
SpeedyCGI: http://www.daemoninc.com/SpeedyCGI/

"SpeedyCGI is a way to run perl scripts persistently, which can make
them run much more quickly." - Sam Horrocks.

Openwebmail can get almost 5x to 10x speedup when running with SpeedyCGI.
You can get a quite reactive openwebmail systems on a very old P133 machine :)

Note: Don't try to fly before you can walk...
      Please do this speedup modification only after your openwebmail is working.

1. install SpeedyCGI

   get the latest SpeedyCGI source from
   http://sourceforge.net/project/showfiles.php?group_id=2208
   http://daemoninc.com/SpeedyCGI/CGI-SpeedyCGI-2.22.tar.gz

   cd /tmp
   tar -zxvf path_to_source/CGI-SpeedyCGI-2.22.tar.gz
   cd CGI-SpeedyCGI-2.22
   perl Makefile.PL (ans 'no' with the default)

   then edit speedy/Makefile
   and add " -DIAMSUID" to the end of the line of "DEFINE = "

   make
   make install
   (If you encounter error complaining about install mod_speedy,
    that is okay, you can safely ignore it.)

2. set speedy to setuid root

   Find the speedy binary according to the messages in previous step,
   it is possible-ly at /usr/bin/speedy or /usr/local/bin/speedy.

   Assume it is installed in /usr/bin/speedy

   cp /usr/bin/speedy /usr/bin/speedy_suid
   chmod 4555 /usr/bin/speedy_suid

3. modify openwebmail for speedy

   The code of openwebmail has already been modified to work with SpeedyCGI,
   so all you have to do is to
   replace the first line of all cgi-bin/openwebmail/openwebmail*pl
   from
	#!/usr/bin/suidperl -T
   to
	#!/usr/bin/speedy_suid -T -- -T/tmp/speedy

   The first -T option (before --) is for perl interpreter.
   The second -T/tmp/speedy option is for SpeedyCGI system,
   which means the prefix of temporary files used by SpeedyCGI.

   ps: You will see a lot of /tmp/speedy.number files if your system is
       quite busy, so you may change this to value like /var/run/speedy

4. test you openwebmail for the speedup.

5. If you are installing openwebmail on a low end machine, then you may
   wish to eliminate the firsttime startup delay of the scripts for the user.
   You may use the preload.pl, it acts as a http client to start
   openwebmail on the web server automatically.

   a. through web interface
      http://your_server/cgi-bin/openwebmail/preload.pl
      Please refer to preload.pl for default password and how to change it.

   b. through command line or you can put the following line in crontab
      to preload the most frequently used scripts into mempry

      0 * * * *	/usr/local/www/cgi-bin/openwebmail/preload.pl -q openwebmail.pl openwebmail-main.pl openwebmail-read.pl

      If your machine has a lot of memory, you may choose to preload all
      openwebmail scripts

      0 * * * *	/usr/local/www/cgi-bin/openwebmail/preload.pl -q --all

6. Need more speedup?

   Yes, you can try to install the mod_speedycgi to your Apache,
   but you may need to recompile Apache to make it allow using root as euid
   Please refer to README in SpeedyCGI source tar ball..

   Another approach for speedup is to use some httpd that handles muliples
   connections with only one process, eg: http://www.acme.com/software/thttpd/,
   instead of the apache web server.

   Please refer to doc/thttpd.txt for some installation tips.

ps: Kevin L. Ellis (kevin.AT.bluelavalamp.net) has written a tutorial
    and benchmark for OWM + SpeedyCGI.
    It is available at http://www.bluelavalamp.net/owmspeedycgi/


HTTP COMPRESSION
----------------
To make this feature work, you have to install the Compress-Zlib-1.33.tar.gz.
HTTP Compression is very useful for users with slow connection to the
openwebmail server (eg: dialup user, PDA user).

Note: There are some compatibility issues for HTTP compression

1. Some proxy servers only support HTTP compression via HTTP 1.1,
   the user have to enable the use of HTTP1.1 for proxy in their browser
2. Some proxy servers don't support HTTP compression at all,
   the user have to list the webmail server as directly connected in
   the advanced proxy setting in their browser
3. Some browsers have problems when using HTTP compression with SSL,
4. Some browsers claim to support HTTP compression but actually not.

The login screen has a checkbox for HTTP compression.
So in case there is any problem, the user can relogin with checkbox unchecked.


INTEGRATION WITH HTML PAGES
---------------------------
A small script has been made to let static html page display the
user mail/calendar status dynamically.
All you need to do is to put the following text in html source code.

<table cellspacing=0 cellpadding=0><tr><td>
<script language="JavaScript"
src="http://you_server_domainname/cgi-bin/openwebmail/userstat.pl">
</script>
</td></tr></table>

or

<table cellspacing=0 cellpadding=0><tr><td>
<script language="JavaScript"
src="http://you_server_domainname/cgi-bin/openwebmail/userstat.pl?playsound=1">
</script>
</td></tr></table>

If the user has ever logined openwebmail successfully,
then his mail/calendar ststus would be displayed in this html page
as an link to the openwebmail login page.


TODO
----
Features that we would like to implement first...

1. web bookmark
2. PGP/GNUPG integration
3. shared folder/calendar

Features that people may also be interested

1. maildir support
2. online people sign in
3. log analyzer


10/13/2003

openwebmail.AT.turtle.ee.ncku.edu.tw

