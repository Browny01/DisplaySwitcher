#!/usr/bin/env python3
"""Generate DisplaySwitcher.xcodeproj/project.pbxproj deterministically."""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

APP_SOURCES = [
    "DisplaySwitcher/App/AppConstants.swift",
    "DisplaySwitcher/App/AppState.swift",
    "DisplaySwitcher/App/DisplaySwitcherApp.swift",
    "DisplaySwitcher/App/MenuBarCoordinator.swift",
    "DisplaySwitcher/App/SettingsWindowPresenter.swift",
    "DisplaySwitcher/Models/DisplayInfo.swift",
    "DisplaySwitcher/Models/DisplayPreset.swift",
    "DisplaySwitcher/Models/AppSettings.swift",
    "DisplaySwitcher/Services/DisplayDiscovery.swift",
    "DisplaySwitcher/Services/DisplayMatcher.swift",
    "DisplaySwitcher/Services/DisplayConfigurationService.swift",
    "DisplaySwitcher/Services/DisplayManager.swift",
    "DisplaySwitcher/Services/PresetManager.swift",
    "DisplaySwitcher/Services/ShortcutManager.swift",
    "DisplaySwitcher/Services/LoginItemManager.swift",
    "DisplaySwitcher/Services/NotificationService.swift",
    "DisplaySwitcher/Services/DisplayChangeObserver.swift",
    "DisplaySwitcher/Utilities/AppLogger.swift",
    "DisplaySwitcher/Utilities/CoordinateUtilities.swift",
    "DisplaySwitcher/Utilities/KeyboardShortcut.swift",
    "DisplaySwitcher/Views/Settings/SettingsView.swift",
    "DisplaySwitcher/Views/Settings/PresetsSettingsView.swift",
    "DisplaySwitcher/Views/Settings/DisplaysSettingsView.swift",
    "DisplaySwitcher/Views/Settings/GeneralSettingsView.swift",
    "DisplaySwitcher/Views/Settings/ShortcutsSettingsView.swift",
    "DisplaySwitcher/Views/Components/LayoutPreviewView.swift",
]


def gid(*parts):
    h = hashlib.sha256("|".join(parts).encode()).hexdigest()[:24].upper()
    return h


def main():
    for f in APP_SOURCES:
        assert os.path.exists(os.path.join(ROOT, f)), f"missing source: {f}"

    build_files = []   # (id, fileref_id)
    file_refs = []     # (id, path, filetype)
    src_app = []
    res_app = []

    for path in APP_SOURCES:
        fr = gid("fr", path)
        bf = gid("bf-app", path)
        file_refs.append((fr, path, "sourcecode.swift"))
        build_files.append((bf, fr))
        src_app.append(bf)

    # Asset catalog (accent colour)
    assets_path = "DisplaySwitcher/Resources/Assets.xcassets"
    assets_fr = gid("fr", assets_path)
    assets_bf = gid("bf-app", assets_path)
    file_refs.append((assets_fr, assets_path, "folder.assetcatalog"))
    build_files.append((assets_bf, assets_fr))
    res_app.append(assets_bf)

    # App icon (.icns) copied verbatim; Info.plist points to it via
    # CFBundleIconFile, so the Finder/Dock always show the branded blue icon.
    icns_path = "DisplaySwitcher/Resources/AppIcon.icns"
    icns_fr = gid("fr", icns_path)
    icns_bf = gid("bf-app", icns_path)
    file_refs.append((icns_fr, icns_path, "image.icns"))
    build_files.append((icns_bf, icns_fr))
    res_app.append(icns_bf)

    # Products
    app_product_fr = gid("fr", "product-app")
    file_refs.append((app_product_fr, "DisplaySwitcher.app", "wrapper.application"))

    # Groups
    g_main = gid("g", "main")
    g_app = gid("g", "appdir")
    g_products = gid("g", "products")

    def group_children(prefix):
        return [gid("fr", p) for p in APP_SOURCES
                if p.startswith(prefix)] + (
                    [assets_fr, icns_fr] if prefix == "DisplaySwitcher/Resources/" else [])

    subgroups = {}
    for name in ["DisplaySwitcher/App/", "DisplaySwitcher/Models/",
                 "DisplaySwitcher/Services/", "DisplaySwitcher/Utilities/",
                 "DisplaySwitcher/Views/", "DisplaySwitcher/Resources/"]:
        subgroups[name] = gid("g", name)

    L = []
    L.append("// !$*UTF8*$!")
    L.append("{")
    L.append("\tarchiveVersion = 1;")
    L.append("\tclasses = {")
    L.append("\t};")
    L.append("\tobjectVersion = 77;")
    L.append("\tobjects = {")

    # PBXBuildFile
    for bf, fr in build_files:
        L.append(f"\t\t{bf} = {{isa = PBXBuildFile; fileRef = {fr}; }};")
    # PBXFileReference
    for fr, path, ftype in file_refs:
        name = os.path.basename(path)
        if ftype == "sourcecode.swift":
            L.append(f'\t\t{fr} = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = "{name}"; path = "{path}"; sourceTree = "<group>"; }};')
        elif ftype == "folder.assetcatalog":
            L.append(f'\t\t{fr} = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = Assets.xcassets; path = "{path}"; sourceTree = "<group>"; }};')
        elif ftype == "image.icns":
            L.append(f'\t\t{fr} = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = AppIcon.icns; path = "{path}"; sourceTree = "<group>"; }};')
        else:
            L.append(f'\t\t{fr} = {{isa = PBXFileReference; explicitFileType = {ftype}; includeInIndex = 0; path = "{name}"; sourceTree = BUILT_PRODUCTS_DIR; }};')

    # Frameworks phase (empty; Swift auto-links system frameworks)
    fw_app = gid("fw", "app")
    L.append(f"\t\t{fw_app} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")

    # Groups
    L.append(f"\t\t{g_main} = {{isa = PBXGroup; children = ({g_app}, {g_products}); sourceTree = \"<group>\"; }};")
    L.append(f"\t\t{g_app} = {{isa = PBXGroup; children = ({', '.join(subgroups.values())}); name = DisplaySwitcher; sourceTree = \"<group>\"; }};")
    for name, g in subgroups.items():
        kids = group_children(name)
        short = {"DisplaySwitcher/App/": "App", "DisplaySwitcher/Models/": "Models",
                 "DisplaySwitcher/Services/": "Services", "DisplaySwitcher/Utilities/": "Utilities",
                 "DisplaySwitcher/Views/": "Views", "DisplaySwitcher/Resources/": "Resources"}[name]
        L.append(f"\t\t{g} = {{isa = PBXGroup; children = ({', '.join(kids)}); name = {short}; sourceTree = \"<group>\"; }};")
    L.append(f"\t\t{g_products} = {{isa = PBXGroup; children = ({app_product_fr}); name = Products; sourceTree = \"<group>\"; }};")

    # Target & phases
    t_app = gid("t", "app")
    s_app = gid("s", "app")
    r_app = gid("r", "app")
    L.append(f"\t\t{s_app} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({', '.join(src_app)}); runOnlyForDeploymentPostprocessing = 0; }};")
    L.append(f"\t\t{r_app} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({', '.join(res_app)}); runOnlyForDeploymentPostprocessing = 0; }};")
    L.append(f"\t\t{t_app} = {{isa = PBXNativeTarget; buildConfigurationList = {gid('cl', 'app')}; buildPhases = ({s_app}, {fw_app}, {r_app}); buildRules = (); dependencies = (); name = DisplaySwitcher; productName = DisplaySwitcher; productReference = {app_product_fr}; productType = \"com.apple.product-type.application\"; }};")

    # Project
    proj = gid("proj")
    L.append(f"\t\t{proj} = {{isa = PBXProject; buildConfigurationList = {gid('cl', 'proj')}; compatibilityVersion = \"Xcode 15.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en); mainGroup = {g_main}; productRefGroup = {g_products}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({t_app}); }};")

    # Configurations
    def xcconfig(gidname, name, settings):
        lines = [f"\t\t{gidname} = {{isa = XCBuildConfiguration; buildSettings = {{"]
        for k, v in settings.items():
            lines.append(f"\t\t\t{k} = {v};")
        lines.append(f"\t\t}}; name = {name}; }};")
        return lines

    proj_common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
        "COPY_PHASE_STRIP": "NO",
        "CURRENT_PROJECT_VERSION": "1",
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "MARKETING_VERSION": "1.0",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": "macosx",
        "SWIFT_VERSION": "5.0",
    }
    for cfg in ["Debug", "Release"]:
        s = dict(proj_common)
        if cfg == "Debug":
            s.update({"GCC_OPTIMIZATION_LEVEL": "0", "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
                      "ENABLE_TESTABILITY": "YES", "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)")'})
        else:
            s.update({"SWIFT_OPTIMIZATION_LEVEL": '"-O"', "ENABLE_TESTABILITY": "NO"})
        L.extend(xcconfig(gid("cfg-proj", cfg), cfg, s))

    app_common = {
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_IDENTITY": '"-"',
        "CODE_SIGN_STYLE": "Manual",
        "COMBINE_HIDPI_IMAGES": "YES",
        "DEVELOPMENT_TEAM": '""',
        "INFOPLIST_FILE": '"DisplaySwitcher/Info.plist"',
        "PRODUCT_BUNDLE_IDENTIFIER": "com.displayswitcher.DisplaySwitcher",
        "PRODUCT_NAME": '"DisplaySwitcher"',
    }
    for cfg in ["Debug", "Release"]:
        L.extend(xcconfig(gid("cfg-app", cfg), cfg, app_common))

    for clid, cfgs in [(gid("cl", "proj"), ["cfg-proj", "Debug", "cfg-proj", "Release"]),
                       (gid("cl", "app"), ["cfg-app", "Debug", "cfg-app", "Release"])]:
        L.append(f"\t\t{clid} = {{isa = XCConfigurationList; buildConfigurations = ({gid(cfgs[0], cfgs[1])}, {gid(cfgs[2], cfgs[3])}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")

    L.append("\t};")
    L.append(f"\trootObject = {proj};")
    L.append("}")

    outdir = os.path.join(ROOT, "DisplaySwitcher.xcodeproj")
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "project.pbxproj"), "w") as f:
        f.write("\n".join(L) + "\n")
    print("Wrote DisplaySwitcher.xcodeproj/project.pbxproj")


if __name__ == "__main__":
    main()