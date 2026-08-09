.PHONY: bootstrap validate test build build-local

bootstrap:
	./Scripts/bootstrap.sh

validate:
	./Scripts/validate.sh

test:
	cd Packages/LinkRouterCore && swift test

build:
	./Scripts/build-local.sh

build-local:
	./Scripts/build-local.sh
