var ExtensionScriptClass = function() {};

ExtensionScriptClass.prototype = {
    run: function(arguments) {
        let allFrames = document.querySelectorAll('iframe, frame');
        var frames = [];

        for (var idx = 0; idx < allFrames.length; idx++) {
        	let frame = allFrames[idx];
            let url = new URL(frame.src, document.location.href);

            // Don't bother trying if domain is different
            if (url.host != document.location.host) {
                frames.push("");
                continue;
            }

            // This might fail for other reasons ('sandbox' attribute?)
            try {
                frames.push(frame.contentWindow.document.documentElement.innerHTML);
            }
            catch (e) {
                frames.push("");
            }
        }

      	arguments.completionFunction({"title": document.title,
                             	      "url": document.URL,
                                      "html": document.documentElement.innerHTML,
                                      "cookies": document.cookie,
                                      "frames": frames
       });
    } 
};

// The JavaScript file must contain a global object named "ExtensionPreprocessingJS".
var ExtensionPreprocessingJS = new ExtensionScriptClass;
