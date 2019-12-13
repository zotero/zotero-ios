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

async function doTranslateWeb(url, cookies, encodedHtml, encodedTranslators) {
	const html = window.atob(encodedHtml);
	const doc = addLocationPropToDoc(new DOMParser().parseFromString(html, 'text/html'), url);
    const translatorData = JSON.parse(window.atob(encodedTranslators));

    if (translatorData) {
        Zotero.Translators.init(translatorData);
    }

	// Set up a translate instance
	const translate = new Zotero.Translate.Web();
	translate.setDocument(doc);
    if (cookies) {
        translate.setCookieSandbox(cookies);
    }

	// Get translators
	let translators;
	try {
		translators = await translate.getTranslators();
	} catch (e) {
		Zotero.logError(e);
		setResult(e);
		return;
	}

	if (!translators.length) {
		setResult(`No translators available for ${url}`);
        return;
	}

	// set handlers for translation
	translate.setHandler("select", (translate, item, callback) => {
		setResult("select handler called: "+ JSON.stringify(item));
		setTimeout(() => callback(item), 3000);
	});

	translate.setHandler("error", function(obj, err) {
		setResult(err);
		Zotero.logError(err);
	});

	let items = await translate.translate();
    printLog('Items: ' + items.length);
	setResult(JSON.stringify(items));
};

var globalLog = ""

function printLog(str) {
    globalLog += str + "<br>";
    document.querySelector('#logs').innerHTML = globalLog.toString();
}

function setResult(str) {
	document.querySelector('#result').innerHTML = str.toString();
}

function addLocationPropToDoc(doc, docURL) {
	docURL = new URL(docURL);
	docURL.toString = () => this.href;
	var wrappedDoc = new Proxy(doc, {
		get: function (t, prop) {
			if (prop === 'location') {
				return docURL;
			}
			else if (prop == 'evaluate') {
				// If you pass the document itself into doc.evaluate as the second argument
				// it fails, because it receives a proxy, which isn't of type `Node` for some reason.
				// Native code magic.
				return function() {
					if (arguments[1] == wrappedDoc) {
						arguments[1] = t;
					}
					return t.evaluate.apply(t, arguments)
				}
			}
			else {
				if (typeof t[prop] == 'function') {
					return t[prop].bind(t);
				}
				return t[prop];
			}
		}
	});
	return wrappedDoc;
};

window.addEventListener('DOMContentLoaded', function() {
	Zotero.Debug.init(1);
});
