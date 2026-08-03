import SwiftUI

enum SettingsDesign {
    static let pageSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 5
    static let iconColumnWidth: CGFloat = 28
    static let controlWidth: CGFloat = 280
}

extension View {
    func settingsAccessoryPicker(width: CGFloat = SettingsDesign.controlWidth) -> some View {
        labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .frame(width: width, alignment: .trailing)
    }
}

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsControlRow<Accessory: View>: View {
    let title: String
    let detail: String?
    let systemImage: String?
    let accessoryWidth: CGFloat
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        detail: String? = nil,
        systemImage: String? = nil,
        accessoryWidth: CGFloat = SettingsDesign.controlWidth,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.accessoryWidth = accessoryWidth
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: SettingsDesign.rowSpacing) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: SettingsDesign.iconColumnWidth)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            accessory()
                .frame(width: accessoryWidth, alignment: .trailing)
        }
        .padding(.vertical, SettingsDesign.rowVerticalPadding)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let detail: String?
    let systemImage: String?
    @Binding var isOn: Bool

    init(
        title: String,
        detail: String? = nil,
        systemImage: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        _isOn = isOn
    }

    var body: some View {
        SettingsControlRow(
            title: title,
            detail: detail,
            systemImage: systemImage
        ) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: SettingsDesign.sectionSpacing) {
                content()
            }
            .padding(.vertical, 4)
        }
    }
}

struct SettingsActionRow: View {
    let title: String
    let detail: String?
    let systemImage: String?
    let buttonTitle: String
    let action: () -> Void

    init(
        title: String,
        detail: String? = nil,
        systemImage: String? = nil,
        buttonTitle: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        SettingsControlRow(title: title, detail: detail, systemImage: systemImage) {
            Button(buttonTitle, action: action)
        }
    }
}
