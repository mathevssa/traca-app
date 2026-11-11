import Testing
import UIKit
@testable import Traca

struct FontesDaMarca {
    @Test func youngSerifCarregada() {
        #expect(UIFont(name: "YoungSerif-Regular", size: 17) != nil)
    }

    @Test func hankenGroteskCarregada() {
        #expect(UIFont.fontNames(forFamilyName: "Hanken Grotesk").isEmpty == false)
    }
}
