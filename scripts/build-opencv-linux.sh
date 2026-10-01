#!/usr/bin/env bash
set -euo pipefail

OPENCV_VERSION="${OPENCV_VERSION:-5.0.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.opencv-build/linux"
SRC_DIR="${WORK_DIR}/opencv-${OPENCV_VERSION}"
BUILD_DIR="${WORK_DIR}/build"

os="$(uname -s)"
machine="$(uname -m)"

if [[ "${os}" != "Linux" ]]; then
  echo "This script must run on Linux, got ${os}" >&2
  exit 1
fi

case "${machine}" in
  x86_64|amd64)
    arch_dir="x64"
    expected_file_text="x86-64"
    ;;
  aarch64|arm64)
    arch_dir="arm64"
    expected_file_text="aarch64|ARM aarch64|ARM64"
    ;;
  *)
    echo "Unsupported Linux CPU architecture: ${machine}" >&2
    exit 1
    ;;
esac

OUT_DIR="${ROOT_DIR}/src/native/linux/${arch_dir}"
CHECK_DIR="${ROOT_DIR}/native-checks/linux/${arch_dir}"
LIB_NAME="libopencv_java500.so"

find_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/javac" ]]; then
    return 0
  fi

  local javac_path
  javac_path="$(readlink -f "$(command -v javac)")"
  JAVA_HOME="$(cd "$(dirname "${javac_path}")/.." && pwd)"
  export JAVA_HOME
}

configure_opencv() {
  local java_args=()
  if [[ -d "${JAVA_HOME}/include" ]]; then
    java_args+=(
      "-DJAVA_AWT_LIBRARY=${JAVA_HOME}/lib/libjawt.so"
      "-DJAVA_JVM_LIBRARY=${JAVA_HOME}/lib/server/libjvm.so"
      "-DJAVA_INCLUDE_PATH=${JAVA_HOME}/include"
      "-DJAVA_INCLUDE_PATH2=${JAVA_HOME}/include/linux"
    )
  fi

  cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
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
  if ldd "${lib}" | tee "${CHECK_DIR}/ldd.txt" | grep -E "libopencv_.*\.so"; then
    echo "${LIB_NAME} depends on OpenCV shared libraries; expected a fat Java native library." >&2
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
  echo "${LIB_NAME} does not match expected architecture ${machine}" >&2
  exit 1
fi

reject_opencv_shared_deps "${lib_path}"

install -m 0755 "${lib_path}" "${OUT_DIR}/${LIB_NAME}"
cp "${WORK_DIR}/cmake-configure.log" "${CHECK_DIR}/cmake-configure.log"

echo "Installed ${OUT_DIR}/${LIB_NAME}"
