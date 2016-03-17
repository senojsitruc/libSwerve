//
//  AppDelegate.swift
//  Swerver
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Cocoa
import libSwerve

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

	@IBOutlet weak var window: NSWindow!
	
	var server: CJHttpServer!

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		let tcpServer = CJSwerve.tcpServerType.init(port: 8080)
		var httpServer = CJSwerve.httpServerType.init(server: tcpServer)
		
		///
		/// downloads handler
		///
		httpServer.addHandler(.Get, pathLike: "^/Downloads/(.+)$") { values, request, response in
			DLog("values = \(values)")
			
			// we expect two match values: the full string and the matched subpath
			if values.count != 2 {
				response.close()
				return
			}
			
			let path = values[1]
			
			// prevent the user from escaping the base directory
			if path.rangeOfString("..") != nil {
				response.close()
				return
			}
			
			CJDispatchBackground() {
				var response = response
				
				// assemble the file path
				let fileName = path
				let fileType = (fileName as NSString).pathExtension.lowercaseString
				let filePath = NSSearchPathForDirectoriesInDomains(.DownloadsDirectory, .UserDomainMask, true)[0] + "/" + fileName
				
				DLog("filePath = \(filePath)")
				
				// close the connection if the target file doesn't exist
				guard let fileData = NSData(contentsOfFile: filePath) else {
					response.close()
					return
				}
				
				// decode the proper mime-type
				if fileType == "jpg" || fileType == "jpeg" {
					response.addHeader("Content-Type", value: "image/jpeg")
				}
				else if fileType == "png" {
					response.addHeader("Content-Type", value: "image/png")
				}
				else if fileType == "gif" {
					response.addHeader("Content-Type", value: "image/gif")
				}
				
				// configure and send the response
				response.addHeader("Content-Length", value: fileData.length)
				response.addHeader("Connection", value: "keep-alive")
				response.write(fileData)
				response.finish()
			}
		}
		
		///
		/// default handler
		///
		httpServer.addHandler(.Get, pathEquals: "/") { request, response in
			DLog("request = \(request)")
			
			CJDispatchBackground() {
				var response = response
				
				let fileName = (request.path as NSString).lastPathComponent
				let fileType = (fileName as NSString).pathExtension.lowercaseString
				let filePath = NSSearchPathForDirectoriesInDomains(.DownloadsDirectory, .UserDomainMask, true)[0] + "/" + fileName
				
				DLog("filePath = \(filePath)")
				
				guard let fileData = NSData(contentsOfFile: filePath) else {
					response.finish()
					return
				}
				
				if fileType == "jpg" || fileType == "jpeg" {
					response.addHeader("Content-Type", value: "image/jpeg")
				}
				else if fileType == "png" {
					response.addHeader("Content-Type", value: "image/png")
				}
				else if fileType == "gif" {
					response.addHeader("Content-Type", value: "image/gif")
				}
				
				response.addHeader("Content-Length", value: fileData.length)
				response.addHeader("Connection", value: "keep-alive")
				response.write(fileData)
				response.finish()
			}
		}
		
		///
		/// start the http server
		///
		httpServer.start() { success, error in
			DLog("success = \(success), error = \(error?.localizedDescription)")
			self.server = httpServer
		}
		
		server = httpServer
	}

	func applicationWillTerminate(aNotification: NSNotification) { }
	
	func applicationShouldTerminate(sender: NSApplication) -> NSApplicationTerminateReply {
		server?.stop() { success, error in
			DLog("success = \(success), error = \(error?.localizedDescription)")
			sender.replyToApplicationShouldTerminate(true)
		}
		
		return .TerminateLater
	}
	
}
