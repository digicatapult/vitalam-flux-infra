`kubectl port-forward -n keycloak service/keycloak 8080:80`

Default user is `user`
Password can be retrieved with `kubectl -n keycloak get secret keycloak -o jsonpath='{.data.admin-password}' | base64 -d && echo`

`kubectl get services -n keycloak`
Register an account with http://localhost:8080/realms/simple/account/
