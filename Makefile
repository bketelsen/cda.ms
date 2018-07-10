# import path is where your repository can be found.
# To import subpackages, always prepend the full import path.
# If you change this, run `make clean`. Read more: https://git.io/vM7zV
IMPORT_PATH := github.com/bketelsen/cda
DOCKER_IMAGE := cda
build_dir := $(CURDIR)/bin
dist_dir := $(CURDIR)/dist
exec := $(DOCKER_IMAGE)
github_repo := bketelsen/cda.ms

# comment this line out for quieter things
V := 1 # When V is set, print commands and build progress.

# Space separated patterns of packages to skip in list, test, format.
IGNORED_PACKAGES := /vendor/

.PHONY: all
all: test build

.PHONY: safebuild
# safebuild builds inside a docker container with no clingons from your $GOPATH
safebuild:
	@echo "Building..."
	$Q docker build -t $(DOCKER_IMAGE):$(VERSION) .

.PHONY: build
build:
	@echo "Building..."
	$Q rm -f $(GOPATH)/bin/$(DOCKER_IMAGE)
	$Q go install $(if $V,-v) $(VERSION_FLAGS) $(IMPORT_PATH)

.PHONY: tags
tags:
	@echo "Listing tags..."
	$Q @git tag

.PHONY: release
release: clean-dist build $(GOPATH)/bin/goreleaser
	goreleaser


### Code not in the repository root? Another binary? Add to the path like this.
# .PHONY: otherbin
# otherbin: .GOPATH/.ok
#   $Q go install $(if $V,-v) $(VERSION_FLAGS) $(IMPORT_PATH)/cmd/otherbin

##### ^^^^^^ EDIT ABOVE ^^^^^^ #####

##### =====> Utility targets <===== #####

.PHONY: clean test list cover format docker deps

deps: setup
	@echo "Ensuring Dependencies..."
	$Q go env
	$Q dep ensure

docker:
	@echo "Docker Build..."
	$Q docker build -t $(DOCKER_IMAGE) .

clean: clean-dist clean-build
	@echo "Clean..."
	$Q rm -rf bin

.PHONY: clean-build
clean-build:
	@echo "Removing cross-compilation files"
	rm -rf $(build_dir)

.PHONY: clean-dist
clean-dist:
	@echo "Removing distribution files"
	rm -rf $(dist_dir)

test:
	@echo "Testing..."
	$Q go test $(if $V,-v) -i -race $(allpackages) # install -race libs to speed up next run
ifndef CI
	@echo "Testing Outside CI..."
	$Q go vet $(allpackages)
	$Q GODEBUG=cgocheck=2 go test -race $(allpackages)
else
	@echo "Testing in CI..."
	$Q mkdir -p test
	$Q ( go vet $(allpackages); echo $$? ) | \
       tee test/vet.txt | sed '$$ d'; exit $$(tail -1 test/vet.txt)
	$Q ( GODEBUG=cgocheck=2 go test -v -race $(allpackages); echo $$? ) | \
       tee test/output.txt | sed '$$ d'; exit $$(tail -1 test/output.txt)
endif

list:
	@echo "List..."
	@echo $(allpackages)

cover: $(GOPATH)/bin/gocovmerge
	@echo "Coverage Report..."
	@echo "NOTE: make cover does not exit 1 on failure, don't use it to check for tests success!"
	$Q rm -f .GOPATH/cover/*.out cover/all.merged
	$(if $V,@echo "-- go test -coverpkg=./... -coverprofile=cover/... ./...")
	@for MOD in $(allpackages); do \
        go test -coverpkg=`echo $(allpackages)|tr " " ","` \
            -coverprofile=cover/unit-`echo $$MOD|tr "/" "_"`.out \
            $$MOD 2>&1 | grep -v "no packages being tested depend on"; \
    done
	$Q gocovmerge cover/*.out > cover/all.merged
ifndef CI
	@echo "Coverage Report..."
	$Q go tool cover -html .GOPATH/cover/all.merged
else
	@echo "Coverage Report In CI..."
	$Q go tool cover -html .GOPATH/cover/all.merged -o .GOPATH/cover/all.html
endif
	@echo ""
	@echo "=====> Total test coverage: <====="
	@echo ""
	$Q go tool cover -func .GOPATH/cover/all.merged

format: $(GOPATH)/bin/goimports
	@echo "Formatting..."
	$Q find . -iname \*.go | grep -v \
        -e "^$$" $(addprefix -e ,$(IGNORED_PACKAGES)) | xargs goimports -w

##### =====> Internals <===== #####

.PHONY: setup
setup: clean
	@echo "Setup..."
	if ! grep "/bin" .gitignore > /dev/null 2>&1; then \
        echo "/bin" >> .gitignore; \
    fi
	if ! grep "/dist" .gitignore > /dev/null 2>&1; then \
        echo "/dist" >> .gitignore; \
    fi
	if ! grep "/build" .gitignore > /dev/null 2>&1; then \
        echo "/build" >> .gitignore; \
    fi
	mkdir -p cover
	mkdir -p bin
	mkdir -p test
	go get -u github.com/golang/dep/cmd/dep
	go get github.com/wadey/gocovmerge
	go get golang.org/x/tools/cmd/goimports
	go get github.com/mitchellh/gox
	go get github.com/goreleaser/goreleaser

VERSION          := $(shell git describe --tags --always --dirty="-dev")
DATE             := $(shell date -u '+%Y-%m-%d-%H:%M UTC')
VERSION_FLAGS    := -ldflags='-X "main.Version=$(VERSION)" -X "main.BuildTime=$(DATE)"'

# assuming go 1.9 here!!
_allpackages = $(shell go list ./...) 

# memoize allpackages, so that it's executed only once and only if used
allpackages = $(if $(__allpackages),,$(eval __allpackages := $$(_allpackages)))$(__allpackages)


Q := $(if $V,,@)


$(GOPATH)/bin/gocovmerge:
	@echo "Checking Coverage Tool Installation..."
	@test -d $(GOPATH)/src/github.com/wadey/gocovmerge || \
        { echo "Vendored gocovmerge not found, try running 'make setup'..."; exit 1; }
	$Q go install github.com/wadey/gocovmerge
$(GOPATH)/bin/goimports:
	@echo "Checking Import Tool Installation..."
	@test -d $(GOPATH)/src/golang.org/x/tools/cmd/goimports || \
        { echo "Vendored goimports not found, try running 'make setup'..."; exit 1; }
	$Q go install golang.org/x/tools/cmd/goimports

$(GOPATH)/bin/goreleaser:
	go get -u github.com/goreleaser/goreleaser
