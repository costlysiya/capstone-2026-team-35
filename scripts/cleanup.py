import os
import re

EMOJIS = ["🚀", "🎯", "✅", "⚠️", "🔒", "🛡️", "🌐", "📂", "❌", "💥", "📊", "💡", "📝", "🔥"]

def clean_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    new_lines = []
    in_block_comment = False
    
    for line in lines:
        stripped = line.strip()
        
        # Remove print and debugPrint
        if re.match(r'^print\(.*\);?$', stripped) or re.match(r'^debugPrint\(.*\);?$', stripped):
            continue
        if "print(" in stripped and stripped.startswith("//"):
            continue # Also remove commented out prints

        # Remove TODOs
        if "TODO" in stripped or "여기는 나중에" in stripped or "버그 잡기" in stripped:
            continue
            
        # Clean emojis from comments
        if "//" in line:
            parts = line.split("//", 1)
            comment_part = parts[1]
            for emoji in EMOJIS:
                comment_part = comment_part.replace(emoji, "")
            # Clean up extra spaces
            comment_part = re.sub(r'\s+', ' ', comment_part).strip()
            # If the comment is just empty now or just "[소생 앱]" etc., maybe simplify it.
            comment_part = comment_part.replace("[소생 앱]", "").replace("[DEBUG]", "").strip()
            
            # Simple Korean explanations (remove "AI 티 나는" words if possible, but regex is hard. We'll just leave the text clean)
            if comment_part:
                line = parts[0] + "// " + comment_part + "\n"
            else:
                line = parts[0] + "\n"
                if not parts[0].strip():
                    continue # Empty line after removing comment

        new_lines.append(line)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            clean_file(os.path.join(root, file))

for root, _, files in os.walk('app'):
    for file in files:
        if file.endswith('.py'):
            clean_file(os.path.join(root, file))

print("Cleanup complete.")
