import Foundation
import Testing
import AudienceKit
import StaffKitCore
import StaffKitServices

/// A version 8 California licence as a phone camera reads it: header, subfile directory, the DL subfile and the
/// jurisdiction's ZC subfile, with the address, height, eye colour and the rest a door must not keep.
private let california = "@\n\u{1e}\rANSI 636014080102DL00410278ZC03190024DLDAQD1234562\nDCSPUBLIC\nDDEN\nDACJOHN\nDDFN\nDADQUINCY\nDDGN\nDCAC\nDCBNONE\nDCDNONE\nDBD08312019\nDBB08311977\nDBA08312027\nDBC1\nDAU069 IN\nDAYBRO\nDAG2570 24TH STREET\nDAIANYTOWN\nDAJCA\nDAK958220000  \nDCF83D9BN217QO983B1\nDCGUSA\nDAW180\nDAZBRO\nDCK12345678900000000000\nDDB02142014\r\nZCZCAY\nZCBCORR LENS\r"
private let today = DoorDay(year: 2026, month: 11, day: 14)!

@Test func aLicenceReadsOnThePhone() throws {
    let card = try #require(AAMVABarcode.read(california, today: today))
    #expect(card.name == "John Quincy Public")
    #expect(card.birthDate?.description == "1977-08-31")
    #expect(card.expiresOn?.description == "2027-08-31")
    #expect(card.issuedOn?.description == "2019-08-31")
    #expect(card.gender == "male")
    #expect(card.idNumber == "D1234562")
    #expect(card.issuer == "CA" && card.country == "USA")
    #expect(card.documentKind == "DRIVERS_LICENSE")
    #expect(card.problems.isEmpty)
    #expect(card.age(on: today) == 49)
    #expect(card.age(on: DoorDay(year: 2026, month: 8, day: 30)!) == 48)
    #expect(!card.expired(on: today) && card.expired(on: DoorDay(year: 2027, month: 9, day: 1)!))
    #expect(AAMVABarcode.read("HMC1.abc") == nil)
}

@Test func onlyTheDoorsFieldsLeaveThePhone() throws {
    let sent = AAMVABarcode.minimized(california)
    for dropped in ["2570 24TH", "ANYTOWN", "958220000", "DAU", "DAY", "DAW", "DAZ", "DCF", "DCK", "DDB", "CORR LENS", "DCA"] {
        #expect(!sent.contains(dropped), "\(dropped) was sent")
    }
    // The header and subfile directory stay as scanned, so the API reads the same card and runs the same checks.
    #expect(sent.hasPrefix("@\n\u{1e}\rANSI 636014080102DL00410278ZC03190024DLDAQD1234562\n"))
    #expect(AAMVABarcode.read(sent, today: today) == AAMVABarcode.read(california, today: today))
    #expect(AAMVABarcode.minimized("HMC1.abc") == "HMC1.abc")

    // A card whose first element isn't one the door keeps (vehicle class first) still leads with its ID number.
    let classFirst = "@\n\u{1e}\rANSI 636040090001DL00310200DLDCAD\nDCSDOE\nDACALEX\nDBB06151995\nDBA06152029\nDAQ123456789\nDAG1 MAIN ST\r"
    let minimal = AAMVABarcode.minimized(classFirst)
    #expect(minimal.contains("DLDAQ123456789\n") && !minimal.contains("MAIN ST") && !minimal.contains("DCAD"))
    #expect(AAMVABarcode.read(minimal, today: today)?.name == "Alex Doe")
}

@Test func olderAndCanadianCardsRead() throws {
    // Version 1: one name field, and a scanner that kept no leading control characters.
    let v1 = "ANSI 6360200101DLDAQ12345\nDAAPUBLIC,JANE,Q\nDBB19900102\nDBA20300102\nDBC2\nDAJTX\r"
    let old = try #require(AAMVABarcode.read(v1, today: today))
    #expect(old.name == "Jane Q Public")
    #expect(old.birthDate?.description == "1990-01-02", "falls back to CCYYMMDD when MMDDCCYY isn't a date")
    #expect(old.gender == "female" && old.problems.isEmpty)

    let ontario = "@\n\u{1e}\rANSI 636012030002DL00410230ZO02710035DLDAQS1234-12345-60101\nDCSSMITH\nDACMARY-ANNE\nDBB20010101\nDBA20290101\nDCGCAN\nDAJON\r"
    let canadian = try #require(AAMVABarcode.read(ontario, today: today))
    #expect(canadian.birthDate?.description == "2001-01-01" && canadian.country == "CAN")
    #expect(canadian.name == "Mary-Anne Smith")
}

@Test func homeMadeBarcodesLookFake() throws {
    let made = "@\n\u{1e}\rANSI 123456990001DL00310200DLDAQ1\nDCSDOE\nDACALEX\nDBB13451995\nDBA06151990\nDAJCALIFORNIA\r"
    let card = try #require(AAMVABarcode.read(made, today: today))
    #expect(card.suspect)
    #expect(card.problems.contains("The barcode’s issuer number isn’t an ID issuer’s"))
    #expect(card.problems.contains("The barcode’s format version isn’t one IDs use"))
    #expect(card.problems.contains("The birth date isn’t a real date"))
    #expect(card.problems.contains("The issuing state isn’t a state or province code"))

    let backwards = "@\n\u{1e}\rANSI 636014080102DL00410278DLDAQD1\nDCSDOE\nDACALEX\nDBB06152030\nDBA06152029\r"
    #expect(AAMVABarcode.read(backwards, today: today)?.problems.contains("The dates are in an impossible order") == true)
    let missing = "@\n\u{1e}\rANSI 636014080102DL00410278DLDCSDOE\nDACALEX\r"
    #expect(AAMVABarcode.read(missing, today: today)?.problems.contains("The barcode is missing fields every ID has") == true)
}

@Test func thePhoneGivesTheSameVerdictAsTheAPI() throws {
    #expect(DoorIDOnDevice(barcode: california, today: today)?.outcome == "OK")
    #expect(DoorIDOnDevice(barcode: california, today: today)?.message == "OK · John Quincy Public, 49")
    let young = california.replacingOccurrences(of: "DBB08311977", with: "DBB08312006").replacingOccurrences(of: "DBD08312019", with: "DBD08312022")
    #expect(DoorIDOnDevice(barcode: young, today: today)?.outcome == "UNDER_AGE")
    #expect(DoorIDOnDevice(barcode: young, drinkingAge: 18, today: today)?.outcome == "OK")
    #expect(DoorIDOnDevice(barcode: california, today: DoorDay(year: 2028, month: 1, day: 1)!)?.outcome == "EXPIRED")
    let fake = california.replacingOccurrences(of: "636014", with: "123456")
    #expect(DoorIDOnDevice(barcode: fake, today: today)?.outcome == "SUSPECT")
    #expect(DoorIDOnDevice(barcode: "HMC1.abc") == nil)
    #expect(DoorDay(year: 2026, month: 2, day: 29) == nil && DoorDay(year: 2028, month: 2, day: 29) != nil)
}

private func client(_ stub: Stub) -> VenueManagementClient {
    VenueManagementClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}

@Test func theDoorSendsTheMinimizedBarcodeAndAnswersOfflineOnThePhone() async throws {
    let online = Stub { _ in .json(status: 200, body: #"{"data":{"scanId":{"result":{"outcome":"OK","message":"OK","idNumber":"D1234562","problems":[],"policy":{"jurisdiction":null,"scan":"OPTIONAL","retentionHours":24,"drinkingAge":21,"visualCheck":null,"citation":null,"summary":"Optional"},"idCheck":null}}}}"#) }
    _ = try await client(online).checkAtDoor(venueID: "venue", code: california)
    let body = try #require(online.requests.last).jsonBody()
    let barcode = ((body["variables"] as? [String: Any])?["input"] as? [String: Any])?["barcode"] as? String
    #expect(barcode == AAMVABarcode.minimized(california))
    #expect(barcode?.contains("2570 24TH") == false)

    let offline = Stub { _ in .failure(URLError(.notConnectedToInternet)) }
    let result = try await client(offline).checkAtDoor(venueID: "venue", code: california)
    #expect(result.onDevice?.card.idNumber == "D1234562")
    #expect(result.outcome == "ID_\(result.onDevice?.outcome ?? "")" && result.idResult == nil)

    // A pass can't be checked on the phone: the failure goes to the door as before.
    await #expect(throws: (any Error).self) { try await client(offline).checkAtDoor(venueID: "venue", code: "HMC1.abc") }
}
