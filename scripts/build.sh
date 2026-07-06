#!/bin/sh
# build.sh — 将 mruby 编译为支持 Apple 全平台的 XCFramework
#
# 用法:
#   ./scripts/build.sh <mruby 源码目录> [输出目录]
#
# 示例:
#   ./scripts/build.sh /tmp/mruby-4.0.0 ./build
#
# 产物:
#   <输出目录>/Mruby.xcframework   — 可直接在 Package.swift 中引用
#
# 依赖: Xcode、rake、ruby
# 注意: 未安装的平台 SDK 会自动跳过，不影响已安装平台的编译

set -e

MRUBY_SRC="${1:?用法: ./scripts/build.sh <mruby 源码目录> [输出目录]}"
OUTPUT_DIR="${2:-$(pwd)/build}"
WORK_DIR="${OUTPUT_DIR}/.mruby_work"
XCFW_OUT="${OUTPUT_DIR}/MRuby.xcframework"

# ──────────────────────────────────────────────────────────────
# 平台列表: SDK  架构  平台标识
# ──────────────────────────────────────────────────────────────
PLATFORMS="\
iphoneos         arm64  ios-arm64
iphonesimulator  arm64  ios-arm64-simulator
appletvos        arm64  tvos-arm64
appletvsimulator arm64  tvos-arm64-simulator
watchos          arm64  watchos-arm64
watchsimulator   arm64  watchos-arm64-simulator
xros             arm64  xros-arm64
xrsimulator      arm64  xros-arm64-simulator
macosx           arm64  macos-arm64"

echo "==> mruby 源码 : ${MRUBY_SRC}"
echo "==> 输出目录   : ${OUTPUT_DIR}"
echo ""

# ──────────────────────────────────────────────────────────────
# 检测各平台 SDK 是否已安装，过滤出可用平台
# ──────────────────────────────────────────────────────────────
echo "==> 检测已安装的 SDK..."
AVAILABLE_PLATFORMS=""
echo "${PLATFORMS}" | while read -r SDK ARCH PLATFORM_ID; do
    if xcrun --sdk "${SDK}" --show-sdk-path > /dev/null 2>&1; then
        echo "    ✓ ${PLATFORM_ID} (${SDK})"
        echo "${SDK} ${ARCH} ${PLATFORM_ID}" >> "${WORK_DIR}/.available_platforms"
    else
        echo "    - ${PLATFORM_ID} (${SDK} 未安装，跳过)"
    fi
done

rm -rf "${XCFW_OUT}" "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

echo "==> 检测已安装的 SDK..."
echo "${PLATFORMS}" | while read -r SDK ARCH PLATFORM_ID; do
    if xcrun --sdk "${SDK}" --show-sdk-path > /dev/null 2>&1; then
        echo "    ✓ ${PLATFORM_ID} (${SDK})"
        printf '%s %s %s\n' "${SDK}" "${ARCH}" "${PLATFORM_ID}" >> "${WORK_DIR}/available_platforms.txt"
    else
        echo "    - ${PLATFORM_ID} 跳过（${SDK} SDK 未安装）"
    fi
done

if [ ! -f "${WORK_DIR}/available_platforms.txt" ]; then
    echo "✗ 未找到任何可用 SDK，请先安装 Xcode 平台支持"
    exit 1
fi

echo ""

# ──────────────────────────────────────────────────────────────
# 用 Ruby 脚本生成 mruby build config
# （避免 shell heredoc 与 Ruby #{} 插值冲突）
# ──────────────────────────────────────────────────────────────
BUILD_CONFIG="${WORK_DIR}/apple_all.rb"

ruby - "${BUILD_CONFIG}" "${WORK_DIR}/available_platforms.txt" << 'GENSCRIPT'
require 'open3'

output_path    = ARGV[0]
platforms_file = ARGV[1]

def xcrun(sdk, *args)
  out, status = Open3.capture2('xcrun', '--sdk', sdk, *args)
  raise "xcrun failed: #{args.inspect}" unless status.success?
  out.strip
end

lines = []
lines << "# 由 build_mruby.sh 自动生成，请勿手动编辑"
lines << ""
lines << "# Host build — CrossBuild 依赖它来编译 mrbc"
lines << "MRuby::Build.new do |conf|"
lines << "  conf.toolchain"
lines << "  conf.bins = []"
lines << "  conf.gembox 'default'"
lines << "end"
lines << ""

File.readlines(platforms_file).each do |line|
  sdk, arch, platform_id = line.strip.split
  next if sdk.nil?

  sdk_path = xcrun(sdk, '--show-sdk-path')
  cc       = xcrun(sdk, '--find', 'clang')
  ar       = xcrun(sdk, '--find', 'ar')

  lines << "MRuby::CrossBuild.new(#{platform_id.inspect}) do |conf|"
  lines << "  conf.toolchain"
  lines << ""
  lines << "  conf.cc do |cc|"
  lines << "    cc.command = #{cc.inspect}"
  lines << "    cc.flags   = %w[-arch #{arch} -Os -fno-exceptions]"
  lines << "    cc.flags  << '-isysroot' << #{sdk_path.inspect}"
  lines << "  end"
  lines << ""
  lines << "  conf.linker do |linker|"
  lines << "    linker.command = #{cc.inspect}"
  lines << "    linker.flags   = %w[-arch #{arch}]"
  lines << "    linker.flags  << '-isysroot' << #{sdk_path.inspect}"
  lines << "  end"
  lines << ""
  lines << "  conf.archiver do |ar|"
  lines << "    ar.command = #{ar.inspect}"
  lines << "    ar.archive_options = 'rcs \"%{outfile}\" %{objs}'"
  lines << "  end"
  lines << ""
  lines << "  conf.bins = []"
  lines << "  # stdlib-io (mruby-io/socket/dir) 依赖 fork/execl，在非 macOS 平台不可用，故排除"
  lines << "  conf.gembox 'stdlib'"
  lines << "  conf.gembox 'stdlib-ext'"
  lines << "  conf.gembox 'math'"
  lines << "  conf.gembox 'metaprog'"
  lines << "  conf.gem :core => 'mruby-compiler'"
  lines << "end"
  lines << ""
end

File.write(output_path, lines.join("\n"))
puts "    config 已写入: #{output_path}"
GENSCRIPT

echo ""
echo "==> 开始编译（这需要几分钟）..."
echo ""

MRUBY_BUILD_OUT="${WORK_DIR}/mruby_out"
mkdir -p "${MRUBY_BUILD_OUT}"

MRUBY_BUILD_DIR="${MRUBY_BUILD_OUT}" \
MRUBY_CONFIG="${BUILD_CONFIG}" \
    rake -f "${MRUBY_SRC}/Rakefile"

echo ""
echo "==> 整理编译产物..."

# ──────────────────────────────────────────────────────────────
# 整理各平台产物并构建 XCFramework 参数
# ──────────────────────────────────────────────────────────────
while IFS= read -r platform_line; do
    SDK=$(echo "${platform_line}" | awk '{print $1}')
    ARCH=$(echo "${platform_line}" | awk '{print $2}')
    PLATFORM_ID=$(echo "${platform_line}" | awk '{print $3}')

    LIB=$(find "${MRUBY_BUILD_OUT}/${PLATFORM_ID}" -name "libmruby.a" 2>/dev/null | head -1)

    if [ -z "${LIB}" ]; then
        echo "    !! [${PLATFORM_ID}] 未找到 libmruby.a，跳过"
        continue
    fi

    STAGED="${WORK_DIR}/staged/${PLATFORM_ID}"
    INC_STAGED="${STAGED}/include"

    mkdir -p "${STAGED}/lib" "${INC_STAGED}"
    cp "${LIB}" "${STAGED}/lib/libmruby.a"

    # 先复制源码头文件，再用 build 产物头文件覆盖/补充
    # （presym/id.h、presym/table.h 等是编译时动态生成的，不在源码 include/ 里）
    cp -R "${MRUBY_SRC}/include/." "${INC_STAGED}/"
    if [ -d "${MRUBY_BUILD_OUT}/${PLATFORM_ID}/include" ]; then
        cp -R "${MRUBY_BUILD_OUT}/${PLATFORM_ID}/include/." "${INC_STAGED}/"
    fi

    # module.modulemap — 显式列出公开头文件，供 Swift import MRuby 使用
    cat > "${INC_STAGED}/module.modulemap" << 'MODULEMAP'
module MRuby {
    header "mruby.h"
    header "mruby/compile.h"
    header "mruby/string.h"
    header "mruby/array.h"
    header "mruby/hash.h"
    header "mruby/value.h"
    header "mruby/variable.h"
    header "mruby/class.h"
    header "mruby/error.h"
    header "mruby/numeric.h"
    header "mruby/object.h"
    header "mruby/proc.h"
    header "mruby/range.h"
    header "mruby/data.h"
    header "mruby/gc.h"
    header "mruby/presym.h"
    export *
}
MODULEMAP

    echo "    ✓ [${PLATFORM_ID}]  $(du -sh "${STAGED}/lib/libmruby.a" | cut -f1)"
    echo "-library ${STAGED}/lib/libmruby.a -headers ${INC_STAGED}" >> "${WORK_DIR}/xcfw_args.txt"

done < "${WORK_DIR}/available_platforms.txt"

if [ ! -f "${WORK_DIR}/xcfw_args.txt" ]; then
    echo ""
    echo "✗ 没有找到任何编译产物，请检查上方编译日志"
    exit 1
fi

# ──────────────────────────────────────────────────────────────
# 打包 XCFramework
# ──────────────────────────────────────────────────────────────
echo ""
echo "==> 打包 XCFramework..."

XCFW_CMD="xcodebuild -create-xcframework"
while IFS= read -r line; do
    XCFW_CMD="${XCFW_CMD} ${line}"
done < "${WORK_DIR}/xcfw_args.txt"
XCFW_CMD="${XCFW_CMD} -output ${XCFW_OUT}"

eval "${XCFW_CMD}"

echo ""
echo "✅ 完成: ${XCFW_OUT}"
echo ""
echo "─────────────────────────────────────────────────────────"
echo "在 Package.swift 中使用:"
echo ""
echo '  .binaryTarget('
echo '      name: "MRuby",'
echo "      path: \"build/MRuby.xcframework\""
echo '  )'
echo "─────────────────────────────────────────────────────────"
