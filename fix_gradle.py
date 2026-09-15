import re

with open('android/app/build.gradle.kts', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'signingConfig = signingConfigs.getByName("debug")',
    'signingConfig = signingConfigs.getByName("debug")\n            isMinifyEnabled = false\n            isShrinkResources = false'
)

with open('android/app/build.gradle.kts', 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
