import Foundation

public enum AGCError: Error {
    case invalidCoreImage
    case memoryError
}

public final class AGCEngine {
    /// The simulation state.
    public var state: AGCState
    
    /// The I/O delegate (using the protocol defined in AGCIO.swift).
    public var ioDelegate: AGCIOProtocol?
    
    /// Task that runs the simulation engine loop.
    private var engineTask: Task<Void, Never>? = nil
    
    /// Simulated program counter.
    public var programCounter: Int = 0
    
    /// Instructions loaded from the core image (each word is a 16-bit value).
    private var instructions: [UInt16] = []
    
    // AGC instruction masks
    private let EXTRACODE: Int = 0o7 
    private let INDEX: Int = 0o7777
    private let BASIC: Int = 0o7777
    
    public init(state: AGCState) throws {
        self.state = state
        try loadCoreImage()
        
        // Initialize I/O channels similar to agc_engine_init.c
        for i in 0..<state.inputChannels.count {
            state.inputChannels[i] = 0
        }
        
        // Channels 030-033 default to 077777 (signals inverted)
        for i in 0o30...0o33 {
            state.inputChannels[i] = 0o77777
        }
        
        // Initialize erasable memory
        for bank in 0..<8 {
            for addr in 0..<0o400 {
                state.erasableMemory[bank][addr] = 0
            }
        }
        
        // Set initial program counter (RegZ) to 0o4000
        state.programCounter = 0o4000
        
        // Initialize other CPU state
        state.cycleCounter = 0
        state.extracode = false
        state.overflow = false
        state.index = 0
    }
    
    private func loadCoreImage() throws {
        guard let data = state.coreImage else {
            throw AGCError.invalidCoreImage
        }
        
        // Core image should be a multiple of 2 bytes (16-bit words)
        guard data.count % 2 == 0 else {
            throw AGCError.invalidCoreImage
        }
        
        // Process the core rope binary image
        var bank = 2  // Start with bank 2 as per original code
        var offset = 0
        
        // Read 16-bit words from the binary
        for i in stride(from: 0, to: data.count, by: 2) {
            // Read two bytes and form a 16-bit word (big endian)
            let word = (Int(data[i]) << 8) | Int(data[i + 1])
            
            // Store in fixed memory following the bank ordering: 2,3,0,1,4,5,6,...,35
            state.fixedMemory[bank][offset] = word >> 1
            
            offset += 1
            if offset >= 0o2000 {
                offset = 0
                // Advance to next bank following original ordering
                bank = switch bank {
                case 2: 3
                case 3: 0
                case 0: 1
                case 1: 4
                default: bank + 1
                }
                
                // Check if we've exceeded available banks
                if bank >= state.fixedMemory.count {
                    throw AGCError.memoryError
                }
            }
        }
    }
    
    /// Execute one AGC instruction
    private func executeInstruction(_ instruction: Int) {
        if state.extracode {
            executeExtendedInstruction(instruction)
            state.extracode = false
            return
        }
        
        let opcode = (instruction >> 12) & 0o7
        let address = instruction & 0o7777
        
        switch opcode {
        case 0: // TC - Transfer Control
            state.returnAddress = state.programCounter
            state.programCounter = address
            
        case 1: // CCS - Count, Compare, and Skip
            let value = readMemory(address)
            if value > 0 {
                state.programCounter += 1
            } else if value < 0 {
                state.programCounter += 2
            } else {
                state.programCounter += 3
            }
            state.accumulator = abs(value) - 1
            
        case 2: // INDEX
            state.index = readMemory(address)
            
        case 3: // RESUME
            // Implement RESUME logic
            break
            
        // Add other opcodes...
            
        default:
            break
        }
    }
    
    private func executeExtendedInstruction(_ instruction: Int) {
        // Implement extended instruction set
    }
    
    private func readMemory(_ address: Int) -> Int {
        // Implement memory read logic
        return 0
    }
    
    private func writeMemory(_ address: Int, _ value: Int) {
        // Implement memory write logic
    }
    
    /// Execute one simulation cycle.
    /// (In a full implementation this function would perform decoding and execution
    /// of a wide range of AGC instructions. Here we demonstrate a simple fetch–execute cycle.)
    private func executeCycle() async {
        // Fetch instruction from current program counter
        let instruction = readMemory(state.programCounter)
        
        // Execute the instruction
        executeInstruction(instruction)
        
        // Update cycle counter
        state.cycleCounter += 1
        
        // Handle I/O
        if let io = ioDelegate {
            await io.channelRoutine()
        }
    }
    
    /// Start the simulation engine.
    public func startEngine() {
        engineTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.executeCycle()
                try? await Task.sleep(nanoseconds: 11_700) // ~11.7 microseconds per instruction
            }
        }
    }
    
    /// Stop the simulation engine.
    public func stopEngine() {
        engineTask?.cancel()
    }
}

extension AGCEngine: @unchecked Sendable { } 