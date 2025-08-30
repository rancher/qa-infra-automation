global
    log         127.0.0.1 local0
    chroot      /var/lib/haproxy
    stats       socket /var/run/haproxy/admin.sock mode 660 level admin
    stats       timeout 30s
    user        haproxy
    group       haproxy
    daemon

defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option                  http-server-close
    option                  forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

# Stats page
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

# Kubernetes API Server
%{ for port in frontend_ports ~}
%{ if port == 6443 ~}
frontend k8s-api
    bind *:${port}
    mode tcp
    default_backend k8s-api-servers

backend k8s-api-servers
    mode tcp
    balance roundrobin
    option tcp-check
%{ for server in backend_servers ~}
%{ if server.port == 6443 ~}
    server k8s-${index(backend_servers, server)} ${server.ip}:${server.port} check
%{ endif ~}
%{ endfor ~}

%{ endif ~}
%{ if port == 80 ~}
# HTTP Frontend
frontend http-frontend
    bind *:${port}
    mode http
    default_backend http-servers

backend http-servers
    mode http
    balance roundrobin
    option httpchk GET ${health_check_path}
%{ for server in backend_servers ~}
%{ if server.port == 80 ~}
    server http-${index(backend_servers, server)} ${server.ip}:${server.port} check
%{ endif ~}
%{ endfor ~}

%{ endif ~}
%{ if port == 443 ~}
# HTTPS Frontend
frontend https-frontend
    bind *:${port}
    mode tcp
    default_backend https-servers

backend https-servers
    mode tcp
    balance roundrobin
    option tcp-check
%{ for server in backend_servers ~}
%{ if server.port == 443 ~}
    server https-${index(backend_servers, server)} ${server.ip}:${server.port} check
%{ endif ~}
%{ endfor ~}

%{ endif ~}
%{ if port == 9345 ~}
# Rancher Server Frontend  
frontend rancher-frontend
    bind *:${port}
    mode tcp
    default_backend rancher-servers

backend rancher-servers
    mode tcp
    balance roundrobin
    option tcp-check
%{ for server in backend_servers ~}
%{ if server.port == 9345 ~}
    server rancher-${index(backend_servers, server)} ${server.ip}:${server.port} check
%{ endif ~}
%{ endfor ~}

%{ endif ~}
%{ endfor ~}
