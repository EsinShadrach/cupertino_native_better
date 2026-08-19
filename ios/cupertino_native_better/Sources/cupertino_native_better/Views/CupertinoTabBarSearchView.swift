import Flutter
import UIKit

/// iOS 26+ native tab bar with search support.
/// Uses UITabBar with UITabBarSystemItem.search for native liquid glass morphing effect.
@available(iOS 26.0, *)
class CupertinoTabBarSearchPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
    /// Vertical room reserved above the bar for the Liquid Glass selection
    /// pill (and the floating search orb), both of which draw past the
    /// UITabBar's top edge. The bar is pinned this far below
    /// `container.topAnchor` and `getIntrinsicSize` reports
    /// `barHeight + pillTopRoom`, so Flutter's `ClipRect`/`SizedBox` wrapper
    /// leaves room for the overflow instead of cropping it.
    ///
    /// Must stay in sync with the identical constant in
    /// `CupertinoTabBarPlatformView` — otherwise adding a `searchItem`
    /// shifts the whole bar up by this amount relative to the non-search
    /// bar, since the two views would report different intrinsic heights.
    private static let pillTopRoom: CGFloat = 14.0

    /// UITabBar's nominal icon edge, used to grow the reported height when
    /// larger custom icons are supplied. Mirrors `CupertinoTabBarPlatformView`.
    private static let defaultIconSize: CGFloat = 25.0

    private let channel: FlutterMethodChannel
    private let container: UIView
    private var tabBar: UITabBar?

    // State
    private var currentLabels: [String] = []
    private var currentSymbols: [String] = []
    private var currentActiveSymbols: [String] = []
    private var currentBadges: [String] = []
    private var currentBadgeCounts: [Int?] = []

    // Custom icon sources, in resolution priority order:
    // imageAssetData > imageAssetPaths > customIconBytes > SF Symbol.
    // Kept identical to `CupertinoTabBarPlatformView.buildItems` so a
    // `CNTabBarItem` renders the same with or without a `searchItem`.
    private var currentCustomIconBytes: [Data?] = []
    private var currentActiveCustomIconBytes: [Data?] = []
    private var currentImageAssetPaths: [String] = []
    private var currentActiveImageAssetPaths: [String] = []
    private var currentImageAssetData: [Data?] = []
    private var currentActiveImageAssetData: [Data?] = []
    private var currentImageAssetFormats: [String] = []
    private var currentActiveImageAssetFormats: [String] = []
    private var currentIconSizes: [NSNumber?] = []
    private var iconScale: CGFloat = UIScreen.main.scale

    private var labelFontFamily: String? = nil
    private var labelFontSize: CGFloat = 0 // 0 means system default (~10pt)

    private var selectedIndex: Int = 0
    private var tintColor: UIColor?
    private var unselectedTintColor: UIColor?
    private var searchPlaceholder: String = "Search"
    private var searchLabel: String = "Search"

    // Search tab is always the last item
    private var searchItemIndex: Int = -1

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(name: "CupertinoNativeTabBar_\(viewId)", binaryMessenger: messenger)
        self.container = UIView(frame: frame)

        super.init()

        // Parse creation params
        if let dict = args as? [String: Any] {
            parseItemParams(dict)
            if let v = dict["selectedIndex"] as? NSNumber {
                selectedIndex = v.intValue
            }
            if let v = dict["isDark"] as? NSNumber {
                container.overrideUserInterfaceStyle = v.boolValue ? .dark : .light
            }
            if let style = dict["style"] as? [String: Any] {
                if let n = style["tint"] as? NSNumber {
                    tintColor = ImageUtils.colorFromARGB(n.intValue)
                }
                if let n = style["unselectedTint"] as? NSNumber {
                    unselectedTintColor = ImageUtils.colorFromARGB(n.intValue)
                }
            }
            if let ff = dict["labelFontFamily"] as? String, !ff.isEmpty { labelFontFamily = ff }
            if let fs = dict["labelFontSize"] as? NSNumber, fs.doubleValue > 0 {
                labelFontSize = CGFloat(truncating: fs)
            }
            searchPlaceholder = (dict["searchPlaceholder"] as? String) ?? "Search"
            searchLabel = (dict["searchLabel"] as? String) ?? "Search"
        }

        container.backgroundColor = .clear
        container.isOpaque = false
        // This view is iOS 26+ only and uses the Liquid Glass tab bar where
        // the search button renders as a floating glass orb that extends
        // slightly above the UITabBar's bounds. Clipping the container or
        // bar (the Issue #2 containment pattern) crops the orb's top edge.
        // The shadow concerns Issue #2 addressed only apply to legacy
        // UITabBar appearance — iOS 26 Liquid Glass already has the
        // top-edge hairline disabled via `bar.shadowImage = UIImage()` and
        // `bar.layer.shadowOpacity = 0` below, so leaving clipsToBounds
        // false is safe here.
        container.clipsToBounds = false
        container.layer.shadowOpacity = 0
        container.layer.backgroundColor = UIColor.clear.cgColor

        setupUI()
        setupMethodChannel()
    }

    // MARK: - Param parsing

    /// Reads every item-describing key out of a creation-params / `setItems`
    /// dictionary. Shared by `init` and the `setItems` channel handler so the
    /// two can't drift apart (the original only read labels/symbols in both,
    /// silently dropping custom icons and image assets).
    private func parseItemParams(_ dict: [String: Any]) {
        currentLabels = (dict["labels"] as? [String]) ?? []
        currentSymbols = (dict["sfSymbols"] as? [String]) ?? []
        currentActiveSymbols = (dict["activeSfSymbols"] as? [String]) ?? []

        // Dart sends `badges` as pre-formatted strings; `badgeCounts` is
        // accepted too for callers that send raw counts.
        currentBadges = (dict["badges"] as? [String]) ?? []
        if let badgeData = dict["badgeCounts"] as? [NSNumber?] {
            currentBadgeCounts = badgeData.map { $0?.intValue }
        }

        if let bytesArray = dict["customIconBytes"] as? [FlutterStandardTypedData?] {
            currentCustomIconBytes = bytesArray.map { $0?.data }
        }
        if let bytesArray = dict["activeCustomIconBytes"] as? [FlutterStandardTypedData?] {
            currentActiveCustomIconBytes = bytesArray.map { $0?.data }
        }
        currentImageAssetPaths = (dict["imageAssetPaths"] as? [String]) ?? []
        currentActiveImageAssetPaths = (dict["activeImageAssetPaths"] as? [String]) ?? []
        if let bytesArray = dict["imageAssetData"] as? [FlutterStandardTypedData?] {
            currentImageAssetData = bytesArray.map { $0?.data }
        }
        if let bytesArray = dict["activeImageAssetData"] as? [FlutterStandardTypedData?] {
            currentActiveImageAssetData = bytesArray.map { $0?.data }
        }
        currentImageAssetFormats = (dict["imageAssetFormats"] as? [String]) ?? []
        currentActiveImageAssetFormats = (dict["activeImageAssetFormats"] as? [String]) ?? []
        currentIconSizes = (dict["sfSymbolSizes"] as? [NSNumber?]) ?? []
        if let scale = dict["iconScale"] as? NSNumber {
            iconScale = CGFloat(truncating: scale)
        }

        // SVG assets have to be rasterized before first use or the tab bar
        // lays out with nil images.
        let allAssetPaths = Set(currentImageAssetPaths + currentActiveImageAssetPaths)
            .filter { !$0.isEmpty }
        if !allAssetPaths.isEmpty {
            SVGImageLoader.shared.preloadAssetsFromPaths(Array(allAssetPaths))
        }
    }

    private func setupUI() {
        // Create native UITabBar - gets liquid glass morphing effect on iOS 26+
        let bar = UITabBar(frame: .zero)
        tabBar = bar
        bar.delegate = self
        bar.translatesAutoresizingMaskIntoConstraints = false

        // iOS 26+ - use direct properties for liquid glass effect
        // Skip UITabBarAppearance as it interferes with iOS 26 styling
        bar.isTranslucent = true
        bar.backgroundImage = UIImage()
        bar.shadowImage = UIImage()
        bar.backgroundColor = .clear
        // Don't clip — the Liquid Glass search orb extends above the bar's
        // bounds and needs the overflow to render its top edge correctly.
        // Top-edge shadow hairline is already suppressed by shadowImage
        // above and layer.shadowOpacity below.
        bar.clipsToBounds = false
        bar.layer.shadowOpacity = 0

        // Set tint colors
        if let tint = tintColor {
            bar.tintColor = tint
        }
        if let unselTint = unselectedTintColor {
            bar.unselectedItemTintColor = unselTint
        }

        // Build tab items including search
        bar.items = buildTabItems()

        // Set selected item (not the search item)
        if let items = bar.items, selectedIndex >= 0, selectedIndex < items.count {
            if selectedIndex != searchItemIndex {
                bar.selectedItem = items[selectedIndex]
            } else if items.count > 1 {
                bar.selectedItem = items[0]
                selectedIndex = 0
            }
        }

        container.addSubview(bar)

        // Pin the bar `pillTopRoom` below the container's top edge — see the
        // constant's doc comment. `getIntrinsicSize` adds the same amount so
        // the bar lands in exactly the same place as the non-search bar.
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.pillTopRoom),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - Item building

    /// Resolves the icon for item `i`, honouring the same source priority as
    /// the non-search bar: image asset data > image asset path > rendered
    /// custom icon bytes > SF Symbol.
    private func resolveImage(
        at i: Int,
        assetData: [Data?],
        assetPaths: [String],
        assetFormats: [String],
        customBytes: [Data?],
        symbols: [String],
        size: CGSize?
    ) -> UIImage? {
        if i < assetData.count, let data = assetData[i] {
            return ImageUtils.createImageFromData(
                data,
                format: (i < assetFormats.count) ? assetFormats[i] : nil,
                size: size,
                scale: iconScale
            )
        }
        if i < assetPaths.count, !assetPaths[i].isEmpty {
            return ImageUtils.loadFlutterAsset(assetPaths[i], size: size)
        }
        if i < customBytes.count, let data = customBytes[i] {
            // Template mode so bar.tintColor / unselectedItemTintColor drive
            // the colour, matching the non-search bar.
            return UIImage(data: data, scale: iconScale)?.withRenderingMode(.alwaysTemplate)
        }
        if i < symbols.count, !symbols[i].isEmpty {
            // Template mode so tintColor applies, as before.
            if let sizeNum = (i < currentIconSizes.count) ? currentIconSizes[i] : nil,
               sizeNum.doubleValue > 0 {
                let config = UIImage.SymbolConfiguration(pointSize: CGFloat(sizeNum.doubleValue))
                return UIImage(systemName: symbols[i], withConfiguration: config)?
                    .withRenderingMode(.alwaysTemplate)
            }
            return UIImage(systemName: symbols[i])?.withRenderingMode(.alwaysTemplate)
        }
        return nil
    }

    private func buildTabItems() -> [UITabBarItem] {
        var items: [UITabBarItem] = []
        let count = max(currentLabels.count, currentSymbols.count)

        for i in 0..<count {
            let title = i < currentLabels.count && !currentLabels[i].isEmpty ? currentLabels[i] : nil

            let imgSize: CGSize? = (i < currentIconSizes.count)
                ? currentIconSizes[i].flatMap {
                    $0.doubleValue > 0
                        ? CGSize(width: $0.doubleValue, height: $0.doubleValue)
                        : nil
                }
                : nil

            var image = resolveImage(
                at: i,
                assetData: currentImageAssetData,
                assetPaths: currentImageAssetPaths,
                assetFormats: currentImageAssetFormats,
                customBytes: currentCustomIconBytes,
                symbols: currentSymbols,
                size: imgSize
            )

            let selectedImage = resolveImage(
                at: i,
                assetData: currentActiveImageAssetData,
                assetPaths: currentActiveImageAssetPaths,
                assetFormats: currentActiveImageAssetFormats,
                customBytes: currentActiveCustomIconBytes,
                symbols: currentActiveSymbols,
                size: imgSize
            ) ?? image

            // iOS 26+: an explicit unselected tint has to be baked into the
            // unselected image, since `unselectedItemTintColor` alone doesn't
            // reliably apply under Liquid Glass. Restricted to template
            // images (SF Symbols and rendered custom icons) — a colored
            // image asset keeps its own colors, same as the non-search bar.
            if let unselTint = unselectedTintColor,
               let base = image,
               base.renderingMode == .alwaysTemplate {
                image = base.withTintColor(unselTint, renderingMode: .alwaysOriginal)
            }

            let item = UITabBarItem(title: title, image: image, selectedImage: selectedImage)
            item.tag = i

            // Badge: prefer the pre-formatted string Dart sends, fall back to
            // a raw count.
            if i < currentBadges.count, !currentBadges[i].isEmpty {
                item.badgeValue = currentBadges[i]
            } else if i < currentBadgeCounts.count, let count = currentBadgeCounts[i], count > 0 {
                item.badgeValue = count > 99 ? "99+" : String(count)
            } else {
                item.badgeValue = nil
            }

            applyLabelFont(to: item)

            // Push the title down when the icon is taller than stock, so the
            // two don't overlap. Mirrors the non-search bar.
            if let sizeNum = (i < currentIconSizes.count) ? currentIconSizes[i] : nil,
               sizeNum.doubleValue > Double(Self.defaultIconSize) {
                let offset = CGFloat(sizeNum.doubleValue) - Self.defaultIconSize
                item.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: offset)
            }

            items.append(item)
        }

        // Add search tab using UITabBarSystemItem.search for native iOS 26 liquid glass styling
        let searchItem = UITabBarItem(tabBarSystemItem: .search, tag: 9999)
        if !searchLabel.isEmpty {
            searchItem.title = searchLabel
        }
        applyLabelFont(to: searchItem)
        items.append(searchItem)
        searchItemIndex = items.count - 1

        return items
    }

    /// Applies `labelFontFamily`/`labelFontSize` to a single item.
    ///
    /// Deliberately per-item rather than via `UITabBarAppearance`: this view
    /// avoids setting an appearance at all because that overrides the iOS 26
    /// Liquid Glass background, and item-level title attributes only take
    /// effect precisely because no appearance is installed here.
    private func applyLabelFont(to item: UITabBarItem) {
        guard let fontFamily = labelFontFamily, !fontFamily.isEmpty else { return }
        let size = labelFontSize > 0 ? labelFontSize : 10.0
        let font = UIFont(name: fontFamily, size: size) ?? UIFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        item.setTitleTextAttributes(attrs, for: .normal)
        item.setTitleTextAttributes(attrs, for: .selected)
    }

    private func setupMethodChannel() {
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }

            switch call.method {
            case "getIntrinsicSize":
                if let bar = self.tabBar {
                    let size = bar.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                    // Grow for oversized icons, then add the pill/orb headroom
                    // the layout constraints reserve above the bar. Without
                    // this the reported height is `pillTopRoom` short and the
                    // bar renders that much higher than the non-search bar.
                    let maxIconSize = self.currentIconSizes
                        .compactMap { $0.map { CGFloat(truncating: $0) } }
                        .max() ?? Self.defaultIconSize
                    let extraHeight = max(0, maxIconSize - Self.defaultIconSize)
                    let dynamicHeight = size.height + extraHeight + Self.pillTopRoom
                    result(["width": Double(self.container.bounds.width), "height": Double(dynamicHeight)])
                } else {
                    result(["width": Double(self.container.bounds.width), "height": 50.0])
                }

            case "setSelectedIndex":
                if let args = call.arguments as? [String: Any],
                   let idx = (args["index"] as? NSNumber)?.intValue,
                   let bar = self.tabBar,
                   let items = bar.items,
                   idx >= 0, idx < items.count {
                    if idx != self.searchItemIndex {
                        bar.selectedItem = items[idx]
                        self.selectedIndex = idx
                    }
                    result(nil)
                } else {
                    result(FlutterError(code: "bad_args", message: "Missing or invalid index", details: nil))
                }

            case "activateSearch":
                // Notify Flutter to show search UI
                self.channel.invokeMethod("searchActiveChanged", arguments: ["isActive": true])
                result(nil)

            case "deactivateSearch":
                // Restore previous selection
                if let bar = self.tabBar,
                   let items = bar.items,
                   self.selectedIndex >= 0,
                   self.selectedIndex < items.count,
                   self.selectedIndex != self.searchItemIndex {
                    bar.selectedItem = items[self.selectedIndex]
                }
                self.channel.invokeMethod("searchActiveChanged", arguments: ["isActive": false])
                result(nil)

            case "setSearchText":
                // Search text is handled by Flutter
                result(nil)

            case "setBrightness":
                if let args = call.arguments as? [String: Any],
                   let isDark = (args["isDark"] as? NSNumber)?.boolValue {
                    self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
                    result(nil)
                } else {
                    result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
                }

            case "setStyle":
                if let args = call.arguments as? [String: Any] {
                    if let n = args["tint"] as? NSNumber {
                        let color = ImageUtils.colorFromARGB(n.intValue)
                        self.tabBar?.tintColor = color
                        self.tintColor = color
                    }
                    if let n = args["unselectedTint"] as? NSNumber {
                        let color = ImageUtils.colorFromARGB(n.intValue)
                        self.tabBar?.unselectedItemTintColor = color
                        self.unselectedTintColor = color
                        // Rebuild items with new unselected color
                        self.rebuildItemsWithCurrentColors()
                    }
                    result(nil)
                } else {
                    result(FlutterError(code: "bad_args", message: "Missing style", details: nil))
                }

            case "setItems":
                if let args = call.arguments as? [String: Any] {
                    self.parseItemParams(args)

                    self.tabBar?.items = self.buildTabItems()

                    if let idx = (args["selectedIndex"] as? NSNumber)?.intValue,
                       let bar = self.tabBar,
                       let items = bar.items,
                       idx >= 0, idx < items.count, idx != self.searchItemIndex {
                        bar.selectedItem = items[idx]
                        self.selectedIndex = idx
                    }
                    result(nil)
                } else {
                    result(FlutterError(code: "bad_args", message: "Missing items", details: nil))
                }

            case "setLayout":
                if let args = call.arguments as? [String: Any] {
                    var needsRebuild = false
                    if let ff = args["labelFontFamily"] as? String {
                        self.labelFontFamily = ff.isEmpty ? nil : ff
                        needsRebuild = true
                    }
                    if let fs = args["labelFontSize"] as? NSNumber, fs.doubleValue > 0 {
                        self.labelFontSize = CGFloat(truncating: fs)
                        needsRebuild = true
                    }
                    if needsRebuild { self.rebuildItemsWithCurrentColors() }
                }
                result(nil)

            case "setBadgeCounts":
                if let args = call.arguments as? [String: Any],
                   let badgeData = args["badgeCounts"] as? [NSNumber?] {
                    let badgeCounts = badgeData.map { $0?.intValue }
                    self.currentBadgeCounts = badgeCounts

                    // Update existing tab bar items
                    if let bar = self.tabBar, let items = bar.items {
                        for (index, item) in items.enumerated() {
                            if index < badgeCounts.count {
                                let count = badgeCounts[index]
                                if let count = count, count > 0 {
                                    item.badgeValue = count > 99 ? "99+" : String(count)
                                } else {
                                    item.badgeValue = nil
                                }
                            }
                        }
                    }
                    result(nil)
                } else {
                    result(FlutterError(code: "bad_args", message: "Missing badge counts", details: nil))
                }

            case "setBadges":
                if let args = call.arguments as? [String: Any],
                   let badges = args["badges"] as? [String] {
                    self.currentBadges = badges
                    if let bar = self.tabBar, let items = bar.items {
                        for (index, item) in items.enumerated() where index < badges.count {
                            item.badgeValue = badges[index].isEmpty ? nil : badges[index]
                        }
                    }
                    result(nil)
                } else {
                    result(FlutterError(code: "bad_args", message: "Missing badges", details: nil))
                }

            case "refresh", "setLabels", "setSfSymbols":
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // Rebuild tab items with current colors (called when style changes)
    private func rebuildItemsWithCurrentColors() {
        guard let bar = self.tabBar else { return }

        let currentSelectedIndex = bar.items?.firstIndex { $0 == bar.selectedItem } ?? 0

        // Rebuild items with new colors
        bar.items = buildTabItems()

        // Restore selection
        if let items = bar.items, currentSelectedIndex < items.count, currentSelectedIndex != searchItemIndex {
            bar.selectedItem = items[currentSelectedIndex]
        }
    }

    deinit {
        channel.setMethodCallHandler(nil)
        tabBar?.delegate = nil
        tabBar?.removeFromSuperview()
    }

    func view() -> UIView {
        return container
    }

    // MARK: - UITabBarDelegate

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        // Check if search item was tapped
        if item.tag == 9999 {
            // Don't restore previous selection - let search tab stay selected
            // This matches adaptive_platform_ui behavior
            // Notify Flutter search was activated
            channel.invokeMethod("searchActiveChanged", arguments: ["isActive": true])
            return
        }

        // Regular tab item
        if let items = tabBar.items, let index = items.firstIndex(of: item) {
            selectedIndex = index
            channel.invokeMethod("valueChanged", arguments: ["index": index])
        }
    }
}
