# Copyright (c) 2020 Tailscale Inc & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

DEBUG_APK=tailscale-debug.apk
RELEASE_AAB=tailscale-release.aab
APPID=com.tailscale.ipn
AAR=android/libs/ipn.aar
KEYSTORE=tailscale.jks
KEYSTORE_ALIAS=tailscale
TAILSCALE_VERSION=$(shell ./version/tailscale-version.sh 200)
OUR_VERSION=$(shell git describe --dirty --exclude "*" --always --abbrev=200)
TAILSCALE_VERSION_ABBREV=$(shell ./version/tailscale-version.sh 11)
OUR_VERSION_ABBREV=$(shell git describe --dirty --exclude "*" --always --abbrev=11)
VERSION_LONG=$(TAILSCALE_VERSION_ABBREV)-g$(OUR_VERSION_ABBREV)
# Extract the long version build.gradle's versionName and strip quotes.
VERSIONNAME=$(patsubst "%",%,$(lastword $(shell grep versionName android/build.gradle)))
# Extract the x.y.z part for the short version.
VERSIONNAME_SHORT=$(shell echo $(VERSIONNAME) | cut -d - -f 1)
TAILSCALE_COMMIT=$(shell echo $(TAILSCALE_VERSION) | cut -d - -f 2 | cut -d t -f 2)
# Extract the version code from build.gradle.
VERSIONCODE=$(lastword $(shell grep versionCode android/build.gradle))
VERSIONCODE_PLUSONE=$(shell expr $(VERSIONCODE) + 1)

# When you update TOOLCHAINREV, also update TOOLCHAINWANT
TOOLCHAINREV=097d1284f961420864b68df0ad332f11824a3424
TOOLCHAINDIR=${HOME}/.cache/tailscale-android-go-$(TOOLCHAINREV)
TOOLCHAINSUM=$(shell find $(TOOLCHAINDIR) -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | cut -d" " -f1)
TOOLCHAINWANT=9b409fcc9a6c5682b93fe8804616e4362800294c
export PATH := $(TOOLCHAINDIR)/go/bin:$(PATH)

all: $(APK)

tag_release:
	sed -i'.bak' 's/versionCode [[:digit:]]\+/versionCode $(VERSIONCODE_PLUSONE)/' android/build.gradle
	sed -i'.bak' 's/versionName .*/versionName "$(VERSION_LONG)"/' android/build.gradle
	git commit -sm "android: bump version code" android/build.gradle
	git tag -a "$(VERSION_LONG)"

toolchain:
ifneq ($(TOOLCHAINWANT),$(TOOLCHAINSUM))
	@echo want: $(TOOLCHAINWANT)
	@echo got: $(TOOLCHAINSUM)
	rm -rf ${HOME}/.cache/tailscale-android-go-*
	$(eval tmpfile=$(shell mktemp --suffix=.tgz))
	wget https://github.com/tailscale/go/releases/download/build-$(TOOLCHAINREV)/linux.tar.gz -O "$(tmpfile)"
	mkdir -p $(TOOLCHAINDIR)
	tar xzf $(tmpfile) -C $(TOOLCHAINDIR)
	rm $(tmpfile)
endif

$(DEBUG_APK): toolchain
	mkdir -p android/libs
	go run gioui.org/cmd/gogio -buildmode archive -target android -appid $(APPID) -o $(AAR) github.com/tailscale/tailscale-android/cmd/tailscale
	(cd android && ./gradlew assemblePlayDebug)
	mv android/build/outputs/apk/play/debug/android-play-debug.apk $@
	
# This target is also used by the F-Droid builder.
release_aar: toolchain
release_aar:
	mkdir -p android/libs
	go run gioui.org/cmd/gogio -ldflags "-X tailscale.com/version.Long=$(VERSIONNAME) -X tailscale.com/version.Short=$(VERSIONNAME_SHORT) -X tailscale.com/version.GitCommit=$(TAILSCALE_COMMIT) -X tailscale.com/version.ExtraGitCommit=$(OUR_VERSION)" -tags xversion -buildmode archive -target android -appid $(APPID) -o $(AAR) github.com/tailscale/tailscale-android/cmd/tailscale

$(RELEASE_AAB): release_aar
	(cd android && ./gradlew bundlePlayRelease)
	mv ./android/build/outputs/bundle/playRelease/android-play-release.aab $@

release: $(RELEASE_AAB)
	jarsigner -sigalg SHA256withRSA -digestalg SHA-256 -keystore $(KEYSTORE) $(RELEASE_AAB) $(KEYSTORE_ALIAS)

install: $(DEBUG_APK)
	adb install -r $(DEBUG_APK)

dockershell:
	docker build -t tailscale-android .
	docker run -v $(CURDIR):/build/tailscale-android -it --rm tailscale-android

clean:
	rm -rf android/build $(RELEASE_AAB) $(DEBUG_APK) $(AAR)

.PHONY: all clean install $(DEBUG_APK) $(RELEASE_AAB) release_aar release bump_version dockershell
