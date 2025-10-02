# Rancher IPv6-only setup

## Usage:

```sh  
  export AWS_ACCESS_KEY_ID=YOUR_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY=YOUR_SECRET_ACCESS_KEY
  terraform init
  terraform apply -var-file="values.tfvars"
```

## Addition Step after executing:

Please patch the rke2-coredns-rke2-coredns ConfigMap in the kube-system namespace:
kubectl -n kube-system edit cm rke2-coredns-rke2-coredns

Change the line:
  `forward  . /etc/resolv.conf`
to:
  `forward  . 2001:4860:4860::8888`

You can use the following command:

```sh
kubectl -n kube-system get cm rke2-coredns-rke2-coredns -o json  \
| jq '.data.Corefile |= sub("forward\\s+\\.\\s+/etc/resolv\\.conf"; "forward  . 2001:4860:4860::8888")' \
| kubectl apply -f -
```

Coredns will reload the config shortly
Or restart CoreDNS:
`kubectl -n kube-system delete pod -l k8s-app=kube-dns`

