# Reset and Redeploy: Compose, Swarm, Kubernetes

This file contains safe, repeatable commands to *remove all runtime state* for the three deployments in this repository (Docker Compose, Docker Swarm, Kubernetes) and then redeploy them from the repository manifests. Images will NOT be deleted.

Run the commands from the repository root: `d:\University\Epi\Sem3\Cloud\Project`.

---

## 1) Stop & remove Docker Compose (no images removed)

Stop and remove containers created by the Compose files and the compose networks/volumes:

```bash
# Stop and remove compose containers for the normal compose file
docker-compose -f docker-compose_noramlWihtoutSworm.yml down

# If you created the temporary incremented-ports compose file, remove it too
if [ -f docker-compose-ports.yml ]; then
  docker-compose -f docker-compose-ports.yml down
fi

# Remove unnamed (dangling) volumes created by compose
docker volume ls -qf dangling=true | xargs -r docker volume rm
```

Notes:
- `docker-compose down` by default removes containers, networks created by that compose file and anonymous volumes; it does NOT remove images.
- If you previously used `docker-compose -f docker-compose-ports.yml up -d`, run `docker-compose -f docker-compose-ports.yml down` as above.

---

## 2) Remove Docker Swarm stack (services, networks) — preserve images

```bash
# Remove the swarm stack
docker stack rm CloudProject

# Wait a few seconds, then remove project overlay networks if any remain
docker network ls | egrep "(CloudProject|project)_?frontend|backend" || true
# Remove specific networks if they remain (careful: only those created for this project)
docker network rm CloudProject_frontend CloudProject_backend || true
```

Do NOT run `docker image rm` in these steps; images are preserved.

---

## 3) Remove project Docker volumes (named volumes used by the project)

List volumes and remove only those that belong to the project (example names used in this repo): `db_data`, `wp_data`, `prometheus_data`, and compose variants `*_compose`.

```bash
# Inspect and remove project volumes (will delete persisted database and grafana data)
docker volume ls --format '{{.Name}}' | grep -E 'db_data|wp_data|prometheus_data|_compose' || true
# Remove them explicitly (only run if you want the data gone):
docker volume rm db_data wp_data prometheus_data project_db_data_compose project_wp_data_compose project_prometheus_data_compose 2>/dev/null || true
```

Warning: removing these volumes will irreversibly delete database and dashboard data.

---

## 4) Prune unused Docker networks (safe for cleaning overlay state)

```bash
# This removes unused networks only (won't remove images/containers)
docker network prune -f
```

This clears leftover overlay networks that caused pool overlap issues previously.

---

## 5) Delete Kubernetes resources for `wp` namespace (k8s)

You can either delete the whole `wp` namespace (fast) or delete individual manifests. Deleting the namespace removes all resources created under it (Deployments, Services, ConfigMaps, PVCs). Images remain in your cluster/node image cache.

```bash
# Option A: Delete the namespace (recommended for a full reset)
kubectl delete namespace wp --ignore-not-found=true

# Option B: Delete individual manifests (use if you prefer selective removal)
# Example:
kubectl delete -f k8s/grafana-deployment.yaml -f k8s/prometheus-deployment.yaml -f k8s/nginx-deployment.yaml -f k8s/mysqld-exporter-deployment.yaml -f k8s/nginx-exporter-deployment.yaml -f k8s/node-exporter-daemonset.yaml -f k8s/mysql-deployment.yaml -f k8s/wordpress-deployment.yaml --ignore-not-found=true
```

Wait until the namespace terminates completely before re-creating (check with `kubectl get ns`).

---

## 6) Optional Docker system cleanup (volumes/networks only)

If you want to further clean dangling objects (no images):

```bash
# Remove dangling volumes
docker volume prune -f
# Remove stopped containers
docker container prune -f
```

Do NOT run `docker system prune --all` if you want to keep images.

---

## 7) Redeploy Docker Swarm stack

After the Swarm cleanup is complete, redeploy the stack from `docker-compose.yml`:

```bash
# Recreate the overlay networks and services
docker stack deploy -c docker-compose.yml CloudProject
# Check status
docker service ls
```

If you previously saw network pool overlap errors, ensure `docker network prune` completed and no other overlay networks conflict.

---

## 8) Start Docker Compose (non-Swarm) side-by-side

Use the normal compose file (without Swarm deploy sections) to run the Compose stack on different host ports so it doesn't collide with Swarm services. Example used previously:

```bash
# Start compose (scale wordpress to 3 if desired)
docker-compose -f docker-compose_noramlWihtoutSworm.yml up -d --scale wordpress=3
# Check containers
docker ps --filter "name=project-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Notes:
- Compose exposes ports based on the `ports:` lines in the compose file; ensure they do not collide with the Swarm host ports (we used +1 ports in previous run).

---

## 9) Apply Kubernetes manifests (re-create namespace and resources)

If you deleted the `wp` namespace, recreate it and apply manifests following the recommended order in `k8s/DEPLOYMENT.md`:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/persistentvolume.yaml
kubectl apply -f k8s/persistentvolumeclaim.yaml
# ConfigMaps and init
kubectl apply -f k8s/mysql-init-configmap.yaml
kubectl apply -f k8s/nginx-configmap.yaml
kubectl apply -f k8s/prometheus-configmap.yaml
kubectl apply -f k8s/grafana-configmaps.yaml
# Deploy DB and app
kubectl apply -f k8s/mysql-deployment.yaml
kubectl apply -f k8s/mysql-service.yaml
kubectl apply -f k8s/wordpress-deployment.yaml
kubectl apply -f k8s/wordpress-service.yaml
# Reverse proxy and exporters
kubectl apply -f k8s/nginx-deployment.yaml
kubectl apply -f k8s/node-exporter-daemonset.yaml
kubectl apply -f k8s/mysqld-exporter-deployment.yaml
kubectl apply -f k8s/nginx-exporter-deployment.yaml
# Monitoring
kubectl apply -f k8s/prometheus-deployment.yaml
kubectl apply -f k8s/grafana-deployment.yaml
```

Verify:

```bash
kubectl get all -n wp
kubectl get pvc -n wp
```

---

## 10) Verify everything is healthy

- Docker Swarm: `docker service ls` and `docker service ps <service>`
- Docker Compose: `docker ps` and `docker logs <container>`
- Kubernetes: `kubectl get pods -n wp` and `kubectl describe pod <pod> -n wp`
- Prometheus targets: `http://localhost:9090` (Swarm) and `http://localhost:9091` (Compose) depending on your ports
- Grafana: `http://localhost:3000` (Swarm) and `http://localhost:3001` (Compose) or Minikube NodePort for k8s

---

## 11) Troubleshooting notes

- If you get network `invalid pool request: Pool overlaps` errors in Swarm, run `docker network prune -f` and ensure no other overlay networks exist with conflicting subnets.
- If Grafana dashboards do not provision, ensure the dashboards are mounted at `/var/lib/grafana/dashboards` and datasource provisioning file matches the datasource name/UID used by dashboards.
- Do not remove Docker images unless you intentionally want to free space. Images are preserved by the steps above.

---

If you want, I can now execute these steps for you (or a subset). Tell me which steps you want automated: full reset + redeploy, or only reset containers for a single environment (Compose/Swarm/K8s).