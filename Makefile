build:; docker-compose build
up:;    docker-compose up -d
down:;  docker-compose down
logs:;  docker-compose logs -f
swarm:; docker stack deploy -c docker-compose.yml CloudProject
k8s:;  kubectl apply -f k8s/
clean:; docker-compose down -v; docker stack rm CloudProject 2>/dev/null || true; kubectl delete -f k8s/ --grace-period=0 --force