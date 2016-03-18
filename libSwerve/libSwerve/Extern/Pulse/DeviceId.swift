import Foundation

public class DeviceId: Equatable, CustomStringConvertible {
	
	let hash: NSData
	
	private init!(hash: NSData) {
		self.hash = hash
		
		if (hash.length != 256 / 8) {
			return nil
		}
	}
	
	public convenience init!(hash: [UInt8]) {
		self.init(hash: NSData(bytes: hash, length: hash.count))
	}
	
	public convenience init!(cert: SecCertificate) {
		self.init(hash: cert.data.SHA256Digest())
	}
	
	public var description: String {
		//return "-".join(base32Groups)
		return ""
	}
	
//	public var sha256 : [UInt8] {
//		return hash.bytes
//	}
	
//	private var base32Groups: [String] {
//		var result: [String] = []
//		base32PlusChecks.processChunksOfSize(7) {
//			result.append($0)
//		}
//		return result
//	}
	
//	private var base32PlusChecks: String {
//		var result = ""
//		base32.processChunksOfSize(13) {
//			result = result + $0 + String(LuhnBase32Wrong.calculateCheckDigit($0))
//		}
//		return result
//	}
	
//	private var base32: String {
//		let result = hash.base32String()
//		return result.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "="))
//	}
	
}

public func == (lhs: DeviceId, rhs: DeviceId) -> Bool {
	return lhs.hash == rhs.hash
}

extension String {
	
	func processChunksOfSize(chunkSize: Int, _ closure: (String)->()) {
		let amountOfChunks = self.characters.count / chunkSize
		var begin = self.startIndex
		for _ in 0..<amountOfChunks {
			let end = begin.advancedBy(chunkSize)
			let chunk = self[begin..<end]
			
			closure(chunk)
			
			begin = end
		}
	}
	
}
