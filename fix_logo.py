import re

path = r"c:\FlutterProjects\quanlyshop\lib\views\shop_settings_view.dart"
with open(path, encoding="utf-8") as f:
    content = f.read()

# Find the correct upload block - starts after the uploadMultipleImages call
# The corruption is: after `if (urls.isNotEmpty) { logoUrl = urls.first;`
# there's a duplicate nested block instead of `} else {`

# We'll replace the entire upload logo section using line-based approach
lines = content.splitlines(keepends=True)

# Find the line with the corrupt pattern
corrupt_start = None
corrupt_end = None
for i, line in enumerate(lines):
    if '              if (_selectedLogo != null) {' in line:
        corrupt_start = i - 1  # The line before (with `logoUrl = urls.first;`)
        break

if corrupt_start is None:
    print("ERROR: Could not find corrupt start")
    exit(1)

print(f"Found corrupt block starting at line {corrupt_start + 1}")

# Find the end: look for `      // Update shop data` after the corrupt start
for i in range(corrupt_start, len(lines)):
    if '      // Update shop data' in lines[i]:
        corrupt_end = i
        break

if corrupt_end is None:
    print("ERROR: Could not find end marker")
    exit(1)

print(f"Found end marker at line {corrupt_end + 1}")

# The correct block to replace lines[corrupt_start..corrupt_end]
correct_block = [
    "        if (urls.isNotEmpty) {\n",
    "          logoUrl = urls.first;\n",
    "        } else {\n",
    "          final denied = StorageService.lastUploadPermissionDenied ||\n",
    "              (StorageService.lastUploadErrorMessage ?? '').toLowerCase().contains('unauthorized') ||\n",
    "              (StorageService.lastUploadErrorMessage ?? '').toLowerCase().contains('permission');\n",
    "          if (mounted) {\n",
    "            NotificationService.showSnackBar(\n",
    "              denied\n",
    "                  ? '\u0027Kh\u00f4ng c\u00f3 quy\u1ec1n t\u1ea3i logo l\u00ean (l\u1ed7i 403). Ki\u1ec3m tra c\u1ea5u h\u00ecnh App Check/Storage Firebase.\u0027'\n",
    "                  : '\u0027T\u1ea3i logo th\u1ea5t b\u1ea1i. Vui l\u00f2ng ki\u1ec3m tra k\u1ebft n\u1ed1i m\u1ea1ng v\u00e0 th\u1eed l\u1ea1i.\u0027'\n",
    "              color: Colors.red,\n",
    "              duration: const Duration(seconds: 6),\n",
    "            );\n",
    "          }\n",
    "        }\n",
    "      }\n",
    "\n",
]

# Actually, let's do it cleanly with proper Vietnamese strings
correct_block = \
        "        if (urls.isNotEmpty) {\n" \
        "          logoUrl = urls.first;\n" \
        "        } else {\n" \
        "          final denied = StorageService.lastUploadPermissionDenied ||\n" \
        "              (StorageService.lastUploadErrorMessage ?? '').toLowerCase().contains('unauthorized') ||\n" \
        "              (StorageService.lastUploadErrorMessage ?? '').toLowerCase().contains('permission');\n" \
        "          if (mounted) {\n" \
        "            NotificationService.showSnackBar(\n" \
        "              denied\n" \
        "                  ? 'Kh\u00f4ng c\u00f3 quy\u1ec1n t\u1ea3i logo l\u00ean (l\u1ed7i 403). Ki\u1ec3m tra c\u1ea5u h\u00ecnh App Check/Storage Firebase.'\n" \
        "                  : 'T\u1ea3i logo th\u1ea5t b\u1ea1i. Vui l\u00f2ng ki\u1ec3m tra k\u1ebft n\u1ed1i m\u1ea1ng v\u00e0 th\u1eed l\u1ea1i.',\n" \
        "              color: Colors.red,\n" \
        "              duration: const Duration(seconds: 6),\n" \
        "            );\n" \
        "          }\n" \
        "        }\n" \
        "      }\n" \
        "\n"

new_lines = lines[:corrupt_start] + [correct_block] + lines[corrupt_end:]
result = "".join(new_lines)

with open(path, "w", encoding="utf-8") as f:
    f.write(result)

print(f"DONE. Lines: {len(new_lines)}")
print("Verify:")
# Print lines around the fixed section
new_lines2 = result.splitlines()
for i in range(corrupt_start - 2, corrupt_start + 25):
    if 0 <= i < len(new_lines2):
        print(f"{i+1}: {new_lines2[i]}")
