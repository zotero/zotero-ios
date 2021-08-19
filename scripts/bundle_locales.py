import json
import os
import re
import shutil
import subprocess
import time

# Get bundle directory
bundle_dir = os.path.join(os.path.abspath("."), "Bundled" + os.sep + "locales")

if not os.path.isdir(bundle_dir):
    os.mkdir(bundle_dir)

# Get locales directory
locales_dir = os.path.join(os.path.abspath("."), "locales")

if not os.path.isdir(locales_dir):
    raise Exception(locales_dir + " is not a directory. Call update_bundled_data.py first.")

# Copy styles to bundle
for filename in os.listdir(locales_dir):
    if filename.endswith(".xml") or filename.endswith(".json"):
        shutil.copyfile(os.path.join(locales_dir, filename), os.path.join(bundle_dir, filename))
        continue
    else:
        continue