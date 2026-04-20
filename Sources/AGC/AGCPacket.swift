import Foundation

/// I/O packet encoding/decoding for AGC channel communication
/// Matches yaAGC packet format: 4-byte packets with signature bits
public struct AGCPacket {
    /// Encode a channel and value into a 4-byte packet
    /// Format: 00pppppp 01pppddd 10dddddd 11dddddd
    /// where ppppppppp is 9-bit channel (8-bit channel + u-bit) and ddddddddddddddd is 15-bit value
    /// - Parameters:
    ///   - channel: Channel number (0-511, with bit 8 as u-bit)
    ///   - value: 15-bit value (0-32767)
    /// - Returns: 4-byte packet, or nil if invalid
    public static func encode(channel: Int, value: Int) -> Data? {
        guard channel >= 0 && channel <= 0x1ff else { return nil }
        guard value >= 0 && value <= 0x7fff else { return nil }
        
        var packet = Data(count: 4)
        packet[0] = UInt8((channel >> 3) & 0x1F)
        packet[1] = UInt8(0x40 | ((channel << 3) & 0x38) | ((value >> 12) & 0x07))
        packet[2] = UInt8(0x80 | ((value >> 6) & 0x3F))
        packet[3] = UInt8(0xC0 | (value & 0x3F))
        
        return packet
    }
    
    /// Decode a 4-byte packet into channel and value
    /// - Parameter packet: 4-byte packet data
    /// - Returns: Tuple of (channel, value, uBit), or nil if invalid
    public static func decode(_ packet: Data) -> (channel: Int, value: Int, uBit: Int)? {
        guard packet.count >= 4 else { return nil }
        
        // Check signature bits
        guard (packet[0] & 0xC0) == 0x00 else { return nil }
        guard (packet[1] & 0xC0) == 0x40 else { return nil }
        guard (packet[2] & 0xC0) == 0x80 else { return nil }
        guard (packet[3] & 0xC0) == 0xC0 else { return nil }
        
        let channel = ((Int(packet[0]) & 0x1F) << 3) | ((Int(packet[1]) >> 3) & 0x07)
        let value = ((Int(packet[1]) & 0x07) << 12) | ((Int(packet[2]) & 0x3F) << 6) | (Int(packet[3]) & 0x3F)
        let uBit = (packet[0] & 0x20) != 0 ? 1 : 0
        
        return (channel, value, uBit)
    }
    
    /// Validate packet signature
    public static func isValid(_ packet: Data) -> Bool {
        guard packet.count >= 4 else { return false }
        return (packet[0] & 0xC0) == 0x00 &&
               (packet[1] & 0xC0) == 0x40 &&
               (packet[2] & 0xC0) == 0x80 &&
               (packet[3] & 0xC0) == 0xC0
    }
}


