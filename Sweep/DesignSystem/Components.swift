import SweepCore
import SwiftUI

// MARK: - AlmanacCard: the standard paper card surface

public struct AlmanacCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                    .fill(Tokens.card)
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous)
                        .strokeBorder(Tokens.line, lineWidth: 1)))
    }
}

// MARK: - Status dot + word

public struct StatusBadge: View {
    let state: VerdictStateUI

    public init(state: VerdictStateUI) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Tokens.statusColor(state))
                .frame(width: 8, height: 8)
            Text(state.word)
                .font(Tokens.statusWord)
                .foregroundStyle(Tokens.statusColor(state))
                .textCase(.uppercase)
                .kerning(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pill tag ("your sign", etc.)

public struct PillTag: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color = Tokens.clay) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }
}

// MARK: - Primary button

public struct ClayButtonStyle: ButtonStyle {
    let background: Color

    public init(background: Color = Tokens.clay) {
        self.background = background
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusControl, style: .continuous)
                .fill(background.opacity(configuration.isPressed ? 0.85 : 1)))
    }
}

// MARK: - SidePicker card (§7.3)

public struct SideCard: View {
    let landmark: String
    let hint: String?
    let doors: String?
    let signLines: [String]
    let miniVerdict: String
    let miniState: VerdictStateUI
    let selected: Bool
    let onTap: () -> Void

    public init(landmark: String, hint: String?, doors: String?, signLines: [String] = [],
                miniVerdict: String, miniState: VerdictStateUI, selected: Bool,
                onTap: @escaping () -> Void) {
        self.landmark = landmark
        self.hint = hint
        self.doors = doors
        self.signLines = signLines
        self.miniVerdict = miniVerdict
        self.miniState = miniState
        self.selected = selected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                Text(landmark)
                    .font(Tokens.display(17, relativeTo: .body).weight(.medium))
                    .foregroundStyle(Tokens.ink)
                if let hint {
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.sub)
                }
                if let doors {
                    Text(doors)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Tokens.sub)
                }
                HStack(alignment: .bottom) {
                    HStack(spacing: 5) {
                        Circle().fill(Tokens.statusColor(miniState)).frame(width: 7, height: 7)
                        Text(miniVerdict)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Tokens.statusColor(miniState))
                    }
                    Spacer()
                    SignPreview(lines: signLines)
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Tokens.radiusSideCard, style: .continuous)
                    .fill(Tokens.card)
                    .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSideCard, style: .continuous)
                        .strokeBorder(selected ? Tokens.clay : Tokens.line,
                                      lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? Tokens.clay.opacity(0.13) : .clear,
                            radius: 3, y: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel([landmark, hint, doors, miniVerdict]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Sign preview

/// Mini rendering of the posted street-sweeping sign, so users can
/// eyeball-match the physical pole before trusting the verdict.
public struct SignPreview: View {
    let lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }

    public var body: some View {
        if !lines.isEmpty {
            VStack(spacing: 2) {
                Text("NO PARKING")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xC0392B))
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Tokens.ink)
                }
                Text("STREET SWEEPING")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Tokens.sub)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(hex: 0xC0392B), lineWidth: 1.5)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Posted sign should read: no parking, "
                                + lines.joined(separator: ", ") + ", street sweeping")
        }
    }
}

// MARK: - Block search result row (§7.2)

public struct BlockHitRow: View {
    let hit: BlockSearch.Hit

    public init(hit: BlockSearch.Hit) {
        self.hit = hit
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.street)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.ink)
                Text(hit.doorSummary.map { "\(hit.blockLabel) · doors \($0)" } ?? hit.blockLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.sub)
            }
            Spacer()
            if hit.matchesNumber {
                PillTag("your address", color: Tokens.sage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

// SweepFormat and VerdictStateUI live in SweepCore (Core/Engine/SweepFormat.swift)
// so the copy rules are unit-testable; views here consume them via import.
