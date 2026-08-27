# Запуск примера, когда эта папка открыта отдельным проектом.
#
# Вся логика — в Makefile корня монорепозитория, здесь только короткие имена:
# `make android` вместо `make -C ../../.. example-android`. Дублировать команды
# в двух файлах нельзя: разъедутся ровно в тот день, когда это будет дороже
# всего заметить.

ROOT := ../../..

# Пробрасывается в корневой Makefile через окружение:
#     make live-check DEVICE=emulator-5554
DEVICE ?=
export DEVICE

.DEFAULT_GOAL := help
.PHONY: help android android-debug ios web live-check live-check-ios logcat tokens \
	apk apk-dart-symbols web-release web-sourcemaps analyze test clean

help: ## Показать этот список
	@echo "Цели (эквивалент make <example-*> из корня репозитория):"
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN { FS = ":.*?## " } { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }'

android: ## Android: release, события реально уходят
	@$(MAKE) -C $(ROOT) example-android

android-debug: ## Android в debug: hot reload и логи Dart
	@$(MAKE) -C $(ROOT) example-android-debug

ios: ## iOS
	@$(MAKE) -C $(ROOT) example-ios

web: ## Chrome (собственный API Tracer)
	@$(MAKE) -C $(ROOT) example-web

live-check-ios: ## Автопрогон сценариев проверок на iOS
	@$(MAKE) -C $(ROOT) example-live-check-ios

live-check: ## Автопрогон сценариев проверок на Android
	@$(MAKE) -C $(ROOT) example-live-check

logcat: ## Логи плагина с подключённого Android-устройства
	@$(MAKE) -C $(ROOT) logcat

tokens: ## Проверить, какие токены подхватились
	@$(MAKE) -C $(ROOT) tokens

apk: ## Обфусцированный release-APK + сверка build id символов
	@$(MAKE) -C $(ROOT) apk

apk-dart-symbols: ## APK + загрузка Dart-символов через additionalLibrariesPath
	@$(MAKE) -C $(ROOT) apk-dart-symbols

web-release: ## Release-сборка web с сорсмапами
	@$(MAKE) -C $(ROOT) web-release

web-sourcemaps: ## Собрать web и залить сорсмапы (RELEASE=1.0.0)
	@$(MAKE) -C $(ROOT) web-sourcemaps

analyze: ## flutter analyze
	flutter analyze --fatal-infos

test: ## Тесты примера
	flutter test --reporter=compact

clean: ## flutter clean
	flutter clean
