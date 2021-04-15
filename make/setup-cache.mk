$(CACHE):
	@echo "creating .cache dir structure..."
	mkdir -p $@
	mkdir -p $(CACHE_BIN)
	mkdir -p $(CACHE_INCLUDE)
	mkdir -p $(CACHE_VERSIONS)
	mkdir -p $(CACHE_NODE_MODULES)
	mkdir -p $(CACHE)/run

$(PROTOC_VERSION_FILE): $(CACHE)
	@echo "installing protoc compiler v$(PROTOC_VERSION) ..."
	rm -f $(PROTOC)
	(cd /tmp; \
	curl -sOL "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${PROTOC_ZIP}"; \
	unzip -oq ${PROTOC_ZIP} -d $(CACHE) bin/protoc; \
	unzip -oq ${PROTOC_ZIP} -d $(CACHE) 'include/*'; \
	rm -f ${PROTOC_ZIP})
	rm -rf "$(dir $@)"
	mkdir -p "$(dir $@)"
	touch $@
$(PROTOC): $(PROTOC_VERSION_FILE)

$(PROTOC_GEN_COSMOS_VERSION_FILE): $(CACHE)
	@echo "installing protoc-gen-cosmos $(PROTOC_GEN_COSMOS_VERSION) ..."
	rm -f $(PROTOC_GEN_COSMOS)
	GOBIN=$(CACHE_BIN) go get github.com/regen-network/cosmos-proto/protoc-gen-gocosmos@$(PROTOC_GEN_COSMOS_VERSION)
	rm -rf "$(dir $@)"
	mkdir -p "$(dir $@)"
	touch $@
$(PROTOC_GEN_COSMOS): $(PROTOC_GEN_COSMOS_VERSION_FILE)

$(GRPC_GATEWAY_VERSION_FILE): $(CACHE)
	@echo "Installing protoc-gen-grpc-gateway v$(GRPC_GATEWAY_VERSION) ..."
	rm -f $(GRPC_GATEWAY)
	curl -o "${CACHE_BIN}/protoc-gen-grpc-gateway" -L \
	"https://github.com/grpc-ecosystem/grpc-gateway/releases/download/v${GRPC_GATEWAY_VERSION}/${GRPC_GATEWAY_BIN}"
	chmod +x "$(CACHE_BIN)/protoc-gen-grpc-gateway"
	rm -rf "$(dir $@)"
	mkdir -p "$(dir $@)"
	touch $@
$(GRPC_GATEWAY): $(GRPC_GATEWAY_VERSION_FILE)

$(STATIK_VERSION_FILE): $(CACHE)
	@echo "Installing statik $(STATIK_VERSION) ..."
	rm -f $(STATIK)
	GOBIN=$(CACHE_BIN) $(GO) install github.com/rakyll/statik@$(STATIK_VERSION)
	rm -rf "$(dir $@)"
	mkdir -p "$(dir $@)"
	touch $@
$(STATIK): $(STATIK_VERSION_FILE)

$(MODVENDOR_VERSION_FILE): $(CACHE)
	@echo "installing modvendor $(MODVENDOR_VERSION) ..."
	rm -f $(MODVENDOR)
	GOBIN=$(CACHE_BIN) $(GO) install github.com/goware/modvendor@$(MODVENDOR_VERSION)
	rm -rf "$(dir $@)"
	mkdir -p "$(dir $@)"
	touch $@
$(MODVENDOR): $(MODVENDOR_VERSION_FILE)

$(GIT_CHGLOG_VERSION_FILE): $(CACHE)
	@echo "installing git-chglog $(GIT_CHGLOG_VERSION) ..."
	rm -f $(GIT_CHGLOG)
	GOBIN=$(CACHE_BIN) go install github.com/git-chglog/git-chglog/cmd/git-chglog@$(GIT_CHGLOG_VERSION)
	rm -rf "$(dir $@)"
	mkdir -p "$(dir $@)"
	touch $@
$(GIT_CHGLOG): $(GIT_CHGLOG_VERSION_FILE)

$(MOCKERY_VERSION_FILE): $(CACHE)
	@echo "installing mockery $(MOCKERY_VERSION) ..."
	rm -f $(MOCKERY)
	GOBIN=$(CACHE_BIN) go install -ldflags '-s -w -X github.com/vektra/mockery/v2/pkg/config.SemVer=$(MOCKERY_VERSION)' github.com/vektra/mockery/v2@v$(MOCKERY_VERSION)
	rm -rf "$(dir $@)"
	mkdir -p "$(dir $@)"
	touch $@
$(MOCKERY): $(MOCKERY_VERSION_FILE)

$(K8S_CODE_GEN_VERSION_FILE): $(CACHE) modvendor
	@echo "installing k8s code-generator $(K8S_CODE_GEN_VERSION) ..."
	rm -f $(K8S_GO_TO_PROTOBUF)
	GOBIN=$(CACHE_BIN) go install $(ROOT_DIR)/vendor/k8s.io/code-generator/...
	rm -rf "$(dir $@)"
	mkdir -p "$(dir $@)"
	touch $@
	chmod +x $(K8S_GENERATE_GROUPS)
$(K8S_GO_TO_PROTOBUF): $(K8S_CODE_GEN_VERSION_FILE)
$(K8S_GENERATE_GROUPS): $(K8S_CODE_GEN_VERSION_FILE)

.PHONY: $(KIND)
$(KIND):
ifeq (, $(shell which $(KIND) 2>/dev/null))
	@echo "installing kind ..."
	$(GO) install sigs.k8s.io/kind
endif

$(SWAGGER_COMBINE): $(CACHE)
ifeq (, $(shell which swagger-combine 2>/dev/null))
	@echo "Installing swagger-combine..."
	npm install swagger-combine --prefix $(CACHE_NODE_MODULES)
else
	@echo "swagger-combine already installed; skipping..."
endif

$(PROTOC_SWAGGER_GEN): $(CACHE)
ifeq (, $(shell which protoc-gen-swagger 2>/dev/null))
	@echo "installing protoc-gen-swagger $(PROTOC_SWAGGER_GEN_VERSION) ..."
	GOBIN=$(CACHE_BIN) $(GO) install github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger@$(PROTOC_SWAGGER_GEN_VERSION)
endif

.PHONY: bla
bla:
	@echo $(SWAGGER_COMBINE)

cache-clean:
	rm -rf $(CACHE)
