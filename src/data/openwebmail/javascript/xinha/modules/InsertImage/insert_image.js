  /*--------------------------------------:noTabs=true:tabSize=2:indentSize=2:--
    --  Xinha (is not htmlArea) - http://xinha.org
    --
    --  Use of Xinha is granted by the terms of the htmlArea License (based on
    --  BSD license)  please read license.txt in this package for details.
    --
    --  Copyright (c) 2005-2008 Xinha Developer Team and contributors
    --
    --  This is the Xinha standard implementation of an image insertion plugin
    --
    --  he file is loaded as a special plugin by the Xinha Core when no alternative method (plugin) is loaded.
    --
    --
    --  $HeadURL: http://svn.xinha.org/trunk/modules/InsertImage/insert_image.js $
    --  $LastChangedDate: 2008-10-03 16:44:49 -0700 (Fri, 03 Oct 2008) $
    --  $LastChangedRevision: 1055 $
    --  $LastChangedBy: ray $
    --------------------------------------------------------------------------*/
  
InsertImage._pluginInfo = {
  name          : "InsertImage",
  origin        : "Xinha Core",
  version       : "$LastChangedRevision: 1055 $".replace(/^[^:]*:\s*(.*)\s*\$$/, '$1'),
  developer     : "The Xinha Core Developer Team",
  developer_url : "$HeadURL: http://svn.xinha.org/trunk/modules/InsertImage/insert_image.js $".replace(/^[^:]*:\s*(.*)\s*\$$/, '$1'),
  sponsor       : "",
  sponsor_url   : "",
  license       : "htmlArea"
};

function InsertImage(editor) {
	this.editor = editor;
	var cfg = editor.config;
	var self = this;

   editor.config.btnList.insertimage[3] = function() { self.show(); }
  }
  
InsertImage.prototype._lc = function(string) {
	return Xinha._lc(string, 'Xinha');
};

InsertImage.prototype.onGenerateOnce = function()
{
	InsertImage.loadAssets();
};

InsertImage.loadAssets = function()
{
	var self = InsertImage;
	if (self.loading) return;
	self.loading = true;
	Xinha._getback(_editor_url + 'modules/InsertImage/dialog.html', function(getback) { self.html = getback; self.dialogReady = true; });
	Xinha._getback(_editor_url + 'modules/InsertImage/pluginMethods.js', function(getback) { eval(getback); self.methodsReady = true; });
};
InsertImage.prototype.onUpdateToolbar = function()
{ 
  if (!(InsertImage.dialogReady && InsertImage.methodsReady))
	{
	  this.editor._toolbarObjects.insertimage.state("enabled", false);
  }
  else this.onUpdateToolbar = null;
};
  
InsertImage.prototype.prepareDialog = function()
{
	var self = this;
	var editor = this.editor;
  
	var dialog = this.dialog = new Xinha.Dialog(editor, InsertImage.html, 'Xinha',{width:410})
	// Connect the OK and Cancel buttons
	dialog.getElementById('ok').onclick = function() {self.apply();}

	dialog.getElementById('cancel').onclick = function() {
          dialog.getElementById('f_selectable').options.selectedIndex = 0;
          dialog.getElementById('f_url').value = '';
          dialog.getElementById('ipreview').src = '';
          self.dialog.hide();
        }

	dialog.getElementById('f_selectable').onchange = function() {
          var f_url = dialog.getElementById('f_url');
          var f_alt = dialog.getElementById('f_alt');

          if (dialog.getElementById('f_selectable').options.selectedIndex > 0) {
             var f_selectable = dialog.getElementById('f_selectable').options[dialog.getElementById('f_selectable').options.selectedIndex];
             f_url.value = f_selectable.value;
             f_alt.value = f_selectable.text;
          } else {
             f_url.value = '';
             f_alt.value = '';
             dialog.getElementById('ipreview').src = '';
          }
        }

        // Populate the f_selectable selection list
        for (var i=0; i<editor.config.selectableImages.length; i++) {
          var text = editor.config.selectableImages[i][0];
          var value = editor.config.selectableImages[i][1];
          // preserve option 0 of the select list (the nothing selected option)
          dialog.getElementById('f_selectable').options[i+1] = new Option(text, value);
        }

	dialog.getElementById('preview').onclick = function() {
	  var f_url = dialog.getElementById('f_url');
	  var url = f_url.value;

	  if (!url) {
	    alert(dialog._lc("You must enter the URL"));
	    f_url.focus();
            return false;
          }

          dialog.getElementById('ipreview').src = url;
	  return false;
	}

	this.dialog.onresize = function ()
  {
		var newHeightForPreview = 
		parseInt(this.height,10) 
		- this.getElementById('h1').offsetHeight 
		- this.getElementById('buttons').offsetHeight
		- this.getElementById('inputs').offsetHeight 
		- parseInt(this.rootElem.style.paddingBottom,10); // we have a padding at the bottom, gotta take this into acount
		
		
		this.getElementById("ipreview").style.height = ((newHeightForPreview > 0) ? newHeightForPreview : 0) + "px"; // no-go beyond 0
		
		this.getElementById("ipreview").style.width = this.width - 2   + 'px'; // and the width

  }
	this.dialogReady = true;
};