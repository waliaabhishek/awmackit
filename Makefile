.PHONY: bootstrap validate test build build-local

bootstrap:
	./Scripts/bootstrap.sh

validate:
	./Scripts/validate.sh

test:
	cd Packages/LinkRouterCore && swift test

build: bootstrap
	xcodebuild -project PowerTools.xcodeproj -scheme PowerTools -configuration Debug -derivedDataPath DerivedData build

build-local:
	./Scripts/build-local.sh
