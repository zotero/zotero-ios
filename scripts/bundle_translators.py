import os
import shutil
import subprocess
import sys
import json
import re

submodule_path_parts = ["translators"]
bundle_subdir = "translators"

submodule_path = os.path.join(*submodule_path_parts)

def get_canonical_submodule_hash(submodule_path: str) -> str:
    output = subprocess.check_output([
        "git", "ls-tree", "--object-only", "HEAD", submodule_path
    ])
    return output.decode("utf-8").strip()

def get_actual_submodule_hash(submodule_path: str) -> str:
    output = subprocess.check_output([
        "git", "-C", submodule_path, "rev-parse", "HEAD"
    ])
    return output.decode("utf-8").strip()

def read_existing_commit_hash(path: str) -> str:
    if os.path.isfile(path):
        with open(path, "r") as f:
            return f.read().strip()
    return ""

def write_commit_hash(path: str, commit_hash: str):
    with open(path, "w") as f:
        f.write(commit_hash)

def index_json(directory):
    index = []

    for fn in sorted((fn for fn in os.listdir(directory)), key=str.lower):
        if not fn.endswith(".js"):
            continue
        
        with open(os.path.join(directory, fn), 'r', encoding='utf-8') as f:
            contents = f.read()
            # Parse out the JSON metadata block
            m = re.match(r'^\s*{[\S\s]*?}\s*?[\r\n]', contents)
            
            if not m:
                raise Exception("Metadata block not found in " + f.name)
            
            metadata = json.loads(m.group(0))
            
            index.append({"id": metadata["translatorID"],
                          "fileName": fn,
                          "lastUpdated": metadata["lastUpdated"]})

    return index

# Get bundle directory
bundle_dir = os.path.join(os.path.abspath("."), "Bundled" + os.sep + bundle_subdir)
hash_path = os.path.join(bundle_dir, "commit_hash.txt")

if not os.path.isdir(bundle_dir):
    os.mkdir(bundle_dir)

# Get submodule directory
submodule_dir = os.path.join(os.path.abspath("."), submodule_path)

if not os.path.isdir(submodule_dir):
    raise Exception(submodule_dir + " is not a directory. Init submodules first.")

existing_hash = read_existing_commit_hash(hash_path)
current_hash = get_actual_submodule_hash(submodule_path)

if existing_hash == current_hash:
    print("Bundle already up to date")
    sys.exit(0)

# Copy files to bundle
# Copy deleted.txt to bundle
shutil.copyfile(os.path.join(submodule_dir, "deleted.txt"), os.path.join(bundle_dir, "deleted.txt"))

# Create index file
index = index_json(submodule_dir)
with open(os.path.join(bundle_dir, "index.json"), "w") as f:
    json.dump(index, f, indent=True, ensure_ascii=False)

# Zip translators
os.chdir(submodule_dir)
subprocess.check_call(['zip', '-r', os.path.join(bundle_dir, "translators.zip"), "."])

write_commit_hash(hash_path, current_hash)

print("Bundle " + bundle_subdir + " copied from hash " + current_hash)