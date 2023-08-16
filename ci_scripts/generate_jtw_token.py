#!/usr/bin/env python3

import os, sys, time
from joserfc import jwt
from joserfc.jwk import ECKey

def generate_jwt_token(key_id, issuer_id, secret):
	header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
	issued_at_time = int(time.time())
	expiration_time = issued_at_time + 2*600
	payload = {"iss": issuer_id, "iat": issued_at_time, "exp": expiration_time, "aud": "appstoreconnect-v1"}
	secret = secret[:27] + secret[27:-25].replace(" ", "\n") + secret[-25:]
	key = ECKey.import_key(secret)
	token = jwt.encode(header, payload, key)
	return f"{token}"

if __name__ == "__main__":
    key_id = os.environ.get("app_store_connect_key_id")
    issuer_id = os.environ.get("app_store_connect_issuer_id")
    secret = os.environ.get("app_store_connect_api_key")
    if key_id is None or issuer_id is None or secret is None:
        print("Error: One or more arguments are missing", file=sys.stderr)
        sys.exit(1)
    elif secret[:27] != "-----BEGIN PRIVATE KEY-----" or secret[-25:] != "-----END PRIVATE KEY-----":    	
        print("Error: secret not in PEM format", file=sys.stderr)
        sys.exit(2)

    result = generate_jwt_token(key_id, issuer_id, secret)
    print(result)