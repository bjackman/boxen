# Packaging ourselves coz it was removed from nixpkgs:
# https://github.com/NixOS/nixpkgs/pull/332259/changes
{
  lib,
  stdenv,
  src,

  # buildtime
  makeWrapper,
  pkg-config,
  python3,
  which,
  gettext,

  # runtime
  avahi,
  bzip2,
  dbus,
  gnutar,
  gzip,
  libiconv,
  openssl,
  pcre2,
  uriparser,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tvheadend";
  version = "4.3-unstable";

  inherit src;

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    python3
    which
    gettext
  ];

  buildInputs = [
    avahi
    bzip2
    dbus
    libiconv
    openssl
    pcre2
    uriparser
    zlib
  ];

  enableParallelBuilding = true;

  configureFlags = [
    # We only use tvheadend to demux/clean the IPTV stream; Jellyfin does the
    # transcoding. Building without libav drops the FFmpeg dependency that got
    # tvheadend removed from nixpkgs, and matches upstream's own container build.
    "--disable-libav"
    "--disable-ffmpeg_static"
    # IPTV-only: skip the DVB/cable/satellite tuner support and its data, and
    # the CSA descrambler (tvhcsa, which pulls in libdvbcsa) since the streams
    # we care about are unencrypted.
    "--disable-dvbscan"
    "--disable-tvhcsa"
    # hdhomerun_static (on by default) downloads and builds a bundled
    # libhdhomerun at build time, which fails in the sandbox.
    "--disable-hdhomerun_client"
    "--disable-hdhomerun_static"
    # Embed the web UI into the binary rather than installing it to $out/share.
    "--enable-bundle"
    "--disable-pngquant"
    "--nowerror"
    "--python=python3"
  ];

  preConfigure = ''
    # The source tree has no .git or debian/changelog, so support/version would
    # fall back to a bogus "0.0.0~unknown"; seed the version it reads instead.
    echo "${finalAttrs.version}" > rpm/version

    # tvheadend execs a hard-coded /usr/bin/tar for its config backups.
    substituteInPlace src/config.c \
      --replace-quiet "/usr/bin/tar" "${gnutar}/bin/tar"
  '';

  postInstall = ''
    # Runtime helpers it execs: the config backup is a bzip2 tarball.
    wrapProgram $out/bin/tvheadend \
      --prefix PATH : ${
        lib.makeBinPath [
          gnutar
          bzip2
          gzip
        ]
      }
  '';

  meta = {
    description = "TV streaming server and digital video recorder";
    homepage = "https://tvheadend.org";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "tvheadend";
  };
})
