// Minimal worker-like environment for JavaScriptCore.
(function () {
  if (typeof globalThis === "undefined") {
    this.globalThis = this;
  }
  var g = globalThis;

  g.console = g.console || {
    log: function () { __nativeLog(Array.prototype.slice.call(arguments)); },
    warn: function () { __nativeLog(Array.prototype.slice.call(arguments)); },
    error: function () { __nativeLog(Array.prototype.slice.call(arguments)); }
  };

  g.navigator = g.navigator || { userAgent: "Zotero-iOS-JSC" };

  if (typeof g.window === "undefined") {
    g.window = g;
  }

  if (typeof g.document === "undefined") {
    g.document = {
      body: { append: function () {}, appendChild: function () {} },
      currentScript: null,
      baseURI: "file://",
      location: { href: "file://", origin: "null" },
      createElement: function () {
        return {
          style: {},
          setAttribute: function () {},
          append: function () {},
          appendChild: function () {},
          addEventListener: function () {},
          removeEventListener: function () {},
          getContext: function () { return null; }
        };
      },
      addEventListener: function () {},
      removeEventListener: function () {},
      getSelection: function () { return null; }
    };
  }

  if (typeof g.Node === "undefined") {
    g.Node = function () {};
  }
  if (typeof g.HTMLInputElement === "undefined") {
    g.HTMLInputElement = function () {};
  }
  if (typeof g.HTMLButtonElement === "undefined") {
    g.HTMLButtonElement = function () {};
  }
  if (typeof g.DOMException === "undefined") {
    g.DOMException = function (message, name) {
      this.message = String(message || "");
      this.name = String(name || "Error");
      if (g.Error && g.Error.captureStackTrace) {
        g.Error.captureStackTrace(this, g.DOMException);
      }
    };
    g.DOMException.prototype = Object.create(g.Error ? g.Error.prototype : Object.prototype);
    g.DOMException.prototype.constructor = g.DOMException;
  }

  g.crypto = g.crypto || {};
  if (!g.crypto.getRandomValues) {
    g.crypto.getRandomValues = function (u8) { return __nativeRandom(u8); };
  }
  if (!g.crypto.randomUUID) {
    g.crypto.randomUUID = function () { return __nativeUUID(); };
  }

  g.atob = g.atob || function (str) { return __nativeAtob(str); };
  g.btoa = g.btoa || function (str) { return __nativeBtoa(str); };

  if (typeof g.TextDecoder === "undefined") {
    g.TextDecoder = function (encoding) {
      this.decode = function (u8) { return __nativeTextDecode(u8, encoding || "utf-8"); };
    };
  }

  if (typeof g.URL === "undefined") {
    g.URL = function (url, base) {
      this.href = base ? String(base) + String(url) : String(url);
      this.origin = "null";
    };
    g.URL.createObjectURL = function () { return ""; };
  }
  if (typeof g.URLSearchParams === "undefined") {
    g.URLSearchParams = function () {
      this.get = function () { return null; };
      this.set = function () {};
      this.delete = function () {};
      this.has = function () { return false; };
      this.toString = function () { return ""; };
    };
  }

  if (typeof g.performance === "undefined") {
    g.performance = { now: function () { return Date.now(); } };
  }

  if (typeof g.setTimeout === "undefined") {
    g.setTimeout = function (fn, ms) { return __nativeSetTimeout(fn, ms || 0); };
  }
  if (typeof g.clearTimeout === "undefined") {
    g.clearTimeout = function (id) { __nativeClearTimeout(id); };
  }
  if (typeof g.setInterval === "undefined") {
    g.setInterval = function (fn, ms) { return __nativeSetInterval(fn, ms || 0); };
  }
  if (typeof g.clearInterval === "undefined") {
    g.clearInterval = function (id) { __nativeClearInterval(id); };
  }

  if (typeof g.MessageChannel === "undefined") {
    g.MessageChannel = function () {
      var port1 = {
        onmessage: null,
        postMessage: function (msg) {
          if (port2.onmessage) {
            port2.onmessage({ data: msg });
          }
        }
      };
      var port2 = {
        onmessage: null,
        postMessage: function (msg) {
          if (port1.onmessage) {
            port1.onmessage({ data: msg });
          }
        }
      };
      this.port1 = port1;
      this.port2 = port2;
    };
  }

  g.self = g;
  g.onmessage = null;
  g.postMessage = function (msg, transfer) {
    __nativePostMessage(msg, transfer || []);
  };
})();
