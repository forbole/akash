#ROOT_DIR              := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../)

GO                    := GO111MODULE=on go

#CACHE_BASE            := $(CACHE_BASE)
#CACHE                 := $(CACHE_BASE)
#CACHE_BIN             := $(CACHE)/bin
#CACHE_INCLUDE         := $(CACHE)/include
#CACHE_VERSIONS        := $(CACHE)/versions
#CACHE_NODE_MODULES    := $(CACHE)/node_modules
#CACHE_NODE_BIN        := $(CACHE_NODE_MODULES)/.bin

include $(ROOT_DIR)/.makerc

# setup .cache bins first in paths to have precedence over already installed same tools for system wide use
PATH                       := "$(PATH):$(CACHE_BIN):$(CACHE_NODE_BIN)"

BUF_VERSION                ?= 0.35.1
PROTOC_VERSION             ?= 3.13.0
PROTOC_GEN_COSMOS_VERSION  ?= v0.3.1
GRPC_GATEWAY_VERSION       := $(shell $(GO) list -mod=readonly -m -f '{{ .Version }}' github.com/grpc-ecosystem/grpc-gateway)
PROTOC_SWAGGER_GEN_VERSION := $(GRPC_GATEWAY_VERSION)
GOLANGCI_LINT_VERSION      ?= v1.38.0
GOLANG_VERSION             ?= 1.16.1
GOLANG_CROSS_VERSION       := v$(GOLANG_VERSION)
STATIK_VERSION             ?= v0.1.7
GIT_CHGLOG_VERSION         ?= v0.10.0
MODVENDOR_VERSION          ?= v0.3.0
MOCKERY_VERSION            ?= 2.5.1
K8S_CODE_GEN_VERSION       ?= v0.19.3

# <TOOL>_VERSION_FILE points to the marker file for the installed version.
# If <TOOL>_VERSION_FILE is changed, the binary will be re-downloaded.
PROTOC_VERSION_FILE             = $(CACHE_VERSIONS)/protoc/$(PROTOC_VERSION)
GRPC_GATEWAY_VERSION_FILE       = $(CACHE_VERSIONS)/protoc-gen-grpc-gateway/$(GRPC_GATEWAY_VERSION)
PROTOC_GEN_COSMOS_VERSION_FILE  = $(CACHE_VERSIONS)/protoc-gen-cosmos/$(PROTOC_GEN_COSMOS_VERSION)
STATIK_VERSION_FILE             = $(CACHE_VERSIONS)/statik/$(STATIK_VERSION)
MODVENDOR_VERSION_FILE          = $(CACHE_VERSIONS)/modvendor/$(MODVENDOR_VERSION)
GIT_CHGLOG_VERSION_FILE         = $(CACHE_VERSIONS)/git-chglog/$(GIT_CHGLOG_VERSION)
MOCKERY_VERSION_FILE            = $(CACHE_VERSIONS)/mockery/v$(MOCKERY_VERSION)
K8S_CODE_GEN_VERSION_FILE       = $(CACHE_VERSIONS)/k8s-codegen/$(K8S_CODE_GEN_VERSION)

MODVENDOR                       = $(CACHE_BIN)/modvendor
SWAGGER_COMBINE                 = $(CACHE_NODE_BIN)/swagger-combine
PROTOC_SWAGGER_GEN             := $(CACHE_BIN)/protoc-swagger-gen
PROTOC                         := $(CACHE_BIN)/protoc
STATIK                         := $(CACHE_BIN)/statik
PROTOC_GEN_COSMOS              := $(CACHE_BIN)/protoc-gen-cosmos
GRPC_GATEWAY                   := $(CACHE_BIN)/protoc-gen-grpc-gateway
GIT_CHGLOG                     := $(CACHE_BIN)/git-chglog
MOCKERY                        := $(CACHE_BIN)/mockery
K8S_GENERATE_GROUPS            := $(ROOT_DIR)/vendor/k8s.io/code-generator/generate-groups.sh
K8S_GO_TO_PROTOBUF             := $(CACHE_BIN)/go-to-protobuf
KIND                           := kind

include $(ROOT_DIR)/make/setup-cache.mk
