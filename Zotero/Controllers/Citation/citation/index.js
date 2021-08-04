var Zotero = {};

async function getCit(encodedItemsCsl, encodedItemsData, encodedStyleXml, localeId, encodedLocaleXml, format, messageId) {
    const styleXml = decodeURIComponent(escape(window.atob(encodedStyleXml)));
    const localeXml = decodeURIComponent(escape(window.atob(encodedLocaleXml)));
    const itemsData = JSON.parse(window.atob(encodedItemsData));
    const itemsCsl = JSON.parse(window.atob(encodedItemsCsl));
    const citation = getCitation(itemsData, itemsCsl, styleXml, localeXml, localeId, format);
    window.webkit.messageHandlers.citationHandler.postMessage({result: citation, id: messageId});
};

async function getBib(encodedItemsCsl, encodedStyleXml, localeId, encodedLocaleXml, format, messageId) {
    const styleXml = decodeURIComponent(escape(window.atob(encodedStyleXml)));
    const localeXml = decodeURIComponent(escape(window.atob(encodedLocaleXml)));
    const itemsCsl = JSON.parse(window.atob(encodedItemsCsl));
    const bibliography = getBibliography(itemsCsl, styleXml, localeXml, localeId, format);
    window.webkit.messageHandlers.bibliographyHandler.postMessage({result: bibliography, id: messageId});
};

async function convertItemsToCSL(encodedItemsJson, encodedSchemaJson, messageId) {
    let schemaJson = JSON.parse(window.atob(encodedSchemaJson));
    Zotero.Schema.init(schemaJson);

    var itemsJson = JSON.parse(window.atob(encodedItemsJson));
    let csls = itemsJson.map(Zotero.Utilities.Item.itemToCSLJSON);
    window.webkit.messageHandlers.cslHandler.postMessage({result: csls, id: messageId});
};
