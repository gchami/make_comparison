#!/bin/python

import os
import sys
import re

# The file locations
base1 = open("/mnt/behemoth1/customers_delivered_releases/2.5/2.5.3/build_20150601181714_22e6f85/build-config/make/local-pkgs.make")
base2 = open("/mnt/behemoth1/customers_delivered_releases/2.5/2.5.3/build_20150601181714_22e6f85/build-config/make/local-pkgs2.make")
hot_fix1 = open("/home/build/ci/cumulus/CumulusLinux-2.5.3_release_br/latest_powerpc/build-config/make/local-pkgs.make")
hot_fix2 = open("/home/build/ci/cumulus/CumulusLinux-2.5.3_release_br/latest_powerpc/build-config/make/local-pkgs2.make")

# Read and append strings
base_str = base1.read()+base2.read()
hot_str = hot_fix1.read()+hot_fix2.read()

# Parse it
base_packages = re.findall("CUMULUS_VERSION.*.*cl.*\d+", base_str, flags=0)
hot_packages = re.findall("CUMULUS_VERSION.*.*cl.*\d+", hot_str, flags=0)
  
# Create a list of differences
differences = []


print "========================================"
print "Packages which we shipped with:"
print "========================================\n"

for package in base_packages:
    print package

    if package not in hot_packages:
        differences.append(package)


print "\n\n\n========================================"
print "Updated Packages Found:"
print "========================================\n"

for diff in differences:
    print diff



base1.close()
base2.close()
hot_fix1.close()
hot_fix2.close()
