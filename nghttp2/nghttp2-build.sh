#!/bin/bash
# This script downlaods and builds the Mac, iOS and tvOS nghttp2 libraries 
#
# Credits:
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL 
#
# NGHTTP2 - https://github.com/nghttp2/nghttp2
#

# > nghttp2 is an implementation of HTTP/2 and its header 
# > compression algorithm HPACK in C
# 
# NOTE: pkg-config is required
 
set -e

# Formatting
default="\033[39m"
wihte="\033[97m"
green="\033[32m"
red="\033[91m"
yellow="\033[33m"

bold="\033[0m${green}\033[1m"
subbold="\033[0m${green}"
archbold="\033[0m${yellow}\033[1m"
normal="${white}\033[0m"
dim="\033[0m${white}\033[2m"
alert="\033[0m${red}\033[1m"
alertdim="\033[0m${red}\033[2m"

# set trap to help debug build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/nghttp2*.log${alertdim}"; tail -3 /tmp/nghttp2*.log' INT TERM EXIT

NGHTTP2_VERNUM="1.40.0"
IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
TVOS_SDK_VERSION="$(xcrun --sdk appletvos --show-sdk-version)"
MIN_IOS_VERSION="11.0"
MIN_TVOS_VERSION="11.0"
BUILD_LIST=("Mac-x86_64" "iOS-armv7" "iOS-armv7s" "iOS-arm64" "iOS-arm64e" "iOS-x86_64" "iOS-i386" "tvOS-arm64" "tvOS-x86_64")

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
    echo -e "  ${subbold}$0${normal} [-v ${dim}<nghttp2 version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-l ${dim}<Restricted arch list>${normal}] [-x] [-h]"
    echo
	echo "         -v   version of nghttp2 (default $NGHTTP2_VERNUM)"
	echo "         -s   iOS SDK version (default $IOS_SDK_VERSION)"
	echo "         -t   tvOS SDK version (default $TVOS_SDK_VERSION)"
	echo "         -i   iPhone target version (default $MIN_IOS_VERSION)"
	echo "         -j   AppleTV target version (default $MIN_TVOS_VERSION)"
	echo "         -x   disable color output"
	echo "         -l   space separated list to restrict targets to build: eg. \"iOS-arm64 iOS-x86_64 tvOS-armV7 Mac-arm64\""
	echo "         -h   show usage"	
	echo
	trap - INT TERM EXIT
	exit 127
}

while getopts "v:s:t:l:i:j:xh\?" o; do
    case "${o}" in
        v)
	    	NGHTTP2_VERNUM="${OPTARG}"
            ;;
        s)
            IOS_SDK_VERSION="${OPTARG}"
            ;;
        t)
	    	TVOS_SDK_VERSION="${OPTARG}"
            ;;
		l)
			BUILD_LIST=()
	    	BUILD_LIST="${OPTARG}"
            ;;
		i)
	    	MIN_IOS_VERSION="${OPTARG}"
            ;;
		j)
	    	MIN_TVOS_VERSION="${OPTARG}"
            ;;
		x)
			bold=""
			subbold=""
			normal=""
			dim=""
			alert=""
			alertdim=""
			archbold=""
			;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

# --- Edit this to update version ---

NGHTTP2_VERSION="nghttp2-${NGHTTP2_VERNUM}"
DEVELOPER=`xcode-select -print-path`

NGHTTP2="${PWD}/../nghttp2"

# Check to see if pkg-config is already installed
if (type "pkg-config" > /dev/null) ; then
	echo "  pkg-config already installed"
else
	echo -e "${alertdim}** WARNING: pkg-config not installed... attempting to install.${dim}"

	# Check to see if Brew is installed
	if ! type "brew" > /dev/null; then
		echo -e "${alert}** FATAL ERROR: brew not installed - unable to install pkg-config - exiting.${normal}"
		exit
	else
		echo "  brew installed - using to install pkg-config"
		brew install pkg-config
	fi

	# Check to see if installation worked
	if (type "pkg-config" > /dev/null) ; then
		echo "  SUCCESS: pkg-config installed"
	else
		echo -e "${alert}** FATAL ERROR: pkg-config failed to install - exiting.${normal}"
		exit
	fi
fi 

getArchitectureToBuild()
{
	local CURRENT_OS=$1
	# be case insensitive for OS name
	CURRENT_OS=$(echo $CURRENT_OS | tr '[:lower:]' '[:upper:]')
	local __resultOutput=$2
	local __resultVariable=()
	for OS_ARCH in ${BUILD_LIST[@]}; do
		IFS='-' && read -ra TOKENS <<< "$OS_ARCH" && unset IFS
		local OS=${TOKENS[0]}
		OS=$(echo $OS | tr '[:lower:]' '[:upper:]')
		local ARCH=${TOKENS[1]}
		if [ "$OS" != "$CURRENT_OS" ]; then
			continue
		fi
		__resultVariable+=("$ARCH")
	done
	# return array as a space separated string
	eval $__resultOutput="'${__resultVariable[@]}'"
}

buildMac()
{
	ARCH=$1
        HOST="i386-apple-darwin"

	echo -e "${subbold}Building ${NGHTTP2_VERSION} for ${archbold}${ARCH}${dim}"

	TARGET="darwin-i386-cc"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
	fi

	export CC="${BUILD_TOOLS}/usr/bin/clang -fembed-bitcode"
        export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
        export LDFLAGS="-arch ${ARCH}"

	pushd . > /dev/null
	cd "${NGHTTP2_VERSION}"
	./configure --disable-shared --disable-app --disable-threads --enable-lib-only --prefix="${NGHTTP2}/Mac/${ARCH}" --host=${HOST} &> "/tmp/${NGHTTP2_VERSION}-${ARCH}.log"
	make >> "/tmp/${NGHTTP2_VERSION}-${ARCH}.log" 2>&1
	make install >> "/tmp/${NGHTTP2_VERSION}-${ARCH}.log" 2>&1
	make clean >> "/tmp/${NGHTTP2_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1
	BITCODE=$2

	pushd . > /dev/null
	cd "${NGHTTP2_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
	fi

        if [[ "${BITCODE}" == "nobitcode" ]]; then
                CC_BITCODE_FLAG=""
        else
                CC_BITCODE_FLAG="-fembed-bitcode"
        fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${MIN_IOS_VERSION} ${CC_BITCODE_FLAG}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK}"
   
	echo -e "${subbold}Building ${NGHTTP2_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim}"
        if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
		./configure --disable-shared --disable-app --disable-threads --enable-lib-only  --prefix="${NGHTTP2}/iOS/${ARCH}" --host="arm-apple-darwin" &> "/tmp/${NGHTTP2_VERSION}-iOS-${ARCH}-${BITCODE}.log"
        else
		./configure --disable-shared --disable-app --disable-threads --enable-lib-only --prefix="${NGHTTP2}/iOS/${ARCH}" --host="${ARCH}-apple-darwin" &> "/tmp/${NGHTTP2_VERSION}-iOS-${ARCH}-${BITCODE}.log"
        fi

        make -j8 >> "/tmp/${NGHTTP2_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
        make install >> "/tmp/${NGHTTP2_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
        make clean >> "/tmp/${NGHTTP2_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
        popd > /dev/null
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${NGHTTP2_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${MIN_TVOS_VERSION} -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L${OPENSSL}/tvOS/lib ${NGHTTP2LIB}"
	export LC_CTYPE=C
  
	echo -e "${subbold}Building ${NGHTTP2_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

	# Patch apps/speed.c to not use fork() since it's not available on tvOS
	# LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

	# Patch Configure to build for tvOS, not iOS
	# LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
	# chmod u+x ./Configure
	
	./configure --disable-shared --disable-app --disable-threads --enable-lib-only  --prefix="${NGHTTP2}/tvOS/${ARCH}" --host="arm-apple-darwin" &> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log"
	LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "config.h"

	# add -isysroot to CC=
	#sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_SDK_VERSION} !" "Makefile"

	make  >> "/tmp/${NGHTTP2_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install  >> "/tmp/${NGHTTP2_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${NGHTTP2_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null
}


echo -e "${bold}Cleaning up${dim}"
rm -rf include/nghttp2/* lib/*
rm -fr Mac
rm -fr iOS
rm -fr tvOS

mkdir -p lib

rm -rf "/tmp/${NGHTTP2_VERSION}-*"
rm -rf "/tmp/${NGHTTP2_VERSION}-*.log"

rm -rf "${NGHTTP2_VERSION}"

if [ ! -e ${NGHTTP2_VERSION}.tar.gz ]; then
	echo "Downloading ${NGHTTP2_VERSION}.tar.gz"
	curl -LO https://github.com/nghttp2/nghttp2/releases/download/v${NGHTTP2_VERNUM}/${NGHTTP2_VERSION}.tar.gz
else
	echo "Using ${NGHTTP2_VERSION}.tar.gz"
fi

echo "Unpacking nghttp2"
tar xfz "${NGHTTP2_VERSION}.tar.gz"

getArchitectureToBuild "Mac" MACOS_ARCHS
read -ra MACOS_ARCHS <<< "$MACOS_ARCHS"
if [[ "${#MACOS_ARCHS[@]}" -gt 0 ]]; then
	echo -e "${bold}Building Mac libraries for architecture: ${MACOS_ARCHS[@]}${dim}"
	ARCH_FILES=()
	for ARCH in "${MACOS_ARCHS[@]}"; do
		buildMac "$ARCH"
		ARCH_FILES+=("${NGHTTP2}/Mac/$ARCH/lib/libnghttp2.a")
	done
	echo "Lipoing ${ARCH_FILES[@]}"
	lipo \
		"${ARCH_FILES[@]}" \
		-create -output "${NGHTTP2}/lib/libnghttp2_Mac.a"
fi

getArchitectureToBuild "iOS" IOS_ARCHS
read -ra IOS_ARCHS <<< "$IOS_ARCHS"
if [[ "${#IOS_ARCHS[@]}" -gt 0 ]]; then
	echo -e "${bold}Building iOS libraries (bitcode) for architecture: ${IOS_ARCHS[@]}${dim}"
	ARCH_FILES=()
	for ARCH in "${IOS_ARCHS[@]}"; do
		buildIOS "$ARCH" "bitcode"
		ARCH_FILES+=("${NGHTTP2}/iOS/$ARCH/lib/libnghttp2.a")
	done
	echo "Lipoing ${ARCH_FILES[@]}"
	lipo \
		"${ARCH_FILES[@]}" \
		-create -output "${NGHTTP2}/lib/libnghttp2_iOS.a"
fi

getArchitectureToBuild "tvOS" TVOS_ARCHS
read -ra TVOS_ARCHS <<< "$TVOS_ARCHS"
if [[ "${#TVOS_ARCHS[@]}" -gt 0 ]]; then
	echo -e "${bold}Building tvOS libraries for architecture: ${TVOS_ARCHS[@]}${dim}"
	ARCH_FILES=()
	for ARCH in "${TVOS_ARCHS[@]}"; do
		buildTVOS "$ARCH"
		ARCH_FILES+=("${NGHTTP2}/tvOS/$ARCH/lib/libnghttp2.a")
	done
	echo "Lipoing ${ARCH_FILES[@]}"
	lipo \
		"${ARCH_FILES[@]}" \
		-create -output "${NGHTTP2}/lib/libnghttp2_tvOS.a"
fi

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${NGHTTP2_VERSION}-*
rm -rf ${NGHTTP2_VERSION}

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"

