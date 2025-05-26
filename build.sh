#!/usr/bin/env bash

set -eux

get_latest_gh_release() {

    gh_ref="${1}"
    curl -s "https://api.github.com/repos/${gh_ref}/releases/latest" | jq -r .tag_name
}

ARCH="$(uname -m)"
GNOME_POMODORO_AUR_PKG="https://aur.archlinux.org/cgit/aur.git/snapshot/gnome-shell-pomodoro.tar.gz"
PKGBUILD_DEPS="binutils debugedit fakeroot sudo wget jq zsync xorg-server-xvfb patchelf binutils strace"
BUILD_DIR="/tmp/build"
APPDIR="/tmp/AppDir"
UPINFO="gh-releases-zsync|$(echo "$GITHUB_REPOSITORY":-no-user/no-repo | tr '/' '|')|latest|*$ARCH.AppImage.zsync"
GITHUB_BASE="https://github.com"

pacman -Syuq --needed --noconfirm --noprogressbar ${PKGBUILD_DEPS}
rm -rf "${APPDIR}" "${BUILD_DIR}"

URUNTIME_VERSION="$(get_latest_gh_release 'VHSgunzo/uruntime')"
URUNTIME_URL="${GITHUB_BASE}/VHSgunzo/uruntime/releases/download/${URUNTIME_VERSION}/uruntime-appimage-dwarfs-${ARCH}"
URUNTIME_LITE_URL="${GITHUB_BASE}/VHSgunzo/uruntime/releases/download/${URUNTIME_VERSION}/uruntime-appimage-dwarfs-lite-${ARCH}"
rm -rf /usr/local/bin/uruntime
wget "${URUNTIME_URL}" -O /tmp/uruntime
chmod +x /tmp/uruntime
mv /tmp/uruntime /usr/local/bin/uruntime

rm -rf /usr/local/bin/uruntime-lite
wget "${URUNTIME_LITE_URL}" -O /tmp/uruntime-lite
chmod +x /tmp/uruntime-lite
mv /tmp/uruntime-lite /usr/local/bin/uruntime-lite

SHARUN_VERSION="$(get_latest_gh_release 'VHSgunzo/sharun')"
SHARUN_URL="${GITHUB_BASE}/VHSgunzo/sharun/releases/download/${SHARUN_VERSION}/sharun-${ARCH}"
rm -rf /usr/local/bin/sharun
wget "${SHARUN_URL}" -O /usr/local/bin/sharun
chmod +x /usr/local/bin/sharun

LLVM_BASE="${GITHUB_BASE}/pkgforge-dev/llvm-libs-debloated/releases/download/continuous"
case "${ARCH}" in
"x86_64")
    EXT="zst"
    LLVM_URL="${LLVM_BASE}/llvm-libs-nano-x86_64.pkg.tar.zst"
    LIBXML_URL="${LLVM_BASE}/libxml2-iculess-x86_64.pkg.tar.zst"
    ;;
"aarch64")
    EXT="xz"
    LLVM_URL="${LLVM_BASE}/llvm-libs-nano-aarch64.pkg.tar.xz"
    LIBXML_URL="${LLVM_BASE}/libxml2-iculess-aarch64.pkg.tar.xz"
    ;;
*)
    echo "Unsupported ARCH: '${ARCH}'"
    exit 1
    ;;
esac

# Debloated llvm and libxml2 without libicudata
wget "${LLVM_URL}" -O /tmp/llvm-libs.pkg.tar.zst
wget "${LIBXML_URL}" -O /tmp/libxml2.pkg.tar.zst
pacman -U --noconfirm /tmp/*.pkg.tar.zst
rm -rf "${BUILD_DIR}" "${PKGBUILD_DEPS}"
mkdir -p -- "${APPDIR}/share" "${BUILD_DIR}"

cd "${BUILD_DIR}"

wget "${GNOME_POMODORO_AUR_PKG}"

tar -xvf gnome-shell-pomodoro.tar.gz
rm gnome-shell-pomodoro.tar.gz
cd gnome-shell-pomodoro

sed -i 's|EUID == 0|EUID == 69|g' /usr/bin/makepkg
sed -i -e "s/x86_64/${ARCH}/" ./PKGBUILD
PKG_VER=$(grep 'pkgver=' PKGBUILD | awk -F '=' '{print $2}')
GNOME_POMODORO_APPIMAGE="Gnome-Pomodoro-${PKG_VER}-${ARCH}.AppImage"
makepkg -s --noconfirm --noprogressbar --needed

pacman -U --noconfirm ./gnome-shell-pomodoro*.pkg.tar.*

pacman -Rsndd --noconfirm mesa || true

cd "${APPDIR}"

export GSK_RENDERER=cairo

cp -rv /usr/share/applications/org.gnome.Pomodoro.desktop .
cp -rv /usr/share/icons/hicolor/256x256/apps/gnome-pomodoro.png ./
cp -rv /usr/share/icons/hicolor/256x256/apps/gnome-pomodoro.png ./.DirIcon
cp -rv /usr/share/gnome-pomodoro ./share
cp -rv /usr/share/locale ./share
find ./share/locale -type f ! -name '*glib*' ! -name '*gtk*' ! -name '*pomodoro*' -delete

cp -rv /usr/share/gnome-shell/extensions/pomodoro@arun.codito.in ./

xvfb-run -a -- sharun l -p -v -e -s -k /usr/bin/gnome-pomodoro

echo '#!/bin/sh' >>./AppRun
echo 'CURRENTDIR="$(cd "${0%/*}" && echo "$PWD")"' >>./AppRun
echo 'DATADIR="${XDG_DATA_HOME:-$HOME/.local/share}"' >>./AppRun
echo 'mkdir -p "${DATADIR}"/gnome-shell/extensions' >>./AppRun
echo 'cp -r "${CURRENTDIR}"/pomodoro@arun.codito.in "$DATADIR"/gnome-shell/extensions/pomodoro@arun.codito.in' >>./AppRun
echo 'exec "${CURRENTDIR}"/bin/gnome-pomodoro "${@}"' >>./AppRun

chmod a+x ./AppRun

./sharun -g

VERSION="$(./AppRun --version | awk 'FNR==1 {print $2}')"
if [ -z "${VERSION}" ]; then
    echo "ERROR: Could not get version from binary"
    exit 1
fi

echo "VERSION=${VERSION}" >>"${GITHUB_ENV}"
echo "::set-output name=VERSION::${VERSION}"

cd /tmp
cp "$(command -v uruntime)" ./uruntime
cp "$(command -v uruntime-lite)" ./uruntime-lite

./uruntime-lite --appimage-addupdinfo "${UPINFO}"

echo "Generating AppImage"
./uruntime --appimage-mkdwarfs -f \
    --set-owner 0 --set-group 0 \
    --no-history --no-create-timestamp \
    --compression zstd:level=22 -S26 -B8 \
    --header uruntime-lite -i "${APPDIR}" \
    -o "${GNOME_POMODORO_APPIMAGE}"

echo "Generating Zsync file"
zsyncmake ./*.AppImage -u ./*.AppImage

pacman -Scc --noconfirm
rm -rf /tmp/*.pkg.tar.zst
