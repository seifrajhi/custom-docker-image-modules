nginx_version ?= stable

DOCKER ?= docker
DOCKER_BUILD_OPTS ?=

.PHONY: all
all:
	flavors=$$(jq -er '.flavors[].name' flavors.json) && \
	for f in $$flavors; do make flavor=$$f image; done

.PHONY: check-required-vars
check-required-vars:
ifndef flavor
	$(error 'You must defined the flavor variable')
endif

ifndef nginx_version
	$(error 'You must define the nginx_version variable')
endif

.PHONY: image
image: check-required-vars
	modules=$$(jq -er '.flavors[] | select(.name == "$(flavor)") | .modules | join(",")' flavors.json) && \
	lua_modules=$$(jq -er '.flavors[] | select(.name == "$(flavor)") | [ .lua_modules[]? ] | join(",")' flavors.json) && \
	$(DOCKER) build $(DOCKER_BUILD_OPTS) \
		--build-arg nginx_version=$(nginx_version) \
		--build-arg modules="$$modules" \
		--build-arg lua_modules="$$lua_modules" \
		-t rajhisaifeddine/nginx-$(flavor):$(nginx_version) .

.PHONY: test
test: check-required-vars
	$(DOCKER) rm -f test-tsuru-nginx-$(flavor)-$(nginx_version) || true
	$(DOCKER) create --name test-tsuru-nginx-$(flavor)-$(nginx_version) tsuru/nginx-$(flavor):$(nginx_version) bash -c " \
	openssl req -x509 -newkey rsa:4096 -nodes -subj '/CN=localhost' -keyout /etc/nginx/key.pem -out /etc/nginx/cert.pem -days 365; \
	nginx -c /etc/nginx/nginx-$(flavor).conf" \

	$(DOCKER) cp ./test/nginx-$(flavor).conf test-tsuru-nginx-$(flavor)-$(nginx_version):/etc/nginx/
	$(DOCKER) cp $$PWD/test/GeoIP2-Country-Test.mmdb test-tsuru-nginx-$(flavor)-$(nginx_version):/etc/nginx; \

	$(DOCKER) start test-tsuru-nginx-$(flavor)-$(nginx_version) && sleep 3

	@if [ "$$($(DOCKER) exec test-tsuru-nginx-$(flavor)-$(nginx_version) curl -fsSL http://localhost:8080)" != "nginx config check ok" ]; then \
		echo 'FAIL' >&2; \
		$(DOCKER) logs test-tsuru-nginx-$(flavor)-$(nginx_version); \
		exit 1; \
	else \
		echo 'SUCCESS'; \
	fi
