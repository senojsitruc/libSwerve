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
			
			// response.write() { finished in return NSData(contentsOfURL: ...); finished = true }
			// response.finish()
		}
		
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
