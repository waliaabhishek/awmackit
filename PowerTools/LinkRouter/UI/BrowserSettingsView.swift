import AppKit
import LinkRouterCore
import SwiftUI

struct BrowserSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var browserCatalog: BrowserCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Browsers, Profiles, and PWAs").font(.title2.bold())
                    Text("Choose what appears in the browser prompt and assign one-key shortcuts.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await browserCatalog.refresh() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(browserCatalog.isRefreshing)
            }

            List {
                Section("Applications") {
                    ForEach(browserCatalog.browsers) { browser in
                        browserRow(browser.routeTarget, detail: browser.version.map { "Version \($0)" })
                    }
                }
                if !browserCatalog.profiles.isEmpty {
                    Section("Profiles") {
                        ForEach(browserCatalog.profiles) { profile in
                            browserRow(profile.routeTarget, detail: profile.kind.rawValue.capitalized)
                        }
                    }
                }
                if !browserCatalog.privateTargets.isEmpty {
                    Section("Private / Incognito") {
                        ForEach(browserCatalog.privateTargets) { target in
                            browserRow(target, detail: "Opens a private window")
                        }
                    }
                }
                if !browserCatalog.pwas.isEmpty {
                    Section("Chromium PWAs") {
                        ForEach(browserCatalog.pwas) { pwa in
                            browserRow(pwa.routeTarget, detail: pwa.parentBrowserBundleIdentifier)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func browserRow(_ target: RouteTarget, detail: String?) -> some View {
        let binding = presentationBinding(for: target.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(nsImage: browserCatalog.icon(for: target))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Show in browser picker", isOn: binding.isShownInPrompt)
                    .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                Text("Keyboard shortcut")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "Key",
                    text: Binding(
                        get: { binding.wrappedValue.promptShortcut ?? "" },
                        set: { value in
                            var item = binding.wrappedValue
                            item.promptShortcut = String(value.lowercased().prefix(1)).nilIfEmpty
                            binding.wrappedValue = item
                        }
                    )
                )
                .frame(width: 54)
                .textFieldStyle(.roundedBorder)
                Spacer()
                Stepper(
                    "Picker order: \(binding.wrappedValue.order)",
                    value: binding.order,
                    in: 0...999
                )
                .help("Lower numbers appear first in the browser picker")
            }
        }
        .padding(.vertical, 6)
    }

    private func presentationBinding(for id: String) -> Binding<BrowserPresentation> {
        Binding(
            get: {
                settingsStore.settings.linkRouter.browserPresentation.first(where: { $0.id == id })
                    ?? BrowserPresentation(
                        id: id, order: browserCatalog.allTargets.firstIndex(where: { $0.id == id }) ?? 0)
            },
            set: { updated in
                if let index = settingsStore.settings.linkRouter.browserPresentation.firstIndex(where: { $0.id == id })
                {
                    settingsStore.settings.linkRouter.browserPresentation[index] = updated
                } else {
                    settingsStore.settings.linkRouter.browserPresentation.append(updated)
                }
            }
        )
    }
}

private extension Binding where Value == BrowserPresentation {
    var isShownInPrompt: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.isShownInPrompt },
            set: { value in
                var copy = wrappedValue; copy.isShownInPrompt = value; wrappedValue = copy
            }
        )
    }
    var order: Binding<Int> {
        Binding<Int>(
            get: { wrappedValue.order },
            set: { value in
                var copy = wrappedValue; copy.order = value; wrappedValue = copy
            }
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
