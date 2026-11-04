package com.idira.samples.lambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.cyberark.conjur.api.Conjur;
import com.cyberark.conjur.api.Token;
import com.cyberark.conjur.api.clients.AWSIAMAuthenticator;
import jakarta.ws.rs.client.ClientBuilder;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Authenticates to Secrets Manager with the function's IAM role and fetches one secret.
 * The response reports the secret's length only, so the value never reaches a caller or the logs.
 */
public class SecretHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final int TOKEN_REFRESH_MARGIN_SECONDS = 60;

    // Survives across warm invocations of the same execution environment.
    private static Token cachedToken;

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {
        boolean tokenReused = cachedToken != null && !cachedToken.willExpireWithin(TOKEN_REFRESH_MARGIN_SECONDS);
        if (!tokenReused) {
            cachedToken = authenticate();
        }

        String secretId = requireEnv("SECRET_ID");
        String secret = new Conjur(cachedToken).variables().retrieveSecret(secretId);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("secretId", secretId);
        response.put("secretLength", secret.length());
        response.put("tokenReused", tokenReused);
        response.put("tokenExpires", cachedToken.getExpiration().toString());
        return response;
    }

    private static Token authenticate() {
        // The 3-argument constructor hardcodes authn-iam/prod and us-east-1, so set both explicitly.
        try (AWSIAMAuthenticator authenticator = new AWSIAMAuthenticator(
                ClientBuilder.newClient(),
                requireEnv("CONJUR_APPLIANCE_URL"),
                requireEnv("CONJUR_ACCOUNT"),
                requireEnv("CONJUR_HOST_ID"),
                "authn-iam/" + requireEnv("CONJUR_AUTHN_IAM_SERVICE_ID"),
                requireEnv("AWS_REGION"))) {
            return authenticator.authenticate();
        }
    }

    private static String requireEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing environment variable: " + name);
        }
        return value;
    }
}
