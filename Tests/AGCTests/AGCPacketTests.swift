import Foundation
import Testing
@testable import AGC

@Suite("AGCPacket Tests")
struct AGCPacketTests {
    @Test func packetEncodeDecode() throws {
        // Test encoding and decoding round-trip
        let channel = 0o15
        let value = 0o21
        
        let packet = try #require(AGCPacket.encode(channel: channel, value: value))
        #expect(packet.count == 4, "Packet should be 4 bytes")
        
        let decoded = try #require(AGCPacket.decode(packet))
        #expect(decoded.channel == channel, "Decoded channel should match")
        #expect(decoded.value == value, "Decoded value should match")
    }
    
    @Test func packetValidation() {
        // Test valid packet signature
        let validPacket = Data([0x00, 0x40, 0x80, 0xC0])
        #expect(AGCPacket.isValid(validPacket), "Valid packet should pass validation")
        
        // Test invalid packet signature
        let invalidPacket = Data([0x00, 0x00, 0x00, 0x00])
        #expect(!AGCPacket.isValid(invalidPacket), "Invalid packet should fail validation")
    }
    
    @Test func packetChannel10() throws {
        // Test channel 10 encoding (display data)
        let channel = 0o10
        let value = 0o50021  // Example display value
        
        let packet = try #require(AGCPacket.encode(channel: channel, value: value))
        let decoded = try #require(AGCPacket.decode(packet))
        
        #expect(decoded.channel == channel)
        #expect(decoded.value == value)
    }
    
    @Test func packetChannel163() throws {
        // Test channel 163 encoding (indicator lights)
        let channel = 0o163
        let value = 0o420  // Example indicator value (KEY_REL | OPER_ERR | RESTART)
        
        let packet = try #require(AGCPacket.encode(channel: channel, value: value))
        let decoded = try #require(AGCPacket.decode(packet))
        
        #expect(decoded.channel == channel)
        #expect(decoded.value == value)
    }
}

