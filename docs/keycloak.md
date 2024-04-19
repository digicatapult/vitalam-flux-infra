# Keycloak

Authentication in SQNC is managed using [`Keycloak`](https://www.keycloak.org/)

## Admin

After following instructions in [getting-started](./getting-started.md) to start a flux cluster, the admin console for Keycloak is available at http://localhost:3080/auth/.

Default user is `user`
Password is retrieved with `kubectl -n keycloak get secret keycloak -o jsonpath='{.data.admin-password}' | base64 -d && echo`

The Keycloak instance comes with a realm named `simple`, set up to use Keycloak's built-in simple user login/registration. The default client for logging in is http://localhost:3080/auth/realms/simple/account/.

## Verifying against Keycloak's test app

Keycloak provide a web app https://www.keycloak.org/app/ to test authorisation flow is working.

Enter the following details:

```
Keycloak URL: http://localhost:3080/auth/
Realm: simple
Client: account-console
```

Clicking `Save` then `Sign in` should redirect to the `simple` realm sign in/register page. `Register` a new user using any details. After registering, the client should be logged into that user and display `Hello {First name} {Last name}`.
