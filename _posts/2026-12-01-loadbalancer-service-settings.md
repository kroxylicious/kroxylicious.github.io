---
layout: post
title: "Kroxylicious operator: configuring LoadBalancer Service options"
date: 2026-12-01 09:00:00 +0000
author: "Aditya Thakur"
author_url: "https://github.com/AdityaThakur1998"
# noinspection YAMLSchemaValidation
categories: blog kroxylicious-operator
tags: [ "kubernetes", "operator", "networking" ]
---

When you expose a virtual cluster outside Kubernetes with a `loadBalancer` `KafkaProxyIngress`, the Kroxylicious operator creates a Kubernetes Service of type `LoadBalancer` in front of the proxy. Until recently, that Service always used the Kubernetes defaults for how traffic reaches the proxy, and the ingress gave you no way to change them.

Kroxylicious 0.25.0 adds two options under `spec.loadBalancer.service`, tracked by [issue #4161](https://github.com/kroxylicious/kroxylicious/issues/4161):

* `externalTrafficPolicy` decides whether the proxy sees the real client's address.
* `allocateLoadBalancerNodePorts` decides whether Kubernetes opens a port on every node that leads to the proxy.

This post explains what each option does, when you'd use it, and how to check its effect on your own cluster. A recorded demo is in the appendix.

## How traffic reaches the proxy

A Service of type `LoadBalancer` is more than a request for a cloud load balancer. By default, Kubernetes also:

* opens a **node port** on every node, a port that forwards to the Service, and
* configures **kube-proxy**, the component on each node that routes Service traffic, to forward whatever arrives to one of the proxy pods.

Many load balancers send traffic to those node ports, and kube-proxy takes it from there. Both new options change part of that path.

## Configuring the options

Both options are optional. Leave them out and the Service keeps the Kubernetes defaults, so upgrading changes nothing:

```yaml
kind: KafkaProxyIngress
apiVersion: kroxylicious.io/v1alpha1
metadata:
  name: load-balancer
  namespace: my-proxy
spec:
  proxyRef:
    name: simple
  loadBalancer:
    bootstrapAddress: "$(virtualClusterName).kafkaproxy.example.com"
    advertisedBrokerAddressPattern: "broker-$(nodeId).$(virtualClusterName).kafkaproxy.example.com"
    service:
      externalTrafficPolicy: Local
      allocateLoadBalancerNodePorts: false
```

The operator copies them onto the LoadBalancer Service it manages. You can see the fields it controls with:

```console
kubectl get service <service-name> -n <namespace> -o yaml \
  | grep -E 'externalTraffic|NodePort|nodePort'
```

## externalTrafficPolicy: who does the proxy see?

With the default policy, `Cluster`, a node that receives traffic can forward it to a proxy pod on any node. To make sure the reply comes back the same way, it replaces the client's address with its own. With `Local`, a node only forwards traffic to a proxy pod on that same node, and the client's address is kept.

![Two panels. With the Cluster policy, a client connects through a node, kube-proxy rewrites the source address, and the Kroxylicious proxy sees the node's address. With the Local policy, kube-proxy forwards the connection unchanged and the proxy sees the client's address.](/assets/blog/images/loadbalancer-service-settings/external-traffic-policy.svg)

The client's address matters for anything in the proxy that records or acts on it: connection logs, audit trails, and filters that make decisions based on where a client connects from. With `Cluster`, all of those see a node's address instead.

To check it on your cluster, look at the source address of a client connection from the proxy's side. With `Cluster` it is an address belonging to the node; with `Local` it is the client's own address.

`Local` has trade-offs:

* A node without a proxy pod has nowhere to send the traffic, so the load balancer has to avoid it. Kubernetes handles that with a health-check port, covered below.
* Traffic is only as evenly spread as the proxy pods are across the nodes.

## allocateLoadBalancerNodePorts: close the side door

By default, Kubernetes opens a node port on every node for each port of a `LoadBalancer` Service. Anyone who can reach a node can connect to that port and reach the proxy without going through the load balancer at all.

Setting `allocateLoadBalancerNodePorts: false` tells Kubernetes not to open those ports. Only use it with a load balancer that doesn't need them, for example one that sends traffic straight to the pod IPs. If your load balancer relies on node ports, turning them off cuts it off from the proxy.

![Two panels. With allocateLoadBalancerNodePorts true, the Kafka client reaches the proxy through the load balancer, and anyone who can reach a node can also connect to the node port, a side door to the proxy. With false, the node port is released and a side door connection is refused, while the load balancer path still works. With Local, the health-check port stays open.](/assets/blog/images/loadbalancer-service-settings/node-ports.svg)

Kubernetes doesn't release node ports that have already been allocated just because the field changes to `false`. When the field changes from unset or `true` to `false` on an existing ingress, the operator clears the node port from the Service, which tells Kubernetes to release it.

To check it on your cluster:

* The Service no longer has a `nodePort` on its ports.
* A connection to any node's address on the old node port is refused.
* Clients going through the load balancer keep working as before.

## The port that stays

With `externalTrafficPolicy: Local`, Kubernetes opens one more port on every node: the `healthCheckNodePort`. kube-proxy answers HTTP requests on it with 200 if that node runs a ready proxy pod and 503 if it doesn't, so the load balancer only sends traffic to nodes that can serve it.

This port comes from a separate allocation that `allocateLoadBalancerNodePorts` doesn't control, so it stays open even when node ports are turned off. To see it:

```console
kubectl get service <service-name> -n <namespace> \
  -o jsonpath='{.spec.healthCheckNodePort}'
curl http://<node-address>:<health-check-port>/healthz
```

The response includes `localEndpoints`, the number of proxy pods on that node. Turning node ports off makes the surface smaller, not zero.

## Recap

| Option | Default | Set to | What changes |
|---|---|---|---|
| `externalTrafficPolicy` | `Cluster` | `Local` | The proxy sees the client's real address. Traffic only goes to nodes running a proxy pod, and a health-check port opens on every node. |
| `allocateLoadBalancerNodePorts` | `true` | `false` | No node port on every node, so clients can't bypass the load balancer. Needs a load balancer that doesn't use node ports. |

Both options are available from Kroxylicious 0.25.0, under `spec.loadBalancer.service` on a `loadBalancer` `KafkaProxyIngress`. See [Configuring LoadBalancer Service settings](https://kroxylicious.io/documentation/0.26.0/html/kroxylicious-operator/#con-kafkaproxyingress-loadbalancer-service-settings-operator) in the operator guide for details.

## Appendix: the recording

The recording shows both options on a single-node minikube cluster, with `minikube tunnel` standing in for a cloud load balancer and a Strimzi-managed Kafka cluster behind the proxy. It opens with a short overview, then switches to a two-terminal layout: the left terminal changes the ingress and inspects the Service and the proxy, and the right terminal runs a test client that connects straight to a node port.

{% comment %} Replace VIDEO_ID with the YouTube video ID once the recording is uploaded. {% endcomment %}
<iframe width="720" height="405" src="https://www.youtube-nocookie.com/embed/VIDEO_ID" title="Kroxylicious LoadBalancer Service options" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
