// this module requires the popup_base.js library file
// be loaded to provide the dhtml layer support
//
// load a given url for contact information into a dhtml popup layer

function popupContact(obj, id, xOffset, yOffset, url) {
   attachListener(id);
   registerPopup(id);
   contactHtml = makeContactHtml(id,url);
   writeLayer(id,contactHtml);
   setLayerPos(obj,id,xOffset,yOffset);
   showLayer(id);
   return true;
}

function makeContactHtml(id,url) {
   var html = '';
   // writing the <html><head><body> causes some browsers (Konquerer) to fail
   html += '<table cellspacing="1" cellpadding="0" border="0" width="400">\n';
   html += '<tr>\n';
   html += '<td valign="top" bgcolor="#000000">\n';
   html += '<table cellspacing="1" cellpadding="2" border="0" width="100%">\n';
   html += '<tr>\n';
   html += '<td align="center" valign="top" class="menubar">\n';
   html += '<iframe width="99%" class="contact" src="' + url + '"></iframe>\n';
   html += '\n</td>\n';
   html += '</tr>\n';
   html += '</table>\n';
   html += '</td>\n';
   html += '</tr>\n';
   html += '</table>';

   return html;
}
