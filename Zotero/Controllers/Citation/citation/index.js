async function getCit(encodedStyleXml, localeId, encodedLocaleXml, format) {
    const styleXml = decodeURIComponent(escape(window.atob(encodedStyleXml)));
    const localeXml = decodeURIComponent(escape(window.atob(encodedLocaleXml)));
    // TODO: - convert Zotero item json to citeproc js
    const itemsCsl = JSON.parse(document.getElementById('items-csl').innerText);
    const citation = getCitation([itemsCsl[0].id, itemsCsl[1].id], itemsCsl, styleXml, localeXml, localeId, format);
    window.webkit.messageHandlers.citationHandler.postMessage(citation);
};

async function getBib(encodedStyleXml, localeId, encodedLocaleXml, format) {
    const styleXml = decodeURIComponent(escape(window.atob(encodedStyleXml)));
    const localeXml = decodeURIComponent(escape(window.atob(encodedLocaleXml)));
    // TODO: - convert Zotero item json to citeproc js
    const itemsCsl = JSON.parse(document.getElementById('items-csl').innerText);
    const bibliography = getBibliography(itemsCsl, styleXml, localeXml, localeId, format);
    window.webkit.messageHandlers.bibliographyHandler.postMessage(bibliography);
};
