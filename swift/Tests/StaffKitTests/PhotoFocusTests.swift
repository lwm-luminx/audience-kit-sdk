import Foundation
import Testing
@testable import StaffKitServices

@Test func photoFocusKeepsAFaceNearTheTopOfASquarePostIn16x9() {
    let focus = PhotoFocus(focalPoint: .init(x: 0.5, y: 0.15), faces: [.init(x: 0.4, y: 0.05, width: 0.2, height: 0.2)])
    let window = focus.crop(width: 1080, height: 1080, aspect: 16.0 / 9.0)
    #expect(window.x == 0 && window.y == 0 && window.width == 1080 && window.height == 608)
}

@Test func photoFocusKeepsEveryFaceWhenTheyFitElseTheLargest() {
    let top = PhotoFocus.Face(x: 0.1, y: 0.0, width: 0.1, height: 0.1)
    let apart = PhotoFocus(focalPoint: .init(x: 0.5, y: 0.5), faces: [top, .init(x: 0.6, y: 0.8, width: 0.3, height: 0.2)])
    #expect(apart.crop(width: 1000, height: 1000, aspect: 2).y == 500)

    let near = PhotoFocus(focalPoint: .init(x: 0.5, y: 0.5), faces: [top, .init(x: 0.6, y: 0.2, width: 0.1, height: 0.1)])
    #expect(near.crop(width: 1000, height: 1000, aspect: 2).y == 0)
}

@Test func photoFocusCentresOnItsFocalPointInsideTheImage() {
    let window = PhotoFocus(focalPoint: .init(x: 0.9, y: 0.5)).crop(width: 1920, height: 1080, aspect: 1)
    #expect(window.x == 840 && window.width == 1080)
    #expect(PhotoFocus(focalPoint: nil).crop(width: 1920, height: 1080, aspect: 1).x == 420)
}

@Test func photoFocusMatchesAPhotoLinkSignedForAnotherWeek() {
    #expect(PhotoFocus.key("https://api.audiencekit.com/v1/photos/abc?sig=x1.y") == "https://api.audiencekit.com/v1/photos/abc")
    #expect(PhotoFocus.key("https://cdn.example/a.jpg") == "https://cdn.example/a.jpg")
}

@Test func photoFocusDecodesWithoutFaces() throws {
    let focus = try JSONDecoder().decode(PhotoFocus.self, from: Data(#"{"focalPoint":{"x":0.3,"y":0.6}}"#.utf8))
    #expect(focus == PhotoFocus(focalPoint: .init(x: 0.3, y: 0.6), faces: []))
}

@Test func screenBackdropDecodesItsFocusAndWhetherItIsText() throws {
    let json = #"""
    {"url":"https://cdn.example/flyer.jpg","source":"instagram","hasText":true,
     "focalPoint":{"x":0.5,"y":0.3},"faces":[{"x":0.4,"y":0.2,"width":0.2,"height":0.2}]}
    """#
    let backdrop = try JSONDecoder().decode(ScreenBackdrop.self, from: Data(json.utf8))
    #expect(backdrop.source == "instagram" && backdrop.hasText == true)
    #expect(backdrop.focus.faces == [.init(x: 0.4, y: 0.2, width: 0.2, height: 0.2)])

    let unchecked = try JSONDecoder().decode(ScreenBackdrop.self, from: Data(#"{"url":"u","source":"google"}"#.utf8))
    #expect(unchecked.hasText == nil && unchecked.focus.focalPoint == nil && unchecked.focus.faces.isEmpty)
}
