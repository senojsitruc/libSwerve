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
	
	var server: CJSwerve!

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		var server = CJSwerve.httpServer(8080)
		
		server.addHandler(.Get, pathEqual: "/") { request, responseHandler in
			DLog("request = \(request)")
		}
		
		server.start() { success, error in
			DLog("success = \(success), error = \(error?.localizedDescription)")
		}
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		// Insert code here to tear down your application
	}


}

