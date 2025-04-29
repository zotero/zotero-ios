(function webpackUniversalModuleDefinition(root, factory) {
	if(typeof exports === 'object' && typeof module === 'object')
		module.exports = factory();
	else if(typeof define === 'function' && define.amd)
		define("view", [], factory);
	else if(typeof exports === 'object')
		exports["view"] = factory();
	else
		root["view"] = factory();
})(self, () => {
return /******/ (() => { // webpackBootstrap
/******/ 	"use strict";
/******/ 	// The require scope
/******/ 	var __webpack_require__ = {};
/******/ 	
/************************************************************************/
/******/ 	/* webpack/runtime/define property getters */
/******/ 	(() => {
/******/ 		// define getter functions for harmony exports
/******/ 		__webpack_require__.d = (exports, definition) => {
/******/ 			for(var key in definition) {
/******/ 				if(__webpack_require__.o(definition, key) && !__webpack_require__.o(exports, key)) {
/******/ 					Object.defineProperty(exports, key, { enumerable: true, get: definition[key] });
/******/ 				}
/******/ 			}
/******/ 		};
/******/ 	})();
/******/ 	
/******/ 	/* webpack/runtime/hasOwnProperty shorthand */
/******/ 	(() => {
/******/ 		__webpack_require__.o = (obj, prop) => (Object.prototype.hasOwnProperty.call(obj, prop))
/******/ 	})();
/******/ 	
/************************************************************************/
var __webpack_exports__ = {};
/* unused harmony export executeSearch */
onmessage = async (event) => {
    let { context, term, options } = event.data;
    postMessage(executeSearch(context, term, options));
};
function executeSearch(context, term, options) {
    if (!term) {
        return [];
    }
    let { text, internalCharDataRanges } = context;
    let ranges = [];
    // https://stackoverflow.com/a/6969486
    let termRe = normalize(term).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (options.entireWord) {
        termRe = '\\b' + termRe + '\\b';
    }
    let re = new RegExp(termRe, 'g' + (options.caseSensitive ? '' : 'i'));
    let matches;
    while ((matches = re.exec(text))) {
        let [match] = matches;
        let { charDataID: startCharDataID, start: startOffset } = binarySearch(internalCharDataRanges, matches.index);
        let { charDataID: endCharDataID, start: endOffset } = binarySearch(internalCharDataRanges, matches.index + match.length);
        ranges.push({
            startCharDataID,
            startIndex: matches.index - startOffset,
            endCharDataID,
            endIndex: matches.index + match.length - endOffset,
        });
    }
    return ranges;
}
function normalize(s) {
    return s
        // Remove smart quotes
        .replace(/[\u2018\u2019]/g, "'")
        .replace(/[\u201C\u201D]/g, '"');
}
function binarySearch(charDataRanges, pos) {
    let left = 0;
    let right = charDataRanges.length - 1;
    while (left <= right) {
        let mid = Math.floor((left + right) / 2);
        if (charDataRanges[mid].start <= pos && pos <= charDataRanges[mid].end) {
            return charDataRanges[mid];
        }
        else if (pos < charDataRanges[mid].start) {
            right = mid - 1;
        }
        else {
            left = mid + 1;
        }
    }
    return null;
}

/******/ 	return __webpack_exports__;
/******/ })()
;
});
//# sourceMappingURL=465.view.js.map