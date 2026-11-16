#!/bin/bash
# Builds a small, universal (arm64 + x86_64), LGPL ffmpeg and ffprobe from the
# official source into vendor/ffmpeg/. Only what Giffer needs is compiled in:
# every decoder and demuxer for input, but just GIF/PNG/raw output and a
# handful of filters. Needs Xcode command line tools and gpg. Takes a few minutes.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=9.0.2
KEY=FCF986EA15E6E293A5644F10B4322F04D67658D8   # FFmpeg release signing key, from ffmpeg.org/download.html
WORK="$PWD/build/ffmpeg"
OUT="$PWD/vendor/ffmpeg"
TARBALL="ffmpeg-$VERSION.tar.xz"
mkdir -p "$WORK" "$OUT"

cd "$WORK"
if [ ! -f "$TARBALL" ]; then
  curl -fsSLO "https://ffmpeg.org/releases/$TARBALL"
  curl -fsSLO "https://ffmpeg.org/releases/$TARBALL.asc"
  curl -fsSL  "https://ffmpeg.org/ffmpeg-devel.asc" -o ffmpeg-devel.asc
fi

# Verify the release signature in a throwaway keyring.
export GNUPGHOME="$WORK/gnupg"
rm -rf "$GNUPGHOME" && mkdir -m 700 "$GNUPGHOME"
gpg --quiet --import ffmpeg-devel.asc
if ! gpg --status-fd 1 --verify "$TARBALL.asc" "$TARBALL" 2>/dev/null | grep -q "VALIDSIG $KEY"; then
  echo "Signature check failed for $TARBALL" >&2
  exit 1
fi
echo "Signature OK: $TARBALL"

FILTERS=scale,fps,setpts,split,palettegen,paletteuse,format,null,copy,trim,crop,pad,transpose,hflip,vflip,rotate,anull,aresample,aformat

build() { # build <arch> [extra configure flags]
  local arch=$1; shift
  local dir="$WORK/$arch"
  rm -rf "$dir" && mkdir -p "$dir"
  tar -xf "$TARBALL" -C "$dir" --strip-components 1
  ( cd "$dir"
    ./configure \
      --cc="clang -arch $arch" --arch="$arch" --target-os=darwin \
      --extra-cflags="-mmacosx-version-min=11.0" --extra-ldflags="-mmacosx-version-min=11.0" \
      --disable-autodetect --enable-zlib \
      --disable-shared --enable-static \
      --disable-doc --disable-debug --disable-ffplay \
      --disable-network --disable-devices \
      --disable-encoders --enable-encoder=gif,png,rawvideo \
      --disable-muxers --enable-muxer=gif,image2,image2pipe,rawvideo,null \
      --disable-protocols --enable-protocol=file,pipe \
      --disable-filters --enable-filter=$FILTERS \
      "$@" >configure.log 2>&1
    make -j"$(sysctl -n hw.ncpu)" >make.log 2>&1
  )
  echo "Built $arch"
}

build arm64 &
A=$!
# No nasm on this machine, so the Intel slice is built without hand-written
# assembly: it works everywhere but decodes slower on Intel Macs.
X86ASM=--disable-x86asm
command -v nasm >/dev/null && X86ASM=
build x86_64 --enable-cross-compile $X86ASM &
B=$!
wait $A
wait $B

for tool in ffmpeg ffprobe; do
  lipo -create "$WORK/arm64/$tool" "$WORK/x86_64/$tool" -output "$OUT/$tool"
  strip -x "$OUT/$tool"
done
cp "$WORK/arm64/COPYING.LGPLv2.1" "$OUT/COPYING.LGPLv2.1"
echo "$VERSION" > "$OUT/VERSION"
ls -lh "$OUT"
"$OUT/ffmpeg" -hide_banner -version | head -3
