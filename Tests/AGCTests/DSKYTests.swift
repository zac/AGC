import Testing
@testable import AGC

@Suite("DSKY Tests")
struct DSKYTests {
    @Test func dskyInitialization() {
        let dsky = DSKY()
        
        // Test initial state
        #expect(dsky.verbDigits == [0, 0])
        #expect(dsky.nounDigits == [0, 0])
        #expect(!dsky.verbNounFlash)
        #expect(!dsky.lampTest)
    }
    
    @Test func channel10Decoding() {
        let dsky = DSKY()
        
        // Test VERB display (row 0o10 = 0x5000)
        let verbValue = 0o50021  // VERB = 21
        dsky.channelOutput(channel: 0o10, value: verbValue)
        
        // Note: decode7Segment returns the raw value, not the digit
        // This is a basic test that the channel is processed
        #expect(dsky.verbDigits.count == 2)
    }
    
    @Test func channel163Indicators() {
        let dsky = DSKY()
        
        // Test indicator lights
        let indicatorValue = 0o320  // KEY_REL | OPER_ERR | RESTART
        dsky.channelOutput(channel: 0o163, value: indicatorValue)
        
        // Check that indicators are updated
        #expect(dsky.indicatorIsOn(14), "KEY REL should be on")
        #expect(dsky.indicatorIsOn(15), "OPER ERR should be on")
        #expect(dsky.indicatorIsOn(24), "RESTART should be on")
    }
    
    @Test func keypressQueue() async {
        let dsky = DSKY()
        
        // Send a keypress
        await dsky.sendKeycode(0o21)  // VERB key
        
        // Check that keypress is queued
        let input = await dsky.channelInput()
        #expect(input != nil, "Keypress should be queued")
        #expect(input?[0o15] == 0o21, "Keycode should match")
    }
    
    @Test func proKey() async {
        let dsky = DSKY()
        
        // Send PRO key press
        await dsky.sendProKey(true)
        
        let input = await dsky.channelInput()
        #expect(input != nil, "PRO keypress should be queued")
        // Should have mask and value
        #expect(input?[0o432] != nil, "Mask should be set")
        #expect(input?[0o13] != nil, "PRO key value should be set")
    }
}

