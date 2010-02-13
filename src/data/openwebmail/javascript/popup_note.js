// this module requires the popup_base.js library file
// be loaded to provide the dhtml layer support
//
// given a note, display the note in a dhtml popup layer

function popupNote(obj, id, xOffset, yOffset, note) {
   attachListener(id);
   registerPopup(id);
   noteHtml = makeNoteHtml(id,note);
   writeLayer(id,noteHtml);
   setLayerPos(obj,id,xOffset,yOffset);
   showLayer(id);
   return true;
}

function makeNoteHtml(id,note) {
   var html = '';
   // writing the <html><head><body> causes some browsers (Konquerer) to fail
   html += '<table cellspacing="1" cellpadding="0" border="0" width="300">\n';
   html += '<tr>\n';
   html += '<td valign="top" bgcolor="#000000">\n';
   html += '<table cellspacing="1" cellpadding="4" border="0" width="100%">\n';
   html += '<tr>\n';
   html += '<td valign="top" class="menubar">\n';
   html += unescape(note);
   html += '\n</td>\n';
   html += '</tr>\n';
   html += '</table>\n';
   html += '</td>\n';
   html += '</tr>\n';
   html += '</table>\n';

   return html;
}
