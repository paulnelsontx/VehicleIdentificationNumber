//
//  VehicleIdentificationNumber.swift
//  VehicleIdentificationNumber
//
//  Created by Paul Nelson on 8/14/21.
//  Copyright © 2021 Paul W. Nelson, Nelson Logic. All rights reserved.
//  nelsonlogic@gmail.com
//

import Foundation
import Combine
import os

public class VehicleIdentificationNumber : ObservableObject {
    public struct VINError : Error {
        public let localizedDescription : String
        
        init( key: String ) {
            self.localizedDescription = Bundle.module.localizedString(forKey: key, value: key, table: nil)
        }
    }

    public struct Detail : Identifiable {
        public let name : String
        public let value: String
        public var id : String { return name }
    }
    @Published public var VIN : String {
        didSet {
            self.isValid = VehicleIdentificationNumber.checkVIN(VIN:VIN)
        }
    }
    @Published public var isValid : Bool
    @Published public var information = [String:String]()
    @Published public var details = [Detail]()
    public var modelYear : Int {
        var year : Int
        guard VIN.count == 17 else {return 0}
        let idx = VIN.index(VIN.startIndex, offsetBy: 9)
        let dateCode = VIN[idx]
        if let dates = VehicleIdentificationNumber.vinYearInfo[String(dateCode)] {
            let date = Date()
            let calendar = Calendar.current
            var dateIdx = -1

//            if yearHint > 0 {
//                if dates[0] == yearHint {
//                    dateIdx = 0
//                } else if dates[1] == yearHint {
//                    dateIdx = 1
//                }
//            }
            if dateIdx < 0 {
                let maxYear = calendar.component(.year, from: date) + 1
                if dates.count == 1 {
                    dateIdx = 0
                } else if dates[0] > maxYear, dates.count > 1 {
                    dateIdx = 1
                } else {
                    dateIdx = 0
                }
            }
            year = dates[dateIdx]
        } else {
            year = 0
        }
        return year
    }
    public static func checkVIN(VIN: String) -> Bool {
        let (res, _) = calculate_check_code(input:VIN)
        return res
    }
    
    public func correctCheckCode() -> Bool {
        let (res, newVIN) = VehicleIdentificationNumber.calculate_check_code(input: self.VIN)
        if res == false, let fixed = newVIN {
            self.VIN = fixed
            return true
        }
        return res
    }
    
    public var decodeURL : URL? {
        var baseURL = "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValuesExtended/\(VIN)?format=json"
        if self.modelYear > 0 {
            baseURL += "&modelyear=\(self.modelYear)"
        }
        return URL(string:baseURL)
    }

    public func fetch( checkValidity: Bool = true, _ completion: @escaping (Data?, Error?)->Void ) {
        if checkValidity, !isValid {
            completion(nil, VINError(key: "VIN_FORMAT_ERROR"))
        }
        os_log("%@", log: .default, type: .debug,
               "VehicleIdentificationNumber.fetch VIN \(VIN)" )
        if let url = self.decodeURL {
            let fetcher = Fetcher()
            fetcher.fetch(url: url) { jsonData, error in
                if let content = jsonData {
                    self.decodeFetchedData( content, completion )
                }
            }
        } else {
            completion(nil, VINError(key:"INVALID_URL"))
        }
    }

    public init( VIN: String = "", detailData : Data? = nil ) {
        self.isValid = VehicleIdentificationNumber.checkVIN(VIN:VIN)
        self.VIN = VIN
        if let data = detailData {
            self.decodeDetails(data)
        }
    }

    @discardableResult public func decodeDetails(_ encoded: Data) -> [String:String]? {
        do {
            if let vdet = try JSONSerialization.jsonObject(with: encoded, options: [] ) as? [String:String] {
                let sorted = vdet.sorted(by:<)
                information.removeAll()
                details.removeAll()
                for item in sorted {
                    information[item.key] = item.value
                    let detail = Detail(name: item.key, value: item.value)
                    details.append( detail )
                }
                if VIN.count == 0, let detailVIN = information["VIN"] {
                    VIN = detailVIN
                }
                return self.information
            }
        }
        catch {
            os_log("%@", log: .default, type: .error,
                   "VehicleIdentificationNumber.decodeDetails failed: \(error.localizedDescription)" )
        }
        return nil
    }
    
    public func encodeDetails() -> Data? {
        do {
            let content = try JSONSerialization.data(withJSONObject: self.information, options: [])
            return content
        } catch {
            os_log("%@", log: .default, type: .error,
                   "VehicleIdentificationNumber.encodeDetails failed: \(error.localizedDescription)"
                   )
            return nil
        }
    }
    
    private static func calculate_check_code(input:String) -> (Bool,String?) {
        guard input.utf8.count == 17 else {return (false,nil)}
        // calculate check value
        // reference: https://en.wikibooks.org/wiki/Vehicle_Identification_Numbers_(VIN_codes)/Check_digit
        var totalValue = 0
        let vinChars = Array(input.uppercased().utf8)
        for ii in 0..<17 {
            if ii == 8 { // check chars are not included in totalValue
                continue
            }
            let ch = vinChars[ii]
            var cval : Int
            if ch >= 0x30 && ch <= 0x39 {
                cval = Int(ch) - 0x30
            } else if ch >= 0x41 && ch <= 0x5a {    // alphabet
                let idx = Int(ch - 0x41)
                cval = VehicleIdentificationNumber.transliteration[idx]
            } else {
                return (false,nil)
            }
            totalValue += cval * VehicleIdentificationNumber.weights[ii]
        }
        var check = totalValue % 11
        if check == 10 {
            check = 0x58    // an X
        } else {
            check += 0x30   // a digit
        }
        let result = vinChars[8] == check

        if vinChars[8] == check {
            return (result,input)
        } else {
            if let checkScalar = Unicode.Scalar(check) {
                let checkCharacter = String(Character(checkScalar))
                let checkIndex = input.index(input.startIndex, offsetBy: 8)
                let fixedVIN = input.replacingCharacters(in: checkIndex...checkIndex, with: checkCharacter)
                return (false, fixedVIN)
            }
            os_log("%@", log: .default, type: .debug,
                   "VIN \(input) check char \(String(vinChars[8])) does not match calculated value \(String(check))" )
        }
        return (false, nil)
    }

    private func decodeFetchedData( _ content: Data, _ completion: @escaping (Data?, Error?)->Void) {
        do {
            if let vinInfo = try JSONSerialization.jsonObject(with: content, options: [] ) as? [String:Any] {
                if let results = vinInfo["Results"] as? [[String:Any]],
                   let responseInfo = results.first {
                    DispatchQueue.main.async {
                        self.information.removeAll()
                        self.details.removeAll()
                        for item in responseInfo {
                            if let vstring = item.value as? String, vstring.count > 0 {
                                if vstring != "Not Applicable" {
                                    self.information[item.key] = vstring
                                    self.details.append( Detail(name: item.key, value: vstring))
                                }
                            }
                        }
                        completion( content, nil )
                    }
                    return
                }
            }
            completion( content, VINError(key: "VIN_DECODE_DATA_INVALID"))
        } catch {
            os_log("%@", log: .default, type: .error,
                   "VehicleIdentificationNumber.decodeFetchedData deocde failed: \(error.localizedDescription)")
            completion( content, error )
        }
    }
    // for VIN checking -
    private static let transliteration = [1,2,3,4,5,6,7,8,-1,1,2,3,4,5,-1,7,-1,9,2,3,4,5,6,7,8,9]
    private static let weights = [8,7,6,5,4,3,2,10,0,9,8,7,6,5,4,3,2]
    private static let vinYearInfo = [
        "A":[2010],
        "B":[2011, 1981],
        "C":[2012, 1982],
        "D":[2013, 1983],
        "E":[2014, 1984],
        "F":[2015, 1985],
        "G":[2016, 1986],
        "H":[2017, 1987],
        "J":[2018, 1988],
        "K":[2019, 1989],
        "L":[2020, 1990],
        "M":[2021, 1991],
        "N":[2022, 1992],
        "P":[2023, 1993],
        "R":[2024, 1994],
        "S":[2025, 1995],
        "T":[2026, 1996],
        "V":[2027, 1997],
        "W":[2028, 1998],
        "X":[2029, 1999],
        "Y":[2030, 2000],
        "1":[2031, 2001],
        "2":[2032, 2002],
        "3":[2033, 2003],
        "4":[2034, 2004],
        "5":[2035, 2005],
        "6":[2036, 2006],
        "7":[2037, 2007],
        "8":[2038, 2008],
        "9":[2039, 2009],
    ]

    private class Fetcher {
        private var session : URLSession? = nil
        private var vinTask : URLSessionDataTask? = nil
        
        public func fetch(url: URL, _ completion: @escaping (Data?, Error?)->Void ) {
            self.session = URLSession(configuration: .ephemeral, delegate:nil, delegateQueue: nil)
            if let sess = self.session {
                var request = URLRequest(url:url)
                request.httpMethod = "GET"
                vinTask = sess.dataTask(with: request){ recv, resp, error in
                    if let err = error {
                        completion(nil, err)
                    } else if let response = resp as? HTTPURLResponse {
                        if response.statusCode != 200 {
                            os_log("%@", log: .default, type: .error,
                                "VIN response: \(response.statusCode)" )
                            completion(nil, nil)
                        } else {
                            if let recvJson = recv {
                                completion(recvJson,nil)
                            }
                        }
                    } else {
                        completion(nil, NSError(domain: "VehicleIdentificationNumber", code: 4, userInfo: [NSLocalizedDescriptionKey:"Network Failure"]))
                    }
                    self.vinTask = nil
                    self.session = nil
                }
                if let dt = vinTask {
                    dt.resume()
                }
            }
        }
    }
}
