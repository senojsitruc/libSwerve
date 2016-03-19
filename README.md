# libSwerve
Fast, light-weight and easy-to-use HTTP server written in Swift for OS X and iOS

## HTTP Server Example
```
// The TCP server will listen on port 8080, and the HTTP server relies on the TCP server.
let tcpServer = CJSwerve.tcpServerType.init(port: 8080)
var httpServer = CJSwerve.httpServerType.init(server: tcpServer)

// This handler will be called for "/" requests. Return some text.
httpServer.addHandler(.Get, pathEquals: "/") { request, response in
	CJDispatchBackground() {
		var response = response
		response.addHeader("Content-Type", value: "text/plain")
		response.addHeader("Content-Length", value: 15)
		response.addHeader("Connection", value: "keep-alive")
		response.write("This is a test.")
		response.finish()
	}
}

# This handler uses the `pathLike` feature.
httpServer.addHandler(.Get, pathLike: "^/SomePath/(\\d+)/(\\d+)\\.txt$") { values, request, response in
	// ...
}

// This handler maps the user's Downloads directory to the "/Downloads/" path, and supports
// directory listings and recursion.
do {
	let filePath = NSSearchPathForDirectoriesInDomains(.DownloadsDirectory, .UserDomainMask, true)[0]
	httpServer.addFileModule(localPath: filePath, webPath: "/Downloads/", recurses: true)
}

// Start your engines.
httpServer.start() { success, error in
	// self.server = httpServer
}

// Ask your default gateway to open a port. This part is still a work-in-progress, as there's
// presently no way for the caller to discover which port was opened.
tcpServer.enablePortMapping(externalPort: 0)
```
