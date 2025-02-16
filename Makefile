$(VERBOSE).SILENT:
############################# Main targets #############################
ci-build: install proto

# Install dependencies.
install: grpc-install api-linter-install buf-install

# Run all linters and compile proto files.
proto: grpc
########################################################################

##### Variables ######
ifndef GOPATH
GOPATH := $(shell go env GOPATH)
endif

GOBIN := $(if $(shell go env GOBIN),$(shell go env GOBIN),$(GOPATH)/bin)
PATH := $(GOBIN):$(PATH)

COLOR := "\e[1;36m%s\e[0m\n"

# Only prints output if the exit code is non-zero
define silent_exec
    @output=$$($(1) 2>&1); \
    status=$$?; \
    if [ $$status -ne 0 ]; then \
        echo "$$output"; \
    fi; \
    exit $$status
endef

PROTO_ROOT := .
PROTO_FILES = $(shell find temporal -name "*.proto")
PROTO_DIRS = $(sort $(dir $(PROTO_FILES)))
PROTO_OUT := .gen
PROTO_IMPORTS = \
	-I=$(PROTO_ROOT) \
	-I=$(shell go list -modfile build/go.mod -m -f '{{.Dir}}' github.com/temporalio/gogo-protobuf)/protobuf \
	-I=$(shell go list -modfile build/go.mod -m -f '{{.Dir}}' github.com/grpc-ecosystem/grpc-gateway)/third_party/googleapis

$(PROTO_OUT):
	mkdir $(PROTO_OUT)

##### Compile proto files for go #####
grpc: buf-lint api-linter buf-breaking gogo-grpc fix-path

gogo-grpc: clean $(PROTO_OUT)
	printf $(COLOR) "Compile for gogo-gRPC..."
	$(foreach PROTO_DIR,$(PROTO_DIRS),\
		protoc --fatal_warnings $(PROTO_IMPORTS) \
			--gogoslick_out=Mgoogle/protobuf/any.proto=github.com/gogo/protobuf/types,Mgoogle/protobuf/wrappers.proto=github.com/gogo/protobuf/types,Mgoogle/protobuf/duration.proto=github.com/gogo/protobuf/types,Mgoogle/protobuf/descriptor.proto=github.com/golang/protobuf/protoc-gen-go/descriptor,Mgoogle/protobuf/timestamp.proto=github.com/gogo/protobuf/types,plugins=grpc,paths=source_relative:$(PROTO_OUT) \
			--grpc-gateway_out=allow_patch_feature=false,paths=source_relative:$(PROTO_OUT) \
			--doc_out=html,index.html,source_relative:$(PROTO_OUT) \
		$(PROTO_DIR)*.proto;)

fix-path:
	mv -f $(PROTO_OUT)/temporal/api/* $(PROTO_OUT) && rm -rf $(PROTO_OUT)/temporal

##### Plugins & tools #####
grpc-install: gogo-protobuf-install
	printf $(COLOR) "Install/update gRPC plugins..."
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
	go install github.com/pseudomuto/protoc-gen-doc/cmd/protoc-gen-doc@latest

gogo-protobuf-install: go-protobuf-install
	go install -modfile build/go.mod github.com/temporalio/gogo-protobuf/protoc-gen-gogoslick
	go install -modfile build/go.mod github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway

go-protobuf-install:
	go install github.com/golang/protobuf/protoc-gen-go@v1.5.2

api-linter-install:
	printf $(COLOR) "Install/update api-linter..."
	go install github.com/googleapis/api-linter/cmd/api-linter@v1.32.3

buf-install:
	printf $(COLOR) "Install/update buf..."
	go install github.com/bufbuild/buf/cmd/buf@v1.6.0

##### Linters #####
api-linter:
	printf $(COLOR) "Run api-linter..."
	$(call silent_exec, api-linter --set-exit-status $(PROTO_IMPORTS) --config $(PROTO_ROOT)/api-linter.yaml $(PROTO_FILES))

buf-lint:
	printf $(COLOR) "Run buf linter..."
	(cd $(PROTO_ROOT) && buf lint)

buf-breaking:
	@printf $(COLOR) "Run buf breaking changes check against master branch..."	
	@(cd $(PROTO_ROOT) && buf breaking --against '.git#branch=master')

##### Clean #####
clean:
	printf $(COLOR) "Delete generated go files..."
	rm -rf $(PROTO_OUT)
