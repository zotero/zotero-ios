var Zotero = {};

async function getCit(encodedItemsCsl, encodedItemsData, encodedStyleXml, localeId, encodedLocaleXml, format, messageId) {
    const styleXml = decodeBase64(encodedStyleXml);
    const localeXml = decodeBase64(encodedLocaleXml);
    const itemsData = JSON.parse(decodeBase64(encodedItemsData));
    const itemsCsl = JSON.parse(decodeBase64(encodedItemsCsl));
    const citation = getCitation(itemsData, itemsCsl, styleXml, localeXml, localeId, format);
    document.body.innerHTML = citation;
    window.webkit.messageHandlers.heightHandler.postMessage(document.body.scrollHeight);
    window.webkit.messageHandlers.citationHandler.postMessage({result: citation, id: messageId});
};

async function getBib(encodedItemsCsl, encodedStyleXml, localeId, encodedLocaleXml, format, messageId) {
    const styleXml = decodeBase64(encodedStyleXml);
    const localeXml = decodeBase64(encodedLocaleXml);
    const itemsCsl = JSON.parse(decodeBase64(encodedItemsCsl));
    const bibliography = getBibliography(itemsCsl, styleXml, localeXml, localeId, format);
    window.webkit.messageHandlers.bibliographyHandler.postMessage({result: bibliography, id: messageId});
};

async function convertItemsToCSL(encodedItemsJson, encodedSchemaJson, messageId) {
    let schemaJson = JSON.parse(decodeBase64(encodedSchemaJson));
    Zotero.Schema.init(schemaJson);

    var itemsJson = JSON.parse(decodeBase64(encodedItemsJson));
    let csls = itemsJson.map(Zotero.Utilities.Item.itemToCSLJSON);
    window.webkit.messageHandlers.cslHandler.postMessage({result: csls, id: messageId});
};

function decodeBase64(base64) {
    const text = window.atob(base64);
    const length = text.length;
    const bytes = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
        bytes[i] = text.charCodeAt(i);
    }
    const decoder = new TextDecoder();
    return decoder.decode(bytes);
}
