#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# if version not passed in, default to latest released version
export VERSION=1.4.6
# if ca version not passed in, default to latest released version
export CA_VERSION=1.4.6
# current version of thirdparty images (couchdb, kafka and zookeeper) released
export THIRDPARTY_IMAGE_VERSION=0.4.18
export ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')") # linux-amd64
export MARCH=$(uname -m) # x86_64

printHelp() {
  echo "Usage: bootstrap.sh [version [ca_version [thirdparty_version]]] [options]"
  echo
  echo "options:"
  echo "-h : this help"
  echo "-d : bypass docker image download"
  echo "-s : bypass fabric-samples repo clone"
  echo "-b : bypass download of platform-specific binaries"
  echo
  echo "e.g. bootstrap.sh 1.4.6 -s"
  echo "would download docker images and binaries for version 1.4.6"
}

dockerFabricPull() {
  local FABRIC_TAG=$1
  for IMAGES in peer orderer ccenv javaenv tools; do
      echo "==> FABRIC IMAGE: $IMAGES"
      echo
      docker pull hyperledger/fabric-$IMAGES:$FABRIC_TAG
      docker tag hyperledger/fabric-$IMAGES:$FABRIC_TAG hyperledger/fabric-$IMAGES
  done
}

dockerThirdPartyImagesPull() {
  local THIRDPARTY_TAG=$1
  for IMAGES in couchdb kafka zookeeper; do
      echo "==> THIRDPARTY DOCKER IMAGE: $IMAGES"
      echo
      docker pull hyperledger/fabric-$IMAGES:$THIRDPARTY_TAG
      docker tag hyperledger/fabric-$IMAGES:$THIRDPARTY_TAG hyperledger/fabric-$IMAGES
  done
}

dockerCaPull() {
      local CA_TAG=$1
      echo "==> FABRIC CA IMAGE"
      echo
      docker pull hyperledger/fabric-ca:$CA_TAG
      docker tag hyperledger/fabric-ca:$CA_TAG hyperledger/fabric-ca
}

samplesInstall() {
  # clone (if needed) hyperledger/fabric-samples and checkout corresponding
  # version to the binaries and docker images to be downloaded
  if [ -d first-network ]; then
    # if we are in the fabric-samples repo, checkout corresponding version
    echo "===> Checking out v${VERSION} of hyperledger/fabric-samples"
    git checkout v${VERSION}
  elif [ -d fabric-samples ]; then
    # if fabric-samples repo already cloned and in current directory,
    # cd fabric-samples and checkout corresponding version
    echo "===> Checking out v${VERSION} of hyperledger/fabric-samples"
    cd fabric-samples && git checkout v${VERSION}
  else
    echo "===> Cloning hyperledger/fabric-samples repo and checkout v${VERSION}"
    git clone -b master https://github.com/hyperledger/fabric-samples.git && cd fabric-samples && git checkout v${VERSION}
  fi
}

# This will download the .tar.gz
download() {
    local BINARY_FILE=$1
    local URL=$2
    echo "===> Downloading: " "${URL}"
    curl -L --retry 5 --retry-delay 3 "${URL}" | tar xz || rc=$?
    if [ -n "$rc" ]; then
        echo "==> There was an error downloading the binary file."
        return 22
    else
        echo "==> Done."
    fi
}

binariesInstall() {
    echo "===> Downloading version ${FABRIC_TAG} platform specific fabric binaries"
    download "${BINARY_FILE}" "https://github.com/hyperledger/fabric/releases/download/v${VERSION}/${BINARY_FILE}"
    if [ $? -eq 22 ]; then
        echo
        echo "------> ${FABRIC_TAG} platform specific fabric binary is not available to download <----"
        echo
        exit
    fi

    echo "===> Downloading version ${CA_TAG} platform specific fabric-ca-client binary"
    download "${CA_BINARY_FILE}" "https://github.com/hyperledger/fabric-ca/releases/download/v${CA_VERSION}/${CA_BINARY_FILE}"
    if [ $? -eq 22 ]; then
        echo
        echo "------> ${CA_TAG} fabric-ca-client binary is not available to download  (Available from 1.1.0-rc1) <----"
        echo
        exit
    fi
}

dockerInstall() {
  which docker >& /dev/null
  NODOCKER=$?
  if [ "${NODOCKER}" == 0 ]; then
	  echo "===> Pulling fabric Images"
	  dockerFabricPull ${FABRIC_TAG}
	  echo "===> Pulling fabric ca Image"
	  dockerCaPull ${CA_TAG}
	  echo "===> Pulling thirdparty docker images"
	  dockerThirdPartyImagesPull ${THIRDPARTY_TAG}
	  echo
	  echo "===> List out hyperledger docker images"
	  docker images | grep hyperledger*
  else
    echo "========================================================="
    echo "Docker not installed, bypassing download of Fabric images"
    echo "========================================================="
  fi
}

DOCKER=true
SAMPLES=true
BINARIES=true

# Parse commandline args pull out
# version and/or ca-version strings first
if [ ! -z "$1"  -a ${1:0:1} != "-" ]; then # 如果第一个参数不为0，且第一参数的第一个字符不为'-'
  VERSION=$1;shift # shift命令用于对参数的移动(左移)，通常用于在不知道传入参数个数的情况下依次遍历每个参数然后进行相应处理（常见于Linux中各种程序的启动脚本）
  if [ ! -z "$1"  -a ${1:0:1} != "-" ]; then
    CA_VERSION=$1;shift
    if [ ! -z "$1"  -a ${1:0:1} != "-" ]; then
      THIRDPARTY_IMAGE_VERSION=$1;shift
    fi
  fi
fi

# prior to 1.2.0 architecture was determined by uname -m
if [[ $VERSION =~ ^1\.[0-1]\.* ]]; then
  export FABRIC_TAG=${MARCH}-${VERSION}
  export CA_TAG=${MARCH}-${CA_VERSION}
  export THIRDPARTY_TAG=${MARCH}-${THIRDPARTY_IMAGE_VERSION}
else
  # starting with 1.2.0, multi-arch images will be default
  : ${CA_TAG:="$CA_VERSION"} # 冒号表示空命令，返回true(i.g., 0),提供一个占位符, 表明后面是表达式, 不是一个命令; 表达式{str:=expr}表示: 如果变量str不为空,${str:=expr}就等于str的值(即str的值保持不变)，若str为空，就把expr的值赋值给str
  : ${FABRIC_TAG:="$VERSION"}
  : ${THIRDPARTY_TAG:="$THIRDPARTY_IMAGE_VERSION"}
fi

BINARY_FILE=hyperledger-fabric-${ARCH}-${VERSION}.tar.gz
CA_BINARY_FILE=hyperledger-fabric-ca-${ARCH}-${CA_VERSION}.tar.gz

# then parse opts
while getopts "h?dsb" opt; do
  case "$opt" in
    h|\?)
      printHelp
      exit 0
    ;;
    d)  DOCKER=false
    ;;
    s)  SAMPLES=false
    ;;
    b)  BINARIES=false
    ;;
  esac
done

if [ "$SAMPLES" == "true" ]; then
  echo
  echo "Installing hyperledger/fabric-samples repo"
  echo
  samplesInstall
fi
if [ "$BINARIES" == "true" ]; then
  echo
  echo "Installing Hyperledger Fabric binaries"
  echo
  binariesInstall
fi
if [ "$DOCKER" == "true" ]; then
  echo
  echo "Installing Hyperledger Fabric docker images"
  echo
  dockerInstall
fi
