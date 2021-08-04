/*
	***** BEGIN LICENSE BLOCK *****
	
	Copyright © 2021 Corporation for Digital Scholarship
                     Vienna, Virginia, USA
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

Zotero.Schema = {
	/**
	 * This must be called before translation
	 * @param data - Zotero schema from https://github.com/zotero/zotero-schema or
	 * 		https://api.zotero.org/schema
	 */
	init(data) {
		// CSL type/field mappings used by Utilities.Item.itemFromCSLJSON()
		Zotero.Schema.CSL_TYPE_MAPPINGS = {};
		Zotero.Schema.CSL_TYPE_MAPPINGS_REVERSE = {};
		for (let cslType in data.csl.types) {
			for (let zoteroType of data.csl.types[cslType]) {
				Zotero.Schema.CSL_TYPE_MAPPINGS[zoteroType] = cslType;
			}
			Zotero.Schema.CSL_TYPE_MAPPINGS_REVERSE[cslType] = [...data.csl.types[cslType]];
		}
		Zotero.Schema.CSL_TEXT_MAPPINGS = data.csl.fields.text;
		Zotero.Schema.CSL_DATE_MAPPINGS = data.csl.fields.date;
		Zotero.Schema.CSL_NAME_MAPPINGS = data.csl.names;
		Zotero.Schema.CSL_FIELD_MAPPINGS_REVERSE = {};
		for (let cslField in data.csl.fields.text) {
			for (let zoteroField of data.csl.fields.text[cslField]) {
				Zotero.Schema.CSL_FIELD_MAPPINGS_REVERSE[zoteroField] = cslField;
			}
		}
		for (let cslField in data.csl.fields.date) {
			let zoteroField = data.csl.fields.date[cslField];
			Zotero.Schema.CSL_FIELD_MAPPINGS_REVERSE[zoteroField] = cslField;
		}
	}
};

if (typeof process === 'object' && process + '' === '[object process]'){
	module.exports = Zotero.Schema;
}
