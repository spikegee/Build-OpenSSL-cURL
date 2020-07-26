#!/bin/bash

# This script downlaods and builds the Mac, iOS and tvOS libcurl libraries with Bitcode enabled

# Credits:
#
# Felix Schwarz, IOSPIRIT GmbH, @@felix_schwarz.
#   https://gist.github.com/c61c0f7d9ab60f53ebb0.git
# Bochun Bai
#   https://github.com/sinofool/build-libcurl-ios
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL 
# Preston Jennings
#   https://github.com/prestonj/Build-OpenSSL-cURL 



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

# set trap to help debug any build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/curl*.log${alertdim}"; tail -3 /tmp/curl*.log' INT TERM EXIT

CURL_VERSION="curl-7.50.1"
IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
TVOS_SDK_VERSION="$(xcrun --sdk appletvos --show-sdk-version)"
MIN_IOS_VERSION="11.0"
MIN_TVOS_VERSION="11.0"
nohttp2="0"
BUILD_LIST=("Mac-x86_64" "iOS-armv7" "iOS-armv7s" "iOS-arm64" "iOS-arm64e" "iOS-x86_64" "iOS-i386" "tvOS-arm64" "tvOS-x86_64")

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-v ${dim}<curl version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-i ${dim}<iPhone target version>${normal}] [-l ${dim}<Restricted arch list>${normal}] [-b] [-x] [-n] [-h]"
    echo
	echo "         -v   version of curl (default $CURL_VERSION)"
	echo "         -s   iOS SDK version (default $IOS_SDK_VERSION)"
	echo "         -t   tvOS SDK version (default $TVOS_SDK_VERSION)"
	echo "         -i   iPhone target version (default $MIN_IOS_VERSION)"
	echo "         -j   AppleTV target version (default $MIN_TVOS_VERSION)"
	echo "         -b   compile without bitcode"
	echo "         -n   compile with nghttp2"
	echo "         -x   disable color output"
	echo "         -l   space separated list to restrict targets to build: eg. \"iOS-arm64 iOS-x86_64 tvOS-armV7 Mac-arm64\""
	echo "         -h   show usage"	
	echo
	trap - INT TERM EXIT
	exit 127
}

while getopts "v:s:t:l:i:j:nbxh\?" o; do
    case "${o}" in
        v)
			CURL_VERSION="curl-${OPTARG}"
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
		n)
			nohttp2="1"
			;;
		b)
			NOBITCODE="yes"
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

OPENSSL="${PWD}/../openssl"  
DEVELOPER=`xcode-select -print-path`

# HTTP2 support
if [ $nohttp2 == "1" ]; then
	# nghttp2 will be in ../nghttp2/{Platform}/{arch}
	NGHTTP2="${PWD}/../nghttp2"  
fi

if [ $nohttp2 == "1" ]; then
	echo "Building with HTTP2 Support (nghttp2)"
else
	echo "Building without HTTP2 Support (nghttp2)"
	NGHTTP2CFG=""
	NGHTTP2LIB=""
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
	HOST="x86_64-apple-darwin"

	echo -e "${subbold}Building ${CURL_VERSION} for ${archbold}${ARCH}${dim}"

	TARGET="darwin-i386-cc"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
	fi

	if [ $nohttp2 == "1" ]; then 
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/Mac/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/Mac/${ARCH}/lib"
	fi
	
	# export CC="${BUILD_TOOLS}/usr/bin/clang"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -L${OPENSSL}/Mac/lib ${NGHTTP2LIB}"
	pushd . > /dev/null
	cd "${CURL_VERSION}"
	./configure -prefix="/tmp/${CURL_VERSION}-${ARCH}" --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=${OPENSSL}/Mac ${NGHTTP2CFG} --host=${HOST} &> "/tmp/${CURL_VERSION}-${ARCH}.log"

	make -j8 >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	# Save curl binary for Mac Version
	cp "/tmp/${CURL_VERSION}-${ARCH}/bin/curl" "/tmp/curl"
	make clean >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1
	BITCODE=$2

	pushd . > /dev/null
	cd "${CURL_VERSION}"
  
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

	if [ $nohttp2 == "1" ]; then 
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/iOS/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/iOS/${ARCH}/lib"
	fi
	  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${MIN_IOS_VERSION} ${CC_BITCODE_FLAG}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L${OPENSSL}/iOS/lib ${NGHTTP2LIB}"

	BUILD_STATIC="--disable-shared --enable-static"
	#BUILD_STATIC=
   
	echo -e "${subbold}Building ${CURL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} ${BITCODE}"

	if [[ "${ARCH}" == *"arm64"* || "${ARCH}" == "arm64e" ]]; then
		./configure -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" $BUILD_STATIC -with-random=/dev/urandom --with-ssl=${OPENSSL}/iOS ${NGHTTP2CFG} --host="arm-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else
		./configure -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" $BUILD_STATIC -with-random=/dev/urandom --with-ssl=${OPENSSL}/iOS ${NGHTTP2CFG} --host="${ARCH}-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	make -j8 >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${CURL_VERSION}"
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
	fi
	
	if [ $nohttp2 == "1" ]; then 
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/tvOS/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/tvOS/${ARCH}/lib"
	fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${MIN_TVOS_VERSION} -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L${OPENSSL}/tvOS/lib ${NGHTTP2LIB}"
#	export PKG_CONFIG_PATH 
   
	echo -e "${subbold}Building ${CURL_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

	./configure -prefix="/tmp/${CURL_VERSION}-tvOS-${ARCH}" --host="arm-apple-darwin" --disable-shared -with-random=/dev/urandom --disable-ntlm-wb --with-ssl="${OPENSSL}/tvOS" ${NGHTTP2CFG} &> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log"

	# Patch to not use fork() since it's not available on tvOS
        LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./lib/curl_config.h"
        LANG=C sed -i -- 's/HAVE_FORK"]=" 1"/HAVE_FORK\"]=" 0"/' "config.status"

	make -j8 >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null
}

echo -e "${bold}Cleaning up${dim}"
rm -rf include/curl/* lib/*

mkdir -p lib
mkdir -p include/curl/

rm -rf "/tmp/${CURL_VERSION}-*"
rm -rf "/tmp/${CURL_VERSION}-*.log"

rm -rf "${CURL_VERSION}"

if [ ! -e ${CURL_VERSION}.tar.gz ]; then
	echo "Downloading ${CURL_VERSION}.tar.gz"
	curl -LO https://curl.haxx.se/download/${CURL_VERSION}.tar.gz
else
	echo "Using ${CURL_VERSION}.tar.gz"
fi

echo "Unpacking curl"
tar xfz "${CURL_VERSION}.tar.gz"

getArchitectureToBuild "Mac" MACOS_ARCHS
read -ra MACOS_ARCHS <<< "$MACOS_ARCHS"
if [[ "${#MACOS_ARCHS[@]}" -gt 0 ]]; then
	echo -e "${bold}Building Mac libraries for architecture: ${MACOS_ARCHS[@]}${dim}"
	ARCH_FILES=()
	for ARCH in "${MACOS_ARCHS[@]}"; do
		buildMac "$ARCH"
		ARCH_FILES+=("/tmp/${CURL_VERSION}-$ARCH/lib/libcurl.a")
	done
	echo "Lipoing ${ARCH_FILES[@]}"
	lipo \
		"${ARCH_FILES[@]}" \
		-create -output lib/libcurl_Mac.a
fi

getArchitectureToBuild "iOS" IOS_ARCHS
read -ra IOS_ARCHS <<< "$IOS_ARCHS"
if [[ "${#IOS_ARCHS[@]}" -gt 0 ]]; then
	echo -e "${bold}Building iOS libraries (bitcode) for architecture: ${IOS_ARCHS[@]}${dim}"
	ARCH_FILES=()
	for ARCH in "${IOS_ARCHS[@]}"; do
		buildIOS "$ARCH" "bitcode"
		ARCH_FILES+=("/tmp/${CURL_VERSION}-iOS-$ARCH-bitcode/lib/libcurl.a")
	done
	echo "Lipoing ${ARCH_FILES[@]}"
	lipo \
		"${ARCH_FILES[@]}" \
		-create -output lib/libcurl_iOS.a

	if [[ "${NOBITCODE}" == "yes" ]]; then
		echo -e "${bold}Building iOS libraries (nobitcode) for architecture: ${IOS_ARCHS[@]}${dim}"
		ARCH_FILES=()
		for ARCH in "${IOS_ARCHS[@]}"; do
			buildIOS "$ARCH" "nobitcode"
			ARCH_FILES+=("/tmp/${CURL_VERSION}-iOS-$ARCH-nobitcode/lib/libcurl.a")
		done
		echo "Lipoing ${ARCH_FILES[@]}"
		lipo \
			"${ARCH_FILES[@]}" \
			-create -output lib/libcurl_iOS_nobitcode.a
	fi
fi

getArchitectureToBuild "tvOS" TVOS_ARCHS
read -ra TVOS_ARCHS <<< "$TVOS_ARCHS"
if [[ "${#TVOS_ARCHS[@]}" -gt 0 ]]; then
	echo -e "${bold}Building tvOS libraries for architecture: ${TVOS_ARCHS[@]}${dim}"
	ARCH_FILES=()
	for ARCH in "${TVOS_ARCHS[@]}"; do
		buildTVOS "$ARCH"
		ARCH_FILES+=("/tmp/${CURL_VERSION}-tvOS-$ARCH/lib/libcurl.a")
	done
	echo "Lipoing ${ARCH_FILES[@]}"
	lipo \
		"${ARCH_FILES[@]}" \
		-create -output lib/libcurl_tvOS.a
fi

echo "  Copying headers"
# take the first build from any of the three OSes
if [[ ! "${#MACOS_ARCHS[@]}" -eq 0 ]]; then
    echo "Copying headers from Mac ${MACOS_ARCHS[0]}"
	cp /tmp/${CURL_VERSION}-${MACOS_ARCHS[0]}/include/curl/* include/curl/
elif [[ ! "${#IOS_ARCHS[@]}" -eq 0 ]]; then
	echo "Copying headers from iOS ${IOS_ARCHS[0]}"
	cp /tmp/${CURL_VERSION}-iOS-${IOS_ARCHS[0]}-bitcode/include/curl/* include/curl/
elif [[ ! "${#TVOS_ARCHS[@]}" -eq 0 ]]; then
	echo "Copying headers from tvOS ${TVOS_ARCHS[0]}"
	cp /tmp/${CURL_VERSION}-tvOS-${TVOS_ARCHS[0]}/include/curl/* include/curl/
else
	echo "ERROR: No headers to copy from!"
	exit
fi

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${CURL_VERSION}-*
rm -rf ${CURL_VERSION}

echo "Checking libraries"
xcrun -sdk iphoneos lipo -info lib/*.a

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"
