#!/bin/bash

DIR="$PWD/.."
source $PWD/util.sh

usage ()
{
cat << EOF
Usage:
   $0 [OPTIONS]

WebRTC automated build script.

OPTIONS:
   -c - Clean out build directories
   
EOF
}

while getopts ch OPTION 
do
  case $OPTION in
  c) CLEAN=true ;;
  #e) ENABLE_RTTI=$OPTARG ;;
  h) usage; exit 1 ;;
  esac
done

#SRCDIR='out'
BLACKLIST='-'
ENABLE_RTTI=${ENABLE_RTTI:-1}
WEBRTC_LOCAL='/opt/webrtc'

SRCDIR=$DIR
#REV_NUMBER=$(get_revision "$SRCDIR")
PACK_VERSION="1.0.$REV_NUMBER"
#PACK_VERSION="1.0.29281"
PACKAGE_NAME="libwebrtc-dev"
mkdir -p $SRCDIR
TARGET_OS=$PLATFORM
TARGET_CPU=${TARGET_CPU:-x64}
DEBIANIZE=true
OUTDIR="$SRCDIR/out/$TARGET_CPU"


if [[ $CLEAN == true ]]
then
	echo Cleaning out dir without ninja files
	find $SRCDIR/out -type f \( -name '*.o' -o -name '*.a' -o -name '*.so' -o -name '*.so.*' -o -name '*.stamp' \) -exec rm -rf {} \;
	exit 0
fi

echo Checking build environment dependencies
check_build_env $PLATFORM "$TARGET_CPU"

EXT_PATH=$PWD/depot_tools

export PATH="$EXT_PATH:$PATH"
echo Compiling WebRTC
#compile $PLATFORM $SRCDIR $OUTDIR $TARGET_OS $TARGET_CPU "$CONFIGS" "$BLACKLIST"

if [[ $DEBIANIZE == true ]]
then
    echo "Packaging WebRTC: $PACKAGE_NAME"
    package_prepare $SRCDIR $OUTDIR $TARGET_CPU $PACKAGE_NAME $DIR/resource "$CONFIGS"
    package_debian $SRCDIR $OUTDIR $PACKAGE_NAME $PACK_VERSION 'amd64'
fi

echo 'End build.'
exit 0

