#!/usr/bin/env python3
"""Deterministic app + keyboard project, with no host paths or signing material."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parent.parent
def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)

objects = {}
def add(name, body):
    key = ident(name)
    objects[key] = body
    return key
def listing(values):
    return "(" + ",".join(values) + ("," if values else "") + ")"
def settings(values):
    return "{" + "".join(str(k) + " = " + (listing([quoted(x) for x in v]) if isinstance(v, list) else quoted(v)) + ";" for k, v in values.items()) + "}"
def config_list(name, values, base=None):
    ids = []
    for mode in ["Debug", "Release"]:
        config = dict(values)
        config.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
                       "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if mode == "Debug" else ""})
        if mode == "Debug":
            config["DEBUG_INFORMATION_FORMAT"] = "dwarf"
        ids.append(add(name + mode, "isa = XCBuildConfiguration;" + ("baseConfigurationReference = " + base + ";" if base else "") + "buildSettings = " + settings(config) + "; name = " + mode + ";"))
    return add(name + "configs", "isa = XCConfigurationList; buildConfigurations = " + listing(ids) + "; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

files = sorted([p.relative_to(ROOT).as_posix() for folder in ["Core", "Shared", "App", "Keyboard"] for p in (ROOT / folder).glob("*.swift")])
resources = ["Assets.xcassets", "THIRD_PARTY_NOTICES.txt", "Config/PrivacyInfo.xcprivacy"]
references = {}
for file in files + resources + ["Config/Project.xcconfig", "Config/App-Info.plist", "Config/Keyboard-Info.plist", "Config/App.entitlements", "Config/Keyboard.entitlements"]:
    kind = "sourcecode.swift" if file.endswith(".swift") else "folder.assetcatalog" if file.endswith(".xcassets") else "text.xcconfig" if file.endswith(".xcconfig") else "text.plist.xml" if file.endswith((".plist", ".entitlements", ".xcprivacy")) else "text"
    references[file] = add("ref:" + file, "isa = PBXFileReference; lastKnownFileType = " + kind + "; path = " + quoted(file) + "; sourceTree = SOURCE_ROOT;")
package = add("azookey-package", 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/azooKey/AzooKeyKanaKanjiConverter"; requirement = { kind = exactVersion; version = 0.11.2; };')
product = add("azookey-product", "isa = XCSwiftPackageProductDependency; package = " + package + "; productName = KanaKanjiConverterModuleWithDefaultDictionary;")

products = {}
targets = {}
for name, display, kind in [("App", "こえのたね.app", "wrapper.application"), ("Keyboard", "VoiceSeedKeyboard.appex", "wrapper.app-extension")]:
    products[name] = add(name + "product", "isa = PBXFileReference; explicitFileType = " + kind + "; includeInIndex = 0; path = " + quoted(display) + "; sourceTree = BUILT_PRODUCTS_DIR;")
    targets[name] = ident(name + "target")
product_group = add("products-group", "isa = PBXGroup; name = Products; children = " + listing(list(products.values())) + '; sourceTree = "<group>";')
group = add("main-group", "isa = PBXGroup; children = " + listing(list(references.values()) + [product_group]) + '; sourceTree = "<group>";')
project_config = config_list("project", {
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "SWIFT_STRICT_CONCURRENCY": "targeted",
    "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
    "GENERATE_INFOPLIST_FILE": "NO", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
}, references["Config/Project.xcconfig"])

for target in ["App", "Keyboard"]:
    sources = [f for f in files if f.startswith(("Core/", "Shared/", target + "/"))]
    builds = [add(target + ":" + f, "isa = PBXBuildFile; fileRef = " + references[f] + ";") for f in sources]
    source_phase = add(target + "sources", "isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = " + listing(builds) + "; runOnlyForDeploymentPostprocessing = 0;")
    resource_builds = [add(target + ":resource:" + f, "isa = PBXBuildFile; fileRef = " + references[f] + ";") for f in resources if target == "App" or f.endswith(".txt")]
    resource_phase = add(target + "resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = " + listing(resource_builds) + "; runOnlyForDeploymentPostprocessing = 0;")
    package_build = [add("azookey-build", "isa = PBXBuildFile; productRef = " + product + ";")] if target == "Keyboard" else []
    frameworks_phase = add(target + "frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = " + listing(package_build) + "; runOnlyForDeploymentPostprocessing = 0;")
    phases = [source_phase, frameworks_phase, resource_phase]
    dependencies = []
    if target == "App":
        proxy = add("keyboard-proxy", "isa = PBXContainerItemProxy; containerPortal = " + ident("project") + "; proxyType = 1; remoteGlobalIDString = " + targets["Keyboard"] + "; remoteInfo = VoiceSeedKeyboard;")
        dependencies.append(add("keyboard-dependency", "isa = PBXTargetDependency; target = " + targets["Keyboard"] + "; targetProxy = " + proxy + ";"))
        embed = add("embed-keyboard-file", "isa = PBXBuildFile; fileRef = " + products["Keyboard"] + "; settings = { ATTRIBUTES = (RemoveHeadersOnCopy, CodeSignOnCopy,); };")
        phases.append(add("embed-keyboard", "isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"\"; dstSubfolderSpec = 13; files = (" + embed + ",); name = \"Embed App Extensions\"; runOnlyForDeploymentPostprocessing = 0;"))
    values = {"PRODUCT_BUNDLE_IDENTIFIER": "$(VOICE_SEED_BUNDLE_ID)" + (".keyboard" if target == "Keyboard" else ""),
              "PRODUCT_MODULE_NAME": "VoiceSeedApp" if target == "App" else "VoiceSeedKeyboard",
              "PRODUCT_NAME": "こえのたね" if target == "App" else "VoiceSeedKeyboard",
              "INFOPLIST_FILE": "Config/" + target + "-Info.plist", "CODE_SIGN_ENTITLEMENTS": "Config/" + target + ".entitlements",
              "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.1.0",
              "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]}
    if target == "App": values["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    else: values.update({"APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES"})
    configs = config_list(target, values)
    add(target + "target", "isa = PBXNativeTarget; buildConfigurationList = " + configs + "; buildPhases = " + listing(phases) + "; buildRules = (); dependencies = " + listing(dependencies) + "; name = " + ("VoiceSeed" if target == "App" else "VoiceSeedKeyboard") + "; productName = VoiceSeed; productReference = " + products[target] + "; productType = " + quoted("com.apple.product-type.application" if target == "App" else "com.apple.product-type.app-extension") + "; packageProductDependencies = " + listing([product] if target == "Keyboard" else []) + ";")

add("project", "isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; }; buildConfigurationList = " + project_config + "; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja,en,Base,); mainGroup = " + group + "; productRefGroup = " + product_group + "; projectDirPath = \"\"; projectRoot = \"\"; targets = " + listing(list(targets.values())) + "; packageReferences = (" + package + ",);")
text = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
text += "\n".join(key + " = { " + body + " };" for key, body in sorted(objects.items()))
text += "\n}; rootObject = " + ident("project") + "; }\n"
project = ROOT / "VoiceSeed.xcodeproj"
path = project / "project.pbxproj"
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets["App"]}" BuildableName="こえのたね.app" BlueprintName="VoiceSeed" ReferencedContainer="container:VoiceSeed.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets["App"]}" BuildableName="こえのたね.app" BlueprintName="VoiceSeed" ReferencedContainer="container:VoiceSeed.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_path = project / "xcshareddata/xcschemes/VoiceSeed-iOS.xcscheme"
if "--check" in sys.argv:
    if not path.is_file() or path.read_text() != text or not scheme_path.is_file() or scheme_path.read_text() != scheme:
        sys.exit("Generated iOS project is stale. Run python3 iOS/Scripts/generate-project.py.")
    print("iOS project inventory and shared scheme: OK")
else:
    path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text)
    scheme_path.parent.mkdir(parents=True, exist_ok=True); scheme_path.write_text(scheme)
    print("Generated iOS app + keyboard project")
