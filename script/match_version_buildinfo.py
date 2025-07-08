import json
import os
import re

version = str(os.environ['VERSION'])
match_version = ""

with open('build_info.json') as f:
    data = json.load(f)

# Sort keys: exact matches and specific wildcards first, general ones later
def specificity_score(key):
    if '*' not in key:
        return 0  # most specific
    elif key.strip() == '*':
        return 2  # least specific
    else:
        return 1  # mid-level

sorted_keys = sorted(data.keys(), key=specificity_score)

for key in sorted_keys:
    if not isinstance(data[key], dict):
        continue  # Skip non-version-specific keys like 'maintainer'

    subKeys = [subKey.strip() for subKey in key.split(',')]
    if version in subKeys:
        match_version = key
        break
    else:
        for subKey in subKeys:
            regex_str = '^' + subKey.replace(".", "\\.").replace("*", ".*") + '$'
            if re.match(regex_str, version):
                match_version = key
                break
    if len(match_version) != 0:
        break

print(match_version)
