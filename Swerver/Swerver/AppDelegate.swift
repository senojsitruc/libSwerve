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
	//setupCertificate()
		setupHttpServer()
	}

	func applicationWillTerminate(aNotification: NSNotification) { }
	
	func applicationShouldTerminate(sender: NSApplication) -> NSApplicationTerminateReply {
		server?.stop() { success, error in
			DLog("success = \(success), error = \(error?.localizedDescription)")
			sender.replyToApplicationShouldTerminate(true)
		}
		
		return .TerminateLater
	}
	
	
	
	
	
	private final func setupCertificate() {
//	if let tlsIdentity = CJCrypto.generateIdentity(keySizeInBits: 4096, label: "us.curtisjones.libSwerve.tlsKey-002") {
		if let tlsIdentity = CJCrypto.identityWithLabel("us.curtisjones.libSwerve.tlsKey-002") {
			CJCrypto.setupTLS(tlsIdentity)
			DLog("tlsIdentity = \(tlsIdentity)")
		}
	}
	
	private final func setupHttpServer() {
		let tcpServer = CJSwerve.tcpServerType.init(port: 8080)
//	let tcpServer = CJSwerve.tlsTcpServerType.init(port: 8080)
		var httpServer = CJSwerve.httpServerType.init(server: tcpServer)
		
		///
		/// default handler
		///
		httpServer.addHandler(.Get, pathEquals: "/", waitForData: true) { match in
			CJDispatchBackground() {
				var response = match.response
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
		/// file upload handler
		///
		httpServer.addHandler(.Post, pathEquals: "/upload/url-form", waitForData: false) { match in
			var request = match.request
			
			DLog("\(request.headers)")
			
			if request.contentType == "application/x-www-form-urlencoded" {
				request.contentHandler = { value, done in
					if let values = value as? [String: AnyObject] {
						DLog("values = \(values)")
					}
					if done == true {
						var response = match.response
						response.addHeader("Content-Type", value: "text/plain")
						response.addHeader("Content-Length", value: 26)
						response.addHeader("Connection", value: "keep-alive")
						response.write("Thank you have a nice day.")
						response.finish()
					}
				}
				request.resume()
			}
			else {
				//match.request.close()
				DLog("Unsupported content type = \(request.contentType)")
			}
		}
		
//		let request = match.request
//		let response = match.response
			
			//      waitForData = FALSE
			//
			// simple form
			//
			// if request.contentType == "application/x-www-form-urlencoded" {
			//   request.contentHandler = { value, done in
			//     if let values = value as? [String: String] {
			//       // partial name-value pairs until done=true
			//     }
			//   }
			// }
			//
			// multipart form
			//
			// else if request.contentType == "multipart/form-data" {
			//   request.contentHandler = { value, done in
			//     if let formData = value as? CJFormData {
			//       // formData.context | name | fileName | contentDisposition | contentType
			//       if formData.context == nil {
			//         formData.context = <open file for writing>
			//       }
			//       if formData.newData != nil {
			//         (formData.context as? NSFileOutputStream)?.write(formData.newData)
			//       }
			//       if done == true {
			//         (formData.context as? NSFileOutputStream)?.close()
			//         formData.context = nil
			//       }
			//     }
			//   }
			// }
			// else if request.contentType == "text/plain" {
			//
			// }
			//
			// request.resume()
			//
			// -----
			//
			//      waitForData = TRUE
			//
			// simple form
			//
			// request.values: [String: AnyObject]
			//   formData.context | name | fileName | contentDisposition | contentType | newData
			//   default
			//
			
//			CJDispatchBackground() {
//				var response = response
//				
//				response.addHeader("Content-Type", value: "text/plain")
//				response.addHeader("Content-Length", value: 15)
//				response.addHeader("Connection", value: "keep-alive")
//				response.write("This is a test.")
//				response.finish()
//			}
//			
//		}
		
		///
		/// start the http server
		///
		httpServer.start() { success, error in
			DLog("success = \(success), error = \(error?.localizedDescription)")
			self.server = httpServer
		}
		
		//tcpServer.enablePortMapping(externalPort: 0)
		
		server = httpServer
	}
	
}
