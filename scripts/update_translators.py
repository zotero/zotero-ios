import os
import shutil
import subprocess
import time

# Get bundle directory
bundle_dir = os.path.join(os.path.abspath("."), "bundled" + os.sep + "translators")

if not os.path.isdir(bundle_dir):
    raise Exception(bundle_dir + " is not a directory")

# Update translators submodule
subprocess.check_call(["git", "submodule", "update", "--recursive", "--remote"])

# Get translators directory
translators_dir = os.path.join(os.path.abspath("."), "ZShare" + os.sep + "Assets" + os.sep + "translation" + os.sep + "modules" + os.sep + "zotero" + os.sep + "translators")

if not os.path.isdir(translators_dir):
    raise Exception(translators_dir + " is not a directory")

# Store timestamp
timestamp = int(time.time())
with open(os.path.join(bundle_dir, "timestamp.txt"), "w") as f:
    f.write(str(timestamp))

# Delete translators submodule
shutil.rmtree(translators_dir)
