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

extension dispatch_data_t {
	
	var length: Int { return dispatch_data_get_size(self) }
	
	internal func hexdump() { }
	
	///
	/// Returns the next line of data as a string. The string itself does not include the new line
	/// characters; the range does.
	///
	internal func readLine(after after: Int = 0) -> (String, NSRange)? {
		guard let range = rangeOfNewline(offset: after) else { return nil }
		guard let data = dispatch_data_create_subrange(self, after, range.location) else { return nil }
		var string = ""
		
		dispatch_data_apply(data) { region, offset, buffer, size in
			string += String(data: NSData(bytes: buffer, length: size), encoding: NSUTF8StringEncoding) ?? ""
			return true
		}
		
		return (string, NSMakeRange(after, data.length + range.length))
	}
	
	///
	///
	///
	internal func rangeOfByte(byte: UInt8, after: Int = 0, maxLength: Int = 0) -> NSRange? {
		var range: NSRange?
		
		dispatch_data_apply(self) { region, offset, _buffer, _size in
			// we haven't reached the specified offset yet
			if after > 0 && offset + _size < after { return true }
			
			let size: Int
			let buffer: UnsafePointer<UInt8>
			
			// we need a UInt8 pointer and we need to advance to the designated offset if the designated
			// offset falls within this region (instead of a previous region)
			if after > offset {
				buffer = UnsafePointer<UInt8>(_buffer).advancedBy(after - offset)
				size = _size - (after - offset)
			}
			else {
				buffer = UnsafePointer<UInt8>(_buffer)
				size = _size
			}
			
			// enumerate the bytes of the region. if we find a \r, check for a subsequent \n. if a \r
			for i in 0..<size {
				if buffer[i] == byte {
					range = NSMakeRange(offset + i + (after - offset), 1)
					return false
				}
			}
			
			return true
		}
		
		return range
	}
	
	///
	/// Returns a string spanning the given range of this data.
	///
	internal func stringWithRange(range: NSRange) -> String? {
		var string: String = ""
		var length = 0
		
		dispatch_data_apply(self) { region, offset, _buffer, _size in
			// we haven't reached the specified offset yet
			if range.location > 0 && offset + _size < range.location { return true }
			
			var size: Int
			let buffer: UnsafePointer<UInt8>
			
			// we need a UInt8 pointer and we need to advance to the designated offset if the designated
			// offset falls within this region (instead of a previous region)
			if range.location > offset {
				buffer = UnsafePointer<UInt8>(_buffer).advancedBy(range.location - offset)
				size = _size - (range.location - offset)
			}
			else {
				buffer = UnsafePointer<UInt8>(_buffer)
				size = _size
			}
			
			// don't get more data than was asked for
			if size > length + range.length {
				size = range.length - length
			}
			
			// get the string and update the length
			string += String(data: NSData(bytes: buffer, length: size), encoding: NSUTF8StringEncoding) ?? ""
			length += size
			
			// continue if we still need more data
			return length < range.length
		}
		
		return string
	}
	
	///
	/// Matches on \r or \n or \r\n
	///
	internal func rangeOfNewline(offset _offset: Int = 0) -> NSRange? {
		var foundcr = false
		var range: NSRange?
		
		dispatch_data_apply(self) { region, offset, _buffer, _size in
			// we haven't reached the specified offset yet
			if _offset > 0 && offset + _size < _offset { return true }
			
			let size: Int
			let buffer: UnsafePointer<UInt8>
			
			// we need a UInt8 pointer and we need to advance to the designated offset if the designated
			// offset falls within this region (instead of a previous region)
			if _offset > offset {
				buffer = UnsafePointer<UInt8>(_buffer).advancedBy(_offset - offset)
				size = _size - (_offset - offset)
			}
			else {
				buffer = UnsafePointer<UInt8>(_buffer)
				size = _size
			}
			
			// enumerate the bytes of the region. if we find a \r, check for a subsequent \n. if a \r
			// falls at the end of a region, we'll need to check the next region (if any) for a \n.
			//
			// if we have not found a \r
			//   if the current char is a \r
			//     set foundcr = true
			//   else if the current char is a \n
			//     set the range & break
			// else if we have found a \r
			//   if the current char is a \n
			//     set the range & break (length = 2)
			//   else
			//     set the range & break (length = 1)
			//
			for i in 0..<size {
				if foundcr == false {
					if buffer[i] == 0x0D {
						foundcr = true
					}
					else if buffer[i] == 0x0A {
						range = NSMakeRange(offset+i, 1)
						break
					}
				}
				else {
					range = NSMakeRange(offset+i-1, buffer[i] == 0x0A ? 2 : 1)
					break
				}
			}
			
			return true
		}
		
		// if we found a \r at the end of the last region, we naively thought we should check the start
		// of the next region. create a range for the \r which is the last byte in the data.
		if foundcr == true && range == nil {
			range = NSMakeRange(dispatch_data_get_size(self) - 1, 1)
		}
		
		return range
	}
	
	///
	///
	///
	internal func subrangeFromIndex(index: Int, length: Int = 0) -> dispatch_data_t {
		return dispatch_data_create_subrange(self, index, length > 0 ? length : (self.length - index))
	}
	
}

internal func +(lhs: dispatch_data_t, rhs: dispatch_data_t) -> dispatch_data_t {
	return dispatch_data_create_concat(lhs, rhs)
}

internal func +=<K, V> (inout left: [K : V], right: [K : V]) { for (k, v) in right { left[k] = v } }

extension NSFileManager {
	
	func isDirectory(path: String) -> Bool {
		var isdir: ObjCBool = false
		self.fileExistsAtPath(path, isDirectory: &isdir)
		return Bool(isdir)
	}
	
}
