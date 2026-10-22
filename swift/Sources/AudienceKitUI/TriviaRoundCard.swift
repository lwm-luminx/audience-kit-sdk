#if canImport(SwiftUI)
import AudienceKit
import SwiftUI

/// A venue's group trivia round as a card for its chat: the question ("Myth or Legend?"), the statement, and a button
/// per choice showing how the room is split. The room talks it over and votes together; tapping a choice votes (or
/// changes the vote) while it's open. Once revealed it shows the answer, the room's call and the story; while a segment
/// holds the answers to its end, it says so. Counts only: nobody is named, scored or ranked.
public struct TriviaRoundCard: View {
    private let round: TriviaRound
    private let onVote: (@MainActor (String) async -> Void)?

    @Environment(\.audiencePreset) private var preset
    @Environment(\.colorScheme) private var scheme
    @State private var voting: String?

    /// - Parameters:
    ///   - round: the round, e.g. ``VenueShow/trivia``.
    ///   - onVote: votes for a choice (``AudienceSession/voteTrivia(roundID:choice:)``) and refreshes the round; nil
    ///     shows the card without voting, e.g. for someone not at the venue.
    public init(round: TriviaRound, onVote: (@MainActor (String) async -> Void)? = nil) {
        self.round = round
        self.onVote = onVote
    }

    private var colors: DesignTokens.Colors { preset.colors(scheme) }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
            Label(round.question, systemImage: "sparkles")
                .font(TokenFont.label).foregroundStyle(Color(colors.accentInk))
                .accessibilityAddTraits(.isHeader)
            Text(round.statement).font(TokenFont.subheading).foregroundStyle(Color(colors.ink))
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: DesignTokens.Spacing.s2) {
                ForEach(round.choices) { choice in choiceButton(choice) }
            }
            footer
        }
        .padding(DesignTokens.Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(colors.surfaceRaised), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.bubble))
        .overlay { RoundedRectangle(cornerRadius: DesignTokens.Radius.bubble).strokeBorder(Color(colors.border)) }
    }

    private func choiceButton(_ choice: TriviaRound.Choice) -> some View {
        let mine = round.myChoice == choice.label
        let right = round.answer == choice.label
        let share = round.share(of: choice)
        return Button {
            guard let onVote, round.voting, voting == nil else { return }
            voting = choice.label
            Task { @MainActor in
                await onVote(choice.label)
                voting = nil
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.s2) {
                if right { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(colors.success)) }
                else if mine { Image(systemName: "hand.raised.fill").foregroundStyle(Color(colors.accentInk)) }
                Text(choice.label).font(TokenFont.label)
                Spacer(minLength: DesignTokens.Spacing.s2)
                if voting == choice.label { ProgressView().controlSize(.small) }
                Text("\(choice.count)").font(TokenFont.bodySm).monospacedDigit()
                    .foregroundStyle(Color(colors.inkMuted))
            }
            .foregroundStyle(Color(colors.ink))
            .padding(.horizontal, DesignTokens.Spacing.s3)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(alignment: .leading) {
                GeometryReader { geometry in
                    Rectangle().fill(Color(right ? colors.successSoft : colors.accentSoft))
                        .frame(width: geometry.size.width * share)
                }
            }
            .background(Color(colors.surface))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color(mine ? colors.accent : colors.border), lineWidth: mine ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(onVote == nil || !round.voting)
        .accessibilityLabel(choiceLabel(choice, mine: mine, right: right))
        .accessibilityHint(round.voting && onVote != nil ? String(localized: "Votes for this") : "")
    }

    private func choiceLabel(_ choice: TriviaRound.Choice, mine: Bool, right: Bool) -> String {
        var parts = [choice.label, String(localized: "\(choice.count) votes")]
        if mine { parts.append(String(localized: "your vote")) }
        if right { parts.append(String(localized: "the answer")) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var footer: some View {
        if round.isRevealed, let answer = round.answer {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1) {
                Text(String(localized: "It's \(answer). \(roomLine(answer))")).font(TokenFont.label)
                    .foregroundStyle(Color(colors.ink))
                if let reveal = round.reveal, !reveal.isEmpty {
                    Text(reveal).font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if round.voting {
            Text(onVote == nil ? String(localized: "Talk it over with the room.")
                 : String(localized: "Talk it over, then vote as a room. You can change your vote until it closes."))
                .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
        } else {
            Text(round.revealsAtEnd ? String(localized: "Votes are in. The answers come at the end.")
                 : String(localized: "Votes are in. The answer's coming."))
                .font(TokenFont.bodySm).foregroundStyle(Color(colors.inkMuted))
        }
    }

    private func roomLine(_ answer: String) -> String {
        guard let call = round.roomCall else { return String(localized: "The room was split.") }
        return call == answer ? String(localized: "The room got it.") : String(localized: "The room said \(call).")
    }
}
#endif
