//
//  CJSwerve.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

struct CJSwerve {
	
	private let httpServerType = CJHttpServerImpl.self
	
	init() {
	}
	
	func httpServer(port: Int16) -> CJHttpServer {
		return httpServerType.init()
	}
	
}
