#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
TZ='UTC'; export TZ

umask 022

LDFLAGS='-Wl,-z,relro -Wl,--as-needed -Wl,-z,now'
export LDFLAGS
_ORIG_LDFLAGS="${LDFLAGS}"

CC=gcc
export CC
CXX=g++
export CXX
/sbin/ldconfig

set -e

_strip_files() {
    if [[ "$(pwd)" = '/' ]]; then
        echo
        printf '\e[01;31m%s\e[m\n' "Current dir is '/'"
        printf '\e[01;31m%s\e[m\n' "quit"
        echo
        exit 1
    else
        rm -fr lib64
        rm -fr lib
        chown -R root:root ./
    fi
    find usr/ -type f -iname '*.la' -delete
    if [[ -d usr/share/man ]]; then
        find -L usr/share/man/ -type l -exec rm -f '{}' \;
        sleep 2
        find usr/share/man/ -type f -iname '*.[1-9]' -exec gzip -f -9 '{}' \;
        sleep 2
        find -L usr/share/man/ -type l | while read file; do ln -svf "$(readlink -s "${file}").gz" "${file}.gz" ; done
        sleep 2
        find -L usr/share/man/ -type l -exec rm -f '{}' \;
    fi
    if [[ -d usr/lib/x86_64-linux-gnu ]]; then
        find usr/lib/x86_64-linux-gnu/ -type f \( -iname '*.so' -or -iname '*.so.*' \) | xargs --no-run-if-empty -I '{}' chmod 0755 '{}'
        find usr/lib/x86_64-linux-gnu/ -iname 'lib*.so*' -type f -exec file '{}' \; | sed -n -e 's/^\(.*\):[  ]*ELF.*, not stripped.*/\1/p' | xargs --no-run-if-empty -I '{}' /usr/bin/strip '{}'
        find usr/lib/x86_64-linux-gnu/ -iname '*.so' -type f -exec file '{}' \; | sed -n -e 's/^\(.*\):[  ]*ELF.*, not stripped.*/\1/p' | xargs --no-run-if-empty -I '{}' /usr/bin/strip '{}'
    fi
    if [[ -d usr/lib64 ]]; then
        find usr/lib64/ -type f \( -iname '*.so' -or -iname '*.so.*' \) | xargs --no-run-if-empty -I '{}' chmod 0755 '{}'
        find usr/lib64/ -iname 'lib*.so*' -type f -exec file '{}' \; | sed -n -e 's/^\(.*\):[  ]*ELF.*, not stripped.*/\1/p' | xargs --no-run-if-empty -I '{}' /usr/bin/strip '{}'
        find usr/lib64/ -iname '*.so' -type f -exec file '{}' \; | sed -n -e 's/^\(.*\):[  ]*ELF.*, not stripped.*/\1/p' | xargs --no-run-if-empty -I '{}' /usr/bin/strip '{}'
    fi
    if [[ -d usr/sbin ]]; then
        find usr/sbin/ -type f -exec file '{}' \; | sed -n -e 's/^\(.*\):[  ]*ELF.*, not stripped.*/\1/p' | xargs --no-run-if-empty -I '{}' /usr/bin/strip '{}'
    fi
    if [[ -d usr/bin ]]; then
        find usr/bin/ -type f -exec file '{}' \; | sed -n -e 's/^\(.*\):[  ]*ELF.*, not stripped.*/\1/p' | xargs --no-run-if-empty -I '{}' /usr/bin/strip '{}'
    fi
    echo
}

_build_zlib() {
    /sbin/ldconfig
    set -e
    _tmp_dir="$(mktemp -d)"
    cd "${_tmp_dir}"
    _zlib_ver="$(wget -qO- 'https://www.zlib.net/' | grep 'zlib-[1-9].*\.tar\.' | sed -e 's|"|\n|g' | grep '^zlib-[1-9]' | sed -e 's|\.tar.*||g' -e 's|zlib-||g' | sort -V | uniq | tail -n 1)"
    wget -c -t 9 -T 9 "https://www.zlib.net/zlib-${_zlib_ver}.tar.gz"
    tar -xof zlib-*.tar.*
    sleep 1
    rm -f zlib-*.tar*
    cd zlib-*
    ./configure --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu --includedir=/usr/include --sysconfdir=/etc --64
    make -j2 all
    rm -fr /tmp/zlib
    make DESTDIR=/tmp/zlib install
    cd /tmp/zlib
    _strip_files
    install -m 0755 -d usr/lib/x86_64-linux-gnu/cryptsetup/private
    cp -af usr/lib/x86_64-linux-gnu/*.so* usr/lib/x86_64-linux-gnu/cryptsetup/private/
    /bin/rm -f /usr/lib/x86_64-linux-gnu/libz.so*
    /bin/rm -f /usr/lib/x86_64-linux-gnu/libz.a
    sleep 2
    /bin/cp -afr * /
    sleep 2
    cd /tmp
    rm -fr "${_tmp_dir}"
    rm -fr /tmp/zlib
    /sbin/ldconfig
}

_build_openssl33() {
    set -e
    _tmp_dir="$(mktemp -d)"
    cd "${_tmp_dir}"
    _openssl33_ver="$(wget -qO- 'https://www.openssl.org/source/' | grep 'href="openssl-3\.3\.' | sed 's|"|\n|g' | grep -i '^openssl-3\.3\..*\.tar\.gz$' | cut -d- -f2 | sed 's|\.tar.*||g' | sort -V | uniq | tail -n 1)"
    wget -c -t 9 -T 9 "https://www.openssl.org/source/openssl-${_openssl33_ver}.tar.gz"
    tar -xof openssl-*.tar*
    sleep 1
    rm -f openssl-*.tar*
    cd openssl-*
    # Only for debian/ubuntu
    sed '/define X509_CERT_FILE .*OPENSSLDIR "/s|"/cert.pem"|"/certs/ca-certificates.crt"|g' -i include/internal/cryptlib.h
    sed '/install_docs:/s| install_html_docs||g' -i Configurations/unix-Makefile.tmpl
    LDFLAGS='' ; LDFLAGS='-Wl,-z,relro -Wl,--as-needed -Wl,-z,now -Wl,-rpath,\$$ORIGIN' ; export LDFLAGS
    HASHBANGPERL=/usr/bin/perl
    ./Configure \
    --prefix=/usr \
    --libdir=/usr/lib/x86_64-linux-gnu \
    --openssldir=/etc/ssl \
    enable-ec_nistp_64_gcc_128 \
    zlib enable-tls1_3 threads \
    enable-camellia enable-seed \
    enable-rfc3779 enable-sctp enable-cms \
    enable-md2 enable-rc5 enable-ktls \
    no-mdc2 no-ec2m \
    no-sm2 no-sm3 no-sm4 \
    shared linux-x86_64 '-DDEVRANDOM="\"/dev/urandom\""'
    perl configdata.pm --dump
    make -j2 all
    rm -fr /tmp/openssl33
    make DESTDIR=/tmp/openssl33 install_sw
    cd /tmp/openssl33
    # Only for debian/ubuntu
    mkdir -p usr/include/x86_64-linux-gnu/openssl
    chmod 0755 usr/include/x86_64-linux-gnu/openssl
    install -c -m 0644 usr/include/openssl/opensslconf.h usr/include/x86_64-linux-gnu/openssl/
    sed 's|http://|https://|g' -i usr/lib/x86_64-linux-gnu/pkgconfig/*.pc
    _strip_files
    install -m 0755 -d usr/lib/x86_64-linux-gnu/cryptsetup/private
    cp -af usr/lib/x86_64-linux-gnu/*.so* usr/lib/x86_64-linux-gnu/cryptsetup/private/
    rm -fr /usr/include/openssl
    rm -fr /usr/include/x86_64-linux-gnu/openssl
    rm -fr /usr/local/openssl-1.1.1
    rm -f /etc/ld.so.conf.d/openssl-1.1.1.conf
    sleep 2
    /bin/cp -afr * /
    sleep 2
    cd /tmp
    rm -fr "${_tmp_dir}"
    rm -fr /tmp/openssl33
    /sbin/ldconfig
}

_build_cryptsetup() {
    /sbin/ldconfig
    set -e
    _tmp_dir="$(mktemp -d)"
    cd "${_tmp_dir}"
    _link="$(wget -qO- 'https://gitlab.com/cryptsetup/cryptsetup/-/raw/main/README.md?ref_type=heads' | grep '\[cryptsetup-[1-9]' | grep -iv '\.sign' | sed 's|[()]| |g' | sed 's| |\n|g' | grep -i '^https:' | sort -V | tail -n 1)"
    _cryptsetup_ver="$(echo ${_link} | sed 's|/|\n|g' | grep -i '^cryptsetup-[1-9].*\.tar.xz' | sed -e 's|cryptsetup-||g' -e 's|\.tar.*||g')"
    wget -c -t 9 -T 9 "https://www.kernel.org/pub/linux/utils/cryptsetup/v${_cryptsetup_ver%.*}/cryptsetup-${_cryptsetup_ver}.tar.xz"
    tar -xof cryptsetup-*.tar*
    sleep 1
    rm -f cryptsetup-*.tar*
    cd cryptsetup*
    LDFLAGS=''
    LDFLAGS="${_ORIG_LDFLAGS}"; export LDFLAGS
    #LDFLAGS="${_ORIG_LDFLAGS}"' -Wl,-rpath,/usr/lib/x86_64-linux-gnu/cryptsetup/private'; export LDFLAGS
    ./configure \
    --build=x86_64-linux-gnu \
    --host=x86_64-linux-gnu \
    --enable-shared \
    --enable-static \
    --prefix=/usr \
    --sbindir=/usr/sbin \
    --bindir=/usr/bin \
    --libdir=/usr/lib/x86_64-linux-gnu \
    --includedir=/usr/include \
    --sysconfdir=/etc \
    --enable-libargon2 \
    --with-plain-hash=sha512 \
    --with-plain-keybits=512 \
    --with-luks1-hash=sha512 \
    --with-luks1-keybits=512 \
    --with-luks2-keyslot-keybits=512 \
    --with-loopaes-keybits=512 \
    --with-verity-hash=sha512 \
    --with-passphrase-size-max=1024 \
    --with-keyfile-size-maxkb=16384 \
    --with-verity-data-block=8192 \
    --with-verity-hash-block=8192 \
    --with-crypto_backend=openssl \
    --with-luks2-lock-path=/run/cryptsetup \
    --with-luks2-lock-dir-perms=0700 \
    --with-default-luks-format=LUKS2
    make all -j2
    rm -fr /tmp/cryptsetup
    sleep 1
    make install DESTDIR=/tmp/cryptsetup
    cd /tmp/cryptsetup
    rm -f usr/lib/x86_64-linux-gnu/libcryptsetup.la
    rm -f usr/lib/x86_64-linux-gnu/cryptsetup/libcryptsetup-token-ssh.la
    _strip_files
    install -m 0755 -d usr/lib/x86_64-linux-gnu/cryptsetup
    cp -afr /usr/lib/x86_64-linux-gnu/cryptsetup/private usr/lib/x86_64-linux-gnu/cryptsetup/
    cp -afr usr/lib/x86_64-linux-gnu/libcryptsetup.so* usr/lib/x86_64-linux-gnu/cryptsetup/private/
    cp -afr usr/lib/x86_64-linux-gnu/cryptsetup/libcryptsetup-token-ssh.so* usr/lib/x86_64-linux-gnu/cryptsetup/private/
    #patchelf --add-rpath '$ORIGIN/../lib/x86_64-linux-gnu/cryptsetup/private' usr/sbin/cryptsetup
    if [[ -d usr/sbin ]]; then
        find usr/sbin/ -type f -exec file '{}' \; | sed -n -e 's/^\(.*\):[  ]*ELF.*, .*stripped.*/\1/p' | xargs --no-run-if-empty -I '{}' patchelf --add-rpath '$ORIGIN/../lib/x86_64-linux-gnu/cryptsetup/private' '{}'
    fi
    if [[ -d usr/bin ]]; then
        find usr/bin/ -type f -exec file '{}' \; | sed -n -e 's/^\(.*\):[  ]*ELF.*, .*stripped.*/\1/p' | xargs --no-run-if-empty -I '{}' patchelf --add-rpath '$ORIGIN/../lib/x86_64-linux-gnu/cryptsetup/private' '{}'
    fi
    patchelf --add-rpath '$ORIGIN' usr/lib/x86_64-linux-gnu/cryptsetup/private/libcryptsetup-token-ssh.so
    patchelf --add-rpath '$ORIGIN' $(readlink -f usr/lib/x86_64-linux-gnu/cryptsetup/private/libcryptsetup.so)
    rm -fr var
    rm -fr lib
    rm -fr run
    echo
    sleep 2
    tar -Jcvf /tmp/cryptsetup-"${_cryptsetup_ver}"-1_ub2204_amd64.tar.xz *
    echo
    sleep 2
    cd /tmp
    openssl dgst -r -sha256 cryptsetup-"${_cryptsetup_ver}"-1_ub2204_amd64.tar.xz | sed 's|\*| |g' > cryptsetup-"${_cryptsetup_ver}"-1_ub2204_amd64.tar.xz.sha256
    rm -fr "${_tmp_dir}"
    rm -fr /tmp/cryptsetup
    /sbin/ldconfig
}

############################################################################

rm -fr /usr/lib/x86_64-linux-gnu/cryptsetup/private

_build_zlib
_build_openssl33
_build_cryptsetup

echo
echo " build cryptsetup v${_cryptsetup_ver} ub2204 done"
echo
exit
