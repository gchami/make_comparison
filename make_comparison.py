#!/bin/python

import os
import sys
import re

# The actual file locations
# base1 = open("/mnt/behemoth1/customers_delivered_releases/2.5/2.5.3/build_20150601181714_22e6f85/build-config/make/local-pkgs.make")
# base2 = open("/mnt/behemoth1/customers_delivered_releases/2.5/2.5.3/build_20150601181714_22e6f85/build-config/make/local-pkgs2.make")
# hot_fix1 = open("/home/build/ci/cumulus/CumulusLinux-2.5.3_release_br/latest_powerpc/build-config/make/local-pkgs.make")
# hot_fix2 = open("/home/build/ci/cumulus/CumulusLinux-2.5.3_release_br/latest_powerpc/build-config/make/local-pkgs2.make")
# base1.close()
# base2.close()
# hot_fix2.close()
# hot_fix2.close()

base1 = open("test_files/base")
hot_fix1 = open("test_files/hot_fix")

base_str = base1.read()
hot_str = hot_fix1.read()

base_packages = re.findall("CUMULUS_VERSION.*.*cl.*\d+", base_str, flags=0)
hot_packages = re.findall("CUMULUS_VERSION.*.*cl.*\d+", hot_str, flags=0)
  

differences = []

for package in base_packages:
    if package not in hot_packages:
        differences.append(package)



print "Updated Packages Found: \n"
print differences
