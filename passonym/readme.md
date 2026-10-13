# Passonym

Authentication system for a anonymous yet controlled social media platform (eg. lemmy).
Users prove their identity via their passport, ZKPassport is used to verify the correctness of a passport document.

Goal: Each user/passport can only have one account but its not possible to trace a user back to his real personal identity or to trace a real person to their user account.

Two servers are used seperately to never have all data in a single place. The user device / frontend is the only bridge of communication between them.

## Identity Server

Only used for the initial authentication / register process and to avoid duplicated user accounts. It verifies the identity of a user and creates a unique signed short lived token for the user to authenticate on the platform server.

- provides backend for ZKPassport
- creates Postgres Identity DB to store passport ids of authenticated users
- creates register tokens

## Frontend (on user device)

Initalizes of authenticating by triggering the passport verification. After getting the token from the backend it uses the token + a locally generated signature to authenticate at the platform server. The token is only needed for the inital register process. After a succesfull register, the signature is enough for the platform server to verify the authenticity of the user.

- provides frontend for ZKPassport (query token)
- provides secondary device register
- transfers token to platform server
- triggers signature key rotation (excluded in MVP)

## Platform Server

Manages the anonymous user which can be used on the social media platform. Therefore it must never see any of the personal identity data from the real user. For registering it gets the token from the identity server as a proof that the user has no account yet and inserts the signature with a newly generated user id into the user table. It also saves the token in a db to ensure it cant be used anymore.

For loggin in, it simply checks if the signature of the user is valid and matches the ID with the signature.

- validates register token
- creates Postgres Platform DB to store 2 tables
  - User: user ids of authenticated users with their signatures (pub keys)
  - Tokens: used register tokens
