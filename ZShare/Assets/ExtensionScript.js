var ExtensionScriptClass = function() {};

ExtensionScriptClass.prototype = {
    run: function(arguments) {
        var cookies = "";
        try {
            cookies = document.cookie;
        } catch (e) {}

        if (!document) {
            arguments.completionFunction({"hasDocument": false,
                                          "cookies": cookies,
                                          "userAgent": window.navigator.userAgent});
            return;
        }
        if (!document.documentElement) {
            arguments.completionFunction({"hasDocument": true,
                                          "title": document.title,
                                          "url": document.URL,
                                          "contentType": document.contentType,
                                          "cookies": cookies,
                                          "userAgent": window.navigator.userAgent,
                                          "referrer": document.referrer});
            return;
        }

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

      	arguments.completionFunction({"hasDocument": true,
                                      "title": document.title,
                             	      "url": document.URL,
                                      "contentType": document.contentType,
                                      "html": document.documentElement.innerHTML,
                                      "cookies": cookies,
                                      "frames": frames,
                                      "userAgent": window.navigator.userAgent,
                                      "referrer": document.referrer});
    }
};

// The JavaScript file must contain a global object named "ExtensionPreprocessingJS".
var ExtensionPreprocessingJS = new ExtensionScriptClass;
