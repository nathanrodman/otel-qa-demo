CLUSTER   ?= otel-qa
CONTEXT   := k3d-$(CLUSTER)
NAMESPACE := tiny-shop
TAG       := 0.1.0
SERVICES  := frontend orders inventory
KUBECTL   := kubectl --context $(CONTEXT)

.PHONY: up cluster build import deploy restart status logs port-forward smoke down

## up: create the cluster, build + load images, deploy the app
up: cluster build import deploy

## cluster: create a dedicated local k3d cluster (no-op if it exists)
cluster:
	@k3d cluster list $(CLUSTER) >/dev/null 2>&1 || k3d cluster create $(CLUSTER) --agents 1 --wait --kubeconfig-switch-context=true
	@echo "Using kube context: $(CONTEXT)"

## build: build service images locally
build:
	@for s in $(SERVICES); do \
		echo "==> building tiny-shop/$$s:$(TAG)"; \
		docker build -q -t tiny-shop/$$s:$(TAG) services/$$s || exit 1; \
	done

## import: load images into the k3d cluster (no registry needed)
import:
	k3d image import -c $(CLUSTER) $(foreach s,$(SERVICES),tiny-shop/$(s):$(TAG))

## deploy: apply manifests and wait for rollout
deploy:
	$(KUBECTL) apply -f k8s/tiny-shop.yaml
	$(KUBECTL) -n $(NAMESPACE) rollout status deploy --timeout=180s

## restart: restart app pods (e.g. after installing auto-injection, so the webhook mutates them)
restart:
	$(KUBECTL) -n $(NAMESPACE) rollout restart deploy frontend orders inventory
	$(KUBECTL) -n $(NAMESPACE) rollout status deploy --timeout=180s

## status: show pods, their containers/init containers, and any OTEL_* env injected
status:
	@$(KUBECTL) -n $(NAMESPACE) get pods -o wide
	@echo
	@$(KUBECTL) -n $(NAMESPACE) get pods -o custom-columns='POD:.metadata.name,INIT:.spec.initContainers[*].name,CONTAINERS:.spec.containers[*].name'
	@echo
	@for s in $(SERVICES); do \
		echo "--- $$s OTEL_* env"; \
		$(KUBECTL) -n $(NAMESPACE) get pod -l app.kubernetes.io/name=$$s -o jsonpath='{range .items[0].spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E '^(OTEL_|JAVA_TOOL_OPTIONS|NODE_OPTIONS|PYTHONPATH)' || echo "(none)"; \
	done

## logs: tail logs from all app services
logs:
	$(KUBECTL) -n $(NAMESPACE) logs -f -l app.kubernetes.io/part-of=tiny-shop --max-log-requests 10 --prefix

## port-forward: expose the frontend on http://localhost:8080
port-forward:
	$(KUBECTL) -n $(NAMESPACE) port-forward svc/frontend 8080:8080

## smoke: hit the app end-to-end from inside the cluster
smoke:
	$(KUBECTL) -n $(NAMESPACE) run smoke --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
		sh -c 'curl -sf http://frontend:8080/api/products && echo && curl -s -X POST "http://frontend:8080/api/checkout?sku=sku-apple&qty=1" && echo && curl -sf http://frontend:8080/api/orders | head -c 300 && echo'

## down: delete the k3d cluster entirely
down:
	k3d cluster delete $(CLUSTER)
