# Atalhos de desenvolvimento do Tomafoco.
.PHONY: test test-domain test-application test-infra project lint open help release release-dry sparkle-keys

help:
	@echo "Alvos:"
	@echo "  make test           - roda os testes de todos os pacotes SPM"
	@echo "  make test-domain    - testes do núcleo puro (roda até em Linux CI)"
	@echo "  make project        - gera Tomafoco.xcodeproj via XcodeGen"
	@echo "  make lint           - roda SwiftLint"
	@echo "  make open           - gera o projeto e abre no Xcode"
	@echo "  make release        - assina, notariza e gera o DMG (ver docs/release.md)"
	@echo "  make release-dry    - empacota sem notarizar (teste local)"
	@echo "  make sparkle-keys   - gera/mostra a chave EdDSA das atualizações (1x só)"

test: test-domain test-application test-infra

test-domain:
	cd Packages/TomafocoDomain && swift test

test-application:
	cd Packages/TomafocoApplication && swift test

test-infra:
	cd Packages/TomafocoInfrastructure && swift test

project:
	xcodegen generate

lint:
	swiftlint

open: project
	open Tomafoco.xcodeproj

release:
	./scripts/release.sh

release-dry:
	SKIP_NOTARIZE=1 ./scripts/release.sh

sparkle-keys:
	./scripts/sparkle-generate-keys.sh
