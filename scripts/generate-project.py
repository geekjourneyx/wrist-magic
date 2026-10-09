from pathlib import Path
import hashlib
from xml.sax.saxutils import escape
p=Path(__file__).resolve().parent.parent / 'WristMagic.xcodeproj'; p.mkdir(exist_ok=True)
objects={}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def obj(key, body): objects[uid(key)]=body; return uid(key)
def arr(items): return '('+','.join(items)+',)' if items else '()'
def val(d): return '{'+''.join(f'{k} = {v};' for k,v in d.items())+'}'
def q(s): return '"'+s+'"'
files={}
root=p.parent
paths=sorted(str(f.relative_to(root)) for folder in ['WristMagiciOS','WristMagicWatch','Shared','Tests'] for f in (root/folder).rglob('*') if f.is_file() and (f.suffix in ['.swift', '.metal'] or '/Resources/' in str(f)))
for path in paths: files[path]=obj(path,val(dict(isa='PBXFileReference',lastKnownFileType=('sourcecode.metal' if path.endswith('.metal') else 'sourcecode.swift' if path.endswith('.swift') else 'file'),path=q(path),sourceTree='SOURCE_ROOT')))
package=obj('package',val(dict(isa='XCLocalSwiftPackageReference',relativePath='Packages/WristMagicCore')))
targets=[]; products=[]
names=['WristMagiciOS','WristMagicWatch','WristMagiciOSTests','WristMagicWatchTests']
for name in names:
 watch='Watch' in name; test=name.endswith('Tests'); tid=uid(name); targets.append(tid)
 product=obj(name+'product',val(dict(isa='PBXFileReference',explicitFileType='wrapper.cfbundle' if test else 'wrapper.application',includeInIndex='0',path=q(name+('.xctest' if test else '.app')),sourceTree='BUILT_PRODUCTS_DIR'))); products.append(product)
 sourcepaths=[path for path in paths if (path.startswith('Tests/'+('Watch' if watch else 'iOS')+'/') or path.startswith('Tests/Fixtures/'))] if test else [path for path in paths if path.startswith(('WristMagicWatch/' if watch else 'WristMagiciOS/', 'Shared/'))]
 resourcepaths=[path for path in sourcepaths if '/Resources/' in path]
 sourcepaths=[path for path in sourcepaths if path.endswith(('.swift','.metal'))]
 builds=[obj(name+path,val(dict(isa='PBXBuildFile',fileRef=files[path]))) for path in sourcepaths]
 source=obj(name+'sources',val(dict(isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=arr(builds),runOnlyForDeploymentPostprocessing='0')))
 dep=obj(name+'core',val(dict(isa='XCSwiftPackageProductDependency',package=package,productName='WristMagicCore')))
 build=obj(name+'corebuild',val(dict(isa='PBXBuildFile',productRef=dep)))
 framework=obj(name+'frameworks',val(dict(isa='PBXFrameworksBuildPhase',buildActionMask='2147483647',files=arr([build]),runOnlyForDeploymentPostprocessing='0')))
 resources=obj(name+'resources',val(dict(isa='PBXResourcesBuildPhase',buildActionMask='2147483647',files=arr([obj(name+'resource'+path,val(dict(isa='PBXBuildFile',fileRef=files[path]))) for path in resourcepaths]),runOnlyForDeploymentPostprocessing='0')))
 phases=[source,framework,resources]; dependencies=[]
 if name=='WristMagiciOS':
  embed=obj('embedwatchfile',val(dict(isa='PBXBuildFile',fileRef=uid('WristMagicWatchproduct'),settings='{ATTRIBUTES = (RemoveHeadersOnCopy,);}')))
  phases.append(obj('embedwatch',val(dict(isa='PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath=q('$(CONTENTS_FOLDER_PATH)/Watch'),dstSubfolderSpec='16',files=arr([embed]),name=q('Embed Watch Content'),runOnlyForDeploymentPostprocessing='0'))))
  proxy=obj('watchproxy',val(dict(isa='PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=uid('WristMagicWatch'),remoteInfo='WristMagicWatch')))
  dependencies=[obj('watchdependency',val(dict(isa='PBXTargetDependency',target=uid('WristMagicWatch'),targetProxy=proxy)))]
 settings={'SWIFT_VERSION':'6.0','SDKROOT':'watchos' if watch else 'iphoneos','SUPPORTED_PLATFORMS':q('watchos watchsimulator' if watch else 'iphoneos iphonesimulator'),'TARGETED_DEVICE_FAMILY':q('4' if watch else '1'),'GENERATE_INFOPLIST_FILE':'YES','PRODUCT_NAME':q('$(TARGET_NAME)'),'PRODUCT_BUNDLE_IDENTIFIER':q('io.github.geekjourneyx.wristmagic'+('.watchkitapp' if watch else '')+('.tests' if test else '')),'CODE_SIGN_STYLE':'Automatic','WATCHOS_DEPLOYMENT_TARGET':'10.0' if watch else '10.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0'}
 if test:
  host = 'WristMagicWatch' if watch else 'WristMagiciOS'
  proxy = obj(name+'hostproxy',val(dict(isa='PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=uid(host),remoteInfo=host)))
  dependencies.append(obj(name+'hostdependency',val(dict(isa='PBXTargetDependency',target=uid(host),targetProxy=proxy))))
  settings.update({'TEST_HOST':q('$(BUILT_PRODUCTS_DIR)/'+host+'.app/'+host),'BUNDLE_LOADER':q('$(TEST_HOST)')})
 if not test:
  settings.update({'INFOPLIST_KEY_CFBundleDisplayName':q('腕术'),'MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'1'})
  if watch: settings.update({'INFOPLIST_KEY_WKApplication':'YES','INFOPLIST_KEY_WKCompanionAppBundleIdentifier':'io.github.geekjourneyx.wristmagic','INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp':'YES','SKIP_INSTALL':'YES','INFOPLIST_KEY_NSMotionUsageDescription':q('Wrist motion recognizes your spell gesture during practice and casting.')})
  else: settings.update({'INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait','INFOPLIST_KEY_NSCameraUsageDescription':q('Camera displays the real world stage and records spell clips.'),'INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription':q('Save your spell clip only when you tap Save.')})
 configs=[]
 for c in ['Debug','Release']:
  st=settings.copy(); st['SWIFT_OPTIMIZATION_LEVEL']=q('-Onone' if c=='Debug' else '-O')
  if c == 'Debug': st.update({'ONLY_ACTIVE_ARCH':'YES','ENABLE_TESTABILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':q('$(inherited) DEBUG')})
  configs.append(obj(name+c,val(dict(isa='XCBuildConfiguration',buildSettings=val(st),name=c))))
 cl=obj(name+'configs',val(dict(isa='XCConfigurationList',buildConfigurations=arr(configs),defaultConfigurationIsVisible='0',defaultConfigurationName='Release')))
 obj(name,val(dict(isa='PBXNativeTarget',buildConfigurationList=cl,buildPhases=arr(phases),buildRules='()',dependencies=arr(dependencies),name=name,packageProductDependencies=arr([dep]),productName=name,productReference=product,productType=q('com.apple.product-type.bundle.unit-test' if test else 'com.apple.product-type.application'))))
group=obj('products',val(dict(isa='PBXGroup',children=arr(products),name='Products',sourceTree=q('<group>'))))
main=obj('main',val(dict(isa='PBXGroup',children=arr(list(files.values())+[group]),sourceTree=q('<group>'))))
configs=[obj('project'+c,val(dict(isa='XCBuildConfiguration',buildSettings='{CLANG_ENABLE_MODULES = YES; SWIFT_STRICT_CONCURRENCY = complete;}',name=c))) for c in ['Debug','Release']]
cl=obj('projectconfigs',val(dict(isa='XCConfigurationList',buildConfigurations=arr(configs),defaultConfigurationIsVisible='0',defaultConfigurationName='Release')))
obj('project',val(dict(isa='PBXProject',attributes='{LastUpgradeCheck = 1600; TargetAttributes = {'+uid('WristMagicWatchTests')+' = {TestTargetID = '+uid('WristMagicWatch')+';};'+uid('WristMagiciOSTests')+' = {TestTargetID = '+uid('WristMagiciOS')+';};};}',buildConfigurationList=cl,compatibilityVersion=q('Xcode 14.0'),developmentRegion='en',hasScannedForEncodings='0',knownRegions='(en,Base,zh-Hans)',mainGroup=main,packageReferences=arr([package]),productRefGroup=group,projectDirPath=q(''),projectRoot=q(''),targets=arr(targets))))
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(f'{k} = {v};\n' for k,v in objects.items())+'}; rootObject = '+uid('project')+';}\n')
s=p/'xcshareddata/xcschemes';s.mkdir(parents=True,exist_ok=True)
for name in names:
 test=name.endswith('Tests'); app=name.removesuffix('Tests')
 def ref(n):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(n)}" BuildableName="{n}{".xctest" if n.endswith("Tests") else ".app"}" BlueprintName="{n}" ReferencedContainer="container:WristMagic.xcodeproj"/>'
 builds=[name] if not test else [app,name]
 xml='<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>'+''.join('<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">'+ref(n)+'</BuildActionEntry>' for n in builds)+'</BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'+ ('<TestableReference skipped="NO">'+ref(name)+'</TestableReference>' if test else '')+'</Testables></TestAction><LaunchAction buildConfiguration="Debug" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+ref(app)+'</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'
 scheme = {'WristMagiciOS':'WristMagic-iOS','WristMagicWatch':'WristMagic-Watch','WristMagiciOSTests':'WristMagic-iOSTests','WristMagicWatchTests':'WristMagic-WatchTests'}[name]
 (s/(scheme+'.xcscheme')).write_text(xml)
