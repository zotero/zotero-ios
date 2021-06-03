import json
import os
import re
import shutil
import subprocess
import time

def commit_hash_from_submodules(array):
    for line in array:
        if line.startswith("bundled-styles"):
            return line.split()[1]

# Get bundle directory
bundle_dir = os.path.join(os.path.abspath("."), "Bundled" + os.sep + "styles")

if not os.path.isdir(bundle_dir):
    raise Exception(bundle_dir + " is not a directory")

# Download submodule
subprocess.check_call(["git", "submodule", "update", "--recursive", "bundled-styles"])

# Get translators directory
styles_dir = os.path.join(os.path.abspath("."), "bundled-styles")

if not os.path.isdir(styles_dir):
    raise Exception(styles_dir + " is not a directory")

# Store last commit hash from translators submodule
submodules = subprocess.check_output(["git", "submodule", "foreach", "--recursive", "echo $path `git rev-parse HEAD`"]).decode("utf-8").splitlines()
commit_hash = commit_hash_from_submodules(submodules)

with open(os.path.join(bundle_dir, "commit_hash.txt"), "w") as f:
    f.write(commit_hash)

# Copy styles to bundle
for filename in os.listdir(styles_dir):
    if filename.endswith(".csl"):
        shutil.copyfile(os.path.join(styles_dir, filename), os.path.join(bundle_dir, filename))
        continue
    else:
        continue