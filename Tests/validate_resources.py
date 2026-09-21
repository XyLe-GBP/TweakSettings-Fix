from pathlib import Path
import json
import plistlib
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
for folder in ('Resources', 'TweakSettings-App', 'TweakSettings-Utility'):
    for path in (root / folder).rglob('*.plist'):
        plistlib.loads(path.read_bytes())
for path in (root / 'TweakSettings-App').rglob('Contents.json'):
    json.loads(path.read_text())
for path in (root / 'TweakSettings-App').rglob('*.storyboard'):
    ET.parse(path)
subprocess.run(['plutil', '-lint', str(root / 'TweakSettings.xcodeproj/project.pbxproj'),
                str(root / 'TweakSettings-App/en.lproj/Localizable.strings')], check=True)
print('Resource and package-script validation: passed')
