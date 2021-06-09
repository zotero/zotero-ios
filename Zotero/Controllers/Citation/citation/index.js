async function getCitation() {
    const styleId = 'modern-language-association'; //e.g. nature, apa, turabian-fullnote-bibliography, any from www.zotero.org/styles
    const lang = 'en-GB'; // e.g. en-US, pl-PL, de-DE, any from https://github.com/citation-style-language/locales
    const styleXML = await (await fetch(`https://www.zotero.org/styles/${styleId}`)).text();
    const localeXML = await (await fetch(`https://cdn.githubraw.com/citation-style-language/locales/bd8d2dbc/locales-${lang}.xml`)).text();
    const itemsCSL = JSON.parse(document.getElementById('items-csl').innerText);
    const bibliography = getBibliography(itemsCSL, styleXML, localeXML, lang, 'html');
    const citation1 = getCitation([itemsCSL[0].id, itemsCSL[1].id], itemsCSL, styleXML, localeXML, lang, 'html');
    const citation2 = getCitation([itemsCSL[2].id], itemsCSL, styleXML, localeXML, lang, 'html');
    window.webkit.messageHandlers.citationHandler.postMessage(citation1);
};