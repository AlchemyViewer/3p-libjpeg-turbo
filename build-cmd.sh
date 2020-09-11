#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

LIBJPEG_TURBO_SOURCE_DIR="libjpeg-turbo"

top="$(pwd)"
stage="$top"/stage

# load autobuild provided shell functions and variables
case "$AUTOBUILD_PLATFORM" in
    windows*)
        autobuild="$(cygpath -u "$AUTOBUILD")"
    ;;
    *)
        autobuild="$AUTOBUILD"
    ;;
esac
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

top="$(pwd)"
stage="$top/stage"
stage_include="$stage/include/jpeglib"
stage_debug="$stage/lib/debug"
stage_release="$stage/lib/release"
mkdir -p "$stage_include"
mkdir -p "$stage_debug"
mkdir -p "$stage_release"

VERSION_HEADER_FILE="$stage_include/jconfig.h"

build=${AUTOBUILD_BUILD_ID:=0}

pushd "$LIBJPEG_TURBO_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                archflags="/arch:SSE2"
            else
                archflags=""
            fi

            mkdir -p "$stage/include/zlib"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            mkdir -p "build_debug"
            pushd "build_debug"
                # Invoke cmake and use as official build
                cmake -E env CFLAGS="$archflags" CXXFLAGS="$archflags /std:c++17 /permissive-" LDFLAGS="/DEBUG:FULL" \
                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" ../ -DWITH_JPEG8=ON -DWITH_CRT_DLL=ON -DWITH_SIMD=ON -DENABLE_SHARED=ON -DENABLE_STATIC=OFF -DREQUIRE_SIMD=ON

                cmake --build . --config Debug --clean-first

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi

                cp -a Debug/jpeg.{exp,lib} "$stage_debug/"
                cp -a Debug/jpeg8.{dll,pdb} "$stage_debug/"
            popd

            mkdir -p "build_release"
            pushd "build_release"
                # Invoke cmake and use as official build
                cmake -E env CFLAGS="$archflags /Ob3 /GL /Gy /Zi" CXXFLAGS="$archflags /Ob3 /GL /Gy /Zi /std:c++17 /permissive-" LDFLAGS="/LTCG /OPT:REF /OPT:ICF /DEBUG:FULL" \
                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" ../ -DWITH_JPEG8=ON -DWITH_CRT_DLL=ON -DWITH_SIMD=ON -DENABLE_SHARED=ON -DENABLE_STATIC=OFF -DREQUIRE_SIMD=ON

                cmake --build . --config Release --clean-first

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi

                cp -a Release/jpeg.{exp,lib} "$stage_release/"
                cp -a Release/jpeg8.{dll,pdb} "$stage_release/"

                cp -a "jconfig.h" "$stage_include"
            popd

            cp -a jerror.h "$stage_include"
            cp -a jmorecfg.h "$stage_include"
            cp -a jpeglib.h "$stage_include"
        ;;
        "darwin")
            opts="${LL_BUILD_RELEASE}"
            mkdir -p "build"
            pushd "build"

            cmake -G "Unix Makefiles" -DCMAKE_OSX_SYSROOT="macosx10.14" -DCMAKE_OSX_DEPLOYMENT_TARGET="10.13" \
                -DCMAKE_C_FLAGS="-arch x86_64"  \
                -DWITH_JPEG8=ON -DWITH_SIMD=ON \
                -DENABLE_STATIC=ON -DENABLE_SHARED=OFF ..
            cmake --build . --config Debug --clean-first
            cp *.a "${stage_debug}"
            cmake --build . --config Release --clean-first
            cp *.a "${stage_release}"

            cp -a "jconfig.h" "${stage_include}"

            popd

            cp -a jerror.h "$stage_include"
            cp -a jmorecfg.h "$stage_include"
            cp -a jpeglib.h "$stage_include"

        ;;
        "linux")
            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
            HARDENED="-fstack-protector-strong -D_FORTIFY_SOURCE=2"

            autoreconf -fvi

            # Let's remain compatible with the LL viewer cmake for less merge hell in the future if it ever changes.
            # and until Windows and Darwin builds are worked out for this thing.
            # Debug Build
            CFLAGS="-m32 -Og -g" CXXFLAGS="$CFLAGS -std=c++11" LDFLAGS="-m32" ./configure --with-jpeg8 \
                    --with-pic --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include/jpeglib" --libdir="\${prefix}/lib/debug"
            make -j$JOBS
            make install DESTDIR="$stage"

            make distclean

            # Release Build
            CFLAGS="-m32 -O3 -g $HARDENED" CXXFLAGS="$CFLAGS -std=c++11" LDFLAGS="-m32" ./configure --with-jpeg8 \
                    --with-pic --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include/jpeglib" --libdir="\${prefix}/lib/release"
            make -j$JOBS
            make install DESTDIR="$stage"

            make distclean
        ;;
        "linux64")
            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
            HARDENED="-fstack-protector-strong -D_FORTIFY_SOURCE=2"

            autoreconf -fvi

            # Let's remain compatible with the LL viewer cmake for less merge hell in the future if it ever changes.
            # and until Windows and Darwin builds are worked out for this thing.
            # Debug Build
            CFLAGS="-m64 -Og -g" CXXFLAGS="$CFLAGS -std=c++11" LDFLAGS="-m64" ./configure --with-jpeg8 \
                    --with-pic --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include/jpeglib" --libdir="\${prefix}/lib/debug"
            make -j$JOBS
            make install DESTDIR="$stage"

            make distclean

            # Release Build
            CFLAGS="-m64 -O3 -g $HARDENED" CXXFLAGS="$CFLAGS -std=c++11" LDFLAGS="-m64" ./configure --with-jpeg8 \
                    --with-pic --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include/jpeglib" --libdir="\${prefix}/lib/release"
            make -j$JOBS
            make install DESTDIR="$stage"

            make distclean
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE.md "$stage/LICENSES/libjpeg-turbo.txt"
	
    # version will be (e.g.) "1.4.0"
    version=`sed -n -E 's/#define LIBJPEG_TURBO_VERSION  ([0-9])[.]([0-9])[.]([0-9]).*/\1.\2.\3/p' "${VERSION_HEADER_FILE}"`
    # shortver will be (e.g.) "230": eliminate all '.' chars
    #since the libs do not use micro in their filenames, chop off shortver at minor
    short="$(echo $version | cut -d"." -f1-2)"
    shortver="${short//.}"

    echo "${version}.${build}" > "${stage}/VERSION.txt"

popd
