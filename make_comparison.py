#!/bin/python

import os
import sys

base1 = open("/mnt/behemoth1/customers_delivered_releases/2.5/2.5.3/build_20150601181714_22e6f85/build-config/make/local-pkgs.make")
base2 = open("/mnt/behemoth1/customers_delivered_releases/2.5/2.5.3/build_20150601181714_22e6f85/build-config/make/local-pkgs2.make")

print base1
print base2


base1.close()
base2.close()
