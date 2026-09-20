#!/usr/bin/env bash
# Garante a presença de libxml2.so.2, exigida pelo IBM Db2 clidriver (conector ibm_db dos plugins).
# Ubuntu <= 24.04: fornecida pelo pacote libxml2.
# Ubuntu >= 25.10: o pacote libxml2 passou para a versão 2.14 (libxml2.so.16); instala-se a
# libxml2 2.9 do Ubuntu 24.04 (e sua dependência libicu74) em /usr/local/lib, sem tocar no apt.
#
# Uso: bash scripts/local-dev/ensure-libxml2-compat.sh
# Variáveis: LIB_PREFIX (padrão /usr/local/lib), FORCE_FALLBACK=1 (ignora apt; para testes)
set -euo pipefail

LIB_PREFIX="${LIB_PREFIX:-/usr/local/lib}"
ARCHIVE="${UBUNTU_ARCHIVE:-http://archive.ubuntu.com/ubuntu/pool/main}"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

has_lib() { ldconfig -p 2>/dev/null | grep -q 'libxml2\.so\.2 ' ; }

if [ "${FORCE_FALLBACK:-0}" != "1" ]; then
  if has_lib; then echo "libxml2.so.2 já disponível."; exit 0; fi
  echo "Tentando instalar libxml2 pelo apt..."
  $SUDO apt-get install -y libxml2 >/dev/null 2>&1 || true
  if has_lib; then echo "libxml2.so.2 instalada pelo apt."; exit 0; fi
fi

echo "libxml2.so.2 indisponível no apt; instalando a versão do Ubuntu 24.04 em ${LIB_PREFIX}..."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
latest_deb() { # $1 = subdiretório do pool, $2 = prefixo do arquivo
  curl -fsSL "$ARCHIVE/$1/" | grep -o "href=\"$2[^\"]*_amd64\.deb\"" | sed 's/href="//;s/"$//' \
    | sed 's/_amd64\.deb$//' | sort -V | tail -1 | sed 's/$/_amd64.deb/'
}
for spec in "libx/libxml2 libxml2_2.9.14" "i/icu libicu74_74.2"; do
  dir="${spec% *}"; pre="${spec#* }"
  file="$(latest_deb "$dir" "$pre")"
  [ -n "$file" ] || { echo "Arquivo ${pre}*.deb não encontrado em $ARCHIVE/$dir/" >&2; exit 1; }
  echo "  baixando $file"
  curl -fsSL -o "$tmp/$pre.deb" "$ARCHIVE/$dir/$file"
  dpkg-deb -x "$tmp/$pre.deb" "$tmp/x"
done
$SUDO mkdir -p "$LIB_PREFIX"
$SUDO cp -a "$tmp"/x/usr/lib/x86_64-linux-gnu/libxml2.so.2* "$tmp"/x/usr/lib/x86_64-linux-gnu/libicuuc.so.74* "$tmp"/x/usr/lib/x86_64-linux-gnu/libicudata.so.74* "$LIB_PREFIX"/
$SUDO ldconfig
if has_lib || [ "$LIB_PREFIX" != "/usr/local/lib" ]; then
  echo "libxml2.so.2 instalada em $LIB_PREFIX."
else
  echo "Falha: libxml2.so.2 ainda não localizada pelo ldconfig." >&2; exit 1
fi
