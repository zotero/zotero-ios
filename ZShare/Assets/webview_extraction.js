function extractData() {
    if (!document || !document.documentElement) {
        return {"isFile": true}
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

    var cookies = "";
    try {
        cookies = document.cookie;
    } catch (e) {}

    return {"title": document.title,
            "html": document.documentElement.innerHTML,
            "cookies": cookies,
            "frames": frames,
            "isFile": false}
}

extractData();
