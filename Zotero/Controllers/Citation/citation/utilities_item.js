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

(function() {

// Various Utility functions related to Zotero, API, Translation Item formats
// and their conversion or field access.

var Utilities_Item = {
	PARTICLE_GIVEN_REGEXP: /^([^ ]+(?:\u02bb |\u2019 | |\' ) *)(.+)$/,
	PARTICLE_FAMILY_REGEXP: /^([^ ]+(?:\-|\u02bb|\u2019| |\') *)(.+)$/,
	
	/**
	 * Tests if an item type exists
	 *
	 * @param {String} type Item type
	 * @type Boolean
	 */
	itemTypeExists: function(type) {
		return !!Zotero.ItemTypes.getID(type);
	},

	/**
	 * Converts an item from toArray() format to citeproc-js JSON
	 * @param {Zotero.Item} zoteroItem
	 * @return {Object|Promise<Object>} A CSL item, or a promise for a CSL item if a Zotero.Item
	 *     is passed
	 */
	itemToCSLJSON: function(zoteroItem) {
		// If a Zotero.Item was passed, convert it to the proper format (skipping child items) and
		// call this function again with that object
		//
		// (Zotero.Item won't be defined in translation-server)
		if (typeof Zotero.Item !== 'undefined' && zoteroItem instanceof Zotero.Item) {
			return Utilities_Item.itemToCSLJSON(
				Zotero.Utilities.Internal.itemToExportFormat(zoteroItem, false, true)
			);
		}

		var cslType = Zotero.Schema.CSL_TYPE_MAPPINGS[zoteroItem.itemType];
		if (!cslType) {
			throw new Error('Unexpected Zotero Item type "' + zoteroItem.itemType + '"');
		}

		var itemTypeID = Zotero.ItemTypes.getID(zoteroItem.itemType);

		var cslItem = {
			'id':zoteroItem.uri,
			'type':cslType
		};

		// get all text variables (there must be a better way)
		for(var variable in Zotero.Schema.CSL_TEXT_MAPPINGS) {
			if (variable === "shortTitle") continue; // read both title-short and shortTitle, but write only title-short
			var fields = Zotero.Schema.CSL_TEXT_MAPPINGS[variable];
			for(var i=0, n=fields.length; i<n; i++) {
				var field = fields[i],
					value = null;

				if(field in zoteroItem) {
					value = zoteroItem[field];
				} else {
					if (field == 'versionNumber') field = 'version'; // Until https://github.com/zotero/zotero/issues/670
					var fieldID = Zotero.ItemFields.getID(field),
						typeFieldID;
					if(fieldID
						&& (typeFieldID = Zotero.ItemFields.getFieldIDFromTypeAndBase(itemTypeID, fieldID))
					) {
						value = zoteroItem[Zotero.ItemFields.getName(typeFieldID)];
					}
				}

				if (!value) continue;

				if (typeof value == 'string') {
					if (field == 'ISBN') {
						// Only use the first ISBN in CSL JSON
						var isbn = value.match(/^(?:97[89]-?)?(?:\d-?){9}[\dx](?!-)\b/i);
						if (isbn) value = isbn[0];
					}
					else if (field == 'extra') {
						value = Zotero.Utilities.Item.extraToCSL(value);
					}

					// Strip enclosing quotes
					if(value.charAt(0) == '"' && value.indexOf('"', 1) == value.length - 1) {
						value = value.substring(1, value.length-1);
					}
					cslItem[variable] = value;
					break;
				}
			}
		}

		// separate name variables
		if (zoteroItem.type != "attachment" && zoteroItem.type != "note") {
			var author = Zotero.CreatorTypes.getName(Zotero.CreatorTypes.getPrimaryIDForType(itemTypeID));
			var creators = zoteroItem.creators;
			for(var i=0; creators && i<creators.length; i++) {
				var creator = creators[i];
				var creatorType = creator.creatorType;
				if(creatorType == author) {
					creatorType = "author";
				}

				creatorType = Zotero.Schema.CSL_NAME_MAPPINGS[creatorType];
				if(!creatorType) continue;

				var nameObj;
				if (creator.lastName || creator.firstName) {
					nameObj = {
						family: creator.lastName || '',
						given: creator.firstName || ''
					};

					// Parse name particles
					// Replicate citeproc-js logic for what should be parsed so we don't
					// break current behavior.
					if (nameObj.family && nameObj.given) {
						// Don't parse if last name is quoted
						if (nameObj.family.length > 1
							&& nameObj.family.charAt(0) == '"'
							&& nameObj.family.charAt(nameObj.family.length - 1) == '"'
						) {
							nameObj.family = nameObj.family.substr(1, nameObj.family.length - 2);
						} else {
							Zotero.Utilities.Item.parseParticles(nameObj);
						}
					}
				} else if (creator.name) {
					nameObj = {'literal': creator.name};
				}

				if(cslItem[creatorType]) {
					cslItem[creatorType].push(nameObj);
				} else {
					cslItem[creatorType] = [nameObj];
				}
			}
		}

		// get date variables
		for(var variable in Zotero.Schema.CSL_DATE_MAPPINGS) {
			var date = zoteroItem[Zotero.Schema.CSL_DATE_MAPPINGS[variable]];
			if (!date) {
				var typeSpecificFieldID = Zotero.ItemFields.getFieldIDFromTypeAndBase(itemTypeID, Zotero.Schema.CSL_DATE_MAPPINGS[variable]);
				if (typeSpecificFieldID) {
					date = zoteroItem[Zotero.ItemFields.getName(typeSpecificFieldID)];
				}
			}

			if(date) {
				// Convert UTC timestamp to local timestamp for access date
				if (Zotero.Schema.CSL_DATE_MAPPINGS[variable] == 'accessDate' && !Zotero.Date.isSQLDate(date)) {
					// Accept ISO date
					if (Zotero.Date.isISODate(date)) {
						let d = Zotero.Date.isoToDate(date);
						date = Zotero.Date.dateToSQL(d, true);
					}
					let localDate = Zotero.Date.sqlToDate(date, true);
					date = Zotero.Date.dateToSQL(localDate);
				}
				var dateObj = Zotero.Date.strToDate(date);
				// otherwise, use date-parts
				var dateParts = [];
				if(dateObj.year) {
					// add year, month, and day, if they exist
					dateParts.push(dateObj.year);
					if(dateObj.month !== undefined) {
						// strToDate() returns a JS-style 0-indexed month, so we add 1 to it
						dateParts.push(dateObj.month+1);
						if(dateObj.day) {
							dateParts.push(dateObj.day);
						}
					}
					cslItem[variable] = {"date-parts":[dateParts]};

					// if no month, use season as month
					if(dateObj.part && dateObj.month === undefined) {
						cslItem[variable].season = dateObj.part;
					}
				} else {
					// if no year, pass date literally
					cslItem[variable] = {"literal":date};
				}
			}
		}

		// Special mapping for note title
		if (zoteroItem.itemType == 'note' && zoteroItem.note) {
			cslItem.title = Zotero.Utilities.Item.noteToTitle(zoteroItem.note);
		}

		//this._cache[zoteroItem.id] = cslItem;
		return cslItem;
	},

	/**
	 * Converts an item in CSL JSON format to a Zotero item
	 * @param {Zotero.Item} item
	 * @param {Object} cslItem
	 */
	itemFromCSLJSON: function(item, cslItem) {
		var isZoteroItem = !!item.setType,
			zoteroType;

		if (!cslItem.type) {
			Zotero.debug(cslItem, 1);
			throw new Error("No 'type' provided in CSL-JSON");
		}

		// Some special cases to help us map item types correctly
		// This ensures that we don't lose data on import. The fields
		// we check are incompatible with the alternative item types
		if (cslItem.type == 'bill' && (cslItem.publisher || cslItem['number-of-volumes'])) {
			zoteroType = 'hearing';
		}
		else if (cslItem.type == 'broadcast'
			&& (cslItem['archive']
				|| cslItem['archive_location']
				|| cslItem['container-title']
				|| cslItem['event-place']
				|| cslItem['publisher']
				|| cslItem['publisher-place']
				|| cslItem['source'])) {
			zoteroType = 'tvBroadcast';
		}
		else if (cslItem.type == 'book' && cslItem.version) {
			zoteroType = 'computerProgram';
		}
		else if (cslItem.type == 'song' && cslItem.number) {
			zoteroType = 'podcast';
		}
		else if (cslItem.type == 'motion_picture'
			&& (cslItem['collection-title'] || cslItem['publisher-place']
				|| cslItem['event-place'] || cslItem.volume
				|| cslItem['number-of-volumes'] || cslItem.ISBN)) {
			zoteroType = 'videoRecording';
		}
		else if (Zotero.Schema.CSL_TYPE_MAPPINGS_REVERSE[cslItem.type]) {
			zoteroType = Zotero.Schema.CSL_TYPE_MAPPINGS_REVERSE[cslItem.type][0];
		}
		else {
			Zotero.debug(`Unknown CSL type '${cslItem.type}' -- using 'document'`, 2);
			zoteroType = "document"
		}

		var itemTypeID = Zotero.ItemTypes.getID(zoteroType);
		if(isZoteroItem) {
			item.setType(itemTypeID);
		} else {
			item.itemID = cslItem.id;
			item.itemType = zoteroType;
		}

		// map text fields
		for (let variable in Zotero.Schema.CSL_TEXT_MAPPINGS) {
			if(variable in cslItem) {
				let textMappings = Zotero.Schema.CSL_TEXT_MAPPINGS[variable];
				for(var i=0; i<textMappings.length; i++) {
					var field = textMappings[i];
					var fieldID = Zotero.ItemFields.getID(field);

					if(Zotero.ItemFields.isBaseField(fieldID)) {
						var newFieldID = Zotero.ItemFields.getFieldIDFromTypeAndBase(itemTypeID, fieldID);
						if(newFieldID) fieldID = newFieldID;
					}

					if(Zotero.ItemFields.isValidForType(fieldID, itemTypeID)) {
						// TODO: Convert restrictive Extra cheater syntax ('original-date: 2018')
						// to nicer format we allow ('Original Date: 2018'), unless we've added
						// those fields before we get to that
						if(isZoteroItem) {
							item.setField(fieldID, cslItem[variable]);
						} else {
							item[field] = cslItem[variable];
						}

						break;
					}
				}
			}
		}

		// separate name variables
		for (let field in Zotero.Schema.CSL_NAME_MAPPINGS) {
			if (Zotero.Schema.CSL_NAME_MAPPINGS[field] in cslItem) {
				var creatorTypeID = Zotero.CreatorTypes.getID(field);
				if(!Zotero.CreatorTypes.isValidForItemType(creatorTypeID, itemTypeID)) {
					creatorTypeID = Zotero.CreatorTypes.getPrimaryIDForType(itemTypeID);
				}

				let nameMappings = cslItem[Zotero.Schema.CSL_NAME_MAPPINGS[field]];
				for(var i in nameMappings) {
					var cslAuthor = nameMappings[i];
					let creator = {};
					if(cslAuthor.family || cslAuthor.given) {
						creator.lastName = cslAuthor.family || '';
						creator.firstName = cslAuthor.given || '';
					} else if(cslAuthor.literal) {
						creator.lastName = cslAuthor.literal;
						creator.fieldMode = 1;
					} else {
						continue;
					}
					creator.creatorTypeID = creatorTypeID;

					if(isZoteroItem) {
						item.setCreator(item.getCreators().length, creator);
					} else {
						creator.creatorType = Zotero.CreatorTypes.getName(creatorTypeID);
						if (Zotero.isFx && !Zotero.isBookmarklet) {
							creator = Components.utils.cloneInto(creator, item);
						}
						item.creators.push(creator);
					}
				}
			}
		}

		// get date variables
		for (let variable in Zotero.Schema.CSL_DATE_MAPPINGS) {
			if(variable in cslItem) {
				let field = Zotero.Schema.CSL_DATE_MAPPINGS[variable];
				let fieldID = Zotero.ItemFields.getID(field);
				let cslDate = cslItem[variable];
				if(Zotero.ItemFields.isBaseField(fieldID)) {
					var newFieldID = Zotero.ItemFields.getFieldIDFromTypeAndBase(itemTypeID, fieldID);
					if(newFieldID) fieldID = newFieldID;
				}

				if(Zotero.ItemFields.isValidForType(fieldID, itemTypeID)) {
					var date = "";
					if(cslDate.literal || cslDate.raw) {
						date = cslDate.literal || cslDate.raw;
						if(variable === "accessed") {
							date = Zotero.Date.strToISO(date);
						}
					} else {
						var newDate = Zotero.Utilities.deepCopy(cslDate);
						if(cslDate["date-parts"] && typeof cslDate["date-parts"] === "object"
							&& cslDate["date-parts"] !== null
							&& typeof cslDate["date-parts"][0] === "object"
							&& cslDate["date-parts"][0] !== null) {
							if(cslDate["date-parts"][0][0]) newDate.year = cslDate["date-parts"][0][0];
							if(cslDate["date-parts"][0][1]) newDate.month = cslDate["date-parts"][0][1];
							if(cslDate["date-parts"][0][2]) newDate.day = cslDate["date-parts"][0][2];
						}

						if(newDate.year) {
							if(variable === "accessed") {
								// Need to convert to SQL
								var date = Zotero.Utilities.lpad(newDate.year, "0", 4);
								if(newDate.month) {
									date += "-"+Zotero.Utilities.lpad(newDate.month, "0", 2);
									if(newDate.day) {
										date += "-"+Zotero.Utilities.lpad(newDate.day, "0", 2);
									}
								}
							} else {
								if(newDate.month) newDate.month--;
								date = Zotero.Date.formatDate(newDate);
								if(newDate.season) {
									date = newDate.season+" "+date;
								}
							}
						}
					}

					if(isZoteroItem) {
						item.setField(fieldID, date);
					} else {
						item[field] = date;
					}
				}
			}
		}
	},

	/**
	 * Given API JSON for an item, return the best single first creator, regardless of creator order
	 *
	 * Note that this is just a single creator, not the firstCreator field return from the
	 * Zotero.Item::firstCreator property or Zotero.Items.getFirstCreatorFromData()
	 *
	 * @return {Object|false} - Creator in API JSON format, or false
	 */
	getFirstCreatorFromItemJSON: function (json) {
		var primaryCreatorType = Zotero.CreatorTypes.getName(
			Zotero.CreatorTypes.getPrimaryIDForType(
				Zotero.ItemTypes.getID(json.itemType)
			)
		);
		let firstCreator = json.creators.find(creator => {
			return creator.creatorType == primaryCreatorType || creator.creatorType == 'author';
		});
		if (!firstCreator) {
			firstCreator = json.creators.find(creator => creator.creatorType == 'editor');
		}
		if (!firstCreator) {
			return false;
		}
		return firstCreator;
	},

	/**
	* Taken from citeproc-js. Extracts particles (e.g. de, von, etc.) from family name and given name.
	* 
	* Copyright (c) 2009-2019 Frank Bennett
	*	This program is free software: you can redistribute it and/or
	*	modify it under EITHER
	*
	*	 * the terms of the Common Public Attribution License (CPAL) as
	*		published by the Open Source Initiative, either version 1 of
	*		the CPAL, or (at your option) any later version; OR
	*
	*	 * the terms of the GNU Affero General Public License (AGPL)
	*		as published by the Free Software Foundation, either version
	*		3 of the AGPL, or (at your option) any later version.
	*
	*	This program is distributed in the hope that it will be useful,
	*	but WITHOUT ANY WARRANTY; without even the implied warranty of
	*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	*	Affero General Public License for more details.
	*
	*	You should have received copies of the Common Public Attribution
	*	License and of the GNU Affero General Public License along with
	*	this program.  If not, see <https://opensource.org/licenses/> or
	*	<http://www.gnu.org/licenses/> respectively.
	*/
	parseParticles: function (nameObj) {
		function splitParticles(nameValue, firstNameFlag, caseOverride) {
			// Parse particles out from name fields.
			// * nameValue (string) is the field content to be parsed.
			// * firstNameFlag (boolean) parse trailing particles
			//	 (default is to parse leading particles)
			// * caseOverride (boolean) include all but one word in particle set
			//	 (default is to include only words with lowercase first char)
			//   [caseOverride is not used in this application]
			// Returns an array with:
			// * (boolean) flag indicating whether a particle was found
			// * (string) the name after removal of particles
			// * (array) the list of particles found
			var origNameValue = nameValue;
			nameValue = caseOverride ? nameValue.toLowerCase() : nameValue;
			var particleList = [];
			var rex;
			var hasParticle;
			if (firstNameFlag) {
				nameValue = nameValue.split("").reverse().join("");
				rex = Utilities_Item.PARTICLE_GIVEN_REGEXP;
			} else {
				rex = Utilities_Item.PARTICLE_FAMILY_REGEXP;
			}
			var m = nameValue.match(rex);
			while (m) {
				var m1 = firstNameFlag ? m[1].split("").reverse().join("") : m[1];
				var firstChar = m ? m1 : false;
				var firstChar = firstChar ? m1.replace(/^[-\'\u02bb\u2019\s]*(.).*$/, "$1") : false;
				hasParticle = firstChar ? firstChar.toUpperCase() !== firstChar : false;
				if (!hasParticle) {
					break;
				}
				if (firstNameFlag) {
					particleList.push(origNameValue.slice(m1.length * -1));
					origNameValue = origNameValue.slice(0,m1.length * -1);
				} else {
					particleList.push(origNameValue.slice(0,m1.length));
					origNameValue = origNameValue.slice(m1.length);
				}
				//particleList.push(m1);
				nameValue = m[2];
				m = nameValue.match(rex);
			}
			if (firstNameFlag) {
				nameValue = nameValue.split("").reverse().join("");
				particleList.reverse();
				for (var i=1,ilen=particleList.length;i<ilen;i++) {
					if (particleList[i].slice(0, 1) == " ") {
						particleList[i-1] += " ";
					}
				}
				for (var i=0,ilen=particleList.length;i<ilen;i++) {
					if (particleList[i].slice(0, 1) == " ") {
						particleList[i] = particleList[i].slice(1);
					}
				}
				nameValue = origNameValue.slice(0, nameValue.length);
			} else {
				nameValue = origNameValue.slice(nameValue.length * -1);
			}
			return [hasParticle, nameValue, particleList];
		}
		function trimLast(str) {
			var lastChar = str.slice(-1);
			str = str.trim();
			if (lastChar === " " && ["\'", "\u2019"].indexOf(str.slice(-1)) > -1) {
				str += " ";
			}
			return str;
		}
		function parseSuffix(nameObj) {
			if (!nameObj.suffix && nameObj.given) {
				var m = nameObj.given.match(/(\s*,!*\s*)/);
				if (m) {
					var idx = nameObj.given.indexOf(m[1]);
					var possible_suffix = nameObj.given.slice(idx + m[1].length);
					var possible_comma = nameObj.given.slice(idx, idx + m[1].length).replace(/\s*/g, "");
					if (possible_suffix.replace(/\./g, "") === 'et al' && !nameObj["dropping-particle"]) {
						// This hack covers the case where "et al." is explicitly used in the
						// authorship information of the work.
						nameObj["dropping-particle"] = possible_suffix;
						nameObj["comma-dropping-particle"] = ",";
					} else {
						if (possible_comma.length === 2) {
							nameObj["comma-suffix"] = true;
						}
						nameObj.suffix = possible_suffix;
					}
					nameObj.given = nameObj.given.slice(0, idx);
				}
			}
		}
		// Extract and set non-dropping particle(s) from family name field
		var res = splitParticles(nameObj.family);
		var lastNameValue = res[1];
		var lastParticleList = res[2];
		nameObj.family = lastNameValue;
		var nonDroppingParticle = trimLast(lastParticleList.join(""));
		if (nonDroppingParticle) {
			nameObj['non-dropping-particle'] = nonDroppingParticle;
		}
		// Split off suffix first of all
		parseSuffix(nameObj);
		// Extract and set dropping particle(s) from given name field
		var res = splitParticles(nameObj.given, true);
		var firstNameValue = res[1];
		var firstParticleList = res[2];
		nameObj.given = firstNameValue;
		var droppingParticle = firstParticleList.join("").trim();
		if (droppingParticle) {
			nameObj['dropping-particle'] = droppingParticle;
		}
	},

	/**
	 * Return first line (or first MAX_LENGTH characters) of note content
	 **/
	noteToTitle: function(text) {
		var origText = text;
		text = text.trim();
		text = text.replace(/<br\s*\/?>/g, ' ');
		text = Zotero.Utilities.unescapeHTML(text);

		// If first line is just an opening HTML tag, remove it
		//
		// Example:
		//
		// <blockquote>
		// <p>Foo</p>
		// </blockquote>
		if (/^<[^>\n]+[^\/]>\n/.test(origText)) {
			text = text.trim();
		}

		var max = this.MAX_TITLE_LENGTH;

		var t = text.substring(0, max);
		var ln = t.indexOf("\n");
		if (ln>-1 && ln<max) {
			t = t.substring(0, ln);
		}
		return t;
	},

	/**
	 * Preprocess Zotero item extra field for passing to citeproc-js for extra CSL properties
	 * @param extra
	 * @returns {String|string|void|*}
	 */
	extraToCSL: function (extra) {
		return extra.replace(/^([A-Za-z \-]+)(:\s*.+)/gm, function (_, field, value) {
			var originalField = field;
			field = field.toLowerCase().replace(/ /g, '-');
			// Fields from https://aurimasv.github.io/z2csl/typeMap.xml
			switch (field) {
				// Standard fields
			case 'abstract':
			case 'accessed':
			case 'annote':
			case 'archive':
			case 'archive-place':
			case 'author':
			case 'authority':
			case 'call-number':
			case 'chapter-number':
			case 'citation-label':
			case 'citation-number':
			case 'collection-editor':
			case 'collection-number':
			case 'collection-title':
			case 'composer':
			case 'container':
			case 'container-author':
			case 'container-title':
			case 'container-title-short':
			case 'dimensions':
			case 'director':
			case 'edition':
			case 'editor':
			case 'editorial-director':
			case 'event':
			case 'event-date':
			case 'event-place':
			case 'first-reference-note-number':
			case 'genre':
			case 'illustrator':
			case 'interviewer':
			case 'issue':
			case 'issued':
			case 'jurisdiction':
			case 'keyword':
			case 'language':
			case 'locator':
			case 'medium':
			case 'note':
			case 'number':
			case 'number-of-pages':
			case 'number-of-volumes':
			case 'original-author':
			case 'original-date':
			case 'original-publisher':
			case 'original-publisher-place':
			case 'original-title':
			case 'page':
			case 'page-first':
			case 'publisher':
			case 'publisher-place':
			case 'recipient':
			case 'references':
			case 'reviewed-author':
			case 'reviewed-title':
			case 'scale':
			case 'section':
			case 'source':
			case 'status':
			case 'submitted':
			case 'title':
			case 'title-short':
			case 'translator':
			case 'type':
			case 'version':
			case 'volume':
			case 'year-suffix':
				break;

				// Uppercase fields
			case 'doi':
			case 'isbn':
			case 'issn':
			case 'pmcid':
			case 'pmid':
			case 'url':
				field = field.toUpperCase();
				break;

				// Weirdo
			case 'archive-location':
				field = 'archive_location';
				break;

			default:
				// See if this is a Zotero field written out (e.g., "Publication Title"), and if so
				// convert to its associated CSL field
				var zoteroField = originalField.replace(/ ([A-Z])/, '$1');
				// If second character is lowercase (so not an acronym), lowercase first letter too
				if (zoteroField[1] && zoteroField[1] == zoteroField[1].toLowerCase()) {
					zoteroField = zoteroField[0].toLowerCase() + zoteroField.substr(1);
				}
				if (Zotero.Schema.CSL_FIELD_MAPPINGS_REVERSE[zoteroField]) {
					field = Zotero.Schema.CSL_FIELD_MAPPINGS_REVERSE[zoteroField];
				}
				// Don't change other lines
				else {
					field = originalField;
				}
			}
			return field + value;
		});
	},

	/**
	 * Converts an item from toArray() format to an array of items in
	 * the content=json format used by the server
	 *
	 * (for origin see: https://github.com/zotero/zotero/blob/56f9f043/chrome/content/zotero/xpcom/utilities.js#L1526-L1526)
	 *
	 */
	itemToAPIJSON: function(item) {
		var newItem = {
				key: Zotero.Utilities.generateObjectKey(),
				version: 0
			},
			newItems = [newItem];

		var typeID = Zotero.ItemTypes.getID(item.itemType);
		if(!typeID) {
			Zotero.debug(`itemToAPIJSON: Invalid itemType ${item.itemType}; using webpage`);
			item.itemType = "webpage";
			typeID = Zotero.ItemTypes.getID(item.itemType);
		}

		var accessDateFieldID = Zotero.ItemFields.getID('accessDate');

		var fieldID, itemFieldID;
		for(var field in item) {
			if(field === "complete" || field === "itemID" || field === "attachments"
				|| field === "seeAlso") continue;

			var val = item[field];

			if(field === "itemType") {
				newItem[field] = val;
			} else if(field === "creators") {
				// normalize creators
				var n = val.length;
				var newCreators = newItem.creators = [];
				for(var j=0; j<n; j++) {
					var creator = val[j];

					if(!creator.firstName && !creator.lastName) {
						Zotero.debug("itemToAPIJSON: Silently dropping empty creator");
						continue;
					}

					// Single-field mode
					if (!creator.firstName || (creator.fieldMode && creator.fieldMode == 1)) {
						var newCreator = {
							name: creator.lastName
						};
					}
					// Two-field mode
					else {
						var newCreator = {
							firstName: creator.firstName,
							lastName: creator.lastName
						};
					}

					// ensure creatorType is present and valid
					if(creator.creatorType) {
						if(Zotero.CreatorTypes.getID(creator.creatorType)) {
							newCreator.creatorType = creator.creatorType;
						} else {
							Zotero.debug(`itemToAPIJSON: Invalid creator type ${creator.creatorType}; `
								+ "falling back to author");
						}
					}
					if(!newCreator.creatorType) newCreator.creatorType = "author";

					newCreators.push(newCreator);
				}
			} else if(field === "tags") {
				// normalize tags
				var n = val.length;
				var newTags = newItem.tags = [];
				for(var j=0; j<n; j++) {
					var tag = val[j];
					if(typeof tag === "object") {
						if(tag.tag) {
							tag = tag.tag;
						} else if(tag.name) {
							tag = tag.name;
						} else {
							Zotero.debug("itemToAPIJSON: Discarded invalid tag");
							continue;
						}
					} else if(tag === "") {
						continue;
					}
					newTags.push({"tag":tag.toString(), "type":1});
				}
			} else if(field === "notes") {
				// normalize notes
				var n = val.length;
				for(var j=0; j<n; j++) {
					var note = val[j];
					if(typeof note === "object") {
						if(!note.note) {
							Zotero.debug("itemToAPIJSON: Discarded invalid note");
							continue;
						}
						note = note.note;
					}
					newItems.push({
						itemType: "note",
						parentItem: newItem.key,
						note: note.toString()
					});
				}
			} else if((fieldID = Zotero.ItemFields.getID(field))) {
				// if content is not a string, either stringify it or delete it
				if(typeof val !== "string") {
					if(val || val === 0) {
						val = val.toString();
					} else {
						continue;
					}
				}

				// map from base field if possible
				if((itemFieldID = Zotero.ItemFields.getFieldIDFromTypeAndBase(typeID, fieldID))) {
					let fieldName = Zotero.ItemFields.getName(itemFieldID);
					// Only map if item field does not exist
					if(fieldName !== field && !newItem[fieldName]) newItem[fieldName] = val;
					continue;	// already know this is valid
				}

				// if field is valid for this type, set field
				if(Zotero.ItemFields.isValidForType(fieldID, typeID)) {
					// Convert access date placeholder to current time
					if (fieldID == accessDateFieldID && val == "CURRENT_TIMESTAMP") {
						val = Zotero.Date.dateToISO(new Date());
					}

					newItem[field] = val;
				} else {
					Zotero.debug(`itemToAPIJSON: Discarded field ${field}: `
						+ `field not valid for type ${item.itemType}`, 3);
				}
			} else {
				Zotero.debug(`itemToAPIJSON: Discarded unknown field ${field}`, 3);
			}
		}

		return newItems;
	},

	/**
	 * Converts a current Zotero Item to a format that export translators written for Zotero versions pre-4.0.26
	 * See https://github.com/zotero/translation-server/issues/73
	 * @param {Object} item
	 * @returns {Object}
	 */
	itemToLegacyExportFormat: function(item) {
		item.uniqueFields = {};

		// Map base fields
		for (let field in item) {
			try {
				var baseField = Zotero.ItemFields.getName(
					Zotero.ItemFields.getBaseIDFromTypeAndField(item.itemType, field)
				);
			} catch (e) {
				continue;
			}

			if (!baseField || baseField == field) {
				item.uniqueFields[field] = item[field];
			} else {
				item[baseField] = item[field];
				item.uniqueFields[baseField] = item[field];
			}
		}

		// Meaningless local item ID, but some older export translators depend on it
		item.itemID = Zotero.Utilities.randomString(6);
		item.key = Zotero.Utilities.randomString(6); // CSV translator exports this

		// "version" is expected to be a field for "computerProgram", which is now
		// called "versionNumber"
		delete item.version;
		if (item.versionNumber) {
			item.version = item.uniqueFields.version = item.versionNumber;
			delete item.versionNumber;
		}

		// Creators
		if (item.creators) {
			for (let i=0; i<item.creators.length; i++) {
				let creator = item.creators[i];

				if (creator.name) {
					creator.fieldMode = 1;
					creator.lastName = creator.name;
					delete creator.name;
				}

				// Old format used to supply creatorID (the database ID), but no
				// translator ever used it
			}
		}
		else {
			item.creators = [];
		}

		item.sourceItemKey = item.parentItem;

		// Tags
		if (item.tags) {
			for (let i = 0; i < item.tags.length; i++) {
				if (!item.tags[i].type) {
					item.tags[i].type = 0;
				}
				// No translator ever used "primary", "fields", or "linkedItems" objects
			}
		}
		else {
			item.tags = [];
		}

		// seeAlso was always present, but it was always an empty array.
		// Zotero RDF translator pretended to use it
		item.seeAlso = [];

		if (item.contentType) {
			item.mimeType = item.uniqueFields.mimeType = item.contentType;
		}

		if (item.note) {
			item.uniqueFields.note = item.note;
		}

		return item;
	}
}

if (typeof module != 'undefined') {
	module.exports = Utilities_Item;
} else if (typeof Zotero != 'undefined' && typeof Zotero.Utilities != 'undefined') {
	Zotero.Utilities.Item = Utilities_Item;
} else {
	console.log('Could not find a way to expose utilities_item.js. Check your load order.')
}

})();
