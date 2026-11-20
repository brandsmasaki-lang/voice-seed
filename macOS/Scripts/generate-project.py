#!/usr/bin/env python3
"""Generate the sandboxed Mac App Store target; keep the direct build separate."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
objects = {}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quoted(value): return json.dumps(value, ensure_ascii=False)
def listing(values): return "(" + ",".join(values) + ",)" if values else "()"
def add(name, body):
    key = ident(name); objects[key] = body; return key
def configurations(name, values):
    entries = []
    for mode in ("Debug", "Release"):
        settings = {**values, "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "APP_STORE DEBUG" if mode == "Debug" else "APP_STORE"}
        body = "".join(k + " = " + quoted(v) + ";" for k, v in settings.items())
        entries.append(add(name + mode, f"isa = XCBuildConfiguration; buildSettings = {{{body}}}; name = {mode};"))
    return add(name + "configs", "isa = XCConfigurationList; buildConfigurations = " + listing(entries) + "; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

sources = ["../Sources/" + p.name for p in sorted((root.parent / "Sources").glob("*.swift"))
           if p.name not in ("ApplicationInstallService.swift", "ApplicationInstallCoordinator.swift")]
resources = ["../Resources/AppIcon.icns", "../Resources/PublicAppInfo.json", "../Resources/SparkleLicense.txt",
             "../THIRD_PARTY_NOTICES.md", "../LICENSE", "PRIVACY.md", "Config/PrivacyInfo.xcprivacy"]
refs = {}
for path in sources + resources:
    kind = "sourcecode.swift" if path.endswith(".swift") else "text.plist.xml" if path.endswith(".xcprivacy") else "file.icns" if path.endswith(".icns") else "text"
    refs[path] = add("ref" + path, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;")
product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "こえのたね.app"; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", 'isa = PBXGroup; name = Products; children = ' + listing([product]) + '; sourceTree = "<group>";')
group = add("group", 'isa = PBXGroup; children = ' + listing(list(refs.values()) + [products]) + '; sourceTree = "<group>";')
phases = []
for name, kind, paths in [("sources", "PBXSourcesBuildPhase", sources), ("resources", "PBXResourcesBuildPhase", resources)]:
    files = [add("build" + path, f"isa = PBXBuildFile; fileRef = {refs[path]};") for path in paths]
    phases.append(add(name, f"isa = {kind}; buildActionMask = 2147483647; files = {listing(files)}; runOnlyForDeploymentPostprocessing = 0;"))
phases.append(add("frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;"))
config = configurations("project", {"SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "26.0", "ARCHS": "arm64",
    "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "targeted", "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": "NRX77TLPW7", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_HARDENED_RUNTIME": "YES"})
target_config = configurations("target", {"PRODUCT_NAME": "こえのたね", "EXECUTABLE_NAME": "VoiceSeed", "PRODUCT_MODULE_NAME": "VoiceSeedStore",
    "PRODUCT_BUNDLE_IDENTIFIER": "jp.ainotane.koenotane.ios", "INFOPLIST_FILE": "Config/App-Info.plist",
    "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_ENTITLEMENTS": "Config/App.entitlements",
    "CURRENT_PROJECT_VERSION": "21", "MARKETING_VERSION": "0.7.7", "COMBINE_HIDPI_IMAGES": "YES"})
target = add("target", f"isa = PBXNativeTarget; buildConfigurationList = {target_config}; buildPhases = {listing(phases)}; buildRules = (); dependencies = (); name = VoiceSeed-Mac-AppStore; productName = VoiceSeed; productReference = {product}; productType = \"com.apple.product-type.application\";")
project = add("project", f"isa = PBXProject; attributes = {{LastUpgradeCheck = 2700;}}; buildConfigurationList = {config}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = ja; knownRegions = (ja,en,Base,); mainGroup = {group}; productRefGroup = {products}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({target},);")
text = "// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
text += "\n".join(k + " = {" + v + "};" for k, v in sorted(objects.items()))
text += "\n}; rootObject = " + project + ";}\n"
directory = root / "VoiceSeedStore.xcodeproj"
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="こえのたね.app" BlueprintName="VoiceSeed-Mac-AppStore" ReferencedContainer="container:VoiceSeedStore.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="こえのたね.app" BlueprintName="VoiceSeed-Mac-AppStore" ReferencedContainer="container:VoiceSeedStore.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"/>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
paths = {directory / "project.pbxproj": text, directory / "xcshareddata/xcschemes/VoiceSeed-Mac-AppStore.xcscheme": scheme}
for path, value in paths.items():
    if "--check" in sys.argv:
        if not path.is_file() or path.read_text() != value: raise SystemExit("Mac App Store project is stale: " + str(path))
    else:
        path.parent.mkdir(parents=True, exist_ok=True); path.write_text(value)
print("Mac App Store project inventory: OK")
