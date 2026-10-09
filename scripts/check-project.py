"""Check the specific native project contracts that cannot be compiled on Linux."""
from pathlib import Path
import hashlib
import re
import xml.etree.ElementTree as ET
root = Path(__file__).resolve().parent.parent
project = (root / 'WristMagic.xcodeproj/project.pbxproj').read_text()
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def record(name):
    match = re.search(r'^' + uid(name) + r' = (.*);$', project, re.M)
    assert match, f'Missing project object {name}'
    return match.group(1)
assert 'productType = "com.apple.product-type.application";' in record('WristMagicWatch')
assert 'watchapp2' not in project
for config in ['Debug', 'Release']:
    settings = record('WristMagicWatchTests' + config)
    assert 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/WristMagicWatch.app/WristMagicWatch";' in settings
    assert 'BUNDLE_LOADER = "$(TEST_HOST)";' in settings
assert uid('WristMagicWatchTestshostdependency') in record('WristMagicWatchTests')
assert 'target = ' + uid('WristMagicWatch') + ';' in record('WristMagicWatchTestshostdependency')
assert uid('WristMagicWatchTests') + ' = {TestTargetID = ' + uid('WristMagicWatch') in record('project')
scheme = ET.parse(root / 'WristMagic.xcodeproj/xcshareddata/xcschemes/WristMagic-WatchTests.xcscheme')
assert scheme.find('.//TestableReference/BuildableReference').attrib['BlueprintIdentifier'] == uid('WristMagicWatchTests')
print('Native project structural contracts passed (Apple compilation still required).')
