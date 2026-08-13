import Testing
@testable import AGC

@Suite("DSKY Tests")
struct DSKYTests {
    private func channel10Value(row: Int, left: Int = 0, right: Int = 0, sign: Bool = false) -> Int {
        return (row << 11) | ((left & 0o37) << 5) | (right & 0o37) | (sign ? 0o400 : 0)
    }

    @Test func dskyInitialization() {
        let dsky = DSKY()
        
        // Test initial state
        #expect(dsky.verbDigits == [-1, -1])
        #expect(dsky.nounDigits == [-1, -1])
        #expect(!dsky.verbNounFlash)
        #expect(!dsky.lampTest)
    }
    
    @Test func channel10DecodesVerbNounAndModeRows() {
        let dsky = DSKY()
        
        dsky.channelOutput(channel: 0o10, value: channel10Value(row: 10, left: 21, right: 3))
        dsky.channelOutput(channel: 0o10, value: channel10Value(row: 9, left: 25, right: 27))
        dsky.channelOutput(channel: 0o10, value: channel10Value(row: 11, left: 15, right: 30))
        
        #expect(dsky.verbDigits == [0, 1])
        #expect(dsky.nounDigits == [2, 3])
        #expect(dsky.modeDigits == [4, 5])
    }

    @Test func channel10DecodesRegisterDigitsAndBlanks() {
        let dsky = DSKY()

        dsky.channelOutput(channel: 0o10, value: channel10Value(row: 8, right: 25))
        dsky.channelOutput(channel: 0o10, value: channel10Value(row: 7, left: 27, right: 0, sign: true))

        #expect(dsky.r1.digits[0] == 2)
        #expect(dsky.r1.digits[1] == 3)
        #expect(dsky.r1.digits[2] == -1)
        #expect(dsky.formatRegister(dsky.r1).hasPrefix("+23 "))
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
        let input = dsky.channelInput()
        #expect(input != nil, "Keypress should be queued")
        #expect(input?.first == AGCChannelInput(channel: 0o15, value: 0o21), "Keycode should match")
    }

    @Test func keypressQueueDeliversOneChannel15PerPoll() async {
        let dsky = DSKY()
        await dsky.sendKeycode(0o21)
        await dsky.sendKeycode(3)
        await dsky.sendKeycode(0o34)
        let first = dsky.channelInput()
        let second = dsky.channelInput()
        let third = dsky.channelInput()
        #expect(first?.first == AGCChannelInput(channel: 0o15, value: 0o21))
        #expect(second?.first == AGCChannelInput(channel: 0o15, value: 3))
        #expect(third?.first == AGCChannelInput(channel: 0o15, value: 0o34))
        let empty = dsky.channelInput()
        #expect(empty == nil)
    }

    @Test func keypressQueuePreservesScriptedPressAndReleasePairs() async {
        let dsky = DSKY()
        let sequence = [0o21, 0, 0o3, 0, 0o5, 0, 0o34, 0]

        for keycode in sequence {
            await dsky.sendKeycode(keycode)
        }

        for keycode in sequence {
            let next = dsky.channelInput()
            #expect(next?.first == AGCChannelInput(channel: 0o15, value: keycode))
        }

        #expect(dsky.channelInput() == nil)
    }
    
    @Test func proKey() async {
        let dsky = DSKY()

        await dsky.sendProKey(true)

        let mask = dsky.channelInput()
        let pro = dsky.channelInput()
        #expect(mask?.first == AGCChannelInput(channel: 0o432, value: 0o20000), "Mask should be set")
        #expect(pro?.first == AGCChannelInput(channel: 0o32, value: 0), "PRO writes inverted bit 14 of channel 032")
        #expect(dsky.proKeyPressed)
    }
}
