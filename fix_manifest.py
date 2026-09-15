import re

with open('android/app/src/main/AndroidManifest.xml', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'android:name="${applicationName}"',
    'android:name="${applicationName}"\n        android:usesCleartextTraffic="true"'
)

with open('android/app/src/main/AndroidManifest.xml', 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
