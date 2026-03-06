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

  function toUint8Array(input) {
    if (!input) {
      return new Uint8Array(0);
    }
    if (input instanceof Uint8Array) {
      return input;
    }
    if (Array.isArray(input)) {
      return new Uint8Array(input);
    }
    if (typeof input.byteLength === "number") {
      if (typeof input.byteOffset === "number" && input.buffer) {
        try {
          return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
        } catch (_e) {}
      }
      try {
        return new Uint8Array(input);
      } catch (_e2) {}
    }
    return new Uint8Array(0);
  }

  function decodeUtf8(u8) {
    var out = "";
    var i = 0;
    while (i < u8.length) {
      var c = u8[i++];
      if (c < 0x80) {
        out += String.fromCharCode(c);
        continue;
      }
      if ((c & 0xe0) === 0xc0 && i < u8.length) {
        out += String.fromCharCode(((c & 0x1f) << 6) | (u8[i++] & 0x3f));
        continue;
      }
      if ((c & 0xf0) === 0xe0 && i + 1 < u8.length) {
        out += String.fromCharCode(
          ((c & 0x0f) << 12) |
          ((u8[i++] & 0x3f) << 6) |
          (u8[i++] & 0x3f)
        );
        continue;
      }
      if ((c & 0xf8) === 0xf0 && i + 2 < u8.length) {
        var codePoint =
          ((c & 0x07) << 18) |
          ((u8[i++] & 0x3f) << 12) |
          ((u8[i++] & 0x3f) << 6) |
          (u8[i++] & 0x3f);
        codePoint -= 0x10000;
        out += String.fromCharCode(
          0xd800 + ((codePoint >> 10) & 0x3ff),
          0xdc00 + (codePoint & 0x3ff)
        );
        continue;
      }
      out += "\ufffd";
    }
    return out;
  }

  function decodeUtf16(u8, littleEndian) {
    var out = "";
    for (var i = 0; i + 1 < u8.length; i += 2) {
      var codeUnit = littleEndian
        ? (u8[i] | (u8[i + 1] << 8))
        : ((u8[i] << 8) | u8[i + 1]);
      out += String.fromCharCode(codeUnit);
    }
    if (out.charCodeAt(0) === 0xfeff) {
      return out.slice(1);
    }
    return out;
  }

  function decodeBytes(u8, encoding) {
    var normalized = String(encoding || "utf-8").toLowerCase();
    if (normalized.indexOf("latin1") !== -1 || normalized.indexOf("iso-8859-1") !== -1) {
      var latin1 = "";
      for (var i = 0; i < u8.length; i++) {
        latin1 += String.fromCharCode(u8[i]);
      }
      return latin1;
    }
    if (normalized.indexOf("utf-16") !== -1) {
      var littleEndian = normalized.indexOf("utf-16be") === -1;
      return decodeUtf16(u8, littleEndian);
    }
    return decodeUtf8(u8);
  }

  if (typeof g.TextDecoder === "undefined") {
    g.TextDecoder = function (encoding) {
      var selectedEncoding = encoding || "utf-8";
      this.decode = function (u8) {
        return decodeBytes(toUint8Array(u8), selectedEncoding);
      };
    };
  }

  if (typeof g.AbortSignal === "undefined") {
    g.AbortSignal = function () {
      this.aborted = false;
      this.reason = undefined;
      this.onabort = null;
      this._listeners = [];
    };
    g.AbortSignal.prototype.addEventListener = function (type, callback) {
      if (type !== "abort" || typeof callback !== "function") {
        return;
      }
      this._listeners.push(callback);
    };
    g.AbortSignal.prototype.removeEventListener = function (type, callback) {
      if (type !== "abort" || typeof callback !== "function") {
        return;
      }
      var idx = this._listeners.indexOf(callback);
      if (idx >= 0) {
        this._listeners.splice(idx, 1);
      }
    };
    g.AbortSignal.prototype.throwIfAborted = function () {
      if (this.aborted) {
        throw (this.reason || new g.DOMException("The operation was aborted.", "AbortError"));
      }
    };
    g.AbortSignal.prototype._abort = function (reason) {
      if (this.aborted) {
        return;
      }
      this.aborted = true;
      this.reason = reason || new g.DOMException("The operation was aborted.", "AbortError");
      if (typeof this.onabort === "function") {
        try {
          this.onabort({ type: "abort", target: this });
        } catch (_e) {}
      }
      var listeners = this._listeners.slice();
      for (var i = 0; i < listeners.length; i++) {
        try {
          listeners[i]({ type: "abort", target: this });
        } catch (_e2) {}
      }
    };
  }

  if (typeof g.AbortController === "undefined") {
    g.AbortController = function () {
      this.signal = new g.AbortSignal();
    };
    g.AbortController.prototype.abort = function (reason) {
      this.signal._abort(reason);
    };
  }

  if (typeof g.AbortSignal.any !== "function") {
    g.AbortSignal.any = function (iterable) {
      var ac = new g.AbortController();
      if (!iterable) {
        return ac.signal;
      }
      var list = [];
      if (typeof iterable.length === "number") {
        for (var i = 0; i < iterable.length; i++) {
          list.push(iterable[i]);
        }
      } else if (typeof Symbol !== "undefined" && iterable[Symbol.iterator]) {
        var iterator = iterable[Symbol.iterator]();
        var item = iterator.next();
        while (!item.done) {
          list.push(item.value);
          item = iterator.next();
        }
      }
      for (var j = 0; j < list.length; j++) {
        (function (signal) {
          if (!signal) {
            return;
          }
          if (signal.aborted) {
            ac.abort(signal.reason);
            return;
          }
          signal.addEventListener("abort", function (event) {
            var target = event && event.target ? event.target : signal;
            ac.abort(target && target.reason);
          });
        })(list[j]);
        if (ac.signal.aborted) {
          break;
        }
      }
      return ac.signal;
    };
  }

  if (typeof g.AbortSignal.timeout !== "function") {
    g.AbortSignal.timeout = function (ms) {
      var ac = new g.AbortController();
      g.setTimeout(function () {
        ac.abort(new g.DOMException("Signal timed out.", "TimeoutError"));
      }, Math.max(0, ms | 0));
      return ac.signal;
    };
  }

  if (typeof g.DOMPoint === "undefined") {
    g.DOMPoint = function (x, y, z, w) {
      this.x = Number(x || 0);
      this.y = Number(y || 0);
      this.z = Number(z || 0);
      this.w = Number(w == null ? 1 : w);
    };
  }

  if (typeof g.DOMMatrix === "undefined") {
    function toMatrixValues(init) {
      if (!init) {
        return [1, 0, 0, 1, 0, 0];
      }
      if (Array.isArray(init) || (typeof init.length === "number")) {
        var arr = [];
        for (var i = 0; i < init.length; i++) {
          arr.push(Number(init[i]));
        }
        if (arr.length >= 6) {
          return [arr[0], arr[1], arr[2], arr[3], arr[4], arr[5]];
        }
      }
      if (typeof init === "object") {
        if (typeof init.a === "number") {
          return [init.a, init.b, init.c, init.d, init.e, init.f];
        }
        if (typeof init.m11 === "number") {
          return [
            init.m11,
            init.m12,
            init.m21,
            init.m22,
            init.m41,
            init.m42
          ];
        }
      }
      return [1, 0, 0, 1, 0, 0];
    }

    function multiply2D(left, right) {
      var a1 = left[0], b1 = left[1], c1 = left[2], d1 = left[3], e1 = left[4], f1 = left[5];
      var a2 = right[0], b2 = right[1], c2 = right[2], d2 = right[3], e2 = right[4], f2 = right[5];
      return [
        a1 * a2 + c1 * b2,
        b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2,
        b1 * c2 + d1 * d2,
        a1 * e2 + c1 * f2 + e1,
        b1 * e2 + d1 * f2 + f1
      ];
    }

    function inverse2D(m) {
      var a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5];
      var det = a * d - b * c;
      if (!det) {
        return null;
      }
      var inv = 1 / det;
      return [
        d * inv,
        -b * inv,
        -c * inv,
        a * inv,
        (c * f - d * e) * inv,
        (b * e - a * f) * inv
      ];
    }

    g.DOMMatrix = function (init) {
      var values = toMatrixValues(init);
      this.a = values[0];
      this.b = values[1];
      this.c = values[2];
      this.d = values[3];
      this.e = values[4];
      this.f = values[5];
      this.is2D = true;
      this.isIdentity = (
        this.a === 1 &&
        this.b === 0 &&
        this.c === 0 &&
        this.d === 1 &&
        this.e === 0 &&
        this.f === 0
      );
    };

    g.DOMMatrix.fromMatrix = function (matrix) {
      return new g.DOMMatrix(matrix);
    };
    g.DOMMatrix.fromFloat32Array = function (arr) {
      return new g.DOMMatrix(arr);
    };
    g.DOMMatrix.fromFloat64Array = function (arr) {
      return new g.DOMMatrix(arr);
    };

    g.DOMMatrix.prototype._values = function () {
      return [this.a, this.b, this.c, this.d, this.e, this.f];
    };
    g.DOMMatrix.prototype._setValues = function (m) {
      this.a = m[0];
      this.b = m[1];
      this.c = m[2];
      this.d = m[3];
      this.e = m[4];
      this.f = m[5];
      this.isIdentity = (
        this.a === 1 &&
        this.b === 0 &&
        this.c === 0 &&
        this.d === 1 &&
        this.e === 0 &&
        this.f === 0
      );
      return this;
    };

    g.DOMMatrix.prototype.multiplySelf = function (other) {
      return this._setValues(multiply2D(this._values(), toMatrixValues(other)));
    };
    g.DOMMatrix.prototype.preMultiplySelf = function (other) {
      return this._setValues(multiply2D(toMatrixValues(other), this._values()));
    };
    g.DOMMatrix.prototype.multiply = function (other) {
      return new g.DOMMatrix(this._values()).multiplySelf(other);
    };

    g.DOMMatrix.prototype.translateSelf = function (tx, ty) {
      tx = Number(tx || 0);
      ty = Number(ty || 0);
      return this.multiplySelf([1, 0, 0, 1, tx, ty]);
    };
    g.DOMMatrix.prototype.translate = function (tx, ty) {
      return new g.DOMMatrix(this._values()).translateSelf(tx, ty);
    };

    g.DOMMatrix.prototype.scaleSelf = function (sx, sy, _sz, ox, oy) {
      sx = Number(sx == null ? 1 : sx);
      sy = Number(sy == null ? sx : sy);
      ox = Number(ox || 0);
      oy = Number(oy || 0);
      if (ox || oy) {
        this.translateSelf(ox, oy);
      }
      this.multiplySelf([sx, 0, 0, sy, 0, 0]);
      if (ox || oy) {
        this.translateSelf(-ox, -oy);
      }
      return this;
    };
    g.DOMMatrix.prototype.scale = function (sx, sy, sz, ox, oy, oz) {
      return new g.DOMMatrix(this._values()).scaleSelf(sx, sy, sz, ox, oy, oz);
    };

    g.DOMMatrix.prototype.rotateSelf = function (_rx, _ry, rz) {
      var angle = Number((rz == null ? _rx : rz) || 0) * Math.PI / 180;
      var cos = Math.cos(angle);
      var sin = Math.sin(angle);
      return this.multiplySelf([cos, sin, -sin, cos, 0, 0]);
    };
    g.DOMMatrix.prototype.rotate = function (rx, ry, rz) {
      return new g.DOMMatrix(this._values()).rotateSelf(rx, ry, rz);
    };

    g.DOMMatrix.prototype.invertSelf = function () {
      var inv = inverse2D(this._values());
      if (!inv) {
        return this._setValues([NaN, NaN, NaN, NaN, NaN, NaN]);
      }
      return this._setValues(inv);
    };
    g.DOMMatrix.prototype.inverse = function () {
      return new g.DOMMatrix(this._values()).invertSelf();
    };

    g.DOMMatrix.prototype.transformPoint = function (point) {
      var p = point || {};
      var x = Number(p.x || 0);
      var y = Number(p.y || 0);
      return new g.DOMPoint(
        this.a * x + this.c * y + this.e,
        this.b * x + this.d * y + this.f,
        Number(p.z || 0),
        Number(p.w == null ? 1 : p.w)
      );
    };

    g.DOMMatrix.prototype.toFloat32Array = function () {
      return new Float32Array([
        this.a, this.b, 0, 0,
        this.c, this.d, 0, 0,
        0, 0, 1, 0,
        this.e, this.f, 0, 1
      ]);
    };
    g.DOMMatrix.prototype.toFloat64Array = function () {
      return new Float64Array([
        this.a, this.b, 0, 0,
        this.c, this.d, 0, 0,
        0, 0, 1, 0,
        this.e, this.f, 0, 1
      ]);
    };
  }

  if (typeof g.DOMMatrixReadOnly === "undefined" && typeof g.DOMMatrix !== "undefined") {
    g.DOMMatrixReadOnly = g.DOMMatrix;
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
