<script type="text/javascript" language="javascript">
<!--
// When you want to include this popup in a page you MUST:
// 1) create a named div for the popup to attach to in the page.
//    It should look like <div id="mypopup"></div>. Do not put
//    the div anywhere in a table. It should be outside tables.
// 2) create a stylesheet id selector entry for your div. It
//    MUST be position absolute and should look like:
//    #mypopup{ position: absolute;
//              visibility: hidden;
//              background-color: @@@MENUBAR@@@;
//              layer-background-color: @@@MENUBAR@@@; }
// 3) call the popup with code that looks like
//    <a href="#" onClick="displayNote(this,'mypopup',-175,15,note);">
//    where -175 and 15 are your desired x and y offsets from the link.
//    The final argument indicates the validation script to run after
//    the popup makes a change to the form. This argument is optional.

var nn4 = (document.layers) ? true : false;
var ie  = (document.all) ? true : false;
var dom = (document.getElementById && !document.all) ? true : false;
var popups = new Array(); // keeps track of popup windows we create
var noteHtml = '';

function displayNote(obj, id, xOffset, yOffset, note) {
   attachListener(id);
   registerPopup(id);
   noteHtml = makeNoteHtml(id,note);
   writeLayer(id,noteHtml);
   setLayerPos(obj,id,xOffset,yOffset);
   showLayer(id);
   return true;
}

function attachListener(id) {
   var layer = new pathToLayer(id)
   if (layer.obj.listening == null) {
      document.oldMouseupEvent = document.onmouseup;
      if (document.oldMouseupEvent != null) {
         document.onmouseup = new Function("document.oldMouseupEvent(); hideLayersNotClicked();");
      } else {
         document.onmouseup = hideLayersNotClicked;
      }
      layer.obj.listening = true;
   }
}

function registerPopup(id) {
   // register this popup window with the popups array
   var layer = new pathToLayer(id);
   if (layer.obj.registered == null) {
      var index = popups.length ? popups.length : 0;
      popups[index] = layer;
      layer.obj.registered = 1;
   }
}

function makeNoteHtml(id,note) {
   var html = '';
   // writing the <html><head><body> causes some browsers (Konquerer) to fail
   html += '<table cellpadding="0" cellspacing="1" border="0" bgcolor="#000000" width="300">\n';
   html += '<tr>\n';
   html += '<td valign="top">\n';
   html += '<table cellpadding="0" cellspacing="2" border="0" bgcolor=@@@MENUBAR@@@ width="100%">\n';
   html += '<tr>\n';
   html += '<td valign="top">\n';
   html += unescape(note);
   html += '\n</td>\n';
   html += '</tr>\n';
   html += '</table>\n';
   html += '</td>\n';
   html += '</tr>\n';
   html += '</table>\n';

   return html;
}

function writeLayer(id, html) {
   var layer = new pathToLayer(id);
   if (nn4) {
      layer.obj.document.open();
      layer.obj.document.write(html);
      layer.obj.document.close();
   } else {
      layer.obj.innerHTML = '';
      layer.obj.innerHTML = html;
   }
}

function setLayerPos(obj, id, xOffset, yOffset) {
   var newX = 0;
   var newY = 0;
   if (obj.offsetParent) {
      // if called from href="setLayerPos(this,'example')" then obj will
      // have no offsetParent properties. Use onClick= instead.
      while (obj.offsetParent) {
         newX += obj.offsetLeft;
         newY += obj.offsetTop;
         obj = obj.offsetParent;
      }
   } else if (obj.x) {
      // nn4 - only works with "a" tags
      newX += obj.x;
      newY += obj.y;
   }

   // apply the offsets
   newX += xOffset;
   newY += yOffset;

   // apply the new positions to our layer
   var layer = new pathToLayer(id);
   if (nn4) {
      layer.style.left = newX;
      layer.style.top  = newY;
   } else {
      // the px avoids errors with doctype strict modes
      layer.style.left = newX + 'px';
      layer.style.top  = newY + 'px';
   }
}

function hideLayersNotClicked(e) {
   if (!e) var e = window.event;
   e.cancelBubble = true;
   if (e.stopPropagation) e.stopPropagation();
   if (e.target) {
      var clicked = e.target;
   } else if (e.srcElement) {
      var clicked = e.srcElement;
   }

   // go through each popup window,
   // checking if it has been clicked
   for (var i=0; i < popups.length; i++) {
      if (nn4) {
         if ((popups[i].style.left < e.pageX) &&
             (popups[i].style.left+popups[i].style.clip.width > e.pageX) &&
             (popups[i].style.top < e.pageY) &&
             (popups[i].style.top+popups[i].style.clip.height > e.pageY)) {
            return true;
         } else {
            hideLayer(popups[i].obj.id);
            return true;
         }
      } else if (ie) {
         while (clicked.parentElement != null) {
            if (popups[i].obj.id == clicked.id) {
               return true;
            }
            clicked = clicked.parentElement;
         }
         hideLayer(popups[i].obj.id);
         return true;
      } else if (dom) {
         while (clicked.parentNode != null) {
            if (popups[i].obj.id == clicked.id) {
               return true;
            }
            clicked = clicked.parentNode;
         }
         hideLayer(popups[i].obj.id);
         return true;
      }
      return true;
   }
   return true;
}

function pathToLayer(id) {
   if (nn4) {
      this.obj = document.layers[id];
      this.style = document.layers[id];
   } else if (ie) {
      this.obj = document.all[id];
      this.style = document.all[id].style;
   } else {
      this.obj = document.getElementById(id);
      this.style = document.getElementById(id).style;
   }
}

function showLayer(id) {
   var layer = new pathToLayer(id)
   layer.style.visibility = "visible";
}

function hideLayer(id) {
   var layer = new pathToLayer(id);
   layer.style.visibility = "hidden";
}
// -->
</script>

