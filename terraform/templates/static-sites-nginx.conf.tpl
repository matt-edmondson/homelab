worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # Logging
    access_log /var/log/nginx/access.log;

%{ for site in sites ~}
    server {
        listen 80;
        server_name ${site.domain};
        root /sites/${site.domain};
        index index.html index.htm;

        location / {
            try_files $uri $uri/ =404;
        }
    }

%{ endfor ~}
    # Default server — health check endpoint and 404 for unknown hosts
    server {
        listen 80 default_server;
        server_name _;

        location /healthz {
            return 200 "ok";
        }

        location / {
            return 404;
        }
    }
}
