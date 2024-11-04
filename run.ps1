$nginxVersion = Get-Content nginx_version.txt

docker stop nginx
docker rm nginx -v
docker volume rm nginx-web 
$volumes = $("nginx-web", "nginx-config", "nginx-logs", "nginx-certs")
foreach ($volume in $volumes) {
    docker volume rm $volume
}
foreach ($volume in $volumes) {
    docker volume create $volume
}

docker create -p 80:80
-p 443:443 `
--name nginx `
-v 'nginx-web:/var/www/:/var/www/'
-v 'nginx-config:/etc/nginx/:/etc/nginx/'
-v 'nginx-logs:/var/log/nginx/:/var/log/nginx/'
-v 'nginx-certs:/etc/ssl/certs:/etc/ssl/certs'
armyguy255a/nginx:$nginxVersion

# Copy Lab/server1.conf to /usr/share/openfore/conf/nginx.xml
# docker cp Lab/server1.conf nginx:/usr/share/nginx/conf/nginx.xml

docker start nginx
