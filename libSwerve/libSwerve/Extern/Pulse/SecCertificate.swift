import Security

extension SecCertificate {
	
	public var data: NSData {
		return SecCertificateCopyData(self) as NSData
	}
	
	public var deviceId: DeviceId {
		return DeviceId(cert:self)
	}
	
}
