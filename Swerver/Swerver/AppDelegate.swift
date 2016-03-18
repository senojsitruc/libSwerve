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
		//CJCrypto.generateKeyPair(label: "us.curtisjones.libSwerve.tlsKey-002")
		//tlsIdentity = SecIdentity.create(numberOfBits: 4096, error: nil)
		//if let identity = CJCrypto.identityWithLabel("us.curtisjones.libSwerve.001") {
		//	CJCrypto.setupTLS(identity)
		//}
		
		let tcpServer = CJSwerve.tcpServerType.init(port: 8080)
		var httpServer = CJSwerve.httpServerType.init(server: tcpServer)
		
		///
		/// default handler
		///
		httpServer.addHandler(.Get, pathEquals: "/") { request, response in
			//DLog("request = \(request)")
			
			CJDispatchBackground() {
				var response = response
				
				response.addHeader("Content-Type", value: "text/plain")
				response.addHeader("Content-Length", value: 15)
				response.addHeader("Connection", value: "keep-alive")
				response.write("This is a test.")
				response.finish()
			}
		}
		
		///
		/// downloads file handler
		///
		do {
			let filePath = NSSearchPathForDirectoriesInDomains(.DownloadsDirectory, .UserDomainMask, true)[0]
			httpServer.addFileModule(localPath: filePath, webPath: "/Downloads/", recurses: true)
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
