// tvOS: AudienceKitUI on Apple TV is only the shared look (Theme, DesignTokens, AudienceAvatar) for Velvet's TV app.
#if !os(tvOS)
#if canImport(Contacts)
import AudienceCore
import Contacts
import Foundation

/// Reads the phone's contacts for friend matching. Only first names, last names and phone numbers are read, and they
/// go straight into ``ContactHashing``; nothing read here is sent or stored.
public enum ContactsReader {
    public enum Access: Sendable {
        /// Not asked yet: ``requestAccess()`` shows the system prompt.
        case notDetermined
        /// Refused, or restricted by a profile: only Settings can change it.
        case denied
        /// All contacts, or on iOS 18 the ones the person picked.
        case authorized
    }

    public static var access: Access {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        #if os(iOS)
        if #available(iOS 18.0, *), status == .limited { return .authorized }
        #endif
        switch status {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Shows the system prompt when the person hasn't answered it, and says whether contacts can be read.
    public static func requestAccess() async -> Bool {
        switch access {
        case .authorized: return true
        case .denied: return false
        case .notDetermined: return (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        }
    }

    /// Every contact the app may see, with its numbers as saved. Runs off the main thread.
    public static func read() async throws -> [DeviceContact] {
        try await Task.detached(priority: .userInitiated) {
            let keys = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor,
                        CNContactPhoneNumbersKey as CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var contacts: [DeviceContact] = []
            try CNContactStore().enumerateContacts(with: request) { contact, _ in
                contacts.append(DeviceContact(firstName: contact.givenName, lastName: contact.familyName,
                                              phoneNumbers: contact.phoneNumbers.map(\.value.stringValue)))
            }
            return contacts
        }.value
    }

    /// The phone's region, for numbers saved without a country code.
    public static var region: String? { Locale.current.region?.identifier }
}
#endif
#endif
