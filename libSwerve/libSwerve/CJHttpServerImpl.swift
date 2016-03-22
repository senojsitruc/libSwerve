//
//  CJHttpServer1.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

private protocol Handler {
	
	var waitForData: Bool { get }
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> CJHttpServerHandlerMatch?
	
}

private struct PathEqualsHandler: Handler {
	
	let method: CJHttpMethod
	let path: String
	let waitForData: Bool
	let handler: CJHttpServerRequestHandler
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> CJHttpServerHandlerMatch? {
		if request.path == path {
			return CJHttpServerHandlerMatch(handler: handler, request: request, response: response, values: nil)
		}
		else {
			return nil
		}
	}
	
	func runHandler(match: CJHttpServerHandlerMatch) {
		handler(match)
	}
	
}

private struct PathLikeHandler: Handler {
	
	let method: CJHttpMethod
	let regex: NSRegularExpression
	let waitForData: Bool
	let handler: CJHttpServerRequestHandler
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> CJHttpServerHandlerMatch? {
		let path = request.path
		var values = [String]()
		
		guard let result = regex.firstMatchInString(path, options: NSMatchingOptions(rawValue: 0), range: NSMakeRange(0, request.path.characters.count)) else { return nil }
		
		for index in 0..<result.numberOfRanges {
			guard let range = path.rangeFromNSRange(result.rangeAtIndex(index)) else { continue }
			values.append(path.substringWithRange(range))
		}
		
		return CJHttpServerHandlerMatch(handler: handler, request: request, response: response, values: values)
	}
	
}





internal class CJHttpServerImpl: CJHttpServer {
	
	private var handlers = [Handler]()
	private var server: CJServer!
	
	required init(server: CJServer) {
		self.server = server
	}
	
	func start(completionHandler: (Bool, NSError?) -> Void) {
		CJDispatchBackground() {
			var success = false
			var nserror: NSError?
			
			// called after starting (or attempting to start) the server / listener to let the caller
			// know whether we succeeded or not.
			defer { CJDispatchMain() { completionHandler(success, nserror) } }
			
			// wrap the underlying socket connection in an http connection object. the http connection
			// object takes a handler that is called when an http request is received.
			self.server.acceptHandler = { [weak self] connection in
				var c = connection
				c.context = CJSwerve.httpConnectionType.init(connection: connection) { connection, request in
					self?.handleRequest(connection, request)
				}
			}
			
			// start the server or die trying
			do {
				try self.server.start()
				success = true
			}
			catch let e as NSError {
				nserror = e
			}
			catch {
				nserror = NSError(description: "Start failed for an unknown reason.")
			}
		}
	}
	
	func stop(completionHandler: (Bool, NSError?) -> Void) {
		CJDispatchBackground() {
			var success = false
			var nserror: NSError?
			
			defer {
				self.server = nil
				CJDispatchMain() { completionHandler(success, nserror) }
			}
			
			do {
				try self.server.stop()
				success = true
			}
			catch let e as NSError {
				nserror = e
			}
			catch {
				nserror = NSError(description: "Failed for an unknown reason!")
			}
		}
	}
	
	func addHandler(method: CJHttpMethod, pathEquals path: String, waitForData: Bool = false, handler: CJHttpServerRequestHandler) {
		handlers.append(PathEqualsHandler(method: method, path: path, waitForData: waitForData, handler: handler))
	}
	
	func addHandler(method: CJHttpMethod, pathLike pattern: String, waitForData: Bool = false, handler: CJHttpServerRequestHandler) {
		do {
			let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpressionOptions(rawValue: 0))
			handlers.append(PathLikeHandler(method: method, regex: regex, waitForData: waitForData, handler: handler))
		}
		catch {
			DLog("Failed to install handler because of invalid regex pattern: \(pattern)")
		}
	}
	
	func addFileModule(localPath _lp: String, webPath _wp: String, recurses: Bool) {
		let localPath = _lp.hasSuffix("/") ? _lp : (_lp + "/")
		let webPath = _wp.hasSuffix("/") ? _wp.substringToIndex(_wp.endIndex.predecessor()) : _wp
		let fileManager = NSFileManager()
		
		self.addHandler(.Get, pathLike: "^\(webPath)/(.*)$", waitForData: false) { match in
//		let request = match.request
			var response = match.response
			
			// if the match was the base path with no additional subpaths, the match count will be 1
			let path = match.values?.count == 2 ? match.values![1] : ""
			
			// prevent the user from escaping the base directory
			if path.rangeOfString("..") != nil {
				response.finish()
				response.close()
				return
			}
			
			CJDispatchBackground() {
				// assemble the file path
				let fileName = path.stringByRemovingPercentEncoding ?? ""
				let fileType = (fileName as NSString).pathExtension.lowercaseString
				let filePath = localPath + fileName
				
				var isdir: ObjCBool = false
				let exists = fileManager.fileExistsAtPath(filePath, isDirectory: &isdir)
				
				if exists == false {
					response.finish()
					response.close()
					return
				}
				
				if Bool(isdir) == true {
					do {
						var page = "<html><body>"
						
						for fileName in try fileManager.contentsOfDirectoryAtPath(filePath) {
							if fileName.hasPrefix(".") == false {
								if fileManager.isDirectory(filePath + "/" + fileName) {
									page += "<a href=\"\(fileName.stringByAddingPercentEncodingWithAllowedCharacters(.URLHostAllowedCharacterSet()) ?? "")/\">\(fileName)/</a><br>"
								}
								else {
									page += "<a href=\"\(fileName.stringByAddingPercentEncodingWithAllowedCharacters(.URLHostAllowedCharacterSet()) ?? "")\">\(fileName)</a><br>"
								}
							}
						}
						
						page += "</body></html>"
						
						guard let fileData = page.dataUsingEncoding(NSUTF8StringEncoding) else {
							response.finish()
							response.close()
							return
						}
						
						// configure and send the response
						response.addHeader("Content-Type", value: "text/html")
						response.addHeader("Content-Length", value: fileData.length)
						response.addHeader("Connection", value: "keep-alive")
						response.write(fileData)
					}
					catch {
						DLog("Failed to read directory contents [filePath = \(filePath)]")
					}
				}
				else {
					// close the connection if the target file's data isn't accessible (permissions?)
					guard let fileData = NSData(contentsOfFile: filePath) else {
						response.finish()
						response.close()
						return
					}
					
					// configure and send the response
					response.addHeader("Content-Type", value: CJMimeTypeForExtension(fileType) ?? "content/octet-stream")
					response.addHeader("Content-Length", value: fileData.length)
					response.addHeader("Connection", value: "keep-alive")
					response.write(fileData)
				}
				
				response.finish()
			}
		}
	}
	
	private final func handleRequest(connection: CJHttpConnection, _ request: CJHttpServerRequest) {
		var match: CJHttpServerHandlerMatch?
		var handler: Handler?
		let response = CJSwerve.httpResponseType.init(connection: connection, request: request)
		
		for _handler in handlers {
			if let _match = _handler.matches(connection, request, response) {
				match = _match
				handler = _handler
				break
			}
		}
		
		if let handler = handler, var match = match {
			if request.method != .Get && handler.waitForData == true {
				if let contentType = request.contentType {
					if contentType == CJHttpContentType.UrlForm.rawValue {
						match.request.contentHandler = { [weak self] value, done in self?.handleUrlFormData(match, request, value, done) }
					}
					else if contentType == CJHttpContentType.MultipartForm.rawValue {
						match.request.contentHandler = { [weak self] value, done in self?.handleMultipartFormData(request, value, done) }
					}
					else {
						match.request.contentHandler = { [weak self] value, done in self?.handleRawData(request, value, done) }
					}
				}
				else {
					match.request.contentHandler = { [weak self] value, done in self?.handleRawData(request, value, done) }
				}
				match.request.resume()
			}
			else {
				match.handler(match)
			}
		}
		else {
			DLog("No handler match found; closing connection [\(request)]")
			connection.close()
		}
	}
	
	///
	/// URL encoded form data.
	///
	private final func handleUrlFormData(match: CJHttpServerHandlerMatch, _ request: CJHttpServerRequest, _ value: AnyObject?, _ done: Bool) {
		var request = request
		
		if let values = value as? [String: AnyObject] {
			if request.values != nil {
				request.values! += values
			}
			else {
				request.values = values
			}
		}
		
		if done == true {
			request.contentHandler = nil
			match.handler(match)
		}
	}
	
	///
	/// Multipart form data.
	///
	private final func handleMultipartFormData(request: CJHttpServerRequest, _ value: AnyObject?, _ done: Bool) {
//		if let value = value as? FormData {
//			
//		}
//		
//		if done == true {
//			
//		}
	}
	
	///
	/// Raw data.
	///
	private final func handleRawData(request: CJHttpServerRequest, _ value: AnyObject?, _ done: Bool) {
//		if let value = value as? dispatch_data_t {
//			
//		}
//		
//		if done == true {
//			
//		}
	}
	
}
