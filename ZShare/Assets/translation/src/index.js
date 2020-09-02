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

async function translate(url, encodedHtml, encodedFrames, encodedTranslators) {
    // Set up translators
    const translatorData = JSON.parse(window.atob(encodedTranslators));
    if (translatorData) {
        Zotero.Translators.init(translatorData);
    }

    // Prepare a document
    const html = decodeURIComponent(escape(window.atob(encodedHtml)));
    const frames = JSON.parse(decodeURIComponent(escape(window.atob(encodedFrames))));
    const doc = prepareDoc(parseDoc(html, frames), url);

    // Set up a translate instance
    const translate = new Zotero.Translate.Web();
    translate.setDocument(doc);

    // Get translators
    var translators;
    try {
        translators = await translate.getTranslators();
    } catch (e) {
        Zotero.logError(e);
        return;
    }

    if (!translators.length) {
        Zotero.debug("No translators found!");
        window.webkit.messageHandlers.saveAsWebHandler.postMessage(0);
        return;
    }

    // Set handlers for translation
    translate.setHandler("select", (translate, item, callback) => {
        Zotero.Messaging.sendMessage(window.webkit.messageHandlers.itemSelectionHandler, Object.entries(item))
                        .then(callback, function(e) { throw (e); });
    });

    translate.setHandler("error", function(obj, err) {
        Zotero.debug(err);
    });

    // Try to get results from translator(s)
    while (translators.length > 0) {
        translator = translators.shift();

        window.webkit.messageHandlers.translationProgressHandler.postMessage("translating_with_" + translator.label);

        translate.setTranslator(translator);

        try {
            const items = await translate.translate();
            if (Array.isArray(items)) {
                window.webkit.messageHandlers.itemResponseHandler.postMessage(items);
                return;
            } else if (typeof items === 'object') {
                window.webkit.messageHandlers.itemResponseHandler.postMessage([items]);
                return;
            }
        } catch (e) {}
    }

    window.webkit.messageHandlers.saveAsWebHandler.postMessage(0);
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

function prepareDoc(doc, docURL) {
    // Add <base> if it doesn't exist, so relative URLs resolve
    if (!doc.getElementsByTagName('base').length) {
        let head = doc.head;
        let base = doc.createElement('base');
        base.href = docURL;
        head.appendChild(base);
    }

    // Add 'location' and 'evaluate'
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
