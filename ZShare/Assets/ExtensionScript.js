var ExtensionScriptClass = function() {};

ExtensionScriptClass.prototype = {
    run: function(arguments) {
       arguments.completionFunction({"title": document.title,
                                     "url": document.URL,
                                     "html": document.documentElement.innerHTML,
                                     "cookies": document.cookie});
    } 
};

// The JavaScript file must contain a global object named "ExtensionPreprocessingJS".
var ExtensionPreprocessingJS = new ExtensionScriptClass;
