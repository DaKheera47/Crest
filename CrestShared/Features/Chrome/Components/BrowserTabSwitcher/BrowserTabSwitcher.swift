import SwiftUI

struct BrowserTabSwitcher: View {
    // MARK: - Static Variables

    private static let tileWidth: CGFloat = 96
    private static let iconSize: CGFloat = 40

    // MARK: - Variables

    let model: BrowserTabSwitcherModel
    let browser: BrowserStore
    @AccessibilityFocusState private var focusedTabID: UUID?

    // MARK: - Actions - Presentation

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.cancel() }
                .accessibilityHidden(true)

            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(spacing: CrestSpacing.small) {
                        ForEach(model.tabs) { tab in
                            tile(tab)
                                .id(tab.id)
                        }
                    }
                    .padding(CrestSpacing.large)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.highlightedTabID, initial: true) { _, selected in
                    if let selected {
                        scroll.scrollTo(selected, anchor: .center)
                        focusedTabID = selected
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: contentWidth)
            .background { CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.panel)) }
            .clipShape(.rect(cornerRadius: CrestRadius.panel))
            .padding(CrestSpacing.extraExtraLarge)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Tab Switcher"))
            .accessibilityIdentifier("tab-switcher")
        }
        .browserPaletteExitCommand { model.cancel() }
    }

    private func tile(_ tab: TabStateModel) -> some View {
        let selected = tab.id == model.highlightedTabID
        return Button {
            model.commit(tab.id)
        } label: {
            VStack(spacing: CrestSpacing.medium) {
                TabStateFaviconView(
                    tab: tab, favicons: browser.core.state.favicons,
                    profileID: model.source?.profileID, size: Self.iconSize)
                Text(verbatim: tab.displayTitle)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .top)
            }
            .frame(width: Self.tileWidth)
            .padding(CrestSpacing.medium)
            .contentShape(.rect(cornerRadius: CrestRadius.control))
        }
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.control, isSelected: selected)
        )
        .focusable(false)
        .accessibilityLabel(Text(verbatim: tab.displayTitle))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityFocused($focusedTabID, equals: tab.id)
        .help(tab.url ?? tab.displayTitle)
    }

    private var contentWidth: CGFloat {
        CGFloat(model.tabs.count) * (Self.tileWidth + 2 * CrestSpacing.medium + CrestSpacing.small)
            - CrestSpacing.small + 2 * CrestSpacing.large
    }
}
