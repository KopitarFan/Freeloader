import SwiftUI

struct SearchBarView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter this folder", text: $browser.searchText)
                .textFieldStyle(.plain)
                .onSubmit { browser.updateSearch() }
                .onChange(of: browser.searchText) { _, _ in browser.updateSearch() }
            if browser.isSearching {
                ProgressView().controlSize(.small)
            }
            if !browser.searchText.isEmpty {
                Button {
                    browser.searchText = ""
                    browser.updateSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Menu {
                Picker("Match", selection: $browser.searchMatchMode) {
                    ForEach(SearchMatchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .onChange(of: browser.searchMatchMode) { _, _ in browser.updateSearch() }
                Toggle("Search Subfolders", isOn: $browser.searchSubfolders)
                    .onChange(of: browser.searchSubfolders) { _, _ in browser.updateSearch() }
                if browser.searchSubfolders {
                    Toggle("Use Spotlight Index", isOn: $browser.usesSpotlight)
                        .onChange(of: browser.usesSpotlight) { _, _ in browser.updateSearch() }
                }
                Picker("Kind", selection: $browser.searchKindFilter) {
                    ForEach(SearchKindFilter.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .onChange(of: browser.searchKindFilter) { _, _ in browser.updateSearch() }
                Menu("Minimum Size") {
                    ForEach([0, 1, 10, 100, 1000], id: \.self) { megabytes in
                        Button(megabytes == 0 ? "Any Size" : "\(megabytes) MB") {
                            browser.minimumSearchSizeMB = megabytes
                            browser.updateSearch()
                        }
                    }
                }
                Menu("Date Modified") {
                    ForEach([0, 1, 7, 30, 365], id: \.self) { days in
                        Button(days == 0 ? "Any Time" : "Within \(days) Day\(days == 1 ? "" : "s")") {
                            browser.modifiedWithinDays = days
                            browser.updateSearch()
                        }
                    }
                }
                Divider()
                Button("Save Search") { browser.saveCurrentSearch() }
                    .disabled(browser.searchText.isEmpty)
                if !browser.savedSearches.isEmpty {
                    Menu("Saved Searches") {
                        ForEach(browser.savedSearches, id: \.self) { query in
                            Button(query) {
                                browser.searchText = query
                                browser.updateSearch()
                            }
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    browser.removeSavedSearch(query)
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityLabel("File search")
        .simultaneousGesture(
            TapGesture().onEnded { browser.clearSelection() }
        )
    }
}
