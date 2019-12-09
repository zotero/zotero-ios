/*
    ***** BEGIN LICENSE BLOCK *****
    
    Copyright © 2011 Center for History and New Media
                     George Mason University, Fairfax, Virginia, USA
                     http://zotero.org
    
    This file is part of Zotero.
    
    Zotero is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    
    Zotero is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.
    
    You should have received a copy of the GNU Affero General Public License
    along with Zotero.  If not, see <http://www.gnu.org/licenses/>.
    
    ***** END LICENSE BLOCK *****
*/

ItemSaver = function(libraryID, attachmentMode, forceTagType) {};
ItemSaver.ATTACHMENT_MODE_IGNORE = 0;
ItemSaver.ATTACHMENT_MODE_DOWNLOAD = 1;
ItemSaver.ATTACHMENT_MODE_FILE = 2;

// We don't define a real itemSaver here because Zotero.Translate will always be run in object-only
// mode, but we do define a saveCollection no-op.
ItemSaver.prototype.saveCollection = function() {};

ItemSaver.prototype.saveItems = async function (jsonItems, attachmentCallback, itemsDoneCallback) {
	this.items = (this.items || []).concat(jsonItems);
	return jsonItems
}

ItemGetter = function() {
	this._itemsLeft = null;
	this._collectionsLeft = null;
	this._itemID = 1;
};

ItemGetter.prototype = {
	"setItems":function(items) {
		this._itemsLeft = items;
		this.numItems = this._itemsLeft.length;
	},
	
	/**
	 * Retrieves the next available item
	 */
	"nextItem":function() {
		if(!this._itemsLeft.length) return false;
		var item = this._itemsLeft.shift();
		if (this.legacy) {
			item = Zotero.Utilities.itemToLegacyExportFormat(item);
		}
		if (!item.attachments) {
			item.attachments = [];
		}
		if (!item.notes) {
			item.notes = [];
		}

		// convert single field creators to format expected by export
		if(item.creators) {
			for(var i=0; i<item.creators.length; i++) {
				var creator = item.creators[i];
				if(creator.name) {
					creator.lastName = creator.name;
					creator.firstName = "";
					delete creator.name;
					creator.fieldMode = 1;
				}
			}
		}
		
		item.itemID = this._itemID++;
		return item;
	},
	
	"nextCollection":function() {
		return false;
	}
}
ItemGetter.prototype.__defineGetter__("numItemsRemaining", function() { return this._itemsLeft.length });
