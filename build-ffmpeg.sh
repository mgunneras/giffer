#!/bin/bash
# Builds a small, universal (arm64 + x86_64), LGPL ffmpeg and ffprobe from the
# official sources into vendor/ffmpeg/, with libwebp (animated WebP) and
# SVT-AV1 (AVIF) linked in statically. Only what Giffer needs is compiled in:
# every decoder and demuxer for input, but just GIF/APNG/WebP/AVIF output and
# a handful of filters.
# Needs Xcode command line tools, gpg, cmake, pkg-config and nasm. Takes several minutes.
set -euo pipefail
cd "$(dirname "$0")"

FFMPEG=9.0.2
FFMPEG_KEY=FCF986EA15E6E293A5644F10B4322F04D67658D8   # release signing key, from ffmpeg.org/download.html
WEBP=1.6.0
WEBP_SHA=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
SVT=4.3.0
SVT_SHA=9223ce06e6172ad41357ed23b3b00f036e03794b86b0e20ea9ccb3f648b8955d

WORK="$PWD/build/ffmpeg"
OUT="$PWD/vendor/ffmpeg"
JOBS=$(sysctl -n hw.ncpu)
MIN=11.0
mkdir -p "$WORK" "$OUT"
cd "$WORK"

fetch() { [ -f "$2" ] || curl -fsSL "$1" -o "$2"; }
check_sha() {
  echo "$2  $1" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $1" >&2; exit 1; }
  echo "Checksum OK: $1"
}

fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz" ffmpeg.tar.xz
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz.asc" ffmpeg.tar.xz.asc
fetch "https://ffmpeg.org/ffmpeg-devel.asc" ffmpeg-devel.asc
fetch "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP.tar.gz" libwebp.tar.gz
fetch "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVT/SVT-AV1-v$SVT.tar.bz2" svtav1.tar.bz2

# Verify the ffmpeg release signature in a throwaway keyring; the libraries by pinned checksum.
export GNUPGHOME="$WORK/gnupg"
rm -rf "$GNUPGHOME" && mkdir -m 700 "$GNUPGHOME"
gpg --quiet --import ffmpeg-devel.asc
if ! gpg --status-fd 1 --verify ffmpeg.tar.xz.asc ffmpeg.tar.xz 2>/dev/null | grep -q "VALIDSIG $FFMPEG_KEY"; then
  echo "Signature check failed for ffmpeg-$FFMPEG" >&2
  exit 1
fi
echo "Signature OK: ffmpeg-$FFMPEG"
check_sha libwebp.tar.gz "$WEBP_SHA"
check_sha svtav1.tar.bz2 "$SVT_SHA"

FILTERS=scale,fps,setpts,split,palettegen,paletteuse,format,null,copy,trim,crop,pad,transpose,hflip,vflip,rotate,anull,aresample,aformat

unpack() { rm -rf "$2" && mkdir -p "$2" && tar -xf "$1" -C "$2" --strip-components 1; }

build() { # build <arch>
  local arch=$1
  local dir="$WORK/$arch" prefix="$WORK/$arch/prefix"
  local host=$arch-apple-darwin
  [ "$arch" = arm64 ] && host=aarch64-apple-darwin
  rm -rf "$dir" && mkdir -p "$prefix"

  unpack libwebp.tar.gz "$dir/libwebp"
  ( cd "$dir/libwebp"
    ./configure --prefix="$prefix" --host="$host" --disable-shared --enable-static \
      --disable-png --disable-jpeg --disable-tiff --disable-gif --disable-sdl --disable-gl \
      CC="clang -arch $arch" CFLAGS="-O2 -mmacosx-version-min=$MIN" >configure.log 2>&1
    make -j"$JOBS" >make.log 2>&1
    make install >install.log 2>&1
  )

  unpack svtav1.tar.bz2 "$dir/svtav1"
  ( cd "$dir/svtav1"
    cmake -S . -B out -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF \
      -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR="$arch" \
      -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN \
      -DCMAKE_INSTALL_PREFIX="$prefix" >configure.log 2>&1
    cmake --build out -j"$JOBS" >make.log 2>&1
    cmake --install out >install.log 2>&1
  )

  unpack ffmpeg.tar.xz "$dir/ffmpeg"
  local cross=
  [ "$arch" != "$(uname -m)" ] && cross=--enable-cross-compile
  ( cd "$dir/ffmpeg"
    # PKG_CONFIG_LIBDIR keeps configure from finding Homebrew's libraries.
    PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" ./configure \
      --cc="clang -arch $arch" --arch="$arch" --target-os=darwin $cross \
      --pkg-config=pkg-config --pkg-config-flags=--static \
      --extra-cflags="-mmacosx-version-min=$MIN" --extra-ldflags="-mmacosx-version-min=$MIN" \
      --disable-autodetect --enable-zlib --enable-libwebp --enable-libsvtav1 \
      --disable-shared --enable-static \
      --disable-doc --disable-debug --disable-ffplay \
      --disable-network --disable-devices \
      --disable-encoders --enable-encoder=gif,png,apng,rawvideo,libwebp,libwebp_anim,libsvtav1 \
      --disable-muxers --enable-muxer=gif,apng,webp,avif,image2,image2pipe,rawvideo,null \
      --disable-protocols --enable-protocol=file,pipe \
      --disable-filters --enable-filter=$FILTERS >configure.log 2>&1
    make -j"$JOBS" >make.log 2>&1
  )
  echo "Built $arch"
}

build arm64 &
A=$!
build x86_64 &
B=$!
wait $A
wait $B

for tool in ffmpeg ffprobe; do
  lipo -create "$WORK/arm64/ffmpeg/$tool" "$WORK/x86_64/ffmpeg/$tool" -output "$OUT/$tool"
  strip -x "$OUT/$tool"
done
mkdir -p "$OUT/licenses"
cp "$WORK/arm64/ffmpeg/COPYING.LGPLv2.1" "$OUT/licenses/FFmpeg-COPYING.LGPLv2.1"
cp "$WORK/arm64/libwebp/COPYING" "$OUT/licenses/libwebp-COPYING"
cp "$WORK/arm64/svtav1/LICENSE.md" "$OUT/licenses/SVT-AV1-LICENSE.md"
cp "$WORK/arm64/svtav1/PATENTS.md" "$OUT/licenses/SVT-AV1-PATENTS.md"
echo "FFmpeg $FFMPEG, libwebp $WEBP, SVT-AV1 $SVT" > "$OUT/VERSION"
rm -f "$OUT/COPYING.LGPLv2.1"
ls -lh "$OUT"
"$OUT/ffmpeg" -hide_banner -version | head -1
