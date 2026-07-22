# Atalhos de desenvolvimento do Tomafoco.
.PHONY: test test-domain test-application test-infra project lint open help

help:
	@echo "Alvos:"
	@echo "  make test           - roda os testes de todos os pacotes SPM"
	@echo "  make test-domain    - testes do núcleo puro (roda até em Linux CI)"
	@echo "  make project        - gera Tomafoco.xcodeproj via XcodeGen"
	@echo "  make lint           - roda SwiftLint"
	@echo "  make open           - gera o projeto e abre no Xcode"

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
