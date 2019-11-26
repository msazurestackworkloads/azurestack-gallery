.PHONY: build-encoder-k8s
build-encoder-k8s: 
	go build -o _out/encoder-k8s makeScripts/encode/main.go

.PHONY: build-encoder-registry
build-encoder-registry: 
	go build -o _out/encoder-registry makeScripts/encode/main.go

.PHONY: clean
clean: 
	rm -rf _out

.PHONY: generate
generate: clean build-encoder-k8s build-encoder-registry
	makeScripts/generate.sh

# Windows only
.PHONY: release
release: clean
	powershell makeScripts/release.ps1
