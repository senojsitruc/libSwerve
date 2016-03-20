//
//  CJHttpServer1.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

private protocol Handler {
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> Bool
	
}

private struct PathEqualsHandler: Handler {
	
	let method: CJHttpMethod
	let path: String
	let handler: CJHttpServerRequestPathEqualsHandler
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> Bool {
		if request.path == path {
			handler(request, response)
			return true
		}
		else {
			return false
		}
	}
	
}

private struct PathLikeHandler: Handler {
	
	let method: CJHttpMethod
	let regex: NSRegularExpression
	let handler: CJHttpServerRequestPathLikeHandler
	
	func matches(connection: CJHttpConnection, _ request: CJHttpServerRequest, _ response: CJHttpServerResponse) -> Bool {
		let path = request.path
		var values = [String]()
		
		guard let result = regex.firstMatchInString(path, options: NSMatchingOptions(rawValue: 0), range: NSMakeRange(0, request.path.characters.count)) else { return false }
		
		for index in 0..<result.numberOfRanges {
			guard let range = path.rangeFromNSRange(result.rangeAtIndex(index)) else { continue }
			values.append(path.substringWithRange(range))
		}
		
		handler(values, request, response)
		
		return true
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
			
			defer { CJDispatchMain() { completionHandler(success, nserror) } }
			
			let requestHandler: CJHttpConnectionRequestHandler = { [weak self] connection, request in
				var matched = false
				let response = CJSwerve.httpResponseType.init(connection: connection, request: request)
				
				for handler in self?.handlers ?? [] {
					if handler.matches(connection, request, response) == true { matched = true; break }
				}
				
				if matched == false {
					DLog("No handler match found; closing connection [\(request)]")
					connection.close()
				}
			}
			
			// link new connections to http connection objects
			self.server.acceptHandler = { connection in
				var c = connection
				c.context = CJSwerve.httpConnectionType.init(connection: connection, requestHandler: requestHandler)
			}
			
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
	
	func addHandler(method: CJHttpMethod, pathEquals path: String, handler: CJHttpServerRequestPathEqualsHandler) {
		handlers.append(PathEqualsHandler(method: method, path: path, handler: handler))
	}
	
	func addHandler(method: CJHttpMethod, pathLike pattern: String, handler: CJHttpServerRequestPathLikeHandler) {
		do {
			let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpressionOptions(rawValue: 0))
			handlers.append(PathLikeHandler(method: method, regex: regex, handler: handler))
		}
		catch {
			DLog("Failed to install handler because of invalid regex pattern: \(pattern)")
		}
	}
	
	func addFileModule(localPath _lp: String, webPath _wp: String, recurses: Bool) {
		let localPath = _lp.hasSuffix("/") ? _lp : (_lp + "/")
		let webPath = _wp.hasSuffix("/") ? _wp.substringToIndex(_wp.endIndex.predecessor()) : _wp
		let fileManager = NSFileManager()
		
		self.addHandler(.Get, pathLike: "^\(webPath)/(.*)$") { values, request, response in
			// DLog("values = \(values)")
			
			let path = values.count == 2 ? values[1] : ""
			
			// prevent the user from escaping the base directory
			if path.rangeOfString("..") != nil {
				response.finish()
				response.close()
				return
			}
			
			CJDispatchBackground() {
				var response = response
				
				// assemble the file path
				let fileName = path.stringByRemovingPercentEncoding ?? ""
				let fileType = (fileName as NSString).pathExtension.lowercaseString
				let filePath = localPath + fileName
				
				//DLog("filePath = \(filePath)")
				
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
	
}
