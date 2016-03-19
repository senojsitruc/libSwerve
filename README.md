# libSwerve
Fast, light-weight and easy-to-use HTTP server written in Swift for OS X and iOS

## HTTP Server Example

### To SSL or Not

First we decide on the underlying data mechanism. The HTTP server uses this for all of its IO and remains uninvolved in the implementation. There's a "plain" TCP socket server available:
```
let tcpServer = CJSwerve.tcpServerType.init(port: 8080)
```

In addition to one that wraps socket IO in SSL:
```
let tcpServer = CJSwerve.tlsTcpServerType.init(port: 8080)
```

### The HTTP Part

The HTTP server uses our TCP server for communication.
```
var httpServer = CJSwerve.httpServerType.init(server: tcpServer)
```

Next up, we need to give our server some content to serve. This handler will be called for "/" requests. We're just returning a string literal.
```
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
```

This handler uses the 'pathLike' feature, which uses regex to match requests.
```
httpServer.addHandler(.Get, pathLike: "^/SomePath/(\\d+)/(\\d+)\\.txt$") { values, request, response in
	// ...
}
```

This handler maps the user's Downloads directory to the "/Downloads/" path, and supports directory listings and recursion.
```
do {
	let filePath = NSSearchPathForDirectoriesInDomains(.DownloadsDirectory, .UserDomainMask, true)[0]
	httpServer.addFileModule(localPath: filePath, webPath: "/Downloads/", recurses: true)
}
```

Finally, we'll start the HTTP server, which in turn starts the TCP server.
```
httpServer.start() { success, error in
	// self.server = httpServer
}
```

Ask your default gateway to open a port. This part is still a work-in-progress, as there's presently no way for the caller to discover which port was opened.
```
tcpServer.enablePortMapping(externalPort: 0)
```

### Generate and Configure a Self-Signed Certificate

Before configuring and starting a TLS/SSL HTTP server, you must 'setupTLS()' with a certificate. If you have a legitimate one, just specify the appropriate label name for the Keychain item.
```
if let tlsIdentity = CJCrypto.identityWithLabel("us.curtisjones.libSwerve.tlsKey-002") {
	CJCrypto.setupTLS(tlsIdentity)
}
```

Otherwise (and subsequently), you can easily generate a self-signed certificate. Browsers will balk, but the connection will still be encrypted.
```
let identity = CJCrypto.generateIdentity(keySizeInBits: 4096, label: "us.curtisjones.libSwerve.tlsKey-002") {
	CJCrypto.setupTLS(identity)
}
```

### Status

- [x] HTTP GET
- [ ] HTTP POST
- [ ] HTTP Multi-part Requests
- [ ] HTTP Multi-part Responses
- [x] HTTP Keep-Alive
- [x] TLS/SSL
- [ ] Logging
