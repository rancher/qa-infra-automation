user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Kubernetes API upstream
    upstream k8s-api {
        least_conn;
%{ for server in backend_servers ~}
%{ if server.port == 6443 ~}
        server ${server.ip}:${server.port} max_fails=3 fail_timeout=30s;
%{ endif ~}
%{ endfor ~}
    }

    # HTTP upstream
    upstream http-backend {
        least_conn;
%{ for server in backend_servers ~}
%{ if server.port == 80 ~}
        server ${server.ip}:${server.port} max_fails=3 fail_timeout=30s;
%{ endif ~}
%{ endfor ~}
    }

    # HTTPS upstream  
    upstream https-backend {
        least_conn;
%{ for server in backend_servers ~}
%{ if server.port == 443 ~}
        server ${server.ip}:${server.port} max_fails=3 fail_timeout=30s;
%{ endif ~}
%{ endfor ~}
    }

    # Rancher upstream
    upstream rancher-backend {
        least_conn;
%{ for server in backend_servers ~}
%{ if server.port == 9345 ~}
        server ${server.ip}:${server.port} max_fails=3 fail_timeout=30s;
%{ endif ~}
%{ endfor ~}
    }

%{ for port in frontend_ports ~}
%{ if port == 80 ~}
    # HTTP Server
    server {
        listen ${port};
        location / {
            proxy_pass http://http-backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location ${health_check_path} {
            proxy_pass http://http-backend;
            access_log off;
        }
    }
%{ endif ~}
%{ if port == 443 ~}
    # HTTPS Server (TCP Proxy)
    # Note: For SSL termination, additional SSL certificate configuration needed
    server {
        listen ${port};
        location / {
            proxy_pass https://https-backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
%{ endif ~}
%{ if port == 9345 ~}
    # Rancher Server
    server {
        listen ${port};
        location / {
            proxy_pass http://rancher-backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
%{ endif ~}
%{ endfor ~}
}

stream {
%{ for port in frontend_ports ~}
%{ if port == 6443 ~}
    # Kubernetes API Server (TCP Stream)
    server {
        listen ${port};
        proxy_pass k8s-api;
        proxy_timeout 1s;
        proxy_responses 1;
        error_log /var/log/nginx/k8s_api.log;
    }
%{ endif ~}
%{ endfor ~}
}
