// These are the classes corresponding to the RDF and N3 data models
//
// Designed to look like rdflib and cwm designs.
//
// Issues: Should the names start with RDF to make them
//      unique as program-wide symbols?
//
// W3C open source licence 2005.
//
//	Symbol

(function() {
var Term = {};

Term.Empty = function () {
  return this;
};

Term.Empty.prototype.termType = 'empty';
Term.Empty.prototype.toString = function () {
  return "()"
};
Term.Empty.prototype.toNT = Term.Empty.prototype.toString;

Term.Symbol = function (uri) {
  this.uri = uri;
  this.value = uri; // -- why? -tim
  return this;
}

Term.Symbol.prototype.termType = 'symbol';
Term.Symbol.prototype.toString = function () {
  return("<" + this.uri + ">");
};
Term.Symbol.prototype.toNT = Term.Symbol.prototype.toString;

//  Some precalculated symbols
Term.Symbol.prototype.XSDboolean = new Term.Symbol('http://www.w3.org/2001/XMLSchema#boolean');
Term.Symbol.prototype.XSDdecimal = new Term.Symbol('http://www.w3.org/2001/XMLSchema#decimal');
Term.Symbol.prototype.XSDfloat = new Term.Symbol('http://www.w3.org/2001/XMLSchema#float');
Term.Symbol.prototype.XSDinteger = new Term.Symbol('http://www.w3.org/2001/XMLSchema#integer');
Term.Symbol.prototype.XSDdateTime = new Term.Symbol('http://www.w3.org/2001/XMLSchema#dateTime');
Term.Symbol.prototype.integer = new Term.Symbol('http://www.w3.org/2001/XMLSchema#integer'); // Used?
//	Blank Node
if(typeof Term.NextId != 'undefined') {
  Term.log('Attempt to re-zero existing blank node id counter at ' + Term.NextId);
} else {
  Term.NextId = 0; // Global genid
}
Term.NTAnonymousNodePrefix = "_:n";

Term.BlankNode = function (id) {
  /*if (id)
    	this.id = id;
    else*/
  this.id = Term.NextId++;
  this.value = id ? id : this.id.toString();
  return this
};

Term.BlankNode.prototype.termType = 'bnode';
Term.BlankNode.prototype.toNT = function () {
  return Term.NTAnonymousNodePrefix + this.id
};
Term.BlankNode.prototype.toString = Term.BlankNode.prototype.toNT;

//	Literal
Term.Literal = function (value, lang, datatype) {
  this.value = value
  if(lang == "" || lang == null) this.lang = undefined;
  else this.lang = lang; // string
  if(datatype == null) this.datatype = undefined;
  else this.datatype = datatype; // term
  return this;
}

Term.Literal.prototype.termType = 'literal'
Term.Literal.prototype.toString = function () {
  return '' + this.value;
};
Term.Literal.prototype.toNT = function () {
  var str = this.value
  if(typeof str != 'string') {
    if(typeof str == 'number') return '' + str;
    throw Error("Value of RDF literal is not string: " + str)
  }
  str = str.replace(/\\/g, '\\\\'); // escape backslashes
  str = str.replace(/\"/g, '\\"'); // escape quotes
  str = str.replace(/\n/g, '\\n'); // escape newlines
  str = '"' + str + '"' //';
  if(this.datatype) {
    str = str + '^^' + this.datatype.toNT()
  }
  if(this.lang) {
    str = str + "@" + this.lang;
  }
  return str;
};

Term.Collection = function () {
  this.id = Term.NextId++; // Why need an id? For hashstring.
  this.elements = [];
  this.closed = false;
};

Term.Collection.prototype.termType = 'collection';

Term.Collection.prototype.toNT = function () {
  return Term.NTAnonymousNodePrefix + this.id
};

Term.Collection.prototype.toString = function () {
  var str = '(';
  for(var i = 0; i < this.elements.length; i++)
  str += this.elements[i] + ' ';
  return str + ')';
};

Term.Collection.prototype.append = function (el) {
  this.elements.push(el)
}
Term.Collection.prototype.unshift = function (el) {
  this.elements.unshift(el);
}
Term.Collection.prototype.shift = function () {
  return this.elements.shift();
}

Term.Collection.prototype.close = function () {
  this.closed = true
}


//      Convert Javascript representation to RDF term object
//
Term.term = function (val) {
  if(typeof val == 'object')
    if(val instanceof Date) {
      var d2 = function (x) {
          return('' + (100 + x)).slice(1, 3)
        }; // format as just two digits
      return new Term.Literal('' + val.getUTCFullYear() + '-' + d2(val.getUTCMonth() + 1)
          + '-' + d2(val.getUTCDate()) + 'T' + d2(val.getUTCHours()) + ':'
          + d2(val.getUTCMinutes()) + ':' + d2(val.getUTCSeconds()) + 'Z',
        undefined,
        Term.Symbol.prototype.XSDdateTime);

    } else if(val instanceof Array) {
      var x = new Term.Collection();
      for(var i = 0; i < val.length; i++)
        x.append(Term.term(val[i]));
      return x;
    } else
      return val;
  if(typeof val == 'string')
    return new Term.Literal(val);
  if(typeof val == 'number') {
    var dt;
    if(('' + val).indexOf('e') >= 0) dt = Term.Symbol.prototype.XSDfloat;
    else if(('' + val).indexOf('.') >= 0) dt = Term.Symbol.prototype.XSDdecimal;
    else dt = Term.Symbol.prototype.XSDinteger;
    return new Term.Literal(val, undefined, dt);
  }
  if(typeof val == 'boolean')
    return new Term.Literal(val ? "1" : "0", undefined, $rdf.Symbol.prototype.XSDboolean);
  if(typeof val == 'undefined')
    return undefined;
  throw("Can't make term from " + val + " of type " + typeof val);
}

//	Statement
//
//  This is a triple with an optional reason.
//
//   The reason can point to provenece or inference
//
Term.Statement = function (subject, predicate, object, why) {
  this.subject = Term.term(subject)
  this.predicate = Term.term(predicate)
  this.object = Term.term(object)
  if(typeof why != 'undefined') {
    this.why = why;
  }
  return this;
}

Term.st = function (subject, predicate, object, why) {
  return new Term.Statement(subject, predicate, object, why);
};

Term.Statement.prototype.toNT = function () {
  return (this.subject.toNT() + " " + this.predicate.toNT() + " " + this.object.toNT() + " .");
};

Term.Statement.prototype.toString = Term.Statement.prototype.toNT;

//	Formula
//
//	Set of statements.
Term.Formula = function () {
  this.statements = []
  this.constraints = []
  this.initBindings = []
  this.optional = []
  return this;
};


Term.Formula.prototype.termType = 'formula';
Term.Formula.prototype.toNT = function () {
  return "{" + this.statements.join('\n') + "}"
};
Term.Formula.prototype.toString = Term.Formula.prototype.toNT;

Term.Formula.prototype.add = function (subj, pred, obj, why) {
  this.statements.push(new Term.Statement(subj, pred, obj, why))
}

// Convenience methods on a formula allow the creation of new RDF terms:
Term.Formula.prototype.sym = function (uri, name) {
  if(name != null) {
    throw "This feature (kb.sym with 2 args) is removed. Do not assume prefix mappings."
  }
  return new Term.Symbol(uri)
}

Term.sym = function (uri) {
  return new Term.Symbol(uri);
};

Term.Formula.prototype.literal = function (val, lang, dt) {
  return new Term.Literal(val.toString(), lang, dt)
}
Term.lit = Term.Formula.prototype.literal;

Term.Formula.prototype.bnode = function (id) {
  return new Term.BlankNode(id)
}

Term.Formula.prototype.formula = function () {
  return new Term.Formula()
}

Term.Formula.prototype.collection = function () { // obsolete
  return new Term.Collection()
}

Term.Formula.prototype.list = function (values) {
  var li = new Term.Collection();
  if(values) {
    for(var i = 0; i < values.length; i++) {
      li.append(values[i]);
    }
  }
  return li;
}

/*  Variable
 **
 ** Variables are placeholders used in patterns to be matched.
 ** In cwm they are symbols which are the formula's list of quantified variables.
 ** In sparl they are not visibily URIs.  Here we compromise, by having
 ** a common special base URI for variables. Their names are uris,
 ** but the ? nottaion has an implicit base uri of 'varid:'
 */

Term.Variable = function (rel) {
  this.base = "varid:"; // We deem variabe x to be the symbol varid:x 
  this.uri = $rdf.Util.uri.join(rel, this.base);
  return this;
}

Term.Variable.prototype.termType = 'variable';
Term.Variable.prototype.toNT = function () {
  if(this.uri.slice(0, this.base.length) == this.base) {
    return '?' + this.uri.slice(this.base.length);
  } // @@ poor man's refTo
  return '?' + this.uri;
};

Term.Variable.prototype.toString = Term.Variable.prototype.toNT;
Term.Variable.prototype.classOrder = 7;

Term.variable = Term.Formula.prototype.variable = function (name) {
  return new Term.Variable(name);
};

Term.Variable.prototype.hashString = Term.Variable.prototype.toNT;


// The namespace function generator 
Term.Namespace = function (nsuri) {
  return function (ln) {
    return new Term.Symbol(nsuri + (ln === undefined ? '' : ln))
  }
}

Term.Formula.prototype.ns = function (nsuri) {
  return function (ln) {
    return new Term.Symbol(nsuri + (ln === undefined ? '' : ln))
  }
}


// Parse a single token
//
// The bnode bit should not be used on program-external values; designed
// for internal work such as storing a bnode id in an HTML attribute.
// This will only parse the strings generated by the vaious toNT() methods.
Term.Formula.prototype.fromNT = function (str) {
  var len = str.length
  var ch = str.slice(0, 1)
  if(ch == '<') return Term.sym(str.slice(1, len - 1))
  if(ch == '"') {
    var lang = undefined;
    var dt = undefined;
    var k = str.lastIndexOf('"');
    if(k < len - 1) {
      if(str[k + 1] == '@') lang = str.slice(k + 2, len);
      else if(str.slice(k + 1, k + 3) == '^^') dt = Term.fromNT(str.slice(k + 3, len));
      else throw "Can't convert string from NT: " + str
    }
    var str = (str.slice(1, k));
    str = str.replace(/\\"/g, '"'); // unescape quotes '
    str = str.replace(/\\n/g, '\n'); // unescape newlines
    str = str.replace(/\\\\/g, '\\'); // unescape backslashes 
    return Term.lit(str, lang, dt);
  }
  if(ch == '_') {
    var x = new Term.BlankNode();
    x.id = parseInt(str.slice(3));
    Term.NextId--
    return x
  }
  if(ch == '?') {
    var x = new Term.Variable(str.slice(1));
    return x;
  }
  throw "Can't convert from NT: " + str;

}
Term.fromNT = Term.Formula.prototype.fromNT; // Not for inexpert user
// Convenience - and more conventional name:
Term.graph = function () {
  return new $rdf.IndexedFormula();
};

// ends


/*
 * Update 2018-06-01
 * match.js extension for term.js:
 * https://github.com/zotero/zotero/blob/805d3ed6a67add126eff97579200458b52bf5ac5/chrome/content/zotero/xpcom/rdf/match.js
 */

Term.Symbol.prototype.sameTerm = function (other) {
  if(!other) {
    return false
  }
  return((this.termType == other.termType) && (this.uri == other.uri))
}

Term.BlankNode.prototype.sameTerm = function (other) {
  if(!other) {
    return false
  }
  return((this.termType == other.termType) && (this.id == other.id))
}

Term.Literal.prototype.sameTerm = function (other) {
  if(!other) {
    return false
  }
  return((this.termType == other.termType)
    && (this.value == other.value)
    && (this.lang == other.lang)
    && ((!this.datatype && !other.datatype)
      || (this.datatype && this.datatype.sameTerm(other.datatype))))
}

Term.Variable.prototype.sameTerm = function (other) {
  if(!other) {
    return false
  }
  return((this.termType == other.termType) && (this.uri == other.uri))
}

Term.Collection.prototype.sameTerm = Term.BlankNode.prototype.sameTerm

Term.Formula.prototype.sameTerm = function (other) {
  return this.hashString() == other.hashString();
}
//  Comparison for ordering
//
// These compare with ANY term
//
//
// When we smush nodes we take the lowest value. This is not
// arbitrary: we want the value actually used to be the literal
// (or list or formula). 
Term.Literal.prototype.classOrder = 1
Term.Collection.prototype.classOrder = 3
Term.Formula.prototype.classOrder = 4
Term.Symbol.prototype.classOrder = 5
Term.BlankNode.prototype.classOrder = 6

//  Compaisons return  sign(self - other)
//  Literals must come out before terms for smushing
Term.Literal.prototype.compareTerm = function (other) {
  if(this.classOrder < other.classOrder) return -1
  if(this.classOrder > other.classOrder) return +1
  if(this.value < other.value) return -1
  if(this.value > other.value) return +1
  return 0
}

Term.Symbol.prototype.compareTerm = function (other) {
  if(this.classOrder < other.classOrder) return -1
  if(this.classOrder > other.classOrder) return +1
  if(this.uri < other.uri) return -1
  if(this.uri > other.uri) return +1
  return 0
}

Term.BlankNode.prototype.compareTerm = function (other) {
  if(this.classOrder < other.classOrder) return -1
  if(this.classOrder > other.classOrder) return +1
  if(this.id < other.id) return -1
  if(this.id > other.id) return +1
  return 0
}

Term.Collection.prototype.compareTerm = Term.BlankNode.prototype.compareTerm

//  Convenience routines
// Only one of s p o can be undefined, and w is optional.
Term.Formula.prototype.each = function (s, p, o, w) {
  var results = []
  var st, sts = this.statementsMatching(s, p, o, w, false)
  var i, n = sts.length
  if(typeof s == 'undefined') {
    for(i = 0; i < n; i++) {
      st = sts[i];
      results.push(st.subject)
    }
  } else if(typeof p == 'undefined') {
    for(i = 0; i < n; i++) {
      st = sts[i];
      results.push(st.predicate)
    }
  } else if(typeof o == 'undefined') {
    for(i = 0; i < n; i++) {
      st = sts[i];
      results.push(st.object)
    }
  } else if(typeof w == 'undefined') {
    for(i = 0; i < n; i++) {
      st = sts[i];
      results.push(st.why)
    }
  }
  return results
}

Term.Formula.prototype.any = function (s, p, o, w) {
  var st = this.anyStatementMatching(s, p, o, w)
  if(typeof st == 'undefined') return undefined;

  if(typeof s == 'undefined') return st.subject;
  if(typeof p == 'undefined') return st.predicate;
  if(typeof o == 'undefined') return st.object;

  return undefined
}

Term.Formula.prototype.holds = function (s, p, o, w) {
  var st = this.anyStatementMatching(s, p, o, w)
  if(typeof st == 'undefined') return false;
  return true;
}

Term.Formula.prototype.the = function (s, p, o, w) {
  // the() should contain a check there is only one
  var x = this.any(s, p, o, w)
  if(typeof x == 'undefined')
    $rdf.log("No value found for the(){" + s + " " + p + " " + o + "}.")
  return x
}

Term.Formula.prototype.whether = function (s, p, o, w) {
  return this.statementsMatching(s, p, o, w, false).length;
}

Object.assign($rdf, Term);
})();
