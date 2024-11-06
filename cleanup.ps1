docker system prune -a --volumes -f
docker volume rm $(docker volume ls -q)
