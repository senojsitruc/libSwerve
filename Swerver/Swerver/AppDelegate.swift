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
		
		httpServer.addHandler(.Get, pathEquals: "/") { request, responseHandler in
			DLog("request = \(request)")
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
