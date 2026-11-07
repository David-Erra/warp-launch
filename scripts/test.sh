#!/bin/bash
# Executa les proves de Warp Launch (swift-testing).
# Amb Swift 6.4.2 de les Command Line Tools i el sistema `swiftbuild`, `swift test` de vegades no carrega
# el connector TestingMacros (vegeu docs/fets-verificats.md). Indicar-ne la carpeta explícitament ho evita.
# La ruta es calcula a partir de la toolchain activa, així que també funciona amb Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
