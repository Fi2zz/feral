# Feral —— 生成工程、跑模拟器测试、装到真机。
#
#   make help          看这份清单
#   make test          模拟器上跑全部用例
#   make run           装到已连接的手机上并拉起来
#
# 签名团队默认从钥匙串里的「Apple Development:」身份自动取，可覆盖：
#   make run DEVELOPMENT_TEAM=XXXXXXXXXX
#   或写进 local.mk（已 gitignore）。

.DEFAULT_GOAL := help
SHELL := /bin/bash
# 管道要带出失败：xcodebuild | tail 5 那种写法否则永远返回 0，编译挂了也照样往下走。
.SHELLFLAGS := -o pipefail -c

SCHEME    := Feral
BUNDLE_ID := com.fi2zz.feral
CONFIG    ?= Debug
SIM_NAME  ?= iPhone 17
DERIVED   := .build/DerivedData
APP_DIR   := $(DERIVED)/Build/Products/$(CONFIG)-iphoneos
APP       := $(APP_DIR)/$(SCHEME).app
SIM_APP   := $(DERIVED)/Build/Products/$(CONFIG)-iphonesimulator/$(SCHEME).app

# 联调用的假 Kimi 服务。
# 模拟器：默认绑 127.0.0.1，模拟器与 Mac 共享网络，直接能连。
# 真机：要绑 0.0.0.0（make mock MOCK_HOST=0.0.0.0），地址填 Mac 的局域网地址：
#   make run-mock-device MOCK_URL=http://$(make lan-ip 2>/dev/null):8099/v1
MOCK_PORT ?= 8099
MOCK_HOST ?= 127.0.0.1
MOCK_URL  ?= http://127.0.0.1:$(MOCK_PORT)/v1

# 本机专属配置（DEVELOPMENT_TEAM、DEVICE 等），不存在也不影响 make help / test。
-include local.mk

# XcodeGen 的本机专属配置（目前只有签名团队），gitignore，重新生成工程也丢不了签名。
TEAM_YML := project.local.yml

# 没写死就问钥匙串要第一个开发签名身份的 Team ID（形如 9WEANLD96Z）。
# 写法上避开圆括号：$(shell) 里出现裸的右括号会把调用提前截断。
IDENTITY_TEAM := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -m1 'Apple Development:' \
	| awk '{gsub(/[^A-Z0-9]/,"",$$NF); print $$NF}')

# 优先用「最近一张描述文件所属的团队」：那才是 Xcode 当前登录账号真正能签的团队。
# 钥匙串里可能留着旧个人团队的证书，只认它会撞上 No Account for Team。
PROFILE_TEAM := $(shell ls -t ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision 2>/dev/null \
	| head -1 \
	| xargs -I{} security cms -D -i {} 2>/dev/null \
	| plutil -extract TeamIdentifier.0 raw -o - - 2>/dev/null)

DEVELOPMENT_TEAM ?= $(or $(PROFILE_TEAM),$(IDENTITY_TEAM))

# 没指定就挑第一台在线的 iPhone。
DEVICE ?= $(shell xcrun devicectl list devices 2>/dev/null \
	| awk '$$3 ~ /^[0-9A-F-]{36}$$/ && $$0 ~ /iPhone/ && $$4 !~ /unavailable/ { print $$3; exit }')

.PHONY: help generate build test test-llm mock mock-fail device-list lan-ip run install run-console run-mock run-mock-device clean

help: ## 列出所有目标
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

generate: $(TEAM_YML) ## project.yml → Feral.xcodeproj（工程无变化时跳过，免得重生成冲掉 Xcode 里的状态）
	@mkdir -p .build
	@{ shasum project.yml $(TEAM_YML); find Feral FeralTests -type f | sort; } > .build/manifest.new
	@if [ -f $(SCHEME).xcodeproj/project.pbxproj ] && cmp -s .build/manifest.new .build/manifest.cur; then \
		echo '工程无变化，跳过 xcodegen（要强制重建：rm -rf Feral.xcodeproj 后再跑）'; \
	else \
		xcodegen generate && mv .build/manifest.new .build/manifest.cur; \
	fi

# 首次生成时把自动推断到的签名团队写进去；推断不到就留个注释模板。
$(TEAM_YML):
	@if [ -n '$(DEVELOPMENT_TEAM)' ]; then \
		printf 'targets:\n  Feral:\n    settings:\n      base:\n        DEVELOPMENT_TEAM: %s\n' '$(DEVELOPMENT_TEAM)' > $(TEAM_YML); \
		echo '已把签名团队 $(DEVELOPMENT_TEAM) 写进 $(TEAM_YML)（不进仓库）'; \
	else \
		printf '# 本机专属 XcodeGen 配置（不进仓库）：签名团队写这里，重新生成工程也丢不了\n# targets:\n#   Feral:\n#     settings:\n#       base:\n#         DEVELOPMENT_TEAM: XXXXXXXXXX\n{}\n' > $(TEAM_YML); \
		echo '已生成 $(TEAM_YML) 模板，建议填入签名团队'; \
	fi

build: generate ## 编译到模拟器用的 .app
	@xcodebuild build \
		-project $(SCHEME).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination 'platform=iOS Simulator,name=$(SIM_NAME)' \
		-derivedDataPath $(DERIVED) \
		| tail -5

test: generate ## 模拟器上跑全部用例
	@xcodebuild test \
		-project $(SCHEME).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination 'platform=iOS Simulator,name=$(SIM_NAME)' \
		-derivedDataPath $(DERIVED) \
		| grep -E 'error:|✘|Test run with|Executed .* tests' || true

device-list: ## 列出 devicectl 能看到的设备
	@xcrun devicectl list devices
	@echo '签名团队：$(DEVELOPMENT_TEAM)'

mock: ## 起本机假 Kimi 服务（前台，日志直接看）
	@python3 tools/mock-kimi/mock_kimi.py --port $(MOCK_PORT) --host $(MOCK_HOST)

mock-fail: ## 同上，但固定返回 401，用来验 App 的错误提示
	@python3 tools/mock-kimi/mock_kimi.py --port $(MOCK_PORT) --host $(MOCK_HOST) --fail 401

mock-lan: ## 真机联调用：绑 0.0.0.0，手机才连得到
	@echo "手机填这个地址：http://$$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1):$(MOCK_PORT)/v1"
	@python3 tools/mock-kimi/mock_kimi.py --port $(MOCK_PORT) --host 0.0.0.0

lan-ip: ## 打印 Mac 的局域网地址
	@ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "取不到，试 ifconfig"

test-llm: generate ## 起假服务并跑 LLM 联调用例
	@set -e; \
	python3 tools/mock-kimi/mock_kimi.py --port $(MOCK_PORT) > .build/mock-kimi.log 2>&1 & \
	mock=$$!; \
	trap 'kill $$mock 2>/dev/null || true' EXIT; \
	sleep 1; \
	xcodebuild test \
		-project $(SCHEME).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination 'platform=iOS Simulator,name=$(SIM_NAME)' \
		-derivedDataPath $(DERIVED) \
		| grep -E 'error:|✘|Test run with' || true; \
	echo '假服务收到的请求：'; tail -30 .build/mock-kimi.log

run-mock: generate build ## 模拟器：装好并指到本机假服务
	@xcrun simctl install booted $(SIM_APP)
	@SIMCTL_CHILD_KIMI_BASE_URL=$(MOCK_URL) xcrun simctl launch booted $(BUNDLE_ID)
	@echo '指到 $(MOCK_URL) 了。假服务没起就先 make mock。'

run-mock-device: install ## 真机：指到 MOCK_URL（要填 Mac 的局域网地址）
	@xcrun devicectl device process launch \
		--device $(DEVICE) \
		--environment-variables "{\"KIMI_BASE_URL\":\"$(MOCK_URL)\"}" \
		$(BUNDLE_ID)
	@echo '指到 $(MOCK_URL) 了。真机连不到 127.0.0.1，用 Mac 的局域网地址。'

run: ## 编译 → 安装 → 启动到已连接的手机
	@$(MAKE) --no-print-directory install
	@xcrun devicectl device process launch --device $(DEVICE) $(BUNDLE_ID)

run-console: ## 同 run，但把 App 的 stdout 打到终端
	@$(MAKE) --no-print-directory install
	@xcrun devicectl device process launch --device $(DEVICE) $(BUNDLE_ID) --console

install: generate ## 只编译并安装，不启动
	@test -n "$(DEVICE)" || { echo '没找到在线的 iPhone，先插线或 make device-list 看看'; exit 1; }
	@test -n "$(DEVELOPMENT_TEAM)" || { echo '取不到开发签名 Team ID，写进 local.mk 或 make run DEVELOPMENT_TEAM=XXXXXXXXXX'; exit 1; }
	@xcodebuild build \
		-project $(SCHEME).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination 'id=$(DEVICE)' \
		-derivedDataPath $(DERIVED) \
		DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
		-allowProvisioningUpdates \
		| tail -20
	@test -d $(APP) || { echo '没编出 .app，看上面的签名报错（No Account for Team 就去 Xcode → Settings → Accounts 登录）'; exit 1; }
	@xcrun devicectl device install app --device $(DEVICE) $(APP)
	@echo '装好了：$(APP)'

clean: ## 删掉构建产物（.build/ 与生成的 xcodeproj）
	@rm -rf .build $(SCHEME).xcodeproj
	@echo 'cleaned'
