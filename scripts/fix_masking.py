import re

with open('lib/core/utils/masking_helper.dart', 'r') as f:
    content = f.read()

# Add import
content = content.replace("import 'package:soseang_app/core/utils/ner_classifier.dart';", "import 'package:soseang_app/core/utils/ner_classifier.dart';\nimport 'package:soseang_app/core/utils/crypto_helper.dart';")

# Fix mask functions
replacements = [
    (r"line\.replaceAllMapped\(rrnRegex, \(match\) => '******-\*\*\*\*\*\*\*'\);", r"line.replaceAllMapped(rrnRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"line\.replaceAllMapped\(cardRegex, \(match\) => _maskDigits\(match\.group\(0\)!\)\);", r"line.replaceAllMapped(cardRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"final maskedVal = '\*\*\*';", r"final maskedVal = CryptoHelper().encryptSensitive(cvcVal);"),
    (r"line\.replaceAllMapped\(couponRegex, \(match\) => _maskDigits\(match\.group\(0\)!\)\);", r"line.replaceAllMapped(couponRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"line\.replaceAllMapped\(accountRegex, \(match\) => _maskDigits\(match\.group\(0\)!\)\);", r"line.replaceAllMapped(accountRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"String maskedVal;\s*if \(val\.contains\('-'\)\) \{\s*final parts = val\.split\('-'\);\s*maskedVal = '010-\$\{\'\*\' \* parts\[1\]\.length\}-\$\{\'\*\' \* parts\[2\]\.length\}';\s*\} else \{\s*maskedVal = '010\$\{\'\*\' \* \(val\.length - 3\)\}';\s*\}", r"String maskedVal = CryptoHelper().encryptSensitive(val);"),
    (r"return '\$keyword\$separator\$\{\'\*\' \* resNum\.length\}';", r"final maskedVal = CryptoHelper().encryptSensitive(resNum);\n        return '$keyword$separator$maskedVal';"),
    (r"line\.replaceAllMapped\(passportDateRegex, \(match\) => _maskAll\(match\.group\(0\)!\)\);", r"line.replaceAllMapped(passportDateRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"line\.replaceAllMapped\(licenseRegex, \(match\) => _maskDigits\(match\.group\(0\)!\)\);", r"line.replaceAllMapped(licenseRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"line\.replaceAllMapped\(addressRegex, \(match\) => _maskAll\(match\.group\(0\)!\)\);", r"line.replaceAllMapped(addressRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"line\.replaceAllMapped\(idDateRegex, \(match\) => _maskDigits\(match\.group\(0\)!\)\);", r"line.replaceAllMapped(idDateRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"lines\[i\] = '\*' \* line\.length;", r"lines[i] = CryptoHelper().encryptSensitive(line);"),
    (r"return '\*' \* match\.group\(0\)!\.length;", r"return CryptoHelper().encryptSensitive(match.group(0)!);"),
    (r"lines\[i\] = lines\[i\]\.replaceAllMapped\(passportNoRegex, \(match\) => '\*' \* match\.group\(0\)!\.length\);", r"lines[i] = lines[i].replaceAllMapped(passportNoRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));"),
    (r"lines\[i\] = lines\[i\]\.replaceAllMapped\(standalone3DigitRegex, \(match\) => '\*\*\*'\);", r"lines[i] = lines[i].replaceAllMapped(standalone3DigitRegex, (match) => CryptoHelper().encryptSensitive(match.group(0)!));")
]

for old, new in replacements:
    content = re.sub(old, new, content)

# Fix unmask method
unmask_pattern = r"static String unmask\(String text, Map<String, dynamic>\? originalInfo\) \{[\s\S]*?return unmaskedText;\n  \}"
unmask_replacement = r"""static String unmask(String text, Map<String, dynamic>? originalInfo) {
    // 기존에는 originalInfo를 사용해 ***를 다시 텍스트로 치환했지만,
    // 이제는 종단간 암호화(E2EE) 방식이므로 CryptoHelper를 통해
    // 문자열 내의 [ENC:...] 패턴을 복호화하여 반환합니다.
    return CryptoHelper().decryptText(text);
  }"""

content = re.sub(unmask_pattern, unmask_replacement, content)

with open('lib/core/utils/masking_helper.dart', 'w') as f:
    f.write(content)
