/*
	***** BEGIN LICENSE BLOCK *****
	
	Copyright © 2019 Center for History and New Media
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

function initTranslators(encodedTranslators) {
    const translatorData = JSON.parse(decodeBase64(encodedTranslators));
    if (translatorData) {
        Zotero.debug("Init translators");
        Zotero.Translators.init(translatorData);
    }
}

function initSchemaAndDateFormats(encodedSchema, encodedDateFormats) {
    const schemaData = JSON.parse(decodeBase64(encodedSchema));
    if (schemaData) {
        Zotero.debug("Init schema");
        Zotero.Schema.init(schemaData);
    }

    const dateFormats = JSON.parse(decodeBase64(encodedDateFormats));
    if (dateFormats) {
        Zotero.debug("Init date formats");
        Zotero.Date.init(dateFormats);
    }
}

async function lookup(encodedIdentifiers) {
    // Get identifiers
    Zotero.debug("Parse identifiers");

    const identifiersInput = decodeBase64(encodedIdentifiers);
    const identifiers = Zotero.Utilities.extractIdentifiers(identifiersInput);

    Zotero.debug("Extracted identifiers: " + JSON.stringify(identifiers));

    // Go through all identifiers

    var newItems = false;

    await Zotero.Promise.all(identifiers.map(async (identifier) => {
        Zotero.debug("Process identifier " + identifier);

        // Set up a translate instance
        var translate = new Zotero.Translate.Search();
        translate.setIdentifier(identifier);

        try {
            // Get translators
            var translators = await translate.getTranslators();
            translate.setTranslator(translators);

            // Get items
            newItems = await translate.translate({ libraryID: false });
        } catch (e) {
            // Continue with other ids on failure
            Zotero.logError(e);
        }
    }));

    if (newItems) {
        window.webkit.messageHandlers.itemsHandler.postMessage(newItems);
    } else {
        window.webkit.messageHandlers.failureHandler.postMessage(0);
    }
};

function parseDoc(html, frames) {
    var parsedDoc = new DOMParser().parseFromString(html, 'text/html')
    const allFrames = parsedDoc.querySelectorAll('iframe, frame');

    if (allFrames.length != frames.length) {
        Zotero.debug("Document frames count (" + allFrames.length + ") and parameter frames (" + frames.length + ") count do not match!");
    } else {
        for (var idx = 0; idx < allFrames.length; idx++) {
            const frameHtml = frames[idx];
            if (frameHtml === "") {
                continue;
            }
            allFrames[idx].innerHTML = frameHtml;
        }
    }

    return parsedDoc;
}

function decodeBase64(base64) {
    const text = atob(base64);
    const length = text.length;
    const bytes = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
        bytes[i] = text.charCodeAt(i);
    }
    const decoder = new TextDecoder();
    return decoder.decode(bytes);
}

window.addEventListener('DOMContentLoaded', function() {
    Zotero.Debug.init(1);
});
