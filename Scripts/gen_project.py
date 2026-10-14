# Generates FlacPlayer.xcodeproj/project.pbxproj
from pathlib import Path

def hid(prefix: str, n: int) -> str:
    value = f"{prefix}{n:022X}"
    assert len(value) == 24, (value, len(value))
    return value

sources = [
    ("App", "AppDelegate.swift"),
    ("App", "SceneDelegate.swift"),
    ("Model", "Models.swift"),
    ("Library", "LibraryStore.swift"),
    ("Library", "LibraryScanner.swift"),
    ("Library", "MetadataReader.swift"),
    ("Library", "Artwork.swift"),
    ("Audio", "PlaybackEngine.swift"),
    ("UI", "Theme.swift"),
    ("UI", "Haptics.swift"),
    ("UI", "ClickWheelView.swift"),
    ("UI", "VinylStageView.swift"),
    ("UI", "CoverFlowView.swift"),
    ("UI", "PlaybackChromeView.swift"),
    ("UI", "RootViewController.swift"),
]

file_refs = {}
build_files = {}
for index, (group, name) in enumerate(sources, start=1):
    file_refs[(group, name)] = hid("A1", index)
    build_files[(group, name)] = hid("B1", index)

info_ref = hid("A1", 40)
launch_ref = hid("A1", 41)
assets_ref = hid("A1", 42)
entitlements_ref = hid("A1", 43)
product_ref = hid("A1", 44)
launch_build = hid("B1", 41)
assets_build = hid("B1", 42)

groups = {
    "App": hid("C1", 1),
    "Model": hid("C1", 2),
    "Library": hid("C1", 3),
    "Audio": hid("C1", 4),
    "UI": hid("C1", 5),
    "FlacPlayer": hid("C1", 6),
    "Products": hid("C1", 7),
    "root": hid("C1", 8),
}

target = "D10000000000000000000001"
assert len(target) == 24
project = hid("E1", 1)
sources_phase = hid("F1", 1)
frameworks_phase = hid("F1", 2)
resources_phase = hid("F1", 3)
debug_project = hid("11", 1)
release_project = hid("11", 2)
project_list = hid("11", 3)
target_list = hid("11", 4)
debug_target = hid("11", 5)
release_target = hid("11", 6)

def pbx_list(items, indent=12):
    pad = " " * indent
    body = ",\n".join(f"{pad}{item}" for item in items)
    return "(\n" + body + ",\n" + (" " * (indent - 4)) + ")"

source_build_lines = [
    f"{build_files[key]} /* {key[1]} in Sources */" for key in file_refs
]
resource_build_lines = [
    f"{launch_build} /* LaunchScreen.storyboard in Resources */",
    f"{assets_build} /* Assets.xcassets in Resources */",
]

group_children = {name: [] for name in ("App", "Model", "Library", "Audio", "UI")}
for (group, name), ref in file_refs.items():
    group_children[group].append(f"{ref} /* {name} */")

file_ref_lines = []
for (group, name), ref in file_refs.items():
    file_ref_lines.append(
        f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
    )
file_ref_lines += [
    f"\t\t{info_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};",
    f"\t\t{launch_ref} /* LaunchScreen.storyboard */ = {{isa = PBXFileReference; lastKnownFileType = file.storyboard; path = LaunchScreen.storyboard; sourceTree = \"<group>\"; }};",
    f"\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};",
    f"\t\t{entitlements_ref} /* Jailbreak.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Jailbreak.entitlements; sourceTree = \"<group>\"; }};",
    f"\t\t{product_ref} /* FlacPlayer.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FlacPlayer.app; sourceTree = BUILT_PRODUCTS_DIR; }};",
]

build_file_lines = []
for (group, name), ref in build_files.items():
    build_file_lines.append(
        f"\t\t{ref} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[(group, name)]} /* {name} */; }};"
    )
build_file_lines += [
    f"\t\t{launch_build} /* LaunchScreen.storyboard in Resources */ = {{isa = PBXBuildFile; fileRef = {launch_ref} /* LaunchScreen.storyboard */; }};",
    f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};",
]

def group_block(gid, name, path, children):
    kids = pbx_list(children, 16)
    path_line = f"\n\t\t\tpath = {path};" if path else ""
    name_line = f"\n\t\t\tname = {name};" if name == "Products" else ""
    return f"""\t\t{gid} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = {kids};{name_line}{path_line}
\t\t\tsourceTree = "<group>";
\t\t}};"""

group_blocks = []
for name in ("App", "Model", "Library", "Audio", "UI"):
    group_blocks.append(group_block(groups[name], name, name, group_children[name]))

flac_children = [
    f"{groups['App']} /* App */",
    f"{groups['Model']} /* Model */",
    f"{groups['Library']} /* Library */",
    f"{groups['Audio']} /* Audio */",
    f"{groups['UI']} /* UI */",
    f"{info_ref} /* Info.plist */",
    f"{launch_ref} /* LaunchScreen.storyboard */",
    f"{assets_ref} /* Assets.xcassets */",
    f"{entitlements_ref} /* Jailbreak.entitlements */",
]
group_blocks.append(group_block(groups["FlacPlayer"], "FlacPlayer", "FlacPlayer", flac_children))
group_blocks.append(group_block(groups["Products"], "Products", None, [f"{product_ref} /* FlacPlayer.app */"]))

root_children = [
    f"{groups['FlacPlayer']} /* FlacPlayer */",
    f"{groups['Products']} /* Products */",
]
group_blocks.append(f"""\t\t{groups['root']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = {pbx_list(root_children, 16)};
\t\t\tsourceTree = "<group>";
\t\t}};""")

common_target = r"""
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = FlacPlayer/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 14.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				OTHER_LDFLAGS = (
					"$(inherited)",
					"-lsqlite3",
				);
				PRODUCT_BUNDLE_IDENTIFIER = local.flacplayer.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""

debug_project_settings = r"""
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				IPHONEOS_DEPLOYMENT_TARGET = 14.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
"""

release_project_settings = r"""
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 14.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
"""

text = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_lines)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_lines)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{chr(10).join(group_blocks)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target} /* FlacPlayer */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_list} /* Build configuration list for PBXNativeTarget "FlacPlayer" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = FlacPlayer;
\t\t\tproductName = FlacPlayer;
\t\t\tproductReference = {product_ref} /* FlacPlayer.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_list} /* Build configuration list for PBXProject "FlacPlayer" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {groups['root']};
\t\t\tproductRefGroup = {groups['Products']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target} /* FlacPlayer */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = {pbx_list(resource_build_lines, 16)};
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = {pbx_list(source_build_lines, 16)};
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{debug_project} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{debug_project_settings}\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_project} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{release_project_settings}\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{debug_target} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{common_target}\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_target} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{common_target}\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_list} /* Build configuration list for PBXProject "FlacPlayer" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_project} /* Debug */,
\t\t\t\t{release_project} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_list} /* Build configuration list for PBXNativeTarget "FlacPlayer" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_target} /* Debug */,
\t\t\t\t{release_target} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project} /* Project object */;
}}
"""

out = Path(__file__).resolve().parents[1] / "FlacPlayer.xcodeproj" / "project.pbxproj"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(text, encoding="utf-8", newline="\n")
print(out)
print("objects", text.count("isa = "))
