#!/usr/bin/env python3
"""Generate a minimal Xcode project that depends on the local QueueCore package."""

from __future__ import annotations

import os
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_NAME = "Queue"
BUNDLE_ID = "com.queueapp.Queue"
DEPLOYMENT = "17.0"


def xid() -> str:
    return uuid.uuid4().hex[:24].upper()


def collect_files(base: Path, exts: set[str]) -> list[Path]:
    files: list[Path] = []
    for path in sorted(base.rglob("*")):
        if path.is_file() and path.suffix in exts:
            files.append(path)
    return files


def main() -> None:
    app_sources = collect_files(ROOT / "Queue", {".swift"})
    test_sources = collect_files(ROOT / "QueueTests", {".swift"})
    assets = ROOT / "Queue" / "Resources" / "Assets.xcassets"
    info_plist = ROOT / "Queue" / "Resources" / "Info.plist"

    project_id = xid()
    main_group = xid()
    products_group = xid()
    queue_group = xid()
    tests_group = xid()
    packages_group = xid()
    app_target = xid()
    test_target = xid()
    app_product = xid()
    test_product = xid()
    sources_phase_app = xid()
    sources_phase_test = xid()
    resources_phase = xid()
    frameworks_phase_app = xid()
    frameworks_phase_test = xid()
    target_dep = xid()
    container_proxy = xid()
    project_config_list = xid()
    app_config_list = xid()
    test_config_list = xid()
    project_debug = xid()
    project_release = xid()
    app_debug = xid()
    app_release = xid()
    test_debug = xid()
    test_release = xid()
    package_ref = xid()
    package_product_dep_app = xid()
    package_product_dep_test = xid()
    assets_ref = xid()
    assets_build = xid()

    file_refs: dict[Path, str] = {}
    build_files_app: dict[Path, str] = {}
    build_files_test: dict[Path, str] = {}

    for path in app_sources:
        file_refs[path] = xid()
        build_files_app[path] = xid()
    for path in test_sources:
        file_refs[path] = xid()
        build_files_test[path] = xid()

    lines: list[str] = []
    w = lines.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")

    # PBXBuildFile
    for path, bid in build_files_app.items():
        w(f"\t\t{bid} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {path.name} */; }};")
    for path, bid in build_files_test.items():
        w(f"\t\t{bid} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {path.name} */; }};")
    w(f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};")
    w(f"\t\t{package_product_dep_app} /* QueueCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {xid()} /* QueueCore */; }};")

    # Keep stable product refs
    product_ref_app = xid()
    product_ref_test = xid()
    # rewrite last package product build file with known ids
    lines[-1] = (
        f"\t\t{package_product_dep_app} /* QueueCore in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {product_ref_app} /* QueueCore */; }};"
    )
    w(
        f"\t\t{package_product_dep_test} /* QueueCore in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {product_ref_test} /* QueueCore */; }};"
    )

    # PBXFileReference
    w(f"\t\t{app_product} /* Queue.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Queue.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    w(f"\t\t{test_product} /* QueueTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = QueueTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    w(
        f"\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; "
        f"name = Assets.xcassets; path = Queue/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT; }};"
    )
    for path, ref in file_refs.items():
        rel = path.relative_to(ROOT)
        w(
            f"\t\t{ref} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"name = {path.name}; path = {rel.as_posix()}; sourceTree = SOURCE_ROOT; }};"
        )

    # Groups
    app_children = [file_refs[p] for p in app_sources] + [assets_ref]
    test_children = [file_refs[p] for p in test_sources]
    w(f"\t\t{main_group} = {{")
    w("\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = ({queue_group}, {tests_group}, {packages_group}, {products_group});")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{products_group} /* Products */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = ({app_product}, {test_product});")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{queue_group} /* Queue */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = ({', '.join(app_children)});")
    w("\t\t\tname = Queue;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{tests_group} /* QueueTests */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = ({', '.join(test_children)});")
    w("\t\t\tname = QueueTests;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{packages_group} /* Packages */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = ();")
    w("\t\t\tname = Packages;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    # Sources build phases
    w(f"\t\t{sources_phase_app} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = ({', '.join(build_files_app.values())});")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w(f"\t\t{sources_phase_test} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = ({', '.join(build_files_test.values())});")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w(f"\t\t{resources_phase} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = ({assets_build});")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w(f"\t\t{frameworks_phase_app} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = ({package_product_dep_app});")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w(f"\t\t{frameworks_phase_test} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = ({package_product_dep_test});")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")

    # Targets
    w(f"\t\t{app_target} /* Queue */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"Queue\" */;" % app_config_list)
    w(f"\t\t\tbuildPhases = ({sources_phase_app}, {frameworks_phase_app}, {resources_phase});")
    w("\t\t\tbuildRules = ();")
    w("\t\t\tdependencies = ();")
    w("\t\t\tname = Queue;")
    w(f"\t\t\tpackageProductDependencies = ({product_ref_app});")
    w("\t\t\tproductName = Queue;")
    w(f"\t\t\tproductReference = {app_product} /* Queue.app */;")
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")

    w(f"\t\t{test_target} /* QueueTests */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"QueueTests\" */;" % test_config_list)
    w(f"\t\t\tbuildPhases = ({sources_phase_test}, {frameworks_phase_test});")
    w("\t\t\tbuildRules = ();")
    w(f"\t\t\tdependencies = ({target_dep});")
    w("\t\t\tname = QueueTests;")
    w(f"\t\t\tpackageProductDependencies = ({product_ref_test});")
    w("\t\t\tproductName = QueueTests;")
    w(f"\t\t\tproductReference = {test_product} /* QueueTests.xctest */;")
    w("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    w("\t\t};")

    w(f"\t\t{target_dep} /* PBXTargetDependency */ = {{")
    w("\t\t\tisa = PBXTargetDependency;")
    w(f"\t\t\ttarget = {app_target} /* Queue */;")
    w(f"\t\t\ttargetProxy = {container_proxy} /* PBXContainerItemProxy */;")
    w("\t\t};")
    w(f"\t\t{container_proxy} /* PBXContainerItemProxy */ = {{")
    w("\t\t\tisa = PBXContainerItemProxy;")
    w(f"\t\t\tcontainerPortal = {project_id} /* Project object */;")
    w("\t\t\tproxyType = 1;")
    w(f"\t\t\tremoteGlobalIDString = {app_target};")
    w("\t\t\tremoteInfo = Queue;")
    w("\t\t};")

    # Project
    w(f"\t\t{project_id} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    w("\t\t\t\tLastUpgradeCheck = 1500;")
    w("\t\t\t};")
    w(f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"Queue\" */;")
    w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (en, Base);")
    w(f"\t\t\tmainGroup = {main_group};")
    w(f"\t\t\tpackageReferences = ({package_ref});")
    w(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w(f"\t\t\ttargets = ({app_target}, {test_target});")
    w("\t\t};")

    w(f"\t\t{package_ref} /* XCLocalSwiftPackageReference \".\" */ = {{")
    w("\t\t\tisa = XCLocalSwiftPackageReference;")
    w("\t\t\trelativePath = .;")
    w("\t\t};")
    w(f"\t\t{product_ref_app} /* QueueCore */ = {{")
    w("\t\t\tisa = XCSwiftPackageProductDependency;")
    w(f"\t\t\tpackage = {package_ref} /* XCLocalSwiftPackageReference \".\" */;")
    w("\t\t\tproductName = QueueCore;")
    w("\t\t};")
    w(f"\t\t{product_ref_test} /* QueueCore */ = {{")
    w("\t\t\tisa = XCSwiftPackageProductDependency;")
    w(f"\t\t\tpackage = {package_ref} /* XCLocalSwiftPackageReference \".\" */;")
    w("\t\t\tproductName = QueueCore;")
    w("\t\t};")

    def config(cid: str, name: str, extra: dict[str, str]) -> None:
        w(f"\t\t{cid} /* {name} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for key, value in extra.items():
            w(f"\t\t\t\t{key} = {value};")
        w("\t\t\t};")
        w(f"\t\t\tname = {name};")
        w("\t\t};")

    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1"',
    }
    debug = {
        **common,
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    }
    release = {
        **common,
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    }
    config(project_debug, "Debug", debug)
    config(project_release, "Release", release)

    app_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Queue/Resources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "MARKETING_VERSION": "0.1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SUPPORTS_MACCATALYST": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": '"1"',
    }
    config(app_debug, "Debug", {**app_settings, "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'})
    config(app_release, "Release", app_settings)

    test_settings = {
        "BUNDLE_LOADER": '"$(TEST_HOST)"',
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MARKETING_VERSION": "0.1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.queueapp.QueueTests",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "TARGETED_DEVICE_FAMILY": '"1"',
        "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/Queue.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Queue"',
    }
    config(test_debug, "Debug", test_settings)
    config(test_release, "Release", test_settings)

    def config_list(cid: str, debug_id: str, release_id: str, title: str) -> None:
        w(f"\t\t{cid} /* Build configuration list for {title} */ = {{")
        w("\t\t\tisa = XCConfigurationList;")
        w(f"\t\t\tbuildConfigurations = ({debug_id}, {release_id});")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")

    config_list(project_config_list, project_debug, project_release, 'PBXProject "Queue"')
    config_list(app_config_list, app_debug, app_release, 'PBXNativeTarget "Queue"')
    config_list(test_config_list, test_debug, test_release, 'PBXNativeTarget "QueueTests"')

    w("\t};")
    w(f"\trootObject = {project_id} /* Project object */;")
    w("}")

    out_dir = ROOT / f"{PROJECT_NAME}.xcodeproj"
    out_dir.mkdir(exist_ok=True)
    (out_dir / "project.pbxproj").write_text("\n".join(lines) + "\n", encoding="utf-8")

    scheme_dir = out_dir / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "Queue.app" BlueprintName = "Queue" ReferencedContainer = "container:Queue.xcodeproj" />
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{test_target}" BuildableName = "QueueTests.xctest" BlueprintName = "QueueTests" ReferencedContainer = "container:Queue.xcodeproj" />
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "Queue.app" BlueprintName = "Queue" ReferencedContainer = "container:Queue.xcodeproj" />
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "Queue.app" BlueprintName = "Queue" ReferencedContainer = "container:Queue.xcodeproj" />
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug" />
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES" />
</Scheme>
"""
    (scheme_dir / "Queue.xcscheme").write_text(scheme, encoding="utf-8")
    print(f"Wrote {out_dir}")


if __name__ == "__main__":
    main()
