import SwiftUI
import Combine
import UIKit
import Foundation

@MainActor
final class ErosionAirCardFeatures: ObservableObject {
    static let shared = ErosionAirCardFeatures()

    @Published var cards: [CardItem] = []
    @Published var walletLog: [String] = []
    @Published var walletScanning = false
    @Published var walletFlashing = false

    @Published var loadedTheme: PasscodeThemeInfo?
    @Published var passcodeLog: [String] = []
    @Published var passcodeFlashing = false

    // AirCard-style passcode creator state. These are UI/payload-preparation features;
    // the existing Erosion flash transport remains unchanged.
    @Published var passcodeMode: CreatorMode = .applyTheme
    @Published var sliceMode: SliceMode = .posterSlice
    @Published var posterImage: UIImage?
    @Published var posterZoom: CGFloat = 1.0
    @Published var posterOffset: CGPoint = .zero
    @Published var maskToCircles = false
    @Published var slicedKeys: [String: UIImage] = [:]
    @Published var customKeys: [String: UIImage] = [:]
    @Published var rawIndividualImages: [String: UIImage] = [:]
    @Published var individualOffsets: [String: CGPoint] = [:]
    @Published var individualZooms: [String: CGFloat] = [:]
    @Published var selectedKeyDigit: String?
    @Published var targetTelephonyVersion = "TelephonyUI-10"
    @Published var passcodeLanguageTarget: PasscodeLanguageTarget = .en
    @Published var passcodeBoldTarget: PasscodeBoldTarget = .both
    @Published var exportedThemeURL: URL?
    @Published var showShareSheet = false

    @Published var tendieItems: [TendieItem] = []
    @Published var wallpaperLog: [String] = []
    @Published var wallpaperBusy = false
    @Published var posterBoardContainer = ""

    private var syslogRunning = false
    // Keep these patterns aligned with AirCard's live scanner. The important distinction
    // is that generic UUID/uniqueID log values are NOT card hashes.
    nonisolated private static let cardRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"/(?:Cards|Passes/Cards)/([-A-Za-z0-9_+=]{20,44})(?:\.pkpass|\.cache|\.pkcache|/|\s|"|'|\)|,|$)"#),
        try! NSRegularExpression(pattern: #"/([-A-Za-z0-9_+=]{20,44})\.(?:pkpass|cache|pkcache)"#),
        try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9+/_-])([A-Za-z0-9+/_-]{27}=)(?![A-Za-z0-9+/_-])"#),
        try! NSRegularExpression(pattern: #"PDCardFileManager: writing card\s+([A-Za-z0-9+/_-]+={0,2})(?=\s|\)|,|$)"#),
        try! NSRegularExpression(pattern: #"PDPassLibrary: wrote pass\s+([A-Za-z0-9+/_-]+={0,2})(?=\s|\)|,|$)"#),
        try! NSRegularExpression(pattern: #"VerificationCheck\.([A-Za-z0-9+/_-]+={0,2})(?=\s|\)|,|$)"#)
    ]

    nonisolated private static let dummyCardHashes: Set<String> = [
        "OM6NYhwXMZrAw0sRUjR62wmF4ZQ=",
        "M6nDwZrkYbFlsodLgCbvyFZQ1cc=",
        "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=",
        "hwAtAmHKYwsQrJbT5cTNDsaxVME="
    ]

    private init() {
        passcodeLanguageTarget = Self.detectedDeviceLanguage
        loadSavedCards()
        loadTendies()
        posterBoardContainer = UserDefaults.standard.string(forKey: "erosion.posterboard_container") ?? ""
    }

    var pairingPath: String { ErosionAirlift.shared.pairingPath }
    var ready: Bool { ErosionAirlift.shared.hasPairing && AirliftNetworkStatus.isConnected() }

    // MARK: Wallet

    nonisolated static func cardImagePath(for cardId: String) -> URL {
        let safe = cardId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WalletCards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("card_\(safe).png")
    }

    func loadSavedCards() {
        let saved = UserDefaults.standard.stringArray(forKey: "erosion.wallet.cards") ?? []
        cards = saved.compactMap { CardItem.cleanCardId($0) }.map { id in
            let data = try? Data(contentsOf: Self.cardImagePath(for: id))
            return CardItem(id: id, customImageData: data, customImage: data.flatMap { ImageEngine.safeImageFromData($0, maxDimension: 512) })
        }
    }

    func saveCards() {
        UserDefaults.standard.set(cards.map(\.id), forKey: "erosion.wallet.cards")
    }

    @discardableResult
    func addCardHash(_ raw: String) -> [String] {
        var added: [String] = []
        for part in raw.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))) {
            guard let id = CardItem.cleanCardId(part), !Self.dummyCardHashes.contains(id), !cards.contains(where: { $0.id == id }) else { continue }
            cards.append(CardItem(id: id))
            added.append(id)
        }
        if !added.isEmpty { saveCards() }
        return added
    }

    func setCardImage(id: String, image: UIImage) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        let thumb = ImageEngine.normalizeAndDownsample(image, maxDimension: 512)
        cards[i].customImage = thumb
        cards[i].customImageData = ImageEngine.prepareCardImage(from: image)
        if let data = cards[i].customImageData { try? data.write(to: Self.cardImagePath(for: id), options: .atomic) }
    }

    func deleteCard(_ id: String) {
        cards.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.cardImagePath(for: id))
        saveCards()
    }

    func startCardScan() {
        guard ErosionAirlift.shared.hasPairing else {
            walletLog.append("❌ Import a pairing file first."); return
        }
        guard !syslogRunning else { return }
        walletLog.removeAll()
        walletScanning = true
        syslogRunning = true
        let pair = pairingPath
        walletLog.append("🔎 Scanning device log for Wallet card identifiers…")

        let strongSelf = self
        DispatchQueue.global(qos: .userInitiated).async {
            var error: UnsafeMutablePointer<CChar>?
            let rc = pair.withCString { p in
                al_syslog_stream_start(p, { ctx, line in
                    guard let ctx, let line else { return }
                    let owner = Unmanaged<ErosionAirCardFeatures>.fromOpaque(ctx).takeUnretainedValue()
                    owner.parseWalletLog(String(cString: line))
                }, Unmanaged.passUnretained(strongSelf).toOpaque(), &error)
            }
            if let error { let message = String(cString: error); al_string_free(error); DispatchQueue.main.async { strongSelf.walletLog.append("❌ Syslog error: \(message)") } }
            DispatchQueue.main.async { strongSelf.walletScanning = false; strongSelf.syslogRunning = false; strongSelf.walletLog.append("⏹ Scan stopped.") }
            _ = rc
        }
    }

    func stopCardScan() {
        guard syslogRunning else { return }
        al_syslog_stream_stop()
        syslogRunning = false
        walletScanning = false
    }

    nonisolated private func parseWalletLog(_ line: String) {
        let lower = line.lowercased()
        let isWalletSubsystem = lower.contains("passd") ||
                                lower.contains("passbook") ||
                                lower.contains("passkit") ||
                                lower.contains("stockholm") ||
                                lower.contains("nanopassd") ||
                                lower.contains("wallet") ||
                                lower.contains("pdcardfilemanager") ||
                                lower.contains("pdpasslibrary") ||
                                lower.contains("verificationcheck") ||
                                lower.contains("/cards/")
        guard isWalletSubsystem else { return }

        let isWalletContext = lower.contains("card") ||
                              lower.contains("pass") ||
                              lower.contains("payment") ||
                              lower.contains("pkpass") ||
                              lower.contains("uniqueid") ||
                              lower.contains("identifier") ||
                              lower.contains("face") ||
                              lower.contains("cache") ||
                              lower.contains("stockholm") ||
                              lower.contains("pdcardfilemanager") ||
                              lower.contains("pdpasslibrary") ||
                              lower.contains("verificationcheck") ||
                              lower.contains("/cards/")
        guard isWalletContext else { return }

        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        for regex in Self.cardRegexes {
            let matches = regex.matches(in: line, range: range)
            for match in matches where match.numberOfRanges > 1 {
                let raw = ns.substring(with: match.range(at: 1))
                guard let candidate = CardItem.cleanCardId(raw), !Self.dummyCardHashes.contains(candidate) else { continue }
                Task { @MainActor in
                    let added = self.addCardHash(candidate)
                    if !added.isEmpty {
                        self.walletLog.append("✅ Found card hash: \(candidate.prefix(24))…")
                    }
                }
            }
        }
    }

    func flashSelectedCards() {
        guard ready else { walletLog.append("❌ Pairing file and LocalDevVPN are required."); return }
        let selected = cards.filter { $0.isSelected && ($0.customImage != nil || $0.customImageData != nil) }
        guard !selected.isEmpty else { walletLog.append("❌ Select a card with custom artwork first."); return }
        walletFlashing = true
        walletLog.removeAll()
        let pair = pairingPath

        let strongSelf = self
        Task.detached {
            var success = 0
            for card in selected {
                let id = CardItem.cleanCardId(card.id) ?? card.id
                let source = card.customImageData.flatMap(UIImage.init(data:)).flatMap { ImageEngine.prepareAllCardSkins(from: $0) } ?? [:]
                guard !source.isEmpty else { continue }
                let stage = FileManager.default.temporaryDirectory.appendingPathComponent("erosion_wallet_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                for (name, data) in source { try? data.write(to: stage.appendingPathComponent(name)) }
                let target = "/var/mobile/Library/Passes/Cards/\(id).pkpass"
                let ok = await Self.writeDirectory(pair: pair, source: stage.path, target: target) { line in
                    Task { @MainActor in strongSelf.walletLog.append("  \(line)") }
                }
                try? FileManager.default.removeItem(at: stage)
                if ok {
                    success += 1
                    await MainActor.run { strongSelf.walletLog.append("✅ Applied artwork to \(id.prefix(12))…") }
                } else {
                    await MainActor.run { strongSelf.walletLog.append("❌ Failed to write \(id.prefix(12))…") }
                }

                let inv = FileManager.default.temporaryDirectory.appendingPathComponent("erosion_wallet_inv_\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: inv, withIntermediateDirectories: true)
                for leaf in ["FrontFace", "Preview", "PlaceHolder"] { try? Data("corrupted".utf8).write(to: inv.appendingPathComponent(leaf)) }
                for ext in [".cache", ".pkcache"] { _ = await Self.writeDirectory(pair: pair, source: inv.path, target: "/var/mobile/Library/Passes/Cards/\(id)\(ext)", log: nil) }
                try? FileManager.default.removeItem(at: inv)
            }
            await MainActor.run {
                strongSelf.walletFlashing = false
                strongSelf.walletLog.append("🎉 \(success)/\(selected.count) card(s) processed. Force-close Wallet to refresh artwork.")
            }
        }
    }

    // MARK: Passcode

    func loadPassthm(url: URL) {
        importPassthm(url)
    }

    func importPassthm(_ url: URL) {
        Task.detached { [weak self] in
            let result = PasscodeThemeReader.inspect(url: url)
            await MainActor.run {
                guard let result else { self?.passcodeLog.append("❌ Invalid or unsupported .passthm file."); return }
                self?.loadedTheme = PasscodeThemeInfo(name: url.deletingPathExtension().lastPathComponent, filePath: url.path, fileCount: result.fileCount, keysPreview: result.keys, rawKeyData: result.rawData)
                self?.passcodeLog = ["✅ Loaded \(result.keys.count) keypad images from \(url.lastPathComponent)"]
            }
        }
    }

    func flashPassthm() {
        guard ready, let theme = loadedTheme else { passcodeLog.append("❌ Pairing, LocalDevVPN and a .passthm theme are required."); return }
        passcodeFlashing = true
        passcodeLog.removeAll()
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("erosion_passthm_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let langs: [String] = passcodeLanguageTarget == .all ? KeypadLocales.all : [passcodeLanguageTarget.code]
        let suffixes: [String] = {
            switch passcodeBoldTarget {
            case .both: return ["", "-bold"]
            case .boldOnly: return ["-bold"]
            case .regularOnly: return [""]
            }
        }()
        for (digit, image) in theme.keysPreview {
            let data = theme.rawKeyData[digit] ?? image.pngData()
            guard let data else { continue }
            let subtext = KeypadLayout.subtexts[digit] ?? ""
            for lang in langs { for suffix in suffixes {
                let names: [String]
                if digit == "0" { names = ["\(lang)-0---white\(suffix).png", "\(lang)-0-+--white\(suffix).png"] }
                else if digit == "1" { names = ["\(lang)-1---white\(suffix).png"] }
                else { names = ["\(lang)-\(digit)---white\(suffix).png", "\(lang)-\(digit)-\(subtext)--white\(suffix).png"] }
                for name in names { try? data.write(to: stage.appendingPathComponent(name)) }
            }}
        }
        try? Data().write(to: stage.appendingPathComponent("_big"))
        let pair = pairingPath
        Task.detached { [weak self] in
            // iOS 27 uses TelephonyUI-10. Do not write to legacy cache folders on iOS 27: 
            // their absence can turn an otherwise successful flash into a reported failure.
            let targets = ["/var/mobile/Library/Caches/TelephonyUI-10"]
            var ok = true
            for target in targets {
                let result = await Self.writeDirectory(pair: pair, source: stage.path, target: target) { line in
                    Task { @MainActor in self?.passcodeLog.append("  \(line)") }
                }
                ok = ok && result
            }
            try? FileManager.default.removeItem(at: stage)
            await MainActor.run {
                self?.passcodeFlashing = false
                if ok {
                    self?.passcodeLog.append("🎉 TelephonyUI-10 updated. Refreshing SpringBoard…")
                    var error: UnsafeMutablePointer<CChar>?
                    _ = pair.withCString { al_device_respring($0, nil, nil, &error) }
                    if let error { al_string_free(error) }
                    self?.passcodeLog.append("✅ Passcode theme applied. Lock the device to see it.")
                } else {
                    self?.passcodeLog.append("❌ TelephonyUI-10 write failed.")
                }
            }
        }
    }

    // MARK: Passcode Theme Creator

    static var detectedDeviceLanguage: PasscodeLanguageTarget {
        let code = Locale.preferredLanguages.first?.components(separatedBy: "-").first?.lowercased() ?? "en"
        for target in PasscodeLanguageTarget.allCases where target.code == code {
            return target
        }
        return .en
    }

    var effectiveKeys: [String: UIImage] {
        sliceMode == .posterSlice ? slicedKeys : customKeys
    }

    func setPosterImage(_ image: UIImage) {
        posterImage = ImageEngine.normalizeAndDownsample(image, maxDimension: 2048)
        posterZoom = 1.0
        posterOffset = .zero
        updatePosterSlicing()
    }

    func updatePosterSlicing() {
        guard posterImage != nil else { slicedKeys = [:]; return }
        slicedKeys = ImageEngine.slicePoster(
            image: posterImage!,
            zoom: posterZoom,
            offset: posterOffset,
            maskToCircles: maskToCircles
        )
    }

    func resetPosterPosition() {
        posterZoom = 1.0
        posterOffset = .zero
        updatePosterSlicing()
    }

    func setIndividualKey(digit: String, image: UIImage) {
        rawIndividualImages[digit] = image
        individualOffsets[digit] = .zero
        individualZooms[digit] = 1.0
        selectedKeyDigit = digit
        updateIndividualKey(digit: digit)
    }

    func updateIndividualKey(digit: String) {
        guard let raw = rawIndividualImages[digit] else { return }
        let offset = individualOffsets[digit] ?? .zero
        let zoom = individualZooms[digit] ?? 1.0
        if let cropped = ImageEngine.cropToCircle(
            image: raw,
            targetSize: CGSize(width: 225, height: 225),
            circleDiameter: 222.0,
            zoom: zoom,
            offset: offset
        ) {
            customKeys[digit] = cropped
        }
    }

    func clearIndividualKey(digit: String) {
        customKeys.removeValue(forKey: digit)
        rawIndividualImages.removeValue(forKey: digit)
        individualOffsets.removeValue(forKey: digit)
        individualZooms.removeValue(forKey: digit)
        if selectedKeyDigit == digit { selectedKeyDigit = nil }
    }

    func clearAllCreator() {
        posterImage = nil
        posterZoom = 1.0
        posterOffset = .zero
        slicedKeys.removeAll()
        customKeys.removeAll()
        rawIndividualImages.removeAll()
        individualOffsets.removeAll()
        individualZooms.removeAll()
        selectedKeyDigit = nil
    }

    func adoptThemeIntoCreator() {
        guard let theme = loadedTheme else { return }
        for (digit, image) in theme.keysPreview {
            customKeys[digit] = image
            rawIndividualImages[digit] = image
            individualOffsets[digit] = .zero
            individualZooms[digit] = 1.0
        }
        selectedKeyDigit = nil
        sliceMode = .individualKeys
        passcodeMode = .themeCreator
    }

    func exportPassthm() -> URL? {
        let keys = effectiveKeys
        guard !keys.isEmpty else {
            passcodeLog.append("❌ Add at least one keypad image before exporting.")
            return nil
        }
        do {
            let data = try PasscodeThemePackager.buildPassthm(
                keys: keys,
                telephonyVersion: targetTelephonyVersion,
                language: passcodeLanguageTarget,
                bold: passcodeBoldTarget
            )
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Erosion_Custom_\(Int(Date().timeIntervalSince1970)).passthm")
            try data.write(to: url, options: .atomic)
            exportedThemeURL = url
            showShareSheet = true
            passcodeLog.append("✅ Exported \(url.lastPathComponent)")
            return url
        } catch {
            passcodeLog.append("❌ Export failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Wallpapers

    func importTendie(_ url: URL) {
        Task { @MainActor in
            do {
                let item = try await TendiesEngine.shared.importTendie(from: url)
                tendieItems.removeAll { $0.fileName == item.fileName }
                tendieItems.append(item)
                saveTendies()
                wallpaperLog.append("✅ Imported \(item.name)")
            } catch { wallpaperLog.append("❌ \(error.localizedDescription)") }
        }
    }

    func loadTendies() {
        if let data = UserDefaults.standard.data(forKey: "erosion.tendies.items"), let items = try? JSONDecoder().decode([TendieItem].self, from: data) { tendieItems = items }
    }

    func saveTendies() {
        if let data = try? JSONEncoder().encode(tendieItems) { UserDefaults.standard.set(data, forKey: "erosion.tendies.items") }
    }

    func deleteTendie(_ item: TendieItem) {
        try? FileManager.default.removeItem(at: item.fileURL)
        tendieItems.removeAll { $0.id == item.id }
        saveTendies()
    }

    func detectPosterBoard() {
        guard ErosionAirlift.shared.hasPairing else { wallpaperLog.append("❌ Import a pairing file first."); return }
        Task { @MainActor in
            do {
                posterBoardContainer = try await TendiesEngine.shared.detectPosterBoardContainer(pairingPath: pairingPath)
                UserDefaults.standard.set(posterBoardContainer, forKey: "erosion.posterboard_container")
                wallpaperLog.append("✅ PosterBoard container detected.")
            } catch { wallpaperLog.append("❌ Detection failed: \(error.localizedDescription)") }
        }
    }

    func flashWallpapers() {
        guard ready else { wallpaperLog.append("❌ Pairing file and LocalDevVPN are required."); return }
        let selected = tendieItems.filter(\.isSelected)
        guard !selected.isEmpty else { wallpaperLog.append("❌ Import/select a .tendies wallpaper first."); return }
        wallpaperBusy = true
        wallpaperLog.removeAll()
        Task { @MainActor in
            do {
                var container = posterBoardContainer
                if container.isEmpty { container = try await TendiesEngine.shared.detectPosterBoardContainer(pairingPath: pairingPath); posterBoardContainer = container }
                try await TendiesEngine.shared.flashTendies(items: selected, containerPath: container, resetProtections: true, pairingPath: pairingPath, log: { [weak self] line in self?.wallpaperLog.append(line) }, progress: { _ in })
                wallpaperLog.append("🎉 Wallpapers injected. Refreshing SpringBoard…")
                var error: UnsafeMutablePointer<CChar>?
                _ = pairingPath.withCString { al_device_respring($0, nil, nil, &error) }
                if let error { al_string_free(error) }
            } catch { wallpaperLog.append("❌ \(error.localizedDescription)") }
            wallpaperBusy = false
        }
    }

    nonisolated private static func writeDirectory(pair: String, source: String, target: String, log: ((String) -> Void)?) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var outError: UnsafeMutablePointer<CChar>?
                let rc = pair.withCString { p in source.withCString { s in target.withCString { t in
                    al_exploit_write_dir(p, s, t, erosionAirCardCLogCallback, nil, &outError)
                }}}
                if let outError { log?(String(cString: outError)); al_string_free(outError) }
                continuation.resume(returning: rc == 0)
            }
        }
    }
}
