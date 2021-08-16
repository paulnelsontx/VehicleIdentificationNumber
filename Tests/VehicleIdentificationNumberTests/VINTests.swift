//
//  VINTests.swift
//  VehicleIdentificationNumber
//
//  Created by Paul Nelson on 8/14/21.
//  Copyright © 2021 Paul W. Nelson, Nelson Logic. All rights reserved.
//

import XCTest
import Security
@testable import VehicleIdentificationNumber

class VINTests: XCTestCase {
    
    let testVINs = [ "1C4HJXFG8KW606403", "1J4FA69S43P322371", "2J4FY19E1KJ132175"]
    let badVINs = [ "123456abcdefRJ", "11111111111111", "1569AF", "1234567890ABCDEFGHI" ]

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testGoodVIN() throws {
        for testVIN in testVINs {
            let expect = expectation(description: "fetch vin detail")
            let vin = VehicleIdentificationNumber(VIN:testVIN)
            XCTAssert( vin.isValid, "VIN Invalid?")
            vin.fetch { data, error in
                XCTAssertNotNil(data, "Fetch failed")
                expect.fulfill()
            }
            wait(for: [expect], timeout: 10.0)
            let encoding = vin.encodeDetails()
            let restoredVIN = VehicleIdentificationNumber(VIN:"", detailData: encoding)
            XCTAssert( restoredVIN.information["VIN"] == testVIN, "Restored VIN detail does not match")
            XCTAssert( restoredVIN.VIN == testVIN, "Restored VIN does not match")
        }
    }
    
    func testIncorrectVIN() throws {
        for badVIN in badVINs {
            let vin = VehicleIdentificationNumber(VIN:badVIN)
            XCTAssertFalse( vin.isValid, "Bad vin checks as valid")
        }
    }
    
    func testTimeoutOK() throws {
        let expect = expectation(description: "fetch vin detail")
        let vin = VehicleIdentificationNumber(VIN:"1C4HJXFG8KW606403")
        XCTAssert( vin.isValid, "VIN Invalid?")
        vin.fetch(checkValidity: false, timeout: 5) { data, error in
            XCTAssertNotNil(data, "Fetch failed")
            expect.fulfill()
        }
        wait(for: [expect], timeout: 10.0)
        XCTAssert( vin.information["ErrorCode"]?.hasPrefix("0") ?? false )
    }
    func testTimeoutFail() throws {
        let expect = expectation(description: "fetch vin detail")
        let vin = VehicleIdentificationNumber(VIN:"1C4HJXFG8KW606403")
        XCTAssert( vin.isValid, "VIN Invalid?")
        vin.fetch(checkValidity: false, timeout: 0.01) { data, error in
            XCTAssertNotNil(error, "Fetch should have returned an error")
            expect.fulfill()
        }
        wait(for: [expect], timeout: 10.0)
    }

    func testReplacingVIN() throws {
        // this vin has a correct check code, but the character at offset 7 is
        // not valid
        let expect = expectation(description: "fetch vin detail")
        let vin = VehicleIdentificationNumber(VIN:"1M8GDM9AXKP042788")
        XCTAssert( vin.isValid, "VIN Invalid?")
        vin.fetch(checkValidity: false) { data, error in
            XCTAssertNotNil(data, "Fetch failed")
            expect.fulfill()
        }
        wait(for: [expect], timeout: 10.0)
        XCTAssert( vin.information["ErrorCode"]?.hasPrefix("3") ?? false )
        
        if let suggested = vin.information["SuggestedVIN"] {
            let expect2 = expectation(description: "fetch vin detail")
            let fixed = suggested.replacingOccurrences(of: "!", with: "8")
            let vin2 = VehicleIdentificationNumber(VIN:fixed)
            XCTAssertFalse( vin2.isValid )
            XCTAssertTrue( vin2.correctCheckCode() )
            XCTAssertTrue( vin2.isValid )
            vin2.fetch(checkValidity: false) { data, error in
                XCTAssertNotNil(data, "Fetch failed")
                expect2.fulfill()
            }
            wait(for: [expect2], timeout: 10.0)
            XCTAssert( vin2.information["ErrorCode"] ?? "" == "0") // no errors this time
            print("\(vin2.information["ErrorText"] ?? "Failed")")
        }
    }
    
    func testBadEncoding() throws {
        let randomSize = 3001
        var random = Data(capacity: randomSize)
        let _ : Int32 = random.withUnsafeMutableBytes( {
            let unsafeUInt8BufferPtr = $0.bindMemory(to: UInt8.self)
            if let unsafeUInt8Ptr = unsafeUInt8BufferPtr.baseAddress {
                return SecRandomCopyBytes(kSecRandomDefault, randomSize, unsafeUInt8Ptr)
            } else {
                return 0
            }
        })
        // restore from bogus data
        let bad = VehicleIdentificationNumber(VIN:"", detailData: random)
        XCTAssert( bad.VIN == "")
    }
    
    func testFetchNoVIN() throws {
        let noVIN = VehicleIdentificationNumber(VIN:"")
        let expectFail = expectation(description: "fetch without vin")
        noVIN.fetch { data, error in
            XCTAssertNotNil( error, "expected an error")
            expectFail.fulfill()
        }
        wait(for: [expectFail], timeout: 10.0)
    }
    
    func testBadManufacturer() throws {
        // test with VIN that checks but is invalid
        // VIN should start with 1FD but JFD also passes the isValid test
        let notVIN = VehicleIdentificationNumber(VIN: "JFDXE4FS6HDC75601" )
        XCTAssertTrue( notVIN.isValid, "notVIN isValid should be true")
        let expectNotVIN = expectation(description: "Fetch VIN that is not a real vehicle")
        notVIN.fetch { data, error in
            XCTAssertNotNil(data, "Fetch failed")
            expectNotVIN.fulfill()
        }
        wait(for: [expectNotVIN], timeout: 10.0)
        XCTAssert( notVIN.information["ErrorCode"] == "7", "Expected error code 7 (manufacturer not registered) error")
    }

}
