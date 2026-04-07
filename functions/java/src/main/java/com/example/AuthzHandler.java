package com.example;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.GetItemResponse;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.List;
import java.util.Map;

/**
 * Mock JWT-validation + permissions-lookup function.
 *
 * On each invocation the handler:
 *   1. Validates the JWT structure and runs a small SHA-256 loop to simulate
 *      HMAC verification work (~5 ms of CPU).
 *   2. Looks up the JWT subject in a DynamoDB permissions table, which
 *      produces a child span when OTel instrumentation is active.
 *   3. Pads total processing time to ~25 ms to simulate consistent authz
 *      latency regardless of memory tier or instance type.
 *
 * DynamoDB client injection
 * ─────────────────────────
 * The default (no-arg) constructor creates a plain DynamoDbClient. For
 * agent-based configs (c02–c15, c19) the Java agent instruments it
 * automatically via bytecode injection.
 *
 * AuthzHandlerProgSdk (c16/c17) passes in a client that has been wired with
 * the OTel AWS SDK v2 execution interceptor so that child spans are emitted
 * even without the agent.
 *
 * All 19 benchmark configurations share this JAR. Instrumentation is
 * controlled entirely via environment variables and Lambda layers.
 */
public class AuthzHandler implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String TABLE_NAME = System.getenv("PERMISSIONS_TABLE_NAME");

    // Set to false after the first invocation so k6 can detect cold starts
    // from the response body without needing CloudWatch access.
    private static volatile boolean coldStart = true;

    private final DynamoDbClient dynamoDb;

    // Default constructor — used by agent-based configs.
    // The Java agent instruments DynamoDbClient automatically.
    public AuthzHandler() {
        this.dynamoDb = (TABLE_NAME != null && !TABLE_NAME.isBlank())
                ? DynamoDbClient.create()
                : null;
    }

    // Package-private — used by AuthzHandlerProgSdk to inject an OTel-instrumented client.
    AuthzHandler(DynamoDbClient dynamoDb) {
        this.dynamoDb = dynamoDb;
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent event, Context context) {
        boolean isColdStart = coldStart;
        coldStart = false;

        long startMs = System.currentTimeMillis();

        String token = extractToken(event.getBody());
        boolean tokenValid = validateToken(token);
        String subject = extractSubject(token);

        // Permissions lookup — produces a DynamoDB child span when instrumented.
        List<String> roles = lookupPermissions(subject);

        // Authorized if the token is structurally valid and DynamoDB confirms
        // the subject is active. Falls back to token-only when DynamoDB is not
        // configured (dynamoDb == null).
        boolean authorized = tokenValid && (dynamoDb == null || !roles.isEmpty());

        // Pad to ~25 ms total to simulate consistent authz latency.
        long elapsed = System.currentTimeMillis() - startMs;
        if (elapsed < 25) {
            try {
                Thread.sleep(25 - elapsed);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }

        long totalMs = System.currentTimeMillis() - startMs;

        ObjectNode body = MAPPER.createObjectNode()
                .put("authorized", authorized)
                .put("subject", subject)
                .put("coldStart", isColdStart)
                .put("processingTimeMs", totalMs);
        body.set("roles", MAPPER.valueToTree(roles));

        try {
            return APIGatewayV2HTTPResponse.builder()
                    .withStatusCode(authorized ? 200 : 403)
                    .withHeaders(Map.of("Content-Type", "application/json"))
                    .withBody(MAPPER.writeValueAsString(body))
                    .build();
        } catch (Exception e) {
            return APIGatewayV2HTTPResponse.builder()
                    .withStatusCode(500)
                    .withBody("{\"error\":\"internal\"}")
                    .build();
        }
    }

    /**
     * Looks up the subject's roles and active status in DynamoDB.
     * Returns an empty list if the subject is not found, is inactive,
     * or if DynamoDB is not configured.
     */
    private List<String> lookupPermissions(String subject) {
        if (dynamoDb == null || subject == null || "unknown".equals(subject)) {
            return List.of();
        }
        try {
            GetItemResponse resp = dynamoDb.getItem(r -> r
                    .tableName(TABLE_NAME)
                    .key(Map.of("subject", AttributeValue.fromS(subject))));

            if (!resp.hasItem()) return List.of();

            Map<String, AttributeValue> item = resp.item();
            AttributeValue isActive = item.get("is_active");
            if (isActive == null || !Boolean.TRUE.equals(isActive.bool())) return List.of();

            AttributeValue rolesAttr = item.get("roles");
            return rolesAttr != null ? rolesAttr.ss() : List.of();
        } catch (Exception e) {
            return List.of();
        }
    }

    private String extractToken(String requestBody) {
        if (requestBody == null || requestBody.isBlank()) {
            return defaultToken();
        }
        try {
            Map<?, ?> parsed = MAPPER.readValue(requestBody, Map.class);
            Object token = parsed.get("token");
            return token != null ? token.toString() : defaultToken();
        } catch (Exception e) {
            return defaultToken();
        }
    }

    // Header: {"alg":"HS256","typ":"JWT"}  Payload: {"sub":"bench-user","iat":1700000000,"exp":9999999999}
    private String defaultToken() {
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
                + ".eyJzdWIiOiJiZW5jaC11c2VyIiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjk5OTk5OTk5OTl9"
                + ".mock-signature-not-verified";
    }

    /**
     * Simulates real authz work: decode the JWT payload, run a SHA-256 loop to
     * mimic HMAC verification, and do a simple policy check.
     */
    private boolean validateToken(String token) {
        if (token == null || token.isEmpty()) return false;
        String[] parts = token.split("\\.", -1);
        if (parts.length != 3) return false;

        try {
            byte[] payloadBytes = Base64.getUrlDecoder().decode(padBase64(parts[1]));
            String payload = new String(payloadBytes, StandardCharsets.UTF_8);
            if (!payload.contains("\"sub\"")) return false;

            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] signingInput = (parts[0] + "." + parts[1]).getBytes(StandardCharsets.UTF_8);
            byte[] secret = "benchmark-secret-key-32-bytes!!".getBytes(StandardCharsets.UTF_8);

            digest.update(secret);
            digest.update(signingInput);
            byte[] hash = digest.digest();

            for (int i = 0; i < 50; i++) {
                digest.reset();
                digest.update(hash);
                hash = digest.digest();
            }

            return hash.length == 32;
        } catch (Exception e) {
            return false;
        }
    }

    private String extractSubject(String token) {
        try {
            String[] parts = token.split("\\.", -1);
            byte[] payloadBytes = Base64.getUrlDecoder().decode(padBase64(parts[1]));
            Map<?, ?> claims = MAPPER.readValue(payloadBytes, Map.class);
            Object sub = claims.get("sub");
            return sub != null ? sub.toString() : "unknown";
        } catch (Exception e) {
            return "unknown";
        }
    }

    private static String padBase64(String s) {
        return switch (s.length() % 4) {
            case 2 -> s + "==";
            case 3 -> s + "=";
            default -> s;
        };
    }
}
