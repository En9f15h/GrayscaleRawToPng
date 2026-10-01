#!/usr/bin/env bash
set -euo pipefail

OPENCV_VERSION="${OPENCV_VERSION:-5.0.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.opencv-build/macos"
SRC_DIR="${WORK_DIR}/opencv-${OPENCV_VERSION}"
BUILD_DIR="${WORK_DIR}/build"

os="$(uname -s)"
machine="$(uname -m)"

if [[ "${os}" != "Darwin" ]]; then
  echo "This script must run on macOS, got ${os}" >&2
  exit 1
fi

case "${machine}" in
  x86_64|amd64)
    arch_dir="x64"
    cmake_arch="x86_64"
    expected_file_text="Mach-O 64-bit.*x86_64"
    apple_silicon_args=()
    ;;
  arm64|aarch64)
    arch_dir="arm64"
    cmake_arch="arm64"
    expected_file_text="Mach-O 64-bit.*arm64"
    apple_silicon_args=(-DCMAKE_APPLE_SILICON_PROCESSOR=arm64)
    ;;
  *)
    echo "Unsupported macOS CPU architecture: ${machine}" >&2
    exit 1
    ;;
esac

OUT_DIR="${ROOT_DIR}/src/native/macos/${arch_dir}"
CHECK_DIR="${ROOT_DIR}/native-checks/macos/${arch_dir}"
LIB_NAME="libopencv_java500.dylib"

find_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/javac" ]]; then
    return 0
  fi

  JAVA_HOME="$(/usr/libexec/java_home -v 17)"
  export JAVA_HOME
}

configure_opencv() {
  local java_args=()
  if [[ -d "${JAVA_HOME}/include" ]]; then
    java_args+=(
      "-DJAVA_AWT_LIBRARY=${JAVA_HOME}/lib/libjawt.dylib"
      "-DJAVA_JVM_LIBRARY=${JAVA_HOME}/lib/server/libjvm.dylib"
      "-DJAVA_INCLUDE_PATH=${JAVA_HOME}/include"
      "-DJAVA_INCLUDE_PATH2=${JAVA_HOME}/include/darwin"
    )
  fi

  cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_OSX_ARCHITECTURES="${cmake_arch}" \
    "${apple_silicon_args[@]}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_JAVA=ON \
    -DBUILD_opencv_java=ON \
    -DBUILD_FAT_JAVA_LIB=ON \
    -DOPENCV_FORCE_3RDPARTY_BUILD=ON \
    -DBUILD_TESTS=OFF \
    -DBUILD_PERF_TESTS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_DOCS=OFF \
    -DBUILD_PACKAGE=OFF \
    -DBUILD_opencv_python3=OFF \
    "${java_args[@]}" 2>&1 | tee "${WORK_DIR}/cmake-configure.log"
}

require_java_bindings() {
  if grep -Eq "ant:[[:space:]]+NO|JNI:[[:space:]]+NO|Java wrappers:[[:space:]]+NO|Unavailable:[[:space:]].*java" "${WORK_DIR}/cmake-configure.log"; then
    echo "OpenCV CMake did not detect the Java/JNI/Ant binding prerequisites." >&2
    grep -A20 -E "^--[[:space:]]+Java:|^--[[:space:]]+OpenCV modules:" "${WORK_DIR}/cmake-configure.log" || true
    exit 1
  fi
}

reject_opencv_shared_deps() {
  local lib="$1"
  if otool -L "${lib}" | tee "${CHECK_DIR}/otool-L.txt" | grep -E "libopencv_.*\.dylib"; then
    echo "${LIB_NAME} depends on OpenCV shared dylibs; expected a fat Java native library." >&2
    exit 1
  fi
}

echo "Host kernel: ${os}"
echo "Host machine: ${machine}"
echo "Output architecture: ${arch_dir}"

find_java_home
echo "JAVA_HOME=${JAVA_HOME}"
"${JAVA_HOME}/bin/java" -version

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${CHECK_DIR}"

git clone --branch "${OPENCV_VERSION}" --depth 1 https://github.com/opencv/opencv.git "${SRC_DIR}"

configure_opencv
require_java_bindings

cmake --build "${BUILD_DIR}" --target opencv_java --parallel

lib_path="$(find "${BUILD_DIR}" -type f -name "${LIB_NAME}" | head -n 1)"
if [[ -z "${lib_path}" ]]; then
  echo "Could not find ${LIB_NAME} under ${BUILD_DIR}" >&2
  exit 1
fi

file "${lib_path}" | tee "${CHECK_DIR}/file.txt"
if ! grep -E "${expected_file_text}" "${CHECK_DIR}/file.txt"; then
  echo "${LIB_NAME} does not match expected architecture ${cmake_arch}" >&2
  exit 1
fi

reject_opencv_shared_deps "${lib_path}"

install -m 0755 "${lib_path}" "${OUT_DIR}/${LIB_NAME}"
cp "${WORK_DIR}/cmake-configure.log" "${CHECK_DIR}/cmake-configure.log"

echo "Installed ${OUT_DIR}/${LIB_NAME}"
