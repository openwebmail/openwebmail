function popup_message(charset, title, msg, button, name, width, height, seconds) {
   // stylesheet and fontsize settings are inherited from the calling document
   var html = '';
   html += '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">\n\n';
   html += '<html>\n';
   html += '<head>\n';
   html += '<meta http-equiv="Content-Type" content="text/html; charset='+charset+'">\n';
   html += '<link rel="stylesheet" type="text/css" href="'+document.styleSheets[0].href+'">\n';
   html += '<title>'+title+'</title>\n';
   html += '</head>\n';
   html += '<body style="font-size: '+document.body.style.fontSize+'">\n';
   html += '<table cellspacing="1" cellpadding="1" border="0" width="90%" align="center">\n';
   html += '<tr>\n';
   html += '<td class="rowdark" style="font-size: '+document.body.style.fontSize+'">\n';
   html += msg;
   html += '</td>\n';
   html += '</tr>\n';
   html += '<tr>\n';
   html += '<td align="center">\n';
   html += '<form action="#" method="post" name="showmsg">\n';
   html += '<br><input type="button" name="ok" value="'+button+'" onclick="window.close();">\n';
   html += '</form>\n';
   html += '</td>\n';
   html += '</tr>\n';
   html += '</table>\n';
   html += '<script type="text/javascript">\n';
   html += 'setTimeout("close()", '+seconds+'*1000);\n';
   html += '</script>\n';
   html += '</body>\n';
   html += '</html>\n';

   var hWnd = window.open("", name,"width="+width+",height="+height+",location=no,menubar=no,resizable=yes,scrollbars=no,status=no,toolbar=no");
   hWnd.document.open("text/html", "replace");
   hWnd.document.write(html);
   hWnd.document.close();
   hWnd.focus();
}
