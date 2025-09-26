#!/usr/bin/env bash

set -euo pipefail

CMAKE_PACKAGE_ROOT_ARGS=""

_installCommonDev() {
    lastDir="$(pwd)"
    arch=$(uname -m)
    
    # 使用固定版本
    cmakeVersionSmall="3.31.6"
    boostVersionSmall="1.86.0"

    rm -rf "${baseDir}"
    mkdir -p "${baseDir}"
    if [[ ! -z "${PREFIX}" ]]; then
        mkdir -p "${PREFIX}"
    fi

    # 首先尝试用apt安装尽可能多的依赖
    echo "📦 使用apt安装开发工具..."
    apt-get update
    apt-get install -y --no-install-recommends \
        cmake \
        bison \
        flex \
        swig \
        libboost-all-dev \
        libeigen3-dev \
        libspdlog-dev \
        libgtest-dev \
        libabsl-dev \
        ninja-build

    # CMake - 如果系统版本不够新，则安装最新版
    cmakePrefix=${PREFIX:-"/usr/local"}
    cmakeBin=${cmakePrefix}/bin/cmake
    if ! command -v cmake &> /dev/null || [[ $(cmake --version | head -1 | awk '{print $3}') < "3.20" ]]; then
        echo "🔧 安装更新的CMake..."
        cd "${baseDir}"
        wget https://github.com/Kitware/CMake/releases/download/v${cmakeVersionSmall}/cmake-${cmakeVersionSmall}-linux-${arch}.sh
        chmod +x cmake-${cmakeVersionSmall}-linux-${arch}.sh
        ./cmake-${cmakeVersionSmall}-linux-${arch}.sh --skip-license --prefix=${cmakePrefix}
    else
        echo "✅ CMake已安装"
    fi

    # 尝试用apt安装其他依赖
    echo "📚 安装其他库..."
    apt-get install -y --no-install-recommends \
        libpcre2-dev \
        libpcre3-dev \
        libyaml-cpp-dev \
        zlib1g-dev

    # 只有apt没有的包才从源码编译
    _compile_missing_packages

    cd "${lastDir}"
    rm -rf "${baseDir}"

    if [[ ! -z ${PREFIX} ]]; then
        # 生成环境设置脚本
        cat > ${PREFIX}/env.sh <<EOF
if [ -n "\$ZSH_VERSION" ]; then
  depRoot="\$(dirname \$(readlink -f "\${(%):-%x}"))"
else
  depRoot="\$(dirname \$(readlink -f "\${BASH_SOURCE[0]}"))"
fi

PATH=\${depRoot}/bin:\${PATH}
LD_LIBRARY_PATH=\${depRoot}/lib64:\${depRoot}/lib:\${LD_LIBRARY_PATH}
export CMAKE_PREFIX_PATH=\${depRoot}:\${CMAKE_PREFIX_PATH}
EOF
    fi
}

_compile_missing_packages() {
    # 检查并编译apt没有的包
    cmakePrefix=${PREFIX:-"/usr/local"}
    
    # cudd
    if ! pkg-config --exists cudd || [[ -z $(pkg-config --modversion cudd) ]]; then
        echo "🔨 编译安装CUDD..."
        cd "${baseDir}"
        git clone --depth=1 -b 3.0.0 https://github.com/The-OpenROAD-Project/cudd.git
        cd cudd
        autoreconf -i
        ./configure --prefix=${PREFIX:-"/usr/local"}
        make -j ${numThreads}
        make install
    fi

    # lemon
    if ! pkg-config --exists lemon || [[ -z $(pkg-config --modversion lemon) ]]; then
        echo "🔨 编译安装Lemon..."
        cd "${baseDir}"
        git clone --depth=1 -b 1.3.1 https://github.com/The-OpenROAD-Project/lemon-graph.git
        cd lemon-graph
        ${cmakePrefix}/bin/cmake -DCMAKE_INSTALL_PREFIX="${PREFIX:-/usr/local}" -B build .
        ${cmakePrefix}/bin/cmake --build build -j ${numThreads} --target install
    fi

    # 如果还需要其他特殊包，在这里添加
}

_installOrTools() {
    echo "🔧 安装OR-Tools..."
    
    rm -rf "${baseDir}"
    mkdir -p "${baseDir}"
    if [[ ! -z "${PREFIX}" ]]; then mkdir -p "${PREFIX}"; fi
    cd "${baseDir}"

    # 尝试用apt安装
    if apt-get install -y --no-install-recommends libortools-dev 2>/dev/null; then
        echo "✅ 使用apt安装OR-Tools"
        return
    fi

    # 备用方案：下载预编译包
    orToolsVersion="9.11.4210"
    orToolsFile="or-tools_amd64_ubuntu-22.04_cpp_v${orToolsVersion}.tar.gz"
    
    if wget https://github.com/google/or-tools/releases/download/v9.11/${orToolsFile}; then
        mkdir -p ${PREFIX:-"/opt/or-tools"}
        tar --strip 1 --dir ${PREFIX:-"/opt/or-tools"} -xf ${orToolsFile}
        echo "✅ OR-Tools安装完成"
    else
        echo "❌ OR-Tools安装失败，但将继续其他安装"
    fi

    rm -rf "${baseDir}"
}

_installUbuntuPackages() {
    echo "🚀 安装Ubuntu系统包..."
    
    export DEBIAN_FRONTEND="noninteractive"
    apt-get update
    apt-get install -y --no-install-recommends \
        software-properties-common \
        tzdata

    # 基础开发工具
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        git \
        wget \
        curl \
        automake \
        autoconf \
        libtool \
        pkg-config \
        ccache

    # 编译器和语言支持
    apt-get install -y --no-install-recommends \
        gcc \
        g++ \
        clang \
        lld \
        python3-dev \
        python3-pip \
        tcl-dev \
        tcl-tclreadline

    # 库文件
    apt-get install -y --no-install-recommends \
        libffi-dev \
        libreadline-dev \
        libomp-dev \
        libgomp1 \
        libpcre2-dev \
        libpcre3-dev \
        libyaml-cpp-dev \
        zlib1g-dev \
        libqt5charts5-dev \
        qtbase5-dev \
        qt5-qmake \
        qtchooser

    # 工具
    apt-get install -y --no-install-recommends \
        bison \
        flex \
        swig \
        lcov \
        groff \
        pandoc \
        unzip

    # 开发库
    apt-get install -y --no-install-recommends \
        libboost-all-dev \
        libeigen3-dev \
        libspdlog-dev \
        libgtest-dev \
        libgmock-dev \
        libabsl-dev

    echo "✅ Ubuntu系统包安装完成"
}

_installUbuntuCleanUp() {
    echo "🧹 清理临时文件..."
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/*
}

_help() {
    cat <<EOF

Usage: $0 -all     # 安装所有依赖（需要sudo权限）
       $0 -base    # 仅安装系统包依赖
       $0 -common  # 仅安装common开发依赖
       $0 -prefix=DIR  # 指定安装目录
       $0 -local   # 安装到用户目录 ~/.local
       $0 -threads=N   # 指定编译线程数

EOF
    exit "${1:-1}"
}

# 默认值
PREFIX=""
option="none"
numThreads=$(nproc)
baseDir=$(mktemp -d /tmp/DependencyInstaller-XXXXXX)

# 参数解析
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -h|-help)
            _help 0
            ;;
        -all)
            option="all"
            ;;
        -base)
            option="base"
            ;;
        -common)
            option="common"
            ;;
        -local)
            if [[ $(id -u) == 0 ]]; then
                echo "错误：使用-local时不能是root用户"
                exit 1
            fi
            export PREFIX="${HOME}/.local"
            ;;
        -prefix=*)
            export PREFIX="$(realpath ${1#*=})"
            ;;
        -threads=*)
            numThreads=${1#*=}
            ;;
        *)
            echo "未知选项: ${1}"
            _help
            ;;
    esac
    shift 1
done

if [[ "${option}" == "none" ]]; then
    echo "必须指定一个选项: -all, -base 或 -common"
    _help
fi

# 检查系统
if [[ ! -f /etc/os-release ]]; then
    echo "错误：无法检测操作系统"
    exit 1
fi

os=$(awk -F= '/^NAME/{print $2}' /etc/os-release | sed 's/"//g')
if [[ "${os}" != "Ubuntu" ]]; then
    echo "错误：此脚本仅支持Ubuntu系统"
    exit 1
fi

ubuntuVersion=$(awk -F= '/^VERSION_ID/{print $2}' /etc/os-release | sed 's/"//g')
echo "🎯 检测到系统: ${os} ${ubuntuVersion}"

# 执行安装
case "${option}" in
    "base")
        _installUbuntuPackages
        _installUbuntuCleanUp
        ;;
    "common")
        _installCommonDev
        _installOrTools
        ;;
    "all")
        _installUbuntuPackages
        _installCommonDev
        _installOrTools
        _installUbuntuCleanUp
        ;;
esac

echo "✅ 所有安装完成！"
if [[ ! -z ${PREFIX} ]]; then
    echo "📝 请运行: source ${PREFIX}/env.sh 来设置环境变量"
fi
