# Как запустить пример и что прогнать перед коммитом.
#
# `make` без аргументов покажет список целей.
#
# Токены читаются из файла вне репозитория — по умолчанию ~/.tracer-env,
# см. docs/live-verification-plan.md, шаг 0.3. Другой файл:
#
#     make example-android TRACER_ENV=~/.tracer-env.work

SHELL := /bin/bash

TRACER_ENV ?= $(HOME)/.tracer-env
EXAMPLE := packages/apptracer_flutter/example
RELEASE ?= 1.0.0

# Когда подключено больше одного устройства, flutter не выбирает сам.
#     make example-live-check DEVICE=emulator-5554
DEVICE ?=
DEVICE_ARG := $(if $(DEVICE),-d $(DEVICE),)

# `set -a` не нужен: файл уже состоит из export-строк.
LOAD_ENV := source $(TRACER_ENV)

.DEFAULT_GOAL := help

.PHONY: help bootstrap check format analyze test tokens \
	example-android example-android-debug example-ios example-web example-desktop \
	example-live-check example-live-check-ios \
	apk apk-dart-symbols ios-dsym web-release web-sourcemaps logcat pod-install clean

help: ## Показать этот список
	@echo "Цели:"
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN { FS = ":.*?## " } { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }'
	@echo
	@echo "Токены: $(TRACER_ENV)"

# --- окружение ---------------------------------------------------------------

$(TRACER_ENV):
	@echo "Нет файла $(TRACER_ENV) с токенами." >&2
	@echo "См. docs/live-verification-plan.md, шаг 0.3." >&2
	@exit 1

# Показывает только префикс: токен целиком в терминале — это токен в истории
# терминала, в скриншотах и в логах записи экрана.
tokens: $(TRACER_ENV) ## Проверить, какие токены подхватились
	@$(LOAD_ENV) && \
		mask() { if [ -z "$$1" ]; then echo '<пусто>'; else echo "$${1:0:6}…"; fi; }; \
		printf '  %-24s %s\n' \
			'TRACER_APP_TOKEN'     "$$(mask "$${TRACER_APP_TOKEN:-}")" \
			'TRACER_PLUGIN_TOKEN'  "$$(mask "$${TRACER_PLUGIN_TOKEN:-}")" \
			'TRACER_IOS_APP_TOKEN' "$$(mask "$${TRACER_IOS_APP_TOKEN:-}")" \
			'TRACER_JS_PLUGIN_TOKEN' "$$(mask "$${TRACER_JS_PLUGIN_TOKEN:-}")" \
			'TRACER_DSN'           "$$(mask "$${TRACER_DSN:-}")"

# Android-плагин Tracer валит сборку без обоих токенов — падаем раньше и понятнее.
.PHONY: require-android-tokens
require-android-tokens: $(TRACER_ENV)
	@$(LOAD_ENV) && \
		if [ -z "$${TRACER_APP_TOKEN:-}" ] || [ -z "$${TRACER_PLUGIN_TOKEN:-}" ]; then \
			echo "TRACER_APP_TOKEN и TRACER_PLUGIN_TOKEN должны быть заполнены в $(TRACER_ENV)." >&2; \
			echo "Токены Android-проекта: консоль Tracer → Настройки." >&2; \
			exit 1; \
		fi

# --- пример ------------------------------------------------------------------

example-android: require-android-tokens ## Пример на Android: release, события реально уходят
	@$(LOAD_ENV) && cd $(EXAMPLE) && flutter run $(DEVICE_ARG) --release -Ptracer.enabled=true

# События уходят и из debug: TracerHostApplication примера выставляет
# CoreTracerConfiguration.setDebugUpload(true), без которого Android SDK Tracer
# из debug-сборки не шлёт ничего. См. docs/live-verification-plan.md, шаг 3.2.
example-android-debug: require-android-tokens ## То же в debug: hot reload и логи Dart
	@$(LOAD_ENV) && cd $(EXAMPLE) && flutter run $(DEVICE_ARG) -Ptracer.enabled=true

# На iOS токен приходит из Dart, а не из сборочного плагина, как на Android.
example-ios: $(TRACER_ENV) ## Пример на iOS
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		flutter run --dart-define=TRACER_APP_TOKEN=$$TRACER_IOS_APP_TOKEN

# Web с 26.08.2026 говорит с собственным API Tracer и хочет appToken
# JS-проекта. Десктоп по-прежнему на транспорте Sentry и хочет DSN.
example-web: $(TRACER_ENV) ## Пример в Chrome (собственный API Tracer)
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		flutter run -d chrome --dart-define=TRACER_APP_TOKEN=$$TRACER_JS_APP_TOKEN

example-desktop: $(TRACER_ENV) ## Пример на macOS (транспорт Sentry)
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		flutter run -d macos --dart-define=TRACER_DSN=$$TRACER_DSN

# Гоняет integration_test на подключённом устройстве. Нужен именно drive, а не
# `flutter test`: только он умеет передавать -P в Gradle.
example-live-check: require-android-tokens ## Автопрогон сценариев проверок на Android
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		flutter drive $(DEVICE_ARG) \
			--driver=test_driver/integration_test.dart \
			--target=integration_test/live_verification_test.dart \
			-Ptracer.enabled=true

# На iOS токен идёт из Dart, а не из сборочного плагина, поэтому гредловых
# флагов здесь нет и цель проще android-ной.
example-live-check-ios: $(TRACER_ENV) ## Автопрогон сценариев проверок на iOS
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		flutter drive $(DEVICE_ARG) \
			--driver=test_driver/integration_test.dart \
			--target=integration_test/live_verification_test.dart \
			--dart-define=TRACER_APP_TOKEN=$$TRACER_IOS_APP_TOKEN

logcat: ## Логи плагина с подключённого Android-устройства
	adb logcat -s apptracer_flutter

pod-install: ## Переустановить поды примера (после правок Podfile)
	cd $(EXAMPLE)/ios && pod install

# --- сборки релизного вида ---------------------------------------------------

apk: require-android-tokens ## Обфусцированный release-APK + сверка build id символов
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		flutter build apk --release -Ptracer.enabled=true \
			--obfuscate --split-debug-info=build/symbols && \
		../../../tool/verify_build_id.sh

# docs/symbolication.md, находка 2: символы Dart уезжают в Tracer каналом
# нативных символов — и это сейчас ничего не даёт, кадры всё равно не
# символизируются. Цель оставлена, чтобы перепроверить, если вендор починит. Первая сборка нужна только чтобы получить файл символов,
# вторая — чтобы залить подставной libapp.so; forceUploadNativeSymbols при этом
# не нужен. Прочитайте документ перед запуском — файл символов несёт абсолютные
# пути со сборочной машины и все имена символов Dart.
apk-dart-symbols: require-android-tokens ## APK + загрузка Dart-символов через additionalLibrariesPath
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		flutter build apk --release -Ptracer.enabled=true \
			--obfuscate --split-debug-info=build/symbols && \
		../../../tool/prepare_dart_symbols.sh build/symbols && \
		DART_SPLIT_DEBUG_INFO="$$PWD/build/symbols/tracer-upload" \
			flutter build apk --release -Ptracer.enabled=true \
				--obfuscate --split-debug-info=build/symbols

ios-dsym: $(TRACER_ENV) ## Загрузить dSYM примера в Tracer (DSYM_DIR=…)
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		TRACER_PLUGIN_TOKEN=$$TRACER_IOS_PLUGIN_TOKEN \
			../../../tool/upload_ios_dsym.sh \
				"$(if $(DSYM_DIR),$(DSYM_DIR),build/ios/Release-iphoneos)" \
				$(RELEASE) 1

# Токен нужен и здесь: без него собранное приложение молчит, а сорсмапы
# грузятся к сборке, которой нечего отправлять.
web-release: $(TRACER_ENV) ## Release-сборка web с сорсмапами
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		flutter build web --release --source-maps \
			--dart-define=TRACER_APP_TOKEN=$$TRACER_JS_APP_TOKEN

web-sourcemaps: web-release $(TRACER_ENV) ## Собрать web и залить сорсмапы (RELEASE=1.0.0)
	@$(LOAD_ENV) && cd $(EXAMPLE) && \
		TRACER_PLUGIN_TOKEN=$$TRACER_JS_PLUGIN_TOKEN \
			../../../tool/upload_web_sourcemaps.sh $(RELEASE)

# --- разработка --------------------------------------------------------------

bootstrap: ## pub get во всех пакетах монорепозитория
	./tool/bootstrap.sh

check: ## Всё, что гоняет CI, в том же порядке
	./tool/check.sh

format: ## dart format по всем пакетам
	dart format packages

analyze: ## flutter analyze в пакете-фасаде и примере
	cd packages/apptracer_flutter && flutter analyze --fatal-infos
	cd $(EXAMPLE) && flutter analyze --fatal-infos

test: ## Тесты пакета-фасада и примера
	cd packages/apptracer_flutter && flutter test --reporter=compact
	cd $(EXAMPLE) && flutter test --reporter=compact

clean: ## flutter clean в примере
	cd $(EXAMPLE) && flutter clean
