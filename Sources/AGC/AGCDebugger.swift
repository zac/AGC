import Foundation

public struct AGCDisassembledInstruction: Equatable, Sendable {
    public let address: Int
    public let word: Int
    public let extraCode: Bool
    public let mnemonic: String
    public let operand: String
    public let text: String

    public init(address: Int, word: Int, extraCode: Bool, mnemonic: String, operand: String) {
        self.address = address
        self.word = word
        self.extraCode = extraCode
        self.mnemonic = mnemonic
        self.operand = operand
        let octal = String(format: "%05o", word & 0o77777)
        if operand.isEmpty {
            self.text = String(format: "%04o  %@  %@", address & 0o7777, octal, mnemonic)
        } else {
            self.text = String(format: "%04o  %@  %@  %@", address & 0o7777, octal, mnemonic, operand)
        }
    }
}

public enum AGCDisassembler {
    public static func disassemble(word: Int, at address: Int, extraCode: Bool) -> AGCDisassembledInstruction {
        let instruction = word & 0o77777
        let opcode = (instruction >> 9) | (extraCode ? 0o100 : 0)
        let address12 = instruction & 0o7777
        let address10 = instruction & 0o1777
        let ioChannel = instruction & 0o777
        let oct12 = String(format: "%04o", address12)
        let oct10 = String(format: "%04o", address10)
        let octIO = String(format: "%03o", ioChannel)

        let mnemonic: String
        let operand: String
        switch opcode {
        case 0o000...0o007:
            switch address12 {
            case 3:
                mnemonic = "RELINT"
                operand = ""
            case 4:
                mnemonic = "INHINT"
                operand = ""
            case 6:
                mnemonic = "EXTEND"
                operand = ""
            default:
                mnemonic = "TC"
                operand = oct12
            }
        case 0o010, 0o011:
            mnemonic = "CCS"
            operand = oct10
        case 0o012...0o017:
            mnemonic = "TCF"
            operand = oct12
        case 0o020, 0o021:
            mnemonic = address10 == 1 ? "DDOUBL" : "DAS"
            operand = address10 == 1 ? "" : oct10
        case 0o022, 0o023:
            mnemonic = "LXCH"
            operand = oct10
        case 0o024, 0o025:
            mnemonic = "INCR"
            operand = oct10
        case 0o026, 0o027:
            mnemonic = "ADS"
            operand = oct10
        case 0o030...0o037:
            mnemonic = "CA"
            operand = oct12
        case 0o040...0o047:
            mnemonic = "CS"
            operand = oct12
        case 0o050, 0o051:
            mnemonic = address12 == 0o17 ? "RESUME" : "INDEX"
            operand = address12 == 0o17 ? "" : oct12
        case 0o052, 0o053:
            mnemonic = "DXCH"
            operand = oct10
        case 0o054, 0o055:
            mnemonic = "TS"
            operand = oct10
        case 0o056, 0o057:
            mnemonic = "XCH"
            operand = oct10
        case 0o060...0o067:
            mnemonic = address12 == 0 ? "DOUBLE" : "AD"
            operand = address12 == 0 ? "" : oct12
        case 0o070...0o077:
            mnemonic = "MASK"
            operand = oct12
        case 0o100:
            mnemonic = "READ"
            operand = octIO
        case 0o101:
            mnemonic = "WRITE"
            operand = octIO
        case 0o102:
            mnemonic = "RAND"
            operand = octIO
        case 0o103:
            mnemonic = "WAND"
            operand = octIO
        case 0o104:
            mnemonic = "ROR"
            operand = octIO
        case 0o105:
            mnemonic = "WOR"
            operand = octIO
        case 0o106:
            mnemonic = "RXOR"
            operand = octIO
        case 0o107:
            mnemonic = "EDRUPT"
            operand = oct12
        case 0o110, 0o111:
            mnemonic = "DV"
            operand = oct10
        case 0o112...0o117:
            mnemonic = "BZF"
            operand = oct12
        case 0o120, 0o121:
            mnemonic = "MSU"
            operand = oct10
        case 0o122, 0o123:
            mnemonic = "QXCH"
            operand = oct10
        case 0o124, 0o125:
            mnemonic = "AUG"
            operand = oct10
        case 0o126, 0o127:
            mnemonic = "DIM"
            operand = oct10
        case 0o130...0o137:
            mnemonic = "DCA"
            operand = oct12
        case 0o140...0o147:
            mnemonic = "DCS"
            operand = oct12
        case 0o150...0o157:
            mnemonic = "INDEX"
            operand = oct12
        case 0o160, 0o161:
            mnemonic = "SU"
            operand = oct10
        case 0o162...0o167:
            mnemonic = "BZMF"
            operand = oct12
        case 0o170...0o177:
            mnemonic = "MP"
            operand = oct12
        default:
            mnemonic = "UNK"
            operand = oct12
        }

        return AGCDisassembledInstruction(
            address: address,
            word: instruction,
            extraCode: extraCode,
            mnemonic: mnemonic,
            operand: operand
        )
    }
}

public struct AGCErasableWatch: Equatable, Sendable, Identifiable {
    public var id: Int { address }
    public let address: Int
    public let value: Int

    public init(address: Int, value: Int) {
        self.address = address & 0o1777
        self.value = value & 0o177777
    }
}

public struct AGCDebuggerSnapshot: Equatable, Sendable {
    public let current: AGCDisassembledInstruction
    public let extraCode: Bool
    public let inIsr: Bool
    public let breakpoints: [Int]
    public let watches: [AGCErasableWatch]
    public let hitBreakpoint: Bool
    public let listing: [AGCDisassembledInstruction]
    public let yaAGCPackets: [String]

    public init(
        current: AGCDisassembledInstruction,
        extraCode: Bool,
        inIsr: Bool,
        breakpoints: [Int],
        watches: [AGCErasableWatch],
        hitBreakpoint: Bool,
        listing: [AGCDisassembledInstruction],
        yaAGCPackets: [String]
    ) {
        self.current = current
        self.extraCode = extraCode
        self.inIsr = inIsr
        self.breakpoints = breakpoints
        self.watches = watches
        self.hitBreakpoint = hitBreakpoint
        self.listing = listing
        self.yaAGCPackets = yaAGCPackets
    }
}
