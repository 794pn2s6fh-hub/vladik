import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct ErosionAirCardHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { ErosionWalletCardsView() } label: { Label("Wallet Cards", systemImage: "creditcard") }
                NavigationLink { ErosionPasscodeView() } label: { Label("Passcode Theme", systemImage: "circle.grid.3x3") }
                NavigationLink { ErosionWallpapersView() } label: { Label("Wallpapers (.tendies)", systemImage: "photo.stack") }
            } header: {
                HeaderLabel("Airlift Features", symbol: "wand.and.stars")
            } footer: {
                Text("These features use the same imported pairing file and LocalDevVPN connection as Airlift.")
            }
        }
        .navigationTitle("Customization")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ErosionWalletCardsView: View {
    @StateObject private var vm = ErosionAirCardFeatures.shared
    @State private var showPicker = false
    @State private var selectedCardID: String?
    @State private var hash = ""

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: vm.ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(vm.ready ? .green : .orange)
                    Text(vm.ready ? "Airlift ready" : "Import pairing + enable LocalDevVPN")
                        .font(.subheadline)
                }
                Button(vm.walletScanning ? "Stop Card Scan" : "Scan Wallet Cards") {
                    vm.walletScanning ? vm.stopCardScan() : vm.startCardScan()
                }
                .disabled(!ErosionAirlift.shared.hasPairing || vm.walletFlashing)
            } header: { HeaderLabel("Detection", symbol: "waveform") }

            Section {
                HStack {
                    TextField("Card identifier / hash", text: $hash)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add") { vm.addCardHash(hash); hash = "" }
                }
                if vm.cards.isEmpty {
                    Text("No cards detected yet. Open Apple Pay and select a card while the scan is running.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(vm.cards) { card in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { card.isSelected }, set: { value in
                            if let i = vm.cards.firstIndex(where: { $0.id == card.id }) { vm.cards[i].isSelected = value }
                        })).labelsHidden()
                        if let image = card.uiImage {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 58, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 58, height: 36)
                        }
                        Text(String(card.id.prefix(18)) + "…").font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button {
                            selectedCardID = card.id
                            showPicker = true
                        } label: {
                            Label("Image", systemImage: "photo")
                                .font(.caption)
                                .frame(minWidth: 54)
                        }
                        .buttonStyle(.borderless)
                        .contentShape(Rectangle())

                        Button(role: .destructive) {
                            vm.deleteCard(card.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderless)
                        .contentShape(Rectangle())
                    }
                }
                if !vm.cards.isEmpty {
                    Button(vm.walletFlashing ? "Applying…" : "Apply Selected Cards") { vm.flashSelectedCards() }
                        .disabled(vm.walletFlashing || !vm.cards.contains(where: { $0.isSelected && $0.customImageData != nil }))
                }
            } header: { HeaderLabel("Cards", symbol: "creditcard") }

            logSection(vm.walletLog)
        }
        .navigationTitle("Wallet Cards")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            PhotoPicker { image in
                if let id = selectedCardID, let image { vm.setCardImage(id: id, image: image) }
                showPicker = false
            }
        }
    }
}

struct ErosionPasscodeView: View {
    @StateObject private var vm = ErosionAirCardFeatures.shared
    @State private var showImporter = false
    @State private var showPosterPicker = false
    @State private var showKeyPicker = false
    @State private var selectedDigit: String?

    var body: some View {
        List {
            Section {
                Picker("Mode", selection: $vm.passcodeMode) {
                    ForEach(CreatorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: { HeaderLabel("Mode", symbol: "slider.horizontal.3") }

            if vm.passcodeMode == .applyTheme {
                applyThemeSection
            } else {
                creatorSection
            }

            passcodeTargetSection
            logSection(vm.passcodeLog)
        }
        .navigationTitle("Passcode Theme")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPosterPicker) {
            PhotoPicker { image in
                if let image { vm.setPosterImage(image) }
                showPosterPicker = false
            }
        }
        .sheet(isPresented: $showKeyPicker) {
            PhotoPicker { image in
                if let digit = selectedDigit, let image { vm.setIndividualKey(digit: digit, image: image) }
                showKeyPicker = false
            }
        }
        .sheet(isPresented: Binding(get: { vm.showShareSheet }, set: { vm.showShareSheet = $0 })) {
            if let url = vm.exportedThemeURL {
                ActivityView(activityItems: [url])
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result { vm.importPassthm(url) }
        }
    }

    @ViewBuilder
    private var applyThemeSection: some View {
        Section {
            Button("Import .passthm") { showImporter = true }
            if let theme = vm.loadedTheme {
                Text("Loaded: \(theme.name) · \(theme.keysPreview.count) keys")
                    .font(.footnote).foregroundStyle(.secondary)
                PasscodeThemePreview(keys: theme.keysPreview)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                Button {
                    vm.adoptThemeIntoCreator()
                } label: {
                    Label("Edit in Theme Creator", systemImage: "pencil")
                }

                Button(vm.passcodeFlashing ? "Applying…" : "Apply Passcode Theme") {
                    vm.flashPassthm()
                }
                .disabled(vm.passcodeFlashing || !vm.ready)

                Button(role: .destructive) {
                    vm.loadedTheme = nil
                } label: {
                    Text("Unload Theme")
                }
            } else {
                Text("Import a .passthm theme to preview and apply custom TelephonyUI keypad artwork.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: { HeaderLabel("Theme", symbol: "circle.grid.3x3") }
    }

    @ViewBuilder
    private var creatorSection: some View {
        Section {
            Picker("Slice Mode", selection: $vm.sliceMode) {
                ForEach(SliceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: { HeaderLabel("Creator", symbol: "wand.and.stars") }

        if vm.sliceMode == .posterSlice {
            Section {
                Button {
                    showPosterPicker = true
                } label: {
                    Label(vm.posterImage == nil ? "Choose Artwork" : "Change Artwork", systemImage: "photo")
                }
                Toggle("Circle Mask", isOn: $vm.maskToCircles)
                    .onChange(of: vm.maskToCircles) { _, _ in vm.updatePosterSlicing() }
                if vm.posterImage != nil {
                    PasscodeThemePreview(keys: vm.slicedKeys)
                        .frame(maxWidth: .infinity)
                    HStack {
                        Button("Reset") { vm.resetPosterPosition() }
                        Spacer()
                        Text("Zoom \(vm.posterZoom, specifier: "%.2fx")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $vm.posterZoom, in: 1...3)
                        .onChange(of: vm.posterZoom) { _, _ in vm.updatePosterSlicing() }
                } else {
                    Text("Choose one image and Erosion will slice it into the ten keypad keys.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { HeaderLabel("Poster Slice", symbol: "rectangle.split.3x3") }
        } else {
            Section {
                ForEach(KeypadLayout.allButtons) { button in
                    HStack {
                        Text(button.digit)
                            .font(.system(.headline, design: .rounded))
                            .frame(width: 30)
                        if let image = vm.customKeys[button.digit] {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                        } else {
                            Circle().fill(.quaternary).frame(width: 42, height: 42)
                        }
                        Spacer()
                        Button("Choose") {
                            selectedDigit = button.digit
                            showKeyPicker = true
                        }
                        if vm.customKeys[button.digit] != nil {
                            Button(role: .destructive) { vm.clearIndividualKey(digit: button.digit) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: { HeaderLabel("Individual Keys", symbol: "circle.grid.3x3") }
        }

        Section {
            PasscodeThemePreview(keys: vm.effectiveKeys)
                .frame(maxWidth: .infinity)
            HStack {
                Button("Export .passthm") { _ = vm.exportPassthm() }
                    .disabled(vm.effectiveKeys.isEmpty)
                Spacer()
                Button("Clear", role: .destructive) { vm.clearAllCreator() }
            }
            Button(vm.passcodeFlashing ? "Applying…" : "Apply Created Theme") {
                // Reuse the existing Erosion flash pipeline after creating an in-memory theme.
                guard !vm.effectiveKeys.isEmpty else { return }
                vm.loadedTheme = PasscodeThemeInfo(
                    name: "Erosion Creator",
                    filePath: "creator://erosion",
                    fileCount: vm.effectiveKeys.count,
                    keysPreview: vm.effectiveKeys,
                    rawKeyData: vm.effectiveKeys.compactMapValues { $0.pngData() }
                )
                vm.flashPassthm()
            }
            .disabled(vm.passcodeFlashing || vm.effectiveKeys.isEmpty || !vm.ready)
        } header: { HeaderLabel("Preview & Apply", symbol: "bolt.fill") }
    }

    private var passcodeTargetSection: some View {
        Section {
            Picker("System Cache", selection: $vm.targetTelephonyVersion) {
                Text("TelephonyUI-10 (iOS 18+)").tag("TelephonyUI-10")
                Text("TelephonyUI-9 (iOS 16–17)").tag("TelephonyUI-9")
                Text("TelephonyUI-8 (iOS 14–15)").tag("TelephonyUI-8")
            }
            Picker("Language", selection: $vm.passcodeLanguageTarget) {
                ForEach(PasscodeLanguageTarget.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            Picker("Font Weight", selection: $vm.passcodeBoldTarget) {
                ForEach(PasscodeBoldTarget.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            Text(vm.passcodeLanguageTarget == .all && vm.passcodeBoldTarget == .both
                 ? "Universal mode includes all supported locale/weight variants."
                 : "Fast mode targets \(vm.passcodeLanguageTarget.rawValue) / \(vm.passcodeBoldTarget.rawValue).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } header: {
            HeaderLabel("Flash Target", symbol: "bolt.badge.clock")
        }
    }
}

struct ErosionWallpapersView: View {
    @StateObject private var vm = ErosionAirCardFeatures.shared
    @State private var showImporter = false

    var body: some View {
        List {
            Section {
                Button("Import .tendies") { showImporter = true }
                Button("Detect PosterBoard Container") { vm.detectPosterBoard() }
                if !vm.posterBoardContainer.isEmpty {
                    Text(vm.posterBoardContainer).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            } header: { HeaderLabel("PosterBoard", symbol: "rectangle.stack") }

            Section {
                if vm.tendieItems.isEmpty {
                    Text("No .tendies wallpapers imported.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach($vm.tendieItems) { $item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $item.isSelected).labelsHidden()
                            if let image = item.uiPreview { Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 60).clipShape(RoundedRectangle(cornerRadius: 7)) }
                            VStack(alignment: .leading) {
                                Text(item.name).lineLimit(1)
                                Text(item.posterType.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { vm.deleteTendie(item) } label: { Image(systemName: "trash") }
                        }
                    }
                }
                Button(vm.wallpaperBusy ? "Applying…" : "Apply Selected Wallpapers") { vm.flashWallpapers() }
                    .disabled(vm.wallpaperBusy || !vm.ready || !vm.tendieItems.contains(where: { $0.isSelected }))
            } header: { HeaderLabel("Wallpapers", symbol: "photo.stack") }

            logSection(vm.wallpaperLog)
        }
        .navigationTitle("Wallpapers")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result { vm.importTendie(url) }
        }
    }
}

private struct PasscodeThemePreview: View {
    let keys: [String: UIImage]

    private let buttons: [KeypadButtonGeometry] = KeypadLayout.allButtons

    var body: some View {
        let scale: CGFloat = 0.48
        let btnD = KeypadLayout.buttonDiameter * scale
        let colW = KeypadLayout.colWidth * scale
        let rowH = KeypadLayout.rowHeight * scale
        let gridW = KeypadLayout.gridWidth * scale
        let gridH = KeypadLayout.gridHeight * scale

        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.75))

            ForEach(buttons) { btn in
                ZStack {
                    if let image = keys[btn.digit] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: btnD, height: btnD)
                            .clipShape(Circle())
                    } else {
                        Circle().fill(.quaternary)
                    }
                }
                .frame(width: btnD, height: btnD)
                .position(
                    x: CGFloat(btn.col) * colW + colW / 2,
                    y: CGFloat(btn.row) * rowH + rowH / 2
                )
            }
        }
        .frame(width: gridW, height: gridH)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private func logSection(_ lines: [String]) -> some View {
    Section {
        Text(lines.isEmpty ? "No output yet." : lines.joined(separator: "\n"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(lines.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
    } header: { HeaderLabel("Log", symbol: "terminal") }
}

private struct PhotoPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first?.itemProvider else { completion(nil); return }
            item.loadObject(ofClass: UIImage.self) { object, _ in DispatchQueue.main.async { self.completion(object as? UIImage) } }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

