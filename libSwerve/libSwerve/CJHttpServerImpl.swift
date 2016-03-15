//
//  CJHttpServer1.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

struct CJHttpServerImpl: CJHttpServer {
	
	var isRunning = false
	
	init() {
		
	}
	
	func start(completionHandler: (Bool, NSError?) -> Void) {
		
	}
	
	func stop(completionHandler: (Bool, NSError?) -> Void) {
		
	}
	
	func addHandler(method: CJHttpMethod, pathEqual: String, handler: CJHttpServerRequestPathEqualsHandler) {
		
	}
	
	func addHandler(method: CJHttpMethod, pathLike: String, handler: CJHttpServerRequestPathLikeHandler) {
		
	}
	
}
