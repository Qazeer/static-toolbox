#!/bin/bash
set -e
set -o pipefail
set -x
if [ "$#" -ne 1 ];then
    echo "Usage: ${0} [x86|x86_64|armhf|aarch64]"
    echo "Example: ${0} x86_64"
    exit 1
fi
source $GITHUB_WORKSPACE/build/lib.sh
init_lib $1

build_gdb() {
    fetch "$GIT_BINUTILS_GDB" "${BUILD_DIRECTORY}/binutils-gdb" git
    cd "${BUILD_DIRECTORY}/binutils-gdb/" || { echo "Cannot cd to ${BUILD_DIRECTORY}/binutils-gdb/"; exit 1; }
    git clean -fdx
    git checkout gdb-9.2-release

    CMD="CFLAGS=\"${GCC_OPTS}\" "
    CMD+="CXXFLAGS=\"${GXX_OPTS}\" "
    CMD+="LDFLAGS=\"-static -pthread\" "
    if [ "$CURRENT_ARCH" != "x86" ] && [ "$CURRENT_ARCH" != "x86_64" ];then
        CMD+="CC_FOR_BUILD=\"/x86_64-linux-musl-cross/bin/x86_64-linux-musl-gcc\" "
        CMD+="CPP_FOR_BUILD=\"/x86_64-linux-musl-cross/bin/x86_64-linux-musl-g++\" "
    fi
    CMD+="${BUILD_DIRECTORY}/binutils-gdb/configure --target=$(get_host_triple) --host=x86_64-unknown-linux-musl "
    CMD+="--disable-shared --enable-static"

    GDB_CMD="${CMD} --disable-interprocess-agent"

    cd "${BUILD_DIRECTORY}/binutils-gdb/"
    mkdir build
    cd build
    eval "$GDB_CMD"
    ls -la
    
    cd "${BUILD_DIRECTORY}/binutils-gdb/"
    MAKE_PROG="${MAKE-make}"
    MAKE="${MAKE_PROG} AR=true LINK=true"
    export MAKE
    ${MAKE} $* all-libiberty
    ${MAKE} $* all-intl
    ${MAKE} $* all-bfd
    cd binutils
    MAKE="${MAKE_PROG}"
    export MAKE
    ${MAKE} $* ar_DEPENDENCIES= ar_LDADD='../bfd/*.o ../libiberty/*.o `if test -f ../intl/gettext.o; then echo '../intl/*.o'; fi`' ar
    ls -la
    cp ar /usr/bin

    cd "${BUILD_DIRECTORY}/binutils-gdb/build"
    make -j4
    
    strip "${BUILD_DIRECTORY}/binutils-gdb/gdb/gdb" "${BUILD_DIRECTORY}/binutils-gdb/gdb/gdbserver/gdbserver"
}

main() {
    build_gdb
    if [ ! -f "${BUILD_DIRECTORY}/binutils-gdb/gdb/gdb" ] || \
        [ ! -f "${BUILD_DIRECTORY}/binutils-gdb/gdb/gdbserver/gdbserver" ];then
        echo "[-] Building GDB ${CURRENT_ARCH} failed!"
        exit 1
    fi
    GDB_VERSION=$(get_version "${BUILD_DIRECTORY}/binutils-gdb/gdb/gdb --version |head -n1 |awk '{print \$4}'")
    GDBSERVER_VERSION=$(get_version "${BUILD_DIRECTORY}/binutils-gdb/gdb/gdbserver/gdbserver --version |head -n1 |awk '{print \$4}'")
    cp "${BUILD_DIRECTORY}/binutils-gdb/gdb/gdb" "${OUTPUT_DIRECTORY}/gdb${GDB_VERSION}"
    cp "${BUILD_DIRECTORY}/binutils-gdb/gdb/gdbserver/gdbserver" "${OUTPUT_DIRECTORY}/gdbserver${GDBSERVER_VERSION}"
    echo "[+] Finished building GDB ${CURRENT_ARCH}"

    echo ::set-output name=PACKAGED_NAME::"gdb${GDB_VERSION}"
    echo ::set-output name=PACKAGED_NAME_PATH::"/output/*"
}

main
