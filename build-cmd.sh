#!/usr/bin/env bash

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

TOP="$(cd "$(dirname "$0")"; pwd)"

PROJECT=libxml2
LICENSE=Copyright
SOURCE_DIR="$PROJECT"

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)"
[ -f "$stage"/packages/include/zlib-ng/zlib.h ] || \
{ echo "You haven't installed packages yet." 1>&2; exit 1; }

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

apply_patch()
{
    local patch="$1"
    local path="$2"
    echo "Applying $patch..."
    git apply --check --directory="$path" "$patch" && git apply --directory="$path" "$patch"
}

pushd "$TOP"

apply_patch "patches/0001-Patch-CMakeLists-to-use-static-prebuilt.patch" "libxml2"

popd

pushd "$TOP/$SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        windows*)
            load_vsvars

            # Setup staging dirs
            mkdir -p "$stage/include"
            mkdir -p "$stage/lib/release"

            mkdir -p "build"
            pushd "build"
                cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/release" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DLIBXML2_WITH_ICONV=OFF \
                    -DLIBXML2_WITH_LZMA=OFF \
                    -DLIBXML2_WITH_PYTHON=OFF \
                    -DLIBXML2_WITH_ZLIB=ON \
                    -DZLIB_INCLUDE_DIRS="$(cygpath -m $stage)/packages/include/zlib-ng/" \
                    -DZLIB_LIBRARIES="$(cygpath -m $stage)/packages/lib/release/zlib.lib" \
                    -DZLIB_LIBRARY_DIRS="$(cygpath -m $stage)/packages/lib"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/release/lib/libxml2s.lib ${stage}/lib/release/libxml2.lib

            # copy headers
            cp -a $stage/release/include/* $stage/include/
        ;;

        linux*)
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            opts="$(remove_cxxstd $opts)"

            # Setup staging dirs
            mkdir -p "$stage/include"
            mkdir -p "$stage/lib"
            mkdir -p $stage/lib/release/

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$opts" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DLIBXML2_WITH_ICONV=ON \
                    -DLIBXML2_WITH_LZMA=OFF \
                    -DLIBXML2_WITH_PYTHON=OFF \
                    -DLIBXML2_WITH_ZLIB=ON \
                    -DZLIB_INCLUDE_DIRS="$stage/packages/include/zlib-ng/" \
                    -DZLIB_LIBRARIES="$stage/packages/lib/release/libz.a"

                cmake --build . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi

                cmake --install . --config Release

                mv $stage/lib/*.a $stage/lib/release/
            popd
        ;;

        darwin*)
            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE}"
            opts="$(remove_cxxstd $opts)"

            # deploy target
            export MACOSX_DEPLOYMENT_TARGET=${LL_BUILD_DARWIN_DEPLOY_TARGET}

            # Setup staging dirs
            mkdir -p "$stage/include"
            mkdir -p "$stage/lib"
            mkdir -p $stage/lib/release/

            mkdir -p "build"
            pushd "build"
                CFLAGS="$opts" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DLIBXML2_WITH_ICONV=ON \
                    -DLIBXML2_WITH_LZMA=OFF \
                    -DLIBXML2_WITH_PYTHON=OFF \
                    -DLIBXML2_WITH_ZLIB=ON \
                    -DZLIB_INCLUDE_DIRS="$stage/packages/include/zlib-ng/" \
                    -DZLIB_LIBRARIES="$stage/packages/lib/release/libz.a" \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_ARCHITECTURES="x86_64"

                cmake --build . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi

                cmake --install . --config Release

                mv $stage/lib/*.a $stage/lib/release/
            popd
        ;;

        *)
            echo "platform not supported" 1>&2
            exit 1
        ;;
    esac
popd

mkdir -p "$stage/LICENSES"
cp "$TOP/$SOURCE_DIR/$LICENSE" "$stage/LICENSES/$PROJECT.txt"
mkdir -p "$stage"/docs/libxml2/
cp -a "$TOP"/README.Linden "$stage"/docs/libxml2/
