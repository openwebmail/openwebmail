// this module requires the calling code to:
// - define the autosuggest_url used to process queries and provide suggestion results
// - define a div named popup_autosuggest
// - load the popup_base.js library file to provide the dhtml layer support
// - load the ajax.js library file to provide XMLHttpRequest support
//
// the fieldname and fieldvalue will be appended to the
// autosuggest_url by the javascript code here
//
// given the results of an autosuggest query, display the results in a dhtml popup layer
// provide interactivity for the user to select a result and append the selection to the
// caller field
//

function popupSuggest(obj, id, xOffset, yOffset, result) {
   if (result == '') {
      hideLayer(id);
   } else {
      attachListener(id);
      registerPopup(id);
      suggestHtml = makeSuggestHtml(obj,id,result);
      writeLayer(id,suggestHtml);
      setLayerPos(obj,id,xOffset,yOffset);
      showLayer(id);
   }

   return true;
}

function makeSuggestHtml(obj,id,result) {
   var html = '';
   // writing the <html><head><body> causes some browsers (Konquerer) to fail
   html += '<table cellspacing="1" cellpadding="0" border="0" width="'+(obj.offsetWidth+3)+'">\n';
   html += '<tr>\n';
   html += '<td valign="top" bgcolor="#000000">\n';
   html += '<table cellspacing="1" cellpadding="0" border="0" width="100%">\n';
   html += '<tr>\n';
   html += '<td valign="top" class="menubar">\n';
   html += unescape(result);
   html += '\n</td>\n';
   html += '</tr>\n';
   html += '</table>\n';
   html += '</td>\n';
   html += '</tr>\n';
   html += '</table>\n';

   return html;
}

var selected_suggestion = -1;

function autosuggest(e, field) {
   var keycodenum = e.keyCode ? e.keyCode : e.which;

   if (keycodenum == 8 || keycodenum == 32 || (keycodenum >= 46 && keycodenum <= 111) || keycodenum > 123) {
      // delay the ajax call until the user has stopped typing for 250 milliseconds
      if (field.zzz) clearTimeout(field.zzz);

      field.zzz = setTimeout(function() { do_autosuggest(field) }, 250);
   }

   if (document.getElementById('suggestions')) {
      var suggestions = document.getElementById('suggestions').getElementsByTagName('div');

      if (suggestions) {
         if (keycodenum == 38) {
            // up arrow
            if ((selected_suggestion - 1) >= 0) highlight_suggestion(suggestions[selected_suggestion - 1]);
         } else if (keycodenum == 40) {
            // down arrow
            if ((selected_suggestion + 1) < suggestions.length) highlight_suggestion(suggestions[selected_suggestion + 1]);
         } else if (keycodenum == 13) {
            // enter key
            if (selected_suggestion >= 0 || selected_suggestion <= suggestions.length) {
               suggestions[selected_suggestion].onclick();

               // prevent form submission
               if (e.preventDefault) e.preventDefault();
               e.returnValue = false;
               e.cancelBubble = true;
               if (e.stopPropagation) e.stopPropagation();
               return false;
            }
         }
      }
   }
}

function do_autosuggest(field) {
   var ajax_url = autosuggest_url + '&fieldname=' + field.name + '&fieldvalue=' + field.value;
   ajax(ajax_url, function (result) { popupSuggest(field,'popup_autosuggest',-2,23,result) });
}

function highlight_suggestion(selectedNode) {
   if (document.getElementById('suggestions')) {
      var suggestions = document.getElementById('suggestions').getElementsByTagName('div');

      if (suggestions) {
         for(i=0; i < suggestions.length; i++) {
            if (suggestions[i] == selectedNode) {
               suggestions[i].className = 'suggesthilite';
               selected_suggestion = i;
            } else {
               suggestions[i].className = 'suggest';
            }
         }
      }
   }
}

function pick_suggestion(form, field, option) {
   var textfield = document.forms[form].elements[field];

   textfield.focus();
   textfield.value = option;

   if (textfield.setSelectionRange) {
      textfield.setSelectionRange(textfield.value.length, textfield.value.length);
   } else if (textfield.createTextRange) {
      var range = textfield.createTextRange();
      range.collapse(true);
      range.moveEnd('character', textfield.value.length);
      range.moveStart('character', textfield.value.length);
      range.select();
   }

   // force carat visibility for some browsers
   if (document.createEvent) {
      // Trigger a space keypress.
      var e = document.createEvent('KeyboardEvent');
      if (typeof(e.initKeyEvent) != 'undefined') {
         e.initKeyEvent('keypress', true, true, null, false, false, false, false, 0, 32);
      } else {
         e.initKeyboardEvent('keypress', true, true, null, false, false, false, false, 0, 32);
      }
      textfield.dispatchEvent(e);

      // Trigger a backspace keypress.
      e = document.createEvent('KeyboardEvent');
      if (typeof(e.initKeyEvent) != 'undefined') {
         e.initKeyEvent('keypress', true, true, null, false, false, false, false, 8, 0);
      } else {
         e.initKeyboardEvent('keypress', true, true, null, false, false, false, false, 8, 0);
      }
      textfield.blur(); // webkit wake-up hack
      textfield.focus();
      textfield.dispatchEvent(e);
   }

   selected_suggestion = -1;
   hideLayer('popup_autosuggest');
}

