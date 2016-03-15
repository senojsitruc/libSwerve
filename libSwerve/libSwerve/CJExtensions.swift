//
//  CJExtensions.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

let dlogQueue = dispatch_queue_create("us.curtisjones.libSwerve.CJExtensions.dlogqueue", nil)

public func DLog(message: String?, file: String = #file, line: Int = #line, function: String = #function) {
	dispatch_async(dlogQueue) {
		if let message = message where message.isEmpty == false {
			print("\(NSDate()): \(file)+\(line)::\(function).. \(message)")
		}
		else {
			print("\(NSDate()): \(file)+\(line)::\(function)")
		}
	}
}

internal func cjstrerror() -> String? {
	let cstring = strerror(errno)
	let strleng = Int(strlen(cstring))
	let data = NSData(bytesNoCopy: cstring, length: strleng)
	let errstr = String(data: data, encoding: NSUTF8StringEncoding)
	
	return errstr
}

extension NSError {
	
	convenience init(domain: String = "", code: Int = 0, description: String?) {
		self.init(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: description ?? ""])
	}
	
}
