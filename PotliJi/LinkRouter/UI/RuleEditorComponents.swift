import LinkRouterCore
import SwiftUI

struct URLMatcherGroupEditor: View {
    let title: String
    @Binding var group: URLMatcherGroup
    let delete: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(groupSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this condition group")
                }

                Picker("How conditions combine", selection: $group.mode) {
                    Text("Match Any").tag(URLMatcherGroupMode.any)
                    Text("Match All").tag(URLMatcherGroupMode.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if group.matchers.isEmpty {
                    Label(emptyGroupMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(Array(group.matchers.indices), id: \.self) { index in
                    URLMatcherRow(
                        title: "Condition \(index + 1)",
                        matcher: $group.matchers[index]
                    ) {
                        group.matchers.remove(at: index)
                    }
                }

                Button {
                    group.matchers.append(URLMatcher(kind: .hostSuffix, pattern: "example.com"))
                } label: {
                    Label("Add Condition", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(6)
        }
    }

    private var groupSummary: String {
        switch group.mode {
        case .any:
            "A link can satisfy any one condition below."
        case .all:
            "A link must satisfy every condition below."
        }
    }

    private var emptyGroupMessage: String {
        switch group.mode {
        case .any:
            "Add a condition or this group cannot match."
        case .all:
            "With no conditions, this group currently matches every link."
        }
    }
}

struct URLRewriteActionRow: View {
    let title: String
    @Binding var action: URLRewriteAction
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive, action: delete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this rewrite action")
            }

            Picker("Action", selection: $action.kind) {
                Text("Replace Domain").tag(URLRewriteKind.replaceHost)
                Text("Force HTTPS").tag(URLRewriteKind.forceHTTPS)
                Text("Replace Path Prefix").tag(URLRewriteKind.replacePathPrefix)
                Text("Remove Query Parameters").tag(URLRewriteKind.removeQueryParameters)
                Text("Set Query Parameter").tag(URLRewriteKind.setQueryParameter)
            }

            switch action.kind {
            case .replaceHost:
                field("New domain", placeholder: "example.com", text: $action.value)
            case .forceHTTPS:
                Text("Change http:// links to https://")
                    .foregroundStyle(.secondary)
            case .replacePathPrefix:
                field("Existing path prefix", placeholder: "/old", text: $action.value)
                field("New path prefix", placeholder: "/new", text: $action.replacement)
            case .removeQueryParameters:
                field(
                    "Parameter names",
                    placeholder: "utm_source, ref",
                    text: $action.value
                )
            case .setQueryParameter:
                field("Parameter name", placeholder: "theme", text: $action.value)
                field("Parameter value", placeholder: "dark", text: $action.replacement)
            }

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
    }

    private func field(
        _ label: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: text, prompt: Text(placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var explanation: String {
        switch action.kind {
        case .replaceHost:
            "Keeps the path, query parameters, and fragment while changing the domain."
        case .forceHTTPS:
            "Uses an encrypted HTTPS URL whenever the incoming link uses HTTP."
        case .replacePathPrefix:
            "Changes the beginning of the URL path and preserves the rest."
        case .removeQueryParameters:
            "Removes each named query parameter before the link opens."
        case .setQueryParameter:
            "Adds this query parameter or replaces its existing value."
        }
    }
}

struct SourceApplicationMatcherRow: View {
    let title: String
    @Binding var matcher: SourceAppMatcher
    let chooseApplication: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive, action: delete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this source application")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bundle identifier")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "",
                    text: $matcher.bundleIdentifier,
                    prompt: Text("com.example.app")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            }

            Toggle("Exclude links from this application", isOn: $matcher.isNegated)
                .toggleStyle(.checkbox)
            Button("Choose Application…", action: chooseApplication)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct URLMatcherRow: View {
    let title: String
    @Binding var matcher: URLMatcher
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive, action: delete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this condition")
            }

            HStack {
                Text("Type")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Condition type", selection: $matcher.kind) {
                    ForEach(URLMatcherKind.allCases, id: \.self) { kind in
                        Text(label(kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Value")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "",
                    text: $matcher.pattern,
                    prompt: Text(patternPlaceholder)
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 18) {
                Toggle("Exclude matching links", isOn: $matcher.isNegated)
                    .toggleStyle(.checkbox)
                Toggle("Case-sensitive", isOn: $matcher.isCaseSensitive)
                    .toggleStyle(.checkbox)
            }

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
    }

    private func label(_ kind: URLMatcherKind) -> String {
        switch kind {
        case .exact: "Exact URL"
        case .host: "Host"
        case .hostSuffix: "Domain / subdomain"
        case .prefix: "URL prefix"
        case .suffix: "URL suffix"
        case .contains: "URL contains"
        case .regularExpression: "Regular expression"
        case .pathPrefix: "Path prefix"
        case .scheme: "Scheme"
        case .queryParameter: "Query parameter"
        }
    }

    private var patternPlaceholder: String {
        switch matcher.kind {
        case .exact: "https://example.com/page"
        case .host, .hostSuffix: "example.com"
        case .prefix, .suffix, .contains: "Text to match in the URL"
        case .regularExpression: "Regular expression"
        case .pathPrefix: "/docs"
        case .scheme: "https"
        case .queryParameter: "name or name=value"
        }
    }

    private var explanation: String {
        switch matcher.kind {
        case .exact:
            "Matches only this complete URL."
        case .host:
            "Matches this exact domain, but not its subdomains."
        case .hostSuffix:
            "Matches this domain and any of its subdomains."
        case .prefix:
            "Matches when the complete URL starts with this value."
        case .suffix:
            "Matches when the complete URL ends with this value."
        case .contains:
            "Matches when this value appears anywhere in the complete URL."
        case .regularExpression:
            "Matches the complete URL using a regular expression."
        case .pathPrefix:
            "Matches when the path begins with this value."
        case .scheme:
            "Matches a URL scheme such as http or https."
        case .queryParameter:
            "Match a parameter name, or use name=value to require a specific value."
        }
    }
}
