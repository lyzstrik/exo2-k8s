@echo off

kubectl apply -f settings/namespaces.yaml
kubectl apply -f settings/networkpolicy.yaml
kubectl apply -f settings/rbac.yaml
kubectl apply -f settings/volumes.yaml

kubectl apply -f web/vuln-web-configmap.yaml
kubectl apply -f web/vuln-web-deployment.yaml
kubectl apply -f web/vuln-web-service.yaml

kubectl apply -f ssh/vuln-ssh-deployment.yaml
kubectl apply -f ssh/vuln-ssh-secret.yaml
kubectl apply -f ssh/vuln-ssh-service.yaml