/*
 * Comment by Adomas 2018-06-01: 
 * The history of this RDF parser goes back to 2009. It appears to be cobbled together
 * from a couple of libraries, including whatever has become out of
 * http://dig.csail.mit.edu/2005/ajar/ajaw/js/rdf/serialize.js,
 * which seems to now be https://github.com/linkeddata/rdflib.js
 * as well as http://brondsema.net/blog/index.php/2006/11/25/javascript_rdfparser_from_tabulator
 * 
 * We could maybe try to update it, but since 2009 there have been multiple bugfix commits 
 * https://github.com/zotero/zotero/commits/c9346d4caad8f0b94786408a2b0fb04ccd620fee/chrome/content/zotero/xpcom/rdf
 * and we have no tests for those commits, to be able to ensure the library still works as intended
 * for every usecase.
 * 
 * I have cleaned this up a bit where possible, e.g. replacing the tabulator and alert log calls
 * with $rdf.log (since that's what they linked to anyway), and made it commonjs modular,
 * but otherwise we'll stick to this code as it works for our purposes
 */

var $rdf = {
	Util: {
		ArrayIndexOf: function (arr, item, i) {
			//supported in all browsers except IE<9
			return arr.indexOf(item, i);
		},
		RDFArrayRemove: function (a, x) { //removes all statements equal to x from a
			for (var i = 0; i < a.length; i++) {
				//TODO: This used to be the following, which didnt always work..why
				//if(a[i] == x)
				if (a[i].subject.sameTerm(x.subject) && a[i].predicate.sameTerm(x.predicate) && a[i].object.sameTerm(x.object) && a[i].why.sameTerm(x.why)) {
					a.splice(i, 1);
					return;
				}
			}
			throw "RDFArrayRemove: Array did not contain " + x;
		}
	},
	log: Zotero.debug
};

Zotero.RDF = {AJAW: $rdf}