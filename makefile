include utils/meta.mk utils/help.mk

SHELL := /bin/bash
BLUE   := $(shell tput -Txterm setaf 6)
RESET  := $(shell tput -Txterm sgr0)

K8S_BUILD_DIR ?= ./build_k8s
K8S_FILES := $(shell find ./kubernetes -name '*.yaml' | sed 's:./kubernetes/::g')

run:
	make -B postgres
	make -B wallet
	make -B hapi
	make -B hasura
	make -B -j 3 hapi-logs hasura-cli

postgres:
	@docker-compose stop postgres
	@docker-compose up -d --build postgres
	@echo "done postgres"

wallet:
	@docker-compose stop wallet
	@docker-compose up -d --build wallet
	@echo "done wallet"

hapi:
	@docker-compose stop hapi
	@docker-compose up -d --build hapi
	@echo "done hapi"

hapi-logs:
	@docker-compose logs -f hapi

hasura:
	$(eval -include .env)
	@until \
		docker-compose exec -T postgres pg_isready; \
		do echo "$(BLUE)hasura |$(RESET) waiting for postgres service"; \
		sleep 5; done;
	@until \
		curl -s -o /dev/null -w 'hapi status %{http_code}\n' http://localhost:9090/healthz; \
		do echo "$(BLUE)hasura |$(RESET) waiting for hapi service"; \
		sleep 5; done;
	@docker-compose stop hasura
	@docker-compose up -d --build hasura
	@echo "done hasura"

hasura-cli:
	$(eval -include .env)
	@until \
		curl -s -o /dev/null -w 'hasura status %{http_code}\n' http://localhost:8080/healthz; \
		do echo "$(BLUE)hasura |$(RESET) waiting for hasura service"; \
		sleep 5; done;
	@cd hasura && hasura seeds apply --admin-secret $(HASURA_GRAPHQL_ADMIN_SECRET) && echo "success!" || echo "failure!";
	@cd hasura && hasura console --endpoint http://localhost:8080 --skip-update-check --no-browser --admin-secret $(HASURA_GRAPHQL_ADMIN_SECRET);

stop:
	@docker-compose stop

install: ##@local Install hapi dependencies
install:
	@cd ./hapi && yarn

clean:
	@docker-compose stop
	@rm -rf tmp/db_data
	@rm -rf tmp/hapi
	@rm -rf hapi/node_modules
	@rm -rf tmp/wallet
	@docker system prune

build-kubernetes: ##@devops Generate proper k8s files based on the templates
build-kubernetes: ./kubernetes
	@echo "Build kubernetes files..."
	@rm -Rf $(K8S_BUILD_DIR) && mkdir -p $(K8S_BUILD_DIR)
	@for file in $(K8S_FILES); do \
		mkdir -p `dirname "$(K8S_BUILD_DIR)/$$file"`; \
		$(SHELL_EXPORT) envsubst <./kubernetes/$$file >$(K8S_BUILD_DIR)/$$file; \
	done

deploy-kubernetes: ##@devops Publish the build k8s files
deploy-kubernetes: $(K8S_BUILD_DIR)
	@kubectl create ns $(NAMESPACE) || echo "Namespace '$(NAMESPACE)' already exists.";
	@echo "Creating SSL certificates..."
	@kubectl create secret tls \
		tls-secret \
		--key ./ssl/eosio.cr.priv.key \
		--cert ./ssl/eosio.cr.crt \
		-n $(NAMESPACE)  || echo "SSL cert already configured.";
	@echo "Creating configmaps..."
	@kubectl create configmap -n $(NAMESPACE) \
	wallet-config \
	--from-file wallet/config/ || echo "Wallet configuration already created.";
	@echo "Applying kubernetes files..."
	@for file in $(shell find $(K8S_BUILD_DIR) -name '*.yaml' | sed 's:$(K8S_BUILD_DIR)/::g'); do \
		kubectl apply -f $(K8S_BUILD_DIR)/$$file -n $(NAMESPACE) || echo "${file} Cannot be updated."; \
	done

build-docker-images: ##@devops Build docker images
build-docker-images:
	@echo "Building docker containers..."
	@for dir in $(SUBDIRS); do \
		$(MAKE) build-docker -C $$dir; \
	done

push-docker-images: ##@devops Publish docker images
push-docker-images:
	@echo $(DOCKER_PASSWORD) | docker login \
		--username $(DOCKER_USERNAME) \
		--password-stdin
	for dir in $(SUBDIRS); do \
		$(MAKE) push-image -C $$dir; \
	done
