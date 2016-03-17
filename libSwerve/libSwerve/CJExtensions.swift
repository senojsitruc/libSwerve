//
//  CJExtensions.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

extension NSError {
	
	convenience init(domain: String = "", code: Int = 0, description: String?) {
		self.init(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: description ?? ""])
	}
	
}

extension String {
	
	func rangesOfString(query: String, options mask: NSStringCompareOptions) -> [Range<String.Index>] {
		var ranges = [Range<String.Index>]()
		var curRange = self.startIndex..<self.endIndex
		
		while true {
			if let range = self.rangeOfString(query, options: mask, range: curRange) {
				ranges.append(range)
				curRange = range.endIndex..<self.endIndex
			}
			else {
				break
			}
		}
		
		return ranges
	}
	
	func rangeFromNSRange(nsRange : NSRange) -> Range<String.Index>? {
		let from16 = utf16.startIndex.advancedBy(nsRange.location, limit: utf16.endIndex)
		let to16 = from16.advancedBy(nsRange.length, limit: utf16.endIndex)
		var range: Range<String.Index>? = nil
		
		if let from = String.Index(from16, within: self), to = String.Index(to16, within: self) {
			range = from ..< to
		}
		
		return range
	}
	
	func stringByTrimmingWhitespace() -> String {
		return self.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
	}
	
}
