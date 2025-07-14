#!/bin/bash -ex
# ----------------------------------------------------------------------------
#
# Package       : istio/proxy
# Version       : 1.23.0
# Source repo   : https://github.com/istio/proxy
# Tested on     : UBI 9.3
# Language      : C++
# Travis-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Chandranana
#
# Disclaimer: This script has been tested in non root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

PACKAGE_NAME=proxy
PACKAGE_ORG=istio
SCRIPT_PACKAGE_VERSION=1.23.0
PACKAGE_VERSION=${1:-${SCRIPT_PACKAGE_VERSION}}
PACKAGE_URL=https://github.com/${PACKAGE_ORG}/${PACKAGE_NAME}
PATH=$PATH:/usr/local/go/bin
SOURCE_ROOT=$(pwd)
scriptdir=$(dirname $(realpath $0))
GO_VERSION=${1:-1.23.2}
GOPATH=$SOURCE_ROOT/go
GOBIN=/usr/local/go/bin 
	
sudo yum install -y wget sudo cmake patch gcc-toolset-12-libatomic-devel unzip python3.11-devel zip java-11-openjdk-devel git gcc-c++ xz

    


