/*
	***** BEGIN LICENSE BLOCK *****
	
	Copyright © 2016 Center for History and New Media
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

/**
 * Intercepts web requests to detect and redirect proxies. Loosely based on Zotero for Firefox proxy code.
 *
 */

(function() {

"use strict";

Zotero.Proxies = new function() {

	/**
	 * Check the url for potential proxies and deproxify, providing a schema to build
	 * a proxy object.
	 * 
	 * @param URL
	 * @returns {Object} Unproxied url to proxy object
	 */
	this.getPotentialProxies = function(URL) {
		var urlToProxy = {};
		// If it's a known proxied URL just return it
		if (Zotero.Proxies.transparent) {
			for (var proxy of Zotero.Proxies.proxies) {
				if (proxy.regexp) {
					var m = proxy.regexp.exec(URL);
					if (m) {
						let proper = proxy.toProper(m);
						urlToProxy[proper] = proxy.toJSON();
						return urlToProxy;
					}
				}
			}
		}
		urlToProxy[URL] = null;
		
		// if there is a subdomain that is also a TLD, also test against URI with the domain
		// dropped after the TLD
		// (i.e., www.nature.com.mutex.gmu.edu => www.nature.com)
		var m = /^(https?:\/\/)([^\/]+)/i.exec(URL);
		if (m) {
			// First, drop the 0- if it exists (this is an III invention)
			var host = m[2];
			if (host.substr(0, 2) === "0-") host = host.substr(2);
			var hostnameParts = [host.split(".")];
			if (m[1] == 'https://') {
				// try replacing hyphens with dots for https protocol
				// to account for EZProxy HttpsHypens mode
				hostnameParts.push(host.split('.'));
				hostnameParts[1].splice(0, 1, ...(hostnameParts[1][0].replace(/-/g, '.').split('.')));
			}
			
			for (let i=0; i < hostnameParts.length; i++) {
				let parts = hostnameParts[i];
				// If hostnameParts has two entries, then the second one is with replaced hyphens
				let dotsToHyphens = i == 1;
				// skip the lowest level subdomain, domain and TLD
				for (let j=1; j<parts.length-2; j++) {
					// if a part matches a TLD, everything up to it is probably the true URL
					if (TLDS[parts[j].toLowerCase()]) {
						var properHost = parts.slice(0, j+1).join(".");
						// protocol + properHost + /path
						var properURL = m[1]+properHost+URL.substr(m[0].length);
						var proxyHost = parts.slice(j+1).join('.');
						urlToProxy[properURL] = {scheme: '%h.' + proxyHost + '/%p', dotsToHyphens};
					}
				}
			}
		}
		return urlToProxy;
	};

	/**
	 * Determines whether a host is blacklisted, i.e., whether we should refuse to save transparent
	 * proxy entries for this host. This is necessary because EZProxy offers to proxy all Google and
	 * Wikipedia subdomains, but in practice, this would get really annoying.
	 *
	 * @type Boolean
	 * @private
	 */
	this._isBlacklisted = function(host) {
		/**
		 * Regular expression patterns of hosts never to proxy
		 * @const
		 */
		const hostBlacklist = [
			/edu$/,
			/google\.com$/,
			/wikipedia\.org$/,
			/^[^.]*$/,
			/doubleclick\.net$/,
			/^eutils.ncbi.nlm.nih.gov$/
		];
		/**
		 * Regular expression patterns of hosts that should always be proxied, regardless of whether
		 * they're on the blacklist
		 * @const
		 */
		const hostWhitelist = [
			/^scholar\.google\.com$/,
			/^muse\.jhu\.edu$/,
			/^(www\.)?journals\.uchicago\.edu$/
		]

		for (var blackPattern of hostBlacklist) {
			if (blackPattern.test(host)) {
				for (var whitePattern of hostWhitelist) {
					if (whitePattern.test(host)) {
						return false;
					}
				}
				return true;
			}
		}
		return false;
	}
};

/**
 * Creates a Zotero.Proxy object from a DB row
 *
 * @constructor
 * @class A model for a http proxy server
 */
Zotero.Proxy = function (json={}) {
	this.id = json.id || Date.now();
	this.autoAssociate = json.autoAssociate == undefined ? true : !!json.autoAssociate;
	this.scheme = json.scheme;
	this.hosts = json.hosts || [];
	this.dotsToHyphens = !!json.dotsToHyphens;
	if (this.scheme) {
		// Loading from storage or new
		this.compileRegexp();
	}
};

/**
 * Convert the proxy to JSON compatible object
 * @returns {Object}
 */
Zotero.Proxy.prototype.toJSON = function() {
	if (!this.scheme) {
		throw Error('Cannot convert proxy to JSON - no scheme');
	}
	return {id: this.id, scheme: this.scheme, dotsToHyphens: this.dotsToHyphens};
};


/**
 * Regexps to match the URL contents corresponding to proxy scheme parameters
 * @const
 */
const Zotero_Proxy_schemeParameters = {
	"%p": "(.*?)",	// path
	"%d": "(.*?)",	// directory
	"%f": "(.*?)",	// filename
	"%a": "(.*?)",	// anything
	"%h": "([a-zA-Z0-9]+[.\\-][a-zA-Z0-9.\\-]+)"	// hostname
};

/**
 * Regexps to match proxy scheme parameters in the proxy scheme URL
 * @const
 */
const Zotero_Proxy_schemeParameterRegexps = {
	"%p": /([^%])%p/,
	"%d": /([^%])%d/,
	"%f": /([^%])%f/,
	"%h": /([^%])%h/,
	"%a": /([^%])%a/
};


/**
 * Compiles the regular expression against which we match URLs to determine if this proxy is in use
 * and saves it in this.regexp
 */
Zotero.Proxy.prototype.compileRegexp = function() {
	var indices = this.indices = {};
	this.parameters = [];
	for (var param in Zotero_Proxy_schemeParameters) {
		var index = this.scheme.indexOf(param);

		// avoid escaped matches
		while (this.scheme[index-1] && (this.scheme[index-1] == "%")) {
			this.scheme = this.scheme.substr(0, index-1)+this.scheme.substr(index);
			index = this.scheme.indexOf(param, index+1);
		}

		if (index != -1) {
			this.indices[param] = index;
			this.parameters.push(param);
		}
	}

	// sort params by index
	this.parameters = this.parameters.sort(function(a, b) {
		return indices[a]-indices[b];
	});

	// now replace with regexp fragment in reverse order
	var re;
	if (this.scheme.includes('://')) {
		re = "^"+Zotero.Utilities.quotemeta(this.scheme)+"$";
	} else {
		re = "^https?"+Zotero.Utilities.quotemeta('://'+this.scheme)+"$";
	}
	for(var i=this.parameters.length-1; i>=0; i--) {
		var param = this.parameters[i];
		re = re.replace(Zotero_Proxy_schemeParameterRegexps[param], "$1"+Zotero_Proxy_schemeParameters[param]);
	}

	this.regexp = new RegExp(re);
}

/**
 * Converts a proxied URL to an unproxied URL using this proxy
 *
 * @param m {Array} The match from running this proxy's regexp against a URL spec
 * @type String
 */
Zotero.Proxy.prototype.toProper = function(m) {
	if (!Array.isArray(m)) {
		let match = this.regexp.exec(m);
		if (!match) {
			return m
		} else {
			m = match;
		}
	}
	let hostIdx = this.parameters.indexOf("%h");
	let scheme = m[0].indexOf('https') == 0 ? 'https://' : 'http://';
	if (hostIdx != -1) {
		var properURL = scheme+m[hostIdx+1]+"/";
	} else {
		var properURL = scheme+this.hosts[0]+"/";
	}
	
	// Replace `-` with `.` in https to support EZProxy HttpsHyphens.
	// Potentially troublesome with domains that contain dashes
	if (this.dotsToHyphens ||
		(this.dotsToHyphens == undefined && scheme == "https://") ||
		!properURL.includes('.')) {
		properURL = properURL.replace(/-/g, '.');
	}

	if (this.indices["%p"]) {
		properURL += m[this.parameters.indexOf("%p")+1];
	} else {
		var dir = m[this.parameters.indexOf("%d")+1];
		var file = m[this.parameters.indexOf("%f")+1];
		if (dir !== "") properURL += dir+"/";
		properURL += file;
	}

	return properURL;
}

/**
 * Converts an unproxied URL to a proxied URL using this proxy
 *
 * @param {Object|String} uri The URI corresponding to the unproxied URL
 * @type String
 */
Zotero.Proxy.prototype.toProxy = function(uri) {
	if (typeof uri == "string") {
		uri = new URL(uri);
	}
	if (this.regexp.exec(uri.href) || Zotero.Proxies._isBlacklisted(uri.hostname)) {
		return uri.href;
	}
	var proxyURL = this.scheme;

	for(var i=this.parameters.length-1; i>=0; i--) {
		var param = this.parameters[i];
		var value = "";
		if (param == "%h") {
			value = (this.dotsToHyphens && uri.protocol == 'https:') ? uri.hostname.replace(/\./g, '-') : uri.hostname;
		} else if (param == "%p") {
			value = uri.pathname.substr(1);
		} else if (param == "%d") {
			value = uri.pathname.substr(0, uri.path.lastIndexOf("/"));
		} else if (param == "%f") {
			value = uri.pathname.substr(uri.path.lastIndexOf("/")+1)
		}

		proxyURL = proxyURL.substr(0, this.indices[param])+value+proxyURL.substr(this.indices[param]+2);
	}

	if (proxyURL.includes('://')) {
		return proxyURL;
	}
	return uri.protocol + '//' + proxyURL;
}

/**
 * Generate a display name for the proxy (e.g., "proxy.example.edu (HTTPS)")
 *
 * @return {String}
 */
Zotero.Proxy.prototype.toDisplayName = function () {
	try {
		var parts = this.scheme.match(/^(?:(?:[^:]+):\/\/)?([^\/]+)/);
		var domain = parts[1]
			// Include part after %h, if it's present
			.split('%h').pop()
			// Trim leading punctuation after the %h
			.match(/\W(.+)/)[1];
		return domain;
	}
	catch (e) {
		Zotero.logError(`Invalid proxy ${this.scheme}: ${e}`);
		return this.scheme;
	}
}

})();
